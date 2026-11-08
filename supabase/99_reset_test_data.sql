-- =====================================================================
--  COFFEEGRAM — TEST MA'LUMOTLARINI TOZALASH (ishga tushirishdan oldin)
--
--  O'CHIRILADI:
--    - barcha cheklar / buyurtmalar / QR'lar (transactions)
--    - barcha xarajatlar (expenses)
--    - jonli lenta / jurnal (activity_log)
--    - mijozlarning shtamplari, bepul kofelari, statistikasi (0 ga tushadi)
--    - chek raqamlari 001000 dan qayta boshlanadi
--
--  TEGILMAYDI:
--    - kassir va admin akkauntlari (login, parol, rol, kofexonasi)
--    - mahsulotlar (menyu, narxlar), kategoriyalar, kofexonalar
--    - barcha funksiyalar, triggerlar, xavfsizlik (RLS)
--    - mijoz akkauntlari — faqat pastdagi 3-QADAM yoqilsa o'chadi
--
--  QAYTARIB BO'LMAYDI. Supabase → SQL Editor da ishga tushiring.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1-QADAM: AVVAL KO'RIB OLING (hech narsa o'chirmaydi)
--   Faqat shu blokni belgilab "Run" bosing — nima o'chishini ko'rasiz.
-- ---------------------------------------------------------------------
select 'O‘CHADI: cheklar / buyurtmalar' as nima, count(*) as soni from public.transactions
union all select 'O‘CHADI: xarajatlar', count(*) from public.expenses
union all select 'O‘CHADI: jonli lenta yozuvlari', count(*) from public.activity_log
union all select 'NOLGA TUSHADI: shtampli mijozlar', count(*) from public.profiles
                where role = 'customer' and (stamps > 0 or free_available > 0 or coffees_total > 0 or balance > 0)
union all select 'QOLADI: adminlar', count(*) from public.profiles where role = 'admin'
union all select 'QOLADI: kassirlar', count(*) from public.profiles where role = 'cashier'
union all select 'QOLADI: mijoz akkauntlari', count(*) from public.profiles where role = 'customer'
union all select 'QOLADI: mahsulotlar', count(*) from public.products
union all select 'QOLADI: kategoriyalar', count(*) from public.categories
union all select 'QOLADI: kofexonalar', count(*) from public.cafes;


-- ---------------------------------------------------------------------
-- 2-QADAM: TOZALASH
--   Hammasi bitta tranzaksiyada: xato bo'lsa hech narsa o'chmaydi.
-- ---------------------------------------------------------------------
begin;

delete from public.activity_log;
delete from public.expenses;
delete from public.transactions;

-- mijozlarning kartochkasi va eski bonus balansi nolga
update public.profiles
   set stamps = 0, free_available = 0, coffees_total = 0, free_total = 0, balance = 0
 where role = 'customer';

-- chek raqamlari yana 001000 dan
alter sequence public.receipt_seq restart with 1000;
select setval('public.activity_log_id_seq', 1, false);

commit;


-- ---------------------------------------------------------------------
-- 3-QADAM (IXTIYORIY): TEST MIJOZ AKKAUNTLARINI HAM O'CHIRISH
--   Kerak bo'lsa: pastdagi 3 qatorning boshidagi "-- " ni olib tashlang va faqat shu blokni ishga tushiring.
--   Faqat role = 'customer' o'chadi. Kassir va admin akkauntlariga TEGMAYDI.
-- ---------------------------------------------------------------------
-- begin;
-- delete from auth.users where id in (select id from public.profiles where role = 'customer');
-- commit;


-- ---------------------------------------------------------------------
-- 4-QADAM: TEKSHIRUV — nima qoldi
-- ---------------------------------------------------------------------
select 'cheklar' as nima, count(*) as soni from public.transactions
union all select 'xarajatlar', count(*) from public.expenses
union all select 'jonli lenta', count(*) from public.activity_log
union all select 'adminlar (qolishi kerak)', count(*) from public.profiles where role = 'admin'
union all select 'kassirlar (qolishi kerak)', count(*) from public.profiles where role = 'cashier'
union all select 'mijozlar', count(*) from public.profiles where role = 'customer'
union all select 'mahsulotlar (qolishi kerak)', count(*) from public.products
union all select 'kategoriyalar (qolishi kerak)', count(*) from public.categories
union all select 'kofexonalar (qolishi kerak)', count(*) from public.cafes;
