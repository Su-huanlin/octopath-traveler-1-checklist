$ErrorActionPreference = "Stop"

$ContentDir = "D:\Unpacking game\afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
$OutHtml = Join-Path $OutDir "octopath_collectibles_auto.html"
$OutCsv = Join-Path $OutDir "octopath_collectibles_auto.csv"
$MapOrderOffset = 12

if (!(Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

function EncodeHtml($Value) { return [System.Net.WebUtility]::HtmlEncode([string]$Value) }

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

function FirstField($Row, [string]$Prefix) {
  foreach ($prop in $Row.PSObject.Properties) {
    if ($prop.Name.StartsWith($Prefix)) { return $prop.Value }
  }
  return $null
}

function ItemName($ItemRows, $TextRows, [string]$ItemId) {
  if ([string]::IsNullOrWhiteSpace($ItemId) -or $ItemId -eq "None") { return "" }
  $prop = $ItemRows.PSObject.Properties[$ItemId]
  if ($null -eq $prop) { return $ItemId }
  $nameKey = FirstField $prop.Value "ItemNameID_"
  $name = TextValue $TextRows $nameKey
  if ($name) { return $name }
  return $ItemId
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

function ObjectLocation($TextRows, [string]$ObjectId) {
  $parts = $ObjectId.Split("_")
  if ($parts.Length -lt 3) { return @{ area_code = ""; map_key = ""; map_name = "" } }
  $region = $parts[1]
  $areaCode = $parts[2]
  foreach ($candidate in (MapCandidates $region $areaCode)) {
    $name = TextValue $TextRows $candidate
    if ($name) { return @{ area_code = $areaCode; map_key = $candidate; map_name = $name } }
  }
  return @{ area_code = $areaCode; map_key = ""; map_name = ("{0}_{1}" -f $region, $areaCode) }
}

function FindSaveData1() {
  $oneDrive = Join-Path $env:USERPROFILE "OneDrive"
  if (!(Test-Path -LiteralPath $oneDrive)) { return $null }
  $save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($null -eq $save) { return $null }
  return $save.FullName
}

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

function ParseByteArray([byte[]]$Bytes, [int]$NameOffset) {
  $nameLen = ReadI32 $Bytes ($NameOffset - 4)
  $typeLenOffset = $NameOffset + $nameLen
  $typeLen = ReadI32 $Bytes $typeLenOffset
  $typeStart = $typeLenOffset + 4
  $sizeOffset = $typeStart + $typeLen
  $size = [BitConverter]::ToInt64($Bytes, $sizeOffset)
  $innerLenOffset = $sizeOffset + 8
  $innerLen = ReadI32 $Bytes $innerLenOffset
  $dataStart = $innerLenOffset + 4 + $innerLen
  $data = New-Object byte[] ([int]$size)
  [Array]::Copy($Bytes, $dataStart, $data, 0, [int]$size)
  return $data
}

function ExtractTreasureArrays([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hits = FindAscii $bytes "TreasureStateArray_"
  $arrays = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $hits.Count; $i++) {
    $arrays.Add((ParseByteArray $bytes $hits[$i]))
  }
  return $arrays
}

function TreasureSlot([string]$ObjectId) {
  if ($ObjectId -match "_(\d+)$") { return ([int]$Matches[1]) - 1 }
  return $null
}

Write-Host "Loading game data..."
$objectRows = LoadRows (Join-Path $ContentDir "Object\Database\ObjectData.json")
$itemRows = LoadRows (Join-Path $ContentDir "Item\Database\ItemDB.json")
$textRows = LoadRows (Join-Path $ContentDir "GameText\Database\GameTextZH_CN.json")

$mapOrder = New-Object System.Collections.Generic.List[string]
foreach ($prop in $textRows.PSObject.Properties) {
  $key = $prop.Name
  if ($key -match "^[TFD]_(Mount|Forest|Plain|River|Cliff|Desert|Sea|Snow)_[0-9LMS]") {
    $mapOrder.Add($key)
  }
}
$mapIndex = @{}
for ($i = 0; $i -lt $mapOrder.Count; $i++) {
  if (!$mapIndex.ContainsKey($mapOrder[$i])) { $mapIndex[$mapOrder[$i]] = $i }
}

$savePath = FindSaveData1
$treasureArrays = $null
if ($savePath) {
  Write-Host "Reading save: $savePath"
  $treasureArrays = ExtractTreasureArrays $savePath
} else {
  Write-Host "SaveData1.sav not found; chest status will be unknown."
}

$entries = New-Object System.Collections.Generic.List[object]
foreach ($prop in $objectRows.PSObject.Properties) {
  $objectId = $prop.Name
  $row = $prop.Value
  if ($objectId.StartsWith("TrsrBx_")) {
    $kind = "Chest"
  } elseif ($objectId.StartsWith("HdnPnt_")) {
    $kind = "Hidden Item"
  } else {
    continue
  }

  $loc = ObjectLocation $textRows $objectId
  $itemId = [string]$row.HaveItemLabel
  $isMoney = [bool]$row.IsMoney
  $count = [int]$row.HaveItemCnt
  if ($isMoney) {
    $reward = "$count LEAF"
    $itemIdOut = ""
  } else {
    $reward = ItemName $itemRows $textRows $itemId
    if ($count -ne 0 -and $count -ne 1) { $reward = "$reward x$count" }
    $itemIdOut = $itemId
  }

  $stateIndex = ""
  $slot = ""
  $saveStatus = "unknown"
  if ($kind -eq "Chest" -and $treasureArrays -and $loc.map_key -and $mapIndex.ContainsKey($loc.map_key)) {
    $stateIndexInt = [int]$mapIndex[$loc.map_key] + $MapOrderOffset
    $slotInt = TreasureSlot $objectId
    $stateIndex = $stateIndexInt
    $slot = $slotInt
    if ($null -ne $slotInt -and $stateIndexInt -ge 0 -and $stateIndexInt -lt $treasureArrays.Count) {
      $arr = $treasureArrays[$stateIndexInt]
      $byteIndex = 6 + $slotInt
      if ($byteIndex -ge 0 -and $byteIndex -lt $arr.Length) {
        if ($arr[$byteIndex] -eq 1) { $saveStatus = "opened" } else { $saveStatus = "unopened" }
      }
    }
  }

  $entries.Add([pscustomobject]@{
    kind = $kind
    save_status = $saveStatus
    map_name = $loc.map_name
    reward = $reward
    object_id = $objectId
    map_key = $loc.map_key
    area_code = $loc.area_code
    state_index = $stateIndex
    slot = $slot
    item_id = $itemIdOut
    count = $count
    object_type = $row.ObjectType
  })
}

$entries = $entries | Sort-Object kind, save_status, map_name, object_id
$entries | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8

$opened = @($entries | Where-Object { $_.kind -eq "Chest" -and $_.save_status -eq "opened" }).Count
$unopened = @($entries | Where-Object { $_.kind -eq "Chest" -and $_.save_status -eq "unopened" }).Count
$unknown = @($entries | Where-Object { $_.kind -eq "Chest" -and $_.save_status -eq "unknown" }).Count
$hidden = @($entries | Where-Object { $_.kind -eq "Hidden Item" }).Count

$rowsHtml = foreach ($e in $entries) {
  $search = (($e.kind, $e.save_status, $e.map_name, $e.reward, $e.object_id, $e.map_key, $e.item_id) -join " ").ToLower()
  '<tr data-kind="{0}" data-status="{1}" data-search="{2}"><td>{1}</td><td>{0}</td><td>{3}</td><td>{4}</td><td><code>{5}</code></td><td><code>{6}</code></td><td>{7}</td><td>{8}</td></tr>' -f `
    (EncodeHtml $e.kind), (EncodeHtml $e.save_status), (EncodeHtml $search), (EncodeHtml $e.map_name), (EncodeHtml $e.reward), (EncodeHtml $e.object_id), (EncodeHtml $e.map_key), (EncodeHtml $e.state_index), (EncodeHtml $e.slot)
}
$rowsJoined = $rowsHtml -join "`n"
$saveShown = if ($savePath) { $savePath } else { "SaveData1.sav not found" }

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Octopath Traveler Auto Tracker</title>
  <style>
    body { font-family: system-ui, "Microsoft YaHei", sans-serif; margin: 24px; background: #111827; color: #e5e7eb; }
    .summary,.controls { display:flex; flex-wrap:wrap; gap:12px; margin:16px 0; }
    .pill { background:#1f2937; border:1px solid #374151; border-radius:999px; padding:8px 12px; }
    input,select { background:#0f172a; color:#e5e7eb; border:1px solid #4b5563; border-radius:8px; padding:8px 10px; }
    input[type=search] { width:min(560px, 90vw); }
    table { border-collapse:collapse; width:100%; }
    th,td { border-bottom:1px solid #374151; padding:8px 10px; text-align:left; vertical-align:top; }
    th { position:sticky; top:0; background:#1f2937; }
    tr[data-status="opened"] { opacity:.45; }
    tr[data-status="unopened"] { background:#1f2937; }
    code { color:#93c5fd; }
    .note { color:#9ca3af; line-height:1.6; }
  </style>
</head>
<body>
  <h1>Octopath Traveler Auto Tracker</h1>
  <p class="note">Save: $(EncodeHtml $saveShown)<br>Chest status uses calibrated rule: state_index = GameText map order + $MapOrderOffset. Hidden items are still not auto-detected.</p>
  <div class="summary">
    <div class="pill">Opened chests: <b>$opened</b></div>
    <div class="pill">Unopened chests: <b>$unopened</b></div>
    <div class="pill">Unknown chests: <b>$unknown</b></div>
    <div class="pill">Hidden items: <b>$hidden</b></div>
    <div class="pill">Visible: <b id="visibleCount">0</b></div>
  </div>
  <div class="controls">
    <input id="q" type="search" placeholder="Search map, reward, object ID">
    <select id="kind"><option value="">All</option><option value="Chest">Chest</option><option value="Hidden Item">Hidden Item</option></select>
    <select id="status"><option value="">All statuses</option><option value="unopened">Unopened</option><option value="opened">Opened</option><option value="unknown">Unknown</option></select>
  </div>
  <table>
    <thead><tr><th>Status</th><th>Type</th><th>Location</th><th>Reward</th><th>Object ID</th><th>Map Key</th><th>State</th><th>Slot</th></tr></thead>
    <tbody>
$rowsJoined
    </tbody>
  </table>
<script>
const rows = [...document.querySelectorAll("tbody tr")];
function applyFilter() {
  const q = document.querySelector("#q").value.trim().toLowerCase();
  const kind = document.querySelector("#kind").value;
  const status = document.querySelector("#status").value;
  let visible = 0;
  for (const row of rows) {
    const show = (!q || row.dataset.search.includes(q)) &&
      (!kind || row.dataset.kind === kind) &&
      (!status || row.dataset.status === status);
    row.style.display = show ? "" : "none";
    if (show) visible++;
  }
  document.querySelector("#visibleCount").textContent = visible;
}
document.querySelector("#q").addEventListener("input", applyFilter);
document.querySelector("#kind").addEventListener("change", applyFilter);
document.querySelector("#status").addEventListener("change", applyFilter);
applyFilter();
</script>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtml, $html, [System.Text.Encoding]::UTF8)
Write-Host "HTML: $OutHtml"
Write-Host "CSV : $OutCsv"
Write-Host "Opened: $opened; Unopened: $unopened; Unknown: $unknown; Hidden: $hidden"
