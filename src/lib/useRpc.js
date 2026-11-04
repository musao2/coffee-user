import { useCallback, useEffect, useState } from 'react'
import { supabase } from './supabase'
import { errText } from './format'

// RPC chaqirib, natija/xato/yuklanish holatini qaytaradi
export function useRpc(fn, args, deps = []) {
  const [data, setData] = useState(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setError('')
    const { data, error } = await supabase.rpc(fn, args)
    if (error) setError(errText(error))
    else setData(data)
    setLoading(false)
  }, deps) // eslint-disable-line

  useEffect(() => { load() }, [load])
  return { data, error, loading, reload: load }
}

export async function rpc(fn, args) {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(errText(error))
  return data
}
