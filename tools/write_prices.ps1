# Writes price changes into prices.lua, in its own layout:
#   [16900] = {175,"T2"}; --Stormrage Cover
# under the raid header and the boss comment the item drops from (loot_db.lua).
# A price already in the file is changed in place; a new one goes at the end
# of its boss's block (a missing boss block or raid header is made, in raid order).
#
# Where the changes come from:
#   -SavedVariables <file>  officers' in-game edits (Prices topic -> Edit prices),
#                           i.e. WTF\Account\<ACCOUNT>\SavedVariables\shootyepgp.lua
#                           (default: every account's file under ..\..\..\WTF)
#   -List <file>            "id:price" pairs, separated by commas or new lines
# Log out (or /reload) first: WoW writes SavedVariables only then.
#   powershell -ExecutionPolicy Bypass -File tools\write_prices.ps1
#   powershell -ExecutionPolicy Bypass -File tools\write_prices.ps1 -List prices.txt -WhatIf
param(
  [string]$SavedVariables,
  [string]$List,
  [switch]$WhatIf
)
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$pricesPath = Join-Path $root "prices.lua"
$dbPath = Join-Path $root "loot_db.lua"

# ---------------------------------------------------------------- the changes
$edits = [ordered]@{}
$when = @{}
if ($List) {
  foreach ($m in [regex]::Matches([IO.File]::ReadAllText((Resolve-Path $List)), '(\d+)\s*:\s*(\d+)')) {
    $edits[$m.Groups[1].Value] = [int]$m.Groups[2].Value
  }
} else {
  $files = @()
  if ($SavedVariables) { $files = @(Resolve-Path $SavedVariables) }
  else {
    $wtf = Join-Path $root "..\..\..\WTF\Account"
    if (Test-Path $wtf) { $files = @(Get-ChildItem $wtf -Recurse -Filter shootyepgp.lua | ?{ $_.Directory.Name -eq "SavedVariables" } | %{ $_.FullName }) }
  }
  if ($files.Count -eq 0) { throw "no SavedVariables\shootyepgp.lua found - pass -SavedVariables <file>" }
  foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f)
    # sepgp_price_edits = { [id] = { ["gp"] = 175, ["by"] = "Name", ["at"] = 123 }, ... }
    $m = [regex]::Match($text, '(?ms)^sepgp_price_edits = \{(.*?)^\}')
    if (-not $m.Success) { continue }
    foreach ($e in [regex]::Matches($m.Groups[1].Value, '\[(\d+)\] = \{[^}]*\["gp"\] = (\d+)[^}]*\["at"\] = (\d+)|\[(\d+)\] = \{[^}]*\["at"\] = (\d+)[^}]*\["gp"\] = (\d+)')) {
      $id = if ($e.Groups[1].Success) { $e.Groups[1].Value } else { $e.Groups[4].Value }
      $gp = if ($e.Groups[1].Success) { [int]$e.Groups[2].Value } else { [int]$e.Groups[6].Value }
      $at = if ($e.Groups[1].Success) { [int]$e.Groups[3].Value } else { [int]$e.Groups[5].Value }
      # several officers' files: the newest edit wins
      if (-not $edits.Contains($id) -or $at -gt $when[$id]) { $edits[$id] = $gp; $when[$id] = $at }
    }
    Write-Host "read $f"
  }
}
if ($edits.Count -eq 0) { Write-Host "no price changes found"; exit 0 }

# ---------------------------------------------------------------- where items drop
$raids = New-Object Collections.ArrayList
$names = @{}
$cur = $null
foreach ($l in [IO.File]::ReadAllLines($dbPath, [Text.Encoding]::UTF8)) {
  if ($l -match '^    \{ key = "([^"]+)", name = "([^"]+)", section = "([^"]+)", tier = "([^"]+)"') {
    $cur = @{ key = $Matches[1]; section = $Matches[3]; tier = $Matches[4]; bosses = New-Object Collections.ArrayList }
    [void]$raids.Add($cur)
  } elseif ($l -match '^      \{ key = "[^"]+", name = "((?:[^"\\]|\\.)*)", items = \{ ([\d, ]*) \} \}') {
    [void]$cur.bosses.Add(@{ name = ($Matches[1] -replace '\\"', '"'); items = @($Matches[2] -split ', ' | ?{ $_ }) })
  } elseif ($l -match '^    \[(\d+)\] = \{ "[^"]*", \d+, "((?:[^"\\]|\\.)*)" \}') {
    $names[$Matches[1]] = $Matches[2] -replace '\\"', '"'
  }
}
function Home($id) {
  for ($ri = 0; $ri -lt $raids.Count; $ri++) {
    $r = $raids[$ri]
    for ($bi = 0; $bi -lt $r.bosses.Count; $bi++) {
      $k = [array]::IndexOf($r.bosses[$bi].items, "$id")
      if ($k -ge 0) { return @{ raid = $r; boss = $r.bosses[$bi]; order = ($ri * 1000 + $bi) * 1000 + $k } }
    }
  }
  return $null
}

