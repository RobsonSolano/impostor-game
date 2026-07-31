import { fileURLToPath } from 'node:url'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    // As regras do jogo são testadas em pgTAP (`npx supabase test db`), onde elas
    // realmente vivem. Aqui ficam só lógica pura e interação de componente.
    include: ['src/**/*.test.{ts,tsx}'],
  },
})
