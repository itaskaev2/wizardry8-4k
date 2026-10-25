# Russian location texts (diaries, signs, bookshelves...) for the Steam game with a Russian translation (Data\RUS.SLF).
# The game reads them from Data\Messages\<LEVEL>.MSG, which only DATA.SLF has (English); RUS.SLF has none. The Fan Patch
# ships both languages as plain text in Data\FanPatch.Dat (LOCALIZATION\ORIGINAL\MESSAGES\ENG|RUS\<LEVEL>.dat: u32
# count, then null-terminated UTF-16 strings; the Russian ones are cp1251 bytes as code units, as the game uses them)
# but does not apply them to such a game. Loose Data\Messages\*.MSG files are read before the archives.
# .MSG: 01 00 00 00 01; per string ff*8, u32 length (with the terminator), u16 0x9696 - char; then ff*4, u32 offset of
# each string record, u32 count, u32 offset of that index. Same as wizardry8-hdui tools\rus_messages.py.

# SLF archive (JA2 SGP): 532-byte header with the entry count at 512; 280-byte entries at the end of the file
# (name[256], u32 offset, u32 size, u8 state; state 0 = present). Returns upper-case name -> @(offset, size).
function Read-SlfIndex([string]$path) {
    $idx = @{}
    $f = [IO.File]::OpenRead($path)
    try {
        $r = New-Object IO.BinaryReader($f)
        [void]$f.Seek(512, 'Begin')
        $n = $r.ReadInt32()
        [void]$f.Seek(-280 * $n, 'End')
        for ($i = 0; $i -lt $n; $i++) {
            $e = $r.ReadBytes(280)
            $len = [Array]::IndexOf($e, [byte]0)
            if ($len -lt 0 -or $len -gt 256) { $len = 256 }
            $name = [Text.Encoding]::GetEncoding(28591).GetString($e, 0, $len)
            if ($e[264] -eq 0) { $idx[$name.ToUpperInvariant()] = @([BitConverter]::ToUInt32($e, 256), [BitConverter]::ToUInt32($e, 260)) }
        }
    } finally { $f.Dispose() }
    return $idx
}

function Read-SlfEntry([string]$path, $entry) {
    $f = [IO.File]::OpenRead($path)
    try {
        [void]$f.Seek($entry[0], 'Begin')
        $b = New-Object byte[] $entry[1]
        $got = 0
        while ($got -lt $b.Length) {
            $k = $f.Read($b, $got, $b.Length - $got)
            if ($k -le 0) { throw "$path is shorter than its index says" }
            $got += $k
        }
        return , $b
    } finally { $f.Dispose() }
}

# .dat -> string[] (code units kept as they are)
function Read-MsgDat([byte[]]$b) {
    $n = [BitConverter]::ToUInt32($b, 0)
    $s = [Text.Encoding]::Unicode.GetString($b, 4, $b.Length - 4).Split([char]0)
    if ($s.Count -lt $n) { throw 'short .dat' }
    return , ($s[0..($n - 1)])
}

# .MSG -> string[]
function Read-Msg([byte[]]$b) {
    $tail = [BitConverter]::ToUInt32($b, $b.Length - 4)
    $n = [BitConverter]::ToUInt32($b, $b.Length - 8)
    $out = New-Object string[] $n
    for ($i = 0; $i -lt $n; $i++) {
        $o = [BitConverter]::ToUInt32($b, $tail + 4 + 4 * $i)
        $len = [BitConverter]::ToUInt32($b, $o + 8)
        $c = New-Object char[] ($len - 1)
        for ($k = 0; $k -lt $len - 1; $k++) { $c[$k] = [char]((0x9696 - [BitConverter]::ToUInt16($b, $o + 12 + 2 * $k)) -band 0xFFFF) }
        $out[$i] = New-Object string (, $c)
    }
    return , $out
}

# string[] -> .MSG bytes
function ConvertTo-Msg([string[]]$strs) {
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $w.Write([byte[]](1, 0, 0, 0, 1))
    $ff = [byte[]](@(255) * 8)
    $offs = New-Object 'System.Collections.Generic.List[uint32]'
    foreach ($s in $strs) {
        $offs.Add([uint32]$ms.Position)
        $w.Write($ff)
        $w.Write([uint32]($s.Length + 1))
        foreach ($ch in $s.ToCharArray()) { $w.Write([uint16]((0x9696 - [int]$ch) -band 0xFFFF)) }
        $w.Write([uint16]0x9696)
    }
    $tail = [uint32]$ms.Position
    $w.Write([byte[]](255, 255, 255, 255))
    foreach ($o in $offs) { $w.Write($o) }
    $w.Write([uint32]$offs.Count)
    $w.Write($tail)
    $w.Flush()
    return , $ms.ToArray()
}

function Test-SameStrings([string[]]$a, [string[]]$b) {
    if ($a.Count -ne $b.Count) { return $false }
    for ($i = 0; $i -lt $a.Count; $i++) { if (-not [string]::Equals($a[$i], $b[$i], 'Ordinal')) { return $false } }
    return $true
}

# LEVEL -> Russian .MSG bytes, for the levels whose Fan Patch English copy equals the game's own .MSG
# (so the Russian one lines up string by string). $null when the game has no RUS.SLF or no FanPatch.Dat.
function Get-RusMessages([string]$GamePath) {
    $data = Join-Path $GamePath 'Data\DATA.SLF'
    $rus = Join-Path $GamePath 'Data\RUS.SLF'
    $fp = Join-Path $GamePath 'Data\FanPatch.Dat'
    if (-not ((Test-Path -LiteralPath $data) -and (Test-Path -LiteralPath $rus) -and (Test-Path -LiteralPath $fp))) { return $null }
    $di = Read-SlfIndex $data
    $fi = Read-SlfIndex $fp
    $out = [ordered]@{}
    foreach ($name in ($di.Keys | Where-Object { $_ -like 'MESSAGES\*.MSG' } | Sort-Object)) {
        $level = [IO.Path]::GetFileNameWithoutExtension($name)
        $ek = "LOCALIZATION\ORIGINAL\MESSAGES\ENG\$level.DAT"
        $rk = "LOCALIZATION\ORIGINAL\MESSAGES\RUS\$level.DAT"
        if (-not ($fi.ContainsKey($ek) -and $fi.ContainsKey($rk))) { continue }
        $orig = Read-SlfEntry $data $di[$name]
        $eng = Read-MsgDat (Read-SlfEntry $fp $fi[$ek])
        $ru = Read-MsgDat (Read-SlfEntry $fp $fi[$rk])
        if (-not (Test-SameStrings (Read-Msg $orig) $eng) -or $ru.Count -ne $eng.Count) {
            Write-Warn2 "$level`: the Fan Patch copy does not match the game's texts, kept English"
            continue
        }
        $out[$level] = ConvertTo-Msg $ru
    }
    return $out
}
