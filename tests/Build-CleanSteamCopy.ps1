<#
.SYNOPSIS
  Rebuild the files of a fresh Steam install of Wizardry 8 in a separate folder, for an in-game test of install.ps1.
.DESCRIPTION
  Reads an inventory (CSV Path,Size,SHA256 taken right after the Steam install) and copies every listed file
  whose SHA-256 matches from the first source folder that has it. Sources are only read. Files nobody has with
  the right hash are reported and the script fails.
.EXAMPLE
  .\Build-CleanSteamCopy.ps1 -Inventory game.csv,mods.csv -Sources F:\Steam\...\Wizardry8,D:\backup\root -Target F:\Wiz8_steamtest
#>
param(
    [Parameter(Mandatory)][string[]]$Inventory,
    # folders to look in, each searched as <source>\<Path> and <source>\<file name> (flat backups)
    [Parameter(Mandatory)][string[]]$Sources,
    [Parameter(Mandatory)][string]$Target
)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Target) { throw "$Target exists; remove it first." }
$rows = foreach ($csv in $Inventory) { Import-Csv -LiteralPath $csv }
$missing = @()
$n = 0
foreach ($r in $rows) {
    $want = $r.SHA256.ToLower()
    $found = $null
    foreach ($s in $Sources) {
        foreach ($cand in @((Join-Path $s $r.Path), (Join-Path $s (Split-Path $r.Path -Leaf)))) {
            if ((Test-Path -LiteralPath $cand -PathType Leaf) -and (Get-Item -LiteralPath $cand).Length -eq [long]$r.Size -and
                (Get-FileHash -LiteralPath $cand -Algorithm SHA256).Hash.ToLower() -eq $want) { $found = $cand; break }
        }
        if ($found) { break }
    }
    if (-not $found) { $missing += $r.Path; continue }
    $dst = Join-Path $Target $r.Path
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item -LiteralPath $found -Destination $dst
    $n++
}
Write-Host "copied $n of $($rows.Count) files to $Target"
if ($missing) { $missing | ForEach-Object { Write-Host "  missing: $_" -ForegroundColor Red }; exit 1 }
