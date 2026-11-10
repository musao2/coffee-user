import { useState } from 'react'
import { LuAlertCircle, LuCheck } from 'react-icons/lu'
import { supabase } from '../lib/supabase'
import { errText } from '../lib/format'
import { useAuth } from '../lib/auth'
import ProfileFields, { joinDate, splitDate } from './ProfileFields'

// Jinsi yoki to'liq tug'ilgan kuni kiritilmagan mijozlar uchun: to'ldirmaguncha yopilmaydi
export default function CompleteProfile() {
  const { profile, refreshProfile } = useAuth()
  const [name, setName] = useState(profile.full_name || '')
  const [gender, setGender] = useState(profile.gender || '')
  // eski mijozda faqat yil bo'lsa — yilni oldindan tanlab qo'yamiz, kun va oyni o'zi tanlaydi
  const [birth, setBirth] = useState(profile.birth_date ? splitDate(profile.birth_date) : { y: profile.birth_year ? String(profile.birth_year) : '', m: '', d: '' })
  const birthDate = joinDate(birth)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const submit = async (e) => {
    e.preventDefault()
    if (!gender) return setError('Jinsingizni tanlang')
    if (!birthDate) return setError('Tug‘ilgan kuningizni to‘liq tanlang (kun, oy, yil)')
    setBusy(true); setError('')
    const { error } = await supabase.rpc('update_my_birth', { p_full_name: name, p_gender: gender, p_birth_date: birthDate })
    setBusy(false)
    if (error) return setError(errText(error))
    refreshProfile()
  }

  return (
    <div className="modal-back">
      <div className="modal" role="dialog" aria-modal="true" aria-label="Ma’lumotlaringizni to‘ldiring">
        <form className="form" onSubmit={submit}>
          <div>
            <h3 style={{ fontSize: 20 }}>Ma’lumotlaringizni to‘ldiring</h3>
            <p className="muted small" style={{ marginTop: 6 }}>Bir marta so‘raladi — sizga mos aksiyalar va takliflar uchun.</p>
          </div>
          <label className="field"><span>Ismingiz</span><input value={name} onChange={(e) => setName(e.target.value)} placeholder="Ismingiz" /></label>
          <ProfileFields gender={gender} setGender={setGender} birth={birth} setBirth={setBirth} />
          {error && <div className="alert err"><LuAlertCircle size={18} />{error}</div>}
          <button className="btn btn-primary btn-lg btn-block" disabled={busy || !gender || !birthDate}><LuCheck size={19} /> {busy ? 'Saqlanmoqda…' : 'Saqlash'}</button>
        </form>
      </div>
    </div>
  )
}
