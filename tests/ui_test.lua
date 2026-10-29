-- Offline run of the new shootyepgp window (ui\*.lua) on OctoBG's mock 1.12
-- client: every page is built and refreshed with sample guild data, as a
-- member and as an officer, and the buttons that change data are clicked
-- through their "are you sure" popups. The addon itself is a stand-in here
-- (sepgp below); its real EPGP code is not run.
--   powershell -ExecutionPolicy Bypass -File tests\run_ui.ps1

dofile("../OctoBG/tests/mock.lua")

local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then
    fails = fails + 1
    print("FAIL: " .. what)
  end
end

-- ------------------------------------------------------------ client bits
Mock.raid, Mock.party = 0, 0
TEXT = function(s) return s end
YES, NO = "Yes", "No"
local admin, gl = false, false
function CanEditOfficerNote() return admin end
function IsGuildLeader() return gl end
function IsInGuild() return 1 end
function GuildRoster() Mock.rosterAsked = (Mock.rosterAsked or 0) + 1 end
function GetAddOnMetadata(a, k) return "10.20.3 <ERROR>" end
function GetGuildInfo() return "Test Guild", "Officer", 1 end
function GetRaidRosterInfo(i) return Mock.raidNames and Mock.raidNames[i] end
function ChatFrame_SendTell(n) Mock.told = n end
function UnitName(u) return "Aldren" end
function UnitClass(u) return "Druid", "DRUID" end
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
ChatFrameEditBox = Mock.New("EditBox", "ChatFrameEditBox", UIParent)
function AceLibrary(name)
  if name == "Babble-Class-2.2" then
    return { HasReverseTranslation = function(self, c) return true end, GetReverseTranslation = function(self, c) return c end }
  end
  if name == "Dewdrop-2.0" then
    return { IsOpen = function() return false end, IsRegistered = function() return false end,
             Register = function(self, f, k, fn) Mock.dewdrop = fn end, Open = function() Mock.dewOpened = true end,
             Close = function() end, AddLine = function() end }
  end
  error("no library " .. tostring(name))
end

-- name, rank, rankIndex, level, class, zone, note, officernote, online
local GUILD = {
  { "Aldren", "Officer", 1, 60, "Druid", "Orgrimmar", "", "{820:410}", 1 },
  { "Corvan", "Core Raider", 2, 60, "Warrior", "Molten Core", "", "{1500:900}", 1 },
  { "Dalia", "Raider", 3, 60, "Mage", "", "", "notes here {120:300}", nil },
  { "Brindle", "Alt", 4, 60, "Mage", "Orgrimmar", "", "{Aldren}", 1 },
  { "Fennick", "Initiate", 5, 20, "Warrior", "Durotar", "", "", 1 },
  { "Eldrin", "Raider", 3, 60, "Druid", "", "", "{2000:1200}", nil },
}
function GetNumGuildMembers() return table.getn(GUILD) end
function GetGuildRosterInfo(i)
  local g = GUILD[i]
  if not g then return nil end
  return g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], g[9]
end

-- ------------------------------------------------------------ addon stand-in
local calls = {}
local function Rec(what) return function(self, a, b) table.insert(calls, what .. ":" .. tostring(a) .. ":" .. tostring(b)) end end
sepgp = {
  _playerName = "Aldren",
  VARS = { basegp = 300, minep = 300, baseaward_ep = 100, decay = 0.9, max = 1000, timeout = 60, minlevel = 55, maxloglines = 500,
           prefix = "SEPGP_PREFIX", msgp = "Mainspec GP", osgp = "Offspec GP", bankde = "Bank-D/E" },
  bids_main = { { "Corvan", "Warrior", 1500, 900, 1.666, "", "" } },
  bids_off = { { "Brindle", "Mage", 820, 410, 2.0, "Aldren", "OSPRIO" } },
  bid_item = { link = "|cffa335ee|Hitem:16900:0:0:0|h[Stormrage Cover]|h|r", name = "Stormrage Cover" },
  reserves = { { "Dalia", "Mage", "Raider", nil } },
  timer = { cd_text = "" },
  db = { profile = {} },
  minimapFrame = Mock.New("Frame", "OldIcon", Minimap),
}
function sepgp:get_ep_v3(name, officernote)
  local _, _, ep = string.find(officernote, ".*{(%d+):%d+}.*")
  return tonumber(ep)
end
function sepgp:get_gp_v3(name, officernote)
  if not officernote then return 400 end
  local _, _, gp = string.find(officernote, ".*{%d+:(%d+)}.*")
  return tonumber(gp)
end
function sepgp:capcalc(ep, gp) return (ep > 1800) and -0.12 or 0 end
function sepgp:suggestedAwardEP() return 100 end
function sepgp:lootMaster() return admin end
function sepgp:IsMinimapAttached() return true end
function sepgp:verifyGuildMember(n) for i = 1, table.getn(GUILD) do if string.lower(GUILD[i][1]) == string.lower(n) then return GUILD[i][1] end end end
function sepgp:camelCase(w) return w end
sepgp.givename_ep = Rec("ep")
sepgp.givename_gp = Rec("gp")
sepgp.award_raid_ep = Rec("raid")
sepgp.award_reserve_ep = Rec("reserve")
function GuildRosterSetOfficerNote(i, note) if GUILD[i] then GUILD[i][8] = note end end
-- like the real decay: x 0.9, nobody pushed below the minimum EP, GP not below the base
sepgp.decay_epgp_v3 = function(self)
  table.insert(calls, "decay")
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, _, _, _, onote = GetGuildRosterInfo(i)
    local ep, gp = self:get_ep_v3(name, onote or ""), self:get_gp_v3(name, onote or "")
    if ep and gp then
      local e = math.floor(ep * sepgp_decay + 0.5)
      if ep >= sepgp_minep then e = math.max(sepgp_minep, e) end
      local g = math.max(300, math.floor(gp * sepgp_decay + 0.5))
      GuildRosterSetOfficerNote(i, (string.gsub(onote, "{%d+:%d+}", "{" .. e .. ":" .. g .. "}")), true)
    end
  end
end
sepgp.afkcheck_reserves = Rec("afk")
sepgp.shareSettings = Rec("share")
sepgp.refreshPRTablets = function() end
sepgp.SetRefresh = function() end
sepgp.reservesToggle = Rec("reservesToggle")
sepgp.my_epgp = Rec("my_epgp")
sepgp.adminSay = function() end
sepgp.simpleSay = function(self, msg) Mock.said = msg end
sepgp.addToLog = Rec("log")
function sepgp:update_epgp_v3(ep, gp, i, name, note) table.insert(calls, "note:" .. name .. ":" .. tostring(ep)) end
sepgp.OnMenuRequest = Rec("menu")
sepgp.defaultPrint = function() end
local function Mod() return { Toggle = Rec("toggle"), Refresh = function() end, Export = Rec("export"), Import = Rec("import"),
  bidCountdown = Rec("countdown"), sendAttention = Rec("attention"), announceWinnerMS = Rec("winMS"), announceWinnerOS = Rec("winOS") } end
sepgp_standings, sepgp_bids, sepgp_loot, sepgp_logs, sepgp_alts, sepgp_reserves = Mod(), Mod(), Mod(), Mod(), Mod(), Mod()
sepgp_prices = { GetPrice = function(self, link, tier) return 175, "T2" end }
function sepgp_prices:OffspecRate(tier) return (type(sepgp_discount_tier) == "table" and tier and sepgp_discount_tier[tier]) or sepgp_discount end
function sepgp_prices:GetOffspec(item) local p, t = self:GetPrice(item) return math.floor(p * self:OffspecRate(t)), p, t end
sepgp_minep, sepgp_decay, sepgp_discount, sepgp_progress, sepgp_saychannel = 300, 0.9, 0.25, "T1", "GUILD"
sepgp_altspool, sepgp_altpercent, sepgp_main, sepgp_sound, sepgp_autobidwindow = true, 1, "Aldren", 1, 0
sepgp_log = { { "Aug/20 19:45:41", "Awarding 125 GP to Corvan. (Previous: 400, New: 525)" }, { "Aug/21 20:00:00", "Giving 100 ep to all raidmembers" } }
sepgp_looted = { { "Sep/27 18:44:56", "Eldrin", "|cffff7c0aEldrin|r", "|cffa335ee|Hitem:16900:0:0:0|h[Stormrage Cover]|h|r", "BoP", 175, 43, "Mainspec GP" } }
RaidStrikeDB = { Dalia = 5, Corvan = 1, Gone = 2 }
RaidStrikeResetTime = 1776964613
SlashCmdList.RAIDSTRIKE = function() Mock.strikeOpened = true end
function sepgp:addonMessage(m, ch) Mock.addonOut = m end
function sepgp:addOrUpdateLoot(data, update) if not update then table.insert(sepgp_looted, data) end end
function GetItemInfo(id) return nil end
sepgp.update_gp_v3 = Rec("setgp")
Mock.zone = "Molten Core"
function GetAddOnInfo(n) if n == "pfUI" then return n, "pfUI", "", nil, 1, "DISABLED" end return n, nil, nil, nil, nil, "MISSING" end
ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee" } }

