$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$entries = Get-Content (Join-Path $root 'MANIFEST.sha256')
$count=0
foreach ($entry in $entries) {
    if ($entry -notmatch '^([0-9a-f]{64})  (.+)$') { throw "Malformed manifest entry: $entry" }
    $hash=$Matches[1];$name=$Matches[2]
    $path=Join-Path $root ($name -replace '/','\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {throw "Missing file: $name"}
    $actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $hash) {throw "Digest mismatch: $name"}
    $count++
}
Write-Host "Verified $count source files against MANIFEST.sha256"
