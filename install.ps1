<#
.SYNOPSIS
  Wizardry 8 (Steam) for 4K / any native resolution, borderless, with the wiz8hd HD interface mod.
.DESCRIPTION
  Needs the Steam version with the community Fan Patch 1.28 (Wiz8_v128.exe) extracted into the game folder;
  Steam does not ship it (see README, "Требования"). dgVoodoo2 comes from mods\dgVoodoo2_87_5.zip or GitHub.
    1. 3DVideo.CFG: DirectX7_1 renderer at the display's native resolution, 32-bit.
    2. dgVoodoo2 2.87.5 (DDraw.dll, D3DImm.dll, dgVoodooCpl.exe) + dgVoodoo.conf: fake fullscreen
       (borderless over the whole screen), 16x anisotropic, 8x MSAA, no watermark.
    3. wiz8hd.asi + wiz8hd.ini + wiz8hd_fonts\ + wiz8hd_bg\: HD TrueType text, HUD at the screen edges,
       wide HD menu/loading/camp pictures (Miles loads *.asi from the game folder).
    4. nGlide: 3dfx splash off (HKCU\Software\Zeus Software\nGlide2 Splash=0).
    5. Desktop shortcut "Wizardry 8 (Fan Patch 4K)" -> Wiz8_v128.exe (Steam's Play button runs the
       original Wiz8.exe 1.2.4, where the mod stays inactive).
  Every replaced file is kept in <game>\_wiz8_4k\backup and listed in _wiz8_4k\manifest.json;
  uninstall.ps1 puts everything back. Running install.ps1 again updates in place (originals stay backed up).
.EXAMPLE
  .\install.ps1
  .\install.ps1 -GamePath "D:\Steam\steamapps\common\Wizardry8" -Width 2560 -Height 1440
  .\install.ps1 -WhatIf
