import { useEffect, useState } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { LuAlertCircle, LuArrowRight, LuInfo, LuSend } from 'react-icons/lu'
import { phoneToEmail, supabase } from '../lib/supabase'
import { errText } from '../lib/format'
import { useAuth } from '../lib/auth'
import { Mark } from '../components/Logo'
import ProfileFields, { joinDate } from '../components/ProfileFields'
import PasswordInput from '../components/PasswordInput'

export default function Login() {
  const [mode, setMode] = useState('login')
  const [phone, setPhone] = useState('')
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [gender, setGender] = useState('')
  const [birth, setBirth] = useState({ y: '', m: '', d: '' })
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [info, setInfo] = useState('')
  const navigate = useNavigate()
  const location = useLocation()
  const { session, profile } = useAuth()
  const from = location.state?.from
  const target = from ? from.pathname + (from.search || '') : '/'

  useEffect(() => {
    if (session && profile) navigate(target, { replace: true })
  }, [session, profile])

  // Telegram ichida: raqamni bir bosishda olish (foydalanuvchi ruxsat bersa)
  const tg = window.Telegram?.WebApp
  const canAskPhone = !!(tg?.initData && tg.requestContact)
  const askPhone = () => {
    try {
      tg.requestContact((ok, res) => {
        const num = String(res?.responseUnsafe?.contact?.phone_number || '').replace(/\D/g, '')
        if (ok && num) setPhone(num.slice(-9))
        if (ok && res?.responseUnsafe?.contact?.first_name && !name) setName(res.responseUnsafe.contact.first_name)
      })
    } catch {}
  }

  const digits = phone.replace(/\D/g, '').slice(0, 9)
  const pretty = digits.replace(/^(\d{0,2})(\d{0,3})(\d{0,2})(\d{0,2}).*/, (_, a, b, c, d) => [a, b, c, d].filter(Boolean).join(' '))

  const submit = async (e) => {
    e.preventDefault()
    setError(''); setInfo('')
    if (digits.length !== 9) return setError('Telefon raqamni to‘liq kiriting')
    if (password.length < 6) return setError('Parol kamida 6 ta belgidan iborat bo‘lsin')
    if (mode === 'register' && !gender) return setError('Jinsingizni tanlang')
    const birthDate = joinDate(birth)
    if (mode === 'register' && !birthDate) return setError('Tug‘ilgan kuningizni to‘liq tanlang (kun, oy, yil)')
    const fullPhone = '+998' + digits
    setBusy(true)
    const email = phoneToEmail(fullPhone)
    const res = mode === 'login'
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({ email, password, options: { data: { phone: fullPhone, full_name: name.trim(), gender, birth_date: birthDate, birth_year: Number(birth.y) } } })
    setBusy(false)
    if (res.error) return setError(errText(res.error))
    if (mode === 'register' && !res.data.session) setInfo('Supabase’da "Confirm email" o‘chirilmagan. README’ga qarang.')
  }

  return (
    <div className="auth">
      <div className="auth-hero">
        <div className="rays" aria-hidden="true" />
        <Mark size={120} light className="mark" />
        <h1>Coffeegram</h1>
        <p>Kofe kartochkasi: 9 ta kofe oling — 10-chisi bepul.</p>
      </div>

      <form className="auth-card" onSubmit={submit}>
        <div className="seg">
          <button type="button" className={mode === 'login' ? 'on' : ''} onClick={() => setMode('login')}>Kirish</button>
          <button type="button" className={mode === 'register' ? 'on' : ''} onClick={() => setMode('register')}>Ro‘yxatdan o‘tish</button>
        </div>

        {mode === 'register' && (
          <label className="field">
            <span>Ismingiz</span>
            <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Masalan, Aziza" autoComplete="given-name" required />
          </label>
        )}
        {mode === 'register' && <ProfileFields gender={gender} setGender={setGender} birth={birth} setBirth={setBirth} />}
        {canAskPhone && (
          <button type="button" className="btn btn-outline btn-block" onClick={askPhone}><LuSend size={17} /> Raqamni Telegram’dan olish</button>
        )}
        <label className="field">
          <span>Telefon raqam</span>
          <div className="phone-input">
            <b>+998</b>
            <input className="input" inputMode="numeric" autoComplete="tel-national" value={pretty} onChange={(e) => setPhone(e.target.value)} placeholder="90 123 45 67" />
          </div>
        </label>
        <label className="field">
          <span>Parol</span>
          <PasswordInput autoComplete={mode === 'login' ? 'current-password' : 'new-password'} value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Kamida 6 belgi" />
        </label>

        {error && <div className="alert err"><LuAlertCircle size={18} />{error}</div>}
        {info && <div className="alert"><LuInfo size={18} />{info}</div>}

        <button className="btn btn-primary btn-lg btn-block" disabled={busy}>
          {busy ? 'Kuting…' : mode === 'login' ? 'Kirish' : 'Akkaunt yaratish'} {!busy && <LuArrowRight size={18} />}
        </button>
        <p className="auth-foot">Ro‘yxatdan o‘tish bepul. Kartochka barcha Coffeegram kofexonalarida ishlaydi.</p>
      </form>
    </div>
  )
}
