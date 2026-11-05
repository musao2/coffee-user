-- =====================================================================
--  COFFEEGRAM — 6-QISM: KOFE KARTOCHKASI (9 ta kofe → 10-chisi bepul)
--  05_staff_credentials.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  Cashback/balans o'rniga shtamp karta:
--  - buyurtmadagi har bir "shtamp beradigan" mahsulot (kofe) = 1 shtamp
--  - 9 shtamp = 1 bepul kofe (keyingi xaridda ishlatiladi)
--  - bepul kofe sifatida buyurtmadagi eng qimmat kofe chegirma qilinadi
--  Eski cashback cheklari tarixda qoladi.
-- =====================================================================

create or replace function public.stamp_goal() returns int language sql immutable as $$ select 9 $$;

-- ---------------------------------------------------------------------
-- 1. JADVALLAR
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists stamps int not null default 0;
alter table public.profiles add column if not exists free_available int not null default 0;
alter table public.profiles add column if not exists coffees_total int not null default 0;
alter table public.profiles add column if not exists free_total int not null default 0;
alter table public.profiles drop constraint if exists profiles_stamps_check;
alter table public.profiles add constraint profiles_stamps_check check (stamps >= 0 and free_available >= 0);

-- Mahsulot shtamp beradimi (birinchi marta: faqat "Kofe" kategoriyasi)
do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'products' and column_name = 'is_stamp') then
    alter table public.products add column is_stamp boolean not null default true;
    update public.products set is_stamp = (category ilike 'kofe%' or category ilike 'coffee%');
  end if;
end $$;

alter table public.transactions drop constraint if exists transactions_type_check;
alter table public.transactions add constraint transactions_type_check check (type in ('cashback', 'spend', 'adjust', 'stamp'));
alter table public.transactions add column if not exists stamps_earned int not null default 0;
alter table public.transactions add column if not exists free_used int not null default 0;
alter table public.transactions add column if not exists discount bigint not null default 0;
alter table public.transactions add column if not exists stamps_after int;
alter table public.transactions add column if not exists free_after int;

-- buyurtmadagi kofelar soni
create or replace function public.stamp_qty(p_items jsonb) returns int language sql immutable as $$
  select coalesce(sum((e ->> 'qty')::int), 0)::int
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e
   where coalesce((e ->> 'stamp')::boolean, false)
$$;
-- bepul bo'ladigan kofe: buyurtmadagi eng qimmati
create or replace function public.free_item(p_items jsonb) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e
   where coalesce((e ->> 'stamp')::boolean, false)
   order by (e ->> 'price')::bigint desc limit 1
$$;

-- ---------------------------------------------------------------------
-- 2. KASSA: buyurtma → QR
-- ---------------------------------------------------------------------
create or replace function public.create_order(p_items jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_me public.profiles; v_cafe public.cafes; v_tx public.transactions; v_items jsonb; v_amount bigint;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null or v_me.role <> 'cashier' or v_me.cafe_id is null then raise exception 'NOT_CASHIER'; end if;
  if not v_me.is_active then raise exception 'BLOCKED'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'BAD_ITEMS'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'price', p.price, 'qty', i.qty, 'stamp', p.is_stamp)
                            order by p.sort, p.name), '[]'::jsonb),
         coalesce(sum(p.price * i.qty), 0)
    into v_items, v_amount
    from (select (e ->> 'id')::uuid as id, least(99, sum(greatest(1, (e ->> 'qty')::int)))::int as qty
            from jsonb_array_elements(p_items) e group by 1) i
    join public.products p on p.id = i.id and p.is_active;
  if jsonb_array_length(v_items) = 0 or v_amount <= 0 then raise exception 'BAD_ITEMS'; end if;
  if v_amount > 10000000 then raise exception 'BAD_AMOUNT'; end if;

  select * into v_cafe from public.cafes where id = v_me.cafe_id and is_active;
  if v_cafe.id is null then raise exception 'CAFE_INACTIVE'; end if;

  update public.transactions set on_display = false where cashier_id = v_me.id and status = 'pending' and on_display;

  insert into public.transactions (token, type, amount, cashback_amount, cafe_id, cashier_id, expires_at, items)
  values (encode(gen_random_bytes(24), 'hex'), 'stamp', v_amount, 0, v_cafe.id, v_me.id, now() + interval '10 years', v_items)
  returning * into v_tx;

  return json_build_object('id', v_tx.id, 'token', v_tx.token, 'type', v_tx.type, 'amount', v_tx.amount,
                           'items', v_tx.items, 'stamp_qty', public.stamp_qty(v_tx.items), 'created_at', v_tx.created_at);
