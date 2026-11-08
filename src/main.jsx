import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { AuthProvider } from './lib/auth'
import './styles.css'

// Telegram Mini App: bot ichida ochilganda start parametri bo'yicha kerakli sahifaga o'tamiz
// t.me/<bot>?startapp=<token>  → /scan?t=<token>   (buyurtma QR'i)
// t.me/<bot>?startapp=card     → /                  (kofe kartochkasi)
const tg = window.Telegram?.WebApp
if (tg?.initData) {
  try {
    tg.ready()
    tg.expand()
    tg.setHeaderColor?.('#f4eee4')
    tg.setBackgroundColor?.('#f4eee4')
    document.documentElement.classList.add('in-telegram')
  } catch {}
  const start = tg.initDataUnsafe?.start_param || new URLSearchParams(location.search).get('tgWebAppStartParam') || ''
  if (/^[a-f0-9]{48}$/.test(start) && !location.pathname.startsWith('/scan')) {
    history.replaceState(null, '', `/scan?t=${start}`)
  }
}

createRoot(document.getElementById('root')).render(
  <BrowserRouter>
    <AuthProvider>
      <App />
    </AuthProvider>
  </BrowserRouter>
)
