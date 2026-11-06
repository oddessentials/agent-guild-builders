import { createRequire } from 'node:module';
import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = process.argv[2] ? path.resolve(process.argv[2]) : null;
if (!root) throw new Error('Usage: node tools/build_halls.mjs <agent-guild checkout>');
const output = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../kits/halls');
const require = createRequire(path.join(root, 'package.json'));
const load = (name) => import(pathToFileURL(require.resolve(name)).href);
const { NodeIO } = await load('@gltf-transform/core');
const { ALL_EXTENSIONS } = await load('@gltf-transform/extensions');
const { dequantize } = await load('@gltf-transform/functions');

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
mkdirSync(output, { recursive: true });
for (const world of ['guild', 'orbital', 'grove', 'professional', 'goblinville', 'gnomeland']) {
  const document = await io.read(path.join(root, 'web/yard/assets', `${world}.glb`));
  await document.transform(dequantize());
  for (const extension of document.getRoot().listExtensionsUsed())
    if (extension.extensionName === 'KHR_mesh_quantization') extension.dispose();
  await io.write(path.join(output, `${world}.glb`), document);
  console.log(world);
}
