// Jins va to'liq tug'ilgan sana (kun / oy / yil) maydonlari — ro'yxatdan o'tish va profilni to'ldirish uchun
const THIS_YEAR = new Date().getFullYear()
const MAX_YEAR = Math.min(2025, THIS_YEAR - 5)
export const YEARS = Array.from({ length: MAX_YEAR - 1930 + 1 }, (_, i) => MAX_YEAR - i) // eng yangisi tepada
export const MONTHS = ['Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun', 'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr']
const pad = (n) => String(n).padStart(2, '0')
const daysIn = (y, m) => new Date(Number(y) || 2000, Number(m) || 1, 0).getDate() // yil tanlanmagan bo'lsa 29-fevral ham chiqsin

// "1995-11-12" <-> { y, m, d }
export const splitDate = (s) => {
  const [y = '', m = '', d = ''] = (s || '').split('-')
  return { y, m: m ? String(Number(m)) : '', d: d ? String(Number(d)) : '' }
}
export const joinDate = ({ y, m, d }) => (y && m && d ? `${y}-${pad(m)}-${pad(d)}` : '')

export function ageOf(dateStr) {
  const { y, m, d } = splitDate(dateStr)
  if (!y || !m || !d) return null
  const now = new Date()
  const had = now.getMonth() + 1 > Number(m) || (now.getMonth() + 1 === Number(m) && now.getDate() >= Number(d))
  return now.getFullYear() - Number(y) - (had ? 0 : 1)
}

export default function ProfileFields({ gender, setGender, birth, setBirth }) {
  const max = daysIn(birth.y, birth.m)
  const set = (k, v) => {
    const next = { ...birth, [k]: v }
    const lim = daysIn(next.y, next.m)
    if (next.d && Number(next.d) > lim) next.d = String(lim) // 31-aprel kabi xatolarni tuzatamiz
    setBirth(next)
  }
  const age = ageOf(joinDate(birth))

  return (
    <>
      <div className="field">
        <span>Jinsingiz</span>
        <div className="seg big">
          <button type="button" className={gender === 'male' ? 'on' : ''} onClick={() => setGender('male')}>Erkak</button>
          <button type="button" className={gender === 'female' ? 'on' : ''} onClick={() => setGender('female')}>Ayol</button>
        </div>
      </div>
      <div className="field">
        <span>Tug‘ilgan kuningiz {age !== null && <b className="muted">· {age} yosh</b>}</span>
        <div className="birth-row">
          <select aria-label="Kun" value={birth.d} onChange={(e) => set('d', e.target.value)} required>
            <option value="">Kun</option>
            {Array.from({ length: max }, (_, i) => <option key={i + 1} value={i + 1}>{i + 1}</option>)}
          </select>
          <select aria-label="Oy" value={birth.m} onChange={(e) => set('m', e.target.value)} required>
            <option value="">Oy</option>
            {MONTHS.map((n, i) => <option key={n} value={i + 1}>{n}</option>)}
          </select>
          <select aria-label="Yil" value={birth.y} onChange={(e) => set('y', e.target.value)} required>
            <option value="">Yil</option>
            {YEARS.map((y) => <option key={y} value={y}>{y}</option>)}
          </select>
        </div>
      </div>
    </>
  )
}