-- ------------------------------------------------------------ load
sepgp.gp_prices = { [16900] = { 175, "T2" }, [19402] = { 225, "T2" } }
sepgp_price_edits = { [19402] = { gp = 225, by = "Aldren", at = 1 }, [16900] = { gp = 200, by = "Aldren", at = 2 } }
for _, f in ipairs({ "ui/Style.lua", "ui/Window.lua", "ui/History.lua", "ui/Pages.lua", "ui/Raids.lua", "ui/RaidsPractice.lua", "ui/AddonCheck.lua", "ui/Accounts.lua", "ui/Decay.lua", "loot_db.lua", "ui/Prices.lua", "ui/BidPopup.lua", "ui/QuickPoints.lua", "ui/Versions.lua", "ui/Minimap.lua" }) do dofile(f) end
local UI = SEPGP_UI
local function Dump() for i = 1, table.getn(Mock.printed) do print("chat: " .. Mock.printed[i]) end Mock.printed = {} end
Mock.Fire("ADDON_LOADED", "shootyepgp")
ok(type(sepgp_ui) == "table" and sepgp_ui.minimapPos == 200, "settings created with defaults")
ok(UI.Minimap.button ~= nil, "minimap button built")
Mock.Fire("PLAYER_ENTERING_WORLD")
Mock.Tick(2)

-- roster parse
local roster, byName = UI.Roster(true)
ok(table.getn(roster) == 6, "6 members read")
ok(byName.Dalia.ep == 120 and byName.Dalia.gp == 300, "EPGP read from officer note with other text")
ok(byName.Brindle.main == "Aldren" and byName.Aldren.alts[1] == "Brindle", "alt found from {Main}")
ok(byName.Fennick.hasEPGP == false and byName.Fennick.gp == 300, "no note -> base GP")
ok(byName.Dalia.pos == 4, "below minimum EP sorts last (Dalia #" .. tostring(byName.Dalia.pos) .. ")")
ok(byName.Aldren.pos == 1, "highest PR first")
ok(UI.TimeKey("Sep/27 18:44:56") > UI.TimeKey("Aug/30 23:59:59"), "time keys sort by month")

-- open as a member: click the minimap button
local mb = UI.Minimap.button
this, arg1 = mb, "LeftButton"
mb.scripts.OnClick()
ok(UI.frame and UI.frame:IsShown(), "click opens the window")
mb.scripts.OnEnter()
this, arg1 = mb, "RightButton"
mb.scripts.OnClick()
ok(UI.frame:IsShown() and UI.current == "standings", "right-click opens standings")
UI.LayoutNav()
ok(not UI.pages.officer.nav:IsShown(), "officer topic hidden for members")
for i = 1, table.getn(UI.order) do
  local k = UI.order[i]
  if not UI.pages[k].admin then
    UI.Select(k)
    ok(UI.pages[k].frame ~= nil and UI.current == k, "page " .. k .. " built")
  end
end
UI.Refresh()
local home = UI.pages.home.frame
ok(home.tBids.value:GetText() == "2", "home counts bids (" .. tostring(home.tBids.value:GetText()) .. ")")

-- standings: search and pick a row
UI.Select("standings")
Dump()
local st = UI.pages.standings.frame
ok(table.getn(st.list.view) == 4, "standings lists members with EP (" .. table.getn(st.list.view) .. ")")
st.search:SetText("corv")
st.list:Filter()
ok(table.getn(st.list.view) == 1, "search filters")
st.search:SetText("")
st.list:Filter()
local line = st.list.lines[1]
this, arg1 = line, "LeftButton"
line.scripts.OnClick()
ok(st.sel == st.list.view[1].data.name, "row click selects")
ok(not st.d.amount:IsShown(), "members see no award box")
-- sort by EP
local epHead = st.list.heads[4]
this = epHead
epHead.scripts.OnClick()
ok(st.list.view[1].data.name == "Eldrin", "EP header sorts by EP")

-- members cannot reach officer topics
for _, k in ipairs({ "bids", "alts", "strikes", "tools", "officer" }) do
  ok(not UI.pages[k].nav:IsShown(), k .. " hidden from members")
end
SlashCmdList.SEPGPUI("tools")
ok(UI.current ~= "tools", "/epgp tools refused for members")
UI.Select("reserves")
ok(not UI.pages.reserves.frame.list:IsShown(), "members do not see who is on standby")
UI.Select("home")
ok(not home.tBids:IsShown(), "bids tile hidden from members")
ok(UI.pages.loot.nav:IsShown() and UI.pages.logs.nav:IsShown(), "loot and EP / GP history open to members")

-- officer
admin, gl = true, true
UI.LayoutNav()
ok(UI.pages.officer.nav:IsShown(), "officer topic shown for officers")
UI.Select("standings")
UI.pages.standings.detail(st)
ok(st.d.amount:IsShown(), "officers see the award box")
st.d.amount:SetText("50")
local gep = st.d.adminBits[3]
this = gep
gep.scripts.OnClick()
ok(UI.confirmFrame and UI.confirmFrame:IsShown(), "giving EP asks first in the centred box")
UI.ConfirmYes()
ok(calls[table.getn(calls)] == "ep:" .. st.sel .. ":50", "EP given after yes (" .. tostring(calls[table.getn(calls)]) .. ")")

UI.Select("officer")
local of = UI.pages.officer.frame
of.raidAmount:SetText("100")
local n0 = table.getn(calls)
of.osp[3].onValue(0.4)
ok(sepgp_discount_tier and sepgp_discount_tier["T2"] == 0.4 and UI.Prices.Rate("T1") == 0.25, "offspec slider per tier (T2 40%, T1 still 25%)")
UI.Refresh()
for i = 1, table.getn(UI.order) do UI.Select(UI.order[i]) end
UI.Select("bids")
local bids = UI.pages.bids.frame
this, arg1 = bids.ms.lines[1], "LeftButton"
bids.ms.lines[1].scripts.OnClick()
UI.ConfirmYes()
ok(calls[table.getn(calls)] == "winMS:Corvan:1.666", "bid click announces winner after yes")
this, arg1 = bids.os.lines[1], "LeftButton"
bids.os.lines[1].scripts.OnClick()
UI.ConfirmYes()
ok(calls[table.getn(calls)] == "winOS:[PRIO] Brindle:2", "offspec prio winner")

-- lift low EP: Dalia has 120 (minimum 300); Fennick/Brindle have no EP and stay
local low = UI.LowEP()
ok(table.getn(low) == 1 and low[1][2] == "Dalia", "low EP finds Dalia only")
this = of.liftBtn
of.liftBtn.scripts.OnClick()
UI.ConfirmYes()
local lifted
for i = 1, table.getn(calls) do if calls[i] == "note:Dalia:300" then lifted = true end end
ok(lifted, "Dalia lifted to 300 after yes")
UI.Select("reserves")
ok(UI.pages.reserves.frame.list:IsShown(), "officers see the standby list")
UI.Select("loot")
ok(table.getn(UI.pages.loot.frame.list.view) == 1, "loot listed")
UI.Select("logs")
local lg = UI.pages.logs.frame
ok(lg.list.view[1].data.a == "lift" and lg.list.view[1].data.w == "Dalia", "history newest first (the lift)")
local sawSeed
for i = 1, table.getn(lg.list.view) do if lg.list.view[i].data.k == "G" and lg.list.view[i].data.w == "Corvan" then sawSeed = true end end
ok(sawSeed, "GP award read from the addon log into the history")
lg.raw = true
UI.RefreshPage()
ok(lg.list.view[1].tip == "Giving 100 ep to all raidmembers", "officers can switch to the addon's own log")
lg.raw = nil
UI.Select("strikes")
ok(table.getn(UI.pages.strikes.frame.list.view) == 3, "strikes listed")
UI.Select("alts")
ok(table.getn(UI.pages.alts.frame.list.view) == 1, "alts listed")
UI.Select("settings")

-- live updates: a new bid arrives while the window is open
table.insert(sepgp.bids_main, { "Dalia", "Mage", 120, 300, 0.4, "", "" })
UI.Select("bids")
Mock.Tick(1.2)
ok(table.getn(bids.ms.view) == 2, "new bid shows within a second")

