$ErrorActionPreference = "Stop"

$oneDrive = Join-Path $env:USERPROFILE "OneDrive"
$save = Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1
if ($null -eq $save) { throw "SaveData1.sav not found" }

$bytes = [System.IO.File]::ReadAllBytes($save.FullName)
$out = "D:\Unpacking game\OctopathTrackerOutput\treasure_arrays_summary.csv"
$txt = "D:\Unpacking game\OctopathTrackerOutput\treasure_arrays_summary.txt"

function ReadI32([byte[]]$b, [int]$o) {
  return [BitConverter]::ToInt32($b, $o)
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

function HexBytes([byte[]]$Bytes, [int]$Offset, [int]$Count) {
  $parts = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $Count -and ($Offset + $i) -lt $Bytes.Length; $i++) {
    $parts.Add($Bytes[$Offset + $i].ToString("X2"))
  }
  return ($parts -join " ")
}

function BitCount([byte[]]$Bytes, [int]$Offset, [int]$Count) {
  $n = 0
  for ($i = 0; $i -lt $Count -and ($Offset + $i) -lt $Bytes.Length; $i++) {
    $v = $Bytes[$Offset + $i]
    for ($bit = 0; $bit -lt 8; $bit++) {
      if (($v -band (1 -shl $bit)) -ne 0) { $n++ }
    }
  }
  return $n
}

function PrevAsciiStrings([byte[]]$Bytes, [int]$Offset, [int]$Window) {
  $start = [Math]::Max(0, $Offset - $Window)
  $result = New-Object System.Collections.Generic.List[string]
  $s = -1
  for ($i = $start; $i -lt $Offset; $i++) {
    $c = $Bytes[$i]
    if ($c -ge 32 -and $c -le 126) {
      if ($s -lt 0) { $s = $i }
    } else {
      if ($s -ge 0 -and ($i - $s) -ge 4) {
        $result.Add([System.Text.Encoding]::ASCII.GetString($Bytes, $s, $i - $s))
      }
      $s = -1
    }
  }
  return ($result -join " | ")
}

$hits = FindAscii $bytes "TreasureStateArray_"
$rows = New-Object System.Collections.Generic.List[object]
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Save: $($save.FullName)")
$lines.Add("TreasureStateArray hits: $($hits.Count)")
$lines.Add("")

for ($idx = 0; $idx -lt $hits.Count; $idx++) {
  $hit = $hits[$idx]
  $nameLenOffset = $hit - 4
  $nameLen = ReadI32 $bytes $nameLenOffset
  $typeLenOffset = $hit + $nameLen
  $typeLen = ReadI32 $bytes $typeLenOffset
  $typeStart = $typeLenOffset + 4
  $type = [System.Text.Encoding]::ASCII.GetString($bytes, $typeStart, $typeLen - 1)
  $sizeOffset = $typeStart + $typeLen
  $size = [BitConverter]::ToInt64($bytes, $sizeOffset)
  $innerLenOffset = $sizeOffset + 8
  $innerLen = ReadI32 $bytes $innerLenOffset
  $innerStart = $innerLenOffset + 4
  $inner = [System.Text.Encoding]::ASCII.GetString($bytes, $innerStart, $innerLen - 1)
  $dataStart = $innerStart + $innerLen
  $dataHex = HexBytes $bytes $dataStart ([Math]::Min([int]$size, 24))
  $opened = BitCount $bytes $dataStart ([int]$size)
  $prev = PrevAsciiStrings $bytes $hit 260

  $rows.Add([pscustomobject]@{
    index = $idx
    offset_hex = ("0x{0:X8}" -f $hit)
    size = $size
    opened_bits = $opened
    data_hex = $dataHex
    prev_strings = $prev
  })

  if ($idx -lt 80) {
    $lines.Add(("index={0} offset=0x{1:X8} size={2} opened_bits={3}" -f $idx, $hit, $size, $opened))
    $lines.Add(("  type={0} inner={1}" -f $type, $inner))
    $lines.Add(("  data={0}" -f $dataHex))
    $lines.Add(("  prev={0}" -f $prev))
  }
}

$rows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
[System.IO.File]::WriteAllLines($txt, $lines, [System.Text.Encoding]::UTF8)
Write-Host "CSV: $out"
Write-Host "TXT: $txt"
