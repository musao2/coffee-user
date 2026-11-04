import { Mark } from './Logo'

export default function Splash({ text = 'Yuklanmoqda…' }) {
  return (
    <div className="splash">
      <Mark size={72} className="spin-logo" />
      <p>{text}</p>
    </div>
  )
}
