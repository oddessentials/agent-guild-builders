// Drives the packaged app's MCP server the way an agent's client does:
// node tests/mcp_smoke.mjs path/to/AgentGuildBuilders.exe [--windowed]
// (on a Mac, the executable inside AgentGuildBuilders.app/Contents/MacOS)
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const [exe, ...flags] = process.argv.slice(2);
const windowed = flags.includes('--windowed');
const appData = fs.mkdtempSync(path.join(os.tmpdir(), 'agb-mcp-'));
const args = ['--headless', '--', windowed ? '--mcp' : '--mcp=headless'];
// Builders keeps its data under APPDATA on Windows and under HOME on a Mac.
const child = spawn(exe, args, { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, APPDATA: appData, ...(process.platform === 'darwin' ? { HOME: appData } : {}) } });
const lines = [];
const waiting = new Map();
let buffer = '';
let stderr = '';
child.stderr.setEncoding('utf8').on('data', (d) => { stderr += d; });
child.stdout.setEncoding('utf8').on('data', (d) => {
  buffer += d;
  let at;
  while ((at = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, at).replace(/\r$/, '');
    buffer = buffer.slice(at + 1);
    if (!line) continue;
    lines.push(line);
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    waiting.get(msg.id)?.(msg);
  }
});
const exited = new Promise((resolve) => child.on('exit', (code) => resolve(code)));
let nextId = 1;
const request = (method, params, timeoutMs = 60000) => new Promise((resolve, reject) => {
  const id = nextId++;
  const timer = setTimeout(() => reject(new Error(`${method} got no reply in ${timeoutMs} ms`)), timeoutMs);
  waiting.set(id, (msg) => { clearTimeout(timer); waiting.delete(id); resolve(msg); });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
});
const tool = async (name, args, timeoutMs) => (await request('tools/call', { name, arguments: args }, timeoutMs)).result;
const failures = [];
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures.push(what); };

try {
  const init = await request('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'smoke', version: '1' } });
  check(init.result?.protocolVersion === '2025-11-25', 'initialize');
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const meta = { 'io.modelcontextprotocol/protocolVersion': '2026-07-28', 'io.modelcontextprotocol/clientCapabilities': {} };
  const discover = await request('server/discover', { _meta: meta });
  check(discover.result?.supportedVersions?.includes('2026-07-28'), 'server/discover');
  const list = await request('tools/list', {});
  check(list.result?.tools?.length === 17, 'tools/list has 17 tools');
  child.stdin.write('{not json\n');
  const made = await tool('create_world', { template: 'blank', title: 'Smoke', seed: 3 }, 120000);
  const world = made?.structuredContent?.world;
  check(!made?.isError && world && fs.existsSync(path.join(world, 'world.json')), 'create_world saves a world');
  const placed = await tool('place_items', { world, items: [{ kind: 'stone', x: 120, z: -120 }, { kind: 'stone', x: 0, z: 0 }] });
  const results = placed?.structuredContent?.results ?? [];
  check(results[0]?.id > 0 && typeof results[1]?.refused === 'string', 'place_items places one and explains the refusal');
  const preview = await tool('render_preview', { world }, 120000);
  if (windowed) {
    check(preview?.content?.[0]?.type === 'image' && preview.content[0].mimeType === 'image/jpeg' && preview.content[0].data.length > 1000, 'render_preview returns a picture');
  } else {
    check(preview?.isError === true && /window/.test(preview.content[0].text), 'render_preview refuses when headless');
  }
  check(lines.every((l) => { try { return typeof JSON.parse(l) === 'object'; } catch { return false; } }), 'stdout carries only JSON');
  check(lines.some((l) => l.includes('"code":-32700')), 'a malformed line gets a parse error');
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: nextId++, method: 'tools/call', params: { name: 'describe_world', arguments: { world } } }) + '\n');
  child.stdin.end();
  const code = await Promise.race([exited, new Promise((r) => setTimeout(() => r('timeout'), 60000))]);
  check(code === 0, `exits cleanly when stdin closes with a call in flight (exit ${code})`);
  check(!/Pipe must be opened|Parse JSON failed/.test(stderr), 'the window\'s pipe is read to its end');
  const saved = world && JSON.parse(fs.readFileSync(path.join(world, 'world.json'), 'utf8'));
  check(saved?.things?.some((t) => t.id === results[0]?.id), 'the placed item was saved on exit');
} catch (e) {
  check(false, e.message);
  child.kill();
  await exited;
}
if (failures.length) {
  console.log(stderr.split('\n').slice(-30).join('\n'));
  process.exitCode = 1;
}
fs.rmSync(appData, { recursive: true, force: true, maxRetries: 10 });
