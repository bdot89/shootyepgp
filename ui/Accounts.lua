-- shootyepgp :: new window, part 8 - Accounts (officers)
-- The guild asked (19 Oct 2026) that officers can see every member's other
-- characters on the same WoW account, Alliance and Horde.
--
-- Every copy of this file remembers the characters logged in on this PC's
-- account (saved variable sepgp_accounts, account-wide: name, realm, faction,
-- class, level, guild). A character only shows once it has been logged in
-- with this version. The list is sent on the guild's hidden addon channel
-- (whispers do not work on this client, see profsync.lua); only officers'
-- copies keep it and only officers see the page.
--
-- Wire, prefix SEPGPAC on GUILD:
--   AQ                          an officer asks online members to send their list
--   AR;<id>;ch~ch~...           a member's list, ch = "name,realm,A|H,CLASS,level,guild"
--                               (a long list comes in several messages, same id)
-- Each member sends once a while after logging in, and answers AQ at most
-- once a minute, after a random 1-8 s wait so the guild does not send at once.

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local AC = { queue = {}, version = 0 }
UI.Accounts = AC

local PREFIX = "SEPGPAC"
local MAX_MSG = 230
local GAP = 0.5
local ANSWER_EVERY = 60
local LOGIN_DELAY = 20

local FACTION = { A = { "Alliance", { 0.30, 0.55, 1.00 } }, H = { "Horde", { 1.00, 0.25, 0.25 } } }

-- ------------------------------------------------------------------ store

function AC.DB()
  if type(sepgp_accounts) ~= "table" then sepgp_accounts = {} end
  local db = sepgp_accounts
  if type(db.chars) ~= "table" then db.chars = {} end
  if type(db.reports) ~= "table" then db.reports = {} end
  return db
end

local function Clean(s, len)
  s = string.gsub(tostring(s or ""), "[,~;|]", " ")
  return string.sub(s, 1, len or 24)
end

local function Realm()
  return Clean(GetRealmName and GetRealmName() or "", 30)
end

local function GuildKey()
  local g = GetGuildInfo and GetGuildInfo("player")
  return g and g ~= "" and g or nil
end

-- the character logged in now -> sepgp_accounts.chars
function AC.Record()
  local name = UnitName("player")
  if not name or name == UNKNOWNOBJECT or name == "" then return end
  local db = AC.DB()
  local realm = Realm()
  local key = name .. "-" .. realm
  local c = db.chars[key] or {}
  local _, class = UnitClass("player")
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  c.n, c.r = name, realm
  c.f = (faction == "Horde" and "H") or (faction == "Alliance" and "A") or c.f or "?"
  c.c = class or c.c or ""
  c.l = UnitLevel("player") or c.l or 0
  local g = GuildKey()
  if g then c.g = g elseif not IsInGuild() then c.g = "" end
  c.t = time()
  db.chars[key] = c
  return c
end

-- this account's characters as wire parts
function AC.MyParts()
  local parts = {}
  for _, c in pairs(AC.DB().chars) do
    table.insert(parts, Clean(c.n, 12) .. "," .. Clean(c.r, 30) .. "," .. Clean(c.f, 1) .. ","
      .. Clean(c.c, 12) .. "," .. tostring(tonumber(c.l) or 0) .. "," .. Clean(c.g, 24))
  end
  table.sort(parts)
  return parts
end

function AC.ParsePart(p)
  local f = UI.History.Split(p, ",")
  if not f[1] or f[1] == "" then return nil end
  return { n = f[1], r = f[2] or "", f = f[3] or "?", c = f[4] or "", l = tonumber(f[5]) or 0, g = f[6] or "" }
end

-- ------------------------------------------------------------------ sending

local function SendNow(msg)
  local ctl = ChatThrottleLib
  if ctl and ctl.SendAddonMessage then
    local ok = pcall(ctl.SendAddonMessage, ctl, "BULK", PREFIX, msg, "GUILD")
    if ok then return end
  end
  pcall(SendAddonMessage, PREFIX, msg, "GUILD")
end

-- our list, to the guild (and straight into our own store if we are an officer)
function AC.Report()
  if not IsInGuild() then return end
  AC.Record()
  local parts = AC.MyParts()
  if table.getn(parts) == 0 then return end
  local id = tostring(math.mod(time(), 100000)) .. tostring(math.random(10, 99))
  local msgs = UI.History.Pack("AR;" .. id .. ";", parts, "~")
  for i = 1, table.getn(msgs) do table.insert(AC.queue, msgs[i]) end
  AC.lastReport = GetTime()
  local me = UnitName("player")
  for i = 1, table.getn(msgs) do AC.OnReport(msgs[i], me) end
end

