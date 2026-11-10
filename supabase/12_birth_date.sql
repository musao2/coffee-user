-- =====================================================================
--  COFFEEGRAM — 12-QISM: TO'LIQ TUG'ILGAN SANA (kun, oy, yil)
--  11_top_customers.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
--
--  - Mijoz endi faqat yilni emas, to'liq tug'ilgan sanasini kiritadi
--  - birth_year avtomatik sanadan olinadi (eski statistika ishlashda davom etadi)
--  - Eski mijozlar ilovaga kirganda tug'ilgan kunini to'ldiradi
--  - Admin: mijozning tug'ilgan sanasi, aniq yoshi va tug'ilgan kunigacha necha kun qolgani
-- =====================================================================

alter table public.profiles add column if not exists birth_date date;
alter table public.profiles drop constraint if exists profiles_birth_date_check;
alter table public.profiles add constraint profiles_birth_date_check
  check (birth_date is null or birth_date between date '1920-01-01' and date '2025-12-31');

-- tug'ilgan kunigacha necha kun qoldi (0 = bugun). 29-fevral kabisa bo'lmagan yilda 28-fevralga tushadi.
create or replace function public.days_to_birthday(p_birth date) returns int language sql stable as $$
  select case when p_birth is null then null else (
    select min(d) from (
      select (make_date(y, extract(month from p_birth)::int,
                least(extract(day from p_birth)::int,
                      extract(day from (make_date(y, extract(month from p_birth)::int, 1) + interval '1 month - 1 day'))::int))
              - (now() at time zone 'Asia/Tashkent')::date) as d
        from generate_series(extract(year from (now() at time zone 'Asia/Tashkent'))::int,
                             extract(year from (now() at time zone 'Asia/Tashkent'))::int + 1) y) s
     where d >= 0) end
$$;

create or replace function public.age_from(p_birth date, p_year int) returns int language sql stable as $$
  select case
    when p_birth is not null then extract(year from age((now() at time zone 'Asia/Tashkent')::date, p_birth))::int
    when p_year is not null then extract(year from now())::int - p_year
  end
$$;

-- Ro'yxatdan o'tishda to'liq sanani saqlaymiz (eski ilova faqat birth_year yuborsa ham ishlaydi)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_gender text := new.raw_user_meta_data ->> 'gender'; v_year int; v_date date;
begin
  begin v_date := (new.raw_user_meta_data ->> 'birth_date')::date; exception when others then v_date := null; end;
  if v_date is not null and (v_date < date '1920-01-01' or v_date > date '2025-12-31') then v_date := null; end if;
  begin v_year := coalesce(extract(year from v_date)::int, (new.raw_user_meta_data ->> 'birth_year')::int); exception when others then v_year := null; end;
  if v_gender not in ('male', 'female') then v_gender := null; end if;
  if v_year is not null and (v_year < 1920 or v_year > 2025) then v_year := null; end if;
  insert into public.profiles (id, phone, full_name, email, gender, birth_year, birth_date)
  values (new.id, nullif(new.raw_user_meta_data ->> 'phone', ''),
          coalesce(new.raw_user_meta_data ->> 'full_name', ''), new.email, v_gender, v_year, v_date)
  on conflict (id) do nothing;
  return new;
end $$;

-- MIJOZ: ism, jins va to'liq tug'ilgan sana
create or replace function public.update_my_birth(p_full_name text, p_gender text, p_birth_date date)
returns json language plpgsql security definer set search_path = public as $$
declare v_p public.profiles;
begin
  if auth.uid() is null then raise exception 'NOT_AUTH'; end if;
  if p_gender not in ('male', 'female') then raise exception 'GENDER_REQUIRED'; end if;
  if p_birth_date is null or p_birth_date < date '1920-01-01' or p_birth_date > date '2025-12-31' then raise exception 'BIRTH_DATE_REQUIRED'; end if;
  update public.profiles
     set gender = p_gender, birth_date = p_birth_date, birth_year = extract(year from p_birth_date)::int,
         full_name = coalesce(nullif(trim(p_full_name), ''), full_name)
   where id = auth.uid()
  returning * into v_p;
  return json_build_object('gender', v_p.gender, 'birth_date', v_p.birth_date, 'full_name', v_p.full_name);
end $$;

-- ADMIN: mijozlar ro'yxati (tug'ilgan sana va tug'ilgan kunigacha qolgan kunlar bilan)
create or replace function public.admin_customers(p_search text default null, p_limit int default 200)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_q text := nullif(trim(coalesce(p_search, '')), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r), '[]'::json) from (
    select p.id, p.full_name, p.phone, p.is_active, p.created_at, p.stamps, p.free_available, p.coffees_total, p.free_total,
           p.gender, p.birth_year, p.birth_date,
           public.age_from(p.birth_date, p.birth_year) as age,
           public.days_to_birthday(p.birth_date) as bday_in,
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

revoke all on function public.update_my_birth(text, text, date) from public, anon;
grant execute on function public.update_my_birth(text, text, date) to authenticated;

-- ADMIN: yaqin tug'ilgan kunlar (bugun va keyingi p_days kun ichida)
create or replace function public.admin_birthdays(p_days int default 30)
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return json_build_object(
    'without_date', (select count(*) from public.profiles where role = 'customer' and birth_date is null),
    'list', (select coalesce(json_agg(r order by r.bday_in, r.full_name), '[]'::json) from (
      select p.id, p.full_name, p.phone, p.gender, p.birth_date, p.is_active,
             public.days_to_birthday(p.birth_date) as bday_in,
             public.age_from(p.birth_date, null) + case when public.days_to_birthday(p.birth_date) = 0 then 0 else 1 end as turns,
             p.coffees_total, p.stamps, p.free_available,
             (select max(t.confirmed_at) from public.transactions t where t.user_id = p.id) as last_at
        from public.profiles p
       where p.role = 'customer' and p.birth_date is not null
         and public.days_to_birthday(p.birth_date) <= least(greatest(coalesce(p_days, 30), 0), 366)) r));
end $$;

revoke all on function public.admin_birthdays(int) from public, anon;
grant execute on function public.admin_birthdays(int) to authenticated;
