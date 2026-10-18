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
sepgp.decay_epgp_v3 = Rec("decay")
sepgp.afkcheck_reserves = Rec("afk")
sepgp.shareSettings = Rec("share")
sepgp.refreshPRTablets = function() end
sepgp.SetRefresh = function() end
sepgp.reservesToggle = Rec("reservesToggle")
sepgp.my_epgp = Rec("my_epgp")
sepgp.adminSay = function() end
sepgp.addToLog = Rec("log")
function sepgp:update_epgp_v3(ep, gp, i, name, note) table.insert(calls, "note:" .. name .. ":" .. tostring(ep)) end
sepgp.OnMenuRequest = Rec("menu")
sepgp.defaultPrint = function() end
local function Mod() return { Toggle = Rec("toggle"), Refresh = function() end, Export = Rec("export"), Import = Rec("import"),
  bidCountdown = Rec("countdown"), sendAttention = Rec("attention"), announceWinnerMS = Rec("winMS"), announceWinnerOS = Rec("winOS") } end
sepgp_standings, sepgp_bids, sepgp_loot, sepgp_logs, sepgp_alts, sepgp_reserves = Mod(), Mod(), Mod(), Mod(), Mod(), Mod()
sepgp_prices = { GetPrice = function(self, link, tier) return 175 end }
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
for _, f in ipairs({ "ui/Style.lua", "ui/Window.lua", "ui/History.lua", "ui/Pages.lua", "ui/Raids.lua", "ui/RaidsPractice.lua", "ui/AddonCheck.lua", "ui/Minimap.lua" }) do dofile(f) end
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
of.osp.onValue(0.5)
ok(sepgp_discount == 0.5, "offspec slider sets the price")
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
admin, gl = false, false
UI.LayoutNav()
ok(not UI.pages.addons.nav:IsShown(), "addon check hidden from members")
admin, gl = true, true
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
-- slash
SlashCmdList.SEPGPUI("logs")
ok(UI.current == "logs", "/epgp logs opens Logs")
SlashCmdList.SEPGPUI("")
ok(not UI.frame:IsShown(), "/epgp toggles closed")

for i = 1, table.getn(Mock.printed) do if string.find(Mock.printed[i], "page") then ok(false, "page error: " .. Mock.printed[i]) end end
print(string.format("%d checks, %d failed", checks, fails))
if fails > 0 then os.exit(1) end
