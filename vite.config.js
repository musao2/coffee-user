import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: { host: true, port: 5173 },
  preview: { port: 5173 },
  build: {
    target: 'es2019',
    rollupOptions: {
      output: {
        // kutubxonalarni alohida faylga ajratamiz: tezroq yuklanadi va keshlanadi
        manualChunks(id) {
          if (!id.includes('node_modules')) return
          if (id.includes('@supabase')) return 'supabase'
          if (id.includes('html5-qrcode')) return 'scanner'
          if (id.includes('react-icons')) return 'icons'
          return 'vendor'
        },
      },
    },
  },
})
