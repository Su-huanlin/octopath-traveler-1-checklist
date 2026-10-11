$ErrorActionPreference = "Stop"

$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
$BeforePath = Join-Path $OutDir "before.sav"
$AfterPath = Join-Path $OutDir "after.sav"
$OutCsv = Join-Path $OutDir "treasure_save_diff.csv"
$OutTxt = Join-Path $OutDir "treasure_save_diff.txt"

function FindSave([string]$Name) {
  $oneDrive = Join-Path $env:USERPROFILE "OneDrive"
  $save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter $Name -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($null -eq $save) { return $null }
  return $save.FullName
}

if (!(Test-Path -LiteralPath $BeforePath)) {
  $auto = FindSave "SaveData0.sav"
  if ($auto) { $BeforePath = $auto }
}
if (!(Test-Path -LiteralPath $AfterPath)) {
  $auto = FindSave "SaveData1.sav"
  if ($auto) { $AfterPath = $auto }
}
if (!(Test-Path -LiteralPath $BeforePath)) { throw "Missing before save. Put before.sav in $OutDir" }
if (!(Test-Path -LiteralPath $AfterPath)) { throw "Missing after save. Put after.sav in $OutDir" }

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
  return @{ size = [int]$size; data_start = $dataStart; data = $data }
}

function ExtractTreasureArrays([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $hits = FindAscii $bytes "TreasureStateArray_"
  $arrays = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $hits.Count; $i++) {
    $arr = ParseByteArray $bytes $hits[$i]
    $arrays.Add([pscustomobject]@{
      index = $i
      name_offset = $hits[$i]
      data_start = $arr.data_start
      size = $arr.size
      data = $arr.data
    })
  }
  return $arrays
}

$before = ExtractTreasureArrays $BeforePath
$after = ExtractTreasureArrays $AfterPath
$rows = New-Object System.Collections.Generic.List[object]
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Before: $BeforePath")
$lines.Add("After : $AfterPath")
$lines.Add("Before arrays: $($before.Count)")
$lines.Add("After arrays : $($after.Count)")
$lines.Add("")

$count = [Math]::Min($before.Count, $after.Count)
for ($i = 0; $i -lt $count; $i++) {
  $b = $before[$i]
  $a = $after[$i]
  $size = [Math]::Min($b.size, $a.size)
  for ($j = 0; $j -lt $size; $j++) {
    $bv = $b.data[$j]
    $av = $a.data[$j]
    if ($bv -ne $av) {
      $slot = $j - 6
      $direction = if ($bv -eq 0 -and $av -eq 1) { "opened_or_set" } elseif ($bv -eq 1 -and $av -eq 0) { "cleared" } else { "changed" }
      $rows.Add([pscustomobject]@{
        state_index = $i
        byte_index = $j
        treasure_slot_guess = $slot
        before = $bv
        after = $av
        direction = $direction
        before_offset = ("0x{0:X8}" -f ($b.data_start + $j))
        after_offset = ("0x{0:X8}" -f ($a.data_start + $j))
      })
    }
  }
}

$rows | Export-Csv -LiteralPath $OutCsv -NoTypeInformation -Encoding UTF8
foreach ($r in $rows) {
  $lines.Add(("state_index={0} byte_index={1} slot_guess={2} {3}->{4} {5}" -f $r.state_index, $r.byte_index, $r.treasure_slot_guess, $r.before, $r.after, $r.direction))
}
[System.IO.File]::WriteAllLines($OutTxt, $lines, [System.Text.Encoding]::UTF8)
Write-Host "CSV: $OutCsv"
Write-Host "TXT: $OutTxt"
Write-Host "Changes: $($rows.Count)"
