import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://projects.envmanager.victorqueiroz.dev',
  output: 'static',
  trailingSlash: 'always',
  integrations: [sitemap()],
});
