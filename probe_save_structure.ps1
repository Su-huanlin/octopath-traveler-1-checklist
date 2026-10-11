$ErrorActionPreference = "Stop"

$Root = "D:\Unpacking game"
$SavePath = Join-Path $Root "SaveData1.sav"
$OutDir = Join-Path $Root "OctopathTrackerOutput"
if (!(Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$OutTxt = Join-Path $OutDir "save_structure_probe.txt"
$OutCsv = Join-Path $OutDir "save_structure_blocks.csv"

if (!(Test-Path -LiteralPath $SavePath)) { throw "Save file not found: $SavePath" }
$bytes = [System.IO.File]::ReadAllBytes($SavePath)
$size = $bytes.Length

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

function HexBytes([byte[]]$B, [int]$Off, [int]$Count) {
  $parts = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Count -and ($Off + $i) -lt $B.Length; $i++) {
    $parts.Add($B[$Off + $i].ToString("X2")) | Out-Null
  }
  return ($parts -join " ")
}

function AsciiSafe([byte[]]$B, [int]$Off, [int]$Count) {
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $Count -and ($Off + $i) -lt $B.Length; $i++) {
    $c = $B[$Off + $i]
    if ($c -ge 32 -and $c -lt 127) { [void]$sb.Append([char]$c) } else { [void]$sb.Append('.') }
  }
  return $sb.ToString()
}

# Walk forward from an offset that is the START of a Property name length field.
# Returns array of property entries (name, type, size, value_offset) until "None" is hit.
function ParsePropertiesAt([byte[]]$B, [int]$Start, [int]$MaxBytes) {
  $props = New-Object System.Collections.Generic.List[object]
  $pos = $Start
  $end = [Math]::Min($B.Length - 4, $Start + $MaxBytes)
  $safety = 0
  while ($pos -lt $end -and $safety -lt 32) {
    $safety++
    if ($pos + 4 -gt $B.Length) { break }
    $nameLen = [BitConverter]::ToInt32($B, $pos)
    if ($nameLen -le 0 -or $nameLen -gt 200) { break }
    if ($pos + 4 + $nameLen -gt $B.Length) { break }
    $name = ReadCString $B ($pos + 4) $nameLen
    $afterName = $pos + 4 + $nameLen
    if ($name -eq "None") {
      $props.Add([pscustomobject]@{
        offset = $pos
        name = $name
        type = ""
        size = 0
        value_offset = $afterName
      }) | Out-Null
      break
    }
    if ($afterName + 4 -gt $B.Length) { break }
    $typeLen = [BitConverter]::ToInt32($B, $afterName)
    if ($typeLen -le 0 -or $typeLen -gt 100) { break }
    if ($afterName + 4 + $typeLen -gt $B.Length) { break }
    $type = ReadCString $B ($afterName + 4) $typeLen
    $afterType = $afterName + 4 + $typeLen
    if ($afterType + 8 -gt $B.Length) { break }
    $valSize = [int][BitConverter]::ToInt64($B, $afterType)
    $afterSize = $afterType + 8
    # arrayindex (4 bytes)
    if ($afterSize + 4 -gt $B.Length) { break }
    $afterArrayIdx = $afterSize + 4
    $valueOffset = $afterArrayIdx
    $nextPos = $valueOffset + $valSize
    $tagExtra = 0
    switch ($type) {
      "BoolProperty"   { $tagExtra = 2; $nextPos = $valueOffset + $tagExtra }
      "ByteProperty"   {
        # ByteProperty: enum name length + enum name + 1 byte guid_present(0) + then value(1 byte) at value_offset
        if ($valueOffset + 4 -gt $B.Length) { break }
        $enumLen = [BitConverter]::ToInt32($B, $valueOffset - 4 - 4)
        # Actually ByteProperty in UE4 GVAS: after size, before guid_present we have:
        # NameProperty: enum FName (8 bytes) then 1 byte guid_present
        # We'll just trust value size and move past valSize.
      }
      "ArrayProperty"  {
        # ArrayProperty tag: 4-byte FName for inner type + 1 byte guid_present(0). The size includes the array content.
        # Inner type bytes (length-prefixed name) + 1 byte; size starts after that.
        if ($valueOffset + 4 -gt $B.Length) { break }
        $innerLen = [BitConverter]::ToInt32($B, $valueOffset)
        $tagExtra = 4 + $innerLen + 1
        $nextPos = $valueOffset + $tagExtra + $valSize
      }
      "StructProperty" {
        # struct name (length prefixed) + 16 byte guid + 1 byte guid_present(0)
        if ($valueOffset + 4 -gt $B.Length) { break }
        $structLen = [BitConverter]::ToInt32($B, $valueOffset)
        $tagExtra = 4 + $structLen + 16 + 1
        $nextPos = $valueOffset + $tagExtra + $valSize
      }
      default {
        # Most simple props have 1 byte guid_present(0) before the value.
        $tagExtra = 1
        $nextPos = $valueOffset + $tagExtra + $valSize
      }
    }
    $props.Add([pscustomobject]@{
      offset = $pos
      name = $name
      type = $type
      size = $valSize
      value_offset = $valueOffset + $tagExtra
    }) | Out-Null
    if ($nextPos -le $pos) { break }
    $pos = $nextPos
  }
  return $props
}

