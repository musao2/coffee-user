-- =====================================================================
--  COFFEEGRAM — 2-QISM: ADMIN PANEL, MENYU, CHEKLAR
--  schema.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
-- =====================================================================

create sequence if not exists public.receipt_seq start 1000;

-- ---------------------------------------------------------------------
-- 1. JADVAL O'ZGARISHLARI
-- ---------------------------------------------------------------------

-- Rollar: customer / cashier / admin; bloklash; email
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('customer', 'cashier', 'admin'));
alter table public.profiles add column if not exists is_active boolean not null default true;
alter table public.profiles add column if not exists email text;

update public.profiles p set email = u.email
  from auth.users u where u.id = p.id and p.email is null;

-- Tranzaksiyalar: chek raqami, mahsulotlar, admin tuzatishlari, bekor qilish
alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check (type in ('cashback', 'spend', 'adjust'));
alter table public.transactions drop constraint if exists transactions_status_check;
alter table public.transactions add constraint transactions_status_check
  check (status in ('pending', 'confirmed', 'expired', 'cancelled', 'reversed'));
alter table public.transactions alter column cafe_id drop not null;
alter table public.transactions add column if not exists items jsonb not null default '[]'::jsonb;
alter table public.transactions add column if not exists receipt_no bigint unique;
alter table public.transactions add column if not exists balance_after bigint;
alter table public.transactions add column if not exists note text;

create index if not exists transactions_created_idx on public.transactions (created_at desc);

-- Menyu (barcha kofexonalar uchun umumiy)
create table if not exists public.products (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  category   text not null default 'Kofe',
  price      bigint not null check (price > 0),
  is_active  boolean not null default true,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
alter table public.products enable row level security;
drop policy if exists "products readable" on public.products;
create policy "products readable" on public.products for select to authenticated using (true);

-- Boshlang'ich menyu (faqat jadval bo'sh bo'lsa)
insert into public.products (name, category, price, sort)
select * from (values
  ('Espresso', 'Kofe', 15000, 1), ('Americano', 'Kofe', 18000, 2), ('Cappuccino', 'Kofe', 25000, 3),
  ('Latte', 'Kofe', 28000, 4), ('Flat white', 'Kofe', 27000, 5), ('Raf', 'Kofe', 32000, 6),
  ('Choy', 'Ichimliklar', 12000, 10), ('Matcha latte', 'Ichimliklar', 34000, 11),
  ('Kruassan', 'Shirinliklar', 18000, 20), ('Chizkeyk', 'Shirinliklar', 32000, 21), ('Brauni', 'Shirinliklar', 22000, 22)
) v(name, category, price, sort)
where not exists (select 1 from public.products);

-- ---------------------------------------------------------------------
-- 2. YORDAMCHI FUNKSIYALAR
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, phone, full_name, email)
  values (new.id, nullif(new.raw_user_meta_data ->> 'phone', ''),
          coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.email)
  on conflict (id) do nothing;
  return new;
end $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin' and is_active)
$$;

create or replace function public.my_cafe_id()
returns uuid language sql stable security definer set search_path = public as $$
  select cafe_id from public.profiles where id = auth.uid() and role = 'cashier' and is_active
$$;

create or replace function public.mask_phone(p text)
returns text language sql immutable as $$
  select case when p is null then null else left(p, 6) || ' *** ** ' || right(p, 2) end
$$;

create or replace function public.tashkent_from(p_days int)
returns timestamptz language sql stable as $$
  select (date_trunc('day', now() at time zone 'Asia/Tashkent')
          - make_interval(days => greatest(p_days, 1) - 1)) at time zone 'Asia/Tashkent'
$$;

-- Admin hamma narsani ko'ra oladi
drop policy if exists "own profile" on public.profiles;
create policy "own profile" on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());

drop policy if exists "own or cafe transactions" on public.transactions;
create policy "own or cafe transactions" on public.transactions
  for select to authenticated
  using (user_id = auth.uid() or cafe_id = public.my_cafe_id() or public.is_admin());

-- ---------------------------------------------------------------------
-- 3. KASSA FUNKSIYALARI (yangilangan)
-- ---------------------------------------------------------------------
drop function if exists public.create_transaction(bigint, text);