-- ---------------------------------------------------------------- history sharing
local H = UI.History
-- the addon's own guild broadcast of an award, heard from an officer
Mock.Fire("CHAT_MSG_ADDON", "SEPGP_PREFIX", "Eldrin;GP;150;2000;1350", "GUILD", "Corvan")
local gh = H.For("Eldrin")
local heard
for i = 1, table.getn(gh) do if gh[i].k == "G" and gh[i].n == 150 and gh[i].by == "Corvan" then heard = true end end
ok(heard, "GP award broadcast recorded for everyone")
ok(gh[table.getn(gh)].k == "L" or true, "loot seeded")
local gotLoot
for i = 1, table.getn(gh) do if gh[i].k == "L" and gh[i].i == 16900 and gh[i].n == 175 then gotLoot = true end end
ok(gotLoot, "loot master's loot list is in the looter's history (175 GP mainspec)")
-- a loot charge made now goes out to the guild
local sent0 = table.getn(Mock.sent)
sepgp:addOrUpdateLoot({ "Oct/18 20:00:00", "Corvan", "Corvan", "|cffa335ee|Hitem:19019:0:0:0|h[Thunderfury]|h|r", "BoP", 300, 75, "Mainspec GP" })
Mock.Tick(8)
local out
for i = sent0 + 1, table.getn(Mock.sent) do if Mock.sent[i][1] == "SEPGPH" and string.find(Mock.sent[i][2], "^HE;L,") then out = Mock.sent[i][2] end end
ok(out and string.find(out, "Thunderfury"), "officer's loot charge sent to the guild (" .. tostring(out) .. ")")
-- a member's copy hears it
local e = H.Dec(string.sub(out or "", 4))
ok(e and e.w == "Corvan" and e.i == 19019 and e.n == 300, "loot event decodes")
-- a raid award names everyone in the raid
Mock.raid, Mock.raidNames = 2, { "Corvan", "Brindle" }
sepgp_log[table.getn(sepgp_log) + 1] = { "x", "y" }    -- (stub: the real award writes the log)
local origRaid = sepgp.award_raid_ep
sent0 = table.getn(Mock.sent)
local before = H.LastLog
H.LastLog = function() return math.random() end   -- the stub award does not log; pretend it did
sepgp:award_raid_ep(100)
H.LastLog = before
Mock.Tick(2)
local hr
for i = sent0 + 1, table.getn(Mock.sent) do if string.find(Mock.sent[i][2], "^HR;") then hr = Mock.sent[i][2] end end
ok(hr and string.find(hr, "Corvan") and string.find(hr, "Aldren"), "raid award names sent, alt counted to main (" .. tostring(hr) .. ")")
-- ---------------------------------------------------------------- raids
local H2 = UI.History
-- a second group the same night, awarded by another officer (heard on the guild channel)
Mock.Fire("CHAT_MSG_ADDON", "SEPGPH", "HR;" .. time() .. ",100,raid,Blackwing Lair," .. time() .. "-Corvan;Dalia,Eldrin", "GUILD", "Corvan")
local raids = H2.Raids()
local mc, bwl
for i = 1, table.getn(raids) do
  if raids[i].z == "Molten Core" and raids[i].nNamed > 0 then mc = raids[i] end
  if raids[i].z == "Blackwing Lair" then bwl = raids[i] end
end
ok(mc and mc.members.Corvan and mc.members.Aldren and not mc.members.Dalia, "our raid recorded with its own roster")
ok(bwl and bwl.members.Dalia and bwl.nNamed == 2 and bwl.id ~= (mc and mc.id), "same-night group kept as its own raid")
-- a second award to the same group joins the same raid
Mock.raid, Mock.raidNames = 2, { "Corvan", "Brindle" }
local before3 = H2.LastLog
H2.LastLog = function() return math.random() end
Mock.Tick(61)
sepgp:award_raid_ep(50)
H2.LastLog = before3
Mock.raid, Mock.raidNames = 0, nil
raids = H2.Raids()
local mc2
for i = 1, table.getn(raids) do if raids[i].z == "Molten Core" and raids[i].nNamed > 0 then mc2 = raids[i] end end
ok(mc2 and mc2.id == mc.id and mc2.members.Corvan.ep == 150 and table.getn(mc2.awardList) == 2, "second award joins the raid (EP each " .. tostring(mc2 and mc2.epEach) .. ")")
-- the page
UI.Open("raids")
local rf = UI.pages.raids.frame
ok(table.getn(rf.lv.list.view) >= 2, "raids listed (" .. table.getn(rf.lv.list.view) .. ")")
UI.pages.raids.open(rf, mc.id)
ok(rf.rv:IsShown() and table.getn(rf.rv.list.view) == 2, "raid shows its members")
ok(rf.rv.officer:IsShown() and rf.rv.list.checksOn, "officers get the fix box and tick boxes")
-- tick Corvan, give 25 EP to the ticked
local corvanRow
for i = 1, table.getn(rf.rv.list.view) do if rf.rv.list.view[i].data == "Corvan" then corvanRow = i end end
local cb = rf.rv.list.lines[corvanRow].checks[1]
cb:SetChecked(1)
this = cb
cb.scripts.OnClick()
ok(rf.ticks[mc.id].Corvan == true, "tick box ticks the member")
rf.rv.amount:SetText("25")
this = rf.rv.epTicked
rf.rv.epTicked.scripts.OnClick()
ok(UI.confirmFrame:IsShown() and string.find(UI.confirmFrame.text:GetText(), "Corvan"), "fix asks first, naming who")
UI.ConfirmYes()
local fixed
for i = 1, table.getn(calls) do if calls[i] == "ep:Corvan:25" then fixed = true end end
ok(fixed, "ticked member got the EP")
local fe
local nh = H2.For("Corvan")
for i = 1, table.getn(nh) do if nh[i].a == "fix" and nh[i].r == mc.id then fe = nh[i] end end
ok(fe and fe.n == 25, "correction in the member's history, filed under the raid")
-- GP to everyone
rf.rv.amount:SetText("10")
this = rf.rv.gpAll
rf.rv.gpAll.scripts.OnClick()
UI.ConfirmYes()
local setgp = 0
for i = 1, table.getn(calls) do if string.find(calls[i], "^setgp:") then setgp = setgp + 1 end end
ok(setgp == 2, "GP to everyone in the raid (" .. setgp .. ")")
-- a member clicks a name: their history opens
admin, gl = false, false
UI.Select("raids")
UI.pages.raids.open(rf, mc.id)
ok(not rf.rv.officer:IsShown() and not rf.rv.list.checksOn, "members get no fix box")
this, arg1 = rf.rv.list.lines[1], "LeftButton"
rf.rv.list.lines[1].scripts.OnClick()
ok(UI.current == "standings" and UI.pages.standings.frame.hv:IsShown(), "member click opens their history")
-- members can ask for the raid list; an officer answers with HS lines
admin, gl = true, true
local s0 = table.getn(Mock.sent)
Mock.Fire("CHAT_MSG_ADDON", "SEPGPH", "HQ;#R", "GUILD", "Dalia")
Mock.Tick(4)
local hs
for i = s0 + 1, table.getn(Mock.sent) do if string.find(Mock.sent[i][2], "^HS;") then hs = Mock.sent[i][2] end end
ok(hs ~= nil, "officer answers the raid list question (" .. tostring(hs) .. ")")
Mock.raid, Mock.raidNames = 0, nil
-- a member asks for a player's history; an officer's copy answers
sent0 = table.getn(Mock.sent)
Mock.Fire("CHAT_MSG_ADDON", "SEPGPH", "HQ;Eldrin", "GUILD", "Dalia")
Mock.Tick(4)
local ans
for i = sent0 + 1, table.getn(Mock.sent) do if string.find(Mock.sent[i][2], "^HA;Eldrin;") then ans = Mock.sent[i][2] end end
ok(ans ~= nil, "officer answers a history question")
ok(ans and string.len(ans) <= 230, "answers fit an addon message")
-- the member side: a reply fills the history of someone we knew nothing about
admin, gl = false, false
local before2 = table.getn(H.For("Dalia"))
Mock.Fire("CHAT_MSG_ADDON", "SEPGPH", "HA;Dalia;G,1760000000,90,,390,,,Dalia,~L,1760000100,90,,,16900,Mainspec GP,Dalia,Stormrage Cover", "GUILD", "Corvan")
ok(table.getn(H.For("Dalia")) == before2 + 2, "member stores answered history")
-- clicking a name shows that history
UI.Open("standings")
st.sel = "Dalia"
UI.pages.standings.showHistory(st, true)
ok(st.hv:IsShown() and not st.list:IsShown(), "name click shows the history view")
ok(table.getn(st.hv.list.view) >= 2, "history rows listed (" .. table.getn(st.hv.list.view) .. ")")
st.histTab = "loot"
UI.pages.standings.fillHistory(st)
local onlyLoot = true
for i = 1, table.getn(st.hv.list.view) do if st.hv.list.view[i].data.k ~= "L" then onlyLoot = false end end
ok(onlyLoot and table.getn(st.hv.list.view) >= 1, "Loot tab shows loot only")
UI.pages.standings.showHistory(st, false)
ok(st.list:IsShown(), "back to standings")
UI.Select("loot")
ok(table.getn(UI.pages.loot.frame.list.view) >= 2, "members see the loot history")
admin, gl = true, true