end $$;

-- ---------------------------------------------------------------------
-- 3. MIJOZ: ko'rish va tasdiqlash
-- ---------------------------------------------------------------------
create or replace function public.preview_order(p_token text)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_tx public.transactions; v_cafe public.cafes; v_me public.profiles; v_free jsonb;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  select * into v_tx from public.transactions where token = p_token and type = 'stamp';
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  select * into v_cafe from public.cafes where id = v_tx.cafe_id;
  v_free := public.free_item(v_tx.items);
  return json_build_object(
    'status', v_tx.status, 'items', v_tx.items, 'amount', v_tx.amount,
    'cafe_name', v_cafe.name, 'cafe_address', v_cafe.address,
    'stamp_qty', public.stamp_qty(v_tx.items), 'goal', public.stamp_goal(),
    'stamps', v_me.stamps, 'free_available', v_me.free_available,
    'can_use_free', v_me.free_available > 0 and v_free is not null,
    'free_item', v_free);
end $$;

create or replace function public.confirm_order(p_token text, p_use_free boolean default false)
returns json language plpgsql security definer set search_path = public as $$
declare
  v_me public.profiles; v_tx public.transactions; v_free jsonb; v_use boolean; v_qty int; v_earned int;
  v_total int; v_goal int := public.stamp_goal(); v_new_free int; v_new_stamps int; v_discount bigint := 0; v_no bigint;
begin
  select * into v_me from public.profiles where id = auth.uid() for update;
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  if v_me.role <> 'customer' then raise exception 'NOT_CUSTOMER'; end if;
  if not v_me.is_active then raise exception 'BLOCKED'; end if;

  select * into v_tx from public.transactions where token = p_token and type = 'stamp' for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status in ('confirmed', 'reversed') then raise exception 'ALREADY_USED'; end if;
  if v_tx.status = 'cancelled' then raise exception 'CANCELLED'; end if;
  if v_tx.status = 'expired' or v_tx.expires_at < now() then raise exception 'EXPIRED'; end if;

  v_qty  := public.stamp_qty(v_tx.items);
  v_free := public.free_item(v_tx.items);
  v_use  := coalesce(p_use_free, false) and v_me.free_available > 0 and v_free is not null;
  if v_use then v_discount := (v_free ->> 'price')::bigint; end if;

  v_earned     := v_qty - case when v_use then 1 else 0 end;   -- bepul kofe shtamp bermaydi
  v_total      := v_me.stamps + v_earned;
  v_new_stamps := v_total % v_goal;
  v_new_free   := v_me.free_available - case when v_use then 1 else 0 end + v_total / v_goal;

  update public.profiles
     set stamps = v_new_stamps, free_available = v_new_free,
         coffees_total = coffees_total + v_qty, free_total = free_total + case when v_use then 1 else 0 end
   where id = v_me.id;

  v_no := nextval('public.receipt_seq');
  update public.transactions
     set status = 'confirmed', user_id = v_me.id, confirmed_at = now(), receipt_no = v_no,
         stamps_earned = v_earned, free_used = case when v_use then 1 else 0 end, discount = v_discount,
         stamps_after = v_new_stamps, free_after = v_new_free
   where id = v_tx.id;

  return json_build_object(
    'id', v_tx.id, 'receipt_no', v_no, 'amount', v_tx.amount, 'discount', v_discount,
    'to_pay', v_tx.amount - v_discount, 'stamps_earned', v_earned, 'free_used', v_use,
    'free_item', case when v_use then v_free end, 'stamps', v_new_stamps, 'free_available', v_new_free,
    'goal', v_goal, 'new_rewards', v_total / v_goal);