-- p_items: [{ "id": "<product uuid>", "qty": 2 }, ...]  — bo'lsa summa serverda hisoblanadi
create or replace function public.create_transaction(p_amount bigint, p_type text, p_items jsonb default '[]'::jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  v_me     public.profiles;
  v_cafe   public.cafes;
  v_tx     public.transactions;
  v_ttl    int := 90;
  v_items  jsonb := '[]'::jsonb;
  v_amount bigint := p_amount;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null or v_me.role <> 'cashier' or v_me.cafe_id is null then raise exception 'NOT_CASHIER'; end if;
  if not v_me.is_active then raise exception 'BLOCKED'; end if;
  if p_type not in ('cashback', 'spend') then raise exception 'BAD_TYPE'; end if;

  if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
    select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'price', p.price, 'qty', i.qty)
                              order by p.sort, p.name), '[]'::jsonb),
           coalesce(sum(p.price * i.qty), 0)
      into v_items, v_amount
      from (select (e ->> 'id')::uuid as id, least(99, sum(greatest(1, (e ->> 'qty')::int)))::int as qty
              from jsonb_array_elements(p_items) e group by 1) i
      join public.products p on p.id = i.id and p.is_active;
    if jsonb_array_length(v_items) = 0 then raise exception 'BAD_ITEMS'; end if;
  end if;

  if v_amount is null or v_amount <= 0 or v_amount > 10000000 then raise exception 'BAD_AMOUNT'; end if;

  select * into v_cafe from public.cafes where id = v_me.cafe_id and is_active;
  if v_cafe.id is null then raise exception 'CAFE_INACTIVE'; end if;

  update public.transactions set status = 'cancelled' where cashier_id = v_me.id and status = 'pending';

  insert into public.transactions (token, type, amount, cashback_amount, cafe_id, cashier_id, expires_at, items)
  values (encode(gen_random_bytes(24), 'hex'), p_type, v_amount,
          case when p_type = 'cashback' then floor(v_amount * v_cafe.cashback_percent / 100)::bigint else 0 end,
          v_cafe.id, v_me.id, now() + make_interval(secs => v_ttl), v_items)
  returning * into v_tx;

  return json_build_object('id', v_tx.id, 'token', v_tx.token, 'type', v_tx.type, 'amount', v_tx.amount,
                           'cashback_amount', v_tx.cashback_amount, 'items', v_tx.items, 'expires_in', v_ttl);
end $$;

create or replace function public.preview_transaction(p_token text)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_tx public.transactions; v_cafe public.cafes; v_bal bigint;
begin
  if auth.uid() is null then raise exception 'NOT_AUTH'; end if;
  select * into v_tx from public.transactions where token = p_token and type <> 'adjust';
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  select * into v_cafe from public.cafes where id = v_tx.cafe_id;
  select balance into v_bal from public.profiles where id = auth.uid();
  return json_build_object(
    'type', v_tx.type, 'amount', v_tx.amount, 'cashback_amount', v_tx.cashback_amount, 'items', v_tx.items,
    'cashback_percent', v_cafe.cashback_percent, 'cafe_name', v_cafe.name, 'cafe_address', v_cafe.address,
    'status', case when v_tx.status = 'pending' and v_tx.expires_at < now() then 'expired' else v_tx.status end,
    'seconds_left', greatest(0, ceil(extract(epoch from (v_tx.expires_at - now()))))::int,
    'balance', coalesce(v_bal, 0), 'will_use', least(coalesce(v_bal, 0), v_tx.amount));
end $$;

