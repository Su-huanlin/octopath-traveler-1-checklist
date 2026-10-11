$ErrorActionPreference = "Stop"

$OutDir = "D:\Unpacking game\OctopathTrackerOutput"
$OutFile = Join-Path $OutDir "save_probe.txt"

if (!(Test-Path -LiteralPath $OutDir)) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

function HexLine([byte[]]$Bytes, [int]$Offset, [int]$Count) {
  $end = [Math]::Min($Bytes.Length, $Offset + $Count)
  $parts = New-Object System.Collections.Generic.List[string]
  for ($i = $Offset; $i -lt $end; $i++) {
    $parts.Add($Bytes[$i].ToString("X2"))
  }
  return ("{0:X8}: {1}" -f $Offset, ($parts -join " "))
}

function ExtractAsciiStrings([byte[]]$Bytes, [int]$MinLen) {
  $result = New-Object System.Collections.Generic.List[object]
  $start = -1
  for ($i = 0; $i -lt $Bytes.Length; $i++) {
    $b = $Bytes[$i]
    $ok = ($b -ge 32 -and $b -le 126)
    if ($ok) {
      if ($start -lt 0) { $start = $i }
    } else {
      if ($start -ge 0 -and ($i - $start) -ge $MinLen) {
        $text = [System.Text.Encoding]::ASCII.GetString($Bytes, $start, $i - $start)
        $result.Add([pscustomobject]@{ offset = $start; text = $text })
      }
      $start = -1
    }
  }
  if ($start -ge 0 -and ($Bytes.Length - $start) -ge $MinLen) {
    $text = [System.Text.Encoding]::ASCII.GetString($Bytes, $start, $Bytes.Length - $start)
    $result.Add([pscustomobject]@{ offset = $start; text = $text })
  }
  return $result
}

function ExtractUtf16LeStrings([byte[]]$Bytes, [int]$MinLen) {
  $result = New-Object System.Collections.Generic.List[object]
  $start = -1
  $chars = New-Object System.Collections.Generic.List[byte]
  for ($i = 0; $i -lt ($Bytes.Length - 1); $i += 2) {
    $b = $Bytes[$i]
    $z = $Bytes[$i + 1]
    $ok = ($z -eq 0 -and $b -ge 32 -and $b -le 126)
    if ($ok) {
      if ($start -lt 0) { $start = $i }
      $chars.Add($b)
    } else {
      if ($start -ge 0 -and $chars.Count -ge $MinLen) {
        $text = [System.Text.Encoding]::ASCII.GetString($chars.ToArray())
        $result.Add([pscustomobject]@{ offset = $start; text = $text })
      }
      $start = -1
      $chars.Clear()
    }
  }
  if ($start -ge 0 -and $chars.Count -ge $MinLen) {
    $text = [System.Text.Encoding]::ASCII.GetString($chars.ToArray())
    $result.Add([pscustomobject]@{ offset = $start; text = $text })
  }
  return $result
}

$oneDrive = Join-Path $env:USERPROFILE "OneDrive"
$candidates = @()
if (Test-Path -LiteralPath $oneDrive) {
  $candidates = @(Get-ChildItem -LiteralPath $oneDrive -Recurse -Filter "SaveData1.sav" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*Octopath_Traveler*" } |
    Sort-Object LastWriteTime -Descending)
}
if ($candidates.Count -eq 0) {
  throw "Could not find SaveData1.sav under OneDrive. Please copy SaveData1.sav to D:\Unpacking game\OctopathTrackerOutput and rerun."
}
$SavePath = $candidates[0].FullName

$bytes = [System.IO.File]::ReadAllBytes($SavePath)
$sha1 = [System.Security.Cryptography.SHA1]::Create()
$hash = [BitConverter]::ToString($sha1.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()

$ascii = ExtractAsciiStrings $bytes 4
$utf16 = ExtractUtf16LeStrings $bytes 4
$keywords = @(
  "TrsrBx", "HdnPnt", "ITM_", "Object", "Treasure", "Chest", "Hidden",
  "Flag", "Map", "Enemy", "Weak", "Item", "Open", "Save", "Game"
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Save probe")
$lines.Add("SavePath: $SavePath")
$lines.Add("Size: $($bytes.Length)")
$lines.Add("SHA1: $hash")
$lines.Add("")
$lines.Add("First 512 bytes:")
for ($o = 0; $o -lt [Math]::Min(512, $bytes.Length); $o += 16) {
  $lines.Add((HexLine $bytes $o 16))
}

$lines.Add("")
$lines.Add("ASCII string count: $($ascii.Count)")
$lines.Add("UTF16LE ascii-compatible string count: $($utf16.Count)")

$lines.Add("")
$lines.Add("Keyword matches in ASCII strings:")
foreach ($kw in $keywords) {
  $matches = @($ascii | Where-Object { $_.text -like "*$kw*" } | Select-Object -First 30)
  $lines.Add("[$kw] count~ $(@($ascii | Where-Object { $_.text -like "*$kw*" }).Count)")
  foreach ($m in $matches) {
    $lines.Add(("  0x{0:X8}: {1}" -f $m.offset, $m.text))
  }
}

$lines.Add("")
$lines.Add("Keyword matches in UTF16LE strings:")
foreach ($kw in $keywords) {
  $matches = @($utf16 | Where-Object { $_.text -like "*$kw*" } | Select-Object -First 30)
  $lines.Add("[$kw] count~ $(@($utf16 | Where-Object { $_.text -like "*$kw*" }).Count)")
  foreach ($m in $matches) {
    $lines.Add(("  0x{0:X8}: {1}" -f $m.offset, $m.text))
  }
}

$lines.Add("")
$lines.Add("First 200 ASCII strings:")
foreach ($s in ($ascii | Select-Object -First 200)) {
  $lines.Add(("  0x{0:X8}: {1}" -f $s.offset, $s.text))
}

$lines.Add("")
$lines.Add("First 200 UTF16LE strings:")
foreach ($s in ($utf16 | Select-Object -First 200)) {
  $lines.Add(("  0x{0:X8}: {1}" -f $s.offset, $s.text))
}

[System.IO.File]::WriteAllLines($OutFile, $lines, [System.Text.Encoding]::UTF8)
Write-Host "Done"
Write-Host "Output: $OutFile"
