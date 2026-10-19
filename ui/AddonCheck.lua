-- shootyepgp :: new window, part 7 - Addon check (officers)
-- From a responder the guild leader's friend sent (18 Oct 2026,
-- Downloads\shootyepgp-addoncheck.lua). Same protocol, so it works with the
-- friend's tool too. Addon message prefix "ADDONCHECK":
--   query:  "Q1:<id>:<Addon1>,<Addon2>,..."   (folder names, to RAID / PARTY / GUILD)
--   answer: "A1:<id>:<Addon1>=L/<version>;<Addon2>=D;<Addon3>=M"   (same channel)
--   L = loaded (version from its .toc, "?" if none), D = installed but not loaded,
--   M = not installed. A long answer comes in several messages with the same head.
-- Added here: the responder only answers guild / group members, at most once
-- per asker every 10 s and 8 answers per 30 s in all (the friend's version
-- answered every new id, so one person could make the whole guild send);
-- and the asking side, an officer page that lists everyone's answer.
-- 19 Oct 2026: one column per addon; members whose copy is too old to answer
-- are filled in from what their addons were heard sending (see "heard") and
-- the version check in Versions.lua.

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local A = { answers = {} }
UI.AddonCheck = A

local PREFIX = "ADDONCHECK"
local MAXLEN = 240
local MAXNAMES = 16
local DEFAULT_LIST = "shootyepgp,BigWigs,pfUI"

-- ------------------------------------------------------------------ answering

local lastId, lastAt, recent = {}, {}, {}

local function Clean(s)
  s = tostring(s or "?")
  s = string.gsub(s, "[:;=,/|]", " ")
  return string.sub(s, 1, 24)
end

function A.State(name)
  if IsAddOnLoaded(name) then
    return "L/" .. Clean(GetAddOnMetadata(name, "Version"))
  end
  local ok, _, title, _, _, _, reason = pcall(GetAddOnInfo, name)
  if not ok or not title or reason == "MISSING" then return "M" end
  return "D"
end

-- someone we may answer: in our guild, raid or party
local function Known(sender)
  if not sender then return false end
  local _, byName = UI.Roster()
  if byName and byName[sender] then return true end
  for i = 1, GetNumRaidMembers() do
    if GetRaidRosterInfo(i) == sender then return true end
  end
  for i = 1, GetNumPartyMembers() do
    if UnitName("party" .. i) == sender then return true end
  end
  return sender == UnitName("player")
end

local function Allowed(sender)
  local now = GetTime()
  if lastAt[sender] and now - lastAt[sender] < 10 then return false end
  local n = 0
  for i = table.getn(recent), 1, -1 do
    if now - recent[i] > 30 then table.remove(recent, i) else n = n + 1 end
  end
  if n >= 8 then return false end
  lastAt[sender] = now
  table.insert(recent, now)
  return true
end

function A.Answer(msg, channel, sender)
  if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "GUILD" and channel ~= "BATTLEGROUND" then return end
  local _, _, id, list = string.find(msg or "", "^Q1:(%w+):(.+)$")
  if not id or lastId[sender or ""] == id then return end   -- not a query, or answered already
  if not Known(sender) or not Allowed(sender) then return end
  lastId[sender or ""] = id
  local head = "A1:" .. id .. ":"
  local out, n = head, 0
  for name in string.gfind(list, "([%w_%-%.]+)") do
    n = n + 1
    if n > MAXNAMES then break end
    local part = name .. "=" .. A.State(name)
    if out ~= head and string.len(out) + 1 + string.len(part) > MAXLEN then
      pcall(SendAddonMessage, PREFIX, out, channel)
      out = head
    end
    if out ~= head then out = out .. ";" end
    out = out .. part
  end
  if out ~= head then pcall(SendAddonMessage, PREFIX, out, channel) end
end

-- ------------------------------------------------------------------ asking

function A.Names(text)
  local names = {}
  for name in string.gfind(text or "", "([%w_%-%.]+)") do
    if table.getn(names) < MAXNAMES then table.insert(names, name) end
  end
  return names
end

