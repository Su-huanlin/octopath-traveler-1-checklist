$ErrorActionPreference = "Stop"
$oneDrive = Join-Path $env:USERPROFILE "OneDrive"
$save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $save) { throw "SaveData1.sav not found" }
$bytes = [System.IO.File]::ReadAllBytes($save.FullName)
$out = "D:\Unpacking game\OctopathTrackerOutput\treasure_region_hex.txt"
$start = 0x00132700
$len = 0x1400
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Save: $($save.FullName)")
$lines.Add(("Region: 0x{0:X8} len 0x{1:X}" -f $start, $len))
for ($o = $start; $o -lt [Math]::Min($bytes.Length, $start + $len); $o += 16) {
  $hex = New-Object System.Collections.Generic.List[string]
  $asc = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt 16 -and ($o + $i) -lt $bytes.Length; $i++) {
    $b = $bytes[$o + $i]
    $hex.Add($b.ToString("X2"))
    if ($b -ge 32 -and $b -le 126) { [void]$asc.Append([char]$b) } else { [void]$asc.Append(".") }
  }
  $lines.Add(("{0:X8}: {1,-47} {2}" -f $o, ($hex -join " "), $asc.ToString()))
}
[System.IO.File]::WriteAllLines($out, $lines, [System.Text.Encoding]::UTF8)
Write-Host $out