-- officers: ask every online member for their list
function AC.Ask()
  if not UI.IsAdmin() then return end
  table.insert(AC.queue, "AQ")
  AC.askedAt = time()
  AC.Report()
end

-- ------------------------------------------------------------------ receiving

function AC.OnReport(msg, sender)
  if not sender or not UI.IsAdmin() then return end   -- only officers keep lists
  local g = GuildKey()
  if not g then return end
  local _, byName = UI.Roster()
  if byName and next(byName) and not byName[sender] then return end   -- guild members only
  local _, _, id, body = string.find(msg or "", "^AR;(%w+);(.*)$")
  if not id then return end
  local db = AC.DB()
  db.reports[g] = db.reports[g] or {}
  local r = db.reports[g][sender]
  if not r or r.id ~= id then
    r = { id = id, list = {} }
    db.reports[g][sender] = r
  end
  r.t = time()
  for p in string.gfind(body, "([^~]+)") do
    local c = AC.ParsePart(p)
    if c then
      local dupe
      for i = 1, table.getn(r.list) do
        if r.list[i].n == c.n and r.list[i].r == c.r then r.list[i] = c dupe = true end
      end
      if not dupe then table.insert(r.list, c) end
    end
  end
  AC.version = AC.version + 1
end

function AC.OnMessage(msg, sender)
  if msg == "AQ" then
    if sender == UnitName("player") then return end
    if AC.lastReport and GetTime() - AC.lastReport < ANSWER_EVERY then return end
    if not AC.answerAt then AC.answerAt = GetTime() + 1 + math.random() * 7 end
  elseif string.find(msg or "", "^AR;") then
    if sender ~= UnitName("player") then AC.OnReport(msg, sender) end
  end
end

-- this guild's reports; a member with no report of their own is found in the
-- report of another character on the same account
function AC.Reports()
  local g = GuildKey()
  local reports = g and AC.DB().reports[g] or {}
  local owner = {}
  local realm = Realm()
  for who, r in pairs(reports) do
    for i = 1, table.getn(r.list) do
      local c = r.list[i]
      if c.g == g and (c.r == "" or c.r == realm) then owner[c.n] = who end
    end
  end
  return reports, owner
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    if arg1 == PREFIX and arg3 == "GUILD" then pcall(AC.OnMessage, arg2, arg4) end
    return
  end
  pcall(AC.Record)
  if event == "PLAYER_LEVEL_UP" and arg1 then
    local c = AC.DB().chars[UnitName("player") .. "-" .. Realm()]
    if c then c.l = tonumber(arg1) or c.l end
  end
  if event == "PLAYER_ENTERING_WORLD" and not AC.loginAt and not AC.lastReport then
    AC.loginAt = GetTime() + LOGIN_DELAY
  end
end)
f.wait = 0
f:SetScript("OnUpdate", function()
  local now = GetTime()
  if AC.loginAt and now >= AC.loginAt then
    if GuildKey() then
      AC.loginAt = nil
      pcall(AC.Report)
    elseif not IsInGuild() then
      AC.loginAt = nil
    else
      AC.loginAt = now + 10   -- guild name not known yet
    end
  end
  if AC.answerAt and now >= AC.answerAt then
    AC.answerAt = nil
    pcall(AC.Report)
  end
  if table.getn(AC.queue) > 0 and now >= f.wait then
    SendNow(table.remove(AC.queue, 1))
    f.wait = now + GAP
  end
end)

-- ------------------------------------------------------------------ page

local function FactionTag(fa)
  local x = FACTION[fa]
  if not x then return UI.Paint(C.dim, "?") end
  return UI.Paint(x[2], fa)
end

local function CharText(c)
  return FactionTag(c.f) .. " " .. UI.ClassName(c.n, c.c) .. UI.Paint(C.dim, " " .. (c.l or 0))
end

local function Ago(t)
  if not t then return "" end
  local d = time() - t
  if d < 3600 then return math.max(0, math.floor(d / 60)) .. " min" end
  if d < 86400 then return math.floor(d / 3600) .. " h" end
  return math.floor(d / 86400) .. " d"
end

