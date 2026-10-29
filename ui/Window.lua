-- shootyepgp :: new window, part 2 - data, window frame, topic list
-- One window for everything shootyepgp knows: your EPGP at the top, topics
-- on the left (Home, Standings, Bids, Loot, Reserves, Alts, Logs, Strikes,
-- Tools, Settings, Officer), the topic's page on the right.
--
-- The window only READS the addon's data (guild officer notes, sepgp_log,
-- sepgp_looted, sepgp.bids_*, sepgp.reserves, RaidStrikeDB). Anything that
-- changes data calls the addon's own functions - the same ones its old
-- right-click menu calls - and asks "are you sure" first.

local UI = SEPGP_UI
local C = UI.C

UI.pages, UI.order = {}, {}
local WIDTH, HEIGHT = 860, 580
local NAV_W = 150
UI.PAGE_W = WIDTH - NAV_W - 24 - 6 - 16   -- usable page width (664)
UI.PAGE_H = HEIGHT - 96 - 12 - 16         -- usable page height (456)

-- ------------------------------------------------------------------ settings

local DEFAULTS = {
  minimapPos = 200,
  minimapHide = false,
  scale = 1,
  alpha = 0.97,
  page = "home",
}
function UI.DB()
  if type(sepgp_ui) ~= "table" then sepgp_ui = {} end
  for k, v in pairs(DEFAULTS) do
    if sepgp_ui[k] == nil then sepgp_ui[k] = v end
  end
  return sepgp_ui
end

-- ------------------------------------------------------------------ data

function UI.IsAdmin() return CanEditOfficerNote() and true or false end
function UI.IsGL() return IsGuildLeader() and true or false end
function UI.Ready() return sepgp and sepgp.VARS and sepgp.get_ep_v3 and true or false end

function UI.Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33b3ffshootyepgp:|r " .. tostring(msg))
end

local MONTHS = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }
-- "Sep/27 18:44:56" -> a number that sorts by time (within a year)
function UI.TimeKey(stamp)
  local _, _, mon, d, h, m, s = string.find(stamp or "", "(%a+)/(%d+) (%d+):(%d+):(%d+)")
  if not mon then return 0 end
  return (((((MONTHS[mon] or 0) * 32 + tonumber(d)) * 24 + tonumber(h)) * 60 + tonumber(m)) * 60) + tonumber(s)
end

-- Ask the server for fresh guild notes, at most every 15 s.
function UI.RequestRoster(force)
  local now = GetTime()
  if IsInGuild() and (force or not UI.lastRequest or now - UI.lastRequest > 15) then
    UI.lastRequest = now
    GuildRoster()
  end
end

-- The addon's standings order: members at / above minimum EP first, then PR,
-- then EP (standings.lua pr_sorter_standings).
local function StandingsOrder(a, b)
  local minep = sepgp_minep or 0
  if minep > 0 then
    local ao, bo = a.ep >= minep, b.ep >= minep
    if ao ~= bo then return ao end
  end
  if a.pr ~= b.pr then return a.pr > b.pr end
  if a.ep ~= b.ep then return a.ep > b.ep end
  return a.name < b.name
end

