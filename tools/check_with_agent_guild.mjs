import { createHash } from 'node:crypto';
import { readFileSync, rmSync, writeFileSync, mkdtempSync } from 'node:fs';
import { gunzipSync, gzipSync } from 'node:zlib';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [file, root] = process.argv.slice(2);
if (!file || !root) throw new Error('Usage: node tools/check_with_agent_guild.mjs <world.agworld> <agent-guild checkout>');
const load = (rel) => import(pathToFileURL(path.join(root, rel)).href);
const { extractArchive } = await load('src/manager/yard-art.mjs');
const m = await load('web/yard/model.mjs');
const sha = (b) => createHash('sha256').update(b).digest('hex');

const raw = readFileSync(file);
const tar = gunzipSync(raw);
const manifestSize = parseInt(tar.subarray(124, 136).toString().trim(), 8);
if (tar.subarray(0, 100).toString().replace(/\0.*$/, '') !== 'world.json') throw new Error('world.json must come first');
const manifestBytes = tar.subarray(512, 512 + manifestSize);
const meta = JSON.parse(manifestBytes);
const environment = sha(JSON.stringify([m.CAMERA, m.SUN, m.STAGING.plaza])).slice(0, 16);
if (meta.environment !== environment) throw new Error(`environment ${meta.environment}, expected ${environment}`);
const files = [{ path: 'world.json', size: manifestBytes.length, sha256: sha(manifestBytes) },
  ...Object.entries(meta.files).map(([p, e]) => ({ path: p, size: e.size, sha256: e.sha256 }))];

const work = mkdtempSync(path.join(tmpdir(), 'agworld-'));
try {
  await extractArchive(file, files, path.join(work, 'ok'));
  console.log(`OK: extractor accepts ${files.length} files, hash matches`);
  const refused = async (label, bytes, list = files) => {
    const bad = path.join(work, 'bad.agworld');
    writeFileSync(bad, bytes);
    try {
      await extractArchive(bad, list, path.join(work, `x${label.length}`));
    } catch (err) {
      console.log(`refused ${label}: ${String(err.message).slice(0, 70)}`);
      return;
    }
    throw new Error(`accepted ${label}`);
  };
  const flipped = Buffer.from(tar);
  flipped[tar.length - 2000] ^= 0xff;
  await refused('a changed byte', gzipSync(flipped));
  await refused('an unlisted file', raw, files.slice(0, -1));
} finally {
  rmSync(work, { recursive: true, force: true });
}