create or replace function public.confirm_transaction(p_token text)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_me public.profiles; v_tx public.transactions; v_used bigint := 0; v_new_bal bigint; v_no bigint;
begin
  select * into v_me from public.profiles where id = auth.uid() for update;
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  if v_me.role <> 'customer' then raise exception 'NOT_CUSTOMER'; end if;
  if not v_me.is_active then raise exception 'BLOCKED'; end if;

  select * into v_tx from public.transactions where token = p_token and type <> 'adjust' for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status in ('confirmed', 'reversed') then raise exception 'ALREADY_USED'; end if;
  if v_tx.status = 'cancelled' then raise exception 'CANCELLED'; end if;
  if v_tx.status = 'expired' or v_tx.expires_at < now() then raise exception 'EXPIRED'; end if;

  if v_tx.type = 'cashback' then
    update public.profiles set balance = balance + v_tx.cashback_amount where id = v_me.id returning balance into v_new_bal;
  else
    v_used := least(v_me.balance, v_tx.amount);
    if v_used <= 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;
    update public.profiles set balance = balance - v_used where id = v_me.id returning balance into v_new_bal;
  end if;

  v_no := nextval('public.receipt_seq');
  update public.transactions
     set status = 'confirmed', user_id = v_me.id, balance_used = v_used, confirmed_at = now(),
         receipt_no = v_no, balance_after = v_new_bal
   where id = v_tx.id;

  return json_build_object('id', v_tx.id, 'receipt_no', v_no, 'type', v_tx.type, 'amount', v_tx.amount,
    'cashback_amount', v_tx.cashback_amount, 'balance_used', v_used,
    'remaining', v_tx.amount - v_used, 'balance', v_new_bal);
end $$;

create or replace function public.cashier_transaction_status(p_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_tx public.transactions; v_u public.profiles;
begin
  select * into v_tx from public.transactions where id = p_id and cafe_id = public.my_cafe_id();
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'id', v_tx.id, 'receipt_no', v_tx.receipt_no,
    'status', case when v_tx.status = 'pending' and v_tx.expires_at < now() then 'expired' else v_tx.status end,
    'type', v_tx.type, 'amount', v_tx.amount, 'cashback_amount', v_tx.cashback_amount,
    'balance_used', v_tx.balance_used, 'remaining', v_tx.amount - v_tx.balance_used,
    'customer_name', v_u.full_name, 'customer_phone', public.mask_phone(v_u.phone));
end $$;

create or replace function public.cashier_report(p_days int default 1)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_cafe uuid := public.my_cafe_id(); v_from timestamptz := public.tashkent_from(p_days); v_stats json; v_list json;
begin
  if v_cafe is null then raise exception 'NOT_CASHIER'; end if;
  select json_build_object(
    'total_count', count(*), 'cashback_count', count(*) filter (where type = 'cashback'),
    'spend_count', count(*) filter (where type = 'spend'), 'total_amount', coalesce(sum(amount), 0),
    'total_cashback', coalesce(sum(cashback_amount) filter (where type = 'cashback'), 0),
    'total_balance_used', coalesce(sum(balance_used), 0), 'unique_customers', count(distinct user_id))
  into v_stats from public.transactions
  where cafe_id = v_cafe and status = 'confirmed' and confirmed_at >= v_from;

  select coalesce(json_agg(r order by r.confirmed_at desc), '[]'::json) into v_list from (
    select t.id, t.receipt_no, t.type, t.status, t.amount, t.cashback_amount, t.balance_used, t.confirmed_at,
           p.full_name as customer_name
      from public.transactions t left join public.profiles p on p.id = t.user_id
     where t.cafe_id = v_cafe and t.status in ('confirmed', 'reversed') and t.confirmed_at >= v_from
     order by t.confirmed_at desc limit 50) r;
  return json_build_object('stats', v_stats, 'recent', v_list);
end $$;

-- Mijozga qaragan QR ekran: shu kassirning hozirgi QR'i (yoki hozirgina tasdiqlangan)
create or replace function public.cashier_display()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_me public.profiles; v_cafe public.cafes; v_tx public.transactions; v_u public.profiles;
begin
  select * into v_me from public.profiles where id = auth.uid() and role = 'cashier' and is_active;
  if v_me.id is null then raise exception 'NOT_CASHIER'; end if;
  select * into v_cafe from public.cafes where id = v_me.cafe_id;
  select * into v_tx from public.transactions
   where cashier_id = v_me.id
     and ((status = 'pending' and expires_at > now())
          or (status = 'confirmed' and confirmed_at > now() - interval '12 seconds'))
   order by created_at desc limit 1;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'cafe_name', v_cafe.name, 'cafe_address', v_cafe.address, 'cashback_percent', v_cafe.cashback_percent,
    'tx', case when v_tx.id is null then null else json_build_object(
      'id', v_tx.id, 'token', v_tx.token, 'type', v_tx.type, 'status', v_tx.status, 'amount', v_tx.amount,
      'cashback_amount', v_tx.cashback_amount, 'balance_used', v_tx.balance_used, 'items', v_tx.items,
      'balance_after', v_tx.balance_after, 'customer_name', v_u.full_name,
      'seconds_left', greatest(0, ceil(extract(epoch from (v_tx.expires_at - now()))))::int) end);
