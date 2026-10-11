$ErrorActionPreference = "Stop"

$Root = "D:\Unpacking game"
$ContentDir = Join-Path $Root "afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
$SavePath = Join-Path $Root "SaveData1.sav"
$OutDir = Join-Path $Root "OctopathTrackerOutput"
if (!(Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

$OutTxt = Join-Path $OutDir "map_ordering_probe.txt"
$OutMapsCsv = Join-Path $OutDir "map_inventory.csv"
$OutOrderingCsv = Join-Path $OutDir "ordering_diagnostic.csv"

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
    if ($suffix -ieq "job") { $candidates.Add(("{0}_{1}_{2}_Job" -f $kind, $Region, $level)) | Out-Null }
    if ($sub) { $baseKey = "{0}_{1}_{2}_{3}" -f $kind, $Region, $level, $sub } else { $baseKey = "{0}_{1}_{2}" -f $kind, $Region, $level }
    if ($suffix -and $suffix -ine "job") {
      $suffixUpper = $suffix.ToUpperInvariant()
      $candidates.Add(("{0}_{1}" -f $baseKey, $suffixUpper)) | Out-Null
      $candidates.Add(("{0}{1}" -f $baseKey, $suffixUpper)) | Out-Null
    }
    $candidates.Add($baseKey) | Out-Null
  }
  if ($kind -eq "T") {
    if ($rest.Length -eq 1) {
      $candidates.Add(("T_{0}_{1}" -f $Region, $rest)) | Out-Null
    } elseif ($rest.Length -eq 2) {
      $candidates.Add(("T_{0}_{1}_{2}" -f $Region, $rest.Substring(0,1), $rest.Substring(1,1))) | Out-Null
      $candidates.Add(("T_{0}_{1}" -f $Region, $rest)) | Out-Null
    } elseif ($rest.Length -eq 3) {
      $candidates.Add(("T_{0}_{1}_{2}_{3}" -f $Region, $rest.Substring(0,1), $rest.Substring(1,1), $rest.Substring(2,1))) | Out-Null
      $candidates.Add(("T_{0}_{1}" -f $Region, $rest)) | Out-Null
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
  # Fall back to the first candidate even if not in text DB.
  $first = (MapCandidates $parts[1] $parts[2])
  if ($first.Count -gt 0) { return $first[0] }
  return ""
}

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

function ParseTreasureArray([byte[]]$B, [int]$NameOffset) {
  $nameLen = [BitConverter]::ToInt32($B, $NameOffset - 4)
  $typeLenOffset = $NameOffset + $nameLen
  $typeLen = [BitConverter]::ToInt32($B, $typeLenOffset)
  $typeStart = $typeLenOffset + 4
  $sizeOffset = $typeStart + $typeLen
  $size = [int][BitConverter]::ToInt64($B, $sizeOffset)
  $innerLenOffset = $sizeOffset + 8
  $innerLen = [BitConverter]::ToInt32($B, $innerLenOffset)
  $dataStart = $innerLenOffset + 4 + $innerLen
  $data = New-Object byte[] $size
  [Array]::Copy($B, $dataStart, $data, 0, $size)
  return $data
}

Write-Host "Loading game data..."
$objectRows = LoadRows (Join-Path $ContentDir "Object\Database\ObjectData.json")
$textRows = LoadRows (Join-Path $ContentDir "GameText\Database\GameTextZH_CN.json")
$bytes = [System.IO.File]::ReadAllBytes($SavePath)
$hits = FindAscii $bytes "TreasureStateArray_"
$arrays = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($h in $hits) {
  $arrays.Add((ParseTreasureArray $bytes $h)) | Out-Null
}
Write-Host "TreasureStateArray blocks: $($arrays.Count)"

# Build inventory: per map_key, list TrsrBx ids and HdnPnt ids.
$inv = @{}
foreach ($prop in $objectRows.PSObject.Properties) {
  $objectId = $prop.Name
  if ($objectId.StartsWith("TrsrBx_")) {
    $kind = "T"
  } elseif ($objectId.StartsWith("HdnPnt_")) {
    $kind = "H"
  } else {
    continue
  }
  $mapKey = ObjectMapKey $textRows $objectId
  if (!$mapKey) { $mapKey = "UNKNOWN_" + $objectId }
  if (!$inv.ContainsKey($mapKey)) {
    $inv[$mapKey] = [pscustomobject]@{
      map_key = $mapKey
      map_name = TextValue $textRows $mapKey
      trsr = New-Object System.Collections.Generic.List[string]
      hidn = New-Object System.Collections.Generic.List[string]
    }
  }
  if ($kind -eq "T") { $inv[$mapKey].trsr.Add($objectId) | Out-Null } else { $inv[$mapKey].hidn.Add($objectId) | Out-Null }
}

# Sort objects inside each map: by trailing number ascending then by name.
foreach ($k in @($inv.Keys)) {
  $entry = $inv[$k]
  $entry.trsr = @($entry.trsr | Sort-Object @{ Expression = { if ($_ -match "_(\d+)$") { [int]$Matches[1] } else { 9999 } } }, { $_ })
  $entry.hidn = @($entry.hidn | Sort-Object @{ Expression = { if ($_ -match "_(\d+)$") { [int]$Matches[1] } else { 9999 } } }, { $_ })
}

# Export inventory
$invRows = $inv.Values | Sort-Object map_key | ForEach-Object {
  [pscustomobject]@{
    map_key = $_.map_key
    map_name = $_.map_name
    chest_count = $_.trsr.Count
    hidden_count = $_.hidn.Count
    total_slots = $_.trsr.Count + $_.hidn.Count
    chest_ids = ($_.trsr -join " ")
    hidden_ids = ($_.hidn -join " ")
  }
}
$invRows | Export-Csv -LiteralPath $OutMapsCsv -NoTypeInformation -Encoding UTF8

# Compute open bits count for each save block.
$blockStats = @()
for ($i = 0; $i -lt $arrays.Count; $i++) {
  $arr = $arrays[$i]
  $cnt = 0
  $lastNonZero = -1
  for ($k = 6; $k -lt $arr.Length; $k++) {
    if ($arr[$k] -ne 0) { $cnt++; $lastNonZero = $k }
  }
  $blockStats += [pscustomobject]@{
    state_index = $i
    open_bits = $cnt
    max_slot_used = $lastNonZero - 6
  }
}

# Candidate orderings
function OrderingGameTextAll() {
  $arr = New-Object System.Collections.Generic.List[string]
  foreach ($prop in $textRows.PSObject.Properties) {
    $key = $prop.Name
    if ($key -match "^[TFD]_(Mount|Forest|Plain|River|Cliff|Desert|Sea|Snow)_[0-9LMS]") {
      if (!$arr.Contains($key)) { $arr.Add($key) | Out-Null }
    }
  }
  return ,$arr
}
function OrderingGameTextNoArea() {
  $all = OrderingGameTextAll
  return ,(@($all | Where-Object { $_ -notmatch "_Area[A-Z]" }))
}
function OrderingGameTextOnlyMapped() {
  # Only keep keys that appear in our inventory (have TrsrBx or HdnPnt).
  $all = OrderingGameTextAll
  return ,(@($all | Where-Object { $inv.ContainsKey($_) }))
}
function OrderingAlphabetical() {
  return ,(@($inv.Keys | Sort-Object))
}
function OrderingByObjectDataFirstSeen() {
  $arr = New-Object System.Collections.Generic.List[string]
  foreach ($prop in $objectRows.PSObject.Properties) {
    $objectId = $prop.Name
    if (!($objectId.StartsWith("TrsrBx_") -or $objectId.StartsWith("HdnPnt_"))) { continue }
    $mapKey = ObjectMapKey $textRows $objectId
    if (!$mapKey) { continue }
    if (!$arr.Contains($mapKey)) { $arr.Add($mapKey) | Out-Null }
  }
  return ,$arr
}

$orderings = @{
  "GameTextAll" = OrderingGameTextAll
  "GameTextNoArea" = OrderingGameTextNoArea
  "GameTextOnlyMapped" = OrderingGameTextOnlyMapped
  "Alphabetical" = OrderingAlphabetical
  "ObjectDataFirstSeen" = OrderingByObjectDataFirstSeen
}

# Anchors that user has confirmed previously.
$anchors = @{
  12 = "T_Mount_S"
  18 = "F_Mount_1_1"
  19 = "F_Mount_1_2"
  21 = "D_Mount_1_1"
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("save_path=$SavePath")
$lines.Add("save_blocks=$($arrays.Count)")
$lines.Add("inventory_unique_maps=$($inv.Count)")
$lines.Add("inventory_total_chests=$((($inv.Values | ForEach-Object { $_.trsr.Count }) | Measure-Object -Sum).Sum)")
$lines.Add("inventory_total_hidden=$((($inv.Values | ForEach-Object { $_.hidn.Count }) | Measure-Object -Sum).Sum)")
$lines.Add("")

# For each candidate ordering: with offset 0..15, count how many blocks violate constraint (open_bits > total_slots).
$diagnosticRows = New-Object System.Collections.Generic.List[object]
foreach ($name in $orderings.Keys) {
  $ord = $orderings[$name]
  $lines.Add(("=== Ordering '{0}' length={1} ===" -f $name, $ord.Count))
  for ($off = 0; $off -le 16; $off++) {
    $violations = 0
    $anchorMatches = 0
    $anchorMisses = 0
    $totalChecked = 0
    for ($i = 0; $i -lt $arrays.Count; $i++) {
      $mapIdx = $i - $off
      if ($mapIdx -lt 0 -or $mapIdx -ge $ord.Count) { continue }
      $mapKey = $ord[$mapIdx]
      $entry = $inv[$mapKey]
      $total = if ($entry) { $entry.trsr.Count + $entry.hidn.Count } else { 0 }
      $open = $blockStats[$i].open_bits
      $totalChecked++
      if ($open -gt $total) { $violations++ }
    }
    foreach ($si in $anchors.Keys) {
      $mapIdx = $si - $off
      if ($mapIdx -ge 0 -and $mapIdx -lt $ord.Count) {
        if ($ord[$mapIdx] -eq $anchors[$si]) { $anchorMatches++ } else { $anchorMisses++ }
      } else {
        $anchorMisses++
      }
    }
    $diagnosticRows.Add([pscustomobject]@{
      ordering = $name
      offset = $off
      checked = $totalChecked
      violations = $violations
      anchor_matches = $anchorMatches
      anchor_misses = $anchorMisses
    }) | Out-Null
    $lines.Add(("  offset={0,2} checked={1,3} violations={2,3} anchor_matches={3}/{4}" -f $off, $totalChecked, $violations, $anchorMatches, ($anchorMatches + $anchorMisses)))
  }
  $lines.Add("")
}

$diagnosticRows | Export-Csv -LiteralPath $OutOrderingCsv -NoTypeInformation -Encoding UTF8

# Best ordering = fewest violations AND most anchor matches
$best = $diagnosticRows | Sort-Object @{Expression='anchor_matches';Descending=$true}, @{Expression='violations';Ascending=$true} | Select-Object -First 1
$lines.Add("BEST CANDIDATE: $($best.ordering) offset=$($best.offset) violations=$($best.violations) anchor_matches=$($best.anchor_matches)")
$lines.Add("")
$lines.Add("Total maps in this best ordering: $($orderings[$best.ordering].Count)")
$lines.Add("Block count: $($arrays.Count)")

# Show the proposed mapping (best ordering + best offset) for the first 30 state_indices, and any violations.
$lines.Add("")
$lines.Add("=== Proposed mapping (best ordering) ===")
$ord = $orderings[$best.ordering]
for ($i = 0; $i -lt $arrays.Count; $i++) {
  $mapIdx = $i - $best.offset
  $mapKey = if ($mapIdx -ge 0 -and $mapIdx -lt $ord.Count) { $ord[$mapIdx] } else { "(out_of_range)" }
  $entry = $inv[$mapKey]
  $total = if ($entry) { $entry.trsr.Count + $entry.hidn.Count } else { 0 }
  $chestCount = if ($entry) { $entry.trsr.Count } else { 0 }
  $hiddenCount = if ($entry) { $entry.hidn.Count } else { 0 }
  $open = $blockStats[$i].open_bits
  $maxSlot = $blockStats[$i].max_slot_used
  $bad = if ($open -gt $total) { " *** VIOLATION" } else { "" }
  $show = ($i -lt 60) -or ($open -gt $total) -or ($anchors.ContainsKey($i))
  if ($show) {
    $name = if ($entry) { $entry.map_name } else { "" }
    $lines.Add(("[{0,3}] open={1,2} max_slot={2,2} map={3,-28} (T={4},H={5},sum={6}) {7} {8}" -f $i, $open, $maxSlot, $mapKey, $chestCount, $hiddenCount, $total, $name, $bad))
  }
}

[System.IO.File]::WriteAllLines($OutTxt, $lines, [System.Text.Encoding]::UTF8)
Write-Host "Done."
Write-Host "TXT:        $OutTxt"
Write-Host "INV CSV:    $OutMapsCsv"
Write-Host "ORDER CSV:  $OutOrderingCsv"