end $$;

-- ---------------------------------------------------------------------
-- 4. KASSA: holat, QR ekran, hisobot
-- ---------------------------------------------------------------------
create or replace function public.cashier_transaction_status(p_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_tx public.transactions; v_u public.profiles;
begin
  select * into v_tx from public.transactions where id = p_id and cafe_id = public.my_cafe_id();
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'id', v_tx.id, 'receipt_no', v_tx.receipt_no, 'status', v_tx.status, 'type', v_tx.type,
    'amount', v_tx.amount, 'discount', v_tx.discount, 'to_pay', v_tx.amount - v_tx.discount,
    'stamps_earned', v_tx.stamps_earned, 'free_used', v_tx.free_used > 0,
    'free_item', case when v_tx.free_used > 0 then public.free_item(v_tx.items) end,
    'stamps_after', v_tx.stamps_after, 'free_after', v_tx.free_after, 'goal', public.stamp_goal(),
    'customer_name', v_u.full_name, 'customer_phone', public.mask_phone(v_u.phone));
end $$;

create or replace function public.cashier_display()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_me public.profiles; v_cafe public.cafes; v_tx public.transactions; v_u public.profiles;
begin
  select * into v_me from public.profiles where id = auth.uid() and role = 'cashier' and is_active;
  if v_me.id is null then raise exception 'NOT_CASHIER'; end if;
  select * into v_cafe from public.cafes where id = v_me.cafe_id;
  select * into v_tx from public.transactions
   where cashier_id = v_me.id
     and ((status = 'pending' and on_display) or (status = 'confirmed' and confirmed_at > now() - interval '12 seconds'))
   order by coalesce(confirmed_at, created_at) desc limit 1;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'cafe_name', v_cafe.name, 'cafe_address', v_cafe.address, 'goal', public.stamp_goal(),
    'tx', case when v_tx.id is null then null else json_build_object(
      'id', v_tx.id, 'token', v_tx.token, 'type', v_tx.type, 'status', v_tx.status, 'amount', v_tx.amount,
      'items', v_tx.items, 'stamp_qty', public.stamp_qty(v_tx.items), 'discount', v_tx.discount,
      'to_pay', v_tx.amount - v_tx.discount, 'stamps_earned', v_tx.stamps_earned, 'free_used', v_tx.free_used > 0,
      'stamps_after', v_tx.stamps_after, 'free_after', v_tx.free_after, 'customer_name', v_u.full_name) end);
end $$;

create or replace function public.cashier_report(p_days int default 1)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_cafe uuid := public.my_cafe_id(); v_from timestamptz := public.tashkent_from(p_days); v_stats json; v_list json;
begin
  if v_cafe is null then raise exception 'NOT_CASHIER'; end if;
  select json_build_object(
    'total_count', count(*), 'total_amount', coalesce(sum(amount), 0),
    'total_paid', coalesce(sum(amount - discount), 0), 'coffees', coalesce(sum(public.stamp_qty(items)), 0),
    'free_given', coalesce(sum(free_used), 0), 'discount', coalesce(sum(discount), 0),
    'unique_customers', count(distinct user_id))
  into v_stats from public.transactions
  where cafe_id = v_cafe and status = 'confirmed' and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from;

  select coalesce(json_agg(r order by r.confirmed_at desc), '[]'::json) into v_list from (
    select t.id, t.receipt_no, t.type, t.status, t.amount, t.discount, t.free_used, t.stamps_earned, t.items, t.confirmed_at,
           p.full_name as customer_name
      from public.transactions t left join public.profiles p on p.id = t.user_id
     where t.cafe_id = v_cafe and t.status in ('confirmed', 'reversed') and t.confirmed_at >= v_from
     order by t.confirmed_at desc limit 50) r;
  return json_build_object('stats', v_stats, 'recent', v_list, 'goal', public.stamp_goal());
