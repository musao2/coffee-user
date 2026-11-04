import { useEffect, useRef, useState } from 'react'
import { Html5Qrcode } from 'html5-qrcode'

export default function QrScanner({ onResult }) {
  const [error, setError] = useState('')
  const cb = useRef(onResult)
  cb.current = onResult

  useEffect(() => {
    const scanner = new Html5Qrcode('qr-reader', { verbose: false })
    let handled = false
    const started = scanner
      .start(
        { facingMode: 'environment' },
        { fps: 10, qrbox: (w, h) => { const s = Math.floor(Math.min(w, h) * 0.7); return { width: s, height: s } } },
        (text) => {
          if (handled) return
          handled = true
          cb.current(text)
        },
        () => {}
      )
      .catch((e) => {
        setError(
          String(e).includes('Permission')
            ? 'Kameraga ruxsat bering (brauzer sozlamalarida)'
            : 'Kamerani ochib bo‘lmadi. Sayt HTTPS orqali ochilganini tekshiring.'
        )
      })
    return () => {
      started.then(() => scanner.isScanning && scanner.stop()).then(() => scanner.clear()).catch(() => {})
    }
  }, [])

  return (
    <div className="scanner">
      <div id="qr-reader" />
      <div className="scanner-frame" aria-hidden="true"><span /><span /><span /><span /></div>
      <div className="scanner-line" aria-hidden="true" />
      {error && <div className="scanner-error">{error}</div>}
    </div>
  )
}