#>
[CmdletBinding()]
param(
    [string]$GamePath,
    [int]$Width,
    [int]$Height,
    [switch]$NoHdUi,             # only the 4K/borderless setup, no wiz8hd mod
    [switch]$NoBackgrounds,      # the mod without the HD background pack
    [switch]$ResetConfig,        # overwrite an existing wiz8hd.ini / dgVoodoo.conf with the defaults
    [switch]$NoShortcut,
    [string]$ShortcutDir = [Environment]::GetFolderPath('Desktop'),
    [switch]$SkipNGlide,
    [string]$NGlideKey,          # registry key override (tests)
    [switch]$Offline,            # never download dgVoodoo2 when mods\ lacks it
    [switch]$DetectOnly,         # print the game folder and checks, change nothing
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\Common.ps1')
if (-not $NGlideKey) { $NGlideKey = $script:DefaultNGlideKey }
$payload = Join-Path $PSScriptRoot 'payload'

# ---------- checks ----------
Write-Step 'Game folder'
$GamePath = Resolve-GamePath $GamePath
Write-Info $GamePath

$exe = Join-Path $GamePath 'Wiz8_v128.exe'
if (-not (Test-Path -LiteralPath $exe)) {
    $fp = Get-ChildItem -LiteralPath (Join-Path $GamePath 'mods') -Filter 'Wizardry8FanPatch*.7z' -ErrorAction SilentlyContinue | Select-Object -First 1
    $hint = if ($fp) { "Extract mods\$($fp.Name) into the game folder" } else { 'Download Wizardry 8 Fan Patch 1.28 (build 6709, see README) and extract it into the game folder' }
    throw "Wiz8_v128.exe (Fan Patch 1.28) not found. $hint, then run this again."
}
$exeHash = Get-Sha256 $exe
if (-not $script:Known['Wiz8_v128.exe'].ContainsKey($exeHash)) {
    throw "Wiz8_v128.exe has an unknown SHA-256 ($exeHash). The mod patches this exact exe; refusing to install."
}
Write-Info ('Wiz8_v128.exe: ' + $script:Known['Wiz8_v128.exe'][$exeHash])
$dll = Join-Path $GamePath 'Wiz8.dll'
if (Test-Path -LiteralPath $dll) {
    $h = Get-Sha256 $dll
    if ($script:Known['Wiz8.dll'].ContainsKey($h)) { Write-Info ('Wiz8.dll: ' + $script:Known['Wiz8.dll'][$h]) }
    else { Write-Warn2 "Wiz8.dll is a Fan Patch build this package was not checked with ($h)." }
}
if (-not $Width -or -not $Height) {
    $r = Get-NativeResolution
    if (-not $Width) { $Width = $r[0] }
    if (-not $Height) { $Height = $r[1] }
}
Write-Info "resolution: ${Width}x${Height}"
if (Test-Path -LiteralPath (Join-Path (Get-StateDir $GamePath) 'manifest.json')) { Write-Info 'already installed: updating in place' }
if ($DetectOnly) { return }
if (-not $WhatIf) { Assert-GameNotRunning $GamePath }

$m = Read-Manifest $GamePath
if (-not $m) { $m = New-Manifest $GamePath }
$m.installed = (Get-Date -Format 's')
$m.payload = ((Get-Content -LiteralPath (Join-Path $payload 'VERSION.txt') -TotalCount 1) -replace '^wizardry8-hdui: ', '')

function Put-File([string]$src, [string]$rel) {
    Register-Target $m $GamePath $rel -WhatIf:$WhatIf
    if ($WhatIf) { Write-Info "write   $rel"; return }
    Copy-Item -LiteralPath $src -Destination (Join-Path $GamePath $rel) -Force
}

function Put-Text([string]$text, [string]$rel) {
    Register-Target $m $GamePath $rel -WhatIf:$WhatIf
    if ($WhatIf) { Write-Info "write   $rel"; return }
    [IO.File]::WriteAllText((Join-Path $GamePath $rel), $text, (New-Object Text.ASCIIEncoding))
}

try {
    # ---------- 1. renderer and resolution ----------
    Write-Step "3DVideo.CFG: DirectX7_1 ${Width}x${Height}x32"
    $cfg = Join-Path $GamePath '3DVideo.CFG'
    $audio = 'Miles Fast 2D Positional Audio'
    if (Test-Path -LiteralPath $cfg) {
        $lines = @(Get-Content -LiteralPath $cfg)
        if ($lines.Count -ge 5 -and $lines[4].Trim()) { $audio = $lines[4].Trim() }
    }
    Put-Text ("DirectX7_1`r`n$Width`r`n$Height`r`n32`r`n$audio`r`n") '3DVideo.CFG'

    # ---------- 2. dgVoodoo2 ----------
    Write-Step 'dgVoodoo2 2.87.5'
    $zip = Join-Path $GamePath $script:DgVoodoo.Zip
    $tmpZip = $null
    if (-not (Test-Path -LiteralPath $zip) -or (Get-Sha256 $zip) -ne $script:DgVoodoo.Sha256) {
        if ($Offline) { throw "$($script:DgVoodoo.Zip) is missing or different, and -Offline was given." }
        $tmpZip = Join-Path $env:TEMP 'dgVoodoo2_87_5.zip'
        Write-Info "downloading $($script:DgVoodoo.Url)"
        if (-not $WhatIf) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $script:DgVoodoo.Url -OutFile $tmpZip -UseBasicParsing
            if ((Get-Sha256 $tmpZip) -ne $script:DgVoodoo.Sha256) { Remove-Item $tmpZip -Force; throw 'Downloaded dgVoodoo2 zip has a wrong SHA-256.' }
        }
        $zip = $tmpZip
    }
    if ($WhatIf) {
        foreach ($rel in $script:DgVoodoo.Files.Values) { Register-Target $m $GamePath $rel -WhatIf; Write-Info "write   $rel" }
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $script:DgVoodoo.Files.Keys) {
                $rel = $script:DgVoodoo.Files[$entry]
                $e = $z.GetEntry($entry)
                if (-not $e) { throw "dgVoodoo2 zip has no $entry" }
                Register-Target $m $GamePath $rel
                [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $GamePath $rel), $true)
            }
        } finally { $z.Dispose() }
        if ($tmpZip) { Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue }
    }
    $conf = Join-Path $GamePath 'dgVoodoo.conf'
    if ((Test-Listed $m.created 'dgVoodoo.conf') -or (Test-Listed $m.backedUp 'dgVoodoo.conf')) {
        if ($ResetConfig) { Put-File (Join-Path $payload 'dgVoodoo.conf') 'dgVoodoo.conf' }
        else { Write-Info 'dgVoodoo.conf kept (installed earlier; -ResetConfig replaces it)' }
    } else {
        Put-File (Join-Path $payload 'dgVoodoo.conf') 'dgVoodoo.conf'
    }

    # ---------- 3. HD interface mod ----------
    if (-not $NoHdUi) {
        Write-Step 'wiz8hd HD interface'
        Put-File (Join-Path $payload 'wiz8hd.asi') 'wiz8hd.asi'
        if ((Test-Path -LiteralPath (Join-Path $GamePath 'wiz8hd.ini')) -and -not $ResetConfig) {
            Write-Info 'wiz8hd.ini kept (exists; -ResetConfig replaces it)'
        } else {
            Put-File (Join-Path $payload 'wiz8hd.ini') 'wiz8hd.ini'
        }
        $dirs = @('wiz8hd_fonts')
        if (-not $NoBackgrounds) { $dirs += 'wiz8hd_bg' }
        foreach ($d in $dirs) {
            Ensure-Dir $m $GamePath $d -WhatIf:$WhatIf
            $files = Get-ChildItem -LiteralPath (Join-Path $payload $d) -File
            foreach ($f in $files) {
                Register-Target $m $GamePath "$d\$($f.Name)" -WhatIf:$WhatIf
                if (-not $WhatIf) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $GamePath "$d\$($f.Name)") -Force }
            }
            Write-Info "$d\ ($($files.Count) files)"
        }
    }

    # ---------- 4. nGlide splash ----------
    if (-not $SkipNGlide) {
        Write-Step '3dfx splash off (nGlide)'
        if (-not $m.registry) {
            $old = $null; $keyExisted = Test-Path $NGlideKey
            if ($keyExisted) { $old = (Get-ItemProperty -Path $NGlideKey -ErrorAction SilentlyContinue).Splash }
            $m.registry = [ordered]@{ key = $NGlideKey; keyExisted = $keyExisted; valueExisted = ($null -ne $old); value = $old }
        }
        if (-not $WhatIf) {
            if (-not (Test-Path $NGlideKey)) { New-Item -Path $NGlideKey -Force | Out-Null }
            New-ItemProperty -Path $NGlideKey -Name Splash -Value 0 -PropertyType DWord -Force | Out-Null
        }
        Write-Info "$NGlideKey Splash = 0"
    }

    # ---------- 5. shortcut ----------
    if (-not $NoShortcut) {
        Write-Step 'Desktop shortcut'
        $lnk = Join-Path $ShortcutDir $script:ShortcutName
        if (-not $m.shortcut) {
            $bak = $null
            if (Test-Path -LiteralPath $lnk) {
                $bak = Join-Path (Get-StateDir $GamePath) ('backup_' + $script:ShortcutName)
                if (-not $WhatIf) { New-Item -ItemType Directory -Force (Get-StateDir $GamePath) | Out-Null; Copy-Item -LiteralPath $lnk $bak -Force }
            }
            $m.shortcut = [ordered]@{ path = $lnk; backup = $bak }
        }
        if (-not $WhatIf) {
            $sh = New-Object -ComObject WScript.Shell
            $s = $sh.CreateShortcut($lnk)
            $s.TargetPath = $exe
            $s.WorkingDirectory = $GamePath
            $s.IconLocation = "$exe,0"
            $s.Description = 'Wizardry 8, Fan Patch 1.28, 4K borderless + HD interface'
            $s.Save()
        }
        Write-Info $lnk
    }
} finally {
    if (-not $WhatIf) { Save-Manifest $m $GamePath }
}

Write-Step 'Done'
if ($WhatIf) { Write-Info 'WhatIf: nothing was changed.'; return }
Write-Info "Backup and manifest: $(Get-StateDir $GamePath)"
Write-Info 'Start the game with the "Wizardry 8 (Fan Patch 4K)" shortcut (or Wiz8_v128.exe), not Steam''s Play button.'
Write-Info 'Undo everything: uninstall.ps1'
