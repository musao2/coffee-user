import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { LuCoffee, LuGift, LuLogOut, LuMinus, LuPlus, LuQrCode, LuReceipt, LuScanLine, LuSlidersHorizontal, LuAlertCircle } from 'react-icons/lu'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { dateTime, num, som } from '../lib/format'
import { Brand } from '../components/Logo'
import ReceiptModal from '../components/Receipt'

export default function Home() {
  const { profile, refreshProfile, signOut } = useAuth()
  const [history, setHistory] = useState(null)
  const [receiptId, setReceiptId] = useState(null)

  useEffect(() => {
    refreshProfile()
    supabase
      .from('transactions')
      .select('id, type, status, receipt_no, note, amount, cashback_amount, balance_used, confirmed_at, cafe:cafes(name)')
      .eq('user_id', profile.id)
      .in('status', ['confirmed', 'reversed'])
      .order('confirmed_at', { ascending: false })
      .limit(50)
      .then(({ data }) => setHistory(data || []))
  }, [])

  const ok = (history || []).filter((h) => h.status === 'confirmed')
  const earned = ok.filter((h) => h.type === 'cashback').reduce((s, h) => s + h.cashback_amount, 0)
  const visits = ok.filter((h) => h.type !== 'adjust').length

  return (
    <div className="app">
      <header className="appbar">
        <Brand size={30} />
        <button className="icon-btn" onClick={signOut} title="Chiqish" aria-label="Chiqish"><LuLogOut size={19} /></button>
      </header>

      {profile.is_active === false && (
        <div className="alert err" style={{ marginBottom: 12 }}><LuAlertCircle size={18} />Akkauntingiz bloklangan. Administratorga murojaat qiling.</div>
      )}
      <p className="hello">Salom, <b>{profile.full_name || 'mehmon'}</b></p>

      <section className="wallet">
        <img src="/logo-mark-white.png" alt="" className="bg-mark" />
        <div className="wallet-top">
          <span>Bonus balans</span>
          <span className="tag">{profile.phone}</span>
        </div>
        <div className="wallet-amount num">{num(profile.balance)} <small>so‘m</small></div>
        <div className="wallet-meta">
          <div><b className="num">{visits}</b><span>tashrif</span></div>
          <div><b className="num">{num(earned)}</b><span>jami cashback</span></div>
        </div>
      </section>

      <section className="steps">
        <div><LuCoffee size={20} /><br />Kofe buyurtma qiling</div>
        <div><LuQrCode size={20} /><br />Kassa yoki chekdagi QR’ni skanerlang</div>
        <div><LuGift size={20} /><br />Bonus bilan keyingisini to‘lang</div>
      </section>

      <h2 className="section-title">Tarix <span className="muted small">{history?.length ? `${history.length} ta` : ''}</span></h2>
      {history === null ? (
        <div className="skeleton"><div /><div /><div /></div>
      ) : history.length === 0 ? (
        <div className="empty"><LuReceipt size={36} />Hali xarid yo‘q. Birinchi kofeingizdan cashback oling!</div>
      ) : (
        <ul className="list">
          {history.map((h) => {
            const plus = h.cashback_amount > 0
            const Icon = h.type === 'adjust' ? LuSlidersHorizontal : plus ? LuPlus : LuMinus
            return (
              <li key={h.id}>
                <button className={`list-item ${h.status === 'reversed' ? 'dim' : ''}`} onClick={() => setReceiptId(h.id)}>
                  <span className={`list-ico ${plus ? 'green' : 'coffee'}`}><Icon size={18} /></span>
                  <span className="list-main">
                    <b>{h.type === 'adjust' ? 'Bonus tuzatish' : h.cafe?.name || 'Kofexona'}</b>
                    <small>{dateTime(h.confirmed_at)} · {h.type === 'adjust' ? h.note : `chek ${som(h.amount)}`}</small>
                  </span>
                  <span className="list-end">
                    <span className={`num ${plus ? 'pos' : 'neg'}`} style={h.status === 'reversed' ? { textDecoration: 'line-through' } : null}>
                      {plus ? `+${num(h.cashback_amount)}` : `−${num(h.balance_used)}`}
                    </span>
                    {h.status === 'reversed' && <small>bekor qilingan</small>}
                  </span>
                </button>
              </li>
            )
          })}
        </ul>
      )}

      <div className="fab-bar">
        <Link to="/scan" className="btn btn-primary btn-lg btn-block"><LuScanLine size={22} /> QR kodni skanerlash</Link>
      </div>
      {receiptId && <ReceiptModal id={receiptId} onClose={() => setReceiptId(null)} />}
    </div>
  )
}