end $$;

-- ---------------------------------------------------------------------
-- 5. CHEK
-- ---------------------------------------------------------------------
create or replace function public.get_receipt(p_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_me public.profiles; v_tx public.transactions; v_cafe public.cafes; v_k public.profiles; v_u public.profiles;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  select * into v_tx from public.transactions where id = p_id and status in ('confirmed', 'reversed');
  if v_tx.id is null or not (v_me.role = 'admin' or v_tx.user_id = v_me.id
                             or (v_me.role = 'cashier' and v_tx.cafe_id = v_me.cafe_id)) then
    raise exception 'NOT_FOUND';
  end if;
  select * into v_cafe from public.cafes where id = v_tx.cafe_id;
  select * into v_k from public.profiles where id = v_tx.cashier_id;
  select * into v_u from public.profiles where id = v_tx.user_id;
  return json_build_object(
    'id', v_tx.id, 'receipt_no', v_tx.receipt_no, 'type', v_tx.type, 'status', v_tx.status,
    'amount', v_tx.amount, 'cashback_amount', v_tx.cashback_amount, 'balance_used', v_tx.balance_used,
    'paid_cash', case when v_tx.type = 'adjust' then 0 else v_tx.amount - v_tx.balance_used - v_tx.discount end,
    'discount', v_tx.discount, 'free_used', v_tx.free_used > 0,
    'free_item', case when v_tx.free_used > 0 then public.free_item(v_tx.items) end,
    'stamps_earned', v_tx.stamps_earned, 'stamps_after', v_tx.stamps_after, 'free_after', v_tx.free_after,
    'goal', public.stamp_goal(), 'balance_after', v_tx.balance_after, 'items', v_tx.items, 'note', v_tx.note,
    'confirmed_at', v_tx.confirmed_at, 'cafe_name', coalesce(v_cafe.name, 'Coffeegram'), 'cafe_address', v_cafe.address,
    'cashier_name', v_k.full_name, 'customer_name', v_u.full_name, 'customer_phone', public.mask_phone(v_u.phone));
end $$;

-- ---------------------------------------------------------------------
-- 6. ADMIN
-- ---------------------------------------------------------------------
create or replace function public.admin_stats(p_days int default 1)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'goal', public.stamp_goal(),
    'totals', (select json_build_object(
        'count', count(*), 'amount', coalesce(sum(amount), 0), 'paid', coalesce(sum(amount - discount), 0),
        'discount', coalesce(sum(discount), 0), 'coffees', coalesce(sum(public.stamp_qty(items)), 0),
        'free_given', coalesce(sum(free_used), 0), 'customers', count(distinct user_id))
      from public.transactions
      where status = 'confirmed' and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from),
    'free_outstanding', (select coalesce(sum(free_available), 0) from public.profiles where role = 'customer'),
    'customers_total', (select count(*) from public.profiles where role = 'customer'),
    'new_customers', (select count(*) from public.profiles where role = 'customer' and created_at >= v_from),
    'by_cafe', (select coalesce(json_agg(x order by x.amount desc), '[]'::json) from (
        select c.id, c.name, c.is_active, count(t.id) as cnt, coalesce(sum(t.amount), 0) as amount,
               coalesce(sum(t.amount - t.discount), 0) as paid, coalesce(sum(public.stamp_qty(t.items)), 0) as coffees,
               coalesce(sum(t.free_used), 0) as free_given
          from public.cafes c
          left join public.transactions t on t.cafe_id = c.id and t.status = 'confirmed'
                                          and t.type in ('stamp', 'cashback', 'spend') and t.confirmed_at >= v_from
         group by c.id) x),
    'top_products', (select coalesce(json_agg(x order by x.qty desc), '[]'::json) from (
        select e ->> 'name' as name, sum((e ->> 'qty')::int) as qty, sum((e ->> 'qty')::int * (e ->> 'price')::bigint) as revenue,
               bool_or(coalesce((e ->> 'stamp')::boolean, false)) as stamp
          from public.transactions t, jsonb_array_elements(t.items) e
         where t.status = 'confirmed' and t.confirmed_at >= v_from
         group by 1 order by 2 desc limit 15) x),
    'daily', (select coalesce(json_agg(d order by d.day desc), '[]'::json) from (
        select (confirmed_at at time zone 'Asia/Tashkent')::date as day, count(*) as cnt, sum(amount) as amount,
               sum(amount - discount) as paid, sum(public.stamp_qty(items)) as coffees, sum(free_used) as free_given
          from public.transactions
         where status = 'confirmed' and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from
         group by 1) d));
