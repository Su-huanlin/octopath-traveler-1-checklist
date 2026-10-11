$ErrorActionPreference = "Stop"

# Dumps the byte layout around SaveEnemyData in the save file so we can decode the
# UE4 GVAS array-of-struct holding per-enemy WeaknessOpen bitmasks.
#
# Output goes to D:\Unpacking game\OctopathTrackerOutput\save_enemy_layout.txt

$SavePath = "D:\Unpacking game\SaveData1.sav"
if (!(Test-Path -LiteralPath $SavePath)) {
  $SavePath = "$env:USERPROFILE\OneDrive\Documents\My Games\Octopath_Traveler\SaveData1.sav"
}
if (!(Test-Path -LiteralPath $SavePath)) {
  $SavePath = "$env:USERPROFILE\Documents\My Games\Octopath_Traveler\SaveData1.sav"
}
if (!(Test-Path -LiteralPath $SavePath)) {
  Write-Error "SaveData1.sav not found at D:\Unpacking game\SaveData1.sav nor in Documents."
  exit 1
}

$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
if (!(Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$OutFile = Join-Path $OutDir "save_enemy_layout.txt"

$bytes = [System.IO.File]::ReadAllBytes($SavePath)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("save file : $SavePath")
$lines.Add("save size : $($bytes.Length) bytes")
$lines.Add("")

function FindAscii([byte[]]$Buf, [string]$Needle, [int]$StartAt = 0) {
  $pat = [System.Text.Encoding]::ASCII.GetBytes($Needle)
  $hits = New-Object System.Collections.Generic.List[int]
  for ($i = $StartAt; $i -le $Buf.Length - $pat.Length; $i++) {
    $match = $true
    for ($j = 0; $j -lt $pat.Length; $j++) {
      if ($Buf[$i + $j] -ne $pat[$j]) { $match = $false; break }
    }
    if ($match) { $hits.Add($i) | Out-Null }
  }
  return $hits
}

# --- 1. Locate SaveEnemyData (UE4 FNames precede the string with an int32 length, so the real
#       start of the FName is 4 bytes earlier).
$tokenHits = FindAscii $bytes "SaveEnemyData"
if ($tokenHits.Count -eq 0) {
  $lines.Add("ERROR: SaveEnemyData token not found.")
  [System.IO.File]::WriteAllLines($OutFile, $lines)
  exit 1
}
$lines.Add("SaveEnemyData ASCII hits (count = $($tokenHits.Count)):")
foreach ($h in $tokenHits) { $lines.Add(("  offset = 0x{0:X}" -f $h)) }
$lines.Add("")

# Pick the first hit as the canonical SaveEnemyData name occurrence.
$tokenOffset = $tokenHits[0]
# The FName length prefix is 4 bytes BEFORE the string start.
$nameLenOff = $tokenOffset - 4
$nameLen = [BitConverter]::ToInt32($bytes, $nameLenOff)
$lines.Add(("Name length prefix (int32) at 0x{0:X} = {1}" -f $nameLenOff, $nameLen))
$lines.Add("Expected length for 'SaveEnemyData\0' = 14")
$lines.Add("")

# --- 2. Dump a big hex+ASCII window starting a bit before the name length prefix so we capture
#       the full ArrayProperty header (name + type + size + index + null + inner-type + count + struct header).
$dumpStart = [Math]::Max(0, $nameLenOff - 16)
$dumpLen   = [Math]::Min(8192, $bytes.Length - $dumpStart)
$lines.Add(("=== Hex+ASCII dump from 0x{0:X} for {1} bytes ===" -f $dumpStart, $dumpLen))

for ($row = 0; $row -lt $dumpLen; $row += 16) {
  $abs = $dumpStart + $row
  $hex = New-Object System.Text.StringBuilder
  $asc = New-Object System.Text.StringBuilder
  for ($col = 0; $col -lt 16; $col++) {
    if ($row + $col -ge $dumpLen) {
      [void]$hex.Append("   ")
      [void]$asc.Append(" ")
      continue
    }
    $b = $bytes[$abs + $col]
    [void]$hex.AppendFormat("{0:X2} ", $b)
    if ($b -ge 0x20 -and $b -lt 0x7F) { [void]$asc.Append([char]$b) } else { [void]$asc.Append(".") }
  }
  $lines.Add(("0x{0:X8}  {1} |{2}|" -f $abs, $hex.ToString().TrimEnd(), $asc.ToString()))
}
$lines.Add("")

# --- 3. Enumerate all UE4 FName-like strings within the dump region. A typical UE4 FName in a
#       GVAS save is: int32 length (incl. trailing \0), then `length` ASCII bytes (last is \0).
$lines.Add("=== Plausible UE4 FName strings inside the dump window ===")
$scanEnd = [Math]::Min($dumpStart + $dumpLen, $bytes.Length - 5)
for ($i = $dumpStart; $i -lt $scanEnd - 4; $i++) {
  $len = [BitConverter]::ToInt32($bytes, $i)
  if ($len -lt 4 -or $len -gt 96) { continue }
  $strStart = $i + 4
  $strEnd   = $strStart + $len
  if ($strEnd -gt $bytes.Length) { continue }
  # Last byte must be 0, all preceding must be 0x20..0x7E (printable ASCII).
  if ($bytes[$strEnd - 1] -ne 0) { continue }
  $ok = $true
  for ($k = $strStart; $k -lt $strEnd - 1; $k++) {
    $b = $bytes[$k]
    if ($b -lt 0x20 -or $b -gt 0x7E) { $ok = $false; break }
  }
  if (!$ok) { continue }
  $s = [System.Text.Encoding]::ASCII.GetString($bytes, $strStart, $len - 1)
  # Require it to look like a UE4 name (alnum + _).
  if ($s -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { continue }
  $lines.Add(("  0x{0:X8}  len={1,3}  {2}" -f $i, $len, $s))
}
$lines.Add("")

# --- 4. Count occurrences of common per-element field markers so we know how many elements.
$markers = @("EnemyID", "WeaknessOpen", "MonsterIsEncount", "MonsterIsCaptured", "EncountFlag", "DefeatCount", "DropFlag")
$lines.Add("=== Field token frequency in the entire save ===")
foreach ($m in $markers) {
  $hits = FindAscii $bytes $m
  $lines.Add(("  {0,-22} hits: {1}" -f $m, $hits.Count))
  if ($hits.Count -gt 0 -and $hits.Count -lt 12) {
    foreach ($h in $hits) { $lines.Add(("    0x{0:X}" -f $h)) }
  }
}

[System.IO.File]::WriteAllLines($OutFile, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutFile"
