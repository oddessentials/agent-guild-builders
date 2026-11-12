import assert from 'node:assert/strict';
import { execFile, spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

assert.equal(process.platform, 'win32', 'this regression requires Windows file locking and windows');
assert.ok(process.argv[2], 'usage: node tests/windows_update.mjs path/to/AgentGuildBuilders-windows.zip');
const zip = path.resolve(process.argv[2]);
assert.ok(fs.statSync(zip).isFile());
const project = fileURLToPath(new URL('../', import.meta.url));
const page = fs.readFileSync(path.join(project, 'site/index.md'), 'utf8').replaceAll('\r\n', '\n');
const step = page.match(/^## 2\. .*?\n([\s\S]*?)^## 3\./m)?.[1];
const install = step?.match(/^```powershell\n([\s\S]*?)^```/m)?.[1];
assert.ok(install, 'the documented Windows install block exists');
const beforeInstall = step.split('```')[0];
assert.match(beforeInstall, /stop the `agent-guild-builders` MCP server in every connected agent/);
assert.match(beforeInstall, /wait for all `AgentGuildBuilders.exe` processes for this installation to exit/);
assert.match(beforeInstall, /Keep the saved MCP registrations/);
assert.match(page, /## Update\n\nStop the running MCP servers and close Builders as step 2 says, then run/);
const args = [...page.match(/args: \[(.*?)\]/)[1].matchAll(/'([^']+)'/g)].map((match) => match[1]);
assert.deepEqual(args, ['--headless', '--no-header', '--', '--mcp']);
const cache = path.join(project, '.cache');
fs.mkdirSync(cache, { recursive: true });
const root = fs.mkdtempSync(path.join(cache, 'windows-update-'));
const env = { ...process.env, APPDATA: path.join(root, 'roaming'), LOCALAPPDATA: path.join(root, 'local'),
  TEMP: path.join(root, 'temp'), TMP: path.join(root, 'temp') };
for (const folder of [env.APPDATA, env.LOCALAPPDATA, env.TEMP]) fs.mkdirSync(folder, { recursive: true });
const exe = path.join(env.LOCALAPPDATA, 'Programs/AgentGuildBuilders/AgentGuildBuilders.exe');
const userData = path.join(env.APPDATA, 'Godot/app_userdata/Agent Guild Builders');
const registration = path.join(root, 'mcp.json');
const installScript = path.join(root, 'install.ps1');
const execute = promisify(execFile);
const clients = [];
const server = http.createServer((request, response) => {
  assert.equal(request.url, '/AgentGuildBuilders-windows.zip');
  response.writeHead(200, { 'Content-Length': fs.statSync(zip).size, 'Content-Type': 'application/zip' });
  fs.createReadStream(zip).pipe(response);
});
let passed = false;

async function deadline(promise, label, ms = 60000) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label} timed out`)), ms);
    })]);
  } finally { clearTimeout(timer); }
}

async function powershell(script, extraEnv = {}) {
  return execute('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script], {
    env: { ...env, TEST_EXE: exe, ...extraEnv }, windowsHide: true, timeout: 180000, maxBuffer: 1024 * 1024,
  });
}

async function installPage() {
  const result = await execute('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', installScript], {
    env, windowsHide: true, timeout: 180000, maxBuffer: 1024 * 1024,
  });
  assert.equal(result.stdout.trim().split(/\r?\n/).at(-1), exe);
}

async function connect() {
  const config = JSON.parse(fs.readFileSync(registration, 'utf8'));
  const child = spawn(config.command, config.args, { env, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
  let buffer = '';
  let stderr = '';
  let nextId = 1;
  const pending = new Map();
  const exited = new Promise((resolve) => child.once('exit', resolve));
  child.stderr.setEncoding('utf8').on('data', (data) => { stderr += data; });
  child.stdout.setEncoding('utf8').on('data', (data) => {
    buffer += data;
    let at;
    while ((at = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, at).trim();
      buffer = buffer.slice(at + 1);
      if (!line) continue;
      const message = JSON.parse(line);
      pending.get(message.id)?.(message);
    }
  });
  const request = async (method, params) => {
    const id = nextId++;
    try {
      const reply = new Promise((resolve) => pending.set(id, resolve));
      child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
      const message = await deadline(Promise.race([reply, exited.then((code) => {
        throw new Error(`MCP exited ${code}: ${stderr}`);
      })]), method, 120000);
      assert.ok(!message.error, JSON.stringify(message));
      return message.result;
    } finally { pending.delete(id); }
  };
  const client = { child, exited, request, tool: async (name, arguments_ = {}) => {
    const result = await request('tools/call', { name, arguments: arguments_ });
    assert.equal(result.isError, false, JSON.stringify(result));
    return result.structuredContent;
  } };
  clients.push(client);
  const initialized = await request('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'windows-update', version: '1' } });
  assert.equal(initialized.protocolVersion, '2025-11-25');
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  return client;
}

async function closeWindow(client) {
  await powershell(`
    $ErrorActionPreference = 'Stop'
    $windows = @(Get-Process -Name AgentGuildBuilders | Where-Object { $_.Path -eq $env:TEST_EXE -and $_.Id -ne [int]$env:RELAY_PID -and $_.MainWindowHandle -ne 0 })
    if ($windows.Count -ne 1) { throw "Expected one test window, found $($windows.Count)." }
    if (-not $windows[0].CloseMainWindow()) { throw 'Could not close the test window.' }
    if (-not $windows[0].WaitForExit(30000)) { throw 'The test window did not exit.' }
  `, { RELAY_PID: String(client.child.pid) });
}

async function disconnect(client) {
  client.child.stdin.end();
  assert.equal(await deadline(client.exited, 'MCP disconnect'), 0);
}

function hashes(folder) {
  return Object.fromEntries(fs.readdirSync(folder, { recursive: true, withFileTypes: true })
    .filter((entry) => entry.isFile()).map((entry) => {
      const file = path.join(entry.parentPath, entry.name);
      return [path.relative(folder, file), createHash('sha256').update(fs.readFileSync(file)).digest('hex')];
    }));
}

try {
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const url = 'https://github.com/oddessentials/agent-guild-builders/releases/latest/download/AgentGuildBuilders-windows.zip';
  assert.ok(install.includes(url));
  fs.writeFileSync(installScript, install.replace(url, `http://127.0.0.1:${server.address().port}/AgentGuildBuilders-windows.zip`));
  await installPage();
  const originalExe = createHash('sha256').update(fs.readFileSync(exe)).digest('hex');
  fs.writeFileSync(registration, JSON.stringify({ command: exe, args }));
  const savedRegistration = fs.readFileSync(registration);
  const picture = fs.readFileSync(path.join(project, 'data/brand/icon.png'));
  const uploadId = 'u' + createHash('sha256').update('sign').update(picture).digest('hex').slice(0, 16);
  const upload = path.join(userData, 'custom', uploadId);
  fs.mkdirSync(upload, { recursive: true });
  fs.writeFileSync(path.join(upload, 'picture.png'), picture);
  fs.writeFileSync(path.join(upload, 'item.json'), JSON.stringify({ format: 1, id: uploadId, type: 'image',
    label: 'Update fixture', height: 2, radius: 1, display: 'sign', source: 'picture.png' }));
  const first = await connect();
  const made = await first.tool('create_world', { template: 'blank', title: 'Windows update', seed: 3 });
  const world = made.world;
  assert.ok(path.resolve(world).startsWith(userData + path.sep));
  const placed = await first.tool('place_items', { world, items: [{ kind: 'stone', x: 120, z: -120 }] });
  assert.ok(placed.results[0].id > 0);
  const beforeUpdate = await first.tool('describe_world', { world });
  await closeWindow(first);
  assert.equal(first.child.exitCode, null);
  assert.ok((await first.tool('list_worlds')).worlds.some((entry) => entry.world === world && !entry.open));
  const worldHashes = hashes(path.join(userData, 'worlds'));
  const uploadHashes = hashes(path.join(userData, 'custom'));
  assert.ok(JSON.parse(fs.readFileSync(path.join(world, 'world.json'), 'utf8')).things.some((item) => item.id === placed.results[0].id));
  console.log('ok   the page installs Builders; MCP creates and saves a world; closing its window leaves the relay connected');

  await assert.rejects(installPage, (error) => {
    assert.notEqual(error.code, 0);
    assert.match(error.stderr, /Permission denied/);
    assert.match(error.stderr, /Extracting failed/);
    return true;
  });
  await first.request('ping', {});
  console.log('ok   the documented extraction fails while the windowless relay holds the executable');

  await disconnect(first);
  await powershell(`
    $running = @(Get-Process -Name AgentGuildBuilders -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $env:TEST_EXE })
    if ($running.Count -ne 0) { throw 'The test installation still has running processes.' }
    $handle = [IO.File]::Open($env:TEST_EXE, 'Open', 'ReadWrite', 'None')
    $handle.Dispose()
  `);
  const licence = path.join(path.dirname(exe), 'LICENSE');
  const originalLicence = fs.readFileSync(licence);
  fs.writeFileSync(licence, 'This installed file must be replaced by extraction.');
  await installPage();
  assert.deepEqual(fs.readFileSync(licence), originalLicence);
  assert.equal(createHash('sha256').update(fs.readFileSync(exe)).digest('hex'), originalExe);
  assert.deepEqual(hashes(path.join(userData, 'worlds')), worldHashes);
  assert.deepEqual(hashes(path.join(userData, 'custom')), uploadHashes);
  assert.deepEqual(fs.readFileSync(registration), savedRegistration);
  console.log('ok   stopping MCP releases the executable; extraction replaces installed files and preserves worlds, uploads and connection settings');

  const second = await connect();
  assert.ok((await second.tool('list_worlds')).worlds.some((entry) => entry.world === world));
  assert.ok((await second.tool('list_items', { group: 'custom' })).items.some((item) => item.kind === `custom:${uploadId}`));
  await second.tool('open_world', { world });
  const described = await second.tool('describe_world', { world });
  assert.equal(described.title, made.title);
  assert.deepEqual(described.kinds, beforeUpdate.kinds);
  assert.equal(described.items, beforeUpdate.items);
  assert.deepEqual(hashes(path.join(userData, 'worlds')), worldHashes);
  await closeWindow(second);
  await disconnect(second);
  assert.deepEqual(hashes(path.join(userData, 'custom')), uploadHashes);
  assert.deepEqual(fs.readFileSync(registration), savedRegistration);
  console.log('ok   reconnecting with the saved command lists and opens the unchanged world and finds the preserved upload');
  await execute(process.execPath, [path.join(project, 'tests/mcp_smoke.mjs'), exe], { env, windowsHide: true, timeout: 180000 })
    .then(({ stdout }) => process.stdout.write(stdout));
  passed = true;
} finally {
  for (const client of clients) {
    if (client.child.exitCode === null) client.child.stdin.end();
  }
  await powershell(`
    $ErrorActionPreference = 'Stop'
    Get-Process -Name AgentGuildBuilders -ErrorAction SilentlyContinue |
      Where-Object { $_.Path -eq $env:TEST_EXE } | Stop-Process -Force
    exit 0
  `);
  server.closeAllConnections();
  await new Promise((resolve) => server.close(resolve));
  assert.equal(path.dirname(root), cache);
  assert.ok(path.basename(root).startsWith('windows-update-'));
  if (passed) fs.rmSync(root, { recursive: true, force: true, maxRetries: 10 });
  else console.error(`Failed Windows update fixtures retained at ${root}`);
}
