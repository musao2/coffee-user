export default function Stat({ icon: Icon, label, value, hint, dark, wide }) {
  return (
    <div className={`stat ${dark ? 'dark' : ''} ${wide ? 'wide' : ''}`}>
      <div className="stat-top">{Icon && <Icon size={16} />}<span>{label}</span></div>
      <b className="num">{value}</b>
      {hint && <em>{hint}</em>}
    </div>
  )
}
