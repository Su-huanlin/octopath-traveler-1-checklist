$ErrorActionPreference = "Stop"

$Root = "D:\Unpacking game"
$ContentDir = Join-Path $Root "afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
$SavePath = Join-Path $Root "SaveData1.sav"
$OutTxt = Join-Path $Root "OctopathTrackerOutput\current_save_chest_probe.txt"
$OutCsv = Join-Path $Root "OctopathTrackerOutput\current_save_chest_probe.csv"

function LoadRows([string]$Path) {
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $data = $raw | ConvertFrom-Json
  return $data[0].Rows
}

function TextValue($TextRows, [string]$Key) {
  if ([string]::IsNullOrWhiteSpace($Key) -or $Key -eq "None") { return "" }
  $prop = $TextRows.PSObject.Properties[$Key]
  if ($null -eq $prop -or $null -eq $prop.Value.Text) { return "" }
  $text = $prop.Value.Text
  if ($text.LocalizedString) { return [string]$text.LocalizedString }
  if ($text.SourceString) { return [string]$text.SourceString }
  return ""
}

function MapCandidates([string]$Region, [string]$AreaCode) {
  $candidates = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($Region) -or [string]::IsNullOrWhiteSpace($AreaCode)) { return $candidates }
  $kind = $AreaCode.Substring(0, 1)
  $rest = $AreaCode.Substring(1)
  if (($kind -eq "D" -or $kind -eq "F") -and $rest -match "^(\d)(\d?)([A-Za-z]*)$") {
    $level = $Matches[1]
    $sub = $Matches[2]
    $suffix = $Matches[3]
    if ($suffix -ieq "job") { $candidates.Add(("{0}_{1}_{2}_Job" -f $kind, $Region, $level)) }
    if ($sub) { $baseKey = "{0}_{1}_{2}_{3}" -f $kind, $Region, $level, $sub } else { $baseKey = "{0}_{1}_{2}" -f $kind, $Region, $level }
    if ($suffix -and $suffix -ine "job") {
      $suffixUpper = $suffix.ToUpperInvariant()
      $candidates.Add(("{0}_{1}" -f $baseKey, $suffixUpper))
      $candidates.Add(("{0}{1}" -f $baseKey, $suffixUpper))
    }
    $candidates.Add($baseKey)
  }
  if ($kind -eq "T") {
    if ($rest.Length -eq 1) {
      $candidates.Add(("T_{0}_{1}" -f $Region, $rest))
    } elseif ($rest.Length -eq 2) {
      $candidates.Add(("T_{0}_{1}_{2}" -f $Region, $rest.Substring(0,1), $rest.Substring(1,1)))
      $candidates.Add(("T_{0}_{1}" -f $Region, $rest))
    } elseif ($rest.Length -eq 3) {
      $candidates.Add(("T_{0}_{1}_{2}_{3}" -f $Region, $rest.Substring(0,1), $rest.Substring(1,1), $rest.Substring(2,1)))
      $candidates.Add(("T_{0}_{1}" -f $Region, $rest))
    }
  }
  return $candidates
}

function ObjectMapKey($TextRows, [string]$ObjectId) {
  $parts = $ObjectId.Split("_")
  if ($parts.Length -lt 3) { return "" }
  foreach ($candidate in (MapCandidates $parts[1] $parts[2])) {
    if (TextValue $TextRows $candidate) { return $candidate }
  }
  return ""
}

function TreasureSuffix([string]$ObjectId) {
  if ($ObjectId -match "_(\d+)$") { return ([int]$Matches[1]) - 1 }
  return 9999
}

function FindAscii([byte[]]$Bytes, [string]$Needle) {
  $pat = [System.Text.Encoding]::ASCII.GetBytes($Needle)
  $hits = New-Object System.Collections.Generic.List[int]
  outer: for ($i = 0; $i -le $Bytes.Length - $pat.Length; $i++) {
    for ($j = 0; $j -lt $pat.Length; $j++) {
      if ($Bytes[$i + $j] -ne $pat[$j]) { continue outer }
    }
    $hits.Add($i)
  }
  return $hits
}

function ParseByteArray([byte[]]$Bytes, [int]$NameOffset) {
  $nameLen = [BitConverter]::ToInt32($Bytes, $NameOffset - 4)
  $typeLenOffset = $NameOffset + $nameLen
  $typeLen = [BitConverter]::ToInt32($Bytes, $typeLenOffset)
  $typeStart = $typeLenOffset + 4
  $sizeOffset = $typeStart + $typeLen
  $size = [int][BitConverter]::ToInt64($Bytes, $sizeOffset)
  $innerLenOffset = $sizeOffset + 8
  $innerLen = [BitConverter]::ToInt32($Bytes, $innerLenOffset)
  $dataStart = $innerLenOffset + 4 + $innerLen
  $data = New-Object byte[] $size
  [Array]::Copy($Bytes, $dataStart, $data, 0, $size)
  return $data
}

