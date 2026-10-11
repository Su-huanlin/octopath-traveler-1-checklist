$ErrorActionPreference = "Stop"
$oneDrive = Join-Path $env:USERPROFILE "OneDrive"
$save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $save) { throw "SaveData1.sav not found" }
$bytes = [System.IO.File]::ReadAllBytes($save.FullName)
$out = "D:\Unpacking game\OctopathTrackerOutput\treasure_blocks_probe.txt"

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

function DumpRegion([byte[]]$Bytes, [int]$Start, [int]$Len) {
  $lines = New-Object System.Collections.Generic.List[string]
  for ($o = $Start; $o -lt [Math]::Min($Bytes.Length, $Start + $Len); $o += 16) {
    $lines.Add((DumpLine $Bytes $o 16))
  }
  return $lines
}

$targets = @("TreasureStateArray", "HiddenPointCount", "WeaknessOpen", "EnemyID")
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Save: $($save.FullName)")
$lines.Add("Size: $($bytes.Length)")
foreach ($target in $targets) {
  $hits = FindAscii $bytes $target
  $lines.Add("")
  $lines.Add("TARGET $target count $($hits.Count)")
  $n = [Math]::Min(12, $hits.Count)
  for ($k = 0; $k -lt $n; $k++) {
    $hit = $hits[$k]
    $start = [Math]::Max(0, $hit - 32)
    $lines.Add("")
    $lines.Add(("HIT {0} at 0x{1:X8}" -f $k, $hit))
    foreach ($l in (DumpRegion $bytes $start 192)) { $lines.Add($l) }
  }
}

[System.IO.File]::WriteAllLines($out, $lines, [System.Text.Encoding]::UTF8)
Write-Host "Output: $out"