-- Every guild member with their EPGP read from the officer note.
-- UI.roster = list, UI.byName[name] = member. Mains of alts are read the same
-- way sepgp:parseAlt does ({Main} in the officer note, Main in the guild and
-- at least sepgp.VARS.minlevel) without scanning the roster per alt.
function UI.Roster(force)
  if not UI.Ready() then return {}, {} end
  if UI.roster and not force and not UI.rosterDirty then return UI.roster, UI.byName end
  UI.rosterDirty = nil
  local basegp, minlevel = sepgp.VARS.basegp, sepgp.VARS.minlevel
  local raid = {}
  for i = 1, GetNumRaidMembers() do
    local n = GetRaidRosterInfo(i)
    if n then raid[n] = true end
  end
  local list, byName, lower = {}, {}, {}
  for i = 1, GetNumGuildMembers(1) do
    local name, rank, rankIndex, level, class, zone, note, onote, online = GetGuildRosterInfo(i)
    if name and name ~= "" then
      onote = onote or ""
      local ep = sepgp:get_ep_v3(name, onote)
      local gp = sepgp:get_gp_v3(name, onote)
      local m = {
        name = name, rank = rank or "", rankIndex = rankIndex or 0, level = tonumber(level) or 0,
        class = class, zone = zone or "", online = online and true or false, note = onote,
        hasEPGP = (ep ~= nil), ep = ep or 0, gp = gp or basegp, inRaid = raid[name],
      }
      if m.gp <= 0 then m.gp = basegp end
      m.pr = m.ep / m.gp
      table.insert(list, m)
      byName[name] = m
      lower[string.lower(name)] = m
    end
  end
  -- alts: {Main} in the officer note
  for i = 1, table.getn(list) do
    local m = list[i]
    local _, _, _, main = string.find(m.note, "(.*){([%a][%a]%a*)}(.*)")
    if main and string.len(main) < 13 then
      local mm = lower[string.lower(main)]
      if mm and mm.level >= minlevel and mm ~= m then
        m.main = mm.name
        mm.alts = mm.alts or {}
        table.insert(mm.alts, m.name)
      end
    end
  end
  -- standings places (only members with EP, as the old standings list)
  local ranked = {}
  for i = 1, table.getn(list) do
    if list[i].ep > 0 then table.insert(ranked, list[i]) end
  end
  table.sort(ranked, StandingsOrder)
  for i = 1, table.getn(ranked) do ranked[i].pos = i end
  UI.roster, UI.byName, UI.ranked = list, byName, ranked
  return list, byName
end

-- Whose EPGP is "yours": your own, or your main's when this character is an alt.
function UI.Me()
  local _, byName = UI.Roster()
  local me = sepgp and sepgp._playerName or UnitName("player")
  local m = byName[me]
  if m and m.main and byName[m.main] then return byName[m.main], m end
  if not m and sepgp_main and byName[sepgp_main] then return byName[sepgp_main], nil end
  return m, m
end

function UI.Fmt(n)
  if not n then return "-" end
  return string.format("%d", n)
end
function UI.FmtPR(pr)
  if not pr then return "-" end
  return string.format("%.3f", pr)
end

-- ------------------------------------------------------------------ window

