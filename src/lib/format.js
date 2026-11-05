import { useEffect, useState } from 'react'

export const som = (n) =>
  String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ') + " so'm"

export const num = (n) => String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' ')

export const fullDate = (iso) =>
  iso
    ? new Date(iso).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
    : ''

export const typeLabel = { stamp: 'Xarid', cashback: 'Cashback (eski)', spend: 'Balansdan (eski)', adjust: 'Tuzatish' }
export const timeAgo = (iso) => {
  if (!iso) return ''
  const s = Math.max(0, Math.round((Date.now() - new Date(iso)) / 1000))
  if (s < 60) return `${s} soniya oldin`
  if (s < 3600) return `${Math.floor(s / 60)} daqiqa oldin`
  if (s < 86400) return `${Math.floor(s / 3600)} soat oldin`
  return dateTime(iso)
}
export const timeOnly = (iso) => (iso ? new Date(iso).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '')
export const statusLabel = { pending: 'Kutilmoqda', confirmed: 'Tasdiqlangan', expired: 'Muddati o‘tgan', cancelled: 'Bekor', reversed: 'Qaytarilgan' }

export const dateTime = (iso) =>
  iso
    ? new Date(iso).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
    : ''

const ERRORS = {
  NOT_CASHIER: 'Bu akkaunt kassir sifatida biriktirilmagan',
  NOT_CUSTOMER: 'Faqat mijoz akkaunti tasdiqlay oladi',
  NOT_AUTH: 'Avval tizimga kiring',
  BAD_AMOUNT: "Summa noto'g'ri",
  CAFE_INACTIVE: 'Kofexona faol emas',
  NOT_FOUND: 'Topilmadi',
  NOT_ADMIN: 'Bu amal faqat admin uchun',
  CATEGORY_EXISTS: 'Bunday kategoriya allaqachon bor',
  CATEGORY_NOT_EMPTY: 'Kategoriyada mahsulotlar bor — avval ularni boshqa kategoriyaga o‘tkazing',
  NOT_ENOUGH_STAMPS: 'Mijozda yetarli shtamp yo‘q',
  EMAIL_TAKEN: 'Bu email boshqa akkauntda band',
  BAD_EMAIL: 'Email noto‘g‘ri kiritilgan',
  WEAK_PASSWORD: 'Parol kamida 6 ta belgidan iborat bo‘lsin',
  NOT_STAFF: 'Bu amal faqat xodimlar uchun',
  NOTHING_TO_CHANGE: 'O‘zgartirish kiritilmadi',
  BLOCKED: 'Akkaunt bloklangan. Administratorga murojaat qiling',
  BAD_ITEMS: 'Menyudan mahsulot tanlang',
  NOTE_REQUIRED: 'Izoh majburiy: kamida 5 ta belgi yozing',
  ONLY_TODAY: 'Kassir faqat bugungi cheklarni bekor qila oladi. Eskisini admin bekor qiladi',
  NOT_REVERSIBLE: 'Bu tranzaksiyani bekor qilib bo‘lmaydi',
  CAFE_REQUIRED: 'Kassir uchun kofexona tanlang',
  SELF: 'O‘z akkauntingizga bu amalni qo‘llab bo‘lmaydi',
  NAME_REQUIRED: 'Nomini kiriting',
  BAD_PERCENT: 'Foiz 0 dan 50 gacha bo‘lsin',
  EXPIRED: 'QR kod muddati tugagan. Kassirdan yangisini so‘rang',
  ALREADY_USED: 'Bu QR kod allaqachon ishlatilgan',
  CANCELLED: 'Kassir bu to‘lovni bekor qilgan',
  INSUFFICIENT_BALANCE: 'Balansingizda mablag‘ yo‘q',
  'Invalid login credentials': 'Login yoki parol noto‘g‘ri',
  'User already registered': 'Bu raqam allaqachon ro‘yxatdan o‘tgan',
  'Password should be at least': 'Parol kamida 6 ta belgidan iborat bo‘lsin',
  'Failed to fetch': 'Internet aloqasini tekshiring',
}

export const errText = (e) => {
  const m = e?.message || String(e || '')
  for (const k of Object.keys(ERRORS)) if (m.includes(k)) return ERRORS[k]
  return m || 'Xatolik yuz berdi'
}

// Server bergan "qolgan soniya" asosida lokal taymer
export function useCountdown(deadline) {
  const [left, setLeft] = useState(0)
  useEffect(() => {
    if (!deadline) return
    const tick = () => setLeft(Math.max(0, Math.ceil((deadline - Date.now()) / 1000)))
    tick()
    const t = setInterval(tick, 250)
    return () => clearInterval(t)
  }, [deadline])
  return left
}

// QR matnidan tokenni ajratish (URL yoki xom token)
export const extractToken = (text) => {
  let t = (text || '').trim()
  try {
    const u = new URL(t)
    t = u.searchParams.get('t') || ''
  } catch {}
  return /^[a-f0-9]{48}$/.test(t) ? t : null
}
