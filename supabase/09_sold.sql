-- =====================================================================
--  COFFEEGRAM — 9-QISM: "KEYINGI BUYURTMA" HAM SOTUV SIFATIDA HISOBLANADI
--  08_categories.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  Yangi holat: 'sold' — kassir "Keyingi buyurtma" ni bosdi, pul olindi, chek chiqarilmadi.
--   - chek raqami beriladi, tushum/hisobotlarga to'liq kiradi
--   - mijoz keyin QR'ni skanerlasa — shtamplarni oladi ('confirmed' bo'ladi), summa ikki marta hisoblanmaydi
--   - kassir (bugungi) va admin uni bekor qila oladi
-- =====================================================================

alter table public.transactions drop constraint if exists transactions_status_check;
alter table public.transactions add constraint transactions_status_check
  check (status in ('pending', 'sold', 'confirmed', 'expired', 'cancelled', 'reversed'));

-- KASSIR: "Keyingi buyurtma" — buyurtma sotildi deb belgilanadi (chek chiqarilmaydi)
create or replace function public.cashier_mark_sold(p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_tx public.transactions; v_no bigint;
begin
  select * into v_tx from public.transactions where id = p_id and cashier_id = auth.uid() for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status = 'pending' then
    v_no := nextval('public.receipt_seq');
    update public.transactions
       set status = 'sold', receipt_no = v_no, confirmed_at = now(), on_display = false
     where id = p_id;
  else
    -- allaqachon tasdiqlangan/sotilgan bo'lsa — faqat ekrandan olib tashlaymiz
    update public.transactions set on_display = false where id = p_id;
    v_no := v_tx.receipt_no;
  end if;
  return json_build_object('receipt_no', v_no, 'status', (select status from public.transactions where id = p_id));
end $$;
revoke all on function public.cashier_mark_sold(uuid) from public, anon;
grant execute on function public.cashier_mark_sold(uuid) to authenticated;

-- cashier_report: 'sold' ham hisoblanadi
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
  where cafe_id = v_cafe and status in ('confirmed', 'sold') and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from;

  select coalesce(json_agg(r order by r.confirmed_at desc), '[]'::json) into v_list from (
    select t.id, t.receipt_no, t.type, t.status, t.amount, t.discount, t.free_used, t.stamps_earned, t.items, t.confirmed_at,
           p.full_name as customer_name
      from public.transactions t left join public.profiles p on p.id = t.user_id
     where t.cafe_id = v_cafe and t.status in ('confirmed', 'sold', 'reversed') and t.confirmed_at >= v_from
     order by t.confirmed_at desc limit 50) r;
  return json_build_object('stats', v_stats, 'recent', v_list, 'goal', public.stamp_goal());
end $$;

-- admin_stats: 'sold' ham hisoblanadi
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
      where status in ('confirmed', 'sold') and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from),
    'free_outstanding', (select coalesce(sum(free_available), 0) from public.profiles where role = 'customer'),
    'customers_total', (select count(*) from public.profiles where role = 'customer'),
    'new_customers', (select count(*) from public.profiles where role = 'customer' and created_at >= v_from),
    'by_cafe', (select coalesce(json_agg(x order by x.amount desc), '[]'::json) from (
        select c.id, c.name, c.is_active, count(t.id) as cnt, coalesce(sum(t.amount), 0) as amount,
               coalesce(sum(t.amount - t.discount), 0) as paid, coalesce(sum(public.stamp_qty(t.items)), 0) as coffees,
               coalesce(sum(t.free_used), 0) as free_given
          from public.cafes c
          left join public.transactions t on t.cafe_id = c.id and t.status in ('confirmed', 'sold')
                                          and t.type in ('stamp', 'cashback', 'spend') and t.confirmed_at >= v_from
         group by c.id) x),
    'top_products', (select coalesce(json_agg(x order by x.qty desc), '[]'::json) from (
        select e ->> 'name' as name, sum((e ->> 'qty')::int) as qty, sum((e ->> 'qty')::int * (e ->> 'price')::bigint) as revenue,
               bool_or(coalesce((e ->> 'stamp')::boolean, false)) as stamp
          from public.transactions t, jsonb_array_elements(t.items) e
         where t.status in ('confirmed', 'sold') and t.confirmed_at >= v_from
         group by 1 order by 2 desc limit 15) x),
    'daily', (select coalesce(json_agg(d order by d.day desc), '[]'::json) from (
        select (confirmed_at at time zone 'Asia/Tashkent')::date as day, count(*) as cnt, sum(amount) as amount,
               sum(amount - discount) as paid, sum(public.stamp_qty(items)) as coffees, sum(free_used) as free_given
          from public.transactions
         where status in ('confirmed', 'sold') and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from
         group by 1) d));