end $$;

-- ---------------------------------------------------------------------
-- 4. CHEK (mijoz o'zinikini, kassir o'z kofexonasinikini, admin hammasini ko'radi)
-- ---------------------------------------------------------------------
create or replace function public.get_receipt(p_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_me public.profiles; v_tx public.transactions; v_cafe public.cafes; v_k public.profiles; v_u public.profiles;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  select * into v_tx from public.transactions where id = p_id and status in ('confirmed', 'reversed');
  if v_tx.id is null or not (
       v_me.role = 'admin' or v_tx.user_id = v_me.id
       or (v_me.role = 'cashier' and v_tx.cafe_id = v_me.cafe_id)) then
    raise exception 'NOT_FOUND';
  end if;
  select * into v_cafe from public.cafes where id = v_tx.cafe_id;
  select * into v_k from public.profiles where id = v_tx.cashier_id;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'id', v_tx.id, 'receipt_no', v_tx.receipt_no, 'type', v_tx.type, 'status', v_tx.status,
    'amount', v_tx.amount, 'cashback_amount', v_tx.cashback_amount, 'balance_used', v_tx.balance_used,
    'paid_cash', case when v_tx.type = 'adjust' then 0 else v_tx.amount - v_tx.balance_used end,
    'balance_after', v_tx.balance_after, 'items', v_tx.items, 'note', v_tx.note,
    'confirmed_at', v_tx.confirmed_at,
    'cafe_name', coalesce(v_cafe.name, 'Bean Back'), 'cafe_address', v_cafe.address,
    'cashier_name', v_k.full_name, 'customer_name', v_u.full_name,
    'customer_phone', public.mask_phone(v_u.phone));
end $$;

-- ---------------------------------------------------------------------
-- 5. ADMIN FUNKSIYALARI
-- ---------------------------------------------------------------------
create or replace function public.admin_stats(p_days int default 1)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'totals', (select json_build_object(
        'count', count(*), 'amount', coalesce(sum(amount), 0),
        'cashback', coalesce(sum(cashback_amount) filter (where type = 'cashback'), 0),
        'balance_used', coalesce(sum(balance_used) filter (where type = 'spend'), 0),
        'customers', count(distinct user_id))
      from public.transactions
      where status = 'confirmed' and type in ('cashback', 'spend') and confirmed_at >= v_from),
    'liability', (select coalesce(sum(balance), 0) from public.profiles where role = 'customer'),
    'customers_total', (select count(*) from public.profiles where role = 'customer'),
    'new_customers', (select count(*) from public.profiles where role = 'customer' and created_at >= v_from),
    'by_cafe', (select coalesce(json_agg(x order by x.amount desc), '[]'::json) from (
        select c.id, c.name, c.is_active, count(t.id) as cnt, coalesce(sum(t.amount), 0) as amount,
               coalesce(sum(t.cashback_amount) filter (where t.type = 'cashback'), 0) as cashback,
               coalesce(sum(t.balance_used) filter (where t.type = 'spend'), 0) as balance_used
          from public.cafes c
          left join public.transactions t on t.cafe_id = c.id and t.status = 'confirmed' and t.confirmed_at >= v_from
         group by c.id) x),
    'daily', (select coalesce(json_agg(d order by d.day desc), '[]'::json) from (
        select (confirmed_at at time zone 'Asia/Tashkent')::date as day, count(*) as cnt, sum(amount) as amount,
               coalesce(sum(cashback_amount) filter (where type = 'cashback'), 0) as cashback,
               coalesce(sum(balance_used) filter (where type = 'spend'), 0) as balance_used
          from public.transactions
         where status = 'confirmed' and type in ('cashback', 'spend') and confirmed_at >= v_from
         group by 1) d));
end $$;