# Find name string occurrences -> their property header is 4 bytes earlier.
function NameLengthOffset([int]$NameAsciiOffset) { return $NameAsciiOffset - 4 }

$treasureNameHits = FindAscii $bytes "TreasureStateArray_"
$hiddenNameHits = FindAscii $bytes "HiddenPointCount"
$mapIdNameHits = FindAscii $bytes "MapID"
$mapDataNameHits = FindAscii $bytes "MapData"
$mapKeyNameHits = FindAscii $bytes "MapKey"
$mapNameNameHits = FindAscii $bytes "MapName"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("save_path=$SavePath")
$lines.Add("save_size=$size")
$lines.Add(("TreasureStateArray hits = {0}" -f $treasureNameHits.Count))
$lines.Add(("HiddenPointCount hits   = {0}" -f $hiddenNameHits.Count))
$lines.Add(("MapID hits              = {0}" -f $mapIdNameHits.Count))
$lines.Add(("MapData hits            = {0}" -f $mapDataNameHits.Count))
$lines.Add(("MapKey hits             = {0}" -f $mapKeyNameHits.Count))
$lines.Add(("MapName hits            = {0}" -f $mapNameNameHits.Count))
$lines.Add("")

# Show context around the first few MapData occurrences.
$lines.Add("=== MapData contexts (first 3) ===")
for ($i = 0; $i -lt [Math]::Min(3, $mapDataNameHits.Count); $i++) {
  $h = $mapDataNameHits[$i]
  $from = [Math]::Max(0, $h - 32)
  $lines.Add(("MapData[{0}] @ 0x{1:X8}" -f $i, $h))
  $lines.Add("  hex   : " + (HexBytes $bytes $from 96))
  $lines.Add("  ascii : " + (AsciiSafe $bytes $from 96))
}
$lines.Add("")

# Show context around the first few MapID occurrences (if any beyond the first).
$lines.Add("=== MapID contexts (first 5) ===")
for ($i = 0; $i -lt [Math]::Min(5, $mapIdNameHits.Count); $i++) {
  $h = $mapIdNameHits[$i]
  $from = [Math]::Max(0, $h - 16)
  $lines.Add(("MapID[{0}] @ 0x{1:X8}" -f $i, $h))
  $lines.Add("  hex   : " + (HexBytes $bytes $from 80))
  $lines.Add("  ascii : " + (AsciiSafe $bytes $from 80))
}
$lines.Add("")

