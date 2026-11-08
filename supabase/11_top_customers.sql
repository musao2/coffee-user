-- =====================================================================
--  COFFEEGRAM — 11-QISM: ENG KO'P XARID QILGAN MIJOZLAR (TOP reyting)
--  10_demographics.sql dan KEYIN ishga tushiring. Qayta ishga tushirish xavfsiz.
-- =====================================================================

-- ADMIN: tanlangan davrda eng ko'p xarid qilgan mijozlar (tushum bo'yicha, teng bo'lsa — kofe soni)
create or replace function public.admin_top_customers(p_days int default 30, p_limit int default 10)
returns json language plpgsql stable security definer set search_path = public as $$
declare v_from timestamptz := public.tashkent_from(p_days);
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return (select coalesce(json_agg(r order by r.rank), '[]'::json) from (
    select row_number() over (order by sum(t.amount - t.discount) desc, sum(public.stamp_qty(t.items)) desc, max(t.confirmed_at) desc)::int as rank,
           p.id, p.full_name, p.phone, p.gender, p.birth_year,
           case when p.birth_year is null then null else extract(year from now())::int - p.birth_year end as age,
           p.stamps, p.free_available,
           count(t.id) as orders,
           sum(public.stamp_qty(t.items))::int as coffees,
           sum(t.amount - t.discount) as revenue,
           sum(t.free_used)::int as free_used,
           max(t.confirmed_at) as last_at,
           (select e ->> 'name' from public.transactions t2, jsonb_array_elements(t2.items) e
             where t2.user_id = p.id and t2.status = 'confirmed' and t2.confirmed_at >= v_from
               and coalesce((e ->> 'stamp')::boolean, false)
             group by 1 order by sum((e ->> 'qty')::int) desc limit 1) as favorite
      from public.transactions t
      join public.profiles p on p.id = t.user_id and p.role = 'customer'
     where t.status = 'confirmed' and t.type = 'stamp' and t.confirmed_at >= v_from
     group by p.id
     order by 1
     limit least(greatest(coalesce(p_limit, 10), 1), 100)) r);
end $$;

revoke all on function public.admin_top_customers(int, int) from public, anon;
grant execute on function public.admin_top_customers(int, int) to authenticated;
