import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import sharp from 'sharp';

const root = new URL('../', import.meta.url);
const repository = new URL('../../', import.meta.url);
const version = (await readFile(new URL('VERSION', repository), 'utf8')).trim();
const installer = await readFile(new URL('installer/install.sh', repository));
const commit = process.env.VERCEL_GIT_COMMIT_SHA || execFileSync('git', ['rev-parse', 'HEAD'], { cwd: repository, encoding: 'utf8' }).trim();
await mkdir(new URL('public/', root), { recursive: true });
await sharp(await readFile(new URL('public/social.svg', root))).png().toFile(new URL('public/social.png', root).pathname);
await writeFile(new URL('public/install.sh', root), installer);
await writeFile(new URL('public/release.json', root), JSON.stringify({
  version, tag: `v${version}`, commit,
  installerSha256: createHash('sha256').update(installer).digest('hex'),
  repository: 'https://github.com/VictorQueiroz/envmanager',
  installUrl: 'https://projects.envmanager.victorqueiroz.dev/install.sh',
}, null, 2) + '\n');