end $$;

-- admin_live: 'sold' ham hisoblanadi
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
      where status in ('confirmed', 'sold') and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from),
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
               (select count(*) from public.transactions t where t.cashier_id = p.id and t.status in ('confirmed', 'sold') and t.confirmed_at >= v_from) as today_count,
               (select coalesce(sum(t.amount - t.discount), 0) from public.transactions t where t.cashier_id = p.id and t.status in ('confirmed', 'sold') and t.confirmed_at >= v_from) as today_amount
          from public.profiles p left join public.cafes c on c.id = p.cafe_id
         where p.role = 'cashier') k),
    'cafes', (select coalesce(json_agg(x order by x.amount desc), '[]'::json) from (
        select c.id, c.name, c.is_active, count(t.id) as cnt, coalesce(sum(t.amount - t.discount), 0) as amount,
               coalesce(sum(public.stamp_qty(t.items)), 0) as coffees, coalesce(sum(t.free_used), 0) as free_given,
               (select max(l.created_at) from public.activity_log l where l.cafe_id = c.id) as last_at
          from public.cafes c
          left join public.transactions t on t.cafe_id = c.id and t.status in ('confirmed', 'sold') and t.confirmed_at >= v_from
         group by c.id) x));
end $$;

-- admin_expenses: 'sold' ham hisoblanadi
create or replace function public.admin_expenses(p_days int default 1, p_cafe uuid default null)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'total', (select coalesce(sum(amount), 0) from public.expenses
               where status = 'active' and created_at >= v_from and (p_cafe is null or cafe_id = p_cafe)),
    'count', (select count(*) from public.expenses
               where status = 'active' and created_at >= v_from and (p_cafe is null or cafe_id = p_cafe)),
    'revenue', (select coalesce(sum(amount - discount - balance_used), 0) from public.transactions
                 where status in ('confirmed', 'sold') and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from
                   and (p_cafe is null or cafe_id = p_cafe)),
    'by_cafe', (select coalesce(json_agg(x order by x.total desc), '[]'::json) from (
        select c.id, c.name, coalesce(sum(e.amount) filter (where e.status = 'active'), 0) as total, count(e.id) filter (where e.status = 'active') as cnt
          from public.cafes c left join public.expenses e on e.cafe_id = c.id and e.created_at >= v_from
         where p_cafe is null or c.id = p_cafe
         group by c.id) x),
    'by_category', (select coalesce(json_agg(x order by x.total desc), '[]'::json) from (
        select category, sum(amount) as total, count(*) as cnt from public.expenses
         where status = 'active' and created_at >= v_from and (p_cafe is null or cafe_id = p_cafe)
         group by 1) x),
    'items', (select coalesce(json_agg(r order by r.created_at desc), '[]'::json) from (
        select e.id, e.amount, e.category, e.note, e.status, e.cancel_note, e.created_at,
               c.name as cafe_name, p.full_name as cashier_name, p.email as cashier_email, a.full_name as cancelled_by_name
          from public.expenses e
          left join public.cafes c on c.id = e.cafe_id
          left join public.profiles p on p.id = e.cashier_id
          left join public.profiles a on a.id = e.cancelled_by
         where e.created_at >= v_from and (p_cafe is null or e.cafe_id = p_cafe)
         order by e.created_at desc limit 500) r));
end $$;

