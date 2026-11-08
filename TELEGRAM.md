# Telegram bot: QR → @COFFEEGRAMURGUTBOT → shtamp

Mijoz kassadagi (yoki chekdagi) QR'ni **oddiy telefon kamerasi** bilan skanerlaydi →
Telegram ochiladi → **@COFFEEGRAMURGUTBOT** ichida Coffeegram ilovasi (Mini App) ochiladi →
"Shtampni olish" → kartochkaga shtamp tushadi.

QR ichidagi havola: `https://t.me/COFFEEGRAMURGUTBOT?startapp=<buyurtma-tokeni>`

## 1. BotFather'da (bir marta, 2 daqiqa)

Telegram'da **@BotFather** ni oching:

1. `/mybots` → **@COFFEEGRAMURGUTBOT** → **Bot Settings** → **Configure Mini App** → **Enable Mini App**
2. URL so'raganda **mijoz saytingiz manzilini** yuboring (Vercel'dagi `coffee-cashback`, `https://...` bilan),
   masalan `https://coffeegram.vercel.app`
3. (ixtiyoriy) **Bot Settings → Menu Button** → shu URL, nomi: `Kartochkam` —
   mijoz botdagi tugma orqali ham kartochkasini ochadi.

> Mini App yoqilmasa `?startapp=` havolasi ishlamaydi — 1-qadam majburiy.

## 2. Vercel'da

| Loyiha | O'zgaruvchi | Qiymat |
| --- | --- | --- |
| coffee-kassa | `VITE_TELEGRAM_BOT` | `COFFEEGRAMURGUTBOT` |
| coffee-admin | `VITE_TELEGRAM_BOT` | `COFFEEGRAMURGUTBOT` |
| coffee-kassa, coffee-admin | `VITE_CUSTOMER_URL` | mijoz saytingiz (Mini App bilan bir xil) |

Saqlang → **Redeploy**.

## 3. Supabase'da

**Authentication → URL Configuration → Site URL** = mijoz saytingiz.

## Qanday ishlaydi

- Birinchi marta mijoz bot ichida telefon raqami + parol bilan kiradi (yoki ro'yxatdan o'tadi).
  "Raqamni Telegram'dan olish" tugmasi raqamni avtomatik to'ldiradi. Keyingi safar yana kirish shart emas.
- QR → bot → "Tasdiqlash" sahifasi: buyurtma tarkibi, "+N shtamp", bepul kofe bo'lsa — "Bepul kofeni ishlatish".
- Chek pastidagi QR → bot → kofe kartochkasi.
- `VITE_TELEGRAM_BOT` bo'sh bo'lsa, QR'lar avvalgidek mijoz saytiga olib boradi.
