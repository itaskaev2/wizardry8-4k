<#
.SYNOPSIS
  Undo install.ps1: restore the replaced files from <game>\_wiz8_4k\backup, delete the added ones,
  put the nGlide splash setting and the desktop shortcut back as they were.
.EXAMPLE
  .\uninstall.ps1
  .\uninstall.ps1 -GamePath "D:\Steam\steamapps\common\Wizardry8" -WhatIf
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')

Write-Step 'Game folder'
$GamePath = Resolve-GamePath $GamePath
Write-Info $GamePath
$m = Read-Manifest $GamePath
if (-not $m) { Write-Info "Nothing to undo: no $($script:StateDirName)\manifest.json in the game folder."; return }
if (-not $WhatIf) { Assert-GameNotRunning $GamePath }
$state = Get-StateDir $GamePath
$backup = Join-Path $state 'backup'

Write-Step 'Files'
$n = 0
foreach ($rel in $m.created) {
    $full = Join-Path $GamePath $rel
    if (Test-Path -LiteralPath $full) {
        if (-not $WhatIf) { Remove-Item -LiteralPath $full -Force }
        $n++
    }
}
Write-Info "removed $n added files"
# the mod's own log, written while playing
if ((Test-Listed $m.created 'wiz8hd.asi') -and (Test-Path -LiteralPath (Join-Path $GamePath 'wiz8hd.log'))) {
    if (-not $WhatIf) { Remove-Item -LiteralPath (Join-Path $GamePath 'wiz8hd.log') -Force }
}
foreach ($rel in $m.backedUp) {
    $src = Join-Path $backup $rel
    if (-not (Test-Path -LiteralPath $src)) { Write-Warn2 "backup of $rel is missing, left as is"; continue }
    if (-not $WhatIf) { Copy-Item -LiteralPath $src -Destination (Join-Path $GamePath $rel) -Force }
    Write-Info "restored $rel"
}
$dirs = @($m.createdDirs)
[array]::Reverse($dirs)
foreach ($rel in $dirs) {
    $full = Join-Path $GamePath $rel
    if ((Test-Path -LiteralPath $full) -and -not (Get-ChildItem -LiteralPath $full -Force)) {
        if (-not $WhatIf) { Remove-Item -LiteralPath $full -Force }
        Write-Info "removed $rel\"
    } elseif (Test-Path -LiteralPath $full) {
        Write-Warn2 "$rel\ has files not from this package, left in place"
    }
}

if ($m.registry) {
    Write-Step '3dfx splash setting'
    $r = $m.registry
    if (-not $WhatIf) {
        if (-not $r.keyExisted) {
            if (Test-Path $r.key) { Remove-Item -Path $r.key -Recurse -Force }
        } elseif ($r.valueExisted) {
            New-ItemProperty -Path $r.key -Name Splash -Value ([int]$r.value) -PropertyType DWord -Force | Out-Null
        } elseif (Test-Path $r.key) {
            Remove-ItemProperty -Path $r.key -Name Splash -ErrorAction SilentlyContinue
        }
    }
    Write-Info "$($r.key) restored"
}

if ($m.shortcut) {
    Write-Step 'Desktop shortcut'
    $s = $m.shortcut
    if (-not $WhatIf) {
        if ($s.backup -and (Test-Path -LiteralPath $s.backup)) { Copy-Item -LiteralPath $s.backup -Destination $s.path -Force }
        elseif (Test-Path -LiteralPath $s.path) { Remove-Item -LiteralPath $s.path -Force }
    }
    Write-Info $s.path
}

if (-not $WhatIf) { Remove-Item -LiteralPath $state -Recurse -Force }
Write-Step 'Done'
if ($WhatIf) { Write-Info 'WhatIf: nothing was changed.' }
