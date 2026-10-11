$ErrorActionPreference = "Stop"
$Root = "D:\Unpacking game"
$SavePath = Join-Path $Root "SaveData1.sav"
$OutDir = Join-Path $Root "OctopathTrackerOutput"
if (!(Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$OutCsv = Join-Path $OutDir "enemy_save_probe.csv"
$OutTxt = Join-Path $OutDir "enemy_save_probe.txt"

if (!(Test-Path -LiteralPath $SavePath)) { throw "Save file not found: $SavePath" }
$bytes = [System.IO.File]::ReadAllBytes($SavePath)

function FindAscii([byte[]]$B, [string]$Needle) {
  $pat = [System.Text.Encoding]::ASCII.GetBytes($Needle)
  $hits = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -le $B.Length - $pat.Length; $i++) {
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

function ReadI32([byte[]]$B, [int]$Off) { return [BitConverter]::ToInt32($B, $Off) }
function ReadI64([byte[]]$B, [int]$Off) { return [BitConverter]::ToInt64($B, $Off) }

function GetPropertyTagExtra([byte[]]$B, [string]$Type, [int]$ValueOffset) {
  switch ($Type) {
    "BoolProperty" { return 1 }
    "ByteProperty" { return 1 }
    "ArrayProperty" {
      $innerLen = ReadI32 $B $ValueOffset
      return 4 + $innerLen + 1
    }
    "StructProperty" {
      $structLen = ReadI32 $B $ValueOffset
      return 4 + $structLen + 16 + 1
    }
    default { return 1 }
  }
}

function ParseOneProperty([byte[]]$B, [int]$Pos, [ref]$NextPos) {
  $NextPos.Value = $Pos
  if ($Pos + 4 -gt $B.Length) { return $null }
  $nameLen = ReadI32 $B $Pos
  if ($nameLen -le 0 -or $nameLen -gt 200) { return $null }
  if ($Pos + 4 + $nameLen -gt $B.Length) { return $null }
  $name = ReadCString $B ($Pos + 4) $nameLen
  $afterName = $Pos + 4 + $nameLen
  if ($afterName + 4 -gt $B.Length) { return $null }
  $typeLen = ReadI32 $B $afterName
  if ($typeLen -le 0 -or $typeLen -gt 100) { return $null }
  $type = ReadCString $B ($afterName + 4) $typeLen
  $afterType = $afterName + 4 + $typeLen
  if ($afterType + 12 -gt $B.Length) { return $null }
  $valSize = ReadI64 $B $afterType
  $afterSize = $afterType + 8
  $afterArrayIdx = $afterSize + 4
  $valueOffset = $afterArrayIdx
  $tagExtra = GetPropertyTagExtra $B $type $valueOffset
  $dataOffset = $valueOffset + $tagExtra
  $NextPos.Value = $dataOffset + $valSize
  if ($name -eq "None") {
    $NextPos.Value = $afterName
    return [pscustomobject]@{ name = "None"; type = ""; size = 0; data_offset = $afterName; raw_offset = $Pos }
  }
  return [pscustomobject]@{
    name = $name
    type = $type
    size = [int]$valSize
    data_offset = $dataOffset
    raw_offset = $Pos
    tag_extra = $tagExtra
    value_offset = $valueOffset
  }
}

function ParseProperties([byte[]]$B, [int]$Start, [int]$MaxBytes) {
  $props = New-Object System.Collections.Generic.List[object]
  $pos = $Start
  $end = [Math]::Min($B.Length, $Start + $MaxBytes)
  $safety = 0
  while ($pos -lt $end -and $safety -lt 64) {
    $safety++
    $next = 0
    $p = ParseOneProperty $B $pos ([ref]$next)
    if ($null -eq $p) { break }
    $props.Add($p) | Out-Null
    if ($p.name -eq "None") { break }
    if ($next -le $pos) { break }
    $pos = $next
  }
  return $props
}

function ParseStructElement([byte[]]$B, [int]$Start, [int]$MaxBytes) {
  $props = ParseProperties $B $Start $MaxBytes
  $result = @{}
  $endPos = $Start
  foreach ($p in $props) {
    if ($p.name -eq "None") {
      $endPos = $p.data_offset
      break
    }
    $endPos = $p.data_offset + $p.size
    $shortName = ($p.name -split "_")[0]
    if ($p.type -eq "IntProperty" -and $p.size -ge 4) {
      $result[$shortName] = ReadI32 $B $p.data_offset
    }
    elseif ($p.type -eq "BoolProperty" -and $p.size -ge 1) {
      $result[$shortName] = [bool]$B[$p.data_offset]
    }
    elseif ($p.type -eq "ArrayProperty") {
      $arrCount = ReadI32 $B $p.data_offset
      $arrData = $p.data_offset + 4
      $bytesList = New-Object System.Collections.Generic.List[int]
      for ($i = 0; $i -lt $arrCount -and ($arrData + $i) -lt $B.Length; $i++) {
        $bytesList.Add([int]$B[$arrData + $i]) | Out-Null
      }
      $result[$shortName] = $bytesList.ToArray()
    }
    elseif ($p.type -eq "ByteProperty" -and $p.size -ge 1) {
      $result[$shortName] = [int]$B[$p.data_offset]
    }
  }
  return [pscustomobject]@{ fields = $result; end_pos = $endPos; props = $props }
}

# Find SaveEnemyData property (exact name, not SaveEnemyDataSomething)
$hits = FindAscii $bytes "SaveEnemyData"
$saveHit = $null
foreach ($h in $hits) {
  $after = ReadCString $bytes ($h + 13) 20
  if ($after.StartsWith("ArrayProperty") -or $after.StartsWith("StructProperty")) {
    # name ends at SaveEnemyData\0, next is type len
  }
  # Check char after "SaveEnemyData" is null
  if ($bytes[$h + 13] -eq 0) { $saveHit = $h; break }
}
if ($null -eq $saveHit) { $saveHit = $hits[0] }

$propStart = $saveHit - 4
$topProps = ParseProperties $bytes $propStart 512
$saveProp = $topProps | Where-Object { $_.name -eq "SaveEnemyData" } | Select-Object -First 1
if ($null -eq $saveProp) { throw "SaveEnemyData property not parsed" }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("SaveEnemyData at 0x$($saveHit.ToString('X'))")
$lines.Add("type=$($saveProp.type) size=$($saveProp.size) data_offset=0x$($saveProp.data_offset.ToString('X'))")
$lines.Add("")

$rows = New-Object System.Collections.Generic.List[object]
if ($saveProp.type -ne "ArrayProperty") { throw "Expected ArrayProperty, got $($saveProp.type)" }

$arrCount = ReadI32 $bytes $saveProp.data_offset
$lines.Add("array count = $arrCount")
$pos = $saveProp.data_offset + 4

for ($i = 0; $i -lt $arrCount; $i++) {
  if ($pos -ge $bytes.Length) { break }
  $elem = ParseStructElement $bytes $pos 512
  $pos = $elem.end_pos
  $f = $elem.fields
  $weak = $null
  if ($f.ContainsKey("WeaknessOpen")) { $weak = $f["WeaknessOpen"] }
  $weakHex = if ($weak) { ($weak | ForEach-Object { $_.ToString("X2") }) -join " " } else { "" }
  $rows.Add([pscustomobject]@{
    index = $i
    enemy_id = if ($f.ContainsKey("EnemyID")) { $f["EnemyID"] } else { $null }
    weakness_open = $weakHex
    weakness_count = if ($weak) { $weak.Length } else { 0 }
    field_names = (($elem.props | Where-Object { $_.name -ne "None" } | ForEach-Object { $_.name.Split("_")[0] + ":" + $_.type }) -join " | ")
  }) | Out-Null
  if ($i -lt 5) {
    $lines.Add("[$i] EnemyID=$($rows[$i].enemy_id) WeaknessOpen=[$weakHex] fields=$($rows[$i].field_names)")
  }
}

$lines.Add("")
$lines.Add("total parsed = $($rows.Count)")
$lines.Add("unique enemy_ids = $(($rows | Where-Object { $null -ne $_.enemy_id } | Select-Object -ExpandProperty enemy_id -Unique | Measure-Object).Count)")

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
[System.IO.File]::WriteAllLines($OutTxt, $lines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $OutCsv and $OutTxt ($($rows.Count) entries)"
