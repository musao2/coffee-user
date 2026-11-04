-- =====================================================================
--  KOFEXONA VA KASSIR QO'SHISH (admin uchun)
-- =====================================================================

-- 1) Kofexona qo'shish (cashback_percent = mijozga qaytadigan foiz)
insert into public.cafes (name, address, cashback_percent)
values ('Coffeegram — Chilonzor', 'Toshkent, Chilonzor 9-kvartal', 5);

-- 2) Kassir akkaunti:
--    a) Supabase → Authentication → Users → "Add user" → "Create new user"
--       Email: kassir1@beanback.uz, Parol: ..., "Auto Confirm User" ✅
--    b) Keyin shu so'rov bilan uni kassir qilib, kofexonaga biriktiring:

update public.profiles
   set role = 'cashier',
       full_name = 'Kassir 1',
       cafe_id = (select id from public.cafes where name = 'Coffeegram — Chilonzor' limit 1)
 where id = (select id from auth.users where email = 'kassir1@beanback.uz');

-- Cashback foizini o'zgartirish:
-- update public.cafes set cashback_percent = 7 where name = 'Coffeegram — Chilonzor';

-- Kofexonani vaqtincha o'chirish:
-- update public.cafes set is_active = false where name = '...';
