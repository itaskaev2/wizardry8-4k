<#
.SYNOPSIS
  Refresh payload\ from a wizardry8-hdui checkout (built dist\) and a configured game folder.
.DESCRIPTION
  Copies wiz8hd.asi, the wiz8hd.ini template, wiz8hd_fonts\ and wiz8hd_bg\ from <HdUi>\dist and
  dgVoodoo.conf from <GameConf>, then writes payload\VERSION.txt with the source commit.
  Run it after rebuilding the mod (wizardry8-hdui: ./build.sh, copy build\wiz8hd.asi to dist\).
#>
param(
    [string]$HdUi = (Join-Path $PSScriptRoot '..\..\wizardry8-hdui'),
    [string]$GameConf = ''
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$payload = Join-Path $repo 'payload'
$dist = Join-Path $HdUi 'dist'
if (-not (Test-Path (Join-Path $dist 'wiz8hd.asi'))) { throw "No wiz8hd.asi in $dist" }

New-Item -ItemType Directory -Force $payload | Out-Null
Copy-Item (Join-Path $dist 'wiz8hd.asi') $payload -Force
foreach ($d in 'wiz8hd_fonts', 'wiz8hd_bg') {
    $dst = Join-Path $payload $d
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item (Join-Path $dist $d) $dst -Recurse
}
# the ini template: the dist one plus the background switch, logging off
$ini = Get-Content (Join-Path $dist 'wiz8hd.ini') -Raw
$ini = $ini -replace "(?m)^Log=1\r?$", 'Log=0'
if ($ini -notmatch '(?m)^Backgrounds=') {
    $ini = $ini -replace "(?m)^(KeepActive=\d)\r?$", "`$1`r`n; 1 = wide HD menu, loading and camp pictures from wiz8hd_bg\`r`nBackgrounds=1"
}
$ini = ($ini -replace "`r`n", "`n") -replace "`n", "`r`n"
[IO.File]::WriteAllText((Join-Path $payload 'wiz8hd.ini'), $ini, (New-Object Text.ASCIIEncoding))
if ($GameConf) { Copy-Item $GameConf (Join-Path $payload 'dgVoodoo.conf') -Force }

Push-Location $HdUi
try { $commit = (git log -1 --format='%h %s') } finally { Pop-Location }
$asiHash = (Get-FileHash (Join-Path $payload 'wiz8hd.asi') -Algorithm SHA256).Hash.ToLower()
@(
    "wizardry8-hdui: $commit"
    "wiz8hd.asi sha256: $asiHash"
    "backgrounds: $((Get-ChildItem (Join-Path $payload 'wiz8hd_bg') -Filter *.raw).Count)"
    "updated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
) | Set-Content (Join-Path $payload 'VERSION.txt') -Encoding ASCII
Get-Content (Join-Path $payload 'VERSION.txt')
