-- Smoke test: the real shootyepgp (every file in the .toc, real Ace2 libraries)
-- loads in the mock client and logs in without errors.
dofile("../OctoBG/tests/mock.lua")
Mock.raid, Mock.party = 0, 0
TEXT = function(s) return s end
YES, NO, OKAY, ACCEPT, CANCEL, CLOSE = "Yes", "No", "Okay", "Accept", "Cancel", "Close"
ITEM_QUALITY_COLORS = {}
for i = -1, 6 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0, g = 0, b = 0 }
RAID_CLASS_COLORS = {}
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.12.1", "5875", "Sep 19 2006", 11200 end
GetNumAddOns = function() return 1 end
GetAddOnInfo = function(i) return "shootyepgp", "shootyepgp", "", 1, 1, nil end
IsAddOnLoaded = function(n) return n == "shootyepgp" or n == 1 end
EnumerateFrames = function() return nil end
debugstack = function() return "x\nInterface\\AddOns\\shootyepgp\\shootyepgp.lua:1: in main chunk\n" end
FACTION_HORDE, FACTION_ALLIANCE, PLAYER_OF_REALM = "Horde", "Alliance", "%s of %s"
YOU = "You"
LOOT_ITEM, LOOT_ITEM_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "%s receives loot: %s.", "%s receives loot: %sx%d.", "You receive loot: %s.", "You receive loot: %sx%d."
ITEM_BIND_ON_PICKUP, ITEM_BIND_QUEST, ITEM_BIND_ON_EQUIP, ITEM_BIND_ON_USE, ITEM_SPELL_TRIGGER_ONUSE = "Binds when picked up", "Quest Item", "Binds when equipped", "Binds when used", "Use:"
MAX_TRADABLE_ITEMS = 6
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
CLASS_SORT_ORDER = {}
UnitFactionGroup = function() return "Horde", "Horde" end
UnitRace = function() return "Tauren", "Tauren" end
UnitClass = function() return "Druid", "DRUID" end
UnitName = function(u) if u == "player" then return "Aldren" end return nil end
LoadAddOn = function() return nil end
GetRealmName = function() return "Testrealm" end
GetNetStats = function() return 0, 0, 50 end
IsAddOnLoadOnDemand = function() return nil end
GetAddOnDependencies = function() return nil end
DisableAddOn = function() end
EnableAddOn = function() end
GetMouseFocus = function() return nil end
UnitInRaid = function() return nil end
UnitIsUnit = function() return nil end
GetItemQualityColor = function() return 1, 1, 1, "|cffffffff" end
GetItemInfo = function() return nil end
UIDropDownMenu_Initialize = UIDropDownMenu_Initialize or function() end
GameTooltip_SetDefaultAnchor = GameTooltip_SetDefaultAnchor or function() end
GetGuildRosterInfo = function() return nil end
GuildControlGetRankFlags = function() return nil end
GetNumSkillLines = function() return 0 end
GetNumTradeSkills = function() return 0 end
GetNumCrafts = function() return 0 end
hooksecurefunc = nil
GetFramerate = function() return 60 end
IsLoggedIn = function() return Mock.loggedIn end
getfenv = getfenv or function() return _G end
strfind, strsub, strlen, strlower, strupper, strrep, strbyte, strchar, strjoin = string.find, string.sub, string.len, string.lower, string.upper, string.rep, string.byte, string.char, nil
format, gsub, tinsert, tremove, getn, floor, ceil, abs, mod = string.format, string.gsub, table.insert, table.remove, table.getn, math.floor, math.ceil, math.abs, math.mod
GetAddOnMetadata = function(a, k) if k == "Version" then return "10.20.5 <ERROR>" end return "" end
IsInGuild = function() return 1 end
GetNumGuildMembers = function() return 0 end
GuildRoster = function() end
CanEditOfficerNote = function() return 1 end
IsGuildLeader = function() return nil end
GetGuildInfo = function() return "Test Guild", "Officer", 1 end
UnitLevel = function() return 60 end
MAX_PLAYER_LEVEL = 60
NUM_CHAT_WINDOWS = 7
for i = 1, 7 do
  local tab = Mock.New("Button", "ChatFrame" .. i .. "Tab", UIParent)
  tab.text = "General"
  if not getglobal("ChatFrame" .. i) then Mock.New("Frame", "ChatFrame" .. i, UIParent) end
