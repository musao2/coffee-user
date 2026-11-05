import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { LuAlertCircle, LuCoffee, LuGift, LuLogOut, LuQrCode, LuReceipt, LuScanLine, LuSlidersHorizontal, LuStar } from 'react-icons/lu'
import { supabase } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { dateTime, num, som } from '../lib/format'
import { Brand } from '../components/Logo'
import StampCard from '../components/StampCard'
import ReceiptModal from '../components/Receipt'

const GOAL = 9

export default function Home() {
  const { profile, refreshProfile, signOut } = useAuth()
  const [history, setHistory] = useState(null)
  const [receiptId, setReceiptId] = useState(null)
  const [tab, setTab] = useState('coffees')

  useEffect(() => {
    refreshProfile()
    supabase
      .from('transactions')
      .select('id, type, status, receipt_no, note, amount, discount, free_used, stamps_earned, cashback_amount, balance_used, items, confirmed_at, cafe:cafes(name)')
      .eq('user_id', profile.id)
      .in('status', ['confirmed', 'reversed'])
      .order('confirmed_at', { ascending: false })
      .limit(100)
      .then(({ data }) => setHistory(data || []))
  }, [])

  // Qaysi kofeni necha marta olgan
  const coffees = useMemo(() => {
    const m = new Map()
    for (const h of history || []) {
      if (h.status !== 'confirmed') continue
      for (const it of h.items || []) {
        const cur = m.get(it.name) || { name: it.name, qty: 0, stamp: it.stamp, last: h.confirmed_at }
        cur.qty += it.qty
        m.set(it.name, cur)
      }
    }
    return [...m.values()].sort((a, b) => b.qty - a.qty)
  }, [history])
  const maxQty = coffees[0]?.qty || 1

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

      <StampCard stamps={profile.stamps || 0} free={profile.free_available || 0} goal={GOAL} />

      <section className="mini-stats">
        <div><LuCoffee size={18} /><b className="num">{profile.coffees_total || 0}</b><span>kofe ichildi</span></div>
        <div><LuGift size={18} /><b className="num">{profile.free_total || 0}</b><span>bepul olindi</span></div>
        <div><LuStar size={18} /><b>{coffees.find((c) => c.stamp)?.name || '—'}</b><span>sevimli kofe</span></div>
      </section>

      <div className="seg" style={{ marginTop: 18 }}>
        <button className={tab === 'coffees' ? 'on' : ''} onClick={() => setTab('coffees')}><LuCoffee size={16} /> Kofelarim</button>
        <button className={tab === 'history' ? 'on' : ''} onClick={() => setTab('history')}><LuReceipt size={16} /> Xaridlar</button>
      </div>

      {history === null && <div className="skeleton" style={{ marginTop: 12 }}><div /><div /><div /></div>}

      {history && tab === 'coffees' && (
        coffees.length === 0 ? (
          <div className="empty" style={{ marginTop: 12 }}><LuCoffee size={36} />Hali kofe olmadingiz. Kassada QR’ni skanerlang — har bir kofe kartochkaga shtamp bo‘ladi.</div>
        ) : (
          <ul className="list" style={{ marginTop: 12 }}>
            {coffees.map((c) => (
              <li key={c.name} className="list-item coffee-row">
                <span className={`list-ico ${c.stamp ? 'dark' : ''}`}><LuCoffee size={18} /></span>
                <span className="list-main">
                  <b>{c.name}</b>
                  <span className="bar"><i style={{ width: `${(c.qty / maxQty) * 100}%` }} /></span>
                </span>
                <span className="list-end"><span className="num">{c.qty} ta</span>{!c.stamp && <small>shtampsiz</small>}</span>
              </li>
            ))}
          </ul>
        )
      )}

      {history && tab === 'history' && (
        history.length === 0 ? (
          <div className="empty" style={{ marginTop: 12 }}><LuReceipt size={36} />Hali xarid yo‘q</div>
        ) : (
          <ul className="list" style={{ marginTop: 12 }}>
            {history.map((h) => {
              const adjust = h.type === 'adjust'
              const legacy = h.type === 'cashback' || h.type === 'spend'
              const items = (h.items || []).map((i) => `${i.qty}× ${i.name}`).join(', ')
              return (
                <li key={h.id}>
                  <button className={`list-item ${h.status === 'reversed' ? 'dim' : ''}`} onClick={() => setReceiptId(h.id)}>
                    <span className={`list-ico ${h.free_used ? 'coffee' : 'green'}`}>{adjust ? <LuSlidersHorizontal size={18} /> : h.free_used ? <LuGift size={18} /> : <LuCoffee size={18} />}</span>
                    <span className="list-main">
                      <b>{adjust ? (h.stamps_earned ? 'Shtamp tuzatish' : 'Bonus tuzatish') : h.cafe?.name || 'Kofexona'}</b>
                      <small>{dateTime(h.confirmed_at)} · {adjust ? h.note : items || `chek ${som(h.amount)}`}</small>
                    </span>
                    <span className="list-end">
                      {h.type === 'stamp' || h.stamps_earned ? (
                        <span className="num pos" style={h.status === 'reversed' ? { textDecoration: 'line-through' } : null}>
                          {h.stamps_earned > 0 ? '+' : ''}{h.stamps_earned} <LuCoffee size={13} />
                        </span>
                      ) : legacy ? <span className="num muted">{som(h.amount)}</span> : null}
                      <small>{h.status === 'reversed' ? 'bekor qilingan' : h.free_used ? 'bepul kofe' : h.type === 'stamp' ? som(h.amount - (h.discount || 0)) : ''}</small>
                    </span>
                  </button>
                </li>
              )
            })}
          </ul>
        )
      )}

      <div className="fab-bar">
        <Link to="/scan" className="btn btn-primary btn-lg btn-block"><LuScanLine size={22} /> QR kodni skanerlash</Link>
      </div>
      {receiptId && <ReceiptModal id={receiptId} onClose={() => setReceiptId(null)} />}
    </div>
  )
}
