import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const supabaseConfigured = Boolean(url && key)

export const supabase = createClient(url || 'http://localhost:54321', key || 'missing-anon-key', {
  auth: { persistSession: true, autoRefreshToken: true },
})

// Telefon raqam → ichki email (SMS provayder ulanmaguncha parol bilan kirish uchun)
export const phoneToEmail = (phone) => `${phone.replace(/\D/g, '')}@phone.beanback.uz`