end
GetChannelName = function() return 0 end
GetLootMethod = function() return "group", nil end
local errs = {}
local okLoad, err = pcall(Mock.Load, ".", "shootyepgp.toc")
if not okLoad then print("LOAD ERROR: " .. tostring(err)) os.exit(1) end
Mock.Fire("ADDON_LOADED", "shootyepgp")
Mock.Fire("PLAYER_LOGIN")
Mock.Fire("PLAYER_ENTERING_WORLD")
Mock.Tick(6)
local fails = 0
local function ok(c, w) if not c then fails = fails + 1 print("FAIL: " .. w) end end
ok(sepgp and sepgp_bids and sepgp_standings and sepgp_loot, "core and stand-ins loaded")
ok(SEPGP_UI and SEPGP_UI.Minimap.button, "new window's minimap button built")
ok(sepgp.minimapFrame == nil, "no old FuBar icon")
ok(type(sepgp.cmdtable) == "function", "slash commands still defined")
-- the old slash commands now open the new window
local cmd = sepgp.cmdtable()
local p1, e1 = pcall(cmd.args.show.func)
ok(p1 and SEPGP_UI.frame and SEPGP_UI.frame:IsShown() and SEPGP_UI.current == "standings", "/shooty show opens Standings " .. tostring(e1))
local p2, e2 = pcall(cmd.args.bids.func)
ok(p2 and SEPGP_UI.current == "bids", "/shooty bids opens Bids " .. tostring(e2))
for i = 1, table.getn(SEPGP_UI.order) do SEPGP_UI.Select(SEPGP_UI.order[i]) end
-- the REAL decay through the decay log (ui\Decay.lua), then its undo
local G = { { "Aldren", "{820:410}" }, { "Corvan", "tank {1500:900}" }, { "Dalia", "{120:300}" }, { "Fennick", "" } }
GetNumGuildMembers = function() return table.getn(G) end
GetGuildRosterInfo = function(i) local g = G[i] if not g then return nil end return g[1], "Raider", 3, 60, "Warrior", "", "", g[2], 1 end
GuildRosterSetOfficerNote = function(i, note) if G[i] then G[i][2] = note end end
sepgp_decay, sepgp_minep = 0.9, 300
local DL = SEPGP_UI.Decay
local okDecay, errDecay = pcall(sepgp.decay_epgp_v3, sepgp)
ok(okDecay, "real decay runs through the decay log " .. tostring(errDecay))
ok(G[1][2] == "{738:369}" and G[2][2] == "tank {1350:810}" and G[3][2] == "{108:300}" and G[4][2] == "",
  "real decay wrote the notes (" .. G[1][2] .. " / " .. G[2][2] .. " / " .. G[3][2] .. ")")
local rec = DL.List()[1]
ok(rec and rec.n == 3 and rec.pct == 10 and DL.Fits(rec), "real decay recorded: 3 members, 10%, fits the rule")
local okUndo, errUndo = pcall(DL.Undo, rec and rec.id)
ok(okUndo, "undo runs " .. tostring(errUndo))
ok(G[1][2] == "{820:410}" and G[2][2] == "tank {1500:900}" and G[3][2] == "{120:300}", "undo puts the notes back (" .. G[1][2] .. " / " .. G[2][2] .. ")")
ok(rec and rec.undo and rec.undo.n == 3, "undo recorded")
-- the REAL bid call line (sepgp:bidPrint) also brings up the bid pop-up (ui\BidPopup.lua)
local okBid, errBid = pcall(sepgp.bidPrint, sepgp, "|cffa335ee|Hitem:19402:0:0:0|h[Legguards of the Fallen Crusader]|h|r", "Corvan", 1, 1, nil)
ok(okBid and SEPGP_UI.BidPopup.frame and SEPGP_UI.BidPopup.frame:IsShown() and SEPGP_UI.BidPopup.frame.id == 19402, "real bid call opens the bid pop-up " .. tostring(errBid))
ok(sepgp_lootdb and SEPGP_UI.pages.prices, "loot list and Prices topic loaded")
-- the REAL addon message handler passes the guild leader's offspec prices per tier on
local oldRoster = GetGuildRosterInfo
GetGuildRosterInfo = function(i) local g = G[i] if not g then return nil end return g[1], i == 2 and "Guild Master" or "Raider", i == 2 and 0 or 3, 60, "Warrior", "", "", g[2], 1 end
local okOs, errOs = pcall(sepgp.addonComms, sepgp, sepgp.VARS.prefix, "OSTIER;T1=0.25,T2=0.4;1", "GUILD", "Corvan")
ok(okOs and sepgp_prices:OffspecRate("T2") == 0.4 and sepgp_prices:GetOffspec(19402) == 90, "real OSTIER message sets the T2 offspec price " .. tostring(errOs))
GetGuildRosterInfo = oldRoster
for i = 1, table.getn(Mock.printed) do
  if string.find(Mock.printed[i], "rror") or string.find(Mock.printed[i], "page ") then print("chat: " .. Mock.printed[i]) fails = fails + 1 end
end
print(fails == 0 and "real addon loads clean" or (fails .. " problems"))
if fails > 0 then os.exit(1) end