-- channel: "RAID", "PARTY" or "GUILD"
function A.Ask(text, channel)
  local names = A.Names(text)
  if table.getn(names) == 0 then return nil, "type at least one addon folder name" end
  local id = tostring(math.mod(time(), 100000)) .. tostring(math.random(10, 99))
  local msg = "Q1:" .. id .. ":" .. table.concat(names, ",")
  while string.len(msg) > MAXLEN and table.getn(names) > 1 do
    table.remove(names)
    msg = "Q1:" .. id .. ":" .. table.concat(names, ",")
  end
  A.id, A.names, A.channel, A.at = id, names, channel, time()
  A.answers = {}
  A.version = (A.version or 0) + 1
  -- our own answer straight away (the server may not echo our message to us)
  local mine = {}
  for i = 1, table.getn(names) do mine[names[i]] = A.State(names[i]) end
  A.answers[UnitName("player")] = mine
  pcall(SendAddonMessage, PREFIX, msg, channel)
  return names
end

function A.OnAnswer(msg, sender)
  if not A.id or not sender then return end
  local _, _, id, body = string.find(msg or "", "^A1:(%w+):(.+)$")
  if id ~= A.id then return end
  local got = A.answers[sender] or {}
  for part in string.gfind(body, "([^;]+)") do
    local _, _, name, state = string.find(part, "^([^=]+)=(.+)$")
    if name then got[name] = state end
  end
  A.answers[sender] = got
  A.version = (A.version or 0) + 1
end

-- who should answer: the raid / party, or online guild members
function A.Expected(channel)
  local out = {}
  if channel == "RAID" then
    for i = 1, GetNumRaidMembers() do
      local n = GetRaidRosterInfo(i)
      if n then out[n] = true end
    end
  elseif channel == "PARTY" then
    out[UnitName("player")] = true
    for i = 1, GetNumPartyMembers() do
      local n = UnitName("party" .. i)
      if n then out[n] = true end
    end
  else
    local roster = UI.Roster()
    for i = 1, table.getn(roster) do
      if roster[i].online then out[roster[i].name] = true end
    end
  end
  return out
end

-- ------------------------------------------------------------------ heard
-- Members whose shootyepgp is too old to answer still show many addons:
-- addons send their own hidden messages (pfUI its version at login, BigWigs
-- its raid syncs and version replies, shootyepgp its login line). Every
-- prefix heard from a member is kept with the time (sepgp_ui.heard,
-- account-wide, guild members only, at most 24 per member, dropped after
-- 30 days). A prefix counts for an addon when it has the addon's folder name
-- or is listed here.

local PREFIX_ADDON = {
  ["SEPGP_PREFIX"] = "shootyepgp", SWOW_R = "shootyepgp", SEPGPH = "shootyepgp", SEPGPAC = "shootyepgp",
  SEPGPV = "shootyepgp", EGPROF = "shootyepgp", ADDONCHECK = "shootyepgp",
  BigWigs = "BigWigs", pfUI = "pfUI", TWT_UDTSv4 = "TWThreat", ["[Spy]"] = "Spy", OBG = "OctoBG",
}
local HEARD_KEEP = 30 * 86400

function A.Heard()
  local db = UI.DB()
  if type(db.heard) ~= "table" then db.heard = {} end
  return db.heard
end

function A.Hear(prefix, msg, sender)
  if not prefix or not sender or sender == "" then return end
  if not (UI.byName and UI.byName[sender]) then return end   -- guild members only (not battleground strangers)
  local heard = A.Heard()
  local h = heard[sender]
  if not h then h = {} heard[sender] = h end
  local e = h[prefix]
  if not e then
    local n = 0
    for _ in pairs(h) do n = n + 1 end
    if n >= 24 then return end
    e = {}
    h[prefix] = e
  end
  e.t = time()
  local v
  if prefix == "pfUI" then
    local _, _, num = string.find(msg or "", "^VERSION:(%d+)")
    num = tonumber(num)
    if num then v = math.floor(num / 10000) .. "." .. math.mod(math.floor(num / 100), 100) .. "." .. math.mod(num, 100) end
  elseif prefix == "BigWigs" then
    local _, _, rev = string.find(msg or "", "BWVR (%-?%d+)")
    if rev and rev ~= "-1" then v = "r" .. rev end
  elseif prefix == "SEPGP_PREFIX" then
    local _, _, ver = string.find(msg or "", "^VERSION;([^;]+)")
    if ver then v = ver end
  end
  if v then e.v = v end
