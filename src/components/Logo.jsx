// Coffeegram logotipi (public/ papkadagi rasmlar)
export function Mark({ size = 40, light = false, className = '', style }) {
  return (
    <img
      src={light ? '/logo-mark-white.png' : '/logo-mark.png'}
      width={size}
      height={Math.round(size * 1.047)}
      alt="Coffeegram"
      className={className}
      style={style}
      draggable="false"
    />
  )
}

export function Brand({ light = false, size = 30, sub }) {
  return (
    <span className="brand" style={{ color: light ? 'var(--paper)' : 'var(--ink)' }}>
      <Mark size={size} light={light} />
      <span>Coffeegram</span>
      {sub && <small>{sub}</small>}
    </span>
  )
}
