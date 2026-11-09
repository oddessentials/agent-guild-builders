# Set up Agent Guild: Builders

Agent Guild: Builders makes environments for Agent Guild Yards. It runs on Windows 10 or 11 (64-bit) and opens a window the person can watch while you build.

Follow these steps in order. Run each block in PowerShell. If your shell isn't PowerShell, save the block as a `.ps1` file and run `powershell -NoProfile -ExecutionPolicy Bypass -File <file>`.

## 1. Choose the folder

Every block below starts with this line, which puts Builders in `%LOCALAPPDATA%\Programs\AgentGuildBuilders`:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
```

Change that line in every block, to `$dest = '<folder>'` with any `'` in the folder written as `''`, if:

- the person named a folder: use it.
- Builders is already connected: use the folder that contains its `AgentGuildBuilders` folder. Find the connected path with `claude mcp get agent-guild-builders`, `codex mcp get agent-guild-builders`, `agy mcp list` or `grok mcp list`, or in your Docker Agent YAML.

Don't move Builders after connecting it.

## 2. Download and install

If Builders is already running, ask the person to close its window first. The download can take a few minutes.

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$zip = Join-Path $env:TEMP 'AgentGuildBuilders-windows.zip'
New-Item -ItemType Directory -Force $dest | Out-Null
Invoke-WebRequest 'https://github.com/oddessentials/agent-guild-builders/releases/latest/download/AgentGuildBuilders-windows.zip' -OutFile $zip
& "$env:SystemRoot\System32\tar.exe" -xf $zip -C $dest
if ($LASTEXITCODE -ne 0) { throw "Extracting failed (exit $LASTEXITCODE)." }
Remove-Item -LiteralPath $zip
(Resolve-Path -LiteralPath (Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe')).Path
```

It prints the full path of `AgentGuildBuilders.exe`.

## 3. Connect

Skip this step if Builders was already connected. Otherwise run the block for the agent you are.

Claude Code:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
claude mcp add -s user agent-guild-builders "--" $exe --no-header "--" --mcp
```

Codex CLI:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
codex mcp add agent-guild-builders "--" $exe --no-header "--" --mcp
```

Antigravity CLI:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
agy mcp add agent-guild-builders "--" $exe --no-header "--" --mcp
```

Grok Build:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
grok mcp add agent-guild-builders "--" $exe --no-header "--" --mcp
```

Docker Agent: add this toolset to your agent's YAML file, with `<exe>` replaced by the path step 2 printed. Write any `'` in the path as `''`.

```yaml
toolsets:
  - type: mcp
    command: '<exe>'
    args: ['--no-header', '--', '--mcp']
```

## 4. Check that it works

1. Claude Code: `claude mcp get agent-guild-builders` shows `Status: ✔ Connected`. Grok Build: `grok mcp doctor agent-guild-builders` shows `1 healthy`. Other agents: go to the next step.
2. Start a new session, so the Builders tools load.
3. Call the `list_worlds` tool. A Builders window opens and the call lists the saved worlds (none on a new install).

Builders is now set up. Its tools explain how to build.

## Update

Run step 2 again with the same folder. The connection and the person's worlds are kept.