end

-- what was heard from a member for one addon: newest time, a version if known
function A.HeardFor(sender, addon)
  local h = A.Heard()[sender]
  if not h then return nil end
  local low = string.lower(addon)
  local t, v
  for prefix, e in pairs(h) do
    local owner = PREFIX_ADDON[prefix]
    if (owner and string.lower(owner) == low) or string.lower(prefix) == low then
      if not t or (e.t or 0) > t then t = e.t or 0 end
      v = v or e.v
    end
  end
  return t, v
end

function A.Prune()
  local heard, cut = A.Heard(), time() - HEARD_KEEP
  for who, h in pairs(heard) do
    local any
    for prefix, e in pairs(h) do
      if (e.t or 0) < cut then h[prefix] = nil else any = true end
    end
    if not any then heard[who] = nil end
  end
end

-- BigWigs's own version check (raid only): every BigWigs answers, with or
-- without shootyepgp
function A.AskBigWigs()
  if GetNumRaidMembers() == 0 then return end
  pcall(SendAddonMessage, "BigWigs", "BWVQ " .. (GetRealZoneText and GetRealZoneText() or ""), "RAID")
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" then
    if arg1 == "shootyepgp" then pcall(A.Prune) end
    return
  end
  if arg4 and arg4 ~= UnitName("player") then pcall(A.Hear, arg1, arg2, arg4) end
  if arg1 ~= PREFIX then return end
  if string.find(arg2 or "", "^Q1:") then
    pcall(A.Answer, arg2, arg3, arg4)
  elseif string.find(arg2 or "", "^A1:") then
    pcall(A.OnAnswer, arg2, arg4)
  end
end)

-- ------------------------------------------------------------------ page

local MAX_COLS = 4   -- addons with a column of their own; the rest are in the tooltip

local function Ago(t)
  local d = time() - (t or 0)
  if d < 3600 then return math.max(1, math.floor(d / 60)) .. "m" end
  if d < 86400 then return math.floor(d / 3600) .. "h" end
  return math.floor(d / 86400) .. "d"
end

-- one member, one addon -> cell text, ok (true / false / nil = unknown), tooltip line
function A.Cell(name, addon, answer, sepgpStatus, sepgpVer)
  local s = answer and answer[addon]
  if s then
    if string.sub(s, 1, 1) == "L" then
      local v = string.sub(s, 3)
      return UI.Paint(C.on, (v ~= "" and v ~= "?") and v or "yes"), true, addon .. ": loaded" .. ((v ~= "" and v ~= "?") and (", version " .. v) or "")
    elseif s == "D" then
      return UI.Paint(C.gold, "off"), false, addon .. ": installed but switched off"
    end
    return UI.Paint(C.red, "missing"), false, addon .. ": not installed"
  end
  if string.lower(addon) == "shootyepgp" and sepgpStatus then
    if sepgpStatus == "current" or sepgpStatus == "newer" then
      return UI.Paint(C.on, sepgpVer or "yes"), true, "shootyepgp: up to date" .. (sepgpVer and (", version " .. sepgpVer) or "")
    elseif sepgpStatus == "old" then
      return UI.Paint(C.gold, "old " .. (sepgpVer or "")), false, "shootyepgp: an older version" .. (sepgpVer and (" (" .. sepgpVer .. ")") or "") .. " - needs to update"
    elseif sepgpStatus == "none" then
      return UI.Paint(C.red, "none"), false, "shootyepgp: no copy answering (not installed, switched off, or from before March 2026)"
    end
  end
  local t, v = A.HeardFor(name, addon)
  if t then
    return UI.Paint(C.on, v or "seen") .. UI.Paint(C.dim, " " .. Ago(t)), true,
      addon .. ": seen in use " .. Ago(t) .. " ago" .. (v and (", version " .. v) or "") .. " (its own hidden messages)"
  end
  return UI.Paint(C.dim, "?"), nil, addon .. ": unknown - their shootyepgp is too old to say, and the addon was not heard"
end

