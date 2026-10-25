<#
.SYNOPSIS
  File-level test of install.ps1 / uninstall.ps1 on small fake game folders under tests\_work.
  Never starts the game and never writes to the real game folder, the real nGlide key or the real Desktop:
  it uses a test registry key (HKCU:\Software\Wiz8_4k_test) and tests\_work\desktop.
.PARAMETER Source
  A real Wizardry 8 folder to take Wiz8_v128.exe, Wiz8.dll and mods\dgVoodoo2_87_5.zip from (read only).
#>
param([Parameter(Mandatory)][string]$Source)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts\Common.ps1')
$work = Join-Path $PSScriptRoot '_work'
$regKey = 'HKCU:\Software\Wiz8_4k_test\nGlide2'
$desk = Join-Path $work 'desktop'
$script:fails = 0

function Check([bool]$ok, [string]$what) {
    if ($ok) { Write-Host "  ok    $what" -ForegroundColor Green }
    else { Write-Host "  FAIL  $what" -ForegroundColor Red; $script:fails++ }
}

function Snapshot([string]$dir) {
    $h = @{}
    Get-ChildItem -LiteralPath $dir -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($dir.Length + 1)
        $h[$rel] = if ($_.PSIsContainer) { '<dir>' } else { Get-Sha256 $_.FullName }
    }
    return $h
}

function Same($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if (-not $b.ContainsKey($k) -or $a[$k] -ne $b[$k]) { return $false } }
    return $true
}

function New-Game([string]$name) {
    $g = Join-Path $work $name
    New-Item -ItemType Directory -Force (Join-Path $g 'mods') | Out-Null
    foreach ($f in 'Wiz8_v128.exe', 'Wiz8.dll') { Copy-Item -LiteralPath (Join-Path $Source $f) $g }
    Copy-Item -LiteralPath (Join-Path $Source 'mods\dgVoodoo2_87_5.zip') (Join-Path $g 'mods')
    [IO.File]::WriteAllText((Join-Path $g '3DVideo.CFG'), "Glide2x`r`n800`r`n600`r`n16`r`nMiles Fast 2D Positional Audio`r`n")
    Set-Content -LiteralPath (Join-Path $g 'Wiz8.exe') -Value 'stand-in' -Encoding ASCII
    return $g
}

function Run([string]$script, [hashtable]$a) {
    & (Join-Path $repo $script) @a *>&1 | Out-String | Write-Verbose
}

function Real-State {
    $k = $script:DefaultNGlideKey
    $reg = if (Test-Path $k) { (Get-ItemProperty $k | Out-String) } else { '<none>' }
    $l = Join-Path ([Environment]::GetFolderPath('Desktop')) $script:ShortcutName
    $reg + '|' + $(if (Test-Path -LiteralPath $l) { Get-Sha256 $l } else { '<none>' })
}
$realBefore = Real-State

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
if (Test-Path 'HKCU:\Software\Wiz8_4k_test') { Remove-Item 'HKCU:\Software\Wiz8_4k_test' -Recurse -Force }
New-Item -ItemType Directory -Force $desk | Out-Null
$payload = Join-Path $repo 'payload'
$common = @{ ShortcutDir = $desk; NGlideKey = $regKey; Width = 2560; Height = 1440; Offline = $true }

# ---------- A: fresh Steam folder ----------
Write-Host 'A: fresh Steam folder -> install -> install again -> uninstall'
$g = New-Game 'steam'
$before = Snapshot $g
Run 'install.ps1' ($common + @{ GamePath = $g; WhatIf = $true })
Check (Same $before (Snapshot $g)) 'WhatIf changes nothing'
Check (-not (Test-Path $regKey)) 'WhatIf leaves the registry alone'

Run 'install.ps1' ($common + @{ GamePath = $g })
Check ((Get-Content -LiteralPath (Join-Path $g '3DVideo.CFG') -Raw) -eq "DirectX7_1`r`n2560`r`n1440`r`n32`r`nMiles Fast 2D Positional Audio`r`n") '3DVideo.CFG = DirectX7_1 2560x1440x32, audio line kept'
Check ((Get-Sha256 (Join-Path $g 'DDraw.dll')) -eq '612a24408a090a3c6f3886557fa18034ee742e94ad0a40ebdf854d2816176c2e') 'DDraw.dll = dgVoodoo2 2.87.5 x86'
Check ((Get-Sha256 (Join-Path $g 'D3DImm.dll')) -eq '93c534f2d17419ea78f15551f7e0aac78b3c503733a840914fa063708a5afe8e') 'D3DImm.dll = dgVoodoo2 2.87.5 x86'
Check ((Get-Sha256 (Join-Path $g 'dgVoodooCpl.exe')) -eq '87fb878166dcaef3e75ff170de030527c73f5c9b164c5943da13f8a97b0b75c6') 'dgVoodooCpl.exe'
foreach ($f in 'dgVoodoo.conf', 'wiz8hd.asi', 'wiz8hd.ini') {
    Check ((Get-Sha256 (Join-Path $g $f)) -eq (Get-Sha256 (Join-Path $payload $f))) "$f = payload"
}
foreach ($d in 'wiz8hd_fonts', 'wiz8hd_bg', 'wiz8hd_ui') {
    $root = Join-Path $payload $d
    $p = @(Get-ChildItem -LiteralPath $root -File -Recurse)
    $bad = @($p | Where-Object { $rel = $d + $_.FullName.Substring($root.Length)
                                 -not (Test-Path -LiteralPath (Join-Path $g $rel)) -or (Get-Sha256 (Join-Path $g $rel)) -ne (Get-Sha256 $_.FullName) })
    Check ($bad.Count -eq 0) "$d\ = payload ($($p.Count) files)"
}
Check ((Get-ItemProperty $regKey).Splash -eq 0) 'nGlide Splash = 0'
$lnk = Join-Path $desk $script:ShortcutName
Check ((Test-Path $lnk) -and ((New-Object -ComObject WScript.Shell).CreateShortcut($lnk).TargetPath -ieq (Join-Path $g 'Wiz8_v128.exe'))) 'shortcut -> Wiz8_v128.exe'
$m1 = Read-Manifest $g
Check ($m1.backedUp.Count -eq 1 -and $m1.backedUp[0] -eq '3DVideo.CFG') 'only 3DVideo.CFG backed up'

