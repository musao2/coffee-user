import { Suspense, lazy } from 'react'
import { Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { LuLogOut } from 'react-icons/lu'
import { useAuth } from './lib/auth'
import { configError, supabaseConfigured } from './lib/supabase'
import Splash from './components/Splash'
import { Mark } from './components/Logo'
import Login from './pages/Login'
import Home from './pages/Home'
import CompleteProfile from './components/CompleteProfile'
// Skaner kutubxonasi og'ir — faqat kerak bo'lganda yuklanadi
const Scan = lazy(() => import('./pages/Scan'))

// Bu ilova faqat mijozlar uchun. Kassir va admin o'z ilovalaridan kiradi.
function CustomerOnly({ children }) {
  const { session, profile, ready, signOut } = useAuth()
  const location = useLocation()

  if (!ready) return <Splash />
  if (!session) return <Navigate to="/login" replace state={{ from: location }} />
  if (!profile) return <Splash text="Profil yuklanmoqda…" />
  if (profile.role !== 'customer') {
    return (
      <div className="splash">
        <Mark size={64} />
        <h2>Bu ilova mijozlar uchun</h2>
        <p>Siz xodim akkaunti bilan kirdingiz. Kassir va administratorlar o‘z ilovalaridan foydalanadi.</p>
        <button className="btn btn-primary" onClick={signOut}><LuLogOut size={18} /> Chiqish</button>
      </div>
    )
  }
  return (
    <>
      {children}
      {(!profile.gender || !profile.birth_date) && <CompleteProfile />}
    </>
  )
}

export default function App() {
  if (!supabaseConfigured) {
    return (
      <div className="splash">
        <Mark size={64} />
        <h2>Supabase ulanmagan</h2>
        <p>{configError}</p>
        <p className="muted small">Vercel → Settings → Environment Variables da qiymatni tekshiring va qayta deploy qiling.</p>
      </div>
    )
  }

  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/" element={<CustomerOnly><Home /></CustomerOnly>} />
      <Route path="/scan" element={<CustomerOnly><Suspense fallback={<Splash text="Kamera tayyorlanmoqda…" />}><Scan /></Suspense></CustomerOnly>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