local function NavButton(nav, label)
  local b = CreateFrame("Button", nil, nav)
  b:SetHeight(24)
  b:SetPoint("LEFT", nav, "LEFT", 4, 0)
  b:SetPoint("RIGHT", nav, "RIGHT", -4, 0)
  b.bar = UI.Fill(b, C.accent, 1, "ARTWORK")
  b.bar:SetWidth(3)
  b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -3)
  b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 3)
  b.bar:Hide()
  b.bg = UI.Fill(b, C.head, 1, "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.bg:Hide()
  UI.Hover(b, 0.05)
  b.text = UI.Text(b, 12, C.dim)
  b.text:SetPoint("LEFT", b, "LEFT", 12, 0)
  b.text:SetText(label)
  b.badge = UI.Text(b, 10, C.gold)
  b.badge:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  return b
end

function UI.Build()
  if UI.frame then return end
  local db = UI.DB()
  local f = CreateFrame("Frame", "SepgpUIFrame", UIParent)
  f:SetWidth(WIDTH)
  f:SetHeight(HEIGHT)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:SetScale(db.scale or 1)
  UI.Flat(f, C.bg, db.alpha or 0.97, C.lineHi)
  f:Hide()
  table.insert(UISpecialFrames, "SepgpUIFrame")   -- Escape closes it
  UI.frame = f

  -- title row (drag to move)
  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -36, 0)
  bar:SetHeight(34)
  bar:EnableMouse(true)
  bar:SetScript("OnMouseDown", function() f:StartMoving() end)
  bar:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
  local icon = f:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\PetitionFrame\\GuildCharter-Icon")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -7)
  local title = UI.Text(f, 15)
  title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  title:SetText("|cff33b3ffshooty|repgp")
  local sub = UI.Text(f, 11, C.dim)
  sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
  UI.subtitle = sub
  local close = UI.Button(f, "X", 22, 22)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
  close:SetScript("OnClick", function() f:Hide() end)
  UI.Tip(close, "Close", "Escape closes it too.")
  local refresh = UI.Button(f, "Refresh", 70, 22)
  refresh:SetPoint("RIGHT", close, "LEFT", -6, 0)
  refresh:SetScript("OnClick", function()
    UI.RequestRoster(true)
    UI.rosterDirty = true
    UI.Refresh()
  end)
  UI.Tip(refresh, "Refresh", "Asks the server for the newest guild notes (where EP and GP are kept) and redraws everything.")
  if UI.Versions then UI.Versions.BuildCounter(f, refresh) end   -- officers: who runs which version

  UI.BuildSummary(f)

  local nav = CreateFrame("Frame", nil, f)
  nav:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -96)
  nav:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
  nav:SetWidth(NAV_W)
  UI.Flat(nav, C.panel, 1, C.line)
  UI.nav = nav
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", f, "TOPLEFT", NAV_W + 18, -96)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
  UI.Flat(content, C.panel, 1, C.line)
  UI.content = content

  for i = 1, table.getn(UI.order) do
    local p = UI.pages[UI.order[i]]
    p.nav = NavButton(nav, p.label)
    p.nav.key = p.key
    p.nav:SetScript("OnClick", function() UI.NavClick(this.key) end)
    UI.Tip(p.nav, p.label, p.tip)
    if p.parent then
      -- a topic folded inside another one: indented under it
      p.nav.text:ClearAllPoints()
      p.nav.text:SetPoint("LEFT", p.nav, "LEFT", 26, 0)
      UI.Font(p.nav.text, 11)
    end
  end
  -- topics with folded topics get an arrow
  for key, p in pairs(UI.pages) do
    local parent = p.parent and UI.pages[p.parent]
    if parent and parent.nav and not parent.nav.arrow then
      local a = parent.nav:CreateTexture(nil, "OVERLAY")
      a:SetTexture(UI.TRI)
      a:SetWidth(9)
      a:SetHeight(9)
      a:SetPoint("RIGHT", parent.nav, "RIGHT", -8, 0)
      a:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 1)
      parent.nav.arrow = a
      parent.nav.badge:SetPoint("RIGHT", parent.nav, "RIGHT", -22, 0)
    end
  end
  local ver = UI.Text(nav, 10, C.dim)
  ver:SetPoint("BOTTOM", nav, "BOTTOM", 0, 8)
  ver:SetText("window v" .. UI.VERSION)

  f:SetScript("OnShow", function()
    UI.RequestRoster()
    UI.rosterDirty = true
    UI.LayoutNav()
    if UI.Versions then UI.Versions.Ask() end
    UI.Refresh()
  end)
  f:SetScript("OnHide", function() UI.CloseMenus() end)
  -- a light ticker: redraw the open page when its data changed
  f.elapsed = 0
  f:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 1 then return end
    this.elapsed = 0
    UI.Tick()
  end)
end

-- Your EPGP, always on top.
function UI.BuildSummary(f)
  local s = CreateFrame("Frame", nil, f)
  s:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36)
  s:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -36)
  s:SetHeight(54)
  UI.Flat(s, C.panel, 1, C.line)
  UI.summary = s
  s.who = UI.Text(s, 14)
  s.who:SetPoint("TOPLEFT", s, "TOPLEFT", 12, -10)
  s.whoSub = UI.Text(s, 10, C.dim)
  s.whoSub:SetPoint("TOPLEFT", s.who, "BOTTOMLEFT", 0, -4)
  local function Stat(x, caption, tip)
    local v = UI.Text(s, 17)
    v:SetPoint("TOPLEFT", s, "TOPLEFT", x, -8)
    local c = UI.Text(s, 10, C.dim)
    c:SetPoint("TOPLEFT", v, "BOTTOMLEFT", 0, -3)
    c:SetText(caption)
    local hit = CreateFrame("Frame", nil, s)
    hit:SetPoint("TOPLEFT", v, "TOPLEFT", -4, 4)
    hit:SetWidth(84)
    hit:SetHeight(44)
    hit:EnableMouse(true)
    UI.Tip(hit, caption, tip)
    return v, c
  end
  s.ep = Stat(236, "EP (effort)", "Effort points: earned by raiding, being on standby and so on. Lowered by decay.")
  s.gp = Stat(318, "GP (gear)", "Gear points: added when you take loot. Everyone starts at the base GP. Lowered by decay.")
  s.pr = Stat(400, "PR (priority)", "Priority = EP / GP. The highest PR wins a loot bid.")
  s.pos = Stat(488, "Place", "Your place in the guild standings (the addon's order: members at or above the minimum EP first, then PR).")
  s.min = Stat(578, "Minimum EP", "Below the guild's minimum EP you go to the bottom of the standings and bids.")
  s.tier, s.tierCaption = Stat(676, "Guild settings", "Raid progress tier, decay per decay run and offspec price.")
