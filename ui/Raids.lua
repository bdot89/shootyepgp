-- shootyepgp :: new window, part 6 - Raids
-- Guild leader's wish (18 Oct 2026): every raid that awarded EP in one list
-- (date, zone, officer, how many were there, EP given); click a raid for its
-- members, click a member for their history. Officers can correct a raid
-- afterwards: EP or GP to everyone in it or only the ticked members (e.g. an
-- award an officer forgot). Raids are built in History.lua (H.Raids); two
-- groups raiding at the same time are kept apart there.

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local H = UI.History

-- Where raids come from: the real history, or the practice copy while an
-- officer has Practice mode on (ui\RaidsPractice.lua; delete that file and
-- its toc line to remove practice mode - this falls back to H by itself).
local function Src()
  local P = UI.Practice
  if P and P.on then return P end
  return H
end

local function RaidTitle(r)
  return (r.z and r.z ~= "" and r.z or "Raid") .. "  -  " .. date("%a %d %b %Y, %H:%M", r.t)
end

local function AwardText(r)
  local parts = {}
  local list = r.awardList or {}
  for i = 1, table.getn(list) do
    local a = list[i]
    local what = (a.gp and "GP" or "EP")
    local label = (a.kind == "standby") and "standby" or ((a.kind == "fix") and "correction" or ((a.kind == "practice") and "PRACTICE" or "raid"))
    local who = (a.count and a.count > 0) and (a.count .. " people") or "everyone"
    table.insert(parts, date("%H:%M", a.t) .. "   " .. ((a.n or 0) >= 0 and "+" or "") .. (a.n or 0) .. " " .. what .. "  " .. label .. ", " .. who)
  end
  if table.getn(parts) > 7 then
    local more = table.getn(parts) - 6
    local cut = {}
    for i = 1, 6 do cut[i] = parts[i] end
    table.insert(cut, "... and " .. more .. " more")
    parts = cut
  end
  return table.concat(parts, "\n")
end

-- ---------------------------------------------------------------- build