local CHANNELS = { { key = "RAID", label = "My raid" }, { key = "PARTY", label = "My party" }, { key = "GUILD", label = "Online guild" } }

UI.Page{ key = "addons", label = "Addon check", after = "officer", parent = "officer", admin = true,
  tip = "Ask your raid or the guild which addons they have loaded. Officers only.",
  build = function(f)
    local top = UI.Card(f, "Check addons", PW, 92)
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Label(top, "Addons", 12, -36)
    f.names = UI.EditBox(top, 330)
    f.names:SetPoint("TOPLEFT", top, "TOPLEFT", 70, -33)
    f.names:SetMaxLetters(220)
    UI.Tip(f.names, "Addons to check", "Addon FOLDER names (as in Interface\\AddOns), separated by commas. Up to " .. MAXNAMES .. ". The first " .. MAX_COLS .. " besides shootyepgp get a column, the rest show on hover.")
    f.names.onChange = function(text) UI.DB().addonList = text UI.RefreshPage() end
    f.chan = UI.Dropdown(top, 120, CHANNELS, function() return f.channel end, function(k) f.channel = k UI.RefreshPage() end)
    f.chan:SetPoint("LEFT", f.names, "RIGHT", 8, 0)
    UI.Tip(f.chan, "Who to ask", "Your raid, your party, or every online guild member.")
    local ask = UI.Button(top, "Check", 90, 22)
    ask:SetPoint("LEFT", f.chan, "RIGHT", 8, 0)
    ask:SetScript("OnClick", function()
      local ch = f.channel
      if ch == "RAID" and GetNumRaidMembers() == 0 then
        UI.Confirm("You are not in a raid. Pick \"My party\" or \"Online guild\" instead.", nil, "Not in a raid", "OK")
        return
      end
      if ch == "PARTY" and GetNumPartyMembers() == 0 then
        UI.Confirm("You are not in a party. Pick \"Online guild\" instead.", nil, "Not in a party", "OK")
        return
      end
      local names = A.Ask(f.names:GetText(), ch)
      if not names then
        UI.Confirm("Type at least one addon folder name, e.g. " .. DEFAULT_LIST .. ".", nil, "No addons to check", "OK")
        return
      end
      if UI.Versions then UI.Versions.Ask(true) end
      for i = 1, table.getn(names) do
        if string.lower(names[i]) == "bigwigs" and ch == "RAID" then A.AskBigWigs() end
      end
      UI.RefreshPage()
    end)
    UI.Tip(ask, "Check", "Asks on the hidden addon channel (nothing shows in chat). Members with shootyepgp 10.20.5 from 18 Oct or newer answer for every addon. For older copies the page shows what their addons were heard sending; in a raid, BigWigs is also asked with its own version check.")
    f.status = UI.Text(top, 11, C.dim)
    f.status:SetPoint("TOPLEFT", top, "TOPLEFT", 12, -66)
    f.status:SetWidth(PW - 24)
    f.status:SetJustifyH("LEFT")
    f.problems = UI.Switch(f)
    f.problems:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -100)
    f.problems.onToggle = function(v) f.onlyProblems = v UI.RefreshPage() end
    local pl = UI.Text(f, 12)
    pl:SetPoint("LEFT", f.problems, "RIGHT", 8, 0)
    pl:SetText("Only show problems")
    UI.Tip(f.problems, "Only problems", "Hide members who have everything confirmed loaded.")
    local key = UI.Text(f, 10, C.dim)
    key:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -104)
    key:SetText(UI.Paint(C.on, "green") .. " loaded   " .. UI.Paint(C.gold, "gold") .. " off / old   " .. UI.Paint(C.red, "red") .. " missing   ? unknown")

    local cols = {
      { key = "name", label = "Name", width = 100, sort = "asc" },
      { key = "miss", label = "Issues", width = 44, align = "RIGHT", sort = true },
      { key = "sepgp", label = "shootyepgp", width = 92, sort = true },
    }
    for i = 1, MAX_COLS do table.insert(cols, { key = "a" .. i, label = "", width = 90, sort = true }) end
    local nRows = math.floor((PH - 124 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -124)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "miss", true
    l.emptyText = "Nobody online to show."
    l.filter = function(r) return not f.onlyProblems or r.problem end
    l.onEnter = function(r, line)
      GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
      GameTooltip:AddLine(r.id)
      for i = 1, table.getn(r.tips) do
        local tl = r.tips[i]
        local col = (tl.ok == true and C.on) or (tl.ok == false and C.red) or C.dim
        GameTooltip:AddLine(tl.text, col[1], col[2], col[3], 1)
      end
      if not r.answered then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("No direct answer: their shootyepgp is older than 18 Oct (or they are not running it). Once they update, every addon is checked exactly.", 0.6, 0.6, 0.6, 1)
      end
      GameTooltip:Show()
    end
    l.onClick = function(r) if UI.byName and UI.byName[r.id] then UI.OpenHistory(r.id) end end
    f.list = l
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
    f.channel = (GetNumRaidMembers() > 0) and "RAID" or "GUILD"
  end,
  refresh = function(f)
    if not f.names.typing and f.names:GetText() == "" then f.names:SetText(UI.DB().addonList or DEFAULT_LIST) end
    f.chan.Refresh()
    f.problems.Set(f.onlyProblems and true or false)
    -- the addons: the ones asked about, or (before asking) the ones typed
    local names = A.id and A.names or A.Names(f.names:GetText())
    local others = {}
    for i = 1, table.getn(names) do
      if string.lower(names[i]) ~= "shootyepgp" then table.insert(others, names[i]) end
    end
    for i = 1, MAX_COLS do
      local h = f.list.heads[3 + i]
      h.col.label = others[i] or ""   -- the list redraws headers from the label
      h.text:SetText(h.col.label)
    end
    local channel = A.id and A.channel or f.channel
    local expected = A.Expected(channel)
    if A.id then for name in pairs(A.answers) do expected[name] = true end end
    local V = UI.Versions
    local rows, answered, total, bad, old = {}, 0, 0, 0, 0
    for name in pairs(expected) do
      total = total + 1
      local ans = A.id and A.answers[name]
      if ans then answered = answered + 1 end
      local st, ver
      if V then st, ver = V.Status(name) end
      if st == "old" or st == "none" then old = old + 1 end
      local tips, issues = {}, 0
      local sCell, sOk, sTip = A.Cell(name, "shootyepgp", ans, st, ver)
      if sOk ~= true then issues = issues + 1 end
      table.insert(tips, { text = sTip, ok = sOk })
      local m = UI.byName and UI.byName[name]
      local cells = { m and UI.ClassName(name, m.class) or name, "", sCell }
      local sort = { name = name, sepgp = sOk == true and 2 or (sOk == false and 0 or 1), tie = name }
      for i = 1, table.getn(others) do
        local c, okc, tip = A.Cell(name, others[i], ans)
        if okc ~= true then issues = issues + 1 end
        table.insert(tips, { text = tip, ok = okc })
        if i <= MAX_COLS then
          cells[3 + i] = c
          sort["a" .. i] = okc == true and 2 or (okc == false and 0 or 1)
        end
      end
      for i = table.getn(others) + 1, MAX_COLS do cells[3 + i] = "" end
      cells[2] = issues > 0 and UI.Paint(C.red, tostring(issues)) or UI.Paint(C.on, "0")
      sort.miss = issues
      if issues > 0 then bad = bad + 1 end
      table.insert(rows, { id = name, tips = tips, answered = ans and true or false, problem = issues > 0, cells = cells, sort = sort })
    end
    f.list:SetRows(rows, true)
    local where = (channel == "RAID" and "raid") or (channel == "PARTY" and "party") or "online guild members"
    if A.id then
      f.status:SetText("Asked your " .. where .. " at " .. date("%H:%M:%S", A.at) .. "  -  " .. answered .. " of " .. total
        .. " answered directly" .. (old > 0 and (", " .. old .. " on an old shootyepgp (shown from what was heard)") or ""))
    else
      f.status:SetText("Showing what was heard from your " .. where .. ". Press Check to ask - members with an up-to-date shootyepgp answer for every addon.")
    end
    f.count:SetText(bad .. " of " .. total .. " with an issue or unknown  -  hover a row for details")
  end,
}