end $$;

create or replace function public.admin_live()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(1);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'server_time', now(), 'goal', public.stamp_goal(),
    'today', (select json_build_object(
        'count', count(*), 'amount', coalesce(sum(amount), 0), 'paid', coalesce(sum(amount - discount), 0),
        'coffees', coalesce(sum(public.stamp_qty(items)), 0), 'free_given', coalesce(sum(free_used), 0),
        'customers', count(distinct user_id))
      from public.transactions
      where status = 'confirmed' and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from),
    'new_customers', (select count(*) from public.profiles where role = 'customer' and created_at >= v_from),
    'free_outstanding', (select coalesce(sum(free_available), 0) from public.profiles where role = 'customer'),
    'open_qr', (select coalesce(json_agg(q order by q.created_at desc), '[]'::json) from (
        select t.id, t.type, t.amount, public.stamp_qty(t.items) as stamp_qty, t.created_at, t.on_display,
               c.name as cafe_name, k.full_name as cashier_name
          from public.transactions t
          left join public.cafes c on c.id = t.cafe_id
          left join public.profiles k on k.id = t.cashier_id
         where t.status = 'pending' order by t.created_at desc limit 100) q),
    'cashiers', (select coalesce(json_agg(k order by k.last_at desc nulls last), '[]'::json) from (
        select p.id, p.full_name, p.email, p.is_active, c.name as cafe_name,
               (select max(t.created_at) from public.transactions t where t.cashier_id = p.id) as last_at,
               (select count(*) from public.transactions t where t.cashier_id = p.id and t.status = 'confirmed' and t.confirmed_at >= v_from) as today_count,
               (select coalesce(sum(t.amount - t.discount), 0) from public.transactions t where t.cashier_id = p.id and t.status = 'confirmed' and t.confirmed_at >= v_from) as today_amount
          from public.profiles p left join public.cafes c on c.id = p.cafe_id
         where p.role = 'cashier') k),
    'cafes', (select coalesce(json_agg(x order by x.amount desc), '[]'::json) from (
        select c.id, c.name, c.is_active, count(t.id) as cnt, coalesce(sum(t.amount - t.discount), 0) as amount,
               coalesce(sum(public.stamp_qty(t.items)), 0) as coffees, coalesce(sum(t.free_used), 0) as free_given,
               (select max(l.created_at) from public.activity_log l where l.cafe_id = c.id) as last_at
          from public.cafes c
          left join public.transactions t on t.cafe_id = c.id and t.status = 'confirmed' and t.confirmed_at >= v_from
         group by c.id) x));
end $$;

create or replace function public.admin_customers(p_search text default null, p_limit int default 200)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r), '[]'::json) from (
    select p.id, p.full_name, p.phone, p.is_active, p.created_at, p.stamps, p.free_available, p.coffees_total, p.free_total,
           (select count(*) from public.transactions t where t.user_id = p.id and t.status = 'confirmed' and t.type <> 'adjust') as tx_count,
           (select max(t.confirmed_at) from public.transactions t where t.user_id = p.id) as last_at,
           (select e ->> 'name' from public.transactions t, jsonb_array_elements(t.items) e
             where t.user_id = p.id and t.status = 'confirmed' and coalesce((e ->> 'stamp')::boolean, false)
             group by 1 order by sum((e ->> 'qty')::int) desc limit 1) as favorite
      from public.profiles p
     where p.role = 'customer'
       and (v_q is null or p.phone ilike '%' || v_q || '%' or p.full_name ilike '%' || v_q || '%')
     order by p.created_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 500)) r);
