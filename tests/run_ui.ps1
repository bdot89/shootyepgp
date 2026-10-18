# Runs the offline tests through DmorphOcto's LuaHost with OctoBG's mock 1.12
# client: tests\ui_test.lua (the new window, with stand-ins for the addon) and
# tests\load_test.lua (the REAL addon: every .toc file and its Ace2 libraries
# load and log in). Pair it with OctoBG\tools\LuaCheck.ps1 (LuaJIT accepts #,
# % and ... that Lua 5.0 does not).
#   powershell -ExecutionPolicy Bypass -File tests\run_ui.ps1
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$exe = Join-Path $root "..\DmorphOcto\tools\LuaHost\bin\LuaHost.exe"
if (-not (Test-Path $exe)) { throw "LuaHost not built: run DmorphOcto\tools\run_tests.ps1 once" }
Push-Location $root
try {
  & $exe "tests/ui_test.lua"
  $a = $LASTEXITCODE
  & $exe "tests/load_test.lua"
  $b = $LASTEXITCODE
  if ($a -ne 0 -or $b -ne 0) { exit 1 }
  exit 0
} finally { Pop-Location }