create or replace function public.admin_transactions(
  p_days int default 7, p_cafe uuid default null, p_type text default null,
  p_status text default null, p_search text default null, p_limit int default 200)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days); v_q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r), '[]'::json) from (
    select t.id, t.receipt_no, t.type, t.status, t.amount, t.cashback_amount, t.balance_used,
           t.created_at, t.confirmed_at, t.note, c.name as cafe_name, k.full_name as cashier_name,
           u.full_name as customer_name, u.phone as customer_phone
      from public.transactions t
      left join public.cafes c on c.id = t.cafe_id
      left join public.profiles k on k.id = t.cashier_id
      left join public.profiles u on u.id = t.user_id
     where t.created_at >= v_from
       and (p_cafe is null or t.cafe_id = p_cafe)
       and (p_type is null or t.type = p_type)
       and (p_status is null or t.status = p_status)
       and (v_q is null or u.phone ilike '%' || v_q || '%' or u.full_name ilike '%' || v_q || '%'
            or t.receipt_no::text = v_q)
     order by t.created_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 500)) r);
end $$;

create or replace function public.admin_customers(p_search text default null, p_limit int default 200)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r), '[]'::json) from (
    select p.id, p.full_name, p.phone, p.balance, p.is_active, p.created_at,
           (select count(*) from public.transactions t where t.user_id = p.id and t.status = 'confirmed' and t.type <> 'adjust') as tx_count,
           (select coalesce(sum(t.cashback_amount), 0) from public.transactions t where t.user_id = p.id and t.status = 'confirmed' and t.type = 'cashback') as earned,
           (select max(t.confirmed_at) from public.transactions t where t.user_id = p.id) as last_at
      from public.profiles p
     where p.role = 'customer'
       and (v_q is null or p.phone ilike '%' || v_q || '%' or p.full_name ilike '%' || v_q || '%')
     order by p.created_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 500)) r);
end $$;

create or replace function public.admin_staff()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r order by r.role, r.full_name), '[]'::json) from (
    select p.id, p.full_name, p.email, p.role, p.cafe_id, c.name as cafe_name, p.is_active, p.created_at
      from public.profiles p left join public.cafes c on c.id = p.cafe_id
     where p.role in ('cashier', 'admin')) r);
end $$;