end

function UI.RefreshSummary()
  local s = UI.summary
  if not s then return end
  local me, char = UI.Me()
  local myName = (sepgp and sepgp._playerName) or UnitName("player")
  local _, myClass = UnitClass("player")
  local hex = "ffffff"
  if myClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[myClass] then
    local c = RAID_CLASS_COLORS[myClass]
    hex = string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
  end
  s.who:SetText("|cff" .. hex .. myName .. "|r")
  local role = UI.IsGL() and "Guild leader" or (UI.IsAdmin() and "Officer (can edit EPGP)" or "Member")
  if not IsInGuild() then
    s.whoSub:SetText("Not in a guild - EPGP lives in guild notes")
  elseif me and char and me ~= char then
    s.whoSub:SetText(role .. "  -  alt of " .. UI.ClassName(me.name, me.class))
  elseif me then
    s.whoSub:SetText(role .. "  -  " .. (me.rank or ""))
  else
    s.whoSub:SetText(role .. "  -  waiting for guild data")
  end
  local minep = sepgp_minep or 0
  if me and me.hasEPGP then
    local below = minep > 0 and me.ep < minep
    s.ep:SetText(below and UI.Paint(C.red, UI.Fmt(me.ep)) or UI.Fmt(me.ep))
    s.gp:SetText(UI.Fmt(me.gp))
    s.pr:SetText(UI.Paint(C.gold, UI.FmtPR(me.pr)))
    local total = UI.ranked and table.getn(UI.ranked) or 0
    s.pos:SetText(me.pos and ("#" .. me.pos .. UI.Paint(C.dim, " / " .. total)) or "-")
    if minep <= 0 then
      s.min:SetText(UI.Paint(C.dim, "none"))
    elseif below then
      s.min:SetText(UI.Paint(C.red, (minep - me.ep) .. " to go"))
    else
      s.min:SetText(UI.Paint(C.on, "OK") .. UI.Paint(C.dim, "  (" .. minep .. ")"))
    end
  else
    s.ep:SetText("-")
    s.gp:SetText("-")
    s.pr:SetText("-")
    s.pos:SetText("-")
    s.min:SetText(minep > 0 and UI.Paint(C.dim, tostring(minep)) or UI.Paint(C.dim, "none"))
  end
  local decay = math.floor((1 - (sepgp_decay or 0.9)) * 100 + 0.5)
  local osPct = math.floor((UI.Prices and UI.Prices.Rate(sepgp_progress) or sepgp_discount or 0.25) * 100 + 0.5)
  -- tier as the big value, decay and offspec price in the caption (they did not fit beside it)
  s.tier:SetText(tostring(sepgp_progress or "T1"))
  s.tierCaption:SetText(decay .. "% decay  -  offspec " .. osPct .. "%")
  if UI.subtitle then
    local v = (GetAddOnMetadata and GetAddOnMetadata("shootyepgp", "Version")) or ""
    local _, _, num = string.find(v, "^([%d%.]+)")   -- "10.20.3 <ERROR>" -> "10.20.3"
    v = num or v
    local g = GetGuildInfo("player")
    UI.subtitle:SetText("v" .. v .. "  -  EPGP loot system" .. (g and ("  -  <" .. g .. ">") or ""))
  end
