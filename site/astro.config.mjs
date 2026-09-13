import { defineConfig } from 'astro/config'
import sitemap from '@astrojs/sitemap'
import tailwindcss from '@tailwindcss/vite'
import { SITE } from './src/consts.ts'

export default defineConfig({
  site: SITE,
  trailingSlash: 'never',
  build: { format: 'file' },   // /tools/period-calculator.html -> cleanUrls in Firebase
  integrations: [sitemap()],
  // assetsInlineLimit: 0 forces island code to a real /_astro/*.js file rather
  // than an inline <script>. The production CSP is `script-src 'self'`, which
  // blocks inline scripts — leaving them inlined would silently break all four
  // calculators on the deployed site while everything looked fine locally.
  vite: { plugins: [tailwindcss()], build: { assetsInlineLimit: 0 } },
})
