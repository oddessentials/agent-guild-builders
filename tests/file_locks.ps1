param([string]$Godot = 'godot')

$ErrorActionPreference = 'Stop'
$project = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$fixture = [IO.Path]::GetFullPath((Join-Path $project '.cache/write-lock-tests'))
if (-not $fixture.StartsWith($project + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid test path.' }
& $Godot --headless --path $project --script res://tests/file_locks.gd -- prepare $fixture
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare file lock fixtures.' }
$handles = @()
$lockedResult = 1
try {
    foreach ($file in @('project/world.json', 'export.agworld', 'recover.old/notes.txt', 'cleanup.agworld.previous')) {
        $handles += [IO.File]::Open((Join-Path $fixture $file), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    }
    & $Godot --headless --path $project --script res://tests/file_locks.gd -- locked $fixture
    $lockedResult = $LASTEXITCODE
} finally {
    foreach ($handle in $handles) { $handle.Dispose() }
}
& $Godot --headless --path $project --script res://tests/file_locks.gd -- released $fixture
if ($LASTEXITCODE -ne 0 -or $lockedResult -ne 0) { throw 'File lock checks failed.' }
