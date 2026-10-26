import { readFile, access } from 'node:fs/promises';
import assert from 'node:assert/strict';

const dist = new URL('../dist/', import.meta.url);
const site = 'https://projects.envmanager.victorqueiroz.dev';
const routes = ['', 'install/macos/', 'install/linux/', 'docs/', 'changelog/'];
for (const route of routes) {
  const html = await readFile(new URL(`${route}index.html`, dist), 'utf8');
  assert.equal((html.match(/<h1\b/g) || []).length, 1, `${route}: one h1`);
  assert.match(html, /<title>[^<]+<\/title>/);
  assert.match(html, /name="description"/);
  assert.ok(html.includes(`href="${site}/${route}"`), `${route}: canonical`);
  assert.match(html, /property="og:image"/);
  assert.match(html, /application\/ld\+json/);
  for (const [, href] of html.matchAll(/href="(\/[^"#?]*)/g)) {
    if (href.startsWith('//')) continue;
    const file = href.endsWith('/') ? `${href}index.html` : href;
    await access(new URL(file.slice(1), dist)).catch(() => { throw new Error(`${route}: broken link ${href}`); });
  }
}
const installer = await readFile(new URL('install.sh', dist));
await access(new URL('social.png', dist));
const source = await readFile(new URL('../../installer/install.sh', import.meta.url));
assert.deepEqual(installer, source, 'published installer must match its canonical source');
assert.ok((await readFile(new URL('robots.txt', dist), 'utf8')).includes(`${site}/sitemap-index.xml`));
assert.ok((await readFile(new URL('sitemap-0.xml', dist), 'utf8')).includes(`${site}/install/linux/`));
console.log(`Verified ${routes.length} HTML pages, internal links, metadata, sitemap and installer bytes.`);