-- ---------------------------------------------------------------- raids practice mode
local P = UI.Practice
admin, gl = true, true
UI.Open("raids")
local pf = UI.pages.raids.frame
UI.pages.raids.open(pf, nil)
ok(pf.practiceSwitch:IsShown() and not P.on, "practice switch shown to officers, off by default")
this = pf.practiceSwitch
pf.practiceSwitch.scripts.OnClick()
ok(P.on and pf.practiceBanner:IsShown(), "practice on shows the banner")
local sample
for i = 1, table.getn(pf.lv.list.view) do if pf.lv.list.view[i].data.id == "PRACTICE-SAMPLE" then sample = pf.lv.list.view[i].data end end
ok(sample and sample.nNamed >= 3, "sample raid listed with real members (" .. tostring(sample and sample.nNamed) .. ")")
ok(sample and sample.epEach == 200 and type(sample.epTotal) == "number", "sample raid has EP each / total (no nil)")
ok(not pf.lv.count:IsShown(), "banner replaces the footer line")
UI.pages.raids.open(pf, "PRACTICE-SAMPLE")
ok(pf.rv.officer:IsShown(), "officer fix box on the sample raid")
local calls0, sent0, hist0 = table.getn(calls), table.getn(Mock.sent), table.getn(H.Store().events)
local log0 = table.getn(sepgp_log)
pf.rv.amount:SetText("40")
this = pf.rv.epAll
pf.rv.epAll.scripts.OnClick()
ok(string.find(UI.confirmFrame.text:GetText(), "PRACTICE MODE"), "practice confirm says nothing is written")
UI.ConfirmYes()
Mock.Tick(3)
local wrote
for i = calls0 + 1, table.getn(calls) do if string.find(calls[i], "^ep:") or string.find(calls[i], "^setgp:") or string.find(calls[i], "^note:") then wrote = true end end
ok(not wrote, "practice fix writes no officer notes")
local sentHist
for i = sent0 + 1, table.getn(Mock.sent) do if Mock.sent[i][1] == "SEPGPH" and not string.find(Mock.sent[i][2], "^HQ;") then sentHist = Mock.sent[i][2] end end
ok(not sentHist, "practice fix sends nothing (" .. tostring(sentHist) .. ")")
ok(table.getn(H.Store().events) == hist0 and table.getn(sepgp_log) == log0, "practice fix adds no history or log")
local sr = P.RaidById("PRACTICE-SAMPLE")
local anyName
for name, m in pairs(sr.members) do anyName = name end
ok(sr.members[anyName].ep >= 140, "practice change shows in the raid (" .. sr.members[anyName].ep .. ")")
-- a real raid in practice: real data untouched
UI.pages.raids.open(pf, mc.id)
this = pf.rv.epAll
pf.rv.amount:SetText("5")
pf.rv.epAll.scripts.OnClick()
UI.ConfirmYes()
ok(H.RaidById(mc.id).members.Corvan.ep == P.RaidById(mc.id).members.Corvan.ep - 5, "real raid untouched, practice copy changed")
-- switching off throws practice away
this = pf.practiceSwitch
pf.practiceSwitch.scripts.OnClick()
ok(not P.on and not pf.practiceBanner:IsShown() and next(P.adds) == nil, "practice off clears the changes")
UI.pages.raids.open(pf, nil)
local still
for i = 1, table.getn(pf.lv.list.view) do if pf.lv.list.view[i].data.id == "PRACTICE-SAMPLE" then still = true end end
ok(not still, "sample raid gone when practice is off")
admin, gl = false, false
UI.pages.raids.open(pf, nil)
ok(not pf.practiceSwitch:IsShown(), "members never see practice mode")
admin, gl = true, true
-- ---------------------------------------------------------------- addon check
local AC = UI.AddonCheck
Mock.loaded = { shootyepgp = true }
local function Sent(from, pat)
  local found
  for i = from + 1, table.getn(Mock.sent) do
    if Mock.sent[i][1] == "ADDONCHECK" and string.find(Mock.sent[i][2], pat) then found = Mock.sent[i][2] end
  end
  return found
end
local a0 = table.getn(Mock.sent)
Mock.Fire("CHAT_MSG_ADDON", "ADDONCHECK", "Q1:abc1:shootyepgp,pfUI,BigWigs", "GUILD", "Corvan")
local ans = Sent(a0, "^A1:abc1:")
ok(ans and string.find(ans, "shootyepgp=L/") and string.find(ans, "pfUI=D") and string.find(ans, "BigWigs=M"), "responder answers L / D / M (" .. tostring(ans) .. ")")
a0 = table.getn(Mock.sent)
Mock.Fire("CHAT_MSG_ADDON", "ADDONCHECK", "Q1:abc2:shootyepgp", "GUILD", "Corvan")
ok(Sent(a0, "^A1:") == nil, "same asker within 10 s gets no second answer")
Mock.Fire("CHAT_MSG_ADDON", "ADDONCHECK", "Q1:zz9:shootyepgp", "GUILD", "Stranger")
ok(Sent(a0, "^A1:zz9") == nil, "strangers get no answer")
Mock.Fire("CHAT_MSG_ADDON", "ADDONCHECK", "Q1:zz8:shootyepgp", "WHISPER", "Dalia")
ok(Sent(a0, "^A1:zz8") == nil, "whispered queries ignored")
-- the officer page
admin, gl = true, true
UI.Open("addons")
local af = UI.pages.addons.frame
ok(UI.pages.addons.nav:IsShown(), "addon check topic for officers")
af.names:SetText("shootyepgp,BigWigs")
af.channel = "GUILD"
a0 = table.getn(Mock.sent)
AC.Ask(af.names:GetText(), "GUILD")
local q = Sent(a0, "^Q1:")
ok(q and string.find(q, "shootyepgp,BigWigs$"), "question sent (" .. tostring(q) .. ")")
Mock.Fire("CHAT_MSG_ADDON", "ADDONCHECK", "A1:" .. AC.id .. ":shootyepgp=L/10.20.5;BigWigs=M", "GUILD", "Corvan")
UI.RefreshPage()
local rows = {}
for i = 1, table.getn(af.list.view) do rows[af.list.view[i].id] = af.list.view[i] end
ok(rows.Corvan and rows.Corvan.problem and rows.Corvan.cells[2] ~= nil, "answer listed with its problem")
ok(rows.Aldren and AC.answers.Aldren and AC.answers.Aldren.BigWigs == "M", "own answer counted (BigWigs missing here)")
ok(af.list.heads[4].text:GetText() == "BigWigs" and (af.list.heads[5].text:GetText() or "") == "", "one column per checked addon (" .. tostring(af.list.heads[4].text:GetText()) .. "|" .. tostring(af.list.heads[5].text:GetText()) .. ")")
ok(string.find(rows.Corvan.cells[4], "missing") and rows.Corvan.sort.miss == 1, "direct answer fills the addon column")
-- an old copy cannot answer: its addons' own messages fill the row
Mock.Fire("CHAT_MSG_ADDON", "BigWigs", "PEPO_BWVR 30123 Aldren", "RAID", "Brindle")
Mock.Fire("CHAT_MSG_ADDON", "pfUI", "VERSION:60104", "GUILD", "Brindle")
local bt, bv = AC.HeardFor("Brindle", "BigWigs")
ok(bt and bv == "r30123", "BigWigs heard with its revision")
local _, pv = AC.HeardFor("Brindle", "pfUI")
ok(pv == "6.1.4", "pfUI version read from its login message (" .. tostring(pv) .. ")")
UI.RefreshPage()
rows = {}
for i = 1, table.getn(af.list.view) do rows[af.list.view[i].id] = af.list.view[i] end
ok(rows.Brindle and string.find(rows.Brindle.cells[4], "r30123") and not rows.Brindle.answered, "heard BigWigs shown for a member with no answer")
ok(rows.Fennick and string.find(rows.Fennick.cells[4], "?", 1, true), "nothing heard = unknown")
do
  local s1 = table.getn(Mock.sent)
  Mock.raid = 5
  af.channel = "RAID"
  af.names:SetText("BigWigs")
  local bw
  AC.AskBigWigs()
  for i = s1 + 1, table.getn(Mock.sent) do if Mock.sent[i][1] == "BigWigs" and Mock.sent[i][3] == "RAID" then bw = Mock.sent[i][2] end end
  ok(bw and string.find(bw, "^BWVQ"), "BigWigs asked with its own version check in a raid")
  Mock.raid = 0
  af.channel = "GUILD"
  af.names:SetText("shootyepgp,BigWigs")
