param([string]$Godot = 'godot')

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$build = Join-Path $project 'build'
$kitPath = Join-Path $project 'kits/meadow/kit.json'
$kit = Get-Content -LiteralPath $kitPath -Raw | ConvertFrom-Json
if (-not $kit.models -or @($kit.models.PSObject.Properties).Count -eq 0) { throw 'The Meadow kit has no models.' }
foreach ($name in @('grass', 'dirt', 'rock', 'gravel', 'cobble')) {
    if (-not $kit.grounds.$name) { throw "The Meadow kit is missing ground: $name" }
}
foreach ($name in @('day', 'dusk', 'overcast', 'moon')) {
    if (-not $kit.skies.$name) { throw "The Meadow kit is missing sky: $name" }
}
$files = @('kits/meadow/kit.json', 'LICENSE', 'data/agx_mhc.lut', 'data/yard_layout.json')
$thumbs = @('mix_wildflowers', 'mix_undergrowth', 'mix_woodland', 'mix_rocks', 'mix_garden', 'mix_camp')
$presets = [regex]::Match((Get-Content -LiteralPath (Join-Path $project 'src/core/templates.gd') -Raw), '(?ms)^const LIST := \{(.*?)^\}').Groups[1].Value
$presets = @($presets -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object {
    if ($_ -notmatch '^\t"(\w+)": \{.*\},?$') { throw "Could not read the preset line in src/core/templates.gd: $($_.Trim())" }
    $Matches[1]
})
if ($presets -notcontains 'blank') { throw 'Could not read the presets from src/core/templates.gd.' }
foreach ($preset in $presets) { $thumbs += "template_$preset" }
if (-not $kit.lands.meadow) { throw 'The Meadow kit has no meadow ground set.' }
foreach ($land in $kit.lands.PSObject.Properties) {
    foreach ($ground in $land.Value.grounds) { $thumbs += "ground_$ground" }
}
foreach ($model in $kit.models.PSObject.Properties) {
    if (-not $model.Value.licence -or -not $model.Value.source) { throw "Missing attribution for $($model.Name)" }
    $files += "kits/meadow/models/$($model.Name).glb"
    $thumbs += $model.Name
}
foreach ($ground in $kit.grounds.PSObject.Properties) {
    if (-not $ground.Value.licence -or -not $ground.Value.source) { throw "Missing attribution for $($ground.Name)" }
    foreach ($suffix in @('diff', 'nor_gl', 'rough')) { $files += "kits/meadow/textures/$($ground.Name)_$suffix.jpg" }
}
foreach ($sky in $kit.skies.PSObject.Properties) {
    if (-not $sky.Value.licence -or -not $sky.Value.source) { throw "Missing attribution for $($sky.Name)" }
    $files += "kits/meadow/skies/$($sky.Name).hdr"
}
foreach ($base in @('guild', 'orbital', 'grove', 'professional', 'goblinville', 'gnomeland')) { $files += "kits/halls/$base.glb" }
foreach ($thumb in $thumbs) { $files += "data/thumbs/$thumb.webp" }
foreach ($file in $files) {
    $item = Get-Item -LiteralPath (Join-Path $project $file)
    if ($item.PSIsContainer -or $item.Length -eq 0) { throw "Missing or empty build asset: $file" }
}

New-Item -ItemType Directory -Path $build -Force | Out-Null
$stage = Join-Path $build ('package-' + [guid]::NewGuid().ToString('N'))
$bundle = Join-Path $stage 'AgentGuildBuilders'
New-Item -ItemType Directory -Path $bundle -Force | Out-Null
try {
    $importLog = & $Godot --headless --path $project --editor --import --quit 2>&1
    $importExit = $LASTEXITCODE
    $importLog | Write-Output
    if ($importExit -ne 0 -or ($importLog -match 'SCRIPT ERROR:')) { throw 'Godot import failed.' }
    $exportLog = & $Godot --headless --path $project --export-release Windows (Join-Path $bundle 'AgentGuildBuilders.exe') 2>&1
    $exportExit = $LASTEXITCODE
    $exportLog | Write-Output
    if ($exportExit -ne 0 -or ($exportLog -match 'SCRIPT ERROR:')) { throw 'Godot export failed.' }
    foreach ($file in $files) {
        if (-not $file.StartsWith('kits/') -and $file -ne 'LICENSE') { continue }
        $destination = Join-Path $bundle $file
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $project $file) -Destination $destination
    }
    $zip = Join-Path $stage 'AgentGuildBuilders-windows.zip'
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip
    $output = Join-Path $build 'AgentGuildBuilders-windows.zip'
    Move-Item -LiteralPath $zip -Destination $output -Force
    Write-Output "Packaged $output"
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stage)
    if (-not $resolvedStage.StartsWith([IO.Path]::GetFullPath($build) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Staging path escaped the build directory.' }
    Remove-Item -LiteralPath $resolvedStage -Recurse -Force
}
