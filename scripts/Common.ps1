# Shared helpers for install.ps1 / uninstall.ps1 (Windows PowerShell 5.1 compatible).

$script:StateDirName = '_wiz8_4k'          # inside the game folder: manifest.json + backup\
$script:SteamAppId = '245450'

# Known files. Wiz8_v128.exe is what the mod is written against; anything else is refused.
$script:Known = @{
    'Wiz8_v128.exe' = @{
        'fdca6d9cd0940034191e82b8e2900de26bb25e381c74128dcb8967360a9fb824' = 'Fan Patch 1.28 (build 1.2.8)'
        '487612705c728f7c2c0127a8fafac434fc0a20f1cae1f5546e9231f2d39f09b3' = 'Fan Patch 1.28 (build 1.2.8), Large Address Aware'
    }
    'Wiz8.dll'      = @{
        '28953363c6090f12a7a466397b619c43e6f26da28dbc5f8554d822ee66259378' = 'Fan Patch 1.28 build 6709'
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
$script:LfsBatchUrl = 'https://github.com/itaskaev2/wizardry8-4k.git/info/lfs/objects/batch'

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Info([string]$msg) { Write-Host "    $msg" }
function Write-Warn2([string]$msg) { Write-Host "    WARNING: $msg" -ForegroundColor Yellow }

function Get-Sha256([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

# Large Address Aware (flag 0x20 in the PE file header): the 32-bit game gets 4 GB of address space on 64-bit
# Windows instead of 2 GB. HD 3D textures need it (Arnika ran out of address space and crashed in the renderer).
# Wiz8_v128.exe has no PE checksum, so this one flag is the whole change.
function Get-PeCharacteristicsOffset([byte[]]$b) { [BitConverter]::ToInt32($b, 0x3C) + 22 }

function Test-LargeAddressAware([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    return [bool]([BitConverter]::ToUInt16($b, (Get-PeCharacteristicsOffset $b)) -band 0x20)
}

function Set-LargeAddressAware([string]$path, [bool]$on = $true) {
    $b = [IO.File]::ReadAllBytes($path)
    $off = Get-PeCharacteristicsOffset $b
    $ch = [BitConverter]::ToUInt16($b, $off)
    $new = if ($on) { $ch -bor 0x20 } else { $ch -band 0xFFDF }
    if ($new -eq $ch) { return $false }
    $nb = [BitConverter]::GetBytes([uint16]$new)
    $b[$off] = $nb[0]; $b[$off + 1] = $nb[1]
    [IO.File]::WriteAllBytes($path, $b)
    return $true
}

# GitHub's "Download ZIP" has Git LFS pointer stubs in place of the fonts, backgrounds and portraits.
function Get-LfsPointers([string[]]$dirs) {
    foreach ($d in $dirs) {
        foreach ($f in Get-ChildItem -LiteralPath $d -File -Recurse) {
            if ($f.Length -ge 200) { continue }
            $t = [IO.File]::ReadAllText($f.FullName)
            if ($t -match '^version https://git-lfs\.github\.com/spec/v1\s+oid sha256:([0-9a-f]{64})\s+size (\d+)') {
                [pscustomobject]@{ Path = $f.FullName; Oid = $Matches[1]; Size = [long]$Matches[2] }
            }
        }
    }
}

# Replace the stubs with the real files: the LFS batch API gives a download link per SHA-256, checked after download.
function Restore-LfsFiles($pointers) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    $byOid = @{}
    foreach ($p in $pointers) { $byOid[$p.Oid] += @($p) }
    $oids = @($byOid.Keys)
    for ($i = 0; $i -lt $oids.Count; $i += 50) {
        $chunk = $oids[$i..([Math]::Min($i + 49, $oids.Count - 1))]
        $body = @{ operation = 'download'; transfers = @('basic')
                   objects = @($chunk | ForEach-Object { @{ oid = $_; size = $byOid[$_][0].Size } }) } | ConvertTo-Json -Depth 4
        $r = Invoke-RestMethod -Method Post -Uri $script:LfsBatchUrl -Body $body -ContentType 'application/vnd.git-lfs+json' `
                               -Headers @{ Accept = 'application/vnd.git-lfs+json' } -UseBasicParsing
        foreach ($o in $r.objects) {
            if ($o.error) { throw "Git LFS $($o.oid): $($o.error.message)" }
            $h = @{}
            if ($o.actions.download.header) { $o.actions.download.header.PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }
            $tmp = [IO.Path]::GetTempFileName()
            try {
                Invoke-WebRequest -Uri $o.actions.download.href -Headers $h -OutFile $tmp -UseBasicParsing
                if ((Get-Sha256 $tmp) -ne $o.oid) { throw "Git LFS $($o.oid): downloaded file has a wrong SHA-256" }
                foreach ($p in $byOid[$o.oid]) { Copy-Item -LiteralPath $tmp -Destination $p.Path -Force }
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
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

# created + backedUp as a case-insensitive set: Test-Listed is a linear scan, too slow for thousands of textures.
function Get-ListedSet($m) {
    $n = $m.created.Count + $m.backedUp.Count
    if (-not $script:ListedSet -or $script:ListedSetCount -ne $n) {
        $script:ListedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($x in $m.created) { [void]$script:ListedSet.Add($x) }
        foreach ($x in $m.backedUp) { [void]$script:ListedSet.Add($x) }
        $script:ListedSetCount = $n
    }
    return , $script:ListedSet          # the comma keeps PowerShell from unrolling an empty set into $null
}

# Before writing <game>\<rel>: remember it was created, or keep the original once in backup\.
function Register-Target($m, [string]$GamePath, [string]$rel, [switch]$WhatIf) {
    $set = Get-ListedSet $m
    if ($set.Contains($rel)) { return }
    [void]$set.Add($rel); $script:ListedSetCount++
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
