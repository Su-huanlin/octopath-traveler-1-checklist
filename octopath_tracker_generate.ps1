$ErrorActionPreference = "Stop"

$ContentDir = "D:\Unpacking game\afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
$OutHtml = Join-Path $OutDir "octopath_collectibles.html"
$OutCsv = Join-Path $OutDir "octopath_collectibles.csv"

if (!(Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

function EncodeHtml($Value) {
  return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function LoadRows([string]$Path) {
  if (!(Test-Path -LiteralPath $Path)) {
    throw "Missing file: $Path"
  }
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
  if ([string]::IsNullOrWhiteSpace($Region) -or [string]::IsNullOrWhiteSpace($AreaCode)) {
    return $candidates
  }

  $kind = $AreaCode.Substring(0, 1)
  $rest = $AreaCode.Substring(1)

  if (($kind -eq "D" -or $kind -eq "F") -and $rest -match "^(\d)(\d?)([A-Za-z]*)$") {
    $level = $Matches[1]
    $sub = $Matches[2]
    $suffix = $Matches[3]
    if ($suffix -ieq "job") {
      $candidates.Add(("{0}_{1}_{2}_Job" -f $kind, $Region, $level))
    }
    if ($sub) {
      $baseKey = "{0}_{1}_{2}_{3}" -f $kind, $Region, $level, $sub
    } else {
      $baseKey = "{0}_{1}_{2}" -f $kind, $Region, $level
    }
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

  $candidates.Add(("{0}_{1}_{2}" -f $kind, $Region, $rest))
  return $candidates
}

function ObjectLocation($TextRows, [string]$ObjectId) {
  $parts = $ObjectId.Split("_")
  if ($parts.Length -lt 3) {
    return @{ area_code = ""; map_key = ""; map_name = "" }
  }
  $region = $parts[1]
  $areaCode = $parts[2]
  foreach ($candidate in (MapCandidates $region $areaCode)) {
    $name = TextValue $TextRows $candidate
    if ($name) {
      return @{ area_code = $areaCode; map_key = $candidate; map_name = $name }
    }
  }
  return @{ area_code = $areaCode; map_key = ""; map_name = ("{0}_{1}" -f $region, $areaCode) }
}

Write-Host "Loading JSON files..."
$objectRows = LoadRows (Join-Path $ContentDir "Object\Database\ObjectData.json")
$itemRows = LoadRows (Join-Path $ContentDir "Item\Database\ItemDB.json")
$textRows = LoadRows (Join-Path $ContentDir "GameText\Database\GameTextZH_CN.json")

Write-Host "Building tracker rows..."
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

  $entries.Add([pscustomobject]@{
    kind = $kind
    map_name = $loc.map_name
    reward = $reward
    object_id = $objectId
    map_key = $loc.map_key
    area_code = $loc.area_code
    item_id = $itemIdOut
    count = $count
    object_type = $row.ObjectType
  })
}

$entries = $entries | Sort-Object kind, map_name, object_id
$entries | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8

$rowsHtml = foreach ($e in $entries) {
  $search = (($e.kind, $e.map_name, $e.reward, $e.object_id, $e.map_key, $e.item_id) -join " ").ToLower()
  '<tr data-kind="{0}" data-id="{1}" data-search="{2}"><td><input type="checkbox" class="done"></td><td>{0}</td><td>{3}</td><td>{4}</td><td><code>{1}</code></td><td><code>{5}</code></td></tr>' -f `
    (EncodeHtml $e.kind), (EncodeHtml $e.object_id), (EncodeHtml $search), (EncodeHtml $e.map_name), (EncodeHtml $e.reward), (EncodeHtml $e.map_key)
}

$chests = ($entries | Where-Object { $_.kind -eq "Chest" }).Count
$hidden = ($entries | Where-Object { $_.kind -eq "Hidden Item" }).Count
$total = $entries.Count
$rowsJoined = $rowsHtml -join "`n"

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>Octopath Traveler Collectible Tracker</title>
  <style>
    body { font-family: system-ui, "Microsoft YaHei", sans-serif; margin: 24px; background: #111827; color: #e5e7eb; }
    .summary,.controls { display:flex; flex-wrap:wrap; gap:12px; margin:16px 0; }
    .pill { background:#1f2937; border:1px solid #374151; border-radius:999px; padding:8px 12px; }
    input,select,button { background:#0f172a; color:#e5e7eb; border:1px solid #4b5563; border-radius:8px; padding:8px 10px; }
    input[type=search] { width:min(560px, 90vw); }
    table { border-collapse:collapse; width:100%; }
    th,td { border-bottom:1px solid #374151; padding:8px 10px; text-align:left; vertical-align:top; }
    th { position:sticky; top:0; background:#1f2937; }
    tr.done-row { opacity:.45; }
    code { color:#93c5fd; }
    .note { color:#9ca3af; line-height:1.6; }
  </style>
</head>
<body>
  <h1>Octopath Traveler Collectible Tracker</h1>
  <p class="note">This first version is an external checklist generated from unpacked game data. Checkbox state is stored in this browser only. It does not edit game files.</p>
  <div class="summary">
    <div class="pill">Chests: <b>$chests</b></div>
    <div class="pill">Hidden Items: <b>$hidden</b></div>
    <div class="pill">Total: <b>$total</b></div>
    <div class="pill">Checked: <b id="doneCount">0</b></div>
    <div class="pill">Visible: <b id="visibleCount">0</b></div>
  </div>
  <div class="controls">
    <input id="q" type="search" placeholder="Search map, reward, or object ID">
    <select id="kind"><option value="">All</option><option value="Chest">Chest</option><option value="Hidden Item">Hidden Item</option></select>
    <select id="state"><option value="">All states</option><option value="todo">Unchecked</option><option value="done">Checked</option></select>
    <button id="clear">Clear checks</button>
  </div>
  <table>
    <thead><tr><th>Done</th><th>Type</th><th>Location</th><th>Reward</th><th>Object ID</th><th>Map Key</th></tr></thead>
    <tbody>
$rowsJoined
    </tbody>
  </table>
<script>
const STORAGE_KEY = "octopath_collectible_tracker_v2";
const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
const rows = [...document.querySelectorAll("tbody tr")];
for (const row of rows) {
  const id = row.dataset.id;
  const checkbox = row.querySelector(".done");
  checkbox.checked = !!saved[id];
  row.classList.toggle("done-row", checkbox.checked);
  checkbox.addEventListener("change", () => {
    saved[id] = checkbox.checked;
    if (!checkbox.checked) delete saved[id];
    localStorage.setItem(STORAGE_KEY, JSON.stringify(saved));
    row.classList.toggle("done-row", checkbox.checked);
    applyFilter();
  });
}
function applyFilter() {
  const q = document.querySelector("#q").value.trim().toLowerCase();
  const kind = document.querySelector("#kind").value;
  const state = document.querySelector("#state").value;
  let visible = 0, done = 0;
  for (const row of rows) {
    const checked = row.querySelector(".done").checked;
    if (checked) done++;
    const show = (!q || row.dataset.search.includes(q)) &&
      (!kind || row.dataset.kind === kind) &&
      (!state || (state === "done" ? checked : !checked));
    row.style.display = show ? "" : "none";
    if (show) visible++;
  }
  document.querySelector("#doneCount").textContent = done;
  document.querySelector("#visibleCount").textContent = visible;
}
document.querySelector("#q").addEventListener("input", applyFilter);
document.querySelector("#kind").addEventListener("change", applyFilter);
document.querySelector("#state").addEventListener("change", applyFilter);
document.querySelector("#clear").addEventListener("click", () => {
  if (!confirm("Clear all checkbox states in this HTML page?")) return;
  localStorage.removeItem(STORAGE_KEY);
  for (const row of rows) {
    row.querySelector(".done").checked = false;
    row.classList.remove("done-row");
  }
  applyFilter();
});
applyFilter();
</script>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtml, $html, [System.Text.Encoding]::UTF8)
Write-Host "Done"
Write-Host "HTML: $OutHtml"
Write-Host "CSV : $OutCsv"
Write-Host "Chests $chests; Hidden Items $hidden; Total $total"