local function BuildList(f)
  local lv = CreateFrame("Frame", nil, f)
  lv:SetAllPoints(f)
  f.lv = lv
  lv.search = UI.EditBox(lv, 200)
  lv.search:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, 0)
  UI.Hint(lv.search, "Search zone, officer or member...")
  lv.search.onChange = function() lv.list:Filter() end
  lv.info = UI.Text(lv, 11, C.dim)
  lv.info:SetPoint("LEFT", lv.search, "RIGHT", 12, 0)
  local cols = {
    { key = "t", label = "When", width = 118, sort = true },
    { key = "z", label = "Zone", width = 150, sort = "asc" },
    { key = "by", label = "Officer", width = 100, sort = "asc" },
    { key = "n", label = "Members", width = 58, align = "RIGHT", sort = true },
    { key = "aw", label = "Awards", width = 50, align = "RIGHT", sort = true },
    { key = "each", label = "EP each", width = 60, align = "RIGHT", sort = true },
    { key = "total", label = "Total EP", width = 66, align = "RIGHT", sort = true },
  }
  local nRows = math.floor((PH - 30 - 24 - 20) / 18)
  local l = UI.List(lv, cols, 18, nRows)
  l:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, -28)
  l:SetWidth(PW)
  l:SetHeight(nRows * 18 + 24)
  l.sortKey, l.sortDesc = "t", true
  l.emptyText = "No raids yet. Every raid that gets EP from now on is listed here; officers' copies are being asked for the ones they have."
  l.filter = function(r)
    local q = lv.search:GetText()
    if not q or q == "" then return true end
    return string.find(r.search, string.lower(q), 1, true) ~= nil
  end
  l.onClick = function(r) UI.pages.raids.open(f, r.data.id) end
  l.onEnter = function(r, line)
    local raid = r.data
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    GameTooltip:AddLine(RaidTitle(raid))
    GameTooltip:AddLine(AwardText(raid), 1, 1, 1, 1)
    GameTooltip:AddLine("Click to see who was there", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end
  lv.list = l
  lv.count = UI.Text(lv, 10, C.dim)
  lv.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
end

local function TickedNames(f)
  local out = {}
  local ticks = f.ticks[f.raidId] or {}
  for name, on in pairs(ticks) do if on then table.insert(out, name) end end
  table.sort(out)
  return out
end

local function AllNames(raid)
  local out = {}
  for name in pairs(raid.members) do table.insert(out, name) end
  table.sort(out)
  return out
end

-- Officer: confirm, then H.Fix
local function AskFix(f, what, everyone)
  local raid = Src().RaidById(f.raidId)
  if not raid then return end
  local n = tonumber(f.rv.amount:GetText() or "")
  local max = (sepgp and sepgp.VARS and sepgp.VARS.max) or 1000
  if not n or n == 0 or math.abs(n) >= max then
    UI.Confirm("Type an amount first (a minus takes points back, e.g. -100). It must be between -" .. max .. " and " .. max .. ".", nil, "No amount", "OK")
    return
  end
  local names = everyone and AllNames(raid) or TickedNames(f)
  if table.getn(names) == 0 then
    UI.Confirm("Tick the members to change first (the boxes left of their names), or use the \"everyone\" buttons.", nil, "Nobody ticked", "OK")
    return
  end
  local shown = {}
  for i = 1, math.min(10, table.getn(names)) do shown[i] = names[i] end
  if table.getn(names) > 10 then table.insert(shown, "and " .. (table.getn(names) - 10) .. " more") end
  local verb = (n > 0) and ("give " .. n .. " " .. what .. " to") or ("take " .. (-n) .. " " .. what .. " from")
  local src = Src()
  local text = string.format("This will %s %d members of\n%s:\n%s\n\nTheir officer notes are rewritten. Officers are told, it is logged and it shows in each member's history as a raid correction.",
      verb, table.getn(names), RaidTitle(raid), table.concat(shown, ", "))
  local title = ((n > 0) and "+" or "") .. n .. " " .. what .. " to " .. table.getn(names) .. " members?"
  if src.practice then
    text = "|cffffc840PRACTICE MODE - nothing is written, posted, logged or sent.|r\n\n" .. text
    title = "Practice: " .. title
  end
  UI.Confirm(text, function() UI.Call(function() src.Fix(raid, names, n, what) end) end, title, "Yes, change them")
end

local function BuildRaid(f)
  local rv = CreateFrame("Frame", nil, f)
  rv:SetAllPoints(f)
  rv:Hide()
  f.rv = rv
  local back = UI.Button(rv, "< All raids", 96, 20)
  back:SetPoint("TOPLEFT", rv, "TOPLEFT", 0, 0)
  back:SetScript("OnClick", function() UI.pages.raids.open(f, nil) end)
  UI.Tip(back, "Back", "Back to the list of raids.")
  rv.title = UI.Text(rv, 13)
  rv.title:SetPoint("LEFT", back, "RIGHT", 10, 0)
  local cols = {
    { key = "tick", label = "", width = 14, check = true },
    { key = "name", label = "Name", width = 120, sort = "asc" },
    { key = "rank", label = "Rank", width = 84, sort = "asc" },
    { key = "role", label = "Was", width = 58, sort = "asc" },
    { key = "ep", label = "EP", width = 46, align = "RIGHT", sort = true },
    { key = "gp", label = "GP", width = 40, align = "RIGHT", sort = true },
  }
  local nRows = math.floor((PH - 30 - 24 - 20) / 18)
  local l = UI.List(rv, cols, 18, nRows)
  l:SetPoint("TOPLEFT", rv, "TOPLEFT", 0, -28)
  l:SetWidth(PW - 214)
  l:SetHeight(nRows * 18 + 24)
  l.sortKey, l.sortDesc = "name", false
  l.onClick = function(r) UI.OpenHistory(r.data) end
  l.onEnter = function(r, line)
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.data)
    GameTooltip:AddLine("Click to open " .. r.data .. "'s history", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end
  l.onCheck = function(r)
    f.ticks[f.raidId] = f.ticks[f.raidId] or {}
    f.ticks[f.raidId][r.data] = r.ticked
    UI.pages.raids.fillRaid(f)
  end
  rv.list = l
  rv.count = UI.Text(rv, 10, C.dim)
  rv.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
  rv.count:SetWidth(PW - 216)
  rv.count:SetJustifyH("LEFT")

  -- right: about the raid, then the officer's fix box
  local d = UI.Card(rv, "This raid", 206, PH - 28)
  d:SetPoint("TOPRIGHT", rv, "TOPRIGHT", 0, -28)
  rv.card = d
  rv.about = UI.Text(d, 11, C.dim)
  rv.about:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -32)
  rv.about:SetWidth(184)
  rv.about:SetJustifyH("LEFT")
  local o = CreateFrame("Frame", nil, d)
  o:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 0, 0)
  o:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 0, 0)
  o:SetHeight(188)
  rv.officer = o
  local line = UI.Fill(o, C.line, 1, "ARTWORK")
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", o, "TOPLEFT", 8, 0)
  line:SetPoint("TOPRIGHT", o, "TOPRIGHT", -8, 0)
  local head = UI.Text(o, 11, C.gold)
  head:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -8)
  head:SetText("Officer: fix this raid")
  rv.amount = UI.EditBox(o, 80)
  rv.amount:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -28)
  rv.amount:SetMaxLetters(6)
  rv.amount:SetText(tostring((sepgp and sepgp.VARS and sepgp.VARS.baseaward_ep) or 100))
  UI.Tip(rv.amount, "Amount", "Points to add. A minus takes them back (e.g. -100 for an award given twice).")
  rv.tickInfo = UI.Text(o, 10, C.dim)
  rv.tickInfo:SetPoint("LEFT", rv.amount, "RIGHT", 8, 0)
  local function B(label, x, y, w, fn, tip)
    local b = UI.Button(o, label, w, 20)
    b:SetPoint("TOPLEFT", o, "TOPLEFT", x, y)
    b:SetScript("OnClick", fn)
    UI.Tip(b, label, tip)
    return b
  end
  rv.epTicked = B("+ EP ticked", 12, -56, 88, function() AskFix(f, "EP", false) end, "Adds the amount of EP to the ticked members only.")
  rv.gpTicked = B("+ GP ticked", 106, -56, 88, function() AskFix(f, "GP", false) end, "Adds the amount of GP to the ticked members only.")
  rv.epAll = B("+ EP everyone", 12, -82, 88, function() AskFix(f, "EP", true) end, "Adds the amount of EP to everyone who was in this raid.")
  rv.gpAll = B("+ GP everyone", 106, -82, 88, function() AskFix(f, "GP", true) end, "Adds the amount of GP to everyone who was in this raid.")
  B("Tick all", 12, -114, 88, function()
    local raid = Src().RaidById(f.raidId)
    if not raid then return end
    f.ticks[f.raidId] = {}
    for name in pairs(raid.members) do f.ticks[f.raidId][name] = true end
    UI.pages.raids.fillRaid(f)
  end, "Ticks everyone in the list.")
  B("Tick none", 106, -114, 88, function()
    f.ticks[f.raidId] = {}
    UI.pages.raids.fillRaid(f)
  end, "Clears every tick.")
  local note = UI.Text(o, 10, C.dim)
  note:SetPoint("TOPLEFT", o, "TOPLEFT", 12, -144)
  note:SetWidth(184)
  note:SetJustifyH("LEFT")
  note:SetText("For mistakes, e.g. a forgotten award. Everything asks first and is logged.")
