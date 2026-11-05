-- =====================================================================
--  COFFEEGRAM — 8-QISM: MENYU KATEGORIYALARI (admin boshqaradi)
--  07_expenses.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  - Admin kategoriya qo'shadi, nomini o'zgartiradi, tartibini va ko'rinishini belgilaydi
--  - Kassadagi "Hammasi · Kofe · Ichimliklar …" tugmalari shu tartibda chiqadi
--  - Nomi o'zgarsa — shu kategoriyadagi mahsulotlar ham avtomatik ko'chadi
-- =====================================================================

create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique check (length(trim(name)) >= 2),
  sort       int not null default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.categories enable row level security;
drop policy if exists "categories readable" on public.categories;
create policy "categories readable" on public.categories for select to authenticated using (true);

-- Mavjud mahsulotlardagi kategoriyalarni ko'chirib olamiz (faqat yo'qlarini)
insert into public.categories (name, sort)
select c.category, (row_number() over (order by min(c.sort)))::int * 10
  from public.products c
 where not exists (select 1 from public.categories k where k.name = c.category)
 group by c.category;

create or replace function public.admin_upsert_category(p_id uuid, p_name text, p_sort int default null, p_active boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_old text; v_name text := trim(coalesce(p_name, ''));
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if length(v_name) < 2 then raise exception 'NAME_REQUIRED'; end if;
  if exists (select 1 from public.categories where lower(name) = lower(v_name) and id is distinct from p_id) then
    raise exception 'CATEGORY_EXISTS';
  end if;
  if p_id is null then
    insert into public.categories (name, sort, is_active)
    values (v_name, coalesce(p_sort, (select coalesce(max(sort), 0) + 10 from public.categories)), coalesce(p_active, true))
    returning id into v_id;
    perform public.log_activity('category_created', null, null, null, null, null, null, v_name);
  else
    select name into v_old from public.categories where id = p_id;
    if v_old is null then raise exception 'NOT_FOUND'; end if;
    update public.categories set name = v_name, sort = coalesce(p_sort, sort), is_active = coalesce(p_active, is_active)
     where id = p_id returning id into v_id;
    if v_old <> v_name then
      update public.products set category = v_name where category = v_old;
    end if;
    perform public.log_activity('category_updated', null, null, null, null, null, null,
      case when v_old <> v_name then v_old || ' → ' || v_name else v_name end
      || case when coalesce(p_active, true) then '' else ' · yashirildi' end);
  end if;
  return v_id;
end $$;

-- Tartibni bir yo'la saqlash: p_ids = kerakli tartibdagi id'lar ro'yxati
create or replace function public.admin_sort_categories(p_ids uuid[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update public.categories c set sort = x.ord * 10
    from unnest(p_ids) with ordinality as x(id, ord)
   where c.id = x.id;
end $$;

-- O'chirish: faqat ichida mahsulot bo'lmasa
create or replace function public.admin_delete_category(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select name into v_name from public.categories where id = p_id;
  if v_name is null then raise exception 'NOT_FOUND'; end if;
  if exists (select 1 from public.products where category = v_name) then raise exception 'CATEGORY_NOT_EMPTY'; end if;
  delete from public.categories where id = p_id;
  perform public.log_activity('category_deleted', null, null, null, null, null, null, v_name);
end $$;

-- Mahsulot qo'shilganda yangi kategoriya bo'lsa — avtomatik ro'yxatga qo'shiladi
create or replace function public.trg_product_category()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.categories (name, sort)
  values (new.category, (select coalesce(max(sort), 0) + 10 from public.categories))
  on conflict (name) do nothing;
  return new;
end $$;
drop trigger if exists product_category on public.products;
create trigger product_category after insert or update of category on public.products
  for each row execute function public.trg_product_category();

do $$
declare f text;
begin
  foreach f in array array['public.admin_upsert_category(uuid, text, int, boolean)',
                           'public.admin_sort_categories(uuid[])', 'public.admin_delete_category(uuid)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
