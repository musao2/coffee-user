-- =====================================================================
--  COFFEEGRAM — 10-QISM: MIJOZ JINSI VA YOSHI + ADMIN STATISTIKASI
--  09_sold.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  - Ro'yxatdan o'tishda: jins (erkak/ayol) va tug'ilgan yil (yosh shundan hisoblanadi)
--  - Eski mijozlar ilovaga kirganda shu ma'lumotni to'ldiradi
--  - Admin: jins va yosh guruhlari bo'yicha mijozlar va savdo statistikasi
-- =====================================================================

alter table public.profiles add column if not exists gender text;
alter table public.profiles add column if not exists birth_year int;
alter table public.profiles drop constraint if exists profiles_gender_check;
alter table public.profiles add constraint profiles_gender_check check (gender is null or gender in ('male', 'female'));
alter table public.profiles drop constraint if exists profiles_birth_year_check;
alter table public.profiles add constraint profiles_birth_year_check check (birth_year is null or birth_year between 1920 and 2025);

-- yosh guruhi
create or replace function public.age_group(p_birth_year int) returns text language sql stable as $$
  select case
    when p_birth_year is null then 'Noma’lum'
    when extract(year from now())::int - p_birth_year < 18 then '18 gacha'
    when extract(year from now())::int - p_birth_year < 25 then '18–24'
    when extract(year from now())::int - p_birth_year < 35 then '25–34'
    when extract(year from now())::int - p_birth_year < 45 then '35–44'
    when extract(year from now())::int - p_birth_year < 55 then '45–54'
    else '55+' end
$$;
create or replace function public.age_group_order(p_group text) returns int language sql immutable as $$
  select array_position(array['18 gacha', '18–24', '25–34', '35–44', '45–54', '55+', 'Noma’lum'], p_group)
$$;

-- Ro'yxatdan o'tishda jins va yilni ham saqlaymiz
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_gender text := new.raw_user_meta_data ->> 'gender'; v_year int;
begin
  begin v_year := (new.raw_user_meta_data ->> 'birth_year')::int; exception when others then v_year := null; end;
  if v_gender not in ('male', 'female') then v_gender := null; end if;
  if v_year is not null and (v_year < 1920 or v_year > 2025) then v_year := null; end if;
  insert into public.profiles (id, phone, full_name, email, gender, birth_year)
  values (new.id, nullif(new.raw_user_meta_data ->> 'phone', ''),
          coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.email, v_gender, v_year)
  on conflict (id) do nothing;
  return new;
end $$;

-- MIJOZ: o'z ma'lumotini to'ldirish/o'zgartirish (ism, jins, tug'ilgan yil)
create or replace function public.update_my_profile(p_full_name text, p_gender text, p_birth_year int)
returns json language plpgsql security definer set search_path = public as $$
declare v_p public.profiles;
begin
  if auth.uid() is null then raise exception 'NOT_AUTH'; end if;
  if p_gender not in ('male', 'female') then raise exception 'GENDER_REQUIRED'; end if;
  if p_birth_year is null or p_birth_year < 1920 or p_birth_year > 2025 then raise exception 'BIRTH_YEAR_REQUIRED'; end if;
  update public.profiles
     set gender = p_gender, birth_year = p_birth_year,
         full_name = coalesce(nullif(trim(p_full_name), ''), full_name)
   where id = auth.uid()
  returning * into v_p;
  return json_build_object('gender', v_p.gender, 'birth_year', v_p.birth_year, 'full_name', v_p.full_name);
end $$;

-- ADMIN: mijozlar ro'yxati (jins va yosh bilan)
create or replace function public.admin_customers(p_search text default null, p_limit int default 200)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r), '[]'::json) from (
    select p.id, p.full_name, p.phone, p.is_active, p.created_at, p.stamps, p.free_available, p.coffees_total, p.free_total,
           p.gender, p.birth_year,
           case when p.birth_year is null then null else extract(year from now())::int - p.birth_year end as age,
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

-- ADMIN: demografiya statistikasi (mijozlar + tanlangan davrdagi savdo)
create or replace function public.admin_demographics(p_days int default 30)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'customers_total', (select count(*) from public.profiles where role = 'customer'),
    'filled', (select count(*) from public.profiles where role = 'customer' and gender is not null and birth_year is not null),
    'avg_age', (select round(avg(extract(year from now())::int - birth_year), 1) from public.profiles where role = 'customer' and birth_year is not null),
    -- jins bo'yicha: mijozlar soni va davrdagi savdo
    'by_gender', (select coalesce(json_agg(x order by x.customers desc), '[]'::json) from (
        select coalesce(p.gender, 'unknown') as gender,
               count(distinct p.id) as customers,
               count(t.id) as orders,
               coalesce(sum(public.stamp_qty(t.items)), 0) as coffees,
               coalesce(sum(t.amount - t.discount), 0) as revenue,
               count(distinct t.user_id) as buyers
          from public.profiles p
          left join public.transactions t on t.user_id = p.id and t.status = 'confirmed' and t.type = 'stamp' and t.confirmed_at >= v_from
         where p.role = 'customer'
         group by 1) x),
    -- yosh guruhlari bo'yicha
    'by_age', (select coalesce(json_agg(x order by public.age_group_order(x.age_group)), '[]'::json) from (
        select public.age_group(p.birth_year) as age_group,
               count(distinct p.id) as customers,
               count(distinct p.id) filter (where p.gender = 'male') as male,
               count(distinct p.id) filter (where p.gender = 'female') as female,
               count(t.id) as orders,
               coalesce(sum(public.stamp_qty(t.items)), 0) as coffees,
               coalesce(sum(t.amount - t.discount), 0) as revenue
          from public.profiles p
          left join public.transactions t on t.user_id = p.id and t.status = 'confirmed' and t.type = 'stamp' and t.confirmed_at >= v_from
         where p.role = 'customer'
         group by 1) x),
    -- har bir jins uchun eng ko'p olinadigan kofe
    'top_by_gender', (select coalesce(json_agg(x), '[]'::json) from (
        select distinct on (g) g as gender, name, qty from (
          select coalesce(p.gender, 'unknown') as g, e ->> 'name' as name, sum((e ->> 'qty')::int) as qty
            from public.transactions t
            join public.profiles p on p.id = t.user_id
            cross join jsonb_array_elements(t.items) e
           where t.status = 'confirmed' and t.type = 'stamp' and t.confirmed_at >= v_from
             and coalesce((e ->> 'stamp')::boolean, false)
           group by 1, 2) s
        order by g, qty desc) x));
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.update_my_profile(text, text, int)', 'public.admin_demographics(int)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
