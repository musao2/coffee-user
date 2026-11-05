-- =====================================================================
--  COFFEEGRAM — 7-QISM: KUNLIK XARAJATLAR
--  06_stamps.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  - Kassir o'z kofexonasi uchun xarajat kiritadi: summa + turi + IZOH (majburiy, kamida 5 belgi)
--  - Kassir faqat o'z kofexonasining xarajatlarini ko'radi; o'chira olmaydi
--  - Admin barcha xarajatlarni ko'radi va sababini yozib bekor qila oladi
--  - Har bir xarajat jonli jurnalga yoziladi
-- =====================================================================

create table if not exists public.expenses (
  id          uuid primary key default gen_random_uuid(),
  cafe_id     uuid not null references public.cafes(id) on delete cascade,
  cashier_id  uuid not null references public.profiles(id) on delete cascade,
  amount      bigint not null check (amount > 0 and amount <= 100000000),
  category    text not null default 'Boshqa',
  note        text not null check (length(trim(note)) >= 5),
  status      text not null default 'active' check (status in ('active', 'cancelled')),
  cancel_note text,
  cancelled_by uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists expenses_cafe_idx on public.expenses (cafe_id, created_at desc);
create index if not exists expenses_created_idx on public.expenses (created_at desc);
alter table public.expenses enable row level security;   -- siyosat yo'q: faqat funksiyalar orqali

create or replace function public.expense_categories() returns text[] language sql immutable as $$
  select array['Mahsulot', 'Kofe donasi', 'Sut', 'Kommunal', 'Ijara', 'Ish haqi', 'Tozalash', 'Ta’mirlash', 'Transport', 'Boshqa']
$$;

-- KASSIR: xarajat qo'shish
create or replace function public.add_expense(p_amount bigint, p_category text, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_me public.profiles; v_e public.expenses; v_cat text := coalesce(nullif(trim(p_category), ''), 'Boshqa');
begin
  select * into v_me from public.profiles where id = auth.uid();
  if v_me.id is null or v_me.role <> 'cashier' or v_me.cafe_id is null then raise exception 'NOT_CASHIER'; end if;
  if not v_me.is_active then raise exception 'BLOCKED'; end if;
  if p_amount is null or p_amount <= 0 or p_amount > 100000000 then raise exception 'BAD_AMOUNT'; end if;
  if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'NOTE_REQUIRED'; end if;
  if not (v_cat = any(public.expense_categories())) then v_cat := 'Boshqa'; end if;
  insert into public.expenses (cafe_id, cashier_id, amount, category, note)
  values (v_me.cafe_id, v_me.id, p_amount, v_cat, trim(p_note))
  returning * into v_e;
  return row_to_json(v_e);
end $$;

-- KASSIR: o'z kofexonasining xarajatlari
create or replace function public.cashier_expenses(p_days int default 1)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_cafe uuid := public.my_cafe_id(); v_from timestamptz := public.tashkent_from(p_days);
begin
  if v_cafe is null then raise exception 'NOT_CASHIER'; end if;
  return json_build_object(
    'categories', public.expense_categories(),
    'total', (select coalesce(sum(amount), 0) from public.expenses where cafe_id = v_cafe and status = 'active' and created_at >= v_from),
    'items', (select coalesce(json_agg(r order by r.created_at desc), '[]'::json) from (
        select e.id, e.amount, e.category, e.note, e.status, e.cancel_note, e.created_at, p.full_name as cashier_name
          from public.expenses e left join public.profiles p on p.id = e.cashier_id
         where e.cafe_id = v_cafe and e.created_at >= v_from
         order by e.created_at desc limit 200) r));
end $$;

-- ADMIN: barcha xarajatlar + jamlar
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
                 where status = 'confirmed' and type in ('stamp', 'cashback', 'spend') and confirmed_at >= v_from
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

-- ADMIN: xarajatni bekor qilish (sabab majburiy)
create or replace function public.admin_cancel_expense(p_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'NOTE_REQUIRED'; end if;
  update public.expenses set status = 'cancelled', cancel_note = trim(p_note), cancelled_by = auth.uid()
   where id = p_id and status = 'active';
  if not found then raise exception 'NOT_FOUND'; end if;
end $$;

-- Jurnal
create or replace function public.trg_expense_activity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    perform public.log_activity('expense_added', new.cafe_id, null, null, null, new.amount, null,
                                new.category || ': ' || new.note, new.cashier_id);
  elsif new.status = 'cancelled' and old.status <> 'cancelled' then
    perform public.log_activity('expense_cancelled', new.cafe_id, null, null, null, new.amount, null,
                                new.category || ': ' || new.note || ' · sabab: ' || coalesce(new.cancel_note, ''));
  end if;
  return new;
end $$;
drop trigger if exists expense_activity on public.expenses;
create trigger expense_activity after insert or update of status on public.expenses
  for each row execute function public.trg_expense_activity();

do $$
declare f text;
begin
  foreach f in array array['public.add_expense(bigint, text, text)', 'public.cashier_expenses(int)',
                           'public.admin_expenses(int, uuid)', 'public.admin_cancel_expense(uuid, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- =====================================================================
--  KASSIR: XATO CHEKNI BEKOR QILISH (faqat o'z kofexonasi, faqat bugungi, sabab majburiy)
-- =====================================================================
create or replace function public.cashier_reverse_transaction(p_id uuid, p_note text)
returns json language plpgsql security definer set search_path = public as $$
declare v_cafe uuid := public.my_cafe_id(); v_tx public.transactions; v_u public.profiles; v_goal int := public.stamp_goal(); v_p int;
begin
  if v_cafe is null then raise exception 'NOT_CASHIER'; end if;
  if length(trim(coalesce(p_note, ''))) < 5 then raise exception 'NOTE_REQUIRED'; end if;
  select * into v_tx from public.transactions where id = p_id and cafe_id = v_cafe for update;
  if v_tx.id is null then raise exception 'NOT_FOUND'; end if;
  if v_tx.status <> 'confirmed' or v_tx.type <> 'stamp' then raise exception 'NOT_REVERSIBLE'; end if;
  if v_tx.confirmed_at < public.tashkent_from(1) then raise exception 'ONLY_TODAY'; end if;

  select * into v_u from public.profiles where id = v_tx.user_id for update;
  v_p := v_u.free_available * v_goal + v_u.stamps - v_tx.stamps_earned + v_tx.free_used * v_goal;
  if v_p < 0 then raise exception 'NOT_ENOUGH_STAMPS'; end if;
  update public.profiles
     set stamps = v_p % v_goal, free_available = v_p / v_goal,
         coffees_total = greatest(0, coffees_total - public.stamp_qty(v_tx.items)),
         free_total = greatest(0, free_total - v_tx.free_used)
   where id = v_u.id;
  update public.transactions
     set status = 'reversed', note = concat_ws(' · ', note, 'Kassir bekor qildi: ' || trim(p_note))
   where id = p_id;
  return json_build_object('ok', true);
end $$;
revoke all on function public.cashier_reverse_transaction(uuid, text) from public, anon;
grant execute on function public.cashier_reverse_transaction(uuid, text) to authenticated;
