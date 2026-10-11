$ErrorActionPreference = "Stop"
$SavePath = "D:\Unpacking game\SaveData1.sav"
$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
if (!(Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$OutFile = Join-Path $OutDir "save_enemy_probe.txt"
$lines = New-Object System.Collections.Generic.List[string]

function FindAscii($Bytes, [string]$Needle) {
  $hits = New-Object System.Collections.Generic.List[int]
  $pat = [System.Text.Encoding]::ASCII.GetBytes($Needle)
  for ($i = 0; $i -le $Bytes.Length - $pat.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $pat.Length; $j++) {
      if ($Bytes[$i + $j] -ne $pat[$j]) { $ok = $false; break }
    }
    if ($ok) { $hits.Add($i) | Out-Null }
  }
  return $hits
}

$bytes = [System.IO.File]::ReadAllBytes($SavePath)
$lines.Add("save size: $($bytes.Length) bytes")

# Common UE4 save keywords that might hold enemy bestiary data:
$candidates = @(
  "Enemy", "Beast", "Bestiary", "Encyclo", "Monster", "Capture", "Catalog",
  "EnemyData", "EnemyState", "EnemyBookState", "EnemyEncyclopedia",
  "MonsterData", "MonsterState", "BeastState", "BookState",
  "WeaknessState", "WeakState", "Library", "Knowledge",
  "Picture",        # JP-style "ＥＮＥ図鑑"
  "GetEnemy", "BookArray", "EnemyArray",
  "EnemyWeakness", "WeakArray", "Resistance",
  "TameEnemy", "TamedEnemy", "Tame",
  "RealName", "HearInfo", "HearState"
)
foreach ($needle in $candidates) {
  $hits = FindAscii $bytes $needle
  $lines.Add(("{0,-25} hits: {1}" -f $needle, $hits.Count))
  if ($hits.Count -gt 0 -and $hits.Count -lt 20) {
    foreach ($h in $hits) { $lines.Add(("  offset=0x{0:X}" -f $h)) }
  }
}

# Also dump all ASCII tokens (>=4 printable chars) that look like UE4 property names containing "Enemy" or "Bestiary"
$lines.Add("")
$lines.Add("=== Searching for printable tokens containing 'Enemy' or 'Beast' ===")
$pattern = [regex]"[A-Za-z][A-Za-z0-9_]{3,40}"
$ascii = [System.Text.Encoding]::ASCII.GetString($bytes)
$seen = @{}
foreach ($m in $pattern.Matches($ascii)) {
  $tok = $m.Value
  if ($tok -match "(?i)(enemy|beast|bestiar|monster|tame|catalog|encyc|weak|resist)") {
    if (!$seen.ContainsKey($tok)) {
      $seen[$tok] = $m.Index
      $lines.Add(("  {0} @ 0x{1:X}" -f $tok, $m.Index))
      if ($seen.Count -ge 200) { break }
    }
  }
}

[System.IO.File]::WriteAllLines($OutFile, $lines)
Write-Host "Wrote $OutFile"
