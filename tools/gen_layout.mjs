// Writes data/yard_layout.json from the Yard's own model, so the builder cannot
// disagree with the contract. Read-only on agent-guild.
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
const root = process.argv[2] ? path.resolve(process.argv[2]) : null;
if (!root) throw new Error('Usage: node tools/gen_layout.mjs <agent-guild checkout>');
const m = await import(pathToFileURL(path.join(root, 'web/yard/model.mjs')).href);
const providers = m.PROVIDER_ORDER.map(id => ({ id }));
const worlds = Object.fromEntries(Object.entries(m.WORLDS).map(([id, w]) => [id, { title: w.title, hemi: w.hemi, sun: w.sun }]));
const crews = providers.flatMap(p => Array.from({ length: 8 }, (_, i) => ({ id: p.id + ':' + i, provider: { id: p.id }, createdAt: String(i) })));
const stations = [...m.layoutSessions(crews, providers)].flatMap(([id, s]) => [{ x: s.x, z: s.z }, (({ x, z }) => ({ x, z }))(m.stationProp(s, id))]);
const places = [...stations, ...providers.map(p => m.doorFor({ provider: p }, providers))];
// The hash a world file carries; Agent Guild computes the same (agent-guild#378).
const environment = createHash('sha256').update(JSON.stringify([m.CAMERA, m.SUN, m.STAGING.plaza])).digest('hex').slice(0, 16);
writeFileSync(fileURLToPath(new URL('../data/yard_layout.json', import.meta.url)), JSON.stringify({
  environment,
  camera: m.CAMERA, sun: m.SUN, basis: m.viewBasis(), extent: m.plateExtent(),
  plaza: m.STAGING.plaza, hall: m.STAGING.hall,
  halls: Object.fromEntries([...m.providerPositions(providers)]),
  restSpots: m.restSpots(providers), places, roam: m.VIBE.roam, worlds,
}, null, 1) + '\n');
