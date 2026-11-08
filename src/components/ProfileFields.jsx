// Jins va tug'ilgan yil maydonlari (ro'yxatdan o'tish va profilni to'ldirish uchun)
const THIS_YEAR = new Date().getFullYear()
export const YEARS = Array.from({ length: THIS_YEAR - 5 - 1930 + 1 }, (_, i) => THIS_YEAR - 5 - i) // eng yangisi tepada
export const ageOf = (y) => (y ? THIS_YEAR - Number(y) : null)

export default function ProfileFields({ gender, setGender, birthYear, setBirthYear }) {
  return (
    <>
      <div className="field">
        <span>Jinsingiz</span>
        <div className="seg big">
          <button type="button" className={gender === 'male' ? 'on' : ''} onClick={() => setGender('male')}>Erkak</button>
          <button type="button" className={gender === 'female' ? 'on' : ''} onClick={() => setGender('female')}>Ayol</button>
        </div>
      </div>
      <label className="field">
        <span>Tug‘ilgan yilingiz {birthYear && <b className="muted">· {ageOf(birthYear)} yosh</b>}</span>
        <select value={birthYear} onChange={(e) => setBirthYear(e.target.value)} required>
          <option value="">Tanlang</option>
          {YEARS.map((y) => <option key={y} value={y}>{y}</option>)}
        </select>
      </label>
    </>
  )
}