create or replace function public.admin_set_staff(p_user uuid, p_role text, p_cafe uuid default null, p_name text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_role not in ('customer', 'cashier', 'admin') then raise exception 'BAD_ROLE'; end if;
  if p_user = auth.uid() and p_role <> 'admin' then raise exception 'SELF'; end if;
  if p_role = 'cashier' and (p_cafe is null or not exists (select 1 from public.cafes where id = p_cafe)) then
    raise exception 'CAFE_REQUIRED';
  end if;
  update public.profiles
     set role = p_role,
         cafe_id = case when p_role = 'cashier' then p_cafe else null end,
         full_name = coalesce(nullif(trim(p_name), ''), full_name)
   where id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
end $$;

create or replace function public.admin_set_active(p_user uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_user = auth.uid() then raise exception 'SELF'; end if;
  update public.profiles set is_active = p_active where id = p_user;
  if not found then raise exception 'NOT_FOUND'; end if;
  if not p_active then
    update public.transactions set status = 'cancelled' where cashier_id = p_user and status = 'pending';
  end if;
end $$;

-- Balansni qo'lda tuzatish (+ yoki −), sabab majburiy, chek sifatida yoziladi
create or replace function public.admin_adjust_balance(p_user uuid, p_delta bigint, p_note text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_u public.profiles; v_new bigint; v_id uuid; v_no bigint;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 10000000 then raise exception 'BAD_AMOUNT'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_u from public.profiles where id = p_user and role = 'customer' for update;
  if v_u.id is null then raise exception 'NOT_FOUND'; end if;
  if v_u.balance + p_delta < 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.profiles set balance = balance + p_delta where id = p_user returning balance into v_new;
  v_no := nextval('public.receipt_seq');
  insert into public.transactions (token, type, amount, cashback_amount, balance_used, user_id, cafe_id, cashier_id,
                                   status, expires_at, confirmed_at, receipt_no, balance_after, note)
  values (encode(gen_random_bytes(24), 'hex'), 'adjust', abs(p_delta), greatest(p_delta, 0), greatest(-p_delta, 0),
          p_user, null, auth.uid(), 'confirmed', now(), now(), v_no, v_new, trim(p_note))
  returning id into v_id;
  return json_build_object('id', v_id, 'receipt_no', v_no, 'balance', v_new);
end $$;

-- Tasdiqlangan tranzaksiyani bekor qilish (balans ta'siri qaytariladi)
create or replace function public.admin_reverse_transaction(p_id uuid, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tx public.transactions; v_u public.profiles; v_delta bigint; v_new bigint;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_tx from public.transactions where id = p_id for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status <> 'confirmed' then raise exception 'NOT_REVERSIBLE'; end if;

  v_delta := case v_tx.type when 'cashback' then -v_tx.cashback_amount
                            when 'spend'    then v_tx.balance_used
                            else v_tx.balance_used - v_tx.cashback_amount end;
  select * into v_u from public.profiles where id = v_tx.user_id for update;
  if v_u.balance + v_delta < 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;

  update public.profiles set balance = balance + v_delta where id = v_u.id returning balance into v_new;
  update public.transactions
     set status = 'reversed', note = concat_ws(' · ', note, 'Bekor qilindi: ' || trim(p_note))
   where id = p_id;
  return json_build_object('balance', v_new);
end $$;

create or replace function public.admin_upsert_cafe(p_id uuid, p_name text, p_address text, p_percent numeric, p_active boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'NAME_REQUIRED'; end if;
  if p_percent is null or p_percent < 0 or p_percent > 50 then raise exception 'BAD_PERCENT'; end if;
  if p_id is null then
    insert into public.cafes (name, address, cashback_percent, is_active)
    values (trim(p_name), nullif(trim(p_address), ''), p_percent, coalesce(p_active, true)) returning id into v_id;
  else
    update public.cafes set name = trim(p_name), address = nullif(trim(p_address), ''),
           cashback_percent = p_percent, is_active = coalesce(p_active, true)
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

create or replace function public.admin_upsert_product(p_id uuid, p_name text, p_category text, p_price bigint, p_active boolean, p_sort int)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'NAME_REQUIRED'; end if;
  if p_price is null or p_price <= 0 then raise exception 'BAD_AMOUNT'; end if;
  if p_id is null then
    insert into public.products (name, category, price, is_active, sort)
    values (trim(p_name), coalesce(nullif(trim(p_category), ''), 'Kofe'), p_price, coalesce(p_active, true), coalesce(p_sort, 0))
    returning id into v_id;
  else
    update public.products set name = trim(p_name), category = coalesce(nullif(trim(p_category), ''), 'Kofe'),
           price = p_price, is_active = coalesce(p_active, true), sort = coalesce(p_sort, 0)
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 6. HUQUQLAR
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.create_transaction(bigint, text, jsonb)', 'public.preview_transaction(text)',
    'public.confirm_transaction(text)', 'public.cashier_transaction_status(uuid)',
    'public.cancel_transaction(uuid)', 'public.cashier_report(int)', 'public.my_cafe_id()',
    'public.is_admin()', 'public.get_receipt(uuid)', 'public.cashier_display()', 'public.admin_stats(int)',
    'public.admin_transactions(int, uuid, text, text, text, int)', 'public.admin_customers(text, int)',
    'public.admin_staff()', 'public.admin_set_staff(uuid, text, uuid, text)',
    'public.admin_set_active(uuid, boolean)', 'public.admin_adjust_balance(uuid, bigint, text)',
    'public.admin_reverse_transaction(uuid, text)',
    'public.admin_upsert_cafe(uuid, text, text, numeric, boolean)',
    'public.admin_upsert_product(uuid, text, text, bigint, boolean, int)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- =====================================================================
--  BIRINCHI ADMINNI TAYINLASH:
--  1) Authentication → Users → Add user: admin@beanback.uz + parol (Auto Confirm ✅)
--  2) Quyidagi qatorni ishga tushiring:
--
--  update public.profiles set role = 'admin', full_name = 'Admin'
--   where id = (select id from auth.users where email = 'admin@beanback.uz');
-- =====================================================================