Set-Content -LiteralPath (Join-Path $g 'wiz8hd.ini') -Value '[HD]' -Encoding ASCII     # the player's own settings
Run 'install.ps1' ($common + @{ GamePath = $g })
$m2 = Read-Manifest $g
Check ($m2.backedUp.Count -eq 1 -and $m2.created.Count -eq $m1.created.Count) 'second install: same manifest, originals not overwritten'
Check ((Get-Content -LiteralPath (Join-Path $g 'wiz8hd.ini') -Raw).Trim() -eq '[HD]') 'second install keeps wiz8hd.ini'
Check ((Get-Content -LiteralPath (Join-Path $g '_wiz8_4k\backup\3DVideo.CFG') -Raw).StartsWith('Glide2x')) 'backup still holds the Steam 3DVideo.CFG'

Set-Content -LiteralPath (Join-Path $g 'wiz8hd.log') -Value 'log' -Encoding ASCII      # written by the mod in game
Run 'uninstall.ps1' @{ GamePath = $g }
Check (Same $before (Snapshot $g)) 'uninstall: folder byte-identical to the Steam state'
Check (-not (Test-Path $regKey)) 'uninstall: test nGlide key removed (it did not exist)'
Check (-not (Test-Path $lnk)) 'uninstall: shortcut removed'

# ---------- B: a folder already set up by hand ----------
Write-Host 'B: hand-made setup (old dgVoodoo, own ini, splash=1, old shortcut) -> install -> uninstall'
$g = New-Game 'manual'
Set-Content -LiteralPath (Join-Path $g 'DDraw.dll') -Value 'old ddraw' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $g 'dgVoodoo.conf') -Value 'old conf' -Encoding ASCII
Set-Content -LiteralPath (Join-Path $g 'wiz8hd.ini') -Value '[HD]' -Encoding ASCII
New-Item -ItemType Directory (Join-Path $g 'wiz8hd_fonts') | Out-Null
Set-Content -LiteralPath (Join-Path $g 'wiz8hd_fonts\Mine.ttf') -Value 'font' -Encoding ASCII
New-Item -Path $regKey -Force | Out-Null
New-ItemProperty -Path $regKey -Name Splash -Value 1 -PropertyType DWord | Out-Null
New-ItemProperty -Path $regKey -Name Backend -Value '2' -PropertyType String | Out-Null
Set-Content -LiteralPath $lnk -Value 'old shortcut' -Encoding ASCII
$before = Snapshot $g
$lnkHash = Get-Sha256 $lnk
Run 'install.ps1' ($common + @{ GamePath = $g })
Check ((Get-Sha256 (Join-Path $g 'dgVoodoo.conf')) -eq (Get-Sha256 (Join-Path $payload 'dgVoodoo.conf'))) 'foreign dgVoodoo.conf replaced'
Check ((Get-Content -LiteralPath (Join-Path $g 'wiz8hd.ini') -Raw).Trim() -eq '[HD]') 'existing wiz8hd.ini kept'
Check ((Get-ItemProperty $regKey).Splash -eq 0) 'Splash = 0'
Run 'uninstall.ps1' @{ GamePath = $g }
Check (Same $before (Snapshot $g)) 'uninstall: hand-made setup restored byte for byte'
Check ((Get-ItemProperty $regKey).Splash -eq 1 -and (Get-ItemProperty $regKey).Backend -eq '2') 'Splash back to 1, other values untouched'
Check ((Get-Sha256 $lnk) -eq $lnkHash) 'old shortcut restored'

# ---------- C: refusals ----------
Write-Host 'C: refusals'
$g = New-Game 'wrongexe'
[IO.File]::AppendAllText((Join-Path $g 'Wiz8_v128.exe'), 'x')
$before = Snapshot $g
$threw = $false
try { & (Join-Path $repo 'install.ps1') @common -GamePath $g *>$null } catch { $threw = $true }
Check ($threw -and (Same $before (Snapshot $g))) 'unknown Wiz8_v128.exe: refused, nothing changed'
Remove-Item -LiteralPath (Join-Path $g 'Wiz8_v128.exe')
$threw = $false
try { & (Join-Path $repo 'install.ps1') @common -GamePath $g *>$null } catch { $threw = $_.Exception.Message -match 'Fan Patch' }
Check $threw 'no Wiz8_v128.exe: refused with a Fan Patch hint'
$g = New-Game 'nozip'
Remove-Item -LiteralPath (Join-Path $g 'mods\dgVoodoo2_87_5.zip')
$before = Snapshot $g
$threw = $false
try { & (Join-Path $repo 'install.ps1') @common -GamePath $g *>$null } catch { $threw = $true }
Check $threw 'no dgVoodoo zip with -Offline: refused'
Run 'uninstall.ps1' @{ GamePath = $g }
Check (Same $before (Snapshot $g)) 'failed install rolled back by uninstall'

Check ((Real-State) -eq $realBefore) 'real nGlide key and real Desktop shortcut untouched'
Remove-Item 'HKCU:\Software\Wiz8_4k_test' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $work -Recurse -Force
Write-Host ''
if ($script:fails) { Write-Host "$script:fails check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'all checks passed' -ForegroundColor Green