end

-- ---------------------------------------------------------------- page

UI.Page{ key = "raids", label = "Raids", after = "standings",
  tip = "Every raid that got EP: when, where, who was there and how much. Click a raid for its members.",
  build = function(f)
    f.ticks = {}
    BuildList(f)
    BuildRaid(f)
  end,
  -- id = a raid to show, nil = the list
  open = function(f, id)
    f.raidId = id
    if id then
      f.lv:Hide()
      f.rv:Show()
      UI.pages.raids.fillRaid(f)
    else
      f.rv:Hide()
      f.lv:Show()
      UI.pages.raids.fillList(f)
    end
  end,
  fillList = function(f)
    local raids = Src().Raids()
    local rows = {}
    for i = 1, table.getn(raids) do
      local r = raids[i]
      local search = string.lower((r.z or "") .. " " .. table.concat(r.byList, " "))
      for name in pairs(r.members) do search = search .. " " .. string.lower(name) end
      local members = r.unknown and r.nNamed == 0 and UI.Paint(C.dim, "?") or tostring(r.nNamed)
      table.insert(rows, { id = r.id, data = r, search = search,
        cells = { date("%a %d %b %H:%M", r.t), (r.z and r.z ~= "") and r.z or UI.Paint(C.dim, "not recorded"),
                  table.getn(r.byList) > 0 and table.concat(r.byList, ", ") or UI.Paint(C.dim, "?"),
                  members, tostring(table.getn(r.awardList)), UI.Paint(C.on, tostring(r.epEach)),
                  r.nNamed > 0 and tostring(r.epTotal) or UI.Paint(C.dim, "-") },
        sort = { t = r.t, z = r.z or "", by = r.byList[1] or "", n = r.nNamed, aw = table.getn(r.awardList), each = r.epEach, total = r.epTotal, tie = r.id } })
    end
    f.lv.list:SetRows(rows, true)
    f.lv.info:SetText(table.getn(raids) .. " raids")
    f.lv.count:SetText("Click a raid to see who was there  -  raids are kept apart per group, even on the same night")
  end,
  fillRaid = function(f)
    local raid = Src().RaidById(f.raidId)
    local rv = f.rv
    if not raid then
      UI.pages.raids.open(f, nil)
      return
    end
    local admin = UI.IsAdmin()
    rv.title:SetText(RaidTitle(raid))
    local ticks = f.ticks[f.raidId] or {}
    local rows = {}
    local nTicked = 0
    for name, m in pairs(raid.members) do
      local g = UI.byName and UI.byName[name]
      local role = (m.role == "standby") and UI.Paint(C.dim, "standby") or ((m.role == "fix") and UI.Paint(C.gold, "added") or "raid")
      if ticks[name] then nTicked = nTicked + 1 end
      table.insert(rows, { id = name, data = name, ticked = ticks[name] and true or false,
        cells = { "", g and UI.ClassName(name, g.class) or name, g and g.rank or UI.Paint(C.dim, "left guild"), role,
                  ((m.ep >= 0) and "+" or "") .. m.ep, (m.gp ~= 0) and (((m.gp > 0) and "+" or "") .. m.gp) or "" },
        sort = { name = name, rank = g and g.rankIndex or 99, role = m.role or "", ep = m.ep, gp = m.gp, tie = name } })
    end
    rv.list.checksOn = admin and raid.nNamed > 0
    if raid.nNamed == 0 then
      rv.list.emptyText = "Names were not recorded for this raid. It is from before 18 Oct 2026, when shootyepgp only logged \"EP to the raid\"."
    else
      rv.list.emptyText = "Nobody."
    end
    rv.list:SetRows(rows, true)
    local by = table.getn(raid.byList) > 0 and table.concat(raid.byList, ", ") or "?"
    rv.about:SetText("Date:  " .. date("%A %d %B %Y", raid.t) .. "\n"
      .. "Time:  " .. date("%H:%M", raid.t) .. ((raid.last > raid.t + 60) and (" - " .. date("%H:%M", raid.last)) or "") .. "\n"
      .. "Zone:  " .. ((raid.z and raid.z ~= "") and raid.z or "not recorded") .. "\n"
      .. "Officer:  " .. by .. "\n"
      .. "Members:  " .. ((raid.nNamed > 0) and raid.nNamed or "?") .. "\n\n"
      .. "|cffffffffAwards|r\n" .. AwardText(raid))
    rv.count:SetText(table.getn(rows) .. " members  -  click a name for their history" .. (admin and "  -  tick boxes pick members for a fix" or ""))
    if admin and raid.nNamed > 0 then
      rv.officer:Show()
      rv.tickInfo:SetText(nTicked .. " ticked")
      UI.Enable(rv.epTicked, nTicked > 0)
      UI.Enable(rv.gpTicked, nTicked > 0)
    else
      rv.officer:Hide()
    end
  end,
  refresh = function(f)
    H.Seed()
    H.Ask("#R")
    if f.raidId then UI.pages.raids.fillRaid(f) else UI.pages.raids.fillList(f) end
  end,
}
