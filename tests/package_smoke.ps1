param([Parameter(Mandatory)][string]$Zip, [Parameter(Mandatory)][string]$Dir)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Dir) { throw "$Dir already exists." }
Expand-Archive -LiteralPath $Zip -DestinationPath $Dir
$Dir = (Resolve-Path -LiteralPath $Dir).Path
$exe = Join-Path $Dir 'AgentGuildBuilders/AgentGuildBuilders.exe'
$world = Join-Path $Dir 'world'
$app = Start-Process -FilePath $exe -ArgumentList '--headless', '--', '--new=meadow', '--title=Smoke', "`"--save=$world`"" -Wait -PassThru
if ($app.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $world 'world.json'))) { throw 'The packaged app did not create a world.' }
node (Join-Path $PSScriptRoot 'mcp_smoke.mjs') $exe
if ($LASTEXITCODE -ne 0) { throw 'The packaged app did not serve MCP.' }