-- get_receipt: 'sold' cheklar ham ochiladi
create or replace function public.get_receipt(p_id uuid)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_me public.profiles; v_tx public.transactions; v_cafe public.cafes; v_k public.profiles; v_u public.profiles;
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null then raise exception 'NOT_AUTH'; end if;
  select * into v_tx from public.transactions where id = p_id and status in ('confirmed', 'sold', 'reversed');
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
    'status', case when v_tx.status = 'sold' then 'pending' else v_tx.status end, 'items', v_tx.items, 'amount', v_tx.amount,
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

  -- 'sold' bo'lsa — sotuv vaqti va chek raqami o'zgarmaydi (tushum ikki marta hisoblanmaydi)
  v_no := coalesce(v_tx.receipt_no, nextval('public.receipt_seq'));
  update public.transactions
     set status = 'confirmed', user_id = v_me.id, confirmed_at = coalesce(v_tx.confirmed_at, now()), receipt_no = v_no, on_display = false,
         stamps_earned = v_earned, free_used = case when v_use then 1 else 0 end, discount = v_discount,
         stamps_after = v_new_stamps, free_after = v_new_free
   where id = v_tx.id;

  return json_build_object(
    'id', v_tx.id, 'receipt_no', v_no, 'amount', v_tx.amount, 'discount', v_discount,
    'to_pay', v_tx.amount - v_discount, 'stamps_earned', v_earned, 'free_used', v_use,
    'free_item', case when v_use then v_free end, 'stamps', v_new_stamps, 'free_available', v_new_free,
    'goal', v_goal, 'new_rewards', v_total / v_goal);
end $$;

create or replace function public.cashier_reverse_transaction(p_id uuid, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_cafe uuid := public.my_cafe_id(); v_tx public.transactions; v_u public.profiles; v_goal int := public.stamp_goal(); v_p int;
begin
  if v_cafe is null then raise exception 'NOT_CASHIER'; end if;
  if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_tx from public.transactions where id = p_id and cafe_id = v_cafe for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status not in ('confirmed', 'sold') or v_tx.type <> 'stamp' then raise exception 'NOT_REVERSIBLE'; end if;
  if v_tx.confirmed_at < public.tashkent_from(1) then raise exception 'ONLY_TODAY'; end if;

  select * into v_u from public.profiles where id = v_tx.user_id for update;
  if v_u.id is not null then
    v_p := v_u.free_available * v_goal + v_u.stamps - v_tx.stamps_earned + v_tx.free_used * v_goal;
    if v_p < 0 then raise exception 'NOT_ENOUGH_STAMPS'; end if;
    update public.profiles
       set stamps = v_p % v_goal, free_available = v_p / v_goal,
           coffees_total = greatest(0, coffees_total - public.stamp_qty(v_tx.items)),
           free_total = greatest(0, free_total - v_tx.free_used)
     where id = v_u.id;
  end if;
  update public.transactions
     set status = 'reversed', note = concat_ws(' · ', note, 'Kassir bekor qildi: ' || trim(p_note))
   where id = p_id;
  return json_build_object('ok', true);
end $$;

create or replace function public.admin_reverse_transaction(p_id uuid, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_tx public.transactions; v_u public.profiles; v_goal int := public.stamp_goal(); v_p int; v_delta bigint;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(trim(p_note), '') = '' then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_tx from public.transactions where id = p_id for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status not in ('confirmed', 'sold') then raise exception 'NOT_REVERSIBLE'; end if;
  select * into v_u from public.profiles where id = v_tx.user_id for update;

  if v_u.id is null then
    null;  -- mijozsiz sotuv: faqat bekor qilamiz
  elsif v_tx.type = 'stamp' or (v_tx.type = 'adjust' and v_tx.stamps_earned <> 0) then
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
  if v_u.id is not null then select * into v_u from public.profiles where id = v_u.id; end if;
  return json_build_object('stamps', v_u.stamps, 'free_available', v_u.free_available);
end $$;

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
    if new.status = 'sold' then
      perform public.log_activity('order_sold', new.cafe_id, null, new.id, new.receipt_no, new.amount,
                                  public.stamp_qty(new.items),
                                  (select string_agg((e ->> 'qty') || '× ' || (e ->> 'name'), ', ') from jsonb_array_elements(new.items) e),
                                  new.cashier_id);
    elsif new.status = 'confirmed' and new.type = 'stamp' and old.status = 'sold' then
      perform public.log_activity('stamps_claimed', new.cafe_id, new.user_id, new.id, new.receipt_no, new.amount - new.discount,
                                  new.stamps_earned, null, new.user_id);
    elsif new.status = 'confirmed' and new.type = 'stamp' then
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
