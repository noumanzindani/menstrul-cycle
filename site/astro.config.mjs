import { defineConfig } from 'astro/config'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'
import { SITE } from './src/consts.ts'

export default defineConfig({
  site: SITE,
  trailingSlash: 'never',
  build: { format: 'file' },   // /tools/period-calculator.html -> cleanUrls in Firebase
  integrations: [sitemap()],
  vite: { plugins: [tailwindcss()] },
})