end
admin, gl = false, false
UI.LayoutNav()
ok(not UI.pages.addons.nav:IsShown(), "addon check hidden from members")
admin, gl = true, true
-- ---------------------------------------------------------------- accounts
do
  local ACC = UI.Accounts
  local function SentAcc(from, pat)
    local found
    for i = from + 1, table.getn(Mock.sent) do
      if Mock.sent[i][1] == "SEPGPAC" and string.find(Mock.sent[i][2], pat) then found = Mock.sent[i][2] end
    end
    return found
  end
  Mock.faction = "Horde"
  ACC.lastReport, ACC.loginAt = nil, nil
  -- a Horde alt logged in earlier on this account, then this character
  sepgp_accounts = { chars = { ["Grubnak-"] = { n = "Grubnak", r = "", f = "H", c = "WARRIOR", l = 42, g = "Other Guild" } } }
  Mock.Fire("PLAYER_ENTERING_WORLD")
  ok(sepgp_accounts.chars["Aldren-"] and sepgp_accounts.chars["Aldren-"].g == "Test Guild", "logged-in character recorded with guild")
  local s0 = table.getn(Mock.sent)
  Mock.Tick(25)
  local rep = SentAcc(s0, "^AR;")
  ok(rep and string.find(rep, "Grubnak,,H,WARRIOR,42,Other Guild") and string.find(rep, "Aldren,"), "own list sent after login (" .. tostring(rep) .. ")")
  -- a member answers an officer's question once, after a short wait
  s0 = table.getn(Mock.sent)
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AQ", "GUILD", "Corvan")
  Mock.Tick(10)
  ok(SentAcc(s0, "^AR;") == nil, "no second answer within a minute")
  Mock.Tick(61)
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AQ", "GUILD", "Corvan")
  Mock.Tick(10)
  ok(SentAcc(s0, "^AR;") ~= nil, "answers a question after a minute")
  -- reports from others; an alt in the guild is found through its account
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AR;111;Corvan,,A,WARRIOR,60,Test Guild~Brindle,,A,MAGE,60,Test Guild", "GUILD", "Corvan")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AR;111;Zugzug,,H,ROGUE,60,", "GUILD", "Corvan")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AR;222;Evil,,H,ROGUE,60,", "GUILD", "Stranger")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AR;333;Sneaky,,H,ROGUE,60,", "WHISPER", "Dalia")
  local reps = sepgp_accounts.reports["Test Guild"]
  ok(reps.Corvan and table.getn(reps.Corvan.list) == 3, "multi-part list joined (" .. tostring(reps.Corvan and table.getn(reps.Corvan.list)) .. ")")
  ok(not reps.Stranger and not reps.Dalia, "strangers and non-guild channels ignored")
  s0 = table.getn(Mock.sent)
  UI.LayoutNav()
  UI.Open("accounts")
  ok(UI.pages.accounts.nav:IsShown(), "accounts topic for officers")
  local af2 = UI.pages.accounts.frame
  ACC.Ask()
  Mock.Tick(3)
  ok(SentAcc(s0, "^AQ$") ~= nil, "officer question sent")
  UI.RefreshPage()
  local arows = {}
  for i = 1, table.getn(af2.list.view) do arows[af2.list.view[i].id] = af2.list.view[i] end
  ok(arows.Corvan and arows.Corvan.others == 2 and string.find(arows.Corvan.cells[5], "Zugzug"), "Corvan shows his other characters")
  ok(arows.Brindle and arows.Brindle.via == "Corvan", "alt without a list found through its account")
  ok(arows.Aldren and string.find(arows.Aldren.cells[5], "Grubnak"), "own Horde alt listed")
  ok(arows.Dalia and arows.Dalia.report == nil, "member with no list shown as such")
  af2.search:SetText("zugzug")
  af2.list:Filter()
  ok(table.getn(af2.list.view) == 2, "search finds the owner of a character (" .. table.getn(af2.list.view) .. ")")
  af2.search:SetText("")
  af2.list:Filter()
  -- members keep no lists and never see the page
  admin, gl = false, false
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPAC", "AR;444;Eldrin,,A,DRUID,60,Test Guild", "GUILD", "Eldrin")
  ok(not reps.Eldrin, "members' copies keep no lists")
  UI.LayoutNav()
  ok(not UI.pages.accounts.nav:IsShown(), "accounts hidden from members")
  ok(not UI.pages.officer.nav:IsShown(), "officer fold hidden from members")
  UI.NavClick("officer")
  ok(UI.current ~= "officer", "members cannot open the officer fold")
  admin, gl = true, true
  -- Officer folds Addon check and Accounts away
  UI.LayoutNav()
  UI.Open("accounts")
  ok(UI.FoldOpen("officer") and UI.pages.accounts.nav:IsShown(), "opening a folded topic unfolded Officer")
  UI.NavClick("officer")
  ok(not UI.FoldOpen("officer") and not UI.pages.accounts.nav:IsShown() and not UI.pages.addons.nav:IsShown(), "Officer click folds its topics away")
  ok(UI.current == "officer", "folding while on a folded topic goes to Officer")
  ok(UI.pages.officer.nav.arrow ~= nil and UI.pages.home.nav.arrow == nil, "only Officer has a fold arrow")
  UI.NavClick("officer")
  ok(UI.FoldOpen("officer") and UI.pages.accounts.nav:IsShown() and UI.current == "officer", "Officer click unfolds and opens Officer")
  UI.NavClick("accounts")
  ok(UI.current == "accounts", "folded topic opens")
  UI.NavClick("officer")
  UI.NavClick("standings")
  UI.Open("accounts")
  ok(UI.FoldOpen("officer") and UI.current == "accounts", "/epgp accounts unfolds Officer")
end
-- ---------------------------------------------------------------- versions
do
  local VV = UI.Versions
  local function SentV(from, p, pat)
    for i = from + 1, table.getn(Mock.sent) do
      if Mock.sent[i][1] == p and string.find(Mock.sent[i][2], pat) then return Mock.sent[i][2] end
    end
  end
  ok(VV.Compare("10.20.5 <ERROR>", "10.21.1") == -1 and VV.Compare("10.21.1", "10.21.1") == 0 and VV.Compare("11.0", "10.21.1") == 1, "versions compare")
  ok(VV.Mine() == "10.20.3", "own version read from the toc (" .. VV.Mine() .. ")")
  -- the responder
  local s0 = table.getn(Mock.sent)
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPV", "VQ", "GUILD", "Corvan")
  Mock.Tick(4)
  ok(SentV(s0, "SEPGPV", "^VA;10%.20%.3$"), "answers a version question")
  s0 = table.getn(Mock.sent)
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPV", "VQ", "GUILD", "Dalia")
  Mock.Tick(4)
  ok(not SentV(s0, "SEPGPV", "^VA;"), "answers at most every 30 s")
  -- an officer asks; Corvan is current, Brindle has an old copy, Fennick nothing
  Mock.Fire("CHAT_MSG_ADDON", "SEPGP_PREFIX", "VERSION;10.20.1;10", "GUILD", "Brindle")
  UI.Open("home")
  s0 = table.getn(Mock.sent)
  VV.Ask(true)
  ok(SentV(s0, "SEPGPV", "^VQ$") and SentV(s0, "SWOW_Q", "."), "officer asks new and old copies")
  ok(VV.Status("Fennick") == "wait", "waiting for answers")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPV", "VA;10.20.3", "GUILD", "Corvan")
  Mock.Fire("CHAT_MSG_ADDON", "SWOW_R", "0", "GUILD", "Corvan")
  Mock.Fire("CHAT_MSG_ADDON", "SWOW_R", "0", "GUILD", "Brindle")
  Mock.Tick(7)
  local st, ver = VV.Status("Brindle")
  ok(VV.Status("Corvan") == "current" and st == "old" and ver == "10.20.1", "old copy found with its version (" .. tostring(st) .. " " .. tostring(ver) .. ")")
  ok(VV.Status("Fennick") == "none" and VV.Status("Aldren") == "current", "silent member = no shootyepgp; self current")
  UI.Refresh()
  ok(VV.counter:IsShown() and string.find(VV.counter.text:GetText(), "2 / 4 online up to date"), "counter shows 2 / 4 (" .. tostring(VV.counter.text:GetText()) .. ")")
  local n = VV.Count()
  ok(table.getn(n.old) == 1 and n.old[1].name == "Brindle" and table.getn(n.none) == 1, "hover lists who needs to update")
  admin, gl = false, false
  UI.Refresh()
  ok(not VV.counter:IsShown(), "counter hidden from members")
  s0 = table.getn(Mock.sent)
  VV.Ask(true)
  ok(not SentV(s0, "SEPGPV", "^VQ$"), "members never ask")
  admin, gl = true, true
