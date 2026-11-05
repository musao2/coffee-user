import { useState } from 'react'
import { LuAlertCircle } from 'react-icons/lu'
import Modal from './Modal'

export const MIN_NOTE = 5

// Sabab/izoh so'raydigan oyna: izohsiz (kamida 5 belgi) tasdiqlab bo'lmaydi
export default function ReasonModal({ title, text, label = 'Sabab (majburiy)', placeholder, confirmText = 'Tasdiqlash', danger, onConfirm, onClose }) {
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const len = note.trim().length
  const ok = len >= MIN_NOTE

  const submit = async (e) => {
    e.preventDefault()
    if (!ok) return setError(`Izoh kamida ${MIN_NOTE} ta belgidan iborat bo‘lsin`)
    setBusy(true); setError('')
    try { await onConfirm(note.trim()) } catch (err) { setError(err.message); setBusy(false) }
  }

  return (
    <Modal title={title} onClose={onClose}>
      <form className="form" onSubmit={submit}>
        {text && <div className="alert warn"><LuAlertCircle size={18} />{text}</div>}
        <label className="field"><span>{label}</span>
          <textarea className="input textarea" rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder={placeholder} autoFocus required />
          <small className={`note-count ${ok ? 'ok' : ''}`}>{ok ? 'Izoh yozildi' : `Yana ${MIN_NOTE - len} ta belgi yozing`}</small>
        </label>
        {error && <div className="alert err"><LuAlertCircle size={18} />{error}</div>}
        <button className={`btn ${danger ? 'btn-danger' : 'btn-primary'} btn-lg btn-block`} disabled={busy || !ok}>{busy ? 'Saqlanmoqda…' : confirmText}</button>
      </form>
    </Modal>
  )
}
