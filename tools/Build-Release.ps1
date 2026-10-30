<#
.SYNOPSIS
  Build the release zips: unpack both into one folder and run install.cmd, nothing else to download but the Fan Patch.
.DESCRIPTION
  <Out>\Wizardry8-4K-<Version>.zip           Wizardry8-4K\ with install/uninstall, scripts\, payload\ (real files,
                                             not Git LFS stubs), mods\dgVoodoo2_87_5.zip (the original package; its
                                             author allows shipping it with a game mod), README*, docs\
  <Out>\Wizardry8-4K-<Version>-textures.zip  Wizardry8-4K\textures\ = the HD 3D-world textures as loose TGAs, made
                                             by wizardry8-hdui tools\tex_hd.py install (capped at 512 px)
  The Fan Patch (a modified game exe, no licence to redistribute) and the game itself are not included.
  A GitHub release asset must stay under 2 GiB, hence two zips.
.EXAMPLE
  .\tools\Build-Release.ps1 -Version 1.0 -Out F:\Wiz8HD_release
#>
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$Out,
    [string]$HdUi = (Join-Path $PSScriptRoot '..\..\wizardry8-hdui'),
    [string]$DgVoodooZip = 'F:\SteamLibrary\steamapps\common\Wizardry8\mods\dgVoodoo2_87_5.zip',
    [string]$Python = 'python',
    [switch]$NoTextures
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'scripts\Common.ps1')
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
if (-not (Test-Path $sevenZip)) { throw '7-Zip not found (C:\Program Files\7-Zip\7z.exe)' }
if ((Get-Sha256 $DgVoodooZip) -ne $script:DgVoodoo.Sha256) { throw "$DgVoodooZip is not dgVoodoo2 2.87.5" }
$stubs = @(Get-LfsPointers @(Join-Path $repo 'payload'))
if ($stubs.Count) { throw "payload\ has $($stubs.Count) Git LFS stubs: run git lfs pull first" }

$stage = Join-Path $Out 'stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$pkg = Join-Path $stage 'Wizardry8-4K'
New-Item -ItemType Directory -Force (Join-Path $pkg 'mods') | Out-Null
foreach ($f in 'install.cmd', 'install.ps1', 'uninstall.cmd', 'uninstall.ps1', 'README.md', 'README.en.md') {
    Copy-Item (Join-Path $repo $f) $pkg
}
foreach ($d in 'scripts', 'payload', 'docs') { Copy-Item (Join-Path $repo $d) (Join-Path $pkg $d) -Recurse }
Copy-Item $DgVoodooZip (Join-Path $pkg 'mods')

$main = Join-Path $Out "Wizardry8-4K-$Version.zip"
if (Test-Path $main) { Remove-Item $main -Force }
& $sevenZip a -tzip -mx=5 -mmt=on $main (Join-Path $stage 'Wizardry8-4K') -bso0 -bsp0
if ($LASTEXITCODE) { throw "7-Zip failed ($LASTEXITCODE)" }
Write-Host ("{0}  {1:N0} MB" -f $main, ((Get-Item $main).Length / 1MB))

if (-not $NoTextures) {
    $texStage = Join-Path $Out 'stage_tex'
    if (Test-Path $texStage) { Remove-Item $texStage -Recurse -Force }
    $tex = Join-Path $texStage 'Wizardry8-4K\textures'
    New-Item -ItemType Directory -Force $tex | Out-Null
    & $Python (Join-Path $HdUi 'tools\tex_hd.py') install $tex
    if ($LASTEXITCODE) { throw "tex_hd.py install failed ($LASTEXITCODE)" }
    Remove-Item (Join-Path $tex 'wiz8hd_tex_files.txt') -Force
    $texZip = Join-Path $Out "Wizardry8-4K-$Version-textures.zip"
    if (Test-Path $texZip) { Remove-Item $texZip -Force }
    & $sevenZip a -tzip -mx=5 -mmt=on $texZip (Join-Path $texStage 'Wizardry8-4K') -bso0 -bsp0
    if ($LASTEXITCODE) { throw "7-Zip failed ($LASTEXITCODE)" }
    $len = (Get-Item $texZip).Length
    Write-Host ("{0}  {1:N0} MB" -f $texZip, ($len / 1MB))
    if ($len -ge 2GB) { throw 'textures zip is over the 2 GiB GitHub release asset limit' }
}
Remove-Item $stage -Recurse -Force
if (-not $NoTextures) { Remove-Item $texStage -Recurse -Force }
Get-FileHash (Join-Path $Out "Wizardry8-4K-$Version*.zip") -Algorithm SHA256 | ForEach-Object {
    '{0}  {1}' -f $_.Hash.ToLower(), (Split-Path $_.Path -Leaf)
} | Set-Content (Join-Path $Out 'SHA256SUMS.txt') -Encoding ASCII
Get-Content (Join-Path $Out 'SHA256SUMS.txt')
