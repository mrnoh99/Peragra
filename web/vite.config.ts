import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Served from https://<owner>.github.io/Peragra/ (a project page, not a
  // custom domain or <owner>.github.io itself) — assets need this prefix
  // or they'd resolve against the domain root and 404.
  base: "/Peragra/",
})
