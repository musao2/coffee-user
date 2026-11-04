import { createClient } from '@supabase/supabase-js'

// Env qiymatlarini tozalaymiz: nusxalashda tushib qoladigan bo'sh joy, qator uzilishi,
// ko'rinmas belgilar va qo'shtirnoqlar (masalan Vercel'ga joylashtirganda) brauzer
// "non ISO-8859-1 code point" xatosini beradi.
export const cleanEnv = (v) =>
  String(v || '')
    .replace(/[\u200B-\u200D\uFEFF\u00A0\s]/g, '')
    .replace(/^["'\u201C\u201D\u2018\u2019]+|["'\u201C\u201D\u2018\u2019]+$/g, '')
    .replace(/[^\x21-\x7E]/g, '')

const url = cleanEnv(import.meta.env.VITE_SUPABASE_URL).replace(/\/+$/, '')
const key = cleanEnv(import.meta.env.VITE_SUPABASE_ANON_KEY)

// Konfiguratsiya xatosi bo'lsa — ekranda aniq ko'rsatamiz
export const configError = !url || !key
  ? 'VITE_SUPABASE_URL va VITE_SUPABASE_ANON_KEY kiritilmagan.'
  : !/^https:\/\/[a-z0-9-]+\.supabase\.(co|in)$/.test(url) && !/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(url)
    ? `VITE_SUPABASE_URL noto‘g‘ri: "${url}". To‘g‘ri ko‘rinish: https://xxxx.supabase.co`
    : !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(key) && !/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)
      ? 'VITE_SUPABASE_ANON_KEY noto‘g‘ri yoki to‘liq emas. Supabase → Project Settings → API dan "anon public" kalitni qaytadan nusxalang.'
      : ''

export const supabaseConfigured = !configError

export const supabase = createClient(url || 'http://localhost:54321', key || 'missing-anon-key', {
  auth: { persistSession: true, autoRefreshToken: true },
})

// Telefon raqam → ichki email (SMS provayder ulanmaguncha parol bilan kirish uchun)
export const phoneToEmail = (phone) => `${phone.replace(/\D/g, '')}@phone.beanback.uz`