end $$;

-- Shtamplarni qo'lda tuzatish (+/−), sabab majburiy
create or replace function public.admin_adjust_stamps(p_user uuid, p_delta int, p_note text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_u public.profiles; v_goal int := public.stamp_goal(); v_p int; v_id uuid; v_no bigint;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_delta is null or p_delta = 0 or abs(p_delta) > 500 then raise exception 'BAD_AMOUNT'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_u from public.profiles where id = p_user and role = 'customer' for update;
  if v_u.id is null then raise exception 'NOT_FOUND'; end if;
  v_p := v_u.free_available * v_goal + v_u.stamps + p_delta;
  if v_p < 0 then raise exception 'NOT_ENOUGH_STAMPS'; end if;
  update public.profiles set stamps = v_p % v_goal, free_available = v_p / v_goal where id = p_user;
  v_no := nextval('public.receipt_seq');
  insert into public.transactions (token, type, amount, user_id, cafe_id, cashier_id, status, expires_at, confirmed_at,
                                   receipt_no, note, stamps_earned, stamps_after, free_after)
  values (encode(gen_random_bytes(24), 'hex'), 'adjust', abs(p_delta), p_user, null, auth.uid(), 'confirmed', now(), now(),
          v_no, trim(p_note), p_delta, v_p % v_goal, v_p / v_goal)
  returning id into v_id;
  return json_build_object('id', v_id, 'receipt_no', v_no, 'stamps', v_p % v_goal, 'free_available', v_p / v_goal);
end $$;

create or replace function public.admin_reverse_transaction(p_id uuid, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tx public.transactions; v_u public.profiles; v_goal int := public.stamp_goal(); v_p int; v_delta bigint;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_tx from public.transactions where id = p_id for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status <> 'confirmed' then raise exception 'NOT_REVERSIBLE'; end if;
  select * into v_u from public.profiles where id = v_tx.user_id for update;

  if v_tx.type = 'stamp' or (v_tx.type = 'adjust' and v_tx.stamps_earned <> 0) then
    -- shtamplarni qaytaramiz, ishlatilgan bepul kofeni qaytarib beramiz
    v_p := v_u.free_available * v_goal + v_u.stamps - v_tx.stamps_earned + v_tx.free_used * v_goal;
    if v_p < 0 then raise exception 'NOT_ENOUGH_STAMPS'; end if;
    update public.profiles
       set stamps = v_p % v_goal, free_available = v_p / v_goal,
           coffees_total = greatest(0, coffees_total - case when v_tx.type = 'stamp' then public.stamp_qty(v_tx.items) else 0 end),
           free_total = greatest(0, free_total - v_tx.free_used)
     where id = v_u.id;
  else
    -- eski cashback/balans amallari
    v_delta := case v_tx.type when 'cashback' then -v_tx.cashback_amount when 'spend' then v_tx.balance_used
                              else v_tx.balance_used - v_tx.cashback_amount end;
    if v_u.balance + v_delta < 0 then raise exception 'INSUFFICIENT_BALANCE'; end if;
    update public.profiles set balance = balance + v_delta where id = v_u.id;
  end if;

  update public.transactions set status = 'reversed', note = concat_ws(' · ', note, 'Bekor qilindi: ' || trim(p_note)) where id = p_id;
  select * into v_u from public.profiles where id = v_u.id;
  return json_build_object('stamps', v_u.stamps, 'free_available', v_u.free_available);
end $$;

create or replace function public.admin_transactions(
  p_days int default 7, p_cafe uuid default null, p_type text default null,
  p_status text default null, p_search text default null, p_limit int default 200)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days); v_q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r), '[]'::json) from (
    select t.id, t.receipt_no, t.type, t.status, t.amount, t.cashback_amount, t.balance_used, t.discount, t.free_used,
           t.stamps_earned, t.items, t.created_at, t.confirmed_at, t.note, c.name as cafe_name, k.full_name as cashier_name,
           u.full_name as customer_name, u.phone as customer_phone
      from public.transactions t
      left join public.cafes c on c.id = t.cafe_id
      left join public.profiles k on k.id = t.cashier_id
      left join public.profiles u on u.id = t.user_id
     where t.created_at >= v_from
       and (p_cafe is null or t.cafe_id = p_cafe)
       and (p_type is null or t.type = p_type)
       and (p_status is null or t.status = p_status)
       and (v_q is null or u.phone ilike '%' || v_q || '%' or u.full_name ilike '%' || v_q || '%' or t.receipt_no::text = v_q)
     order by t.created_at desc
     limit least(greatest(coalesce(p_limit, 200), 1), 500)) r);