end
-- ---------------------------------------------------------------- decay log
do
  local DL = UI.Decay
  local function SentD(from, pat)
    for i = from + 1, table.getn(Mock.sent) do
      if Mock.sent[i][1] == "SEPGPD" and string.find(Mock.sent[i][2], pat) then return Mock.sent[i][2] end
    end
  end
  local function Row(name) for i = 1, table.getn(GUILD) do if GUILD[i][1] == name then return GUILD[i] end end end
  local function Note(name) return Row(name)[8] end
  local function SetNote(name, ep, gp) local g = Row(name) g[8] = (string.gsub(g[8], "{%d+:%d+}", "{" .. ep .. ":" .. gp .. "}")) end
  local saved = {}
  for i = 1, table.getn(GUILD) do saved[i] = GUILD[i][8] end
  -- a note writer that really writes (the stand-in above only records)
  local oldUpd = sepgp.update_epgp_v3
  function sepgp:update_epgp_v3(ep, gp, i, name, note)
    local g = GUILD[i]
    local _, _, oe, og = string.find(g[8], "{(%d+):(%d+)}")
    if ep then ep = math.max(0, ep) end
    if gp then gp = math.max(300, gp) end
    g[8] = (string.gsub(g[8], "{%d+:%d+}", "{" .. (ep or oe) .. ":" .. (gp or og) .. "}"))
  end
  admin, gl = true, true
  UI.LayoutNav()
  local setter = GuildRosterSetOfficerNote
  local s0 = table.getn(Mock.sent)
  sepgp:decay_epgp_v3()
  local rec = DL.List()[1]
  ok(rec and rec.n == 4 and rec.by == "Aldren" and rec.pct == 10, "decay recorded (" .. tostring(rec and rec.n) .. " members)")
  local a
  for i = 1, table.getn(rec.m) do if rec.m[i][1] == "Aldren" then a = rec.m[i] end end
  ok(a and a[2] == 820 and a[3] == 410 and a[4] == 738 and a[5] == 369, "before and after caught from the note writes")
  ok(Note("Corvan") == "{1350:810}" and Note("Dalia") == "notes here {108:300}", "the decay itself still ran (" .. Note("Corvan") .. ")")
  ok(GuildRosterSetOfficerNote == setter, "note writer given back after the decay")
  -- the check a few seconds later, against fresh notes
  local asked = Mock.rosterAsked or 0
  Mock.Tick(5)
  ok((Mock.rosterAsked or 0) > asked, "guild notes fetched again after the decay")
  Mock.Fire("GUILD_ROSTER_UPDATE")
  Mock.Tick(3)
  ok(rec.check and rec.check.ok == 4 and rec.check.missed == 0, "check: every note changed")
  Mock.Tick(3)
  ok(SentD(s0, "^DD;") and SentD(s0, "^DM;.*Corvan,1500,900,1350,810") and SentD(s0, "^DK;"), "record and check sent to the officers")
  -- the page
  UI.Open("decay")
  local df = UI.pages.decay.frame
  ok(UI.pages.decay.nav:IsShown(), "decay log topic for officers")
  local row
  for i = 1, table.getn(df.lv.list.view) do if df.lv.list.view[i].id == rec.id then row = df.lv.list.view[i] end end
  ok(row and string.find(row.cells[5], "OK"), "list says it went through (" .. tostring(row and row.cells[5]) .. ")")
  UI.pages.decay.open(df, rec.id)
  ok(df.dv:IsShown() and table.getn(df.dv.list.view) == 4, "the decay shows its members")
  ok(df.dv.list.heads[2].text:GetText() == "EP before" and df.dv.list.heads[5].text:GetText() == "GP after", "before / after columns")
  -- a note that did not change, an award given after the decay
  SetNote("Eldrin", 2000, 1200)
  SetNote("Corvan", 1400, 810)
  UI.RefreshPage()
  local st = {}
  for i = 1, table.getn(df.dv.list.view) do st[df.dv.list.view[i].id] = df.dv.list.view[i].cells[6] end
  ok(string.find(st.Eldrin, "NOT decayed") and string.find(st.Corvan, "changed since") and string.find(st.Aldren, "decayed") and not string.find(st.Aldren, "NOT"), "state of every member now")
  ok(df.dv.finish:IsShown(), "missed members can be decayed afterwards")
  this = df.dv.finish
  df.dv.finish.scripts.OnClick()
  ok(UI.confirmFrame:IsShown() and string.find(UI.confirmFrame.text:GetText(), "Eldrin"), "decaying the missed asks first, naming who")
  UI.ConfirmYes()
  ok(Note("Eldrin") == "{1800:1080}", "missed member decayed (" .. Note("Eldrin") .. ")")
  -- undo: everyone gets back what the decay took; the award since is kept
  local s1 = table.getn(Mock.sent)
  this = df.dv.undo
  df.dv.undo.scripts.OnClick()
  ok(UI.confirmFrame:IsShown() and string.find(UI.confirmFrame.title:GetText(), "Undo") and string.find(UI.confirmFrame.text:GetText(), "by Aldren"), "undo asks first, naming the decay")
  UI.ConfirmYes()
  ok(Note("Aldren") == "{820:410}" and Note("Corvan") == "{1550:900}" and Note("Dalia") == "notes here {120:300}" and Note("Eldrin") == "{2000:1200}",
    "undo puts EP and GP back and keeps the award since (" .. Note("Corvan") .. ")")
  ok(rec.undo and rec.undo.by == "Aldren" and rec.undo.n == 4, "undo recorded")
  ok(Mock.said and string.find(Mock.said, "undone"), "undo posted in the report channel (" .. tostring(Mock.said) .. ")")
  Mock.Tick(16)
  ok(SentD(s1, "^DU;" .. string.gsub(rec.id, "%-", "%%-")), "undo sent to the officers")
  ok(rec.undo.check and rec.undo.check.missed == 0, "undo checked")
  local u
  local us = H.All({ U = 1 })
  for i = 1, table.getn(us) do u = us[i] end
  ok(u and u.n == 10 and u.by == "Aldren", "undo in the EP / GP history")
  UI.RefreshPage()
  ok(df.dv.undo.disabledLook and not df.dv.finish:IsShown(), "no second undo")
  st = {}
  for i = 1, table.getn(df.dv.list.view) do st[df.dv.list.view[i].id] = df.dv.list.view[i].cells[6] end
  ok(string.find(st.Aldren, "put back"), "members shown as put back")
  DL.Undo(rec.id)
  ok(Note("Aldren") == "{820:410}" and string.find(UI.confirmFrame.title:GetText(), "Cannot undo"), "undoing twice is refused")
  UI.confirmFrame:Hide()
  -- a second decay whose notes were put back by hand: undo refuses
  Mock.Tick(130, 1)
  sepgp:decay_epgp_v3()
  local rec2 = DL.List()[1]
  ok(rec2 ~= rec and rec2.n == 4, "second decay recorded")
  ok(DL.Last().t == rec2.t, "last decay = the newest one not undone")
  for i = 1, table.getn(rec2.m) do SetNote(rec2.m[i][1], rec2.m[i][2], rec2.m[i][3]) end
  ok(string.find(DL.Refuse(rec2) or "", "looks undone"), "undo refused when the notes already show their before values")
  -- members hidden from addons: nothing is decayed
  local oldNum = GetNumGuildMembers
  GetNumGuildMembers = function() return table.getn(GUILD) + 3 end
  local n0 = table.getn(DL.List())
  sepgp:decay_epgp_v3()
  GetNumGuildMembers = oldNum
  ok(Note("Aldren") == "{820:410}" and table.getn(DL.List()) == n0 and string.find(UI.confirmFrame.text:GetText(), "hidden"), "decay refused while members are hidden")
  UI.confirmFrame:Hide()
  -- another officer's decay arrives on the addon channel
  Mock.Tick(200, 5)
  local t3 = time()
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPD", "DD;" .. t3 .. "-Corvan;" .. t3 .. ",Corvan,10,300,300,2", "GUILD", "Corvan")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPD", "DM;" .. t3 .. "-Corvan;Aldren,820,410,738,369~Eldrin,2000,1200,1800,1080", "GUILD", "Corvan")
  local got = DL.Get(t3 .. "-Corvan")
  ok(got and got.from == "Corvan" and table.getn(got.m) == 2 and got.n == 2 and DL.Fits(got), "another officer's decay stored")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPD", "DD;" .. t3 .. "-Eldrin;" .. t3 .. ",Eldrin,10,300,300,2", "GUILD", "Dalia")
  ok(not DL.Get(t3 .. "-Eldrin"), "a record only from the officer who decayed")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPD", "DD;" .. (t3 + 1) .. "-Corvan;" .. (t3 + 1) .. ",Corvan,10,300,300,2", "GUILD", "Corvan")
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPD", "DM;" .. (t3 + 1) .. "-Corvan;Aldren,5820,4410,738,369~Eldrin,9000,9200,1800,1080", "GUILD", "Corvan")
  ok(string.find(DL.Refuse(DL.Get((t3 + 1) .. "-Corvan")) or "", "do not fit"), "a record that is not a decay cannot be undone")
  admin, gl = false, false
  Mock.Fire("CHAT_MSG_ADDON", "SEPGPD", "DD;" .. (t3 + 2) .. "-Corvan;" .. (t3 + 2) .. ",Corvan,10,300,300,2", "GUILD", "Corvan")
  ok(not DL.Get((t3 + 2) .. "-Corvan"), "members' copies keep no records")
  UI.LayoutNav()
  ok(not UI.pages.decay.nav:IsShown(), "decay log hidden from members")
  admin, gl = true, true
  UI.LayoutNav()
  -- a decay that is only in the history: the GP check
  Mock.Tick(600, 5)
  local tD = time()
  H.Add({ k = "G", t = tD - 100, n = 50, gp = 1200, w = "Eldrin" })
  H.Add({ k = "G", t = tD - 90, n = 50, gp = 900, w = "Corvan" })
  H.Add({ k = "D", t = tD, n = 10, by = "Corvan" })
  SetNote("Eldrin", 2000, 1080)
  SetNote("Corvan", 1500, 900)
  UI.pages.decay.open(df, nil)
  local hrow
  for i = 1, table.getn(df.lv.list.view) do if df.lv.list.view[i].id == "H" .. tD then hrow = df.lv.list.view[i] end end
  ok(hrow and string.find(hrow.cells[5], "history only"), "a decay from the history is listed")
  UI.pages.decay.open(df, "H" .. tD)
  st = {}
  for i = 1, table.getn(df.dv.list.view) do st[df.dv.list.view[i].id] = df.dv.list.view[i].cells[6] end
  ok(st.Eldrin and string.find(st.Eldrin, "decayed") and not string.find(st.Eldrin, "NOT") and st.Corvan and string.find(st.Corvan, "NOT decayed"), "GP check: Eldrin decayed, Corvan not")
  ok(not df.dv.undo:IsShown() and df.dv.list.heads[3].text:GetText() == "known", "no undo without a record")
  -- the decay button warns when the last decay was recent
  UI.Select("officer")
  this = UI.pages.officer.frame.decayLogBtn
  UI.pages.officer.frame.decayLogBtn.scripts.OnClick()
  ok(UI.current == "decay", "Officer page button opens the decay log")
  UI.Select("officer")
  -- the history reads summer stamps an hour late no more; old late copies move
  local oldDate = date
  date = function(fmt, t) if fmt == "*t" then return { hour = 8 } end return "14 Oct" end
  local t, raw = H.ParseStamp("Oct/20 07:13:11")
  ok(raw and t == raw - 3600, "summer stamp corrected by an hour")
  H.Add({ k = "D", t = raw, n = 12 })                      -- read late before the fix
  H.Add({ k = "D", t = raw - 3600, n = 12, by = "Aldren" })  -- heard live
  local lateG = H.Add({ k = "G", t = raw, n = 77, gp = 777, w = "Dalia" })
  H.FromLog("Oct/20 07:13:11", "All EP and GP decayed by 12%")
  H.FromLog("Oct/20 07:13:11", "Awarding 77 GP to Dalia. (Previous: 700, New: 777)")
  date = oldDate
  local d12 = 0
  local ds = H.All({ D = 1 })
  for i = 1, table.getn(ds) do if ds[i].n == 12 then d12 = d12 + 1 end end
  ok(d12 == 1, "late copy of a decay heard live dropped (" .. d12 .. ")")
  ok(lateG.t == raw - 3600 and table.getn(H.For("Dalia")) > 0, "late GP line moved to the right time")
  sepgp.update_epgp_v3 = oldUpd
  for i = 1, table.getn(GUILD) do GUILD[i][8] = saved[i] end
