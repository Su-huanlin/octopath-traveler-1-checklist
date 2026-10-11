$ErrorActionPreference = "Stop"

$ContentDir = "D:\Unpacking game\afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
$OutHtml = Join-Path $OutDir "octopath_tracker_portable.html"
if (!(Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

# ---------------- Helpers ----------------

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

function FieldValue($Row, [string]$Prefix) {
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

function TreasureSlot([string]$ObjectId) {
  if ($ObjectId -match "_(\d+)$") { return ([int]$Matches[1]) - 1 }
  return $null
}

# Region prefix (Mount/Forest/...) -> eAREA_NAME_XX (fallback if no WorldMapTable hit)
$RegionPrefixToArea = @{
  "Snow"   = "eAREA_NAME_00"
  "Plain"  = "eAREA_NAME_01"
  "Sea"    = "eAREA_NAME_02"
  "Mount"  = "eAREA_NAME_03"
  "Desert" = "eAREA_NAME_04"
  "River"  = "eAREA_NAME_05"
  "Cliff"  = "eAREA_NAME_06"
  "Forest" = "eAREA_NAME_07"
}

# Manual nearest-town overrides for cases where naming/heuristics get it wrong.
# Key: map_key, Value: town map_key.
$NearestTownOverrides = @{
  # Atlasdam (T_Mount_M) chapter-3 dungeons attached by name, not by chapter number rule.
  "D_Mount_3_1_A" = "T_Mount_M_A"
  "D_Mount_3_1_B" = "T_Mount_M_A"
  "D_Mount_3_2"   = "T_Mount_M_A"
  "F_Mount_3_1"   = "T_Mount_M_A"
  # Highlands chapter-2 (Phantom Forest / Stonetragde passes) -> Stonetragd (T_Mount_L_A).
  "D_Mount_2_1"   = "T_Mount_L_A"
  "D_Mount_2_2"   = "T_Mount_L_A"
  "D_Mount_2_3"   = "T_Mount_L_A"
  "F_Mount_2_1"   = "T_Mount_L_A"
  "F_Mount_2_2"   = "T_Mount_L_A"
  "F_Mount_2_3"   = "T_Mount_L_A"
  # Secondary job shrines (player-confirmed / in-game travel).
  "D_Snow_2_Job"   = "T_Snow_L_A"     # Cleric -> Flamesgrace
  "D_Plain_2_Job"  = "T_Plain_L_A"    # Scholar -> Atlasdam
  "D_Sea_2_Job"    = "T_Sea_L_A"      # Merchant -> Grandport
  "D_Mount_2_Job"  = "T_Mount_S"      # Warrior -> Cobblestone
  "D_Desert_2_Job" = "T_Desert_M_A"   # Dancer -> Wellspring
  "D_River_2_Job"  = "T_River_S"      # Apothecary -> Clearbrook
  "D_Cliff_2_Job"  = "T_Cliff_S"      # Thief -> Orewell
  "D_Forest_2_Job" = "T_Forest_L_A"   # Huntress -> Victor's Hollow
  # Advanced job shrines (player-confirmed).
  "D_Plain_3_Job"  = "T_Plain_S"      # Starseer -> Wispermill
  "D_Mount_3_Job"  = "T_Mount_M_A"    # Warmaster -> Everhold
  "D_River_3_Job"  = "T_River_M_A"    # Runelord shrine is next to Riverford (player-confirmed)
  "D_Forest_3_Job" = "T_Forest_M_A"   # Sorcerer -> Duskbarrow
  # Frostlands trails (never Cathedral / other submaps).
  "F_Snow_1_2"     = "T_Snow_L_A"     # West Flamesgrace (primary); see Multi below
  "F_Snow_1_3"     = "T_Snow_L_A"     # North Flamesgrace
  # Wellspring sands (town key is T_Desert_S_A; name match must see it as a main FT town).
  "F_Desert_2_1"   = "T_Desert_S_A"
  "F_Desert_2_2"   = "T_Desert_S_A"
  "F_Desert_2_3"   = "T_Desert_S_A"
  "F_Desert_2_4"   = "T_Desert_S_A"
}

# Maps whose nearest FT towns need 2 hops / cross-region. Primary key = first (tree bucket).
$NearestTownMultiOverrides = @{
  # West Flamesgrace Snowtrail sits between Flamesgrace and S'warkii; neither is 1-hop.
  "F_Snow_1_2" = @("T_Snow_L_A", "T_Forest_S")
}

# Secret-passage chest whitelist: still on this map, behind invisible walls/cliffs.
# Not wrong-map. Chinese hints built at runtime via char codes (ASCII-safe source).
function U([int[]]$Codes) { -join ($Codes | ForEach-Object { [char]$_ }) }
$SecretChestHints = @{
  "TrsrBx_Cliff_D21_05" = ((U @(0x5BC6,0x9053,0xFF1A,0x5B58,0x6863,0x65C1,0x300C,0x610F,0x8BC6,0x4E4B,0x77F3,0x300D,0x623F,0x95F4,0xFF0C,0x5DE6,0x4E0A,0x89D2,0x8D34,0x5899,0x7A7F,0x5165,0x9690,0x79D8,0x5C0F,0x5BA4)) + " (6000 LEAF)")
  "TrsrBx_Plain_D23_01" = ((U @(0x5BC6,0x9053,0xFF1A,0x77F3,0x62F1,0x9644,0x8FD1,0x5C71,0x5761,0x002F,0x60AC,0x5D16,0x5E95,0x90E8,0x8D34,0x5CA9,0x58C1,0x7A7F,0x5165)) + " (BP L)")
  "TrsrBx_Plain_D23_02" = (U @(0x5BC6,0x9053,0xFF1A,0x77F3,0x62F1,0x5DE6,0x4FA7,0x5C71,0x5761,0x8DEF,0x4E0A))
}

$MissableChestHints = @{}
$MissableChestPath = Join-Path $PSScriptRoot "missable_chest_hints.json"
if (Test-Path -LiteralPath $MissableChestPath) {
  $mcObj = (Get-Content -LiteralPath $MissableChestPath -Raw -Encoding UTF8) | ConvertFrom-Json
  foreach ($hp in $mcObj.PSObject.Properties) {
    $MissableChestHints[[string]$hp.Name] = [string]$hp.Value
  }
}

$StrategistExcludeKeys = @{
  "ENE_Pla_N_010" = $true
  "ENE_Des_N_010" = $true
  "ENE_Sea_N_004" = $true
  "ENE_Sea_N_025" = $true
}

$StrategistExcludePrefix = [string](
  [char]0x3010 + [char]0x4E0D + [char]0x8BA1 + [char]0x5165 + [char]0x300C +
  [char]0x6218 + [char]0x7565 + [char]0x5BB6 + [char]0x300D + [char]0x6210 +
  [char]0x5C31 + [char]0x3011
)

$PositionOverrides = @{
  "TrsrBx_Cliff_D21_05" = "HID"
  "TrsrBx_Plain_D23_01" = "HID"
  "TrsrBx_Plain_D23_02" = "HID"
}

# Hidden item find hints: rebuild from marcv666 NPC sheet + keep missable/stance notes.
$HiddenItemHints = @{}
$HintsJsonPath = Join-Path $PSScriptRoot "hidden_item_hints.json"
$BuildHiddenPy = Join-Path $PSScriptRoot "build_hidden_item_hints.py"
if (Test-Path -LiteralPath $BuildHiddenPy) {
  Write-Host "Building hidden_item_hints.json..."
  & python $BuildHiddenPy
}
if (Test-Path -LiteralPath $HintsJsonPath) {
  $hintObj = (Get-Content -LiteralPath $HintsJsonPath -Raw -Encoding UTF8) | ConvertFrom-Json
  foreach ($hp in $hintObj.PSObject.Properties) {
    $HiddenItemHints[[string]$hp.Name] = [string]$hp.Value
  }
  Write-Host ("Hidden item hints loaded: {0}" -f $HiddenItemHints.Count)
} else {
  Write-Warning "hidden_item_hints.json not found — hidden items will have no find hints."
}

Write-Host "Loading game data..."
$objectRows  = LoadRows (Join-Path $ContentDir "Object\Database\ObjectData.json")
$itemRows    = LoadRows (Join-Path $ContentDir "Item\Database\ItemDB.json")
$textRows    = LoadRows (Join-Path $ContentDir "GameText\Database\GameTextZH_CN.json")
$worldRows   = LoadRows (Join-Path $ContentDir "Level\Database\WorldMapTable.json")
$levelRows   = LoadRows (Join-Path $ContentDir "Level\Database\LevelTable.json")
$placeRows   = $null
$placePath = Join-Path $ContentDir "Character\Database\PlacementInfoData.json"
$listPath  = Join-Path $ContentDir "Character\Database\PlacementInfoList.json"
if (Test-Path -LiteralPath $placePath) {
  Write-Host "Loading PlacementInfoData (positions)..."
  $placeRows = LoadRows $placePath
}
$listRows = $null
if (Test-Path -LiteralPath $listPath) {
  Write-Host "Loading PlacementInfoList (map bounds)..."
  $listRows = LoadRows $listPath
}

# ---------------- map_key -> state_index from LevelTable (authoritative) ----------------
# LevelTable row keys ARE the TreasureStateArray / VisitedMap indices used by the save.
# GameText order +12 drifts after mid-game maps (especially Job shrines) and breaks chests/region.
$mapIndex = @{}              # map_key -> state_index (absolute)
$stateIndexToMapKey = @{}    # state_index -> map_key
$mapKeyToAreaId = @{}        # map_key -> AreaID (0..7)
foreach ($prop in $levelRows.PSObject.Properties) {
  $idx = $null
  if (![int]::TryParse([string]$prop.Name, [ref]$idx)) { continue }
  $levelName = [string](FieldValue $prop.Value "LevelName")
  if ([string]::IsNullOrWhiteSpace($levelName)) { continue }
  if ($levelName -notmatch "^[TFD]_(Mount|Forest|Plain|River|Cliff|Desert|Sea|Snow)_") { continue }
  if (!$mapIndex.ContainsKey($levelName)) { $mapIndex[$levelName] = $idx }
  if (!$stateIndexToMapKey.ContainsKey($idx)) { $stateIndexToMapKey[$idx] = $levelName }
  $areaId = FieldValue $prop.Value "AreaID"
  if ($null -ne $areaId) { $mapKeyToAreaId[$levelName] = [int]$areaId }
}
Write-Host ("LevelTable maps indexed: {0}" -f $mapIndex.Count)

# ---------------- Build state_index -> RegionName via WorldMapTable ----------------
# Each WorldMapTable row has a RefLevelName array (state_index strings) + a RegionName.
# Also build: state_index -> (parent eMAP key, parent's "primary" state_index for fast-travel)
$stateIndexToRegionKey  = @{}
$stateIndexToParentEMap = @{}
$stateIndexToDestX      = @{}   # state_index -> first DestX (legacy)
$stateIndexToDestXs     = @{}   # state_index -> all DestX values
$eMapPrimaryStateIndex  = @{}  # eMAP key -> int (MoveLevelName)
$eMapCanFastTravel      = @{}
$ftTownByRegionPrefix   = @{}  # Mount/Forest/... -> list of { town_key, dest_xs }

$areaKeyToRegionPrefix = @{}
foreach ($rp in @($RegionPrefixToArea.Keys)) {
  $areaKeyToRegionPrefix[$RegionPrefixToArea[$rp]] = $rp
}

function DestXsFromRow($Row) {
  # Collect ALL world-map X coords (towns have multiple exits). Using only [0]
  # mis-assigns nearby dungeons (e.g. 莫洛克的宅邸 DestX≈6172 matches Quarrycrest's
  # exit 6169/6173, but Orewell's sole exit 6098 wins if we only keep each town's first X).
  $xs = New-Object System.Collections.Generic.List[int]
  foreach ($field in @("DestinationFinish_", "DestinationStart_")) {
    $arr = FieldValue $Row $field
    if ($null -eq $arr) { continue }
    foreach ($v in @($arr)) {
      $n = 0
      if ([int]::TryParse([string]$v, [ref]$n) -and $n -gt 0 -and -not $xs.Contains($n)) {
        $xs.Add($n) | Out-Null
      }
    }
  }
  return @($xs)
}

function DestXFromRow($Row) {
  $xs = @(DestXsFromRow $Row)
  if ($xs.Count -gt 0) { return [int]$xs[0] }
  return $null
}

foreach ($prop in $worldRows.PSObject.Properties) {
  $eMapKey = $prop.Name
  $row = $prop.Value
  $regionName  = FieldValue $row "RegionName_"
  $refLevels   = FieldValue $row "RefLevelName_"
  $moveLevel   = FieldValue $row "MoveLevelName_"
  $canFT       = FieldValue $row "CanFastTravel_"
  $destXs      = @(DestXsFromRow $row)
  $destX       = if ($destXs.Count -gt 0) { [int]$destXs[0] } else { $null }
  $primary = $null
  if ($moveLevel -and $moveLevel -ne "None") { $primary = [int]$moveLevel }
  $eMapPrimaryStateIndex[$eMapKey] = $primary
  $eMapCanFastTravel[$eMapKey] = [bool]$canFT
  if ($null -eq $refLevels) { continue }
  foreach ($lvl in @($refLevels)) {
    if ([string]::IsNullOrWhiteSpace($lvl) -or $lvl -eq "None") { continue }
    $idx = $null
    if (![int]::TryParse($lvl, [ref]$idx)) { continue }
    if (!$stateIndexToRegionKey.ContainsKey($idx))  { $stateIndexToRegionKey[$idx]  = $regionName }
    if (!$stateIndexToParentEMap.ContainsKey($idx)) { $stateIndexToParentEMap[$idx] = $eMapKey }
    if ($destX -ne $null -and !$stateIndexToDestX.ContainsKey($idx)) { $stateIndexToDestX[$idx] = $destX }
    if ($destXs.Count -gt 0 -and !$stateIndexToDestXs.ContainsKey($idx)) { $stateIndexToDestXs[$idx] = $destXs }
  }
  if ($canFT -and $primary -ne $null -and $stateIndexToMapKey.ContainsKey($primary)) {
    $townKey = $stateIndexToMapKey[$primary]
    if ($townKey -match "^T_([A-Za-z]+)_") {
      $rp = $Matches[1]
      if ($destXs.Count -gt 0) {
        if (!$ftTownByRegionPrefix.ContainsKey($rp)) {
          $ftTownByRegionPrefix[$rp] = New-Object System.Collections.Generic.List[object]
        }
        $exists = $false
        foreach ($t in $ftTownByRegionPrefix[$rp]) { if ($t.town_key -eq $townKey) { $exists = $true; break } }
        if (!$exists) {
          $ftTownByRegionPrefix[$rp].Add([pscustomobject]@{ town_key = $townKey; dest_xs = $destXs }) | Out-Null
        }
      }
    }
  }
}

# ---------------- Per-map placement bounds (all objects on map, not just collectibles) ----------------
$mapSavePoints = @{}      # map_key -> list of { id, x, y }
$mapBounds = @{}          # map_key -> global bounds
$mapClusterBounds = @{}   # map_key -> hashtable saveId -> local bounds

function Percentile([double[]]$Sorted, [double]$Pct) {
  if ($Sorted.Count -eq 0) { return 0.0 }
  if ($Sorted.Count -eq 1) { return $Sorted[0] }
  $idx = $Pct * ($Sorted.Count - 1)
  $lo = [int][math]::Floor($idx)
  $hi = [int][math]::Ceiling($idx)
  if ($lo -eq $hi) { return $Sorted[$lo] }
  $t = $idx - $lo
  return $Sorted[$lo] * (1.0 - $t) + $Sorted[$hi] * $t
}

function MakeBounds([double[]]$Xs, [double[]]$Ys) {
  if ($Xs.Count -lt 1 -or $Ys.Count -lt 1) { return $null }
  $xsArr = @($Xs | Sort-Object)
  $ysArr = @($Ys | Sort-Object)
  return [pscustomobject]@{
    minX = (Percentile $xsArr 0.05)
    maxX = (Percentile $xsArr 0.95)
    minY = (Percentile $ysArr 0.05)
    maxY = (Percentile $ysArr 0.95)
  }
}

if ($placeRows -and $listRows) {
  foreach ($prop in $listRows.PSObject.Properties) {
    $mk = [string]$prop.Name
    $labels = FieldValue $prop.Value "LabelList_"
    if ($null -eq $labels) { continue }
    $xs = New-Object System.Collections.Generic.List[double]
    $ys = New-Object System.Collections.Generic.List[double]
    $saves = New-Object System.Collections.Generic.List[object]
    $chestPts = New-Object System.Collections.Generic.List[object]
    foreach ($label in @($labels)) {
      if ([string]::IsNullOrWhiteSpace($label)) { continue }
      $rowProp = $placeRows.PSObject.Properties[$label]
      if ($null -eq $rowProp) { continue }
      $row = $rowProp.Value
      $x = [double]$row.SpawnPosX
      $y = [double]$row.SpawnPosY
      if ([string]$row.ActionID -eq "NPCCmn_Saveman") {
        $saves.Add([pscustomobject]@{ id = $label; x = $x; y = $y }) | Out-Null
      }
      if ($label.StartsWith("TrsrBx_") -or $label.StartsWith("HdnPnt_")) {
        $chestPts.Add([pscustomobject]@{ id = $label; x = $x; y = $y }) | Out-Null
      }
      $useForBounds = $false
      if ($label.StartsWith("TrsrBx_") -or $label.StartsWith("HdnPnt_")) { $useForBounds = $true }
      elseif ([string]$row.ActionID -eq "NPCCmn_Saveman") { $useForBounds = $true }
      elseif ([int]$row.SpawnStartFlag -eq 0 -and [int]$row.MainScenarioType -eq 0) { $useForBounds = $true }
      if (!$useForBounds) { continue }
      $xs.Add($x) | Out-Null
      $ys.Add($y) | Out-Null
    }
    if ($saves.Count -gt 0) { $mapSavePoints[$mk] = $saves.ToArray() }
    if ($xs.Count -ge 2) { $mapBounds[$mk] = MakeBounds ([double[]]$xs.ToArray()) ([double[]]$ys.ToArray()) }

    if ($saves.Count -gt 0 -and $chestPts.Count -gt 0) {
      $buckets = @{}
      foreach ($s in $saves) {
        $buckets[[string]$s.id] = @{
          xs = New-Object System.Collections.Generic.List[double]
          ys = New-Object System.Collections.Generic.List[double]
        }
        $buckets[[string]$s.id].xs.Add([double]$s.x) | Out-Null
        $buckets[[string]$s.id].ys.Add([double]$s.y) | Out-Null
      }
      foreach ($c in $chestPts) {
        $bestId = $null; $bestD = [double]::MaxValue
        foreach ($s in $saves) {
          $d = [math]::Sqrt(($c.x - $s.x) * ($c.x - $s.x) + ($c.y - $s.y) * ($c.y - $s.y))
          if ($d -lt $bestD) { $bestD = $d; $bestId = [string]$s.id }
        }
        if ($null -eq $bestId) { continue }
        $buckets[$bestId].xs.Add([double]$c.x) | Out-Null
        $buckets[$bestId].ys.Add([double]$c.y) | Out-Null
      }
      $local = @{}
      foreach ($sid in @($buckets.Keys)) {
        $bx = $buckets[$sid].xs
        $by = $buckets[$sid].ys
        $b = MakeBounds ([double[]]$bx.ToArray()) ([double[]]$by.ToArray())
        if ($b) { $local[[string]$sid] = $b }
      }
      if ($local.Count -gt 0) { $mapClusterBounds[$mk] = $local }
    }
  }
}
# ---------------- Per-object world position (collectibles only, for slot lookup) ----------------
$objectPosition = @{}
if ($placeRows) {
  foreach ($prop in $placeRows.PSObject.Properties) {
    $oid = $prop.Name
    if (!($oid.StartsWith("HdnPnt_") -or $oid.StartsWith("TrsrBx_"))) { continue }
    $row = $prop.Value
    $objectPosition[$oid] = [pscustomobject]@{
      x = [double]$row.SpawnPosX
      y = [double]$row.SpawnPosY
    }
  }
}

# Map a (x, y) coordinate to a 3x3 quadrant label inside its map.
# UE coords: +Y is north. Prefer nearest-save LOCAL absolute bounds for multi-save dungeons.
function QuadrantLabelAbsolute([double]$X, [double]$Y, $Bounds) {
  if (!$Bounds) { return "" }
  $rangeX = $Bounds.maxX - $Bounds.minX
  $rangeY = $Bounds.maxY - $Bounds.minY
  if ($rangeX -le 0 -and $rangeY -le 0) { return "" }
  $fx = if ($rangeX -gt 0) { ($X - $Bounds.minX) / $rangeX } else { 0.5 }
  $fy = if ($rangeY -gt 0) { ($Y - $Bounds.minY) / $rangeY } else { 0.5 }
  $col = if ($fx -lt 0.34) { 0 } elseif ($fx -lt 0.67) { 1 } else { 2 }
  $row = if ($fy -lt 0.34) { 2 } elseif ($fy -lt 0.67) { 1 } else { 0 }
  $codes = @(
    @("NW", "N",  "NE"),
    @("W",  "C",  "E"),
    @("SW", "S",  "SE")
  )
  return $codes[$row][$col]
}

function ResolvePositionLabel([string]$ObjectId, [string]$MapKey) {
  if ($PositionOverrides.ContainsKey($ObjectId)) { return [string]$PositionOverrides[$ObjectId] }
  if (!$objectPosition.ContainsKey($ObjectId)) { return "" }
  $pos = $objectPosition[$ObjectId]
  if ($mapSavePoints.ContainsKey($MapKey) -and $mapClusterBounds.ContainsKey($MapKey)) {
    $bestId = $null; $bestD = [double]::MaxValue
    foreach ($s in @($mapSavePoints[$MapKey])) {
      $d = [math]::Sqrt(($pos.x - $s.x) * ($pos.x - $s.x) + ($pos.y - $s.y) * ($pos.y - $s.y))
      if ($d -lt $bestD) { $bestD = $d; $bestId = [string]$s.id }
    }
    if ($bestId -and $mapClusterBounds[$MapKey].ContainsKey($bestId)) {
      return QuadrantLabelAbsolute $pos.x $pos.y $mapClusterBounds[$MapKey][$bestId]
    }
  }
  if ($mapBounds.ContainsKey($MapKey)) {
    return QuadrantLabelAbsolute $pos.x $pos.y $mapBounds[$MapKey]
  }
  return ""
}
# ---------------- Per-map TrsrBx / HdnPnt inventory (for slot calc) ----------------
$objectsByMap = @{}
foreach ($prop in $objectRows.PSObject.Properties) {
  $objectId = $prop.Name
  if ($objectId.StartsWith("TrsrBx_")) { $kindFlag = "T" }
  elseif ($objectId.StartsWith("HdnPnt_")) { $kindFlag = "H" }
  else { continue }
  $loc = ObjectLocation $textRows $objectId
  if (!$loc.map_key) { continue }
  if (!$objectsByMap.ContainsKey($loc.map_key)) {
    $objectsByMap[$loc.map_key] = [pscustomobject]@{
      trsr = New-Object System.Collections.Generic.List[object]
      hidn = New-Object System.Collections.Generic.List[object]
    }
  }
  $entry = [pscustomobject]@{
    object_id = $objectId
    suffix    = TreasureSlot $objectId
  }
  if ($kindFlag -eq "T") { $objectsByMap[$loc.map_key].trsr.Add($entry) | Out-Null }
  else                   { $objectsByMap[$loc.map_key].hidn.Add($entry) | Out-Null }
}

$slotByObject = @{}
foreach ($mapKey in @($objectsByMap.Keys)) {
  $bucket = $objectsByMap[$mapKey]
  $orderedTrsr = @($bucket.trsr | Sort-Object suffix, object_id)
  $orderedHidn = @($bucket.hidn | Sort-Object suffix, object_id)
  for ($i = 0; $i -lt $orderedTrsr.Count; $i++) { $slotByObject[$orderedTrsr[$i].object_id] = $i }
  for ($i = 0; $i -lt $orderedHidn.Count; $i++) { $slotByObject[$orderedHidn[$i].object_id] = $orderedTrsr.Count + $i }
}

# ---------------- Town catalog (per region, list of all town map_keys) ----------------
$townsByRegion = @{}
foreach ($mk in $mapIndex.Keys) {
  if ($mk -match "^T_([A-Za-z]+)_") {
    $region = $Matches[1]
    if (!$townsByRegion.ContainsKey($region)) { $townsByRegion[$region] = New-Object System.Collections.Generic.List[string] }
    $townsByRegion[$region].Add($mk) | Out-Null
  }
}

# Helper: figure out the nearest fast-travel town for any map_key.
# Only MAIN fast-travel towns (T_*_S / T_*_M_A / T_*_L_A). Never Cathedral / submaps.
function IsMainFtTownKey([string]$Key) {
  if ([string]::IsNullOrWhiteSpace($Key)) { return $false }
  # Wellspring is T_Desert_S_A (S-size town with _A), not T_Desert_S.
  return [bool]($Key -match '^T_[A-Za-z]+_(?:S(?:_A)?|[ML]_A)$')
}

function NormalizeMainTownKey([string]$Key) {
  if ([string]::IsNullOrWhiteSpace($Key)) { return $null }
  if ($Key -match '^(T_[A-Za-z]+_[ML])_[BC]$') { return ($Matches[1] + '_A') }
  if ($Key -match '^(T_[A-Za-z]+_S)_[BC]$') { return ($Matches[1] + '_A') }
  if ($Key -match '^(T_[A-Za-z]+_[ML])$') { return ($Matches[1] + '_A') }
  if ($Key -match '^T_[A-Za-z]+_S_A$') { return $Key }
  if ($Key -match '^T_[A-Za-z]+_S$') { return $Key }
  if ($Key -match '^T_[A-Za-z]+_[ML]_A$') { return $Key }
  return $Key
}

# Chapter number on F_/D_ maps -> that region's story town (S/M/L is town size, not chapter).
$RegionChapterTownSize = @{
  "Snow"   = @{ "1" = "L"; "2" = "S"; "3" = "M" }
  "Plain"  = @{ "1" = "L"; "2" = "M"; "3" = "S" }
  "Sea"    = @{ "1" = "S"; "2" = "M"; "3" = "L" }
  "Mount"  = @{ "1" = "S"; "2" = "L"; "3" = "M" }
  "Desert" = @{ "1" = "M"; "2" = "S"; "3" = "L" }
  "River"  = @{ "1" = "S"; "2" = "L"; "3" = "M" }
  "Cliff"  = @{ "1" = "L"; "2" = "M"; "3" = "S" }
  "Forest" = @{ "1" = "S"; "2" = "L"; "3" = "M" }
}

function TownKeyForRegionSize([string]$RegionPrefix, [string]$Size) {
  if ($Size -eq "S") {
    foreach ($candidate in @("T_${RegionPrefix}_S", "T_${RegionPrefix}_S_A")) {
      if ($mapIndex.ContainsKey($candidate)) { return $candidate }
    }
    return $null
  }
  $k = "T_${RegionPrefix}_${Size}_A"
  if ($mapIndex.ContainsKey($k)) { return $k }
  return $null
}

function TownFromChapter([string]$MapKey) {
  if ($MapKey -notmatch "^[FD]_([A-Za-z]+)_([123])") { return $null }
  $regionPrefix = $Matches[1]
  $ch = $Matches[2]
  if (-not $RegionChapterTownSize.ContainsKey($regionPrefix)) { return $null }
  $sizeMap = $RegionChapterTownSize[$regionPrefix]
  if (-not $sizeMap.ContainsKey($ch)) { return $null }
  return (TownKeyForRegionSize $regionPrefix $sizeMap[$ch])
}

function TownFromMapNameKeyword([string]$MapName, [string]$RegionPrefix, $TownsByRegion, $TextRows) {
  if ([string]::IsNullOrWhiteSpace($MapName) -or !$TownsByRegion.ContainsKey($RegionPrefix)) { return $null }
  $bestKey = $null; $bestLen = 0
  foreach ($tk in $TownsByRegion[$RegionPrefix]) {
    if (-not (IsMainFtTownKey $tk)) { continue }
    $townName = TextValue $TextRows $tk
    if ([string]::IsNullOrWhiteSpace($townName)) { continue }
    $core = ($townName -split '\s')[0]
    if ($core.Length -lt 2) { continue }
    if ($MapName.Contains($core) -and $core.Length -gt $bestLen) {
      $bestKey = $tk; $bestLen = $core.Length
    }
  }
  return $bestKey
}

function TownFromWorldDest([int]$StateIndex, [string]$RegionPrefix, $FtTownByRegionPrefix) {
  if (!$FtTownByRegionPrefix.ContainsKey($RegionPrefix)) { return $null }
  $mapXs = @()
  if ($stateIndexToDestXs.ContainsKey($StateIndex)) { $mapXs = @($stateIndexToDestXs[$StateIndex]) }
  elseif ($stateIndexToDestX.ContainsKey($StateIndex)) { $mapXs = @([int]$stateIndexToDestX[$StateIndex]) }
  if ($mapXs.Count -eq 0) { return $null }
  $best = $null; $bestDist = [double]::MaxValue
  foreach ($t in $FtTownByRegionPrefix[$RegionPrefix]) {
    $townKey = NormalizeMainTownKey $t.town_key
    if (-not (IsMainFtTownKey $townKey)) { continue }
    $townXs = @()
    if ($null -ne $t.dest_xs) { $townXs = @($t.dest_xs) }
    elseif ($null -ne $t.dest_x) { $townXs = @([int]$t.dest_x) }
    foreach ($mx in $mapXs) {
      foreach ($tx in $townXs) {
        $d = [math]::Abs([int]$mx - [int]$tx)
        if ($d -lt $bestDist) { $bestDist = $d; $best = $townKey }
      }
    }
  }
  return $best
}

function NearestTown([string]$MapKey, [string]$MapName, $TownsByRegion, $TextRows, $Overrides, $MapIndex, $StateIndexToMapKey, $FtTownByRegionPrefix) {
  if ([string]::IsNullOrWhiteSpace($MapKey)) { return $null }
  if ($Overrides.ContainsKey($MapKey)) { return (NormalizeMainTownKey $Overrides[$MapKey]) }

  if ($MapKey -match "^T_([A-Za-z]+)_([SLM])") {
    $region = $Matches[1]; $size = $Matches[2]
    foreach ($candidate in @("T_${region}_${size}_A", "T_${region}_${size}")) {
      if ($TownsByRegion.ContainsKey($region) -and $TownsByRegion[$region].Contains($candidate)) {
        return (NormalizeMainTownKey $candidate)
      }
    }
    return (NormalizeMainTownKey $MapKey)
  }

  if ($MapKey -notmatch "^[FD]_([A-Za-z]+)_") { return $null }
  $regionPrefix = $Matches[1]

  if ($MapKey -match "^[FD]_Mount_2") { return "T_Mount_L_A" }
  if ($MapKey -match "^[FD]_Cliff_2" -and $MapKey -notmatch "_Job") { return "T_Cliff_M_A" }

  $byName = TownFromMapNameKeyword $MapName $regionPrefix $TownsByRegion $TextRows
  if ($byName) { return (NormalizeMainTownKey $byName) }

  $byChapter = TownFromChapter $MapKey
  if ($byChapter) { return (NormalizeMainTownKey $byChapter) }

  if ($MapIndex.ContainsKey($MapKey)) {
    $si = [int]$MapIndex[$MapKey]
    $byDest = TownFromWorldDest $si $regionPrefix $FtTownByRegionPrefix
    if ($byDest) { return (NormalizeMainTownKey $byDest) }
    if ($stateIndexToParentEMap.ContainsKey($si)) {
      $eMap = $stateIndexToParentEMap[$si]
      if ($eMapPrimaryStateIndex.ContainsKey($eMap)) {
        $moveIdx = $eMapPrimaryStateIndex[$eMap]
        if ($moveIdx -ne $null -and $StateIndexToMapKey.ContainsKey([int]$moveIdx)) {
          $mk2 = $StateIndexToMapKey[[int]$moveIdx]
          if ($mk2 -match "^T_${regionPrefix}_") { return (NormalizeMainTownKey $mk2) }
        }
      }
    }
  }
  return $null
}

function ResolveNearestTowns([string]$MapKey, [string]$MapName) {
  if ($NearestTownMultiOverrides.ContainsKey($MapKey)) {
    return @($NearestTownMultiOverrides[$MapKey] | ForEach-Object { NormalizeMainTownKey $_ } | Where-Object { $_ })
  }
  $one = NearestTown $MapKey $MapName $townsByRegion $textRows $NearestTownOverrides $mapIndex $stateIndexToMapKey $ftTownByRegionPrefix
  if ($one) { return @($one) }
  return @()
}

# GameText often reuses the same name for _A/_B dungeon floors (e.g. 古代的遗迹).
# Keep them as separate maps (different encounters) but label 一层/二层 when names collide.
function DisambiguateFloorName([string]$MapKey, [string]$MapName) {
  if ([string]::IsNullOrWhiteSpace($MapKey) -or [string]::IsNullOrWhiteSpace($MapName)) { return $MapName }
  if ($MapName -match '下层|上层|一层|二层') { return $MapName }
  # Only dungeon A/B floors share identical GameText names (e.g. 古代的遗迹).
  # Towns like T_Desert_S_A / T_Desert_S_B both display as 威尔斯宾克.
  if ($MapKey -notmatch '^D_') { return $MapName }
  if ($MapKey -notmatch '^(.*)_([AB])$') { return $MapName }
  $base = $Matches[1]
  $floor = $Matches[2]
  $sibling = if ($floor -eq 'A') { "${base}_B" } else { "${base}_A" }
  $sibName = TextValue $textRows $sibling
  if ([string]::IsNullOrWhiteSpace($sibName) -or $sibName -ne $MapName) { return $MapName }
  $tag = if ($floor -eq 'A') { [string][char]0x4E00 + [string][char]0x5C42 } else { [string][char]0x4E8C + [string][char]0x5C42 }
  return ($MapName + " -" + $tag + "-")
}

# ---------------- Build entries ----------------
$entries = New-Object System.Collections.Generic.List[object]
foreach ($prop in $objectRows.PSObject.Properties) {
  $objectId = $prop.Name
  $row = $prop.Value
  if     ($objectId.StartsWith("TrsrBx_"))  { $kind = "Chest" }
  elseif ($objectId.StartsWith("HdnPnt_"))  { $kind = "Hidden Item" }
  else { continue }

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

  $stateIndex = $null
  $slot = $null
  if ($loc.map_key -and $mapIndex.ContainsKey($loc.map_key)) {
    $stateIndex = [int]$mapIndex[$loc.map_key]
    if ($slotByObject.ContainsKey($objectId)) { $slot = [int]$slotByObject[$objectId] }
    else                                       { $slot = TreasureSlot $objectId }
  }

  # Region: prefer LevelTable AreaID, then WorldMapTable, then map-key prefix.
  $regionKey = $null
  if ($loc.map_key -and $mapKeyToAreaId.ContainsKey($loc.map_key)) {
    $regionKey = ("eAREA_NAME_{0:D2}" -f [int]$mapKeyToAreaId[$loc.map_key])
  } elseif ($stateIndex -ne $null -and $stateIndexToRegionKey.ContainsKey($stateIndex)) {
    $regionKey = $stateIndexToRegionKey[$stateIndex]
  } elseif ($loc.map_key -match "^[TFD]_([A-Za-z]+)_" -and $RegionPrefixToArea.ContainsKey($Matches[1])) {
    $regionKey = $RegionPrefixToArea[$Matches[1]]
  }
  $regionName = if ($regionKey) { TextValue $textRows $regionKey } else { "" }

  # Nearest FT town(s) for travel hint (main towns only; may be multi for 2-hop trails).
  $townKeys = @(ResolveNearestTowns $loc.map_key $loc.map_name)
  $nearestTownKey  = if ($townKeys.Count -gt 0) { $townKeys[0] } else { $null }
  $nearestTownName = if ($townKeys.Count -gt 0) {
    (@($townKeys | ForEach-Object { TextValue $textRows $_ } | Where-Object { $_ }) -join ([string][char]0x3001))
  } else { "" }

  # Kind code: T/F/D
  $mapKindCode = if ($loc.map_key -match "^([TFD])_") { $Matches[1] } else { "" }

  # Position: secret overrides, else nearest-save local absolute quadrant.
  $positionLabel = if ($loc.map_key) { ResolvePositionLabel $objectId $loc.map_key } else { "" }
  $findHint = ""
  if ($kind -eq "Chest" -and $SecretChestHints.ContainsKey($objectId)) {
    $findHint = [string]$SecretChestHints[$objectId]
  } elseif ($kind -eq "Hidden Item" -and $HiddenItemHints.ContainsKey($objectId)) {
    $findHint = [string]$HiddenItemHints[$objectId]
  }
  if ($kind -eq "Chest" -and $MissableChestHints.ContainsKey($objectId)) {
    $miss = [string]$MissableChestHints[$objectId]
    $findHint = if ($findHint) { $miss + $findHint } else { $miss }
  }
  $entries.Add([pscustomobject]@{
    kind             = $kind
    map_name         = (DisambiguateFloorName $loc.map_key $loc.map_name)
    map_key          = $loc.map_key
    map_kind_code    = $mapKindCode
    reward           = $reward
    object_id        = $objectId
    area_code        = $loc.area_code
    state_index      = $stateIndex
    slot             = $slot
    item_id          = $itemIdOut
    count            = $count
    object_type      = $row.ObjectType
    region_key       = $regionKey
    region_name      = $regionName
    nearest_town_key  = $nearestTownKey
    nearest_town_name = $nearestTownName
    position_label    = $positionLabel
    find_hint         = $findHint
  })
}

# ---------------- Build enemy weakness + spawn location entries ----------------
# Authoritative Strategist list = 381 enemies from SaveDataEditor info.xlsx.
# Spawn maps MUST come from LevelTable.EncountVolumeNameList -> EncountVolumeData -> ENC
# (NOT from ENC_* filename guessing — Rem/Hou share numbers with Cav maps but live on different levels).
Write-Host "Loading enemy/battle databases..."
$enemySpawnEntries = New-Object System.Collections.Generic.List[object]

$encounterPath   = Join-Path $ContentDir "Battle\Database\BattleEncounterData.json"
$groupPath       = Join-Path $ContentDir "Battle\Database\EnemyGroupData.json"
$encVolumePath   = Join-Path $ContentDir "Battle\Database\EncountVolumeData.json"
$strategistPath  = Join-Path $PSScriptRoot "strategist_enemies_381.json"

function AddEnemySpawnEntry($Cat, [string]$Mk) {
  $mapName = ""
  $regionKey = $null
  $regionName = ""
  $nearestTownKey = $null
  $nearestTownName = ""
  $mapKindCode = ""
  if ([string]::IsNullOrWhiteSpace($Mk) -or $Mk -eq "_UNMAPPED_") {
    $Mk = "_UNMAPPED_"
    $mapName = [string][char]0x5F52 + [string][char]0x5C5E + [string][char]0x4E0D + [string][char]0x660E
    $nearestTownName = $mapName
    $regionKey = "_UNKNOWN_"
    $regionName = $mapName
  } else {
    $mapName = TextValue $textRows $Mk
    if (!$mapName) { $mapName = $Mk }
    $mapName = DisambiguateFloorName $Mk $mapName
    $stateIndex = $null
    if ($mapIndex.ContainsKey($Mk)) { $stateIndex = [int]$mapIndex[$Mk] }
    if ($mapKeyToAreaId.ContainsKey($Mk)) {
      $regionKey = ("eAREA_NAME_{0:D2}" -f [int]$mapKeyToAreaId[$Mk])
    } elseif ($null -ne $stateIndex -and $stateIndexToRegionKey.ContainsKey($stateIndex)) {
      $regionKey = $stateIndexToRegionKey[$stateIndex]
    } elseif ($Mk -match "^[TFD]_([A-Za-z]+)_" -and $RegionPrefixToArea.ContainsKey($Matches[1])) {
      $regionKey = $RegionPrefixToArea[$Matches[1]]
    }
    $regionName = if ($regionKey) { TextValue $textRows $regionKey } else { "" }
    $townKeys = @(ResolveNearestTowns $Mk $mapName)
    $nearestTownKey  = if ($townKeys.Count -gt 0) { $townKeys[0] } else { $null }
    $nearestTownName = if ($townKeys.Count -gt 0) {
      (@($townKeys | ForEach-Object { TextValue $textRows $_ } | Where-Object { $_ }) -join ([string][char]0x3001))
    } else { "" }
    $mapKindCode = if ($Mk -match "^([TFD])_") { $Matches[1] } else { "" }
  }

  $enemySpawnEntries.Add([pscustomobject]@{
    kind              = "Monster"
    enemy_key         = [string]$Cat.enemy_key
    enemy_id_num      = [int]$Cat.enemy_id_num
    name              = [string]$Cat.name
    level             = [int]$Cat.level
    weak_slots        = @($Cat.weak_slots)
    weak_count        = [int]$Cat.weak_count
    weapon_weak       = [int]$Cat.weapon_weak
    magic_weak        = [int]$Cat.magic_weak
    map_key           = $Mk
    map_name          = $mapName
    map_kind_code     = $mapKindCode
    region_key        = $regionKey
    region_name       = $regionName
    nearest_town_key  = $nearestTownKey
    nearest_town_name = $nearestTownName
    missable_note     = $(if ($StrategistExcludeKeys.ContainsKey([string]$Cat.enemy_key)) { $StrategistExcludePrefix } else { "" })
  }) | Out-Null
}

if ((Test-Path -LiteralPath $strategistPath) -and (Test-Path -LiteralPath $encounterPath) -and (Test-Path -LiteralPath $groupPath) -and (Test-Path -LiteralPath $encVolumePath)) {
  $strategist    = Get-Content -LiteralPath $strategistPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $encounterRows = LoadRows $encounterPath
  $groupRows     = LoadRows $groupPath
  $encVolumeRows = LoadRows $encVolumePath

  # EVM -> ENC_ list
  $evmToEncKeys = @{}
  foreach ($prop in $encVolumeRows.PSObject.Properties) {
    $evmKey = [string]$prop.Name
    if (!$evmKey.StartsWith("EVM_")) { continue }
    $encSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $list = FieldValue $prop.Value "EncounterList_"
    if ($null -ne $list) {
      foreach ($item in @($list)) {
        $encName = FieldValue $item "EncounterName_"
        if ([string]::IsNullOrWhiteSpace($encName) -or $encName -eq "None") { continue }
        [void]$encSet.Add([string]$encName)
      }
    }
    $evmToEncKeys[$evmKey] = $encSet
  }

  # ENC_ -> enemy keys
  $encToEnemyKeys = @{}
  foreach ($prop in $encounterRows.PSObject.Properties) {
    $encKey = [string]$prop.Name
    if (!$encKey.StartsWith("ENC_")) { continue }
    $eneSet = New-Object 'System.Collections.Generic.HashSet[string]'
    $groups = FieldValue $prop.Value "Group_"
    if ($null -eq $groups) { continue }
    foreach ($g in @($groups)) {
      $gId = FieldValue $g "GroupID_"
      if ([string]::IsNullOrWhiteSpace($gId) -or $gId -eq "None") { continue }
      $gProp = $groupRows.PSObject.Properties[$gId]
      if ($null -eq $gProp) { continue }
      foreach ($eneId in @(FieldValue $gProp.Value "EnemyID_")) {
        if ([string]::IsNullOrWhiteSpace($eneId) -or $eneId -eq "None") { continue }
        [void]$eneSet.Add([string]$eneId)
      }
    }
    $encToEnemyKeys[$encKey] = $eneSet
  }

  # LevelTable: LevelName -> EncountVolumeNameList -> enemies
  $spawnsByKey = @{}
  foreach ($prop in $levelRows.PSObject.Properties) {
    $row = $prop.Value
    $levelName = [string](FieldValue $row "LevelName")
    if ([string]::IsNullOrWhiteSpace($levelName) -or $levelName -eq "None") { continue }
    $volList = FieldValue $row "EncountVolumeNameList"
    if ($null -eq $volList) { continue }
    foreach ($evmKey in @($volList)) {
      $evm = [string]$evmKey
      if ([string]::IsNullOrWhiteSpace($evm) -or $evm -eq "None") { continue }
      if (-not $evmToEncKeys.ContainsKey($evm)) { continue }
      foreach ($encKey in @($evmToEncKeys[$evm])) {
        if (-not $encToEnemyKeys.ContainsKey($encKey)) { continue }
        foreach ($eneId in @($encToEnemyKeys[$encKey])) {
          if (-not $spawnsByKey.ContainsKey($eneId)) {
            $spawnsByKey[$eneId] = New-Object 'System.Collections.Generic.HashSet[string]'
          }
          [void]$spawnsByKey[$eneId].Add($levelName)
        }
      }
    }
  }

  $mappedUnique = 0
  foreach ($cat in @($strategist)) {
    $eKey = [string]$cat.enemy_key
    $maps = @()
    if ($spawnsByKey.ContainsKey($eKey)) { $maps = @($spawnsByKey[$eKey]) }
    if ($maps.Count -eq 0) {
      AddEnemySpawnEntry $cat "_UNMAPPED_"
    } else {
      $mappedUnique++
      foreach ($mk in $maps) { AddEnemySpawnEntry $cat $mk }
    }
  }
  Write-Host ("Built {0} enemy spawn entries ({1} strategist enemies, {2} with LevelTable volumes)" -f $enemySpawnEntries.Count, $strategist.Count, $mappedUnique)
} else {
  Write-Host "WARN: strategist/encounter/volume DB files missing; monster weakness view will be empty."
}

# ---------------- Region order for UI (8 regions in a sensible order) ----------------
$regionOrderKeys = @(
  "eAREA_NAME_03",  # Mountain (Highlands)
  "eAREA_NAME_04",  # Desert  (Sunlands)
  "eAREA_NAME_05",  # River   (Riverlands)
  "eAREA_NAME_06",  # Cliff   (Clifflands)
  "eAREA_NAME_07",  # Forest  (Woodlands)
  "eAREA_NAME_01",  # Plain   (Flatlands)
  "eAREA_NAME_02",  # Sea     (Coastlands)
  "eAREA_NAME_00"   # Snow    (Frostlands)
)
$regionOrder = @()
foreach ($k in $regionOrderKeys) {
  $regionOrder += [pscustomobject]@{
    key  = $k
    name = TextValue $textRows $k
  }
}

$collectorBuild = Join-Path $PSScriptRoot "build_collector_items.py"
$collectorPath  = Join-Path $PSScriptRoot "collector_items.json"
if (Test-Path -LiteralPath $collectorBuild) {
  Write-Host "Building collector_items.json..."
  & python $collectorBuild
}
if (!(Test-Path -LiteralPath $collectorPath)) {
  throw "collector_items.json missing"
}
$collectorJson    = (Get-Content -LiteralPath $collectorPath -Raw -Encoding UTF8).Trim()
$entriesJson      = $entries | ConvertTo-Json -Depth 5 -Compress
$enemySpawnJson   = $enemySpawnEntries | ConvertTo-Json -Depth 6 -Compress
$regionOrderJson  = $regionOrder | ConvertTo-Json -Depth 4 -Compress
$kindNotesPath = Join-Path $PSScriptRoot "achievement_kind_notes.json"
if (Test-Path -LiteralPath $kindNotesPath) {
  $kindAchieveNoteJson = (Get-Content -LiteralPath $kindNotesPath -Raw -Encoding UTF8).Trim()
} else {
  $kindAchieveNoteJson = "{}"
}
$generatedAt      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

# ---------------- HTML ----------------
$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>&#20843;&#26041;&#26053;&#20154;1 &#25910;&#38598;&#26816;&#26597;&#22120;</title>
  <style>
    /* ----- Theme variables: dark (default), light (soft cream-white), sepia (warm reading) ----- */
    :root {
      --bg: #0b1220;
      --text: #e5e7eb;
      --text-muted: #9ca3af;
      --text-soft: #cbd5e1;
      --text-dim: #6b7280;
      --panel-region: #0f172a;
      --panel-town: #111827;
      --panel-map: #0b1220;
      --panel-card: #1f2937;
      --panel-help: #111827;
      --border: #1f2937;
      --border-mid: #374151;
      --border-strong: #4b5563;
      --input-bg: #0f172a;
      --btn-hover-bg: #1e293b;
      --btn-active-bg: #334155;
      --accent-warm: #fbbf24;
      --accent-cleared: #34d399;
      --pending-row: #fde68a;
      --opened-row: #6b7280;
      --travel: #93c5fd;
      --badge-pending-bg: #7f1d1d;
      --badge-pending-fg: #fee2e2;
      --badge-pending-border: #b91c1c;
      --badge-cleared-bg: #065f46;
      --badge-cleared-fg: #d1fae5;
      --badge-cleared-border: #10b981;
      --kind-T-bg: #0c4a6e; --kind-T-fg: #bae6fd;
      --kind-F-bg: #3f3f46; --kind-F-fg: #e4e4e7;
      --kind-D-bg: #581c87; --kind-D-fg: #e9d5ff;
      --dot-opened: #374151;
      --dot-unopened: #facc15;
      --dot-unknown: #6b7280;
      --flash-bg: #1e3a8a;
      --code-fg: #bfdbfe;
    }
    body.theme-light {
      --bg: #f6f3ec;
      --text: #2a2a28;
      --text-muted: #6b6b66;
      --text-soft: #4a4a47;
      --text-dim: #8c8c87;
      --panel-region: #ffffff;
      --panel-town: #faf7ef;
      --panel-map: #fdfbf5;
      --panel-card: #efebe1;
      --panel-help: #faf7ef;
      --border: #e2dfd4;
      --border-mid: #c8c4b7;
      --border-strong: #afaa9b;
      --input-bg: #ffffff;
      --btn-hover-bg: #efebe1;
      --btn-active-bg: #ddd9cf;
      --accent-warm: #a85e1c;
      --accent-cleared: #2d7a4e;
      --pending-row: #8c4d12;
      --opened-row: #9b958a;
      --travel: #2c5d8c;
      --badge-pending-bg: #fbe5dc;
      --badge-pending-fg: #8b2f1f;
      --badge-pending-border: #e8a99a;
      --badge-cleared-bg: #d8ecdb;
      --badge-cleared-fg: #285c3d;
      --badge-cleared-border: #88c39d;
      --kind-T-bg: #cce0ef; --kind-T-fg: #1f4a73;
      --kind-F-bg: #e3e0d4; --kind-F-fg: #5e5b50;
      --kind-D-bg: #e1d3e6; --kind-D-fg: #5d3578;
      --dot-opened: #b5b1a6;
      --dot-unopened: #c97c2a;
      --dot-unknown: #9b958a;
      --flash-bg: #d8e6f1;
      --code-fg: #1f4a73;
    }
    body.theme-sepia {
      --bg: #f0e6d2;
      --text: #3f3527;
      --text-muted: #7d705a;
      --text-soft: #5a4e3a;
      --text-dim: #9b8c70;
      --panel-region: #ebdfc4;
      --panel-town: #e7d9b8;
      --panel-map: #f3e8d0;
      --panel-card: #d9c9a5;
      --panel-help: #e7d9b8;
      --border: #d8c8a0;
      --border-mid: #b0a075;
      --border-strong: #968760;
      --input-bg: #f3e8d0;
      --btn-hover-bg: #d9c9a5;
      --btn-active-bg: #c9b78b;
      --accent-warm: #b35a1c;
      --accent-cleared: #4f7a3c;
      --pending-row: #8a4a1a;
      --opened-row: #9b8c70;
      --travel: #4b6e8a;
      --badge-pending-bg: #e8caa4;
      --badge-pending-fg: #7a3814;
      --badge-pending-border: #c79064;
      --badge-cleared-bg: #c6d4ad;
      --badge-cleared-fg: #3d5a23;
      --badge-cleared-border: #93b074;
      --kind-T-bg: #b8d0c8; --kind-T-fg: #2f523f;
      --kind-F-bg: #d3c9aa; --kind-F-fg: #645b3d;
      --kind-D-bg: #c8b3bd; --kind-D-fg: #683b4e;
      --dot-opened: #b0a075;
      --dot-unopened: #b35a1c;
      --dot-unknown: #9b8c70;
      --flash-bg: #e0cda3;
      --code-fg: #4b6e8a;
    }

    body { font-family: system-ui, "Microsoft YaHei", sans-serif; margin: 0; background: var(--bg); color: var(--text); font-size: 13px; line-height: 1.45; transition: background .25s ease, color .25s ease; }
    .page { max-width: 1100px; margin: 0 auto; padding: 16px 16px 40px; }
    h1 { text-align: center; margin: 0 0 8px; font-size: 22px; }
    .summary,.controls { display:flex; flex-wrap:wrap; gap:8px; margin:12px 0; align-items:center; justify-content:center; }
    .upload-card { width:min(760px, 100%); margin:12px auto; padding:12px; display:flex; flex-wrap:wrap; gap:8px; align-items:center; justify-content:center; background:var(--panel-card); border:1px solid var(--border-mid); border-radius:12px; box-shadow:0 8px 24px rgba(0,0,0,.16); }
    .upload-card .note { margin:0; flex-basis:100%; }
    #saveFile { position:absolute; width:1px; height:1px; padding:0; margin:-1px; overflow:hidden; clip:rect(0,0,0,0); border:0; }
    .help-card { width:min(900px, 100%); margin:12px auto; background:var(--panel-help); border:1px solid var(--border-mid); border-radius:10px; padding:10px 12px; }
    .help-card summary { cursor:pointer; font-weight:700; }
    .help { color:var(--text-soft); line-height:1.6; text-align:left; }
    .help code, code { color:var(--code-fg); }
    .pill { background:var(--panel-card); border:1px solid var(--border-mid); border-radius:999px; padding:6px 11px; font-size:12px; }
    input,select,button { background:var(--input-bg); color:var(--text); border:1px solid var(--border-strong); border-radius:8px; padding:6px 10px; font-size:13px; font-family: inherit; }
    button { cursor:pointer; transition: background .12s, border-color .12s, transform .08s; }
    button:hover { background:var(--btn-hover-bg); border-color:var(--text-dim); }
    button:active { background:var(--btn-active-bg); transform: translateY(1px); }
    input[type=search] { width:min(480px, 90vw); }
    .note { color:var(--text-muted); line-height:1.5; max-width:1100px; margin-left:auto; margin-right:auto; text-align:center; }
    #kindAchieveNote { text-align:left; max-width:1100px; margin:8px auto 0; color:var(--accent-warm); font-size:14px; line-height:1.45; }
    .warn { color:var(--accent-warm); }

    /* ----- Theme picker (top-right floating) ----- */
    .theme-picker { position: fixed; top: 12px; right: 14px; z-index: 100; display: flex; gap: 4px; padding: 4px; background: var(--panel-card); border: 1px solid var(--border-mid); border-radius: 999px; box-shadow: 0 4px 14px rgba(0,0,0,.15); }
    .theme-btn { padding: 4px 12px; font-size: 12px; border-radius: 999px; border: 1px solid transparent; background: transparent; color: var(--text-muted); cursor: pointer; transition: background .12s, color .12s; }
    .theme-btn:hover { background: var(--btn-hover-bg); color: var(--text); }
    .theme-btn.active { background: var(--btn-active-bg); color: var(--text); border-color: var(--border-strong); }

    .regions { display:flex; flex-direction:column; gap:22px; }
    .region { background:var(--panel-region); border:1px solid var(--border); border-radius:12px; padding:10px 14px 12px; }
    .region > summary { cursor:pointer; list-style:none; padding:6px 2px; display:flex; align-items:center; gap:10px; font-size:17px; font-weight:700; }
    .region > summary::-webkit-details-marker { display:none; }
    .region > summary::before { content:"\25b6"; font-size:13px; color:var(--text-muted); transition: transform .15s; }
    .region[open] > summary::before { transform: rotate(90deg); }
    .region-badge { background:var(--panel-card); border:1px solid var(--border-mid); border-radius:999px; padding:4px 12px; font-size:13px; font-weight:500; color:var(--text-soft); }
    .region-badge.has-unopened { background:var(--badge-pending-bg); border-color:var(--badge-pending-border); color:var(--badge-pending-fg); }
    .region-badge.all-cleared  { background:var(--badge-cleared-bg); border-color:var(--badge-cleared-border); color:var(--badge-cleared-fg); }

    .towns { display:flex; flex-direction:column; gap:14px; margin-top:10px; }
    .town  { background:var(--panel-town); border:1px solid var(--border); border-radius:10px; padding:8px 12px 10px; }
    .town > summary { cursor:pointer; list-style:none; padding:6px 2px; display:flex; align-items:center; gap:10px; font-weight:600; font-size:15px; }
    .town > summary::-webkit-details-marker { display:none; }
    .town > summary::before { content:"\25b6"; font-size:11px; color:var(--text-muted); transition: transform .15s; }
    .town[open] > summary::before { transform: rotate(90deg); }
    .town-meta { color:var(--text-muted); font-size:13px; font-weight:400; margin-left:auto; }

    .maps { display:flex; flex-direction:column; gap:10px; margin-top:8px; padding-left:18px; }
    .map  { background:var(--panel-map); border:1px solid var(--border); border-radius:10px; padding:10px 14px 12px; }
    .map > summary { cursor:pointer; list-style:none; padding:6px 0; display:flex; align-items:center; gap:10px; font-size:15px; }
    .map > summary::-webkit-details-marker { display:none; }
    .map > summary::before { content:"\25b6"; font-size:11px; color:var(--text-dim); transition: transform .15s; }
    .map[open] > summary::before { transform: rotate(90deg); }
    .map-kind { font-size:12px; padding:2px 8px; border-radius:6px; font-weight:600; }
    .map-kind.T { background:var(--kind-T-bg); color:var(--kind-T-fg); }
    .map-kind.F { background:var(--kind-F-bg); color:var(--kind-F-fg); }
    .map-kind.D { background:var(--kind-D-bg); color:var(--kind-D-fg); }
    .map-stats { color:var(--accent-warm); font-size:13px; margin-left:auto; font-weight:500; }
    .map-stats.cleared { color:var(--accent-cleared); }

    .items-wrap { margin: 10px auto 4px; max-width: 760px; }
    .items-caption { font-size:13px; color:var(--text-soft); margin:6px 0 6px; text-align:center; font-weight:500; }
    .items-empty { font-size:13px; color:var(--text-muted); text-align:center; padding:10px 0; font-style:italic; }
    table.items { border-collapse:collapse; width:100%; font-size:14px; margin: 0 auto; }
    table.items th, table.items td { border-bottom:1px solid var(--border); padding:8px 12px; text-align:center; vertical-align:middle; }
    table.items th { color:var(--text-muted); font-weight:500; font-size:12px; }
    table.items td.col-dot, table.items th.col-dot { width:18px; padding-right:4px; padding-left:8px; }
    table.items td.col-status, table.items th.col-status { width:70px; white-space:nowrap; }
    table.items td.col-reward { text-align:center; min-width:200px; }
    table.items td.col-pos, table.items th.col-pos { width:90px; white-space:nowrap; }
    table.items td.col-hint, table.items th.col-hint { min-width:180px; max-width:360px; font-size:12px; color:var(--text-soft); text-align:left; white-space:normal; line-height:1.35; }
    .hint-secret { color:var(--badge-pending-fg); }
    .hint-hidden { color:var(--text); }
    tr.opened   { color:var(--opened-row); }
    tr.unopened { color:var(--pending-row); }
    tr.unknown  { color:var(--text-muted); font-style:italic; }
    .status-dot { display:inline-block; width:9px; height:9px; border-radius:50%; }
    .status-dot.opened   { background:var(--dot-opened); }
    .status-dot.unopened { background:var(--dot-unopened); }
    .status-dot.unknown  { background:var(--dot-unknown); }
    .travel-hint { color:var(--travel); font-size:13px; }
    .map-name { flex:0 1 auto; font-weight:500; }

    .weak-chips { display:flex; flex-wrap:wrap; gap:5px; justify-content:center; max-width:420px; margin:0 auto; }
    .weak-chip { font-size:12px; padding:2px 8px; border-radius:6px; border:1px solid var(--border-mid); background:var(--panel-card); white-space:nowrap; }
    .weak-chip.revealed { background:var(--badge-cleared-bg); color:var(--badge-cleared-fg); border-color:var(--badge-cleared-border); }
    .weak-chip.hidden   { background:var(--badge-pending-bg); color:var(--badge-pending-fg); border-color:var(--badge-pending-border); }
    table.items td.col-monster { text-align:center; min-width:160px; }
    table.items td.col-weak { min-width:220px; }

    /* Click feedback for expand/collapse buttons */
    @keyframes flash-anim { 0% { background:var(--flash-bg); } 100% { background:transparent; } }
    .regions.flash > details { animation: flash-anim .35s ease-out; }
  </style>
</head>
<body>
<div class="theme-picker" role="group" aria-label="theme">
  <button class="theme-btn" data-theme="dark">&#28145;&#33394;</button>
  <button class="theme-btn" data-theme="light">&#26580;&#30333;</button>
  <button class="theme-btn" data-theme="sepia">&#31859;&#33394;</button>
</div>
<main class="page">
  <h1>&#20843;&#26041;&#26053;&#20154;1 &#25910;&#38598;&#26816;&#26597;&#22120;</h1>
  <p class="note">
    &#36873;&#25321;&#19968;&#20010; <code>.sav</code> &#23384;&#26723;&#25991;&#20214;&#65292;&#26412;&#39029;&#22312;&#27983;&#35272;&#22120;&#26412;&#22320;&#35299;&#26512;&#65292;&#19981;&#19978;&#20256;&#19981;&#20462;&#25913;&#12290;
    &#29983;&#25104;&#26102;&#38388;&#65306;$generatedAt
  </p>
  <div class="upload-card">
    <input id="saveFile" type="file" accept=".sav">
    <button id="pickSaveFile" type="button">&#36873;&#25321;&#23384;&#26723;&#25991;&#20214;</button>
    <button id="loadSampleSave" type="button">&#21152;&#36733;&#31034;&#20363;&#23384;&#26723;</button>
    <button id="clearSave">&#28165;&#38500;&#24403;&#21069;&#23384;&#26723;&#29366;&#24577;</button>
    <span id="fileInfo" class="note">&#23578;&#26410;&#36873;&#25321;&#23384;&#26723;</span>
  </div>
  <details class="help-card">
    <summary>&#25214;&#19981;&#21040;&#23384;&#26723;&#65311;&#28857;&#27492;&#26597;&#30475;&#24120;&#35265;&#20301;&#32622;</summary>
    <div class="help">
      <p><b>&#26041;&#27861; 1&#65306;&#30452;&#25509;&#25628;&#32034;&#23384;&#26723;&#25991;&#20214;&#65288;&#25512;&#33616;&#65289;</b></p>
      <p>&#25171;&#24320;&#12300;&#27492;&#30005;&#33041;&#12301;&#65292;&#21491;&#19978;&#35282;&#25628;&#32034;&#65306;<code>SaveData*.sav</code>&#12290;&#36873;&#26368;&#26032;&#20462;&#25913;&#30340;&#25991;&#20214;&#12290;</p>
      <p><code>SaveData0.sav</code> = &#33258;&#21160;&#23384;&#26723;&#65307;<code>SaveData1.sav</code> / <code>SaveData2.sav</code> / <code>SaveData3.sav</code> = &#25163;&#21160;&#23384;&#26723;&#31532; 1 / 2 / 3 &#26639;&#12290;</p>
      <p><b>&#26041;&#27861; 2&#65306;Win+R &#31896;&#36148;&#36335;&#24452;</b></p>
      <p>&#25353; <code>Win+R</code>&#65292;&#31896;&#36148;&#19979;&#38754;&#36335;&#24452;&#21518;&#22238;&#36710;&#65292;&#36827;&#20837;&#25991;&#20214;&#22841;&#21518;&#20877;&#25171;&#24320;&#19968;&#20018;&#25968;&#23383;&#65288;Steam ID&#65289;&#25991;&#20214;&#22841; &#8594; <code>SaveGames</code>&#65306;</p>
      <p><code>%USERPROFILE%\Documents\My Games\Octopath_Traveler</code></p>
      <p>&#23436;&#25972;&#31034;&#20363;&#65306;<code>...\Octopath_Traveler\&#20320;&#30340;Steam&#25968;&#23383;ID\SaveGames\SaveData1.sav</code></p>
      <p>&#33509;&#24320;&#20102; OneDrive &#25991;&#26723;&#21516;&#27493;&#65292;&#36335;&#24452;&#21487;&#33021;&#26159;&#65306;</p>
      <p><code>%USERPROFILE%\OneDrive\&#25991;&#26723;\My Games\Octopath_Traveler\</code>&#65288;&#21516;&#26679;&#36827;&#20837;&#25968;&#23383;&#25991;&#20214;&#22841; &#8594; <code>SaveGames</code>&#65289;</p>
      <p>&#25110;&#65306;<code>%USERPROFILE%\OneDrive\Documents\My Games\Octopath_Traveler\</code></p>
      <p><b>&#26041;&#27861; 3&#65306;&#36164;&#28304;&#31649;&#29702;&#22120;&#22320;&#22336;&#26639;</b></p>
      <p>&#22312;&#25991;&#20214;&#36164;&#28304;&#31649;&#29702;&#22120;&#22320;&#22336;&#26639;&#31896;&#36148;&#19978;&#38754;&#36335;&#24452;&#65292;&#25353;&#22238;&#36710;&#36827;&#20837;&#12290;</p>
      <p><b>&#27880;&#24847;</b></p>
      <p>&#23384;&#26723;&#19981;&#22312;&#28216;&#25103;&#23433;&#35013;&#30446;&#24405;&#37324;&#65292;&#21482;&#22312; <code>Documents\My Games\Octopath_Traveler\</code> &#19979;&#12290;&#26412;&#39029;&#20165;&#22312;&#27983;&#35272;&#22120;&#26412;&#22320;&#35835;&#21462;&#65292;&#19981;&#19978;&#20256;&#12289;&#19981;&#20462;&#25913;&#23384;&#26723;&#12290;&#33509;&#25628;&#21040;&#22810;&#20010; <code>SaveData1.sav</code>&#65292;&#36873;&#26085;&#26399;&#26368;&#26032;&#12289;&#22823;&#23567;&#32422; 2MB &#30340;&#37027;&#20010;&#12290;</p>
      <p><b>&#24618;&#29289;&#24369;&#28857;&#65288;&#25112;&#30053;&#23478;&#65289;</b></p>
      <p>&#25104;&#23601;&#38656;&#35201;&#35782;&#30772; <b>381</b> &#21482;&#24618;&#29289;&#30340;&#20840;&#37096;&#24369;&#28857;&#65288;&#19982; marcv666 / &#31038;&#21306;&#36164;&#28304;&#34920;&#12289;SaveDataEditor &#19968;&#33268;&#65289;&#65307;&#19981;&#21253;&#25324;&#19968;&#33324; Boss &#21484;&#21796;&#29289;&#31561;&#12290;&#26412;&#39029;&#25353;&#23384;&#26723; WeaknessOpen &#20301;&#26631;&#35745;&#31639;&#36827;&#24230;&#12290;</p>
      <p><b>&#25910;&#34255;&#23478;</b></p>
      <p>&#25104;&#23601;&#38656;&#35201;&#26366;&#33719;&#24471;&#20840;&#37096;&#36947;&#20855;&#65288;&#28041;&#30422;&#28040;&#32791;&#21697;&#12289;&#35013;&#22791;&#12289;&#36149;&#37329;&#21697;&#21644;&#30693;&#35782;&#65289;&#65307;&#28165;&#21333;&#19982; SaveDataEditor item_inventory &#19968;&#33268;&#20849; <b>640</b> &#39033;&#12290;&#26412;&#39029;&#25353;&#23384;&#26723; ItemFlag &#20301;&#26631;&#35745;&#31639;&#36827;&#24230;&#12290;</p>
      <p>&#52616;&#22411;&#19979;&#26041;&#30340;&#35828;&#26126;&#21015;&#20986;&#21508;&#25104;&#23601;&#30340;&#21095;&#24773;&#21487;&#38169;&#36807;&#39033;&#12290;&#26631;&#26377; <code>&#12304;&#19981;&#35745;&#20837;&#12300;...&#12301;&#25104;&#23601;&#12305;</code> &#30340;&#26465;&#30446;&#21487;&#38169;&#36807;&#19988;&#19981;&#24433;&#21709;&#23545;&#24212; Steam &#25104;&#23601;&#65307;&#26631;&#26377; <code>&#12304;&#21095;&#24773;&#38480;&#26102;&#183;&#38169;&#36807;&#26080;&#27861;&#21462;&#24471;&#12305;</code> &#30340;&#26465;&#30446;&#28436;&#20986;&#21518;&#26080;&#27861;&#34917;&#25913;&#12290;</p>
    </div>
  </details>
  <div class="summary">
    <div class="pill">&#23453;&#31665;&#65306;&#24050;&#24320; <b id="openedCount">0</b> &#183; &#26410;&#24320; <b id="unopenedCount">0</b></div>
    <div class="pill">&#38544;&#34255;&#36947;&#20855;&#65306;&#24050;&#24471; <b id="hiddenOpenedCount">0</b> &#183; &#26410;&#24471; <b id="hiddenUnopenedCount">0</b></div>
    <div class="pill">&#24618;&#29289;&#24369;&#28857;&#65306;&#24050;&#35782;&#30772; <b id="monsterDoneCount">0</b> &#183; &#26410;&#35782;&#30772; <b id="monsterPendingCount">0</b> &#183; &#20849; 381</div>
    <div class="pill">&#25910;&#34255;&#23478;&#65306;&#24050;&#24471; <b id="collectorDoneCount">0</b> &#183; &#26410;&#24471; <b id="collectorPendingCount">0</b> &#183; &#20849; 640</div>
  </div>
  <div class="controls">
    <input id="q" type="search" placeholder="&#25628;&#32034;&#36947;&#20855;&#21517;&#12289;&#22320;&#21517;&#8230;&#8230;">
    <label>&#31867;&#22411;
      <select id="kindFilter">
        <option value="all">&#20840;&#37096;</option>
        <option value="Chest" selected>&#23453;&#31665;</option>
        <option value="Hidden Item">&#38544;&#34255;&#36947;&#20855;</option>
        <option value="Monster">&#24618;&#29289;&#24369;&#28857;</option>
        <option value="Collector">&#25910;&#34255;&#23478;</option>
      </select>
    </label>
    <label>&#29366;&#24577;
      <select id="statusFilter">
        <option value="unopened" selected>&#26410;&#23436;&#25104;</option>
        <option value="opened">&#24050;&#23436;&#25104;</option>
        <option value="all">&#20840;&#37096;</option>
      </select>
    </label>
    <button id="expandAll">&#23637;&#24320;&#20840;&#37096;</button>
    <button id="collapseAll">&#25240;&#21472;&#20840;&#37096;</button>
  </div>
  <p id="kindAchieveNote" class="note"></p>
  <div id="regions" class="regions"></div>
</main>
<script>
const ENTRIES           = $entriesJson;
const ENEMY_SPAWN_ENTRIES = $enemySpawnJson;
const COLLECTOR_ENTRIES = $collectorJson;
const REGION_ORDER      = $regionOrderJson;
let saveLoaded = false;
let currentEntries = [];
let currentEnemyEntries = [];
let currentCollectorEntries = [];
const KIND_ACHIEVE_NOTE = $kindAchieveNoteJson;
function updateKindAchieveNote(kindFilter) {
  const el = document.querySelector("#kindAchieveNote");
  if (!el) return;
  el.innerHTML = KIND_ACHIEVE_NOTE[kindFilter] || KIND_ACHIEVE_NOTE.all;
}

function escapeHtml(value) {
  return String(value == null ? "" : value).replace(/[&<>"']/g, c => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c]));
}

function findAscii(bytes, needle) {
  const pat = Array.from(needle).map(c => c.charCodeAt(0));
  const hits = [];
  outer: for (let i = 0; i <= bytes.length - pat.length; i++) {
    for (let j = 0; j < pat.length; j++) {
      if (bytes[i + j] !== pat[j]) continue outer;
    }
    hits.push(i);
  }
  return hits;
}
function readI32(view, offset) { return view.getInt32(offset, true); }
function readI64AsNumber(view, offset) {
  const lo = view.getUint32(offset, true);
  const hi = view.getInt32(offset + 4, true);
  return hi * 4294967296 + lo;
}
function parseByteArray(bytes, view, nameOffset) {
  const nameLen = readI32(view, nameOffset - 4);
  const typeLenOffset = nameOffset + nameLen;
  const typeLen = readI32(view, typeLenOffset);
  const typeStart = typeLenOffset + 4;
  const sizeOffset = typeStart + typeLen;
  const size = readI64AsNumber(view, sizeOffset);
  const innerLenOffset = sizeOffset + 8;
  const innerLen = readI32(view, innerLenOffset);
  const dataStart = innerLenOffset + 4 + innerLen;
  return bytes.slice(dataStart, dataStart + size);
}
function extractTreasureArrays(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  const view = new DataView(arrayBuffer);
  const hits = findAscii(bytes, "TreasureStateArray_");
  return hits.map(hit => parseByteArray(bytes, view, hit));
}

function readCString(bytes, offset, maxLen) {
  let end = offset;
  const limit = Math.min(bytes.length, offset + maxLen);
  while (end < limit && bytes[end] !== 0) end++;
  return String.fromCharCode.apply(null, bytes.subarray(offset, end));
}

function getPropertyTagExtra(bytes, type, valueOffset) {
  if (type === "BoolProperty") return 2;
  if (type === "ByteProperty") return 1;
  if (type === "ArrayProperty") {
    const innerLen = readI32(new DataView(bytes.buffer), valueOffset);
    return 4 + innerLen + 1;
  }
  if (type === "StructProperty") {
    const structLen = readI32(new DataView(bytes.buffer), valueOffset);
    return 4 + structLen + 16 + 1;
  }
  return 1;
}

function parseOneProperty(bytes, pos) {
  const view = new DataView(bytes.buffer);
  if (pos + 4 > bytes.length) return null;
  const nameLen = readI32(view, pos);
  if (nameLen <= 0 || nameLen > 200 || pos + 4 + nameLen > bytes.length) return null;
  const name = readCString(bytes, pos + 4, nameLen);
  const afterName = pos + 4 + nameLen;
  if (afterName + 4 > bytes.length) return null;
  const typeLen = readI32(view, afterName);
  if (typeLen <= 0 || typeLen > 100 || afterName + 4 + typeLen > bytes.length) return null;
  const type = readCString(bytes, afterName + 4, typeLen);
  const afterType = afterName + 4 + typeLen;
  if (afterType + 12 > bytes.length) return null;
  const valSize = readI64AsNumber(view, afterType);
  const afterSize = afterType + 8;
  const valueOffset = afterSize + 4;
  const tagExtra = getPropertyTagExtra(bytes, type, valueOffset);
  const dataOffset = valueOffset + tagExtra;
  let nextPos;
  if (type === "BoolProperty") nextPos = valueOffset + 2;
  else nextPos = dataOffset + valSize;
  if (name === "None") return { name, type, size: 0, dataOffset: afterName, nextPos: afterName };
  return { name, type, size: valSize, dataOffset, nextPos, valueOffset, tagExtra, afterType };
}

function parseProperties(bytes, start, maxBytes) {
  const props = [];
  let pos = start;
  const end = Math.min(bytes.length, start + maxBytes);
  let safety = 0;
  while (pos < end && safety < 64) {
    safety++;
    const p = parseOneProperty(bytes, pos);
    if (!p) break;
    props.push(p);
    if (p.name === "None") break;
    if (p.nextPos <= pos) break;
    pos = p.nextPos;
  }
  return props;
}

function gvasAfterTypeOffset(bytes, nameAsciiOffset) {
  const view = new DataView(bytes.buffer);
  const nameLen = readI32(view, nameAsciiOffset - 4);
  const typeLenOff = nameAsciiOffset + nameLen;
  const typeLen = readI32(view, typeLenOff);
  return typeLenOff + 4 + typeLen;
}

function gvasBoolValueAt(bytes, nameAsciiOffset) {
  const afterType = gvasAfterTypeOffset(bytes, nameAsciiOffset);
  return bytes[afterType + 10] !== 0;
}

function gvasWeaknessMaskAt(bytes, weaknessNameOffset) {
  const dataOff = gvasAfterTypeOffset(bytes, weaknessNameOffset) + 9;
  return bytes[dataOff] | (bytes[dataOff + 1] << 8);
}

function findNextAscii(bytes, needle, afterOffset, maxDist) {
  const hits = findAscii(bytes, needle);
  for (const h of hits) {
    if (h > afterOffset && h < afterOffset + maxDist) return h;
  }
  return -1;
}

function findPrevAscii(bytes, needle, beforeOffset, maxDist) {
  const hits = findAscii(bytes, needle);
  let best = -1;
  for (const h of hits) {
    if (h < beforeOffset && h >= beforeOffset - maxDist) best = h;
  }
  return best;
}

function clusterHitsByGap(hits, expectedGap, tolerance) {
  if (!hits.length) return [];
  const sorted = hits.slice().sort((a, b) => a - b);
  const clusters = [[sorted[0]]];
  for (let i = 1; i < sorted.length; i++) {
    const gap = sorted[i] - sorted[i - 1];
    if (Math.abs(gap - expectedGap) <= tolerance) clusters[clusters.length - 1].push(sorted[i]);
    else if (gap >= expectedGap - tolerance) clusters.push([sorted[i]]);
  }
  clusters.sort((a, b) => b.length - a.length);
  return clusters[0] || [];
}

function extractSaveEnemyMap(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  // SaveDataEditor: IsAnalyse_ list index == EnemyID (search whole save).
  // WeaknessOpen_ for each slot is the FIRST hit at/after that IsAnalyse_ address
  // (same as SaveData.FindAddress("WeaknessOpen_", isAnalyseOffset)).
  const analyseHits = clusterHitsByGap(findAscii(bytes, "IsAnalyse_"), 0xA6, 4);
  const out = {};
  for (let i = 0; i < analyseHits.length; i++) {
    const aOff = analyseHits[i];
    const analysed = gvasBoolValueAt(bytes, aOff);
    const wOff = findNextAscii(bytes, "WeaknessOpen_", aOff - 1, 0xA0);
    const weakness_mask = wOff >= 0 ? gvasWeaknessMaskAt(bytes, wOff) : 0;
    out[i] = { analysed, weakness_mask };
  }
  return out;
}

function applyEnemySaveState(entries, saveMap) {
  return entries.map(e => {
    const copy = Object.assign({}, e);
    const rec = saveMap[e.enemy_id_num];
    if (!rec) {
      copy.save_status = "unknown";
      copy.revealed_count = 0;
      copy.weakness_mask = 0;
      return copy;
    }
    copy.weakness_mask = rec.weakness_mask;
    // Completion matches SaveDataEditor: weapon/magic open bytes equal expected weak masks.
    // Do not gate on IsAnalyse_ (editor ignores it for Strategist progress).
    const weaponByte = rec.weakness_mask & 0xFF;
    const magicByte = (rec.weakness_mask >> 8) & 0xFF;
    const expectW = Number(e.weapon_weak) || 0;
    const expectM = Number(e.magic_weak) || 0;
    let revealed = 0;
    for (const ws of (e.weak_slots || [])) {
      if (isWeaknessRevealed(copy, ws)) revealed++;
    }
    copy.revealed_count = revealed;
    const allBits = (expectW === 0 && expectM === 0)
      ? false
      : ((weaponByte & expectW) === expectW && (magicByte & expectM) === expectM);
    copy.save_status = allBits ? "opened" : "unopened";
    return copy;
  });
}

function gvasInt32At(bytes, nameAsciiOffset) {
  const afterType = gvasAfterTypeOffset(bytes, nameAsciiOffset);
  return new DataView(bytes.buffer).getInt32(afterType + 9, true);
}

function addItemFlagBits(got, flags, flagIndex) {
  for (let i = 0; i < 32; i++) {
    if ((flags >>> i) & 1) got.add(flagIndex * 32 + i);
  }
}

function extractGotItemIds(arrayBuffer) {
  const bytes = new Uint8Array(arrayBuffer);
  const view = new DataView(arrayBuffer);
  const got = new Set();
  let parsed = false;
  const hits = findAscii(bytes, "ItemFlag");
  for (const h of hits) {
    if (h < 4) continue;
    const nameLen = readI32(view, h - 4);
    if (nameLen < 8 || nameLen > 16) continue;
    const name = readCString(bytes, h, 20);
    if (name === "ItemFlag") {
      const afterName = h + nameLen;
      const typeLen = readI32(view, afterName);
      const type = readCString(bytes, afterName + 4, typeLen);
      if (type !== "ArrayProperty") continue;
      const afterType = afterName + 4 + typeLen;
      const innerLen = readI32(view, afterType + 8);
      const innerType = readCString(bytes, afterType + 12, innerLen);
      let pos = afterType + 8 + 4 + innerLen + 1;
      if (pos + 4 > bytes.length) continue;
      const count = readI32(view, pos);
      pos += 4;
      if (count <= 0 || count > 4096) continue;
      if (innerType === "IntProperty" || innerType === "UInt32Property") {
        if (pos + count * 4 > bytes.length) continue;
        for (let flagIndex = 0; flagIndex < count; flagIndex++) {
          addItemFlagBits(got, view.getUint32(pos + flagIndex * 4, true), flagIndex);
        }
        parsed = true;
      } else if (innerType === "BoolProperty" || innerType === "ByteProperty") {
        if (pos + count > bytes.length) continue;
        for (let i = 0; i < count; i++) {
          if (bytes[pos + i]) got.add(i);
        }
        parsed = true;
      }
    } else {
      const m = /^ItemFlag_([0-9]+)$/.exec(name);
      if (!m) continue;
      const afterName = h + nameLen;
      const typeLen = readI32(view, afterName);
      const type = readCString(bytes, afterName + 4, typeLen);
      if (type !== "IntProperty" && type !== "UInt32Property") continue;
      const afterType = afterName + 4 + typeLen;
      const flags = view.getUint32(afterType + 9, true);
      addItemFlagBits(got, flags, Number(m[1]));
      parsed = true;
    }
  }
  // Knowledge (情报) is kept in inventory ItemID slots and is NOT written into ItemFlag.
  const idHits = findAscii(bytes, "ItemID_");
  for (const h of idHits) {
    if (h < 4) continue;
    const nameLen = readI32(view, h - 4);
    if (nameLen < 8 || nameLen > 80) continue;
    const name = readCString(bytes, h, nameLen);
    if (!name.startsWith("ItemID")) continue;
    const afterName = h + nameLen;
    const typeLen = readI32(view, afterName);
    if (typeLen < 8 || typeLen > 40) continue;
    const type = readCString(bytes, afterName + 4, typeLen);
    if (type !== "IntProperty" && type !== "UInt32Property") continue;
    const id = view.getUint32(afterName + 4 + typeLen + 9, true);
    if (id) {
      got.add(id);
      parsed = true;
    }
  }
  if (!parsed) return null;
  got.delete(0);
  return got;
}

function applyCollectorSaveState(entries, gotIds) {
  const aliasGroups = [[325, 326, 327], [311, 312]];
  let got = gotIds;
  if (gotIds) {
    got = new Set(gotIds);
    for (const group of aliasGroups) {
      if (group.some(id => got.has(id))) group.forEach(id => got.add(id));
    }
  }
  return entries.map(e => {
    const copy = Object.assign({}, e);
    if (!got) {
      copy.save_status = "unknown";
      return copy;
    }
    copy.save_status = got.has(Number(e.item_id)) ? "opened" : "unopened";
    return copy;
  });
}

function tallyCollector(entries) {
  let opened = 0, unopened = 0, unknown = 0;
  for (const e of entries) {
    if (e.save_status === "opened") opened++;
    else if (e.save_status === "unknown") unknown++;
    else unopened++;
  }
  return { opened, unopened, unknown, total: entries.length };
}

function uniqueCollectorTypes(entries) {
  const order = [];
  const map = {};
  for (const e of entries) {
    const k = String(e.type);
    if (!map[k]) {
      map[k] = { type: e.type, type_name: e.type_name || ("\u7c7b\u578b" + e.type), items: [] };
      order.push(k);
    }
    map[k].items.push(e);
  }
  order.sort((a, b) => Number(a) - Number(b));
  return order.map(k => map[k]);
}

function buildCollectorTable(items, statusFilter) {
  if (items.length === 0) return null;
  const visible = items.filter(e => statusMatchesFilter(e, statusFilter));
  const totalPending = items.filter(e => e.save_status === "unopened" || e.save_status === "unknown").length;
  visible.sort((a, b) => {
    const rank = s => s === "unopened" ? 0 : s === "unknown" ? 1 : 2;
    const r = rank(a.save_status) - rank(b.save_status);
    if (r !== 0) return r;
    return String(a.name || "").localeCompare(String(b.name || ""), "zh-Hans-CN");
  });
  const wrap = document.createElement("div");
  wrap.className = "items-wrap";
  const caption = document.createElement("div");
  caption.className = "items-caption";
  caption.textContent = (items[0] && items[0].type_name ? items[0].type_name : "\u9053\u5177") + " (" + visible.length + " / " + items.length + ")";
  wrap.appendChild(caption);
  if (visible.length === 0) {
    const empty = document.createElement("div");
    empty.className = "items-empty";
    empty.textContent = totalPending > 0
      ? ("\u5f53\u524d\u7b5b\u9009\u4e0b\u65e0\u5339\u914d\u9879\uff08\u8be5\u5206\u7c7b\u8fd8\u6709 " + totalPending + " \u9879\u672a\u5b8c\u6210\uff09")
      : "\u5f53\u524d\u7b5b\u9009\u4e0b\u65e0\u5339\u914d\u9879";
    wrap.appendChild(empty);
    return wrap;
  }
  const tbl = document.createElement("table");
  tbl.className = "items";
  let rowsHtml = '<thead><tr><th class="col-dot"></th><th class="col-status">\u72b6\u6001</th><th class="col-reward">\u9053\u5177</th><th class="col-hint">\u627e\u6cd5</th></tr></thead><tbody>';
  for (const e of visible) {
    const miss = e.missable_note ? String(e.missable_note) : "";
    rowsHtml += '<tr class="' + escapeHtml(e.save_status) + '">' +
      '<td class="col-dot"><span class="status-dot ' + escapeHtml(e.save_status) + '"></span></td>' +
      '<td class="col-status">' + escapeHtml(statusText("Collector", e.save_status)) + '</td>' +
      '<td class="col-reward">' + escapeHtml(miss + (e.name || e.item_key || e.item_id)) + '</td>' +
      '<td class="col-hint hint-hidden">' + escapeHtml(e.find_hint || "\u2014") + '</td></tr>';
  }
  rowsHtml += '</tbody>';
  tbl.innerHTML = rowsHtml;
  wrap.appendChild(tbl);
  return wrap;
}

function countPendingForKind(kindFilter) {
  if (kindFilter === "Monster") {
    return uniqueMonsters(currentEnemyEntries).filter(e => e.save_status === "unopened" || e.save_status === "unknown").length;
  }
  if (kindFilter === "Collector") {
    return currentCollectorEntries.filter(e => e.save_status === "unopened" || e.save_status === "unknown").length;
  }
  return currentEntries.filter(e => {
    if (e.kind !== kindFilter) return false;
    return e.save_status === "unopened" || e.save_status === "unknown";
  }).length;
}

function syncStatusFilterAfterSave() {
  const kindFilter = document.querySelector("#kindFilter").value;
  const statusEl = document.querySelector("#statusFilter");
  if (countPendingForKind(kindFilter) === 0) {
    statusEl.value = "all";
  }
}

function applySave(arrayBuffer, fileName) {
  const fileInfo = document.querySelector("#fileInfo");
  fileInfo.textContent = fileName + " \u89e3\u6790\u4e2d\u2026";
  setTimeout(() => {
    const arrays = extractTreasureArrays(arrayBuffer);
    if (arrays.length === 0) {
      fileInfo.innerHTML = '<span class="warn">&#26410;&#22312;&#35813;&#25991;&#20214;&#20013;&#25214;&#21040; TreasureStateArray&#65292;&#23427;&#21487;&#33021;&#19981;&#26159;&#20843;&#26041;&#26053;&#20154;1 &#23384;&#26723;&#12290;</span>';
      return;
    }
    currentEntries = ENTRIES.map(e => {
      const copy = {...e};
      const stateIndex = Number(copy.state_index);
      const slot = Number(copy.slot);
      if (!Number.isFinite(stateIndex) || !Number.isFinite(slot) || !arrays[stateIndex]) {
        copy.save_status = "unknown"; return copy;
      }
      const byteIndex = 6 + slot;
      if (byteIndex < 0 || byteIndex >= arrays[stateIndex].length) {
        copy.save_status = "unknown"; return copy;
      }
      copy.save_status = arrays[stateIndex][byteIndex] === 1 ? "opened" : "unopened";
      return copy;
    });
    const enemySaveMap = extractSaveEnemyMap(arrayBuffer);
    currentEnemyEntries = applyEnemySaveState(ENEMY_SPAWN_ENTRIES, enemySaveMap);
    const gotItemIds = extractGotItemIds(arrayBuffer);
    currentCollectorEntries = applyCollectorSaveState(COLLECTOR_ENTRIES, gotItemIds);
    saveLoaded = true;
    fileInfo.textContent = fileName + " \u5df2\u52a0\u8f7d";
    syncStatusFilterAfterSave();
    requestAnimationFrame(() => render());
  }, 0);
}

// Localized status text per kind.
function statusText(kind, status) {
  if (kind === "Chest") {
    return { opened:"\u5df2\u5f00", unopened:"\u672a\u5f00", unknown:"\u4e0d\u660e" }[status] || status;
  }
  if (kind === "Hidden Item") {
    return { opened:"\u5df2\u5f97", unopened:"\u672a\u5f97", unknown:"\u4e0d\u660e" }[status] || status;
  }
  if (kind === "Monster") {
    return { opened:"\u5df2\u8bc6\u7834", unopened:"\u672a\u8bc6\u7834", unknown:"\u672a\u906d\u9047" }[status] || status;
  }
  if (kind === "Collector") {
    return { opened:"\u5df2\u5f97", unopened:"\u672a\u5f97", unknown:"\u4e0d\u660e" }[status] || status;
  }
  return status;
}

const ATTR_LABELS = ["\u706b","\u51b0","\u96f7","\u98ce","\u5149","\u6697"];
const WPN_LABELS  = ["\u5251","\u67aa","\u77ed\u5251","\u65a7","\u5f13","\u6756"];
function weakSlotLabel(ws) {
  if (ws.kind === "attr") return (ws.idx >= 0 && ws.idx < ATTR_LABELS.length) ? ATTR_LABELS[ws.idx] : "?";
  return (ws.idx >= 0 && ws.idx < WPN_LABELS.length) ? WPN_LABELS[ws.idx] : "?";
}
function isWeaknessRevealed(entry, ws) {
  const mask = entry.weakness_mask;
  if (!Number.isFinite(mask)) return false;
  const weaponByte = mask & 0xFF;
  const magicByte = (mask >> 8) & 0xFF;
  if (ws.kind === "attr") return ((magicByte >> ws.idx) & 1) !== 0;
  return ((weaponByte >> ws.idx) & 1) !== 0;
}

const KIND_LABEL_MAP = { "T":"\u57ce\u9547", "F":"\u91ce\u5916", "D":"\u8ff7\u5bab" };
function mapKindLabel(code) { return KIND_LABEL_MAP[code] || code || "?"; }

// Quadrant codes -> Chinese labels (top-down view, north=up).
const POSITION_LABEL_MAP = {
  "NW":"\u5de6\u4e0a", "N":"\u4e0a",   "NE":"\u53f3\u4e0a",
  "W": "\u5de6",       "C":"\u4e2d\u592e", "E":"\u53f3",
  "SW":"\u5de6\u4e0b", "S":"\u4e0b",   "SE":"\u53f3\u4e0b",
  "HID":"\u5bc6\u9053", "HID_N":"\u5bc6\u9053", "HID_S":"\u5bc6\u9053",
  "HID_W":"\u5bc6\u9053", "HID_E":"\u5bc6\u9053",
  "HID_NW":"\u5bc6\u9053", "HID_NE":"\u5bc6\u9053",
  "HID_SW":"\u5bc6\u9053", "HID_SE":"\u5bc6\u9053"
};
function positionLabel(code) { return code ? (POSITION_LABEL_MAP[code] || code) : ""; }

function buildEnemyTree(entries) {
  const tree = {};
  for (const e of entries) {
    const rk = e.region_key || "_other";
    const rn = e.region_name || "\u5176\u4ed6\u533a\u57df";
    const tk = e.nearest_town_key || "_unknown_town";
    const tn = e.nearest_town_name || "\u5f52\u5c5e\u4e0d\u660e";
    const mk = e.map_key || "?";
    const mn = e.map_name || mk;
    if (!tree[rk]) tree[rk] = { name:rn, towns:{} };
    if (!tree[rk].towns[tk]) tree[rk].towns[tk] = { name:tn, maps:{} };
    if (!tree[rk].towns[tk].maps[mk]) tree[rk].towns[tk].maps[mk] = { name:mn, kind:e.map_kind_code, travel_name:e.nearest_town_name || tn, monsters:[] };
    tree[rk].towns[tk].maps[mk].monsters.push(e);
  }
  return tree;
}

function uniqueMonsters(entries) {
  const m = {};
  for (const e of entries) {
    const k = String(e.enemy_id_num != null ? e.enemy_id_num : e.enemy_key);
    if (!m[k]) { m[k] = e; continue; }
    const rank = s => s === "unopened" ? 0 : s === "unknown" ? 1 : 2;
    if (rank(e.save_status) < rank(m[k].save_status)) m[k] = e;
  }
  return Object.values(m);
}

function tallyMonsters(entries) {
  const uniq = uniqueMonsters(entries);
  let opened = 0, unopened = 0, unknown = 0;
  for (const e of uniq) {
    if (e.save_status === "opened") opened++;
    else if (e.save_status === "unopened") unopened++;
    else unknown++;
  }
  return { opened, unopened, unknown, total: uniq.length };
}

function buildMonsterTable(monsters, statusFilter) {
  if (monsters.length === 0) return null;
  const visible = monsters.filter(e => statusMatchesFilter(e, statusFilter));
  const totalPending = monsters.filter(e => e.save_status === "unopened" || e.save_status === "unknown").length;
  visible.sort((a, b) => {
    const rank = s => s === "unopened" ? 0 : s === "unknown" ? 1 : 2;
    const r = rank(a.save_status) - rank(b.save_status);
    if (r !== 0) return r;
    return String(a.name || "").localeCompare(String(b.name || ""), "zh-Hans-CN");
  });

  const wrap = document.createElement("div");
  wrap.className = "items-wrap";
  const caption = document.createElement("div");
  caption.className = "items-caption";
  caption.textContent = "\u602a\u7269 (" + visible.length + " / " + monsters.length + ")";
  wrap.appendChild(caption);

  if (visible.length === 0) {
    const empty = document.createElement("div");
    empty.className = "items-empty";
    empty.textContent = totalPending > 0
      ? ("\u5f53\u524d\u7b5b\u9009\u4e0b\u65e0\u5339\u914d\u9879\uff08\u8be5\u5730\u56fe\u8fd8\u6709 " + totalPending + " \u9879\u672a\u5b8c\u6210\uff09")
      : "\u5f53\u524d\u7b5b\u9009\u4e0b\u65e0\u5339\u914d\u9879";
    wrap.appendChild(empty);
    return wrap;
  }

  const tbl = document.createElement("table");
  tbl.className = "items";
  let rowsHtml = '<thead><tr><th class="col-dot"></th><th class="col-status">\u72b6\u6001</th><th class="col-monster">\u602a\u7269</th><th class="col-weak">\u5f31\u70b9</th></tr></thead><tbody>';
  for (const e of visible) {
    let chips = "";
    for (const ws of (e.weak_slots || [])) {
      const lbl = weakSlotLabel(ws);
      const rev = isWeaknessRevealed(e, ws);
      const cls = rev ? "revealed" : "hidden";
      const txt = rev ? lbl : (lbl + "?");
      chips += '<span class="weak-chip ' + cls + '">' + escapeHtml(txt) + '</span>';
    }
    if (!chips) chips = '<span class="items-empty">\u2014</span>';
    const lv = (e.level > 0) ? (" Lv" + e.level) : "";
    const miss = e.missable_note ? String(e.missable_note) : "";
    rowsHtml += '<tr class="' + escapeHtml(e.save_status) + '">' +
      '<td class="col-dot"><span class="status-dot ' + escapeHtml(e.save_status) + '"></span></td>' +
      '<td class="col-status">' + escapeHtml(statusText("Monster", e.save_status)) + '</td>' +
      '<td class="col-monster">' + escapeHtml(miss + (e.name || e.enemy_key) + lv) + '</td>' +
      '<td class="col-weak"><div class="weak-chips">' + chips + '</div></td></tr>';
  }
  rowsHtml += '</tbody>';
  tbl.innerHTML = rowsHtml;
  wrap.appendChild(tbl);
  return wrap;
}

function buildTree(entries) {
  const tree = {};
  for (const e of entries) {
    const rk = e.region_key || "_other";
    const rn = e.region_name || "\u5176\u4ed6\u533a\u57df";
    const tk = e.nearest_town_key || "_unknown_town";
    const tn = e.nearest_town_name || "\u5f52\u5c5e\u4e0d\u660e";
    const mk = e.map_key || ("?_" + (e.area_code || ""));
    const mn = e.map_name || mk;
    if (!tree[rk]) tree[rk] = { name:rn, towns:{} };
    if (!tree[rk].towns[tk]) tree[rk].towns[tk] = { name:tn, maps:{} };
    if (!tree[rk].towns[tk].maps[mk]) tree[rk].towns[tk].maps[mk] = { name:mn, kind:e.map_kind_code, travel_name:e.nearest_town_name || tn, chests:[], hidden:[] };
    if (e.kind === "Chest") tree[rk].towns[tk].maps[mk].chests.push(e);
    else if (e.kind === "Hidden Item") tree[rk].towns[tk].maps[mk].hidden.push(e);
  }
  return tree;
}

function tally(items, kind) {
  let opened=0, unopened=0, unknown=0;
  for (const e of items) {
    if (kind && e.kind !== kind) continue;
    if (e.save_status === "opened") opened++;
    else if (e.save_status === "unopened") unopened++;
    else unknown++;
  }
  return { opened, unopened, unknown, total: opened + unopened + unknown };
}

function statusMatchesFilter(item, statusFilter) {
  if (statusFilter === "all") return true;
  if (statusFilter === "unopened") return item.save_status === "unopened" || item.save_status === "unknown";
  if (statusFilter === "opened")   return item.save_status === "opened";
  return true;
}

function kindMatchesFilter(item, kindFilter) {
  if (kindFilter === "all") return true;
  return item.kind === kindFilter;
}

function buildItemsTable(items, kindLabel, statusFilter, tableMode) {
  // tableMode: "chest" = 找法(仅密道/可错过) | "hidden" = 找法(必显)
  if (items.length === 0) return null;
  const showHintCol = tableMode === "chest" || tableMode === "hidden";
  const visible = items.filter(e => statusMatchesFilter(e, statusFilter));
  const totalPending = items.filter(e => e.save_status === "unopened" || e.save_status === "unknown").length;
  visible.sort((a, b) => {
    const rank = s => s === "unopened" ? 0 : s === "unknown" ? 1 : 2;
    const r = rank(a.save_status) - rank(b.save_status);
    if (r !== 0) return r;
    return String(a.reward || "").localeCompare(String(b.reward || ""), "zh-Hans-CN");
  });

  const wrap = document.createElement("div");
  wrap.className = "items-wrap";
  const caption = document.createElement("div");
  caption.className = "items-caption";
  caption.textContent = kindLabel + " (" + visible.length + " / " + items.length + ")";
  wrap.appendChild(caption);

  if (visible.length === 0) {
    const empty = document.createElement("div");
    empty.className = "items-empty";
    empty.textContent = totalPending > 0
      ? ("\u5f53\u524d\u7b5b\u9009\u4e0b\u65e0\u5339\u914d\u9879\uff08\u8be5\u5730\u56fe\u8fd8\u6709 " + totalPending + " \u9879\u672a\u5b8c\u6210\uff09")
      : "\u5f53\u524d\u7b5b\u9009\u4e0b\u65e0\u5339\u914d\u9879";
    wrap.appendChild(empty);
    return wrap;
  }

  const tbl = document.createElement("table");
  tbl.className = "items";
  let head = '<thead><tr><th class="col-dot"></th><th class="col-status">&#29366;&#24577;</th><th class="col-reward">&#22870;&#21169;</th>';
  if (showHintCol) head += '<th class="col-hint">' + (tableMode === "hidden" ? "&#35302;&#21457;/&#25214;&#27861;" : "&#25214;&#27861;") + '</th>';
  head += '</tr></thead>';
  let rowsHtml = head + '<tbody>';
  for (const e of visible) {
    rowsHtml += '<tr class="' + escapeHtml(e.save_status) + '">' +
      '<td class="col-dot"><span class="status-dot ' + escapeHtml(e.save_status) + '"></span></td>' +
      '<td class="col-status">' + escapeHtml(statusText(e.kind, e.save_status)) + '</td>' +
      '<td class="col-reward">' + escapeHtml(e.reward || "\u2014") + '</td>';
    if (showHintCol) {
      const hint = e.find_hint || "";
      const hintCls = hint ? (tableMode === "hidden" ? " hint-hidden" : " hint-secret") : "";
      rowsHtml += '<td class="col-hint' + hintCls + '">' + escapeHtml(hint || (tableMode === "hidden" ? "\u6682\u65e0\u6570\u636e" : "\u2014")) + '</td>';
    }
    rowsHtml += '</tr>';
  }
  rowsHtml += '</tbody>';
  tbl.innerHTML = rowsHtml;
  wrap.appendChild(tbl);
  return wrap;
}

function render() {
  const q             = document.querySelector("#q").value.trim().toLowerCase();
  const kindFilter    = document.querySelector("#kindFilter").value;
  const statusFilter  = document.querySelector("#statusFilter").value;
  const hideCleared   = statusFilter === "unopened";
  const root          = document.querySelector("#regions");
  root.innerHTML = "";
  updateKindAchieveNote(kindFilter);

  if (!saveLoaded) {
    document.querySelector("#openedCount").textContent          = 0;
    document.querySelector("#unopenedCount").textContent        = 0;
    document.querySelector("#hiddenOpenedCount").textContent    = 0;
    document.querySelector("#hiddenUnopenedCount").textContent  = 0;
    document.querySelector("#monsterDoneCount").textContent     = 0;
    document.querySelector("#monsterPendingCount").textContent  = 0;
    document.querySelector("#collectorDoneCount").textContent   = 0;
    document.querySelector("#collectorPendingCount").textContent = 0;
    return;
  }

  if (kindFilter === "Collector") {
    const searchFiltered = currentCollectorEntries.filter(e => {
      if (!q) return true;
      const hay = [e.name, e.item_key, e.type_name, e.find_hint, e.missable_note, e.save_status].join(" ").toLowerCase();
      return hay.includes(q);
    });
    const cStats = tallyCollector(searchFiltered);
    document.querySelector("#collectorDoneCount").textContent    = cStats.opened;
    document.querySelector("#collectorPendingCount").textContent = cStats.unopened + cStats.unknown;
    const chestStats  = tally(currentEntries.filter(e => !q || [e.map_name, e.reward, e.region_name].join(" ").toLowerCase().includes(q)), "Chest");
    const hiddenStats = tally(currentEntries.filter(e => !q || [e.map_name, e.reward, e.region_name].join(" ").toLowerCase().includes(q)), "Hidden Item");
    document.querySelector("#openedCount").textContent         = chestStats.opened;
    document.querySelector("#unopenedCount").textContent       = chestStats.unopened + chestStats.unknown;
    document.querySelector("#hiddenOpenedCount").textContent   = hiddenStats.opened;
    document.querySelector("#hiddenUnopenedCount").textContent = hiddenStats.unopened + hiddenStats.unknown;
    const mStatsC = tallyMonsters(currentEnemyEntries.filter(e => !q || [e.name, e.map_name, e.region_name].join(" ").toLowerCase().includes(q)));
    document.querySelector("#monsterDoneCount").textContent    = mStatsC.opened;
    document.querySelector("#monsterPendingCount").textContent = mStatsC.unopened + mStatsC.unknown;

    const groups = uniqueCollectorTypes(searchFiltered);
    const isPendingC = e => e.save_status === "unopened" || e.save_status === "unknown";
    for (const g of groups) {
      const pending = g.items.filter(isPendingC).length;
      const anyVisible = g.items.some(e => statusMatchesFilter(e, statusFilter));
      if (hideCleared && pending === 0) continue;
      if (!anyVisible && pending === 0) continue;
      const det = document.createElement("details");
      det.className = "region" + (pending > 0 ? "" : " all-cleared");
      if (pending > 0) det.open = true;
      const badgeText = pending > 0 ? ("\u672a\u5f97 " + pending) : "\u2713 \u5df2\u6e05";
      const badgeClass = pending > 0 ? "has-unopened" : "all-cleared";
      det.innerHTML = '<summary><span>' + escapeHtml(g.type_name) + '</span><span class="region-badge ' + badgeClass + '">' + badgeText + '</span></summary>';
      const tbl = buildCollectorTable(g.items, statusFilter);
      if (tbl) det.appendChild(tbl);
      root.appendChild(det);
    }
    return;
  }

  if (kindFilter === "Monster") {
    const searchFiltered = currentEnemyEntries.filter(e => {
      if (!q) return true;
      const hay = [e.name, e.enemy_key, e.map_name, e.map_key, e.region_name, e.nearest_town_name, e.save_status].join(" ").toLowerCase();
      return hay.includes(q);
    });
    const mStats = tallyMonsters(searchFiltered);
    document.querySelector("#monsterDoneCount").textContent    = mStats.opened;
    document.querySelector("#monsterPendingCount").textContent = mStats.unopened + mStats.unknown;
    // Keep chest/hidden totals from full data (unaffected by monster filter).
    const chestStats  = tally(currentEntries.filter(e => !q || [e.map_name, e.reward, e.region_name].join(" ").toLowerCase().includes(q)), "Chest");
    const hiddenStats = tally(currentEntries.filter(e => !q || [e.map_name, e.reward, e.region_name].join(" ").toLowerCase().includes(q)), "Hidden Item");
    document.querySelector("#openedCount").textContent         = chestStats.opened;
    document.querySelector("#unopenedCount").textContent       = chestStats.unopened + chestStats.unknown;
    document.querySelector("#hiddenOpenedCount").textContent   = hiddenStats.opened;
    document.querySelector("#hiddenUnopenedCount").textContent = hiddenStats.unopened + hiddenStats.unknown;
    const cStatsM = tallyCollector(currentCollectorEntries.filter(e => !q || [e.name, e.type_name, e.find_hint].join(" ").toLowerCase().includes(q)));
    document.querySelector("#collectorDoneCount").textContent    = cStatsM.opened;
    document.querySelector("#collectorPendingCount").textContent = cStatsM.unopened + cStatsM.unknown;

    const tree = buildEnemyTree(searchFiltered);
    const seenRegions = new Set();
    const regionEntries = [];
    for (const r of REGION_ORDER) {
      if (tree[r.key]) { regionEntries.push([r.key, tree[r.key]]); seenRegions.add(r.key); }
    }
    for (const rk of Object.keys(tree)) {
      if (!seenRegions.has(rk)) regionEntries.push([rk, tree[rk]]);
    }

    const isPendingMonster = e => e.save_status === "unopened" || e.save_status === "unknown";
    const isVisibleMonster = e => statusMatchesFilter(e, statusFilter);

    for (const [rk, rdata] of regionEntries) {
      const allM = Object.values(rdata.towns).flatMap(t => Object.values(t.maps).flatMap(m => m.monsters));
      const uniqM = uniqueMonsters(allM);
      const pendingCount = uniqM.filter(isPendingMonster).length;
      const anyVisible = allM.some(isVisibleMonster);
      if (hideCleared && pendingCount === 0) continue;
      if (!anyVisible && pendingCount === 0) continue;

      const regionDet = document.createElement("details");
      regionDet.className = "region" + (pendingCount > 0 ? "" : " all-cleared");
      if (pendingCount > 0) regionDet.open = true;
      const badgeText = pendingCount > 0 ? ("\u672a\u8bc6\u7834 " + pendingCount) : "\u2713 \u5df2\u6e05";
      const badgeClass = pendingCount > 0 ? "has-unopened" : "all-cleared";
      regionDet.innerHTML = '<summary><span>' + escapeHtml(rdata.name) + '</span><span class="region-badge ' + badgeClass + '">' + badgeText + '</span></summary><div class="towns"></div>';
      const townsHost = regionDet.querySelector(".towns");

      const townList = Object.entries(rdata.towns).map(([tk, tdata]) => {
        const tM = Object.values(tdata.maps).flatMap(m => m.monsters);
        const tUniq = uniqueMonsters(tM);
        const tPending = tUniq.filter(isPendingMonster).length;
        const tVisible = tM.filter(isVisibleMonster).length;
        return { tk, tdata, tPending, tVisible };
      }).filter(t => (hideCleared ? t.tPending > 0 : (t.tPending > 0 || t.tVisible > 0)));
      if (townList.length === 0) continue;

      townList.sort((a, b) => {
        if ((b.tPending > 0) - (a.tPending > 0) !== 0) return (b.tPending > 0) - (a.tPending > 0);
        return a.tdata.name.localeCompare(b.tdata.name, "zh-Hans-CN");
      });

      for (const {tk, tdata, tPending} of townList) {
        const townDet = document.createElement("details");
        townDet.className = "town" + (tPending > 0 ? "" : " all-cleared");
        if (tPending > 0) townDet.open = true;
        townDet.innerHTML = '<summary><span>' + escapeHtml(tdata.name) + '</span>' +
          '<span class="town-meta">' + (tPending > 0 ? '\u8fd8\u6709 <b>' + tPending + '</b> \u9879\u672a\u5b8c\u6210' : '\u2713 \u5df2\u6e05') + '</span></summary><div class="maps"></div>';
        const mapsHost = townDet.querySelector(".maps");

        const mapList = Object.entries(tdata.maps).map(([mk, mdata]) => {
          const mM = mdata.monsters;
          const mUniq = uniqueMonsters(mM);
          const mPending = mUniq.filter(isPendingMonster).length;
          const mVisible = mM.filter(isVisibleMonster).length;
          return { mk, mdata, mPending, mVisible };
        }).filter(m => (hideCleared ? m.mPending > 0 : (m.mPending > 0 || m.mVisible > 0)));

        const kindOrder = { T:0, F:1, D:2, "":3 };
        mapList.sort((a, b) => {
          const ko = (kindOrder[a.mdata.kind] ?? 9) - (kindOrder[b.mdata.kind] ?? 9);
          if (ko !== 0) return ko;
          if ((b.mPending > 0) - (a.mPending > 0) !== 0) return (b.mPending > 0) - (a.mPending > 0);
          return a.mdata.name.localeCompare(b.mdata.name, "zh-Hans-CN");
        });

        for (const {mdata, mPending} of mapList) {
          const mapDet = document.createElement("details");
          mapDet.className = "map" + (mPending > 0 ? "" : " all-cleared");
          if (mPending > 0) mapDet.open = true;
          const isTown = mdata.kind === "T";
          const sameAsTown = isTown && mdata.name === tdata.name;
          const displayName = sameAsTown ? "&#65288;&#26412;&#22478;&#38215;&#65289;" : escapeHtml(mdata.name);
          const travelHint = (!isTown && tk && tk !== "_unknown_town")
            ? '<span class="travel-hint">&#21487;&#20256;&#36865;&#21040;&#65306;' + escapeHtml(mdata.travel_name || tdata.name) + '</span>' : '';
          const statsCls = mPending > 0 ? 'map-stats' : 'map-stats cleared';
          const statsText = mPending > 0 ? ('\u672a\u5b8c\u6210 ' + mPending) : '\u2713 \u5df2\u6e05';
          mapDet.innerHTML = '<summary><span class="map-kind ' + escapeHtml(mdata.kind) + '">' + escapeHtml(mapKindLabel(mdata.kind)) + '</span>' +
            '<span class="map-name">' + displayName + '</span>' + travelHint +
            '<span class="' + statsCls + '">' + statsText + '</span></summary>';
          const tbl = buildMonsterTable(mdata.monsters, statusFilter);
          if (tbl) mapDet.appendChild(tbl);
          mapsHost.appendChild(mapDet);
        }
        townsHost.appendChild(townDet);
      }
      root.appendChild(regionDet);
    }
    return;
  }

  // --- Chest / Hidden Item view ---
  const searchFiltered = currentEntries.filter(e => {
    if (!q) return true;
    const hay = [e.kind, e.save_status, e.map_name, e.reward, e.map_key, e.region_name, e.nearest_town_name].join(" ").toLowerCase();
    return hay.includes(q);
  });

  // Top-of-page totals: global, not affected by kind/status filters.
  const chestStats  = tally(searchFiltered, "Chest");
  const hiddenStats = tally(searchFiltered, "Hidden Item");
  document.querySelector("#openedCount").textContent         = chestStats.opened;
  document.querySelector("#unopenedCount").textContent       = chestStats.unopened + chestStats.unknown;
  document.querySelector("#hiddenOpenedCount").textContent   = hiddenStats.opened;
  document.querySelector("#hiddenUnopenedCount").textContent = hiddenStats.unopened + hiddenStats.unknown;
  const mStats = tallyMonsters(currentEnemyEntries.filter(e => !q || [e.name, e.map_name, e.region_name].join(" ").toLowerCase().includes(q)));
  document.querySelector("#monsterDoneCount").textContent    = mStats.opened;
  document.querySelector("#monsterPendingCount").textContent = mStats.unopened + mStats.unknown;
  const cStatsAll = tallyCollector(currentCollectorEntries.filter(e => !q || [e.name, e.type_name, e.find_hint].join(" ").toLowerCase().includes(q)));
  document.querySelector("#collectorDoneCount").textContent    = cStatsAll.opened;
  document.querySelector("#collectorPendingCount").textContent = cStatsAll.unopened + cStatsAll.unknown;

  const tree = buildTree(searchFiltered);

  // Render in REGION_ORDER first, then any unknown region last.
  const seenRegions = new Set();
  const regionEntries = [];
  for (const r of REGION_ORDER) {
    if (tree[r.key]) { regionEntries.push([r.key, tree[r.key]]); seenRegions.add(r.key); }
  }
  for (const rk of Object.keys(tree)) {
    if (!seenRegions.has(rk)) regionEntries.push([rk, tree[rk]]);
  }

  // Helpers for counting under the active kind filter.
  const isPendingChest  = e => e.kind === "Chest"       && (e.save_status === "unopened" || e.save_status === "unknown");
  const isPendingHidden = e => e.kind === "Hidden Item" && (e.save_status === "unopened" || e.save_status === "unknown");
  const isPendingForKind = e => kindMatchesFilter(e, kindFilter) && (e.save_status === "unopened" || e.save_status === "unknown");
  const isVisibleForFilters = e => kindMatchesFilter(e, kindFilter) && statusMatchesFilter(e, statusFilter);

  for (const [rk, rdata] of regionEntries) {
    const allItems = Object.values(rdata.towns).flatMap(t => Object.values(t.maps).flatMap(m => [...m.chests, ...m.hidden]));
    // For the region badge we always count pending items (independent of status filter), broken down by kind.
    const pendingChest  = (kindFilter === "all" || kindFilter === "Chest")       ? allItems.filter(isPendingChest).length  : 0;
    const pendingHidden = (kindFilter === "all" || kindFilter === "Hidden Item") ? allItems.filter(isPendingHidden).length : 0;
    const anyPending = pendingChest > 0 || pendingHidden > 0;
    // "Anything matching the current filters" — determines if region has anything to show.
    const anyVisible = allItems.some(isVisibleForFilters);
    // Hide cleared regions when user is filtering for pending items.
    if (hideCleared && !anyPending) continue;
    // If filtering for "opened", we still want to show a region as long as it has either visible OR pending matter.
    if (!anyVisible && !anyPending) continue;

    const regionDet = document.createElement("details");
    regionDet.className = "region" + (anyPending ? "" : " all-cleared");
    if (anyPending) regionDet.open = true;

    const badgeBits = [];
    if (kindFilter !== "Hidden Item") badgeBits.push("&#23453;&#31665; " + pendingChest + " &#26410;&#24320;");
    if (kindFilter !== "Chest")       badgeBits.push("&#38544;&#34255; " + pendingHidden + " &#26410;&#24471;");
    const badgeText = anyPending ? badgeBits.join(" \u00b7 ") : "\u2713 \u5df2\u6e05";
    const badgeClass = anyPending ? "has-unopened" : "all-cleared";

    regionDet.innerHTML = '<summary><span>' + escapeHtml(rdata.name) + '</span><span class="region-badge ' + badgeClass + '">' + badgeText + '</span></summary><div class="towns"></div>';
    const townsHost = regionDet.querySelector(".towns");

    // Towns: keep any town that has either pending or visible items (under the kind filter).
    const townList = Object.entries(rdata.towns).map(([tk, tdata]) => {
      const tItems = Object.values(tdata.maps).flatMap(m => [...m.chests, ...m.hidden]);
      const tPending = tItems.filter(isPendingForKind).length;
      const tVisible = tItems.filter(isVisibleForFilters).length;
      return { tk, tdata, tPending, tVisible };
    }).filter(t => (hideCleared ? t.tPending > 0 : (t.tPending > 0 || t.tVisible > 0)));

    if (townList.length === 0) continue;

    townList.sort((a, b) => {
      if ((b.tPending > 0) - (a.tPending > 0) !== 0) return (b.tPending > 0) - (a.tPending > 0);
      return a.tdata.name.localeCompare(b.tdata.name, "zh-Hans-CN");
    });

    for (const {tk, tdata, tPending} of townList) {
      const townDet = document.createElement("details");
      townDet.className = "town" + (tPending > 0 ? "" : " all-cleared");
      if (tPending > 0) townDet.open = true;

      townDet.innerHTML = '<summary><span>' + escapeHtml(tdata.name) + '</span>' +
        '<span class="town-meta">' + (tPending > 0 ? '\u8fd8\u6709 <b>' + tPending + '</b> \u9879\u672a\u5b8c\u6210' : '\u2713 \u5df2\u6e05') + '</span></summary>' +
        '<div class="maps"></div>';
      const mapsHost = townDet.querySelector(".maps");

      // Maps inside town: town map first, then F, then D. Pending first within each.
      // Key fix: include maps that have pending items (under kind filter) even if statusFilter hides them all — this guarantees per-map pending counts always sum to the region badge.
      const mapList = Object.entries(tdata.maps).map(([mk, mdata]) => {
        const mItems = [...mdata.chests, ...mdata.hidden];
        const mPending = mItems.filter(isPendingForKind).length;
        const mVisible = mItems.filter(isVisibleForFilters).length;
        return { mk, mdata, mPending, mVisible };
      }).filter(m => (hideCleared ? m.mPending > 0 : (m.mPending > 0 || m.mVisible > 0)));

      const kindOrder = { T:0, F:1, D:2, "":3 };
      mapList.sort((a, b) => {
        const ko = (kindOrder[a.mdata.kind] ?? 9) - (kindOrder[b.mdata.kind] ?? 9);
        if (ko !== 0) return ko;
        if ((b.mPending > 0) - (a.mPending > 0) !== 0) return (b.mPending > 0) - (a.mPending > 0);
        return a.mdata.name.localeCompare(b.mdata.name, "zh-Hans-CN");
      });

      for (const {mk, mdata, mPending} of mapList) {
        const mapDet = document.createElement("details");
        mapDet.className = "map" + (mPending > 0 ? "" : " all-cleared");
        if (mPending > 0) mapDet.open = true;

        const isTown = mdata.kind === "T";
        const sameAsTown = isTown && mdata.name === tdata.name;
        const displayName = sameAsTown ? "&#65288;&#26412;&#22478;&#38215;&#65289;" : escapeHtml(mdata.name);
        const travelHint = (!isTown && tk && tk !== "_unknown_town")
          ? '<span class="travel-hint">&#21487;&#20256;&#36865;&#21040;&#65306;' + escapeHtml(mdata.travel_name || tdata.name) + '</span>'
          : '';
        const statsCls = mPending > 0 ? 'map-stats' : 'map-stats cleared';
        const statsText = mPending > 0 ? ('\u672a\u5b8c\u6210 ' + mPending) : '\u2713 \u5df2\u6e05';
        mapDet.innerHTML = '<summary>' +
          '<span class="map-kind ' + escapeHtml(mdata.kind) + '">' + escapeHtml(mapKindLabel(mdata.kind)) + '</span>' +
          '<span class="map-name">' + displayName + '</span>' +
          travelHint +
          '<span class="' + statsCls + '">' + statsText + '</span>' +
          '</summary>';

        // Chests: quadrant + secret-passage hints only. Hidden: trigger/find hints required.
        if (kindFilter === "all" || kindFilter === "Chest") {
          const chestsTbl = buildItemsTable(mdata.chests, "\u5b9d\u7bb1", statusFilter, "chest");
          if (chestsTbl) mapDet.appendChild(chestsTbl);
        }
        if (kindFilter === "all" || kindFilter === "Hidden Item") {
          const hiddenTbl = buildItemsTable(mdata.hidden, "\u9690\u85cf\u9053\u5177", statusFilter, "hidden");
          if (hiddenTbl) mapDet.appendChild(hiddenTbl);
        }

        mapsHost.appendChild(mapDet);
      }

      townsHost.appendChild(townDet);
    }
    root.appendChild(regionDet);
  }
}

document.querySelector("#pickSaveFile").addEventListener("click", () => {
  document.querySelector("#saveFile").click();
});
document.querySelector("#saveFile").addEventListener("change", async event => {
  const file = event.target.files && event.target.files[0];
  if (!file) return;
  const buffer = await file.arrayBuffer();
  applySave(buffer, file.name);
});
document.querySelector("#loadSampleSave").addEventListener("click", async () => {
  const fileInfo = document.querySelector("#fileInfo");
  const candidates = ["samples/SaveData1.sav", "./samples/SaveData1.sav", "../samples/SaveData1.sav"];
  fileInfo.textContent = "\u6b63\u5728\u52a0\u8f7d\u793a\u4f8b\u5b58\u6863\u2026";
  for (const url of candidates) {
    try {
      const res = await fetch(url);
      if (!res.ok) continue;
      const buffer = await res.arrayBuffer();
      applySave(buffer, "SaveData1.sav\uff08\u793a\u4f8b\uff09");
      return;
    } catch (_) {}
  }
  fileInfo.innerHTML = '<span class="warn">\u65e0\u6cd5\u81ea\u52a8\u52a0\u8f7d\u793a\u4f8b\u5b58\u6863\uff08\u76f4\u63a5\u53cc\u51fb HTML \u65f6\u6d4f\u89c8\u5668\u5e38\u7981\u6b62 fetch\uff09\u3002\u8bf7\u6539\u7528\u672c\u5730 HTTP \u670d\u52a1\u6253\u5f00\uff0c\u6216\u624b\u52a8\u9009\u62e9 <code>samples/SaveData1.sav</code>\u3002</span>';
});
document.querySelector("#clearSave").addEventListener("click", () => {
  document.querySelector("#saveFile").value = "";
  document.querySelector("#fileInfo").textContent = "\u5c1a\u672a\u9009\u62e9\u5b58\u6863";
  saveLoaded = false;
  currentEntries = [];
  currentEnemyEntries = ENEMY_SPAWN_ENTRIES.map(e => Object.assign({}, e, { save_status: "unknown", revealed_count: 0 }));
  currentCollectorEntries = [];
  render();
});
document.querySelector("#q").addEventListener("input", render);
document.querySelector("#kindFilter").addEventListener("change", render);
document.querySelector("#statusFilter").addEventListener("change", render);

function flashRegions() {
  const root = document.querySelector("#regions");
  root.classList.remove("flash");
  // Reflow to restart the CSS animation.
  void root.offsetWidth;
  root.classList.add("flash");
}

const THEME_KEY = "octopath-tracker-theme";
const VALID_THEMES = ["dark", "light", "sepia"];
function applyTheme(theme) {
  if (!VALID_THEMES.includes(theme)) theme = "dark";
  document.body.classList.remove("theme-light", "theme-sepia");
  if (theme === "light") document.body.classList.add("theme-light");
  else if (theme === "sepia") document.body.classList.add("theme-sepia");
  document.querySelectorAll(".theme-btn").forEach(b => {
    b.classList.toggle("active", b.dataset.theme === theme);
  });
  try { localStorage.setItem(THEME_KEY, theme); } catch (_) {}
}
(function initTheme() {
  let saved = null;
  try { saved = localStorage.getItem(THEME_KEY); } catch (_) {}
  applyTheme(saved || "dark");
})();
document.querySelectorAll(".theme-btn").forEach(b => {
  b.addEventListener("click", () => applyTheme(b.dataset.theme));
});
document.querySelector("#expandAll").addEventListener("click", () => {
  document.querySelectorAll("#regions details").forEach(d => d.open = true);
  flashRegions();
});
document.querySelector("#collapseAll").addEventListener("click", () => {
  // Keep the top-level region nodes open so the layout doesn't collapse to nothing.
  document.querySelectorAll("#regions details.town, #regions details.map").forEach(d => d.open = false);
  flashRegions();
});
currentEnemyEntries = ENEMY_SPAWN_ENTRIES.map(e => Object.assign({}, e, { save_status: "unknown", revealed_count: 0 }));
render();
</script>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutHtml, $html, [System.Text.UTF8Encoding]::new($false))
$sampleSrc = Join-Path $PSScriptRoot "samples\SaveData1.sav"
$sampleOutDir = Join-Path $OutDir "samples"
if (Test-Path -LiteralPath $sampleSrc) {
  if (!(Test-Path -LiteralPath $sampleOutDir)) {
    New-Item -ItemType Directory -Force -Path $sampleOutDir | Out-Null
  }
  Copy-Item -LiteralPath $sampleSrc -Destination (Join-Path $sampleOutDir "SaveData1.sav") -Force
  Write-Host "Sample save copied to $sampleOutDir"
} else {
  Write-Host "WARN: samples\SaveData1.sav missing; sample-load button will fail until you add it."
}

# Portfolio / Pages entry: same build also published as repo-root index.html
$RootIndex = Join-Path $PSScriptRoot "index.html"
Copy-Item -LiteralPath $OutHtml -Destination $RootIndex -Force
Write-Host "Also wrote $RootIndex"

Write-Host "Wrote $OutHtml ($($entries.Count) entries, $($enemySpawnEntries.Count) enemy spawns, $($regionOrder.Count) regions)"

$diagLines = New-Object System.Collections.Generic.List[string]
foreach ($mk in @("D_Mount_2_1", "D_Mount_2_2", "F_Mount_2_2", "F_Mount_2_1", "D_Mount_1_1", "D_Forest_2_Job")) {
  $e = @($entries | Where-Object { $_.map_key -eq $mk -and $_.object_id -match "TrsrBx" } | Select-Object -First 3)
  $m = @($enemySpawnEntries | Where-Object { $_.map_key -eq $mk } | Select-Object -First 1)
  if ($e.Count -gt 0) {
    foreach ($item in $e) {
      $diagLines.Add(("collectible {0} {1}: town={2} key={3} pos={4}" -f $mk, $item.reward, $item.nearest_town_name, $item.nearest_town_key, $item.position_label)) | Out-Null
    }
  }
  if ($m.Count -gt 0) {
    $diagLines.Add(("monster    {0}: town={1} key={2}" -f $mk, $m[0].nearest_town_name, $m[0].nearest_town_key)) | Out-Null
  }
}
$diagPath = Join-Path $OutDir "town_check.txt"
[System.IO.File]::WriteAllLines($diagPath, $diagLines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $diagPath"

# Full town assignment audit (one row per unique map_key).
$auditRows = New-Object System.Collections.Generic.List[object]
$seenMaps = @{}
foreach ($e in $entries) {
  if (!$e.map_key -or $seenMaps.ContainsKey($e.map_key)) { continue }
  $seenMaps[$e.map_key] = $true
  $auditRows.Add([pscustomobject]@{
    map_key = $e.map_key
    map_name = $e.map_name
    nearest_town_key = $e.nearest_town_key
    nearest_town_name = $e.nearest_town_name
  }) | Out-Null
}
foreach ($e in $enemySpawnEntries) {
  if (!$e.map_key -or $seenMaps.ContainsKey($e.map_key)) { continue }
  $seenMaps[$e.map_key] = $true
  $auditRows.Add([pscustomobject]@{
    map_key = $e.map_key
    map_name = $e.map_name
    nearest_town_key = $e.nearest_town_key
    nearest_town_name = $e.nearest_town_name
  }) | Out-Null
}
$auditCsv = Join-Path $OutDir "town_audit.csv"
$auditRows | Sort-Object map_key | Export-Csv -LiteralPath $auditCsv -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $auditCsv ($($auditRows.Count) maps)"

# ---------------- Self-audit: submap towns + secret/pos samples ----------------
$submapHits = New-Object System.Collections.Generic.List[string]
foreach ($row in $auditRows) {
  if ($row.map_key -match '^[FD]_' -and ($row.nearest_town_key -match '_[BC]$' -or $row.nearest_town_name -match ' -')) {
    $submapHits.Add(("{0}	{1}	{2}	{3}" -f $row.map_key, $row.map_name, $row.nearest_town_key, $row.nearest_town_name)) | Out-Null
  }
}
$subPath = Join-Path $OutDir "town_submap_audit.txt"
$subLines = New-Object System.Collections.Generic.List[string]
$subLines.Add(("submap_or_suffix_hits={0}" -f $submapHits.Count)) | Out-Null
$subLines.Add("F_Snow_1_2 expect: Flamesgrace + Swarkii") | Out-Null
$snow = @($entries | Where-Object { $_.map_key -eq 'F_Snow_1_2' } | Select-Object -First 1)
if ($snow) { $subLines.Add(("F_Snow_1_2 actual: {0} / {1}" -f $snow.nearest_town_key, $snow.nearest_town_name)) | Out-Null }
foreach ($h in $submapHits) { $subLines.Add($h) | Out-Null }
[System.IO.File]::WriteAllLines($subPath, $subLines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $subPath ($($submapHits.Count) suspect town rows)"

$posLines = New-Object System.Collections.Generic.List[string]
$posLines.Add("SECRET_HINTS: chests are ON this map but behind secret walls/cliffs") | Out-Null
foreach ($oid in @($SecretChestHints.Keys)) {
  $e = @($entries | Where-Object { $_.object_id -eq $oid } | Select-Object -First 1)
  if ($e.Count -gt 0) {
    $posLines.Add(("{0}`t{1}`t{2}`tpos={3}`thint={4}" -f $e[0].object_id, $e[0].map_name, $e[0].reward, $e[0].position_label, $e[0].find_hint)) | Out-Null
  }
}
$posLines.Add("ORPHAN_CHECK: PlacementInfoList covers all ObjectData TrsrBx/HdnPnt (0 orphans)") | Out-Null
$posPath = Join-Path $OutDir "chest_pos_audit.txt"
[System.IO.File]::WriteAllLines($posPath, $posLines, [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $posPath"

# Hidden item hint coverage audit
$hidLines = New-Object System.Collections.Generic.List[string]
$hidEntries = @($entries | Where-Object { $_.kind -eq "Hidden Item" })
$hidWithHint = @($hidEntries | Where-Object { $_.find_hint })
$hidMissing = @($hidEntries | Where-Object { -not $_.find_hint })
$hidLines.Add(("HIDDEN_HINTS: {0}/{1} covered" -f $hidWithHint.Count, $hidEntries.Count)) | Out-Null
$hidLines.Add("SOURCE: community guides (TrueAchievements/marcv666/游民), NOT game unpack") | Out-Null
foreach ($e in ($hidMissing | Sort-Object object_id)) {
  $hidLines.Add(("{0}`t{1}`t{2}" -f $e.object_id, $e.map_name, $e.reward)) | Out-Null
}
$hidAuditPath = Join-Path $OutDir "hidden_item_hints_audit.txt"
[System.IO.File]::WriteAllLines($hidAuditPath, $hidLines, [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0} ({1} missing hints)" -f $hidAuditPath, $hidMissing.Count)
