param([Parameter(Mandatory)][string]$Zip, [Parameter(Mandatory)][string]$Dir)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Dir) { throw "$Dir already exists." }
Expand-Archive -LiteralPath $Zip -DestinationPath $Dir
$Dir = (Resolve-Path -LiteralPath $Dir).Path
$exe = Join-Path $Dir 'AgentGuildBuilders/AgentGuildBuilders.exe'
Add-Type -AssemblyName System.Drawing
function Pixels([Drawing.Icon]$Icon) {
    $bitmap = $Icon.ToBitmap()
    $data = $bitmap.LockBits([Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height), 'ReadOnly', 'Format32bppArgb')
    $bytes = [byte[]]::new($data.Stride * $data.Height)
    [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $bitmap.UnlockBits($data)
    , $bytes
}
$ico = Join-Path $PSScriptRoot '../data/brand/icon.ico'
foreach ($size in 16, 32, 48) {
    $got = [Drawing.Icon]::ExtractIcon($exe, 0, $size)
    if (-not $got -or -not [Linq.Enumerable]::SequenceEqual([byte[]](Pixels $got), [byte[]](Pixels ([Drawing.Icon]::new($ico, $size, $size))))) {
        throw "The packaged app's $size px icon is not data/brand/icon.ico."
    }
}
$world = Join-Path $Dir 'world'
$app = Start-Process -FilePath $exe -ArgumentList '--headless', '--', '--new=meadow', '--title=Smoke', "`"--save=$world`"" -Wait -PassThru
if ($app.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $world 'world.json'))) { throw 'The packaged app did not create a world.' }
node (Join-Path $PSScriptRoot 'mcp_smoke.mjs') $exe
if ($LASTEXITCODE -ne 0) { throw 'The packaged app did not serve MCP.' }
