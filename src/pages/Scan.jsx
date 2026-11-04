import { useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { LuAlertCircle, LuCheck, LuChevronLeft, LuFrown, LuReceipt, LuRefreshCw, LuStore } from 'react-icons/lu'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { errText, extractToken, num, som } from '../lib/format'
import QrScanner from '../components/QrScanner'
import ReceiptModal from '../components/Receipt'

export default function Scan() {
  const [params, setParams] = useSearchParams()
  const token = params.get('t')
  const [preview, setPreview] = useState(null)
  const [result, setResult] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [showReceipt, setShowReceipt] = useState(false)
  const { refreshProfile } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    if (!token) return
    setError(''); setPreview(null)
    supabase.rpc('preview_transaction', { p_token: token }).then(({ data, error }) => {
      if (error) setError(errText(error))
      else setPreview(data)
    })
  }, [token])

  const onScan = (text) => {
    const t = extractToken(text)
    if (!t) return setError('Bu Coffeegram QR kodi emas')
    setParams({ t }, { replace: true })
  }

  const confirm = async () => {
    setBusy(true); setError('')
    const { data, error } = await supabase.rpc('confirm_transaction', { p_token: token })
    setBusy(false)
    if (error) return setError(errText(error))
    setResult(data)
    refreshProfile()
  }

  const rescan = () => { setError(''); setPreview(null); setParams({}, { replace: true }) }
  const status = preview?.status

  if (result) {
    return (
      <div className="app">
        <div className="result">
          <div className="result-ico"><LuCheck size={48} strokeWidth={3} /></div>
          {result.type === 'cashback' ? (
            <>
              <h1 className="num">+{num(result.cashback_amount)} so‘m</h1>
              <p className="muted">balansingizga tushdi. Yoqimli ishtaha!</p>
            </>
          ) : (
            <>
              <h1 className="num">−{num(result.balance_used)} so‘m</h1>
              <p className="muted">balansdan to‘landi</p>
              {result.remaining > 0 && <div className="alert warn">Qolgan <b>&nbsp;{som(result.remaining)}&nbsp;</b> ni kassaga naqd yoki karta bilan to‘lang.</div>}
            </>
          )}
          <div className="pill">Yangi balans: <b>{som(result.balance)}</b></div>
        </div>
        <div className="fab-bar">
          <div className="stack" style={{ maxWidth: 488, margin: '0 auto' }}>
            <button className="btn btn-outline btn-block" onClick={() => setShowReceipt(true)}><LuReceipt size={18} /> Chekni ko‘rish</button>
            <button className="btn btn-primary btn-lg btn-block" onClick={() => navigate('/')}>Bosh sahifa</button>
          </div>
        </div>
        {showReceipt && <ReceiptModal id={result.id} onClose={() => setShowReceipt(false)} />}
      </div>
    )
  }

  return (
    <div className="app">
      <header className="appbar">
        <Link to="/" className="icon-btn" aria-label="Orqaga"><LuChevronLeft size={22} /></Link>
        <h1>{token ? 'Tasdiqlash' : 'Skanerlash'}</h1>
        <span style={{ width: 42 }} />
      </header>

      {!token && (
        <div className="stack">
          <QrScanner onResult={onScan} />
          <p className="muted center">Kassa ekranidagi yoki chekdagi QR kodni ramka ichiga joylang</p>
          {error && <div className="alert err"><LuAlertCircle size={18} />{error}</div>}
        </div>
      )}

      {token && !preview && !error && <div className="skeleton"><div /><div /></div>}

      {token && error && (
        <div className="card stack center">
          <LuFrown size={44} style={{ margin: '0 auto', color: 'var(--muted)' }} />
          <div className="alert err"><LuAlertCircle size={18} />{error}</div>
          <button className="btn btn-primary btn-block" onClick={rescan}><LuRefreshCw size={18} /> Qayta skanerlash</button>
        </div>
      )}

      {preview && !error && (
        <>
          <div className="ticket">
            <div className="ticket-head">
              <span className="list-ico dark"><LuStore size={18} /></span>
              <h2>{preview.cafe_name}</h2>
              {preview.cafe_address && <p className="muted small">{preview.cafe_address}</p>}
            </div>
            {preview.items?.map((it) => (
              <div key={it.id} className="ticket-row item"><span>{it.qty} × {it.name}</span><span className="num">{som(it.qty * it.price)}</span></div>
            ))}
            <div className="ticket-row"><span>Chek summasi</span><b className="num">{som(preview.amount)}</b></div>
            {preview.type === 'cashback' ? (
              <div className="ticket-row hl"><span>Cashback ({Number(preview.cashback_percent)}%)</span><b className="num">+{som(preview.cashback_amount)}</b></div>
            ) : (
              <>
                <div className="ticket-row"><span>Balansingiz</span><b className="num">{som(preview.balance)}</b></div>
                <div className="ticket-row hl coffee"><span>Balansdan yechiladi</span><b className="num">−{som(preview.will_use)}</b></div>
                {preview.amount > preview.will_use && <div className="ticket-row"><span>Naqd / karta bilan</span><b className="num">{som(preview.amount - preview.will_use)}</b></div>}
              </>
            )}
            {status !== 'pending' && (
              <div className="alert err"><LuAlertCircle size={18} />
                {status === 'confirmed' && 'Bu QR kod allaqachon ishlatilgan.'}
                {status === 'cancelled' && 'Kassir bu to‘lovni bekor qilgan.'}
                {status === 'expired' && 'Bu QR kod endi amal qilmaydi.'}
              </div>
            )}
            {status === 'pending' && preview.type === 'spend' && preview.will_use <= 0 && (
              <div className="alert err"><LuAlertCircle size={18} />Balansingizda mablag‘ yo‘q</div>
            )}
          </div>
          <div className="fab-bar">
            <div className="stack" style={{ maxWidth: 488, margin: '0 auto' }}>
              {status === 'pending' && !(preview.type === 'spend' && preview.will_use <= 0) && (
                <button className="btn btn-primary btn-lg btn-block" onClick={confirm} disabled={busy}>
                  <LuCheck size={20} /> {busy ? 'Tasdiqlanmoqda…' : preview.type === 'cashback' ? 'Cashbackni olish' : 'Balansdan to‘lash'}
                </button>
              )}
              <button className="btn btn-ghost btn-block" onClick={rescan}>Bekor qilish</button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