end

-- Show the topics this character may use; Officer only for officers.
-- folded topics (p.parent): shown under their parent while it is open
function UI.FoldOpen(key)
  local folds = UI.DB().folds
  return type(folds) == "table" and folds[key] and true or false
end
function UI.SetFold(key, open)
  local db = UI.DB()
  if type(db.folds) ~= "table" then db.folds = {} end
  db.folds[key] = open and true or nil
end

-- a topic with folded topics opens / closes them; any other topic is selected
function UI.NavClick(key)
  local p = UI.pages[key]
  if not p or (p.admin and not UI.IsAdmin()) then return end
  if p.nav and p.nav.arrow then
    local open = not UI.FoldOpen(key)
    UI.SetFold(key, open)
    local cur = UI.pages[UI.current or ""]
    if open or (cur and cur.parent == key) then
      UI.LayoutNav()
      UI.Select(key)
      return
    end
    UI.LayoutNav()
    return
  end
  UI.Select(key)
end

function UI.LayoutNav()
  local y = -6
  local admin = UI.IsAdmin()
  for i = 1, table.getn(UI.order) do
    local p = UI.pages[UI.order[i]]
    if p.nav.arrow then
      p.nav.arrow:SetTexCoord(0, 1, UI.FoldOpen(p.key) and 0 or 1, UI.FoldOpen(p.key) and 1 or 0)
    end
    if (p.admin and not admin) or (p.parent and not UI.FoldOpen(p.parent)) then
      p.nav:Hide()
    else
      if p.gap then y = y - 10 end
      p.nav:ClearAllPoints()
      p.nav:SetPoint("TOPLEFT", UI.nav, "TOPLEFT", 4, y)
      p.nav:SetPoint("TOPRIGHT", UI.nav, "TOPRIGHT", -4, y)
      p.nav:Show()
      y = y - 25
    end
  end
  local cur = UI.pages[UI.current or ""]
  if not cur or (cur.admin and not admin) then
    local want = UI.DB().page
    local p = UI.pages[want or ""]
    if not p or (p.admin and not admin) then want = "home" end
    UI.Select(want, true)
  end
end

function UI.Select(key, quiet)
  local p = UI.pages[key]
  if not p then return end
  if p.admin and not UI.IsAdmin() then
    if not quiet then UI.Print("that topic is for officers only") end
    if UI.current then return end
    key, p = "home", UI.pages.home
  end
  UI.CloseMenus()
  for k, q in pairs(UI.pages) do
    if q.frame then q.frame:Hide() end
    if q.nav then
      q.nav.bar:Hide()
      q.nav.bg:Hide()
      q.nav.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    end
  end
  if not p.frame then
    local pf = CreateFrame("Frame", nil, UI.content)
    pf:SetPoint("TOPLEFT", UI.content, "TOPLEFT", 8, -8)
    pf:SetPoint("BOTTOMRIGHT", UI.content, "BOTTOMRIGHT", -8, 8)
    p.frame = pf
    local ok, err = pcall(p.build, pf)
    if not ok then UI.Print("could not draw page " .. key .. ": " .. tostring(err)) end
  end
  p.frame:Show()
  p.nav.bar:Show()
  p.nav.bg:Show()
  p.nav.text:SetTextColor(1, 1, 1)
  UI.current = key
  UI.DB().page = key
  if p.parent and not UI.FoldOpen(p.parent) then
    -- opened from elsewhere (/epgp accounts, last page): unfold its parent
    UI.SetFold(p.parent, true)
    UI.LayoutNav()
    p.nav.bar:Show()
  end
  UI.RefreshPage()
end

function UI.RefreshPage()
  local p = UI.pages[UI.current or ""]
  if p and p.frame and p.refresh then
    local ok, err = pcall(p.refresh, p.frame)
    if not ok then UI.Print("page " .. p.key .. ": " .. tostring(err)) end
  end
end

function UI.RefreshBadges()
  for k, p in pairs(UI.pages) do
    if p.nav then
      local n = p.badge and p.badge()
      p.nav.badge:SetText(n and n > 0 and tostring(n) or "")
    end
  end