# ---------------------------------------------------------------- the file
$lines = New-Object Collections.ArrayList
[void]$lines.AddRange([IO.File]::ReadAllLines($pricesPath, [Text.Encoding]::UTF8))
$changed, $added, $skipped = 0, 0, @()
function Header($section) {
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -eq "--- $section ---") { return $i } }
  return -1
}
# end of a raid section: the line before the next header's dashes, or the table's closing brace
function SectionEnd($h) {
  for ($i = $h + 2; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^--- .+ ---$') { return $i - 1 }
    if ($lines[$i] -eq '}') { return $i }
  }
  return $lines.Count
}
function Dashes($s) { '-' * ($s.Length + 8) }

# new entries in raid / boss / AtlasLoot order, so their blocks come out in that order
$order = @{}
foreach ($id in @($edits.Keys)) { $hm = Home $id; $order[$id] = if ($hm) { $hm.order } else { [int]::MaxValue } }
foreach ($id in (@($edits.Keys) | Sort-Object { $order[$_] })) {
  $gp = $edits[$id]
  $at = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match "^\[$id\] = \{") { $at = $i; break } }
  if ($at -ge 0) {
    $new = $lines[$at] -replace '^(\[\d+\] = \{)\d+(,)', "`${1}$gp`$2"
    if ($new -ne $lines[$at]) { Write-Host "  $($lines[$at])  ->  $gp"; $lines[$at] = $new; $changed++ }
    continue
  }
  $where = Home $id
  if (-not $where) { $skipped += $id; continue }
  $r, $b = $where.raid, $where.boss
  $h = Header $r.section
  if ($h -lt 0) {
    # a new raid section, placed before the first raid that comes after it
    $ri = $raids.IndexOf($r)
    $before = -1
    for ($j = $ri + 1; $j -lt $raids.Count -and $before -lt 0; $j++) { $x = Header $raids[$j].section; if ($x -ge 0) { $before = $x - 1 } }
    if ($before -lt 0) { $before = SectionEnd 0; for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -eq '}') { $before = $i; break } } }
    $block = @((Dashes $r.section), "--- $($r.section) ---", (Dashes $r.section), "", "")
    $lines.InsertRange($before, [string[]]$block)
    $h = $before + 1
  }
  $end = SectionEnd $h
  $bi = -1
  for ($i = $h; $i -le $end -and $i -lt $lines.Count; $i++) { if ($lines[$i] -eq "--$($b.name)") { $bi = $i; break } }
  if ($bi -lt 0) {
    # a new boss block at the end of the raid section (after its last entry)
    $last = $end
    while ($last -gt $h + 1 -and ($lines[$last] -eq '' -or $lines[$last] -eq '}' -or $lines[$last] -match '^-+$')) { $last-- }
    $lines.InsertRange($last + 1, [string[]]@("", "--$($b.name)"))
    $bi = $last + 2
  }
  $ins = $bi + 1
  while ($ins -lt $lines.Count -and $lines[$ins] -match '^\[') { $ins++ }
  $name = $names[$id]
  $line = "[$id] = {$gp,`"$($r.tier)`"}; --$name"
  $lines.Insert($ins, $line)
  Write-Host "  + $line   ($($r.section) / $($b.name))"
  $added++
}
if ($skipped.Count -gt 0) { Write-Host ("not in any raid of loot_db.lua, left out: " + ($skipped -join ', ')) }
Write-Host "$changed changed, $added added"
if ($WhatIf) { Write-Host "(-WhatIf: prices.lua not written)"; exit 0 }
if ($changed + $added -gt 0) {
  [IO.File]::WriteAllText($pricesPath, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))
  Write-Host "prices.lua written. In game, the edits that are now in prices.lua clear themselves after the next /reload."
}
