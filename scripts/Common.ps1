# Shared helpers for install.ps1 / uninstall.ps1 (Windows PowerShell 5.1 compatible).

$script:StateDirName = '_wiz8_4k'          # inside the game folder: manifest.json + backup\
$script:SteamAppId = '245450'

# Known files. Wiz8_v128.exe is what the mod is written against; anything else is refused.
$script:Known = @{
    'Wiz8_v128.exe' = @{ 'fdca6d9cd0940034191e82b8e2900de26bb25e381c74128dcb8967360a9fb824' = 'Fan Patch 1.28 (build 1.2.8)' }
    'Wiz8.dll'      = @{
        '28953363c6090f12a7a466397b619c43e6f26da28dbc5f8554d822ee66259378' = 'Fan Patch 1.28 build 6709 (as shipped by Steam)'
        '702851cf5bc09d9d5c749f11c5c058e62a27f4be8975718f54cceb6c127da612' = 'Fan Patch 1.28 build 6735 (Mini-Update)'
    }
}
$script:DgVoodoo = @{
    Zip      = 'mods\dgVoodoo2_87_5.zip'
    Sha256   = '5ffde6927f7355ca3fdd5d785b581256a8e6539fa13e395a891ade6ba1040850'
    Url      = 'https://github.com/dege-diosg/dgVoodoo2/releases/download/v2.87.5/dgVoodoo2_87_5.zip'
    # zip entry -> game file
    Files    = [ordered]@{ 'MS/x86/DDraw.dll' = 'DDraw.dll'; 'MS/x86/D3DImm.dll' = 'D3DImm.dll'; 'dgVoodooCpl.exe' = 'dgVoodooCpl.exe' }
}
$script:DefaultNGlideKey = 'HKCU:\Software\Zeus Software\nGlide2'
$script:ShortcutName = 'Wizardry 8 (Fan Patch 4K).lnk'

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Info([string]$msg) { Write-Host "    $msg" }
function Write-Warn2([string]$msg) { Write-Host "    WARNING: $msg" -ForegroundColor Yellow }

function Get-Sha256([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

# Steam: SteamPath from the registry, every library from libraryfolders.vdf, the app manifest names the folder.
function Find-Wiz8Path {
    $roots = @()
    foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = Get-ItemProperty -Path $k -ErrorAction Stop
            foreach ($n in 'SteamPath', 'InstallPath') {
                if ($p.$n) { $roots += ($p.$n -replace '/', '\') }
            }
        } catch {}
    }
    $libs = @()
    foreach ($r in ($roots | Select-Object -Unique)) {
        $libs += $r
        $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $acf = Join-Path $lib "steamapps\appmanifest_$script:SteamAppId.acf"
        if (Test-Path -LiteralPath $acf) {
            $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"installdir"\s+"([^"]+)"')
            if ($m.Success) {
                $dir = Join-Path $lib ("steamapps\common\" + $m.Groups[1].Value)
                if (Test-Path -LiteralPath $dir) { return $dir }
            }
        }
    }
    return $null
}

function Resolve-GamePath([string]$GamePath) {
    if (-not $GamePath) {
        $GamePath = Find-Wiz8Path
        if (-not $GamePath) { throw 'Wizardry 8 (Steam app 245450) not found. Pass -GamePath "<game folder>".' }
    }
    $GamePath = (Resolve-Path -LiteralPath $GamePath).Path
    if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'Wiz8.exe')) -and
        -not (Test-Path -LiteralPath (Join-Path $GamePath 'Wiz8_v128.exe'))) {
        throw "$GamePath does not look like a Wizardry 8 folder (no Wiz8.exe / Wiz8_v128.exe)."
    }
    return $GamePath
}

# Refuse to touch files of a running game.
function Assert-GameNotRunning([string]$GamePath) {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($GamePath + '\', [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    }
    if ($running) {
        throw ("The game is running from this folder (" + (($running | ForEach-Object { $_.ProcessName }) -join ', ') + '). Close it first.')
    }
}

# Physical size of the primary display (not DPI-scaled).
function Get-NativeResolution {
    if (-not ('Wiz8Disp' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Wiz8Disp {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    public static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
    public static int[] Current() {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(null, -1, ref dm)) return null;
        return new int[] { dm.dmPelsWidth, dm.dmPelsHeight };
    }
}
'@
    }
    $r = [Wiz8Disp]::Current()
    if (-not $r -or $r[0] -lt 640) { throw 'Could not read the display resolution. Pass -Width and -Height.' }
    return $r
}

# ---------- manifest: what the install created and what it replaced ----------

function Get-StateDir([string]$GamePath) { Join-Path $GamePath $script:StateDirName }

function Read-Manifest([string]$GamePath) {
    $f = Join-Path (Get-StateDir $GamePath) 'manifest.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
    $m = [ordered]@{
        version = $j.version; gamePath = $j.gamePath; installed = $j.installed; payload = $j.payload
        created = [System.Collections.ArrayList]@(); createdDirs = [System.Collections.ArrayList]@()
        backedUp = [System.Collections.ArrayList]@(); registry = $j.registry; shortcut = $j.shortcut
    }
    foreach ($n in 'created', 'createdDirs', 'backedUp') { foreach ($x in @($j.$n)) { if ($x) { [void]$m[$n].Add([string]$x) } } }
    return $m
}

function New-Manifest([string]$GamePath) {
    [ordered]@{
        version = 1; gamePath = $GamePath; installed = ''; payload = ''
        created = [System.Collections.ArrayList]@(); createdDirs = [System.Collections.ArrayList]@()
        backedUp = [System.Collections.ArrayList]@(); registry = $null; shortcut = $null
    }
}

function Save-Manifest($m, [string]$GamePath) {
    $dir = Get-StateDir $GamePath
    New-Item -ItemType Directory -Force $dir | Out-Null
    $m | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding UTF8
}

function Test-Listed($list, [string]$rel) {
    foreach ($x in $list) { if ($x -ieq $rel) { return $true } }
    return $false
}

# Before writing <game>\<rel>: remember it was created, or keep the original once in backup\.
function Register-Target($m, [string]$GamePath, [string]$rel, [switch]$WhatIf) {
    if ((Test-Listed $m.created $rel) -or (Test-Listed $m.backedUp $rel)) { return }
    $full = Join-Path $GamePath $rel
    if (Test-Path -LiteralPath $full) {
        $bak = Join-Path (Join-Path (Get-StateDir $GamePath) 'backup') $rel
        if (-not $WhatIf) {
            New-Item -ItemType Directory -Force (Split-Path $bak -Parent) | Out-Null
            Copy-Item -LiteralPath $full -Destination $bak -Force
        }
        [void]$m.backedUp.Add($rel)
        Write-Info "backup  $rel"
    } else {
        [void]$m.created.Add($rel)
    }
}

function Ensure-Dir($m, [string]$GamePath, [string]$relDir, [switch]$WhatIf) {
    $full = Join-Path $GamePath $relDir
    if (Test-Path -LiteralPath $full) { return }
    if (-not $WhatIf) { New-Item -ItemType Directory -Force $full | Out-Null }
    if (-not (Test-Listed $m.createdDirs $relDir)) { [void]$m.createdDirs.Add($relDir) }
}
