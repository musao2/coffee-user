-- =====================================================================
--  COFFEEGRAM — Kofexonalar uchun cashback tizimi (Supabase backend)
--  Supabase → SQL Editor → shu faylni to'liq joylashtirib "Run" bosing.
--  Qayta ishga tushirsa ham xavfsiz (idempotent).
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. JADVALLAR
-- ---------------------------------------------------------------------

-- Kofexonalar (filiallar)
create table if not exists public.cafes (
  id               uuid primary key default gen_random_uuid(),
  name             text not null,
  address          text,
  cashback_percent numeric(5,2) not null default 5 check (cashback_percent >= 0 and cashback_percent <= 50),
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

-- Foydalanuvchilar profili (mijoz yoki kassir). auth.users bilan 1:1
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  phone      text unique,
  full_name  text not null default '',
  role       text not null default 'customer' check (role in ('customer', 'cashier')),
  cafe_id    uuid references public.cafes(id) on delete set null,
  balance    bigint not null default 0 check (balance >= 0),
  created_at timestamptz not null default now()
);

-- Tranzaksiyalar (har biri = bitta bir martalik QR kod)
create table if not exists public.transactions (
  id              uuid primary key default gen_random_uuid(),
  token           text not null unique,                       -- QR ichidagi maxfiy token
  type            text not null check (type in ('cashback', 'spend')),
  amount          bigint not null check (amount > 0),          -- chek summasi
  cashback_amount bigint not null default 0,                   -- mijozga tushadigan bonus
  balance_used    bigint not null default 0,                   -- balansdan yechilgan summa
  user_id         uuid references public.profiles(id) on delete set null,
  cafe_id         uuid not null references public.cafes(id) on delete cascade,
  cashier_id      uuid not null references public.profiles(id) on delete cascade,
  status          text not null default 'pending' check (status in ('pending', 'confirmed', 'expired', 'cancelled')),
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  confirmed_at    timestamptz
);

create index if not exists transactions_user_idx    on public.transactions (user_id, confirmed_at desc);
create index if not exists transactions_cafe_idx    on public.transactions (cafe_id, confirmed_at desc);
create index if not exists transactions_cashier_idx on public.transactions (cashier_id, status);

-- ---------------------------------------------------------------------
-- 2. YANGI FOYDALANUVCHI → PROFIL (trigger)
--    Rol har doim 'customer'. Kassirni faqat admin SQL orqali tayinlaydi.
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, phone, full_name)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- 3. XAVFSIZLIK (Row Level Security)
--    Jadvallarga to'g'ridan-to'g'ri yozish TAQIQLANGAN.
--    Balans faqat quyidagi funksiyalar orqali o'zgaradi.
-- ---------------------------------------------------------------------
alter table public.cafes        enable row level security;
alter table public.profiles     enable row level security;
alter table public.transactions enable row level security;

-- Joriy kassirning kofexonasi
create or replace function public.my_cafe_id()
returns uuid language sql stable security definer set search_path = public as $$
  select cafe_id from public.profiles where id = auth.uid() and role = 'cashier'
$$;

drop policy if exists "cafes readable" on public.cafes;
create policy "cafes readable" on public.cafes
  for select to authenticated using (true);

drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for select to authenticated using (id = auth.uid());

drop policy if exists "own or cafe transactions" on public.transactions;
create policy "own or cafe transactions" on public.transactions
  for select to authenticated
  using (user_id = auth.uid() or cafe_id = public.my_cafe_id());

-- ---------------------------------------------------------------------
-- 4. BIZNES LOGIKA (RPC funksiyalar)
-- ---------------------------------------------------------------------