end $$;

drop function if exists public.admin_upsert_product(uuid, text, text, bigint, boolean, int);
create or replace function public.admin_upsert_product(p_id uuid, p_name text, p_category text, p_price bigint,
                                                       p_active boolean, p_sort int, p_stamp boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'NAME_REQUIRED'; end if;
  if p_price is null or p_price <= 0 then raise exception 'BAD_AMOUNT'; end if;
  if p_id is null then
    insert into public.products (name, category, price, is_active, sort, is_stamp)
    values (trim(p_name), coalesce(nullif(trim(p_category), ''), 'Kofe'), p_price, coalesce(p_active, true), coalesce(p_sort, 0), coalesce(p_stamp, true))
    returning id into v_id;
  else
    update public.products set name = trim(p_name), category = coalesce(nullif(trim(p_category), ''), 'Kofe'),
           price = p_price, is_active = coalesce(p_active, true), sort = coalesce(p_sort, 0), is_stamp = coalesce(p_stamp, is_stamp)
     where id = p_id returning id into v_id;
    if v_id is null then raise exception 'NOT_FOUND'; end if;
  end if;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 7. JURNAL: yangi harakatlar
-- ---------------------------------------------------------------------
create or replace function public.trg_tx_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.type = 'adjust' and new.stamps_earned <> 0 then
      perform public.log_activity('stamps_adjusted', null, new.user_id, new.id, new.receipt_no,
                                  new.stamps_earned, new.free_after, new.note, new.cashier_id);
    elsif new.type = 'adjust' then
      perform public.log_activity('balance_adjusted', null, new.user_id, new.id, new.receipt_no,
                                  new.cashback_amount - new.balance_used, new.balance_after, new.note, new.cashier_id);
    else
      perform public.log_activity('qr_created', new.cafe_id, null, new.id, null,
                                  new.amount, public.stamp_qty(new.items), new.type, new.cashier_id);
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'confirmed' and new.type = 'stamp' then
      perform public.log_activity(case when new.free_used > 0 then 'free_redeemed' else 'order_confirmed' end,
                                  new.cafe_id, new.user_id, new.id, new.receipt_no, new.amount - new.discount,
                                  new.stamps_earned,
                                  (select string_agg((e ->> 'qty') || '× ' || (e ->> 'name'), ', ') from jsonb_array_elements(new.items) e),
                                  new.user_id);
    elsif new.status = 'confirmed' then
      perform public.log_activity(case new.type when 'cashback' then 'cashback_given' else 'balance_spent' end,
                                  new.cafe_id, new.user_id, new.id, new.receipt_no, new.amount,
                                  case new.type when 'cashback' then new.cashback_amount else new.balance_used end, null, new.user_id);
    elsif new.status = 'cancelled' then
      perform public.log_activity('qr_cancelled', new.cafe_id, null, new.id, null, new.amount, null, new.type);
    elsif new.status = 'reversed' then
      perform public.log_activity('tx_reversed', new.cafe_id, new.user_id, new.id, new.receipt_no,
                                  new.amount, new.stamps_earned, new.note);
    end if;
  end if;
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 8. HUQUQLAR
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'public.create_order(jsonb)', 'public.preview_order(text)', 'public.confirm_order(text, boolean)',
    'public.admin_adjust_stamps(uuid, int, text)',
    'public.admin_upsert_product(uuid, text, text, bigint, boolean, int, boolean)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
