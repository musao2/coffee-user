-- =====================================================================
--  COFFEEGRAM — 4-QISM: JONLI FAOLIYAT JURNALI (admin hamma narsani ko'radi)
--  03_qr_no_expiry.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  Tizimdagi HAR BIR harakat avtomatik (trigger orqali) yoziladi:
--  QR yaratildi / cashback berildi / balansdan to'landi / QR bekor qilindi /
--  chek qaytarildi / balans tuzatildi / mijoz ro'yxatdan o'tdi / bloklandi /
--  rol o'zgardi / kofexona va menyu o'zgarishlari.
--  Jurnalni faqat admin o'qiy oladi, hech kim tahrirlay yoki o'chira olmaydi.
-- =====================================================================

create table if not exists public.activity_log (
  id             bigserial primary key,
  created_at     timestamptz not null default now(),
  action         text not null,
  actor_id       uuid,
  actor_name     text,
  actor_role     text,
  cafe_id        uuid,
  cafe_name      text,
  customer_id    uuid,
  customer_name  text,
  customer_phone text,
  tx_id          uuid,
  receipt_no     bigint,
  amount         bigint,
  amount2        bigint,
  details        text
);
create index if not exists activity_log_created_idx on public.activity_log (created_at desc);
create index if not exists activity_log_cafe_idx on public.activity_log (cafe_id, created_at desc);
alter table public.activity_log enable row level security;  -- siyosat yo'q = to'g'ridan-to'g'ri kirish yo'q

-- ---------------------------------------------------------------------
-- Yozuvchi yordamchi
-- ---------------------------------------------------------------------
create or replace function public.log_activity(
  p_action text, p_cafe uuid default null, p_customer uuid default null, p_tx uuid default null,
  p_receipt bigint default null, p_amount bigint default null, p_amount2 bigint default null,
  p_details text default null, p_actor uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_actor public.profiles; v_cust public.profiles; v_cafe text;
begin
  select * into v_actor from public.profiles where id = coalesce(p_actor, auth.uid());
  select * into v_cust  from public.profiles where id = p_customer;
  select name into v_cafe from public.cafes where id = p_cafe;
  insert into public.activity_log (action, actor_id, actor_name, actor_role, cafe_id, cafe_name,
                                   customer_id, customer_name, customer_phone, tx_id, receipt_no,
                                   amount, amount2, details)
  values (p_action, v_actor.id, coalesce(nullif(v_actor.full_name, ''), v_actor.email, v_actor.phone), v_actor.role,
          p_cafe, v_cafe, v_cust.id, v_cust.full_name, v_cust.phone, p_tx, p_receipt,
          p_amount, p_amount2, p_details);
end $$;
revoke all on function public.log_activity(text, uuid, uuid, uuid, bigint, bigint, bigint, text, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Triggerlar
-- ---------------------------------------------------------------------
create or replace function public.trg_tx_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if new.type = 'adjust' then
      perform public.log_activity('balance_adjusted', null, new.user_id, new.id, new.receipt_no,
                                  new.cashback_amount - new.balance_used, new.balance_after, new.note, new.cashier_id);
    else
      perform public.log_activity('qr_created', new.cafe_id, null, new.id, null,
                                  new.amount, new.cashback_amount, new.type, new.cashier_id);
    end if;
    return new;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'confirmed' then
      perform public.log_activity(case new.type when 'cashback' then 'cashback_given' else 'balance_spent' end,
                                  new.cafe_id, new.user_id, new.id, new.receipt_no, new.amount,
                                  case new.type when 'cashback' then new.cashback_amount else new.balance_used end,
                                  null, new.user_id);
    elsif new.status = 'cancelled' then
      perform public.log_activity('qr_cancelled', new.cafe_id, null, new.id, null, new.amount, null, new.type);
    elsif new.status = 'reversed' then
      perform public.log_activity('tx_reversed', new.cafe_id, new.user_id, new.id, new.receipt_no,
                                  new.amount, case new.type when 'cashback' then new.cashback_amount else new.balance_used end,
                                  new.note);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists tx_activity on public.transactions;
create trigger tx_activity after insert or update of status on public.transactions
  for each row execute function public.trg_tx_activity();

create or replace function public.trg_profile_activity()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_old_cafe text; v_new_cafe text;
begin
  if tg_op = 'INSERT' then
    if new.role = 'customer' then
      perform public.log_activity('customer_registered', null, new.id, null, null, null, null, new.phone, new.id);
    end if;
    return new;
  end if;
  if new.is_active is distinct from old.is_active then
    perform public.log_activity(case when new.is_active then 'user_unblocked' else 'user_blocked' end,
                                new.cafe_id, new.id, null, null, null, null,
                                coalesce(nullif(new.full_name, ''), new.email, new.phone) || ' (' || new.role || ')');
  end if;
  if new.role is distinct from old.role or new.cafe_id is distinct from old.cafe_id then
    select name into v_old_cafe from public.cafes where id = old.cafe_id;
    select name into v_new_cafe from public.cafes where id = new.cafe_id;
    perform public.log_activity('role_changed', new.cafe_id, new.id, null, null, null, null,
      coalesce(nullif(new.full_name, ''), new.email, new.phone) || ': ' || old.role || coalesce(' / ' || v_old_cafe, '')
      || ' → ' || new.role || coalesce(' / ' || v_new_cafe, ''));
  end if;
  return new;
end $$;

drop trigger if exists profile_activity on public.profiles;
create trigger profile_activity after insert or update of role, cafe_id, is_active on public.profiles
  for each row execute function public.trg_profile_activity();

create or replace function public.trg_cafe_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.log_activity(case when tg_op = 'INSERT' then 'cafe_created' else 'cafe_updated' end,
    new.id, null, null, null, null, null,
    new.name || ' · ' || new.cashback_percent || '% cashback' || case when new.is_active then '' else ' · o''chirilgan' end);
  return new;
end $$;
drop trigger if exists cafe_activity on public.cafes;
create trigger cafe_activity after insert or update on public.cafes
  for each row execute function public.trg_cafe_activity();

create or replace function public.trg_product_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public.log_activity(case when tg_op = 'INSERT' then 'product_created' else 'product_updated' end,
    null, null, null, null, new.price, null,
    new.name || ' (' || new.category || ')' || case when new.is_active then '' else ' · yashirilgan' end);
  return new;
end $$;
drop trigger if exists product_activity on public.products;
create trigger product_activity after insert or update on public.products
  for each row execute function public.trg_product_activity();

-- Jurnal bo'sh bo'lsa — oldingi tasdiqlangan amallarni tarixdan to'ldiramiz
insert into public.activity_log (created_at, action, actor_id, actor_name, actor_role, cafe_id, cafe_name,
                                 customer_id, customer_name, customer_phone, tx_id, receipt_no, amount, amount2, details)
select coalesce(t.confirmed_at, t.created_at),
       case when t.type = 'adjust' then 'balance_adjusted'
            when t.type = 'cashback' then 'cashback_given' else 'balance_spent' end,
       u.id, u.full_name, u.role, t.cafe_id, c.name, u.id, u.full_name, u.phone, t.id, t.receipt_no,
       case when t.type = 'adjust' then t.cashback_amount - t.balance_used else t.amount end,
       case when t.type = 'cashback' then t.cashback_amount when t.type = 'spend' then t.balance_used else t.balance_after end,
       t.note
  from public.transactions t
  left join public.profiles u on u.id = t.user_id
  left join public.cafes c on c.id = t.cafe_id
 where t.status in ('confirmed', 'reversed')
   and not exists (select 1 from public.activity_log);

-- ---------------------------------------------------------------------
-- ADMIN RPC
-- ---------------------------------------------------------------------

-- Jonli lenta: eng yangi harakatlar (p_after — faqat shu id dan keyingilari)
create or replace function public.admin_activity(
  p_limit int default 100, p_after bigint default null, p_cafe uuid default null, p_action text default null)
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(a order by a.id desc), '[]'::json) from (
    select * from public.activity_log
     where (p_after is null or id > p_after)
       and (p_cafe is null or cafe_id = p_cafe)
       and (p_action is null or action = p_action)
     order by id desc
     limit least(greatest(coalesce(p_limit, 100), 1), 500)) a);
end $$;

-- Bugungi jonli holat: ko'rsatkichlar, ochiq QR'lar, kassirlar, kofexonalar
create or replace function public.admin_live()
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(1);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'server_time', now(),
    'today', (select json_build_object(
        'count', count(*),
        'amount', coalesce(sum(amount), 0),
        'cashback', coalesce(sum(cashback_amount) filter (where type = 'cashback'), 0),
        'balance_used', coalesce(sum(balance_used) filter (where type = 'spend'), 0),
        'customers', count(distinct user_id))
      from public.transactions
      where status = 'confirmed' and type in ('cashback', 'spend') and confirmed_at >= v_from),
    'new_customers', (select count(*) from public.profiles where role = 'customer' and created_at >= v_from),
    'liability', (select coalesce(sum(balance), 0) from public.profiles where role = 'customer'),
    'open_qr', (select coalesce(json_agg(q order by q.created_at desc), '[]'::json) from (
        select t.id, t.type, t.amount, t.cashback_amount, t.created_at, t.on_display,
               c.name as cafe_name, k.full_name as cashier_name
          from public.transactions t
          left join public.cafes c on c.id = t.cafe_id
          left join public.profiles k on k.id = t.cashier_id
         where t.status = 'pending'
         order by t.created_at desc limit 100) q),
    'cashiers', (select coalesce(json_agg(k order by k.last_at desc nulls last), '[]'::json) from (
        select p.id, p.full_name, p.email, p.is_active, c.name as cafe_name,
               (select max(t.created_at) from public.transactions t where t.cashier_id = p.id) as last_at,
               (select count(*) from public.transactions t
                 where t.cashier_id = p.id and t.status = 'confirmed' and t.confirmed_at >= v_from) as today_count,
               (select coalesce(sum(t.amount), 0) from public.transactions t
                 where t.cashier_id = p.id and t.status = 'confirmed' and t.confirmed_at >= v_from) as today_amount
          from public.profiles p left join public.cafes c on c.id = p.cafe_id
         where p.role = 'cashier') k),
    'cafes', (select coalesce(json_agg(x order by x.amount desc), '[]'::json) from (
        select c.id, c.name, c.is_active, c.cashback_percent,
               count(t.id) as cnt, coalesce(sum(t.amount), 0) as amount,
               coalesce(sum(t.cashback_amount) filter (where t.type = 'cashback'), 0) as cashback,
               coalesce(sum(t.balance_used) filter (where t.type = 'spend'), 0) as balance_used,
               (select max(l.created_at) from public.activity_log l where l.cafe_id = c.id) as last_at
          from public.cafes c
          left join public.transactions t on t.cafe_id = c.id and t.status = 'confirmed' and t.confirmed_at >= v_from
         group by c.id) x));
end $$;

-- Admin istalgan ochiq QR'ni bekor qila oladi
create or replace function public.admin_cancel_transaction(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update public.transactions set status = 'cancelled', on_display = false where id = p_id and status = 'pending';
  if not found then raise exception 'NOT_REVERSIBLE'; end if;
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.admin_activity(int, bigint, uuid, text)', 'public.admin_live()',
                           'public.admin_cancel_transaction(uuid)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