-- 4.1 KASSIR: yangi QR yaratish (cashback berish yoki balansdan yechish)
create or replace function public.create_transaction(p_amount bigint, p_type text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me   public.profiles;
  v_cafe public.cafes;
  v_tx   public.transactions;
  v_ttl  int := 90;   -- QR amal qilish muddati (soniya)
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null or v_me.role <> 'cashier' or v_me.cafe_id is null then
    raise exception 'NOT_CASHIER';
  end if;
  if p_type not in ('cashback', 'spend') then raise exception 'BAD_TYPE'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 10000000 then raise exception 'BAD_AMOUNT'; end if;

  select * into v_cafe from public.cafes where id = v_me.cafe_id and is_active;
  if v_cafe.id is null then raise exception 'CAFE_INACTIVE'; end if;

  -- shu kassirning eski ochiq QR'larini bekor qilamiz
  update public.transactions set status = 'cancelled'
   where cashier_id = v_me.id and status = 'pending';

  insert into public.transactions (token, type, amount, cashback_amount, cafe_id, cashier_id, expires_at)
  values (
    encode(gen_random_bytes(24), 'hex'),
    p_type,
    p_amount,
    case when p_type = 'cashback' then floor(p_amount * v_cafe.cashback_percent / 100)::bigint else 0 end,
    v_cafe.id,
    v_me.id,
    now() + make_interval(secs => v_ttl)
  )
  returning * into v_tx;

  return json_build_object(
    'id', v_tx.id,
    'token', v_tx.token,
    'type', v_tx.type,
    'amount', v_tx.amount,
    'cashback_amount', v_tx.cashback_amount,
    'expires_in', v_ttl
  );
end $$;

-- 4.2 MIJOZ: QR skanerlangandan keyin ma'lumotni ko'rish (hali tasdiqlamasdan)
create or replace function public.preview_transaction(p_token text)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_tx   public.transactions;
  v_cafe public.cafes;
  v_bal  bigint;
begin
  if auth.uid() is null then raise exception 'NOT_AUTH'; end if;

  select * into v_tx from public.transactions where token = p_token;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;

  select * into v_cafe from public.cafes where id = v_tx.cafe_id;
  select balance into v_bal from public.profiles where id = auth.uid();

  return json_build_object(
    'type', v_tx.type,
    'amount', v_tx.amount,
    'cashback_amount', v_tx.cashback_amount,
    'cashback_percent', v_cafe.cashback_percent,
    'cafe_name', v_cafe.name,
    'cafe_address', v_cafe.address,
    'status', case when v_tx.status = 'pending' and v_tx.expires_at < now() then 'expired' else v_tx.status end,
    'seconds_left', greatest(0, ceil(extract(epoch from (v_tx.expires_at - now()))))::int,
    'balance', coalesce(v_bal, 0),
    'will_use', least(coalesce(v_bal, 0), v_tx.amount)
  );
end $$;

-- 4.3 MIJOZ: tranzaksiyani tasdiqlash → balans o'zgaradi (atomik)
create or replace function public.confirm_transaction(p_token text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_me      public.profiles;
  v_tx      public.transactions;
  v_used    bigint := 0;
  v_new_bal bigint;
begin
  select * into v_me from public.profiles where id = auth.uid() for update;
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  if v_me.role <> 'customer' then raise exception 'NOT_CUSTOMER'; end if;

  select * into v_tx from public.transactions where token = p_token for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status = 'confirmed' then raise exception 'ALREADY_USED'; end if;
  if v_tx.status = 'cancelled' then raise exception 'CANCELLED'; end if;
  if v_tx.status = 'expired' or v_tx.expires_at < now() then raise exception 'EXPIRED'; end if;

  if v_tx.type = 'cashback' then
    update public.profiles set balance = balance + v_tx.cashback_amount
     where id = v_me.id returning balance into v_new_bal;
  else
    -- balans yetmasa — bor qismi yechiladi, qolganini mijoz naqd/karta bilan to'laydi
    v_used := least(v_me.balance, v_tx.amount);
    if v_used <= 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;
    update public.profiles set balance = balance - v_used
     where id = v_me.id returning balance into v_new_bal;
  end if;

  update public.transactions
     set status = 'confirmed', user_id = v_me.id, balance_used = v_used, confirmed_at = now()
   where id = v_tx.id;

  return json_build_object(
    'type', v_tx.type,
    'amount', v_tx.amount,
    'cashback_amount', v_tx.cashback_amount,
    'balance_used', v_used,
    'remaining', v_tx.amount - v_used,
    'balance', v_new_bal
  );
end $$;

-- 4.4 KASSIR: QR holatini tekshirish (kassa ekrani har 2 soniyada so'raydi)
create or replace function public.cashier_transaction_status(p_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_tx public.transactions;
  v_u  public.profiles;
begin
  select * into v_tx from public.transactions where id = p_id and cafe_id = public.my_cafe_id();
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  select * into v_u from public.profiles where id = v_tx.user_id;

  return json_build_object(
    'status', case when v_tx.status = 'pending' and v_tx.expires_at < now() then 'expired' else v_tx.status end,
    'type', v_tx.type,
    'amount', v_tx.amount,
    'cashback_amount', v_tx.cashback_amount,
    'balance_used', v_tx.balance_used,
    'remaining', v_tx.amount - v_tx.balance_used,
    'customer_name', v_u.full_name,
    'customer_phone', case when v_u.phone is null then null
                           else left(v_u.phone, 6) || ' *** ** ' || right(v_u.phone, 2) end
  );
end $$;

-- 4.5 KASSIR: QR'ni bekor qilish
create or replace function public.cancel_transaction(p_id uuid)
returns void language sql security definer set search_path = public as $$
  update public.transactions set status = 'cancelled'
   where id = p_id and cafe_id = public.my_cafe_id() and status = 'pending';
$$;

-- 4.6 KASSIR: hisobot (oxirgi N kun, Toshkent vaqti bo'yicha)
create or replace function public.cashier_report(p_days int default 1)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  v_cafe  uuid := public.my_cafe_id();
  v_from  timestamptz;
  v_stats json;
  v_list  json;
begin
  if v_cafe is null then raise exception 'NOT_CASHIER'; end if;
  v_from := (date_trunc('day', now() at time zone 'Asia/Tashkent')
             - make_interval(days => greatest(p_days, 1) - 1)) at time zone 'Asia/Tashkent';

  select json_build_object(
    'total_count',        count(*),
    'cashback_count',     count(*) filter (where type = 'cashback'),
    'spend_count',        count(*) filter (where type = 'spend'),
    'total_amount',       coalesce(sum(amount), 0),
    'total_cashback',     coalesce(sum(cashback_amount) filter (where type = 'cashback'), 0),
    'total_balance_used', coalesce(sum(balance_used), 0),
    'unique_customers',   count(distinct user_id)
  ) into v_stats
  from public.transactions
  where cafe_id = v_cafe and status = 'confirmed' and confirmed_at >= v_from;

  select coalesce(json_agg(r order by r.confirmed_at desc), '[]'::json) into v_list
  from (
    select t.id, t.type, t.amount, t.cashback_amount, t.balance_used, t.confirmed_at,
           p.full_name as customer_name
      from public.transactions t
      left join public.profiles p on p.id = t.user_id
     where t.cafe_id = v_cafe and t.status = 'confirmed' and t.confirmed_at >= v_from
     order by t.confirmed_at desc
     limit 50
  ) r;

  return json_build_object('stats', v_stats, 'recent', v_list);
end $$;

-- ---------------------------------------------------------------------
-- 5. HUQUQLAR: funksiyalarni faqat tizimga kirganlar chaqira oladi
-- ---------------------------------------------------------------------
revoke all on function public.create_transaction(bigint, text)    from public, anon;
revoke all on function public.preview_transaction(text)           from public, anon;
revoke all on function public.confirm_transaction(text)           from public, anon;
revoke all on function public.cashier_transaction_status(uuid)    from public, anon;
revoke all on function public.cancel_transaction(uuid)            from public, anon;
revoke all on function public.cashier_report(int)                 from public, anon;
revoke all on function public.my_cafe_id()                        from public, anon;

grant execute on function public.create_transaction(bigint, text) to authenticated;
grant execute on function public.preview_transaction(text)        to authenticated;
grant execute on function public.confirm_transaction(text)        to authenticated;
grant execute on function public.cashier_transaction_status(uuid) to authenticated;
grant execute on function public.cancel_transaction(uuid)         to authenticated;
grant execute on function public.cashier_report(int)              to authenticated;
grant execute on function public.my_cafe_id()                     to authenticated;
