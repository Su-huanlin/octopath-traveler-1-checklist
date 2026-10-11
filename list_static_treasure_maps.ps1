$ErrorActionPreference = "Stop"

$ContentDir = "D:\Unpacking game\afb02f5bbd8d0d94fe47e171a61cd51ee2ffeb73\Output\Exports\Octopath_Traveler\Content"
$Out = "D:\Unpacking game\OctopathTrackerOutput\static_treasure_map_order.csv"

function LoadRows([string]$Path) {
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $data = $raw | ConvertFrom-Json
  return $data[0].Rows
}

function TextValue($TextRows, [string]$Key) {
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

$objectRows = LoadRows (Join-Path $ContentDir "Object\Database\ObjectData.json")
$textRows = LoadRows (Join-Path $ContentDir "GameText\Database\GameTextZH_CN.json")
$seen = @{}
$rows = New-Object System.Collections.Generic.List[object]

foreach ($prop in $objectRows.PSObject.Properties) {
  $objectId = $prop.Name
  if (!$objectId.StartsWith("TrsrBx_")) { continue }
  $mapKey = ObjectMapKey $textRows $objectId
  if (!$mapKey) { $mapKey = "UNMAPPED" }
  if (!$seen.ContainsKey($mapKey)) {
    $seen[$mapKey] = $rows.Count
    $rows.Add([pscustomobject]@{
      static_order = $rows.Count
      map_key = $mapKey
      map_name = TextValue $textRows $mapKey
      first_object_id = $objectId
    })
  }
}

$rows | Export-Csv -LiteralPath $Out -NoTypeInformation -Encoding UTF8
Write-Host "Output: $Out"
Write-Host "Rows: $($rows.Count)"
