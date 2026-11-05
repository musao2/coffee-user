import { LuCoffee, LuGift } from 'react-icons/lu'

// Kofe kartochkasi: 9 ta katak (shtamp) + 10-chisi bepul
export default function StampCard({ stamps = 0, goal = 9, free = 0, compact = false, title = 'Kofe kartochkasi' }) {
  const left = Math.max(0, goal - stamps)
  return (
    <section className={`stampcard ${compact ? 'compact' : ''}`}>
      <img src="/logo-mark-white.png" alt="" className="bg-mark" />
      <div className="stampcard-top">
        <span>{title}</span>
        {free > 0
          ? <span className="tag free"><LuGift size={13} /> {free} ta bepul kofe</span>
          : <span className="tag">{stamps}/{goal}</span>}
      </div>
      <div className="stamps" style={{ '--n': goal + 1 }} aria-label={`${stamps} / ${goal} shtamp`}>
        {Array.from({ length: goal }, (_, i) => (
          <span key={i} className={`stamp ${i < stamps ? 'on' : ''}`}>{i < stamps ? <LuCoffee size={compact ? 16 : 19} /> : i + 1}</span>
        ))}
        <span className={`stamp gift ${free > 0 ? 'on' : ''}`}><LuGift size={compact ? 16 : 20} /></span>
      </div>
      {!compact && (
        <p className="stampcard-hint">
          {free > 0 ? 'Bepul kofeingiz tayyor! Keyingi xaridda kassadagi QR’ni skanerlang.'
            : left === goal ? `${goal} ta kofe oling — 10-chisi bepul`
            : `Bepul kofegacha yana ${left} ta kofe`}
        </p>
      )}
    </section>
  )
}
