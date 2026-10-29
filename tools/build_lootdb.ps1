# Builds loot_db.lua (the Prices topic's raids, bosses and items) from an
# AtlasLoot copy, once. The addon never needs AtlasLoot itself.
#   powershell -ExecutionPolicy Bypass -File tools\build_lootdb.ps1 -AtlasLoot <AtlasLoot folder>
# AtlasLoot = the Turtle AtlasLoot (same boss keys as the guild site's catalog).
param(
  [Parameter(Mandatory = $true)][string]$AtlasLoot,
  [string]$Out
)
$ErrorActionPreference = "Stop"
if (-not $Out) { $Out = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\loot_db.lua" }
$src = Join-Path $AtlasLoot "Database\Instances.lua"
if (-not (Test-Path $src)) { throw "no Database\Instances.lua in $AtlasLoot" }

# raid key, name in the window, its header in prices.lua, tier for new prices,
# then boss key = name (names as on the guild site)
$raids = @(
  @{ key = "MC"; name = "Molten Core"; section = "Molten Core"; tier = "T1"; bosses = @(
    "MCIncindis=Incindis", "MCLucifron=Lucifron", "MCMagmadar=Magmadar", "MCGarr=Garr", "MCGeddon=Baron Geddon",
    "MCShazzrah=Shazzrah", "MCSulfuron=Sulfuron Harbinger", "MCGolemagg=Golemagg the Incinerator",
    "MCTwins=Basalthar & Smoldaris", "MCThaurissan=Sorcerer-Thane Thaurissan", "MCMajordomo=Majordomo Executus",
    "MCRagnaros=Ragnaros", "MCTrashMobs=Trash Mobs") },
  @{ key = "ONY"; name = "Onyxia's Lair"; section = "Onyxia's Lair"; tier = "T2"; bosses = @(
    "Axelus=Broodcommander Axelus", "Onyxia=Onyxia") },
  @{ key = "BWL"; name = "Blackwing Lair"; section = "Blackwing Lair"; tier = "T2"; bosses = @(
    "BWLRazorgore=Razorgore the Untamed", "BWLVaelastrasz=Vaelastrasz the Corrupt", "BWLLashlayer=Broodlord Lashlayer",
    "BWLFiremaw=Firemaw", "BWLEzzel=Ezzel Darkbrewer", "BWLEbonroc=Ebonroc", "BWLFlamegor=Flamegor",
    "BWLChromaggus=Chromaggus", "BWLNefarian=Nefarian", "BWLTrashMobs=Trash Mobs") },
  @{ key = "AQ40"; name = "Temple of Ahn'Qiraj"; section = "Temple of Ahn'Qiraj"; tier = "T2.5"; bosses = @(
    "AQ40Skeram=The Prophet Skeram", "AQ40Trio=The Bug Family", "AQ40Sartura=Battleguard Sartura",
    "AQ40Fankriss=Fankriss the Unyielding", "AQ40Viscidus=Viscidus", "AQ40Huhuran=Princess Huhuran",
    "AQ40Emperors=The Twin Emperors", "AQ40Ouro=Ouro", "AQ40CThun=C'Thun", "AQ40Trash1=Trash Mobs", "T25SET=Tier 2.5 Sets") },
  @{ key = "NAXX"; name = "Naxxramas"; section = "Naxxramas"; tier = "T3"; bosses = @(
    "NAXPatchwerk=Patchwerk", "NAXGrobbulus=Grobbulus", "NAXGluth=Gluth", "NAXThaddius=Thaddius",
    "NAXAnubRekhan=Anub'Rekhan", "NAXGrandWidowFaerlina=Grand Widow Faerlina", "NAXMaexxna=Maexxna",
    "NAXNoththePlaguebringer=Noth the Plaguebringer", "NAXHeigantheUnclean=Heigan the Unclean", "NAXLoatheb=Loatheb",
    "NAXInstructorRazuvious=Instructor Razuvious", "NAXGothiktheHarvester=Gothik the Harvester",
    "NAXTheFourHorsemen=The Four Horsemen", "NAXSapphiron=Sapphiron", "NAXKelThuzard=Kel'Thuzad", "NAXTrash=Trash Mobs", "T3SET=Tier 3 Sets") },
  @{ key = "KARA40"; name = "Tower of Karazhan"; section = "Upper Karazhan Halls"; tier = "T3.5"; bosses = @(
    "UKHGnarlmoon=Keeper Gnarlmoon", "UKHIncantagos=Ley-Watcher Incantagos", "UKHAnomalus=Anomalus",
    "UKHEcho=Echo of Medivh", "UKHKing=King (Chess fight)", "UKHSanvTasdal=Sanv Tas'dal",
    "UKHRupturan=Rupturan the Broken", "UKHKruul=Kruul", "UKHMephistroth=Mephistroth", "UKHTrash=Trash Mobs") }
)

$lines = [IO.File]::ReadAllLines($src, [Text.Encoding]::UTF8)
# boss key -> line where its table starts
$start = @{}
for ($i = 0; $i -lt $lines.Length; $i++) {
  if ($lines[$i] -match '^\t([A-Za-z0-9_]+) = \{') { if (-not $start.ContainsKey($Matches[1])) { $start[$Matches[1]] = $i } }
}
function Q([string]$s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }

# icon / quality / name of every item AtlasLoot lists anywhere (set tables only give ids)
$known = @{}
foreach ($f in (Get-ChildItem (Join-Path $AtlasLoot "Database") -Filter *.lua)) {
  foreach ($m in [regex]::Matches([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8), '\{ (\d+), "([^"=]*)", "=q(\d+)=((?:[^"\\]|\\.)*)"')) {
    $id = $m.Groups[1].Value
    if (-not $known.ContainsKey($id)) { $known[$id] = "{ $(Q $m.Groups[2].Value), $([int]$m.Groups[3].Value), $(Q ($m.Groups[4].Value -replace '\\"', '"')) }" }
  }
}
$pricesLines = [IO.File]::ReadAllLines((Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\prices.lua")))

$items = @{}
$sb = New-Object Text.StringBuilder
[void]$sb.Append("-- shootyepgp :: raids, bosses and their loot for the Prices topic.`n")
[void]$sb.Append("-- Made by tools\build_lootdb.ps1 from AtlasLoot - do not edit by hand.`n")
[void]$sb.Append("-- items[id] = { icon, quality, name }`n")
[void]$sb.Append("sepgp_lootdb = {`n  raids = {`n")
foreach ($r in $raids) {
  [void]$sb.Append("    { key = $(Q $r.key), name = $(Q $r.name), section = $(Q $r.section), tier = $(Q $r.tier), bosses = {`n")
  foreach ($b in $r.bosses) {
    $k, $n = $b -split '=', 2
    $ids = New-Object Collections.ArrayList
    if ($k -match 'SET$') {
      # set pieces hang under tokens in AtlasLoot: take prices.lua's own "--Tier x Sets" block
      $in = $false
      foreach ($pl in $pricesLines) {
        if ($pl -eq "--$n") { $in = $true; continue }
        if ($in) {
          if ($pl -notmatch '^\[(\d+)\]') { break }
          $id = $Matches[1]
          if (-not $known.ContainsKey($id)) { throw "no icon for set piece $id" }
          [void]$ids.Add([int]$id)
          $items[$id] = $known[$id]
        }
      }
      [void]$sb.Append("      { key = $(Q $k), name = $(Q $n), items = { $($ids -join ', ') } },`n")
      continue
    }
    if (-not $start.ContainsKey($k)) { throw "AtlasLoot has no boss table $k" }
    for ($i = $start[$k] + 1; $i -lt $lines.Length -and $lines[$i] -notmatch '^\t\},?\s*$'; $i++) {
      # top-level item rows only (nested rows are variants)
      if ($lines[$i] -match '^\t\t\{ (\d+), "([^"]*)", "=q(\d+)=((?:[^"\\]|\\.)*)"') {
        $id = [int]$Matches[1]
        if ($id -le 0) { continue }
        if ($ids -notcontains $id) { [void]$ids.Add($id) }
        if (-not $items.ContainsKey("$id")) {
          $name = $Matches[4] -replace '\\"', '"'
          $items["$id"] = "{ $(Q $Matches[2]), $([int]$Matches[3]), $(Q $name) }"
        }
      }
    }
    [void]$sb.Append("      { key = $(Q $k), name = $(Q $n), items = { $($ids -join ', ') } },`n")
  }
  [void]$sb.Append("    } },`n")
}
[void]$sb.Append("  },`n  items = {`n")
foreach ($id in ($items.Keys | Sort-Object { [int]$_ })) { [void]$sb.Append("    [$id] = $($items[$id]),`n") }
[void]$sb.Append("  },`n}`n")
[IO.File]::WriteAllText((Resolve-Path (Split-Path $Out)).Path + "\" + (Split-Path $Out -Leaf), $sb.ToString(), (New-Object Text.UTF8Encoding $false))
Write-Host ("loot_db.lua: " + $items.Count + " items")
