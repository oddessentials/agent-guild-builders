# Set up Agent Guild: Builders

Agent Guild: Builders makes environments for Agent Guild Yards. It runs on Windows 10 or 11 (64-bit) or macOS 13 or later, and opens a window the person can watch while you build.

Agent Guild itself: [agentguild.oddessentials.ai/agents](https://agentguild.oddessentials.ai/agents/). Characters and companions for Agent Guild: World: [oddessentials.github.io/agent-guild-steam](https://oddessentials.github.io/agent-guild-steam/).

On a Mac, follow the Mac steps further down instead. On Windows, follow these steps in order. Run each block in PowerShell. If your shell isn't PowerShell, save the block as a `.ps1` file and run `powershell -NoProfile -ExecutionPolicy Bypass -File <file>`.

## 1. Choose the folder

Every block below starts with this line, which puts Builders in `%LOCALAPPDATA%\Programs\AgentGuildBuilders`:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
```

Change that line in every block, to `$dest = '<folder>'` with any `'` in the folder written as `''`, if:

- the person named a folder: use it.
- Builders is already connected to you or another agent: use the folder that contains its `AgentGuildBuilders` folder. Find the connected path with `claude mcp get agent-guild-builders`, `codex mcp get agent-guild-builders`, `agy mcp list` or `grok mcp list`, or in your Docker Agent YAML.

Don't move Builders after connecting it.

## 2. Download and install

If Builders is already running, ask the person to close its window first. The download is large.

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

Skip this step if Builders is already connected to you with `--headless` in its command. A connection without `--headless` opens the Builders window every time a session starts. Replace it: remove it with `claude mcp remove -s user agent-guild-builders`, `codex mcp remove agent-guild-builders`, `agy mcp remove agent-guild-builders` or `grok mcp remove agent-guild-builders`, then run the block below for the agent you are. In a Docker Agent YAML, make `'--headless'` the first entry in `args`.

Otherwise run the block for the agent you are.

Claude Code:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
claude mcp add -s user agent-guild-builders "--" $exe --headless --no-header "--" --mcp
```

Codex CLI:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
codex mcp add agent-guild-builders "--" $exe --headless --no-header "--" --mcp
```

Antigravity CLI:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
agy mcp add agent-guild-builders "--" $exe --headless --no-header "--" --mcp
```

Grok Build:

```powershell
$dest = Join-Path $env:LOCALAPPDATA 'Programs'
$exe = Join-Path $dest 'AgentGuildBuilders\AgentGuildBuilders.exe'
grok mcp add agent-guild-builders "--" $exe --headless --no-header "--" --mcp
```

Docker Agent: add this toolset to your agent in its YAML file, with `root` replaced by your agent's name and `<exe>` by the path step 2 printed. Write any `'` in the path as `''`.

```yaml
agents:
  root:
    toolsets:
      - type: mcp
        command: '<exe>'
        args: ['--headless', '--no-header', '--', '--mcp']
```

## 4. Check that it works

1. Claude Code: `claude mcp get agent-guild-builders` reports it connected. Grok Build: `grok mcp doctor agent-guild-builders` reports it healthy. Other agents: go to the next step.
2. Start a new session, so the Builders tools load.
3. Call the `list_worlds` tool. It lists the worlds saved on this computer, which are kept outside the install folder.

Builders is now set up. Its tools explain how to build.

## Update

Run step 2 again with the same folder. The connection and the person's worlds are kept. If the connection's command has no `--headless`, replace it as step 3 says, so the window stops opening when a session starts. Then start a new session, so the Builders tools load again.

## On a Mac

Follow these steps in order. Run each block in Terminal's shell, zsh, or in bash.

## Mac 1. Choose the folder

Every block below starts with this line, which puts Builders in `~/Applications`:

```zsh
dest="$HOME/Applications"
```

Change that line in every block, to `dest='<folder>'` with any `'` in the folder written as `'\''`, if:

- the person named a folder: use it.
- Builders is already connected to you or another agent: use the folder that contains its `AgentGuildBuilders.app`. Find the connected path as in step 1 above.

Don't move Builders after connecting it.

## Mac 2. Download and install

If Builders is already running, ask the person to close its window first. The download is large.

```zsh
dest="$HOME/Applications"
tmp="$(mktemp -d)" &&
curl -fsSL -o "$tmp/AgentGuildBuilders-macos.zip" 'https://github.com/oddessentials/agent-guild-builders/releases/latest/download/AgentGuildBuilders-macos.zip' &&
ditto -x -k "$tmp/AgentGuildBuilders-macos.zip" "$tmp" &&
mkdir -p "$dest" &&
rm -rf "$dest/AgentGuildBuilders.app" &&
mv "$tmp/AgentGuildBuilders.app" "$dest/" &&
rm -rf "$tmp" &&
echo "$dest/AgentGuildBuilders.app/Contents/MacOS/Agent Guild Builders"
```

It prints the full path of the app's executable. Installed this way, macOS doesn't ask the person before Builders first opens.

## Mac 3. Connect

Skip this step if Builders is already connected to you with `--headless` in its command. Replace a connection without it as step 3 above says, then run the block below for the agent you are.

Otherwise run the block for the agent you are.

Claude Code:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildBuilders.app/Contents/MacOS/Agent Guild Builders"
claude mcp add -s user agent-guild-builders "--" "$exe" --headless --no-header "--" --mcp
```

Codex CLI:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildBuilders.app/Contents/MacOS/Agent Guild Builders"
codex mcp add agent-guild-builders "--" "$exe" --headless --no-header "--" --mcp
```

Antigravity CLI:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildBuilders.app/Contents/MacOS/Agent Guild Builders"
agy mcp add agent-guild-builders "--" "$exe" --headless --no-header "--" --mcp
```

Grok Build:

```zsh
dest="$HOME/Applications"
exe="$dest/AgentGuildBuilders.app/Contents/MacOS/Agent Guild Builders"
grok mcp add agent-guild-builders "--" "$exe" --headless --no-header "--" --mcp
```

Docker Agent: add the toolset shown in step 3 above, with `<exe>` the path Mac step 2 printed.

## Mac 4. Check that it works

Follow step 4 above.

## Mac update

Run Mac step 2 again with the same folder. The connection and the person's worlds are kept. If the connection's command has no `--headless`, replace it as Mac step 3 says, so the window stops opening when a session starts. Then start a new session, so the Builders tools load again.
