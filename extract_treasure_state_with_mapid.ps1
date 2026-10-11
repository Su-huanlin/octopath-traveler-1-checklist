$ErrorActionPreference = "Stop"

$oneDrive = Join-Path $env:USERPROFILE "OneDrive"
$save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $save) { throw "SaveData1.sav not found" }

$bytes = [System.IO.File]::ReadAllBytes($save.FullName)
$out = "D:\Unpacking game\OctopathTrackerOutput\treasure_state_with_mapid.csv"

function ReadI32([byte[]]$b, [int]$o) { return [BitConverter]::ToInt32($b, $o) }

function FindAscii([byte[]]$Bytes, [string]$Needle) {
  $pat = [System.Text.Encoding]::ASCII.GetBytes($Needle)
  $hits = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -le $Bytes.Length - $pat.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $pat.Length; $j++) {
      if ($Bytes[$i + $j] -ne $pat[$j]) { $ok = $false; break }
    }
    if ($ok) { $hits.Add($i) }
  }
  return $hits
}

function HexBytes([byte[]]$Bytes, [int]$Offset, [int]$Count) {
  $parts = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Count -and ($Offset + $i) -lt $Bytes.Length; $i++) {
    $parts.Add($Bytes[$Offset + $i].ToString("X2"))
  }
  return ($parts -join " ")
}

function CountOpenSlots([byte[]]$Bytes, [int]$Offset, [int]$Count) {
  # In this save the first bytes are metadata-like; treasure states appear as 00/01 slots.
  $n = 0
  for ($i = 0; $i -lt $Count -and ($Offset + $i) -lt $Bytes.Length; $i++) {
    if ($Bytes[$Offset + $i] -eq 1) { $n++ }
  }
  return $n
}

function ParseIntPropertyValueAfterName([byte[]]$Bytes, [int]$NameOffset) {
  $nameLenOffset = $NameOffset - 4
  if ($nameLenOffset -lt 0) { return $null }
  $nameLen = ReadI32 $Bytes $nameLenOffset
  if ($nameLen -le 0 -or $nameLen -gt 200) { return $null }
  $typeLenOffset = $NameOffset + $nameLen
  $typeLen = ReadI32 $Bytes $typeLenOffset
  if ($typeLen -le 0 -or $typeLen -gt 100) { return $null }
  $typeStart = $typeLenOffset + 4
  $type = [System.Text.Encoding]::ASCII.GetString($Bytes, $typeStart, $typeLen - 1)
  if ($type -ne "IntProperty") { return $null }
  $sizeOffset = $typeStart + $typeLen
  $valueOffset = $sizeOffset + 8 + 4
  if ($valueOffset + 4 -gt $Bytes.Length) { return $null }
  return ReadI32 $Bytes $valueOffset
}

function ParseByteArrayDataStart([byte[]]$Bytes, [int]$NameOffset) {
  $nameLen = ReadI32 $Bytes ($NameOffset - 4)
  $typeLenOffset = $NameOffset + $nameLen
  $typeLen = ReadI32 $Bytes $typeLenOffset
  $typeStart = $typeLenOffset + 4
  $sizeOffset = $typeStart + $typeLen
  $size = [BitConverter]::ToInt64($Bytes, $sizeOffset)
  $innerLenOffset = $sizeOffset + 8
  $innerLen = ReadI32 $Bytes $innerLenOffset
  $dataStart = $innerLenOffset + 4 + $innerLen
  return @{ size = [int]$size; data_start = $dataStart }
}

$treasureHits = FindAscii $bytes "TreasureStateArray_"
$mapHits = FindAscii $bytes "MapID_"
$rows = New-Object System.Collections.Generic.List[object]

for ($i = 0; $i -lt $treasureHits.Count; $i++) {
  $hit = $treasureHits[$i]
  $prevMapHit = $null
  foreach ($m in $mapHits) {
    if ($m -lt $hit -and $m -gt ($hit - 700)) { $prevMapHit = $m }
    if ($m -ge $hit) { break }
  }
  $mapId = $null
  if ($null -ne $prevMapHit) {
    $mapId = ParseIntPropertyValueAfterName $bytes $prevMapHit
  }
  $arr = ParseByteArrayDataStart $bytes $hit
  $rows.Add([pscustomobject]@{
    index = $i
    map_id = $mapId
    treasure_offset = ("0x{0:X8}" -f $hit)
    mapid_offset = if ($null -ne $prevMapHit) { ("0x{0:X8}" -f $prevMapHit) } else { "" }
    size = $arr.size
    open_slots = CountOpenSlots $bytes $arr.data_start $arr.size
    data_hex = HexBytes $bytes $arr.data_start $arr.size
  })
}

$rows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
Write-Host "Output: $out"
Write-Host "Rows: $($rows.Count)"
