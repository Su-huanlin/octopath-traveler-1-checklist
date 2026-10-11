$ErrorActionPreference = "Stop"

$oneDrive = Join-Path $env:USERPROFILE "OneDrive"
$save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $save) { throw "SaveData1.sav not found" }

$bytes = [System.IO.File]::ReadAllBytes($save.FullName)
$out = "D:\Unpacking game\OctopathTrackerOutput\mapdata_region_probe.txt"

function DumpLine([byte[]]$Bytes, [int]$Offset, [int]$Count) {
  $hex = New-Object System.Collections.Generic.List[string]
  $asc = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $Count -and ($Offset + $i) -lt $Bytes.Length; $i++) {
    $b = $Bytes[$Offset + $i]
    $hex.Add($b.ToString("X2"))
    if ($b -ge 32 -and $b -le 126) { [void]$asc.Append([char]$b) } else { [void]$asc.Append(".") }
  }
  return ("{0:X8}: {1,-47} {2}" -f $Offset, ($hex -join " "), $asc.ToString())
}

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

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Save: $($save.FullName)")
$lines.Add("")

$targets = @("MapData", "MapID_", "TreasureStateArray_")
foreach ($target in $targets) {
  $hits = FindAscii $bytes $target
  $lines.Add("$target count $($hits.Count)")
  $lines.Add(($hits | Select-Object -First 40 | ForEach-Object { "0x{0:X8}" -f $_ }) -join ", ")
  $lines.Add("")
}

$regions = @(
  @{ name = "MapData array header"; start = 0x00132480; len = 0x500 },
  @{ name = "First treasure entries"; start = 0x00132860; len = 0x900 },
  @{ name = "MapID earlier sample"; start = 0x00108F80; len = 0x500 }
)

foreach ($r in $regions) {
  $lines.Add("")
  $lines.Add("=== $($r.name) start=0x$('{0:X8}' -f $r.start) len=0x$('{0:X}' -f $r.len) ===")
  for ($o = $r.start; $o -lt [Math]::Min($bytes.Length, $r.start + $r.len); $o += 16) {
    $lines.Add((DumpLine $bytes $o 16))
  }
}

[System.IO.File]::WriteAllLines($out, $lines, [System.Text.Encoding]::UTF8)
Write-Host "Output: $out"
