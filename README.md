# Coffeegram — kofexonalar uchun kofe kartochkasi

Mijoz kofe oladi → kassir menyudan buyurtmani kiritadi → QR chiqadi (kassada, mijoz ekranida yoki chekda) →
mijoz telefonidan skanerlaydi → buyurtmadagi **har bir kofe = 1 shtamp**. **9 shtamp = 10-kofe bepul.**
Bepul kofe keyingi xaridda ishlatiladi (buyurtmadagi eng qimmat kofe chegirma qilinadi).
Mijoz qaysi kofelarni necha marta olganini ko'radi. Admin hamma narsani jonli kuzatadi.

## Uchta alohida ilova (bitta Supabase bazasi)

| Ilova | Papka | Lokal manzil | Kim uchun | Tavsiya domen |
| --- | --- | --- | --- | --- |
| **Mijoz** (shu papka) | `coffee-cashback` | http://localhost:5173 | mijozlar | `coffeegram.uz` |
| Kassa + QR ekran | `coffee-kassa` | http://localhost:5182 | kassirlar | `kassa.coffeegram.uz` |
| Admin panel | `coffee-admin` | http://localhost:5181 | administrator | `admin.coffeegram.uz` |

Har bir ilova faqat o'z rolidagi akkauntni kiritadi (mijoz / kassir / admin).
**Backend (SQL) shu papkada:** `supabase/`.

## 1. Supabase (backend)

1. [supabase.com](https://supabase.com) → loyiha → **SQL Editor**. Fayllarni **shu tartibda** ishga tushiring
   (har birini qayta ishga tushirish xavfsiz):
   1. `supabase/schema.sql` — jadvallar, xavfsizlik, kassa funksiyalari
   2. `supabase/02_admin.sql` — admin, menyu, cheklar
   3. `supabase/03_qr_no_expiry.sql` — QR vaqtsiz, QR'li chek
   4. `supabase/04_activity.sql` — jonli faoliyat jurnali (admin "Jonli" bo'limi)
   5. `supabase/05_staff_credentials.sql` — admin xodimning email va parolini o'zgartiradi
   6. `supabase/06_stamps.sql` — kofe kartochkasi (cashback o'rniga: 9 ta kofe → 10-chisi bepul)
   7. `supabase/07_expenses.sql` — kunlik xarajatlar (izoh majburiy) va kassir xato chekni bekor qilishi
   8. `supabase/08_categories.sql` — menyu kategoriyalari (admin qo'shadi, tartiblaydi, yashiradi)
   9. `supabase/09_sold.sql` — "Keyingi buyurtma" ham sotuv sifatida hisoblanadi (mijoz keyin skanerlasa ham shtamp oladi)
   10. `supabase/10_demographics.sql` — mijoz jinsi va yoshi + admin statistikasi
2. **Authentication → Sign In / Providers → Email** → **Confirm email** ni **o'chiring**.
3. **Authentication → URL Configuration** → **Site URL** = mijoz ilovasi domeni (masalan `https://coffeegram.uz`).
4. **Project Settings → API** → `Project URL` va `anon public` kalit — uchala ilovaning `.env` fayliga.

### Birinchi admin
Authentication → Users → **Add user** (`admin@coffeegram.uz` + parol, ✅ Auto Confirm User), keyin SQL:
```sql
update public.profiles set role = 'admin', full_name = 'Admin'
 where id = (select id from auth.users where email = 'admin@coffeegram.uz');
```
Qolgan hammasi (kofexonalar, kassirlar, menyu, cashback foizi) — **admin paneldan**.

## Telegram bot (@COFFEEGRAMURGUTBOT)

QR oddiy kamera bilan skanerlansa — Telegram bot ochiladi va shtamp bot ichida olinadi.
Sozlash: **[TELEGRAM.md](TELEGRAM.md)** (BotFather'da Mini App yoqish + Vercel'da `VITE_TELEGRAM_BOT`).

## 2. Lokal ishga tushirish

```bash
cp .env.example .env   # URL va anon kalit
npm install
npm run dev            # http://localhost:5173
```
Kamera faqat **HTTPS** yoki `localhost` da ishlaydi — telefonda sinash uchun deploy qiling.

## 3. Deploy (Vercel — tavsiya)

Har bir papkani **alohida loyiha** sifatida joylang:

1. Kodni GitHub'ga yuklang (har bir papka alohida repo yoki bitta repo ichida alohida papka).
2. [vercel.com](https://vercel.com) → **Add New → Project** → repo'ni tanlang.
   Bitta repo bo'lsa **Root Directory** = `coffee-cashback` / `coffee-kassa` / `coffee-admin`.
3. **Environment Variables**:

   | O'zgaruvchi | Mijoz | Kassa | Admin |
   | --- | --- | --- | --- |
   | `VITE_SUPABASE_URL` | ✅ | ✅ | ✅ |
   | `VITE_SUPABASE_ANON_KEY` | ✅ | ✅ | ✅ |
   | `VITE_CUSTOMER_URL` (mijoz sayti, masalan `https://coffeegram.uz`) | — | ✅ **majburiy** | ✅ |

4. **Deploy**. `vercel.json` (SPA marshrutlar, kesh) tayyor. Netlify uchun `netlify.toml` ham bor.
5. Domenlarni ulang (Vercel → Settings → Domains).

> `VITE_CUSTOMER_URL` noto'g'ri bo'lsa, kassadagi QR'lar `localhost` ga olib boradi — albatta mijoz domenini yozing.

## Telefon uchun

- Uchala ilova 360px dan boshlab qulay; mijoz ilovasini "Bosh ekranga qo'shish" mumkin (PWA manifest).
- Kassa telefonda: menyu to'liq ekran, pastda "Jami + QR yaratish" paneli; planshetda ikki ustun.
- Admin telefonda: pastki menyu, jadvallar kartalarga aylanadi.

## Xavfsizlik

- Kartochka faqat server funksiyalari orqali o'zgaradi (RLS). Rol faqat admin tomonidan beriladi.
- QR: 48 belgili tasodifiy token, vaqt bilan cheklanmagan, **faqat bir marta** ishlatiladi.
- Shtamp va bepul kofe faqat server funksiyalari orqali o'zgaradi; kassir summani emas, faqat menyudan mahsulot tanlaydi (narxni server hisoblaydi).
- Har bir harakat `activity_log` jurnaliga yoziladi; uni faqat admin o'qiydi, hech kim o'zgartira olmaydi.
# coffee-user
