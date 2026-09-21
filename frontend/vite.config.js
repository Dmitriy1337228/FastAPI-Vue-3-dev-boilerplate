import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    host: true,
    port: 3000,
    hmr: {
      // HMR WebSocket reaches Vite through Nginx on port 80.
      clientPort: 80,
    },
  },
})