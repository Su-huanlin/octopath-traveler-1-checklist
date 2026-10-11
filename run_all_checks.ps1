# UTF-8 output for Chinese text in console
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$base = "D:\Unpacking game"
$out  = Join-Path $base "OctopathTrackerOutput"
$htmlPath = Join-Path $out "octopath_tracker_portable.html"
$logPath = Join-Path $out "run_all_checks_log.txt"

function Log([string]$Msg) {
  Write-Host $Msg
  Add-Content -LiteralPath $logPath -Value $Msg -Encoding UTF8
}

if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath -Force }
Log "========== generate_portable_tracker.ps1 =========="
try {
  $genOut = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $base "generate_portable_tracker.ps1") 2>&1
  foreach ($line in @($genOut)) { Log $line }
} catch {
  Log ("ERROR: " + $_.Exception.Message)
}

Log ""
Log "========== town_check.txt =========="
$tc = Join-Path $out "town_check.txt"
if (Test-Path -LiteralPath $tc) { Get-Content -LiteralPath $tc -Encoding UTF8 | ForEach-Object { Log $_ } }
else { Log "MISSING town_check.txt" }

Log ""
Log "========== spot checks =========="
$html = Get-Content -LiteralPath $htmlPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
if ($html -match "(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})") { Log ("generatedAt: " + $Matches[1]) }

foreach ($oid in @("TrsrBx_Mount_D11_01", "TrsrBx_Mount_D11_05")) {
  if ($html -match ('"' + [regex]::Escape($oid) + '"[^}]*"position_label"\s*:\s*"([^"]*)"')) {
    Log ("$oid position_label=" + $Matches[1])
  } else { Log ("$oid NOT FOUND") }
}

if ($html -match "clusterHitsByGap" -and $html -match "gvasWeaknessMaskAt") {
  Log "OK: IsAnalyse cluster weakness parser present"
} else {
  Log "WARN: old/broken enemy parser may still be in HTML"
}

if ($html -match "D_Forest_2_Job[^}]*nearest_town_name`":`"([^`"]+)`"") {
  Log ("D_Forest_2_Job nearest_town=" + $Matches[1])
}

Log ""
Log "========== enemy save verify =========="
$verifyJs = Join-Path $out "verify_enemy_save.js"
if (Get-Command node -ErrorAction SilentlyContinue) {
  $nodeOut = & node $verifyJs 2>&1
  foreach ($line in @($nodeOut)) { Log $line }
} else {
  Log "node not installed - skipped verify_enemy_save.js"
  Log "Install Node.js OR open HTML and load save to check weakness counts manually."
}

Log ""
Log "Done. Full log: $logPath"