function HexBytes([byte[]]$Bytes) {
  return (($Bytes | ForEach-Object { $_.ToString("X2") }) -join " ")
}

if (!(Test-Path -LiteralPath $SavePath)) { throw "Save file not found: $SavePath" }

$objectRows = LoadRows (Join-Path $ContentDir "Object\Database\ObjectData.json")
$textRows = LoadRows (Join-Path $ContentDir "GameText\Database\GameTextZH_CN.json")
$bytes = [System.IO.File]::ReadAllBytes($SavePath)
$arrays = (FindAscii $bytes "TreasureStateArray_") | ForEach-Object { ParseByteArray $bytes $_ }

$targetMapKeys = @("D_Mount_3_2", "D_Plain_3_Job", "D_Mount_3_Job", "D_River_3_Job", "D_Forest_3_Job")
$chestsByMap = @{}
foreach ($prop in $objectRows.PSObject.Properties) {
  $objectId = $prop.Name
  if (!$objectId.StartsWith("TrsrBx_")) { continue }
  $mapKey = ObjectMapKey $textRows $objectId
  if (!$targetMapKeys.Contains($mapKey)) { continue }
  if (!$chestsByMap.ContainsKey($mapKey)) {
    $chestsByMap[$mapKey] = New-Object System.Collections.Generic.List[object]
  }
  $chestsByMap[$mapKey].Add([pscustomobject]@{
    object_id = $objectId
    suffix = TreasureSuffix $objectId
  })
}

$rows = New-Object System.Collections.Generic.List[object]
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Save: $SavePath")
$lines.Add("TreasureStateArray count: $($arrays.Count)")
$lines.Add("")

foreach ($mapKey in $targetMapKeys) {
  $ordered = @($chestsByMap[$mapKey] | Sort-Object suffix, object_id)
  $mapName = TextValue $textRows $mapKey
  $lines.Add("MAP $mapKey $mapName")
  $lines.Add("Chests: $($ordered.Count) " + (($ordered | ForEach-Object { $_.object_id }) -join ", "))
  $best = @()
  for ($i = 0; $i -lt $arrays.Count; $i++) {
    $arr = $arrays[$i]
    $openCompact = 0
    $compactBits = New-Object System.Collections.Generic.List[string]
    $suffixOpen = 0
    $suffixBits = New-Object System.Collections.Generic.List[string]
    foreach ($chest in $ordered) {
      $compactByte = 6 + [Array]::IndexOf($ordered, $chest)
      $suffixByte = 6 + [int]$chest.suffix
      $compactVal = if ($compactByte -ge 0 -and $compactByte -lt $arr.Length) { [int]$arr[$compactByte] } else { -1 }
      $suffixVal = if ($suffixByte -ge 0 -and $suffixByte -lt $arr.Length) { [int]$arr[$suffixByte] } else { -1 }
      if ($compactVal -eq 1) { $openCompact++ }
      if ($suffixVal -eq 1) { $suffixOpen++ }
      $compactBits.Add([string]$compactVal)
      $suffixBits.Add([string]$suffixVal)
    }
    if ($openCompact -eq $ordered.Count -or $suffixOpen -eq $ordered.Count -or $openCompact -ge [Math]::Max(1, $ordered.Count - 1) -or $suffixOpen -ge [Math]::Max(1, $ordered.Count - 1)) {
      $rows.Add([pscustomobject]@{
        map_key = $mapKey
        map_name = $mapName
        state_index = $i
        chest_count = $ordered.Count
        compact_open = $openCompact
        compact_bits = ($compactBits -join "")
        suffix_open = $suffixOpen
        suffix_bits = ($suffixBits -join "")
        data_hex = HexBytes $arr
      })
      $best += [pscustomobject]@{
        state_index = $i
        compact_open = $openCompact
        compact_bits = ($compactBits -join "")
        suffix_open = $suffixOpen
        suffix_bits = ($suffixBits -join "")
      }
    }
  }
  if ($best.Count -eq 0) {
    $lines.Add("  No near/full-open candidates found.")
  } else {
    foreach ($b in ($best | Sort-Object @{ Expression = "compact_open"; Descending = $true }, @{ Expression = "suffix_open"; Descending = $true }, state_index | Select-Object -First 20)) {
      $lines.Add(("  index={0} compact={1}/{2} bits={3} suffix={4}/{2} bits={5}" -f $b.state_index, $b.compact_open, $ordered.Count, $b.compact_bits, $b.suffix_open, $b.suffix_bits))
    }
  }
  $lines.Add("")
}

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
[System.IO.File]::WriteAllLines($OutTxt, $lines, [System.Text.Encoding]::UTF8)
Write-Host "Output: $OutTxt"