end

function UI.Refresh()
  if not UI.frame or not UI.frame:IsShown() then return end
  UI.Roster(UI.rosterDirty)
  UI.RefreshSummary()
  UI.RefreshBadges()
  if UI.Versions then UI.Versions.Refresh() end
  UI.RefreshPage()
end

-- What the live pages watch: a cheap fingerprint of the data they show.
function UI.Signature()
  local bids = (sepgp and sepgp.bids_main and table.getn(sepgp.bids_main) or 0) * 1000
             + (sepgp and sepgp.bids_off and table.getn(sepgp.bids_off) or 0)
             + (sepgp and sepgp.bids_xmog and table.getn(sepgp.bids_xmog) or 0) * 100000
  local item = sepgp and sepgp.bid_item and sepgp.bid_item.link or ""
  local res = sepgp and sepgp.reserves and table.getn(sepgp.reserves) or 0
  local loot = type(sepgp_looted) == "table" and table.getn(sepgp_looted) or 0
  local log = type(sepgp_log) == "table" and table.getn(sepgp_log) or 0
  local cd = sepgp and sepgp.timer and sepgp.timer.cd_text or ""
  local bidcd = sepgp_bids and sepgp_bids._counterText or ""
  local hist = (UI.History and UI.History.version or 0) .. "/" .. (UI.AddonCheck and UI.AddonCheck.version or 0)
    .. "/" .. (UI.Accounts and UI.Accounts.version or 0) .. "/" .. (UI.Versions and UI.Versions.version or 0)
    .. "/" .. (UI.Decay and UI.Decay.version or 0) .. ((UI.Decay and UI.Decay.check) and "c" or "")
    .. "/" .. (UI.Prices and UI.Prices.version or 0)
  return bids .. ":" .. item .. ":" .. res .. ":" .. loot .. ":" .. log .. ":" .. cd .. ":" .. bidcd .. ":" .. hist
end

function UI.Tick()
  local sig = UI.Signature()
  if UI.rosterDirty or sig ~= UI.lastSig then
    UI.lastSig = sig
    UI.Refresh()
  end
end

function UI.Toggle(page)
  UI.Build()
  if UI.frame:IsShown() and (not page or page == UI.current) then
    UI.frame:Hide()
  else
    UI.frame:Show()
    if page then UI.Select(page) end
  end
end

function UI.Open(page)
  UI.Build()
  UI.frame:Show()
  if page then UI.Select(page) end
end

-- Pages register themselves: UI.Page{ key, label, tip, build, refresh, admin, badge, gap, parent }
-- (parent = "key": folded under that topic, shown while it is open)
function UI.Page(p)
  UI.pages[p.key] = p
  -- p.after = "key": listed right after that topic
  if p.after then
    for i = 1, table.getn(UI.order) do
      if UI.order[i] == p.after then
        table.insert(UI.order, i + 1, p.key)
        return
      end
    end
  end
  table.insert(UI.order, p.key)
end

-- Show one member's history (Standings, history view).
function UI.OpenHistory(name)
  if not name then return end
  UI.Open("standings")
  local st = UI.pages.standings.frame
  if not st then return end
  st.sel = name
  st.list.selected = name
  UI.pages.standings.detail(st)
  UI.pages.standings.showHistory(st, true)
end

-- ------------------------------------------------------------------ events

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 == "shootyepgp" then
      UI.DB()
      if UI.Minimap then UI.Minimap.Build() end
    end
  elseif event == "PLAYER_ENTERING_WORLD" then
    if UI.Minimap then UI.Minimap.Later() end
  else
    UI.rosterDirty = true
  end
end)

SLASH_SEPGPUI1 = "/epgp"
SlashCmdList["SEPGPUI"] = function(msg)
  msg = string.lower(msg or "")
  if msg == "" then UI.Toggle() return end
  if UI.pages[msg] then UI.Open(msg) return end
  UI.Print("/epgp opens the window. /epgp <topic>: home, standings, bids, loot, prices, reserves, alts, logs, strikes, tools, settings, officer, decay, addons, accounts")
end