# For each TreasureStateArray entry, parse its property + neighboring properties.
$lines.Add("=== TreasureStateArray entries (first 30 + last 5) ===")
$rows = New-Object System.Collections.Generic.List[object]
$treasureCount = $treasureNameHits.Count
for ($i = 0; $i -lt $treasureCount; $i++) {
  $hit = $treasureNameHits[$i]
  $propStart = NameLengthOffset $hit
  $props = ParsePropertiesAt $bytes $propStart 400
  $treasureProp = $props | Where-Object { $_.name -like "TreasureStateArray*" } | Select-Object -First 1
  $hiddenProp = $props | Where-Object { $_.name -eq "HiddenPointCount" } | Select-Object -First 1
  $mapIdProp = $props | Where-Object { $_.name -eq "MapID" -or $_.name -eq "MapId" } | Select-Object -First 1
  $hiddenValue = if ($hiddenProp) { [BitConverter]::ToInt32($bytes, $hiddenProp.value_offset) } else { $null }
  $mapIdValue = if ($mapIdProp) { [BitConverter]::ToInt32($bytes, $mapIdProp.value_offset) } else { $null }
  # Look 96 bytes BEFORE this property for any obvious string.
  $preFrom = [Math]::Max(0, $propStart - 96)
  $preAscii = AsciiSafe $bytes $preFrom 96
  $treasureSize = if ($treasureProp) { $treasureProp.size } else { 0 }
  $treasureData = ""
  $openSlots = 0
  if ($treasureProp -and $treasureProp.size -gt 0) {
    # ArrayProperty value layout in our parse: value_offset already past tagExtra (4+innerLen+1).
    # The array bytes start with a 4-byte count, then raw bytes for ByteProperty arrays.
    $arrPos = $treasureProp.value_offset
    if ($arrPos + 4 -le $bytes.Length) {
      $arrCount = [BitConverter]::ToInt32($bytes, $arrPos)
      $dataStart = $arrPos + 4
      $dataLen = [Math]::Min($treasureProp.size - 4, $bytes.Length - $dataStart)
      if ($dataLen -gt 0) {
        $treasureData = HexBytes $bytes $dataStart $dataLen
        for ($k = 0; $k -lt $dataLen; $k++) {
          if ($bytes[$dataStart + $k] -eq 1) { $openSlots++ }
        }
      }
    }
  }
  $row = [pscustomobject]@{
    state_index    = $i
    treasure_offset = ("0x{0:X8}" -f $hit)
    treasure_size  = $treasureSize
    open_slots     = $openSlots
    has_HiddenPointCount = [bool]$hiddenProp
    HiddenPointCount = $hiddenValue
    has_MapID      = [bool]$mapIdProp
    MapID          = $mapIdValue
    properties     = (($props | Where-Object { $_.name -ne "None" } | ForEach-Object { "{0}:{1}({2})" -f $_.name, $_.type, $_.size }) -join " | ")
    pre_ascii      = $preAscii
    data_hex       = $treasureData
  }
  $rows.Add($row) | Out-Null
  $showThis = ($i -lt 30) -or ($i -ge $treasureCount - 5)
  if ($showThis) {
    $lines.Add(("[{0,3}] off=0x{1:X8} sz={2} open={3} hidden={4} mapId={5} props=[{6}]" -f $i, $hit, $treasureSize, $openSlots, $hiddenValue, $mapIdValue, $row.properties))
  }
}
$lines.Add("")
$lines.Add(("TreasureStateArray entries that report HiddenPointCount: {0}" -f ($rows | Where-Object { $_.has_HiddenPointCount } | Measure-Object).Count))
$lines.Add(("TreasureStateArray entries that report MapID:            {0}" -f ($rows | Where-Object { $_.has_MapID } | Measure-Object).Count))

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
[System.IO.File]::WriteAllLines($OutTxt, $lines, [System.Text.Encoding]::UTF8)
Write-Host ("Done. {0} entries written." -f $rows.Count)
Write-Host ("TXT: {0}" -f $OutTxt)
Write-Host ("CSV: {0}" -f $OutCsv)
