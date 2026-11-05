import { useEffect, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { LuAlertCircle, LuCheck, LuChevronLeft, LuCoffee, LuFrown, LuGift, LuPartyPopper, LuReceipt, LuRefreshCw, LuStore } from 'react-icons/lu'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { errText, extractToken, som } from '../lib/format'
import QrScanner from '../components/QrScanner'
import ReceiptModal from '../components/Receipt'
import StampCard from '../components/StampCard'

export default function Scan() {
  const [params, setParams] = useSearchParams()
  const token = params.get('t')
  const [preview, setPreview] = useState(null)
  const [useFree, setUseFree] = useState(true)
  const [result, setResult] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [showReceipt, setShowReceipt] = useState(false)
  const { refreshProfile } = useAuth()
  const navigate = useNavigate()

  useEffect(() => {
    if (!token) return
    setError(''); setPreview(null)
    supabase.rpc('preview_order', { p_token: token }).then(({ data, error }) => {
      if (error) setError(errText(error))
      else { setPreview(data); setUseFree(true) }
    })
  }, [token])

  const onScan = (text) => {
    const t = extractToken(text)
    if (!t) return setError('Bu Coffeegram QR kodi emas')
    setParams({ t }, { replace: true })
  }

  const confirm = async () => {
    setBusy(true); setError('')
    const { data, error } = await supabase.rpc('confirm_order', { p_token: token, p_use_free: !!(preview?.can_use_free && useFree) })
    setBusy(false)
    if (error) return setError(errText(error))
    setResult(data)
    refreshProfile()
  }

  const rescan = () => { setError(''); setPreview(null); setParams({}, { replace: true }) }
  const status = preview?.status
  const applyFree = preview?.can_use_free && useFree
  const freePrice = applyFree ? Number(preview.free_item?.price || 0) : 0
  const earn = (preview?.stamp_qty || 0) - (applyFree ? 1 : 0)

  if (result) {
    return (
      <div className="app">
        <div className="result">
          <div className="result-ico">{result.new_rewards > 0 ? <LuPartyPopper size={46} /> : <LuCheck size={48} strokeWidth={3} />}</div>
          {result.new_rewards > 0 ? (
            <><h1>Tabriklaymiz!</h1><p className="muted">Bepul kofe yutdingiz — keyingi xaridda ishlating.</p></>
          ) : (
            <><h1 className="num">+{result.stamps_earned} shtamp</h1><p className="muted">kartochkangizga qo‘shildi. Yoqimli ishtaha!</p></>
          )}
          {result.free_used && <div className="alert ok"><LuGift size={18} />{result.free_item?.name} bepul bo‘ldi: −{som(result.discount)}</div>}
          <div className="pill">To‘lov: <b>{som(result.to_pay)}</b></div>
        </div>
        <div style={{ marginTop: 16 }}><StampCard stamps={result.stamps} free={result.free_available} goal={result.goal} /></div>
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
              <div key={it.id} className="ticket-row item">
                <span>{it.qty} × {it.name} {it.stamp && <LuCoffee size={13} style={{ verticalAlign: -2, color: 'var(--caramel)' }} />}</span>
                <span className="num">{som(it.qty * it.price)}</span>
              </div>
            ))}
            <div className="ticket-row"><span>Jami</span><b className="num">{som(preview.amount)}</b></div>

            {preview.can_use_free && status === 'pending' && (
              <label className={`free-toggle ${useFree ? 'on' : ''}`}>
                <input type="checkbox" checked={useFree} onChange={(e) => setUseFree(e.target.checked)} />
                <LuGift size={22} />
                <span className="grow"><b>Bepul kofeni ishlatish</b><small>{preview.free_item?.name} — {som(preview.free_item?.price)} · sizda {preview.free_available} ta</small></span>
              </label>
            )}
            {applyFree && <div className="ticket-row hl coffee"><span>Bepul kofe</span><b className="num">−{som(freePrice)}</b></div>}
            <div className="ticket-row hl"><span>Kartochkaga</span><b className="num">+{Math.max(0, earn)} shtamp</b></div>
            <div className="ticket-row"><span><b>To‘lov</b></span><b className="num">{som(preview.amount - freePrice)}</b></div>

            {status !== 'pending' && (
              <div className="alert err"><LuAlertCircle size={18} />
                {status === 'confirmed' && 'Bu QR kod allaqachon ishlatilgan.'}
                {status === 'cancelled' && 'Kassir bu buyurtmani bekor qilgan.'}
                {status === 'reversed' && 'Bu buyurtma bekor qilingan.'}
                {status === 'expired' && 'Bu QR kod endi amal qilmaydi.'}
              </div>
            )}
          </div>
          <div style={{ marginTop: 12 }}><StampCard compact stamps={preview.stamps} free={preview.free_available} goal={preview.goal} title="Hozirgi kartochkangiz" /></div>
          <div className="fab-bar">
            <div className="stack" style={{ maxWidth: 488, margin: '0 auto' }}>
              {status === 'pending' && (
                <button className="btn btn-primary btn-lg btn-block" onClick={confirm} disabled={busy}>
                  <LuCheck size={20} /> {busy ? 'Tasdiqlanmoqda…' : applyFree ? 'Bepul kofe bilan tasdiqlash' : 'Shtampni olish'}
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