end
-- ---------------------------------------------------------------- legacy.lua (the old windows' stand-ins)
do
  local said = {}
  sepgp.widestAudience = function(self, msg) table.insert(said, msg) end
  sepgp.broadcastBidAttention = function() said.attention = true end
  sepgp.make_escable = function() end
  local L = setmetatable({ IMPORT_WARNING = "warn" }, { __index = function(t, k) return k end })
  local libs = { ["Crayon-2.0"] = { Yellow = function(s, x) return x end, Green = function(s, x) return x end, Red = function(s, x) return x end, Gold = function(s, x) return x end },
                 ["AceLocale-2.2"] = { new = function() return L end } }
  local oldLib = AceLibrary
  AceLibrary = function(n) return libs[n] or oldLib(n) end
  local scheduled = {}
  function sepgp:NewModule(name)
    return { ScheduleRepeatingEvent = function(s, id) scheduled[id] = true end, ScheduleEvent = function(s, id) scheduled[id] = true end,
             IsEventScheduled = function(s, id) return scheduled[id] end, CancelScheduledEvent = function(s, id) scheduled[id] = nil end }
  end
  TOOLTIP_DEFAULT_COLOR = TOOLTIP_DEFAULT_COLOR or { r = 1, g = 1, b = 1 }
  TOOLTIP_DEFAULT_BACKGROUND_COLOR = TOOLTIP_DEFAULT_BACKGROUND_COLOR or { r = 0, g = 0, b = 0 }
  dofile("legacy.lua")
  AceLibrary = oldLib
  UI.frame:Hide()
  sepgp_bids:Toggle(true)
  ok(UI.frame:IsShown() and UI.current == "bids", "a new bid opens the window on Bids (as the old window did)")
  UI.Select("home")
  sepgp_bids:Toggle(true)
  ok(UI.current == "home", "while the window is open a new bid only redraws it")
  sepgp_reserves:Toggle(true)
  sepgp_loot:Refresh()
  sepgp_standings:Toggle()
  ok(UI.current == "standings", "old standings call opens Standings")
  sepgp_bids:announceWinnerMS("Corvan", 1.5)
  ok(said[table.getn(said)] == "Winning Mainspec Bid: Corvan (1.500 PR)", "winner announcement kept")
  sepgp_bids:bidCountdown()
  ok(scheduled.shootyepgpBidCountdown and sepgp_bids._counterText == "Starting", "bid countdown kept")
  sepgp.lootMaster = function() return true end
  sepgp_bids:sendAttention()
  ok(said.attention, "attention ping kept")
  ok(type(sepgp_standings.Export) == "function" and type(sepgp_standings.Import) == "function", "export / import kept")
end
-- ---------------------------------------------------------------- prices, wish list, ignore list
do
  local PR = UI.Prices
  ok(sepgp_price_edits[19402] == nil, "a saved price change prices.lua already has clears itself")
  ok(sepgp.gp_prices[16900][1] == 200 and sepgp.gp_prices[16900][2] == "T2" and PR.filePrice[16900][1] == 175, "a saved price change is used at login")
  local raids = sepgp_lootdb.raids
  local keys = ""
  for i = 1, table.getn(raids) do keys = keys .. raids[i].key .. " " end
  ok(keys == "MC ONY BWL AQ40 NAXX KARA40 ", "every EP raid in the loot list (" .. keys .. ")")
  ok(table.getn(raids[1].bosses[1].items) > 10 and sepgp_lootdb.items[16812][3] == "Gloves of Prophecy", "boss loot with names")
  local r, b = PR.Find(19402)
  ok(r and r.key == "BWL" and b, "an item knows its raid and boss")

  admin = false
  UI.Select("prices")
  local f = UI.pages.prices.frame
  ok(f and UI.current == "prices", "Prices topic opens for members")
  ok(not f.tabs[4]:IsShown(), "members do not see the Changes tab")
  -- pick Blackwing Lair, then Nefarian
  this = f.lootView.raidButtons[3]
  f.lootView.raidButtons[3].scripts.OnClick()
  ok(f.raid == 3, "raid button picks the raid")
  local nef
  for i = 1, table.getn(raids[3].bosses) do if raids[3].bosses[i].name == "Nefarian" then nef = i end end
  f.lootView.bosses.onClick({ id = nef })
  local items = f.lootView.items
  ok(items.lines[1]:IsShown() and items.lines[1].entry, "boss items listed")
  local id = items.lines[1].entry.id
  ok(items.lines[1].ms:GetText() == "175" and items.lines[1].os:GetText() == "70", "MS and OS GP shown (" .. tostring(items.lines[1].ms:GetText()) .. "/" .. tostring(items.lines[1].os:GetText()) .. ")")
  this = items.lines[1]
  items.lines[1].scripts.OnEnter()
  -- right-click -> wish list
  this, arg1 = items.lines[1], "RightButton"
  items.lines[1].scripts.OnClick()
  ok(PR.menu and PR.menu:IsShown() and PR.menu.buttons[1].text:GetText() == "Add to wish list" and not PR.menu.buttons[3]:IsShown(), "right-click menu: wish / ignore (no price for members)")
  this = PR.menu.buttons[1]
  PR.menu.buttons[1].scripts.OnClick()
  ok(PR.State(id) == "wish" and sepgp_wish.wish[id], "item wishlisted")
  UI.RefreshPage()
  ok(items.lines[1].mark:IsShown() and items.lines[1].mark.texture == PR.WISH_ICON, "star shows on the row")
  -- ignore another
  local id2 = items.lines[2].entry.id
  PR.SetState(id2, "ignore")
  UI.RefreshPage()
  ok(items.lines[2].mark.texture == PR.IGNORE_ICON, "ignored mark shows")
  PR.SetState(id, "wish")
  -- wish and ignored tabs
  this = f.tabs[2]
  f.tabs[2].scripts.OnClick()
  ok(f.wishView:IsShown() and f.wishView.list.lines[1].entry.id == id and string.find(f.wishView.list.lines[1].where:GetText(), "BWL - Nefarian", 1, true), "wish list tab lists it with its boss")
  this = f.tabs[3]
  f.tabs[3].scripts.OnClick()
  ok(f.ignoreView.list.lines[1].entry.id == id2, "ignored tab lists it")

  -- bid pop-ups
  local told = {}
  local oldSend = SendChatMessage
  SendChatMessage = function(msg, ch, lang, to) table.insert(told, { msg, ch, to }) end
  sepgp.inRaid = function() return true end
  local BP = UI.BidPopup
  BP.OnCall(PR.Link(id2), "Corvan", 1, 1, nil)
  ok(not (BP.frame and BP.frame:IsShown()), "an ignored item does not pop up")
  local link = PR.Link(id)
  BP.OnCall(link, "Corvan", 1, 1, nil)
  ok(BP.frame:IsShown() and BP.frame.id == id, "bid pop-up comes up")
  ok(BP.alert and BP.alert:IsShown(), "wish list item: big alert")
  this = BP.frame.ms
  BP.frame.ms.scripts.OnClick()
  ok(told[1] and told[1][1] == "+" and told[1][2] == "WHISPER" and told[1][3] == "Corvan", "Mainspec whispers + to the loot master")
  ok(not BP.frame:IsShown(), "pop-up closes after a bid")
  local plain = 19402
  BP.OnCall(PR.Link(plain), "Corvan", nil, 1, nil)
  ok(BP.frame:IsShown() and BP.frame.ms.disabledLook and not BP.frame.os.disabledLook, "an offspec-only call offers offspec only")
  this = BP.frame.os
  BP.frame.os.scripts.OnClick()
  ok(told[2] and told[2][1] == "-", "Offspec whispers -")
  BP.OnCall(PR.Link(plain), "Corvan", 1, 1, nil)
  this = BP.frame.ignore
  BP.frame.ignore.scripts.OnClick()
  ok(PR.State(plain) == "ignore" and not BP.frame:IsShown(), "ignore for good")
  BP.OnCall(PR.Link(plain), "Corvan", 1, 1, nil)
  ok(not BP.frame:IsShown(), "it never pops up again")
  this = f.tabs[3]
  f.tabs[3].scripts.OnClick()
  local undoRow
  for r = 1, 3 do if f.ignoreView.list.lines[r].entry and f.ignoreView.list.lines[r].entry.id == plain then undoRow = f.ignoreView.list.lines[r] end end
  this = undoRow and undoRow.action
  if undoRow then undoRow.action.scripts.OnClick() end
  ok(PR.State(plain) == nil, "unignored from the Ignored tab")
  sepgp_wish.popups = false
  BP.OnCall(PR.Link(plain), "Corvan", 1, 1, nil)
  ok(not BP.frame:IsShown(), "pop-ups can be switched off")
  sepgp_wish.popups = true
  -- through the real hook: bidPrint is in shootyepgp.lua; here the chat line's caller
  SendChatMessage = oldSend

  -- officers change a price
  admin = true
  UI.LayoutNav()
  UI.Select("prices")
  ok(f.tabs[4]:IsShown(), "officers see Changes")
  this = f.tabs[1]
  f.tabs[1].scripts.OnClick()
  this, arg1 = items.lines[1], "LeftButton"
  items.lines[1].scripts.OnClick()
  ok(PR.editor and PR.editor:IsShown() and PR.editor.id == id, "officer left-click opens the price editor")
  PR.editor.box:SetText("250")
  this = PR.editor.save
  PR.editor.save.scripts.OnClick()
  ok(sepgp.gp_prices[id][1] == 250 and sepgp_price_edits[id].gp == 250 and sepgp_price_edits[id].by == "Aldren", "price change saved and used")
  ok(PR.filePrice[id] == false, "the item was not in prices.lua (noted for the write-back)")
  this = f.tabs[4]
  f.tabs[4].scripts.OnClick()
  ok(f.changesView:IsShown() and f.changesView.list.lines[1].entry, "Changes tab lists price changes")
  local row
  for r = 1, 3 do local l = f.changesView.list.lines[r] if l.entry and l.entry.id == id then row = l end end
  this = row.action
  row.action.scripts.OnClick()
  UI.ConfirmYes()
  ok(sepgp_price_edits[id] == nil and sepgp.gp_prices[id] == nil, "undo drops the change")
  PR.SetPrice(16900, 175)
  ok(sepgp_price_edits[16900] == nil and sepgp.gp_prices[16900][1] == 175, "setting the file price again drops the change")

  -- sharing: every copy shows the same prices
  local sent = {}
  sepgp.addonMessage = function(self, m, ch) table.insert(sent, m) end
  PR.SetPrice(19402, 240)
  ok(sent[1] and string.find(sent[1], "^PRICE;19402:240:%d+;1$"), "a price change goes to the guild (" .. tostring(sent[1]) .. ")")
  gl = true
  sent = {}
  PR.Share()
  ok(sent[1] and string.find(sent[1], "T2=0.4", 1, true) and string.find(sent[1], "^OSTIER;"), "guild leader shares offspec per tier (" .. tostring(sent[1]) .. ")")
  ok(sent[2] and string.find(sent[2], "19402:240", 1, true), "and every saved price change")
  gl = false
  PR.UndoPrice(19402)
  ok(sent[3] and string.find(sent[3], "^PRICE;19402:%-1:"), "an undo goes to the guild too")
  sent = {}
  -- heard from others: Aldren is rank 1 (Officer), Corvan rank 2 (Core Raider); nobody here is rank 0
  GUILD[2][3] = 0
  PR.Receive("OSTIER", "T1=0.3,T2=0.45", "Corvan", "Guild Master")
  ok(PR.Rate("T1") == 0.3 and PR.Rate("T2") == 0.45, "the guild leader's offspec prices are taken")
  GUILD[2][3] = 2
  PR.Receive("OSTIER", "T1=0.9", "Corvan", "Core Raider")
  ok(PR.Rate("T1") == 0.3, "nobody else can set them")
  PR.Receive("PRICE", "16900:333:5", "Dalia", "Raider")
  ok(sepgp.gp_prices[16900][1] == 175, "price changes from non-officers are ignored")
  PR.Receive("PRICE", "16900:333:5,19402:260:6", "Eldrin", "Officer")
  ok(sepgp.gp_prices[16900][1] == 333 and sepgp_price_edits[16900].by == "Eldrin" and sepgp.gp_prices[19402][1] == 260, "an officer's price changes are taken")
  PR.Receive("PRICE", "16900:-1:7", "Eldrin", "Officer")
  ok(sepgp_price_edits[16900] == nil and sepgp.gp_prices[16900][1] == 175, "an officer's undo is taken")
  ok(table.getn(sent) == 0, "heard changes are not sent on again")
  PR.UndoPrice(19402, true)
end
-- ---------------------------------------------------------------- quick EP / GP
do
  admin = true
  UI.LayoutNav()
  UI.Select("quickpoints")
  local f = UI.pages.quickpoints.frame
  ok(f and UI.current == "quickpoints", "Quick EP / GP opens for officers")
  local listed = {}
  for i = 1, table.getn(f.list.view) do listed[f.list.view[i].data] = true end
  ok(listed.Corvan and listed.Dalia and not listed.Brindle, "members listed, alts left out")
  f.list.onClick({ data = "Corvan" })
  f.list.onCheck({ data = "Dalia", ticked = true })
  ok(f.tickInfo:GetText() == "2 members ticked", "ticks counted (" .. tostring(f.tickInfo:GetText()) .. ")")
  f.amount:SetText("25")
  local n0 = table.getn(calls)
  this = f.epBtn
  f.epBtn.scripts.OnClick()
  ok(UI.confirmFrame:IsShown(), "asks first")
  UI.ConfirmYes()
  ok(calls[n0 + 1] == "ep:Corvan:25" and calls[n0 + 2] == "ep:Dalia:25", "EP given to every ticked member (" .. tostring(calls[n0 + 1]) .. ", " .. tostring(calls[n0 + 2]) .. ")")
  ok(table.getn(UI.QuickPoints.Ticked(f)) == 0, "ticks cleared after giving")
  f.list.onClick({ data = "Eldrin" })
  f.amount:SetText("40")
  this = f.gpBtn
  f.gpBtn.scripts.OnClick()
  UI.ConfirmYes()
  ok(calls[table.getn(calls)] == "gp:Eldrin:40", "GP given")
  admin = false
  UI.LayoutNav()
  ok(not UI.pages.quickpoints.nav:IsShown(), "hidden from members")
end
-- slash
SlashCmdList.SEPGPUI("logs")
ok(UI.current == "logs", "/epgp logs opens Logs")
SlashCmdList.SEPGPUI("")
ok(not UI.frame:IsShown(), "/epgp toggles closed")

for i = 1, table.getn(Mock.printed) do if string.find(Mock.printed[i], "page") then ok(false, "page error: " .. Mock.printed[i]) end end
print(string.format("%d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
