import { useState } from 'react'
import { LuEye, LuEyeOff } from 'react-icons/lu'

// Parol maydoni: ko'zcha bosilsa yozilgan parol ko'rinadi / yashiriladi
export default function PasswordInput({ value, onChange, placeholder, autoComplete = 'current-password', required, ...rest }) {
  const [show, setShow] = useState(false)
  return (
    <div className="pass-input">
      <input
        type={show ? 'text' : 'password'}
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        autoComplete={autoComplete}
        required={required}
        autoCapitalize="off"
        autoCorrect="off"
        spellCheck="false"
        {...rest}
      />
      <button
        type="button"
        className="pass-eye"
        onClick={() => setShow((s) => !s)}
        aria-label={show ? 'Parolni yashirish' : 'Parolni ko‘rsatish'}
        aria-pressed={show}
        tabIndex={0}
      >
        {show ? <LuEyeOff size={20} /> : <LuEye size={20} />}
      </button>
    </div>
  )
}
