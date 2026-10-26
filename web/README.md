# EnvManager website

Static Astro pages for https://projects.envmanager.victorqueiroz.dev.
End users do not need Node.js. Website development uses Node 24 and npm.

```sh
npm ci --prefix web
npm run build --prefix web
npm run dev --prefix web
```

The build copies the canonical installer, renders the social preview image, and
records the source SHA and installer checksum in `release.json`. Post-build
checks cover page metadata, internal links, sitemap, and installer byte equality.
Generated assets and `dist` are ignored by Git.

Vercel builds the `web` directory with source files outside the root directory
included, so it can read `VERSION` and `installer/install.sh`. Use the Astro
preset, Node 24, `npm run build`, and `dist`. The site is entirely static and
requires no server adapter or runtime secrets.

Production deployment is an explicit promotion after CI passes. Keep automatic
Git production deployment disconnected unless an equivalent check gate is set
up. Verify the exact custom hostname, HTTPS, canonical URLs, robots directives,
installer content type, release SHA, and installer checksum. Preview deployments
must remain noindex. The Vercel default production alias should redirect to the
custom domain with paths and query strings retained.