UI.Page{ key = "accounts", label = "Accounts", after = "addons", parent = "officer", admin = true,
  tip = "Every member's other characters on the same account, Alliance and Horde. Officers only.",
  build = function(f)
    f.search = UI.EditBox(f, 200)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Hint(f.search, "Search any character or guild...")
    f.search.onChange = function() f.list:Filter() end
    f.only = UI.Switch(f)
    f.only:SetPoint("LEFT", f.search, "RIGHT", 14, 0)
    f.only.onToggle = function(v) f.onlyOthers = v UI.RefreshPage() end
    local ol = UI.Text(f, 12)
    ol:SetPoint("LEFT", f.only, "RIGHT", 8, 0)
    ol:SetText("Only with other characters")
    UI.Tip(f.only, "Only with other characters", "Hide members whose list has no character besides themselves, and members with no list yet.")
    local ask = UI.Button(f, "Ask online members", 140, 22)
    ask:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ask:SetScript("OnClick", function()
      AC.Ask()
      UI.RefreshPage()
    end)
    UI.Tip(ask, "Ask online members", "Asks every online member's shootyepgp for its list of characters, on the hidden addon channel. Answers arrive over the next few seconds. Members also send their list by themselves when they log in.")
    f.status = UI.Text(f, 11, C.dim)
    f.status:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
    f.status:SetWidth(PW)
    f.status:SetJustifyH("LEFT")

    local cols = {
      { key = "name", label = "Member", width = 110, sort = "asc" },
      { key = "rank", label = "Rank", width = 84, sort = "asc" },
      { key = "n", label = "Chars", width = 36, align = "RIGHT", sort = true },
      { key = "t", label = "Sent", width = 48, align = "RIGHT", sort = true },
      { key = "others", label = "Other characters on the account (A = Alliance, H = Horde)", width = 340 },
    }
    local nRows = math.floor((PH - 50 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -50)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "name", false
    l.emptyText = "Nobody to show. Press \"Ask online members\" - members with this shootyepgp answer in a few seconds."
    l.filter = function(r)
      if f.onlyOthers and r.others == 0 then return false end
      local q = f.search:GetText()
      if not q or q == "" then return true end
      return string.find(r.search, string.lower(q), 1, true) ~= nil
    end
    l.onEnter = function(r, line)
      GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
      GameTooltip:AddLine(r.id)
      if not r.report then
        GameTooltip:AddLine("No list yet: not logged in since updating shootyepgp, or an older version.", 1, 1, 1, 1)
      else
        if r.via then GameTooltip:AddLine("Sent from " .. r.via .. " (same account)", 0.6, 0.6, 0.6) end
        local realm = Realm()
        for i = 1, table.getn(r.report.list) do
          local c = r.report.list[i]
          local fx = FACTION[c.f]
          local col = fx and fx[2] or { 0.6, 0.6, 0.6 }
          local where = (c.g ~= "" and ("<" .. c.g .. ">") or "no guild")
          if c.r ~= "" and c.r ~= realm then where = where .. "  " .. c.r end
          GameTooltip:AddDoubleLine(UI.ClassName(c.n, c.c) .. "  " .. (c.l or 0),
            (fx and fx[1] or "?") .. "  " .. where, 1, 1, 1, col[1], col[2], col[3])
        end
        GameTooltip:AddLine("Sent " .. date("%d %b %H:%M", r.report.t or 0), 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end
    l.onClick = function(r) if UI.byName and UI.byName[r.id] then UI.OpenHistory(r.id) end end
    f.list = l
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
  end,
  refresh = function(f)
    f.only.Set(f.onlyOthers and true or false)
    local reports, owner = AC.Reports()
    local realm = Realm()
    local rows, have, withOthers = {}, 0, 0
    local list = UI.roster or {}
    for i = 1, table.getn(list) do
      local m = list[i]
      local via = reports[m.name] and m.name or owner[m.name]
      local rep = via and reports[via]
      local cells, search, others, n = {}, string.lower(m.name), 0, 0
      if rep then
        have = have + 1
        local fs = {}
        for j = 1, table.getn(rep.list) do
          local c = rep.list[j]
          search = search .. " " .. string.lower(c.n .. " " .. (c.g or ""))
          if not (c.n == m.name and (c.r == "" or c.r == realm)) then
            others = others + 1
            table.insert(fs, CharText(c))
          end
        end
        n = table.getn(rep.list)
        if others > 0 then withOthers = withOthers + 1 end
        cells = { UI.ClassName(m.name, m.class), m.rank, n, Ago(rep.t),
                  others > 0 and table.concat(fs, ", ") or UI.Paint(C.dim, "none") }
      else
        cells = { UI.ClassName(m.name, m.class), m.rank, "", "", UI.Paint(C.dim, "no list yet") }
      end
      table.insert(rows, { id = m.name, report = rep, via = (via ~= m.name) and via or nil,
        others = others, search = search, cells = cells,
        sort = { name = m.name, rank = m.rankIndex * 1000 + (rep and 0 or 1), n = rep and n or -1, t = rep and rep.t or 0, tie = m.name } })
    end
    f.list:SetRows(rows, true)
    local asked = AC.askedAt and ("  -  asked online members at " .. date("%H:%M:%S", AC.askedAt)) or ""
    f.status:SetText(have .. " of " .. table.getn(list) .. " members have a list" .. asked
      .. ". A character shows once it has been logged in with this shootyepgp.")
    f.count:SetText(withOthers .. " members with other characters  -  hover a row for details, faction, guild and realm")
  end,
}
