$ErrorActionPreference = "Stop"

$Root = "D:\Unpacking game"
$SavePath = Join-Path $Root "SaveData1.sav"
$OutDir = Join-Path $Root "OctopathTrackerOutput"
if (!(Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$OutTxt = Join-Path $OutDir "mapid_array_probe.txt"
$OutCsv = Join-Path $OutDir "mapid_array.csv"

if (!(Test-Path -LiteralPath $SavePath)) { throw "Save file not found: $SavePath" }
$bytes = [System.IO.File]::ReadAllBytes($SavePath)

function FindAscii([byte[]]$B, [string]$Needle) {
  $pat = [System.Text.Encoding]::ASCII.GetBytes($Needle)
  $hits = New-Object System.Collections.Generic.List[int]
  $limit = $B.Length - $pat.Length
  for ($i = 0; $i -le $limit; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $pat.Length; $j++) {
      if ($B[$i + $j] -ne $pat[$j]) { $ok = $false; break }
    }
    if ($ok) { $hits.Add($i) | Out-Null }
  }
  return $hits
}

function ReadCString([byte[]]$B, [int]$Off, [int]$Max) {
  $end = $Off
  while ($end -lt $B.Length -and $end -lt ($Off + $Max) -and $B[$end] -ne 0) { $end++ }
  return [System.Text.Encoding]::ASCII.GetString($B, $Off, $end - $Off)
}

function AsciiSafe([byte[]]$B, [int]$Off, [int]$Count) {
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $Count -and ($Off + $i) -lt $B.Length; $i++) {
    $c = $B[$Off + $i]
    if ($c -ge 32 -and $c -lt 127) { [void]$sb.Append([char]$c) } else { [void]$sb.Append('.') }
  }
  return $sb.ToString()
}

function HexBytes([byte[]]$B, [int]$Off, [int]$Count) {
  $parts = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Count -and ($Off + $i) -lt $B.Length; $i++) {
    $parts.Add($B[$Off + $i].ToString("X2")) | Out-Null
  }
  return ($parts -join " ")
}

$mapIdNameHits = FindAscii $bytes "MapID_5_"
$mapInfoHits = FindAscii $bytes "MapInfo"
$mapStateHits = FindAscii $bytes "MapState"
$treasureNameHits = FindAscii $bytes "TreasureStateArray_"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("save_size = $($bytes.Length)")
$lines.Add("MapID_5_ hits     = $($mapIdNameHits.Count)")
$lines.Add("MapInfo  hits     = $($mapInfoHits.Count)")
$lines.Add("MapState hits     = $($mapStateHits.Count)")
$lines.Add("TreasureState hits= $($treasureNameHits.Count)")
$lines.Add("")
$lines.Add("First TreasureStateArray offset: 0x{0:X8}" -f $treasureNameHits[0])
$lines.Add("First MapID offset:              0x{0:X8}" -f $mapIdNameHits[0])
$lines.Add("Last  MapID offset:              0x{0:X8}" -f $mapIdNameHits[-1])
$lines.Add("")

$rows = New-Object System.Collections.Generic.List[object]
$prevOffset = -1
for ($i = 0; $i -lt $mapIdNameHits.Count; $i++) {
  $hit = $mapIdNameHits[$i]
  # Property header starts 4 bytes before the ASCII name (length prefix).
  $propStart = $hit - 4
  if ($propStart -lt 0) { continue }
  $nameLen = [BitConverter]::ToInt32($bytes, $propStart)
  if ($nameLen -le 0 -or $nameLen -gt 200) { continue }
  $afterName = $propStart + 4 + $nameLen
  if ($afterName + 4 -gt $bytes.Length) { continue }
  $typeLen = [BitConverter]::ToInt32($bytes, $afterName)
  if ($typeLen -le 0 -or $typeLen -gt 100) { continue }
  $type = ReadCString $bytes ($afterName + 4) $typeLen
  $afterType = $afterName + 4 + $typeLen
  if ($type -ne "IntProperty") {
    # Skip; not a true MapID IntProperty
    continue
  }
  # IntProperty layout: size(8) + arrayindex(4) + guid_present(1) + value(4)
  $valueOffset = $afterType + 8 + 4 + 1
  if ($valueOffset + 4 -gt $bytes.Length) { continue }
  $value = [BitConverter]::ToInt32($bytes, $valueOffset)
  $delta = if ($prevOffset -ge 0) { $hit - $prevOffset } else { 0 }
  $rows.Add([pscustomobject]@{
    index = $rows.Count
    offset = ("0x{0:X8}" -f $hit)
    map_id = $value
    delta_bytes_from_prev = $delta
  }) | Out-Null
  $prevOffset = $hit
}

$lines.Add("Parsed MapID IntProperty count: $($rows.Count)")
$lines.Add("")
$lines.Add("=== First 30 MapID values ===")
for ($i = 0; $i -lt [Math]::Min(30, $rows.Count); $i++) {
  $r = $rows[$i]
  $lines.Add(("[{0,4}] off={1} value={2,6} delta={3}" -f $r.index, $r.offset, $r.map_id, $r.delta_bytes_from_prev))
}
$lines.Add("")
$lines.Add("=== Last 10 MapID values ===")
for ($i = [Math]::Max(0, $rows.Count - 10); $i -lt $rows.Count; $i++) {
  $r = $rows[$i]
  $lines.Add(("[{0,4}] off={1} value={2,6} delta={3}" -f $r.index, $r.offset, $r.map_id, $r.delta_bytes_from_prev))
}
$lines.Add("")

# Distinct values and counts
$grouped = $rows | Group-Object -Property map_id | Sort-Object -Property Count -Descending
$lines.Add("Distinct MapID values: $($grouped.Count)")
$lines.Add("Top 10 by frequency:")
foreach ($g in $grouped | Select-Object -First 10) {
  $lines.Add(("  value={0,6} count={1}" -f $g.Name, $g.Count))
}
$lines.Add("")

# Look at the bytes around the FIRST MapID entry to understand the per-entry layout / siblings.
$firstHit = $mapIdNameHits[0]
$lines.Add(("=== Hex dump around first MapID entry (0x{0:X8} +- 64) ===" -f $firstHit))
$startOff = [Math]::Max(0, $firstHit - 64)
$lines.Add((HexBytes $bytes $startOff 256))
$lines.Add((AsciiSafe $bytes $startOff 256))
$lines.Add("")
$lines.Add(("=== Hex dump around the SECOND MapID entry (0x{0:X8} +- 32) ===" -f $mapIdNameHits[1]))
$startOff2 = [Math]::Max(0, $mapIdNameHits[1] - 32)
$lines.Add((HexBytes $bytes $startOff2 256))
$lines.Add((AsciiSafe $bytes $startOff2 256))
$lines.Add("")
# Look at one MapID hit further down to see if other fields appear (eg map name)
$midIdx = [int]($mapIdNameHits.Count / 2)
$startOff3 = [Math]::Max(0, $mapIdNameHits[$midIdx] - 16)
$lines.Add(("=== Hex dump around middle MapID entry idx={0} (0x{1:X8} +- 16) ===" -f $midIdx, $mapIdNameHits[$midIdx]))
$lines.Add((HexBytes $bytes $startOff3 256))
$lines.Add((AsciiSafe $bytes $startOff3 256))

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
[System.IO.File]::WriteAllLines($OutTxt, $lines, [System.Text.Encoding]::UTF8)
Write-Host "Done. CSV=$OutCsv  TXT=$OutTxt"
