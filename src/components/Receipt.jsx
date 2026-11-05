import { QRCodeSVG } from 'qrcode.react'
import { LuPrinter } from 'react-icons/lu'
import { useRpc } from '../lib/useRpc'
import { fullDate, num } from '../lib/format'
import Modal from './Modal'
import { cleanEnv } from '../lib/supabase'

// Mijoz ilovasi manzili (kassa va admin ilovalarida .env orqali beriladi)
export const CUSTOMER_URL = (cleanEnv(import.meta.env.VITE_CUSTOMER_URL) || window.location.origin).replace(/\/+$/, '')

// Chek: termal printer (58/80mm) uchun, window.print() bilan chiqariladi
export function ReceiptPaper({ r, qr }) {
  const pending = r.status === 'pending'
  const stamp = r.type === 'stamp'
  const stampAdjust = r.type === 'adjust' && r.stamps_earned
  const title = pending ? 'BUYURTMA (QR CHEK)'
    : stamp ? 'SAVDO CHEKI'
    : r.type === 'cashback' ? 'SAVDO CHEKI'
    : r.type === 'spend' ? 'BALANS BILAN TO‘LOV'
    : stampAdjust ? 'SHTAMP TUZATISH' : 'BALANS TUZATISH'
  const goal = r.goal || 9
  return (
    <div className="paper">
      {r.status === 'reversed' && <div className="paper-stamp">BEKOR QILINGAN</div>}
      <div className="paper-logo">
        <img src="/logo-mark.png" alt="" />
        <b>COFFEEGRAM</b>
      </div>
      <div className="paper-c"><b>{r.cafe_name}</b></div>
      {r.cafe_address && <div className="paper-c sm">{r.cafe_address}</div>}
      <div className="paper-line" />
      <div className="paper-c"><b>{title}</b></div>
      {!pending && <Row l="Chek №" r={String(r.receipt_no || '—').padStart(6, '0')} />}
      <Row l="Sana" r={fullDate(r.confirmed_at)} />
      {r.cashier_name && <Row l={r.type === 'adjust' ? 'Admin' : 'Kassir'} r={r.cashier_name} />}
      {(r.customer_name || r.customer_phone) && <Row l="Mijoz" r={[r.customer_name, r.customer_phone].filter(Boolean).join(' ')} />}
      <div className="paper-line" />

      {r.items?.length > 0 ? (
        r.items.map((it) => (
          <div key={it.id} className="paper-item">
            <div>{it.name}{it.stamp ? ' ☆' : ''}</div>
            <div className="paper-row"><span>{it.qty} x {num(it.price)}</span><span>{num(it.qty * it.price)}</span></div>
          </div>
        ))
      ) : r.type !== 'adjust' ? (
        <Row l="Buyurtma" r={num(r.amount)} />
      ) : (
        <div className="sm">{r.note}</div>
      )}
      <div className="paper-line" />

      {r.type !== 'adjust' && <Row l={<b>JAMI</b>} r={<b>{num(r.amount)} so‘m</b>} big />}
      {r.free_used && <Row l={`Bepul kofe: ${r.free_item?.name || ''}`} r={`−${num(r.discount)}`} />}
      {r.type === 'spend' && !pending && <Row l="Balansdan" r={`−${num(r.balance_used)}`} />}
      {r.type !== 'adjust' && <Row l={<b>TO‘LOV</b>} r={<b>{num(pending ? r.amount : r.paid_cash)} so‘m</b>} big />}
      {r.type === 'cashback' && <Row l="Cashback" r={`+${num(r.cashback_amount)}`} />}
      {(stamp || stampAdjust) && !pending && <Row l="Shtamp" r={`${r.stamps_earned > 0 ? '+' : ''}${r.stamps_earned}`} />}
      {(stamp || stampAdjust) && !pending && r.stamps_after != null && <Row l="Kartochka" r={`${r.stamps_after}/${goal}${r.free_after ? ` · bepul: ${r.free_after}` : ''}`} />}
      {pending && stamp && <Row l="Shtamp (kofe)" r={`+${r.stamp_qty ?? ''}`} />}
      {r.type === 'adjust' && !stampAdjust && <Row l={<b>O‘zgarish</b>} r={<b>{r.cashback_amount > 0 ? `+${num(r.cashback_amount)}` : `−${num(r.balance_used)}`}</b>} big />}
      {r.status === 'reversed' && r.note && <div className="sm">{r.note}</div>}

      <div className="paper-line" />
      <div className="paper-c sm">☆ — kofe kartochkasiga shtamp · {goal} ta kofe = 1 bepul</div>
      {qr?.value && (
        <div className="paper-qr">
          {qr.title && <div className="paper-c"><b>{qr.title}</b></div>}
          <QRCodeSVG value={qr.value} size={150} level="M" includeMargin={false} />
          {qr.label && <div className="paper-c sm">{qr.label}</div>}
        </div>
      )}
      <div className="paper-c sm">Rahmat! Yana kutib qolamiz</div>
    </div>
  )
}

function Row({ l, r, big }) {
  return <div className={`paper-row ${big ? 'big' : ''}`}><span>{l}</span><span>{r}</span></div>
}

export default function ReceiptModal({ id, onClose, actions }) {
  const { data, error, loading } = useRpc('get_receipt', { p_id: id }, [id])
  return (
    <Modal title="Chek" onClose={onClose}>
      {loading && <div className="skeleton"><div /><div /></div>}
      {error && <div className="alert err">{error}</div>}
      {data && (
        <>
          <div className="print-area">
            <ReceiptPaper r={data} qr={{ value: CUSTOMER_URL, label: 'Skanerlang: kofe kartochkangiz va cheklaringiz' }} />
          </div>
          <div className="modal-actions">
            <button className="btn btn-primary" onClick={() => window.print()}><LuPrinter size={18} /> Chop etish</button>
            {actions?.(data)}
            <button className="btn btn-ghost" onClick={onClose}>Yopish</button>
          </div>
        </>
      )}
    </Modal>
  )
}

// Hali tasdiqlanmagan QR'ni chekda chop etish (mijoz keyinroq skanerlaydi)
export function PendingReceiptModal({ r, qrValue, onClose }) {
  return (
    <Modal title="QR chek" onClose={onClose}>
      <div className="print-area">
        <ReceiptPaper r={r} qr={{ value: qrValue, title: 'SHTAMP OLISH UCHUN SKANERLANG', label: 'Bir marta ishlatiladi · Coffeegram' }} />
      </div>
      <div className="modal-actions">
        <button className="btn btn-primary" onClick={() => window.print()}><LuPrinter size={18} /> Chop etish</button>
        <button className="btn btn-ghost" onClick={onClose}>Yopish</button>
      </div>
    </Modal>
  )
}
