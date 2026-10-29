-- shootyepgp :: new window, part 11 - Quick EP / GP (officers)
-- The guild leader asked (29 Oct 2026) for a quick way to give EP or GP to
-- many guild members at once: a list with tick boxes, an amount, one button.
-- Each ticked member goes through the addon's own sepgp:givename_ep /
-- givename_gp (alts' points go to their main, posted and logged as usual),
-- after one "are you sure".

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local QP = {}
UI.QuickPoints = QP

local function MaxPoints() return (sepgp and sepgp.VARS and sepgp.VARS.max) or 1000 end

-- the ticked names, sorted
function QP.Ticked(f)
  local out = {}
  for name, on in pairs(f.ticks) do if on then table.insert(out, name) end end
  table.sort(out)
  return out
end

-- give n EP or GP to every name (the addon's own functions, one by one)
function QP.Give(names, n, what)
  for i = 1, table.getn(names) do
    if what == "EP" then sepgp:givename_ep(names[i], n) else sepgp:givename_gp(names[i], n) end
  end
  if sepgp.refreshPRTablets then sepgp:refreshPRTablets() end
end

local function Ask(f, what)
  local n = tonumber(f.amount:GetText() or "")
  local max = MaxPoints()
  if not n or n == 0 or math.abs(n) >= max or (what == "GP" and n < 0) then
    UI.Confirm("Type an amount first, between 1 and " .. (max - 1) .. (what == "EP" and " (a minus gives an EP penalty, e.g. -50)." or "."), nil, "No amount", "OK")
    return
  end
  local names = QP.Ticked(f)
  if table.getn(names) == 0 then
    UI.Confirm("Tick the members first (the boxes left of their names).", nil, "Nobody ticked", "OK")
    return
  end
  local shown = {}
  for i = 1, math.min(12, table.getn(names)) do shown[i] = names[i] end
  if table.getn(names) > 12 then table.insert(shown, "and " .. (table.getn(names) - 12) .. " more") end
  local verb = (n > 0) and ("give " .. n .. " " .. what .. " to") or ("take " .. (-n) .. " " .. what .. " from")
  UI.Confirm(string.format("This will %s %d members:\n%s\n\nTheir officer notes are rewritten, officers are told and it is logged.",
      verb, table.getn(names), table.concat(shown, ", ")),
    function()
      UI.Call(function() QP.Give(names, n, what) end)
      f.ticks = {}
      UI.RefreshPage()
    end, ((n > 0) and "+" or "") .. n .. " " .. what .. " to " .. table.getn(names) .. " members?", "Yes, give it")
end

UI.Page{ key = "quickpoints", label = "Quick EP / GP", after = "officer", parent = "officer", admin = true,
  tip = "Tick guild members and give them all the same EP or GP at once. Officers only.",
  build = function(f)
    f.ticks = {}
    f.search = UI.EditBox(f, 170)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Hint(f.search, "Search names...")
    f.search.onChange = function() UI.RefreshPage() end
    local function Filter(label, x, tip)
      local cb = UI.CheckBox(f, 14)
      cb:SetPoint("TOPLEFT", f, "TOPLEFT", x, -3)
      local t = UI.Text(f, 11)
      t:SetPoint("LEFT", cb, "RIGHT", 5, 0)
      t:SetText(label)
      cb:SetScript("OnClick", function() UI.RefreshPage() end)
      UI.Tip(cb, label, tip)
      return cb
    end
    f.online = Filter("Online", 184, "Show only members who are online now.")
    f.raid = Filter("In my raid", 254, "Show only members in your raid group.")
    local all = UI.Button(f, "Tick all shown", 110, 20)
    all:SetPoint("TOPLEFT", f, "TOPLEFT", 350, 0)
    all:SetScript("OnClick", function()
      local view = f.list.view
      for i = 1, table.getn(view) do f.ticks[view[i].data] = true end
      UI.RefreshPage()
    end)
    local none = UI.Button(f, "Untick all", 90, 20)
    none:SetPoint("LEFT", all, "RIGHT", 4, 0)
    none:SetScript("OnClick", function() f.ticks = {} UI.RefreshPage() end)

    local cols = {
      { key = "tick", label = "", width = 14, check = true },
      { key = "name", label = "Name", width = 130, sort = "asc" },
      { key = "rank", label = "Rank", width = 100, sort = "asc" },
      { key = "ep", label = "EP", width = 48, align = "RIGHT", sort = true },
      { key = "gp", label = "GP", width = 44, align = "RIGHT", sort = true },
      { key = "pr", label = "PR", width = 48, align = "RIGHT", sort = true },
    }
    local nRows = math.floor((PH - 28 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
    l:SetWidth(PW - 208)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "name", false
    l.checksOn = true
    l.emptyText = "No members match."
    l.onCheck = function(r)
      f.ticks[r.data] = r.ticked or nil
      UI.RefreshPage()
    end
    l.onClick = function(r)
      f.ticks[r.data] = not f.ticks[r.data] or nil
      UI.RefreshPage()
    end
    f.list = l
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)

    -- the amount and the buttons
    local c = UI.Card(f, "Give to the ticked", 200, 214)
    c:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -28)
    f.tickInfo = UI.Text(c, 12, C.gold)
    f.tickInfo:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -34)
    UI.Label(c, "Amount", 12, -62)
    f.amount = UI.EditBox(c, 70)
    f.amount:SetMaxLetters(6)
    f.amount:SetPoint("TOPRIGHT", c, "TOPRIGHT", -12, -59)
    f.amount:SetText("100")
    UI.Tip(f.amount, "Amount", "How many points each ticked member gets. For EP a minus gives a penalty, e.g. -50.")
    local ep = UI.Button(c, "+ EP to ticked", 176, 24)
    ep:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -92)
    ep:SetScript("OnClick", function() Ask(f, "EP") end)
    UI.Tip(ep, "Give EP", "Adds the amount to every ticked member's EP (to their main when alts share EPGP). Asks first.")
    local gp = UI.Button(c, "+ GP to ticked", 176, 24)
    gp:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -122)
    gp:SetScript("OnClick", function() Ask(f, "GP") end)
    UI.Tip(gp, "Give GP", "Adds the amount to every ticked member's GP (to their main when alts share EPGP). Asks first.")
    f.epBtn, f.gpBtn = ep, gp
    local note = UI.Text(c, 10, C.dim)
    note:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -158)
    note:SetWidth(176)
    note:SetHeight(44)
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetText("Alts are not listed:\ntheir points go to their main.")
  end,
  refresh = function(f)
    local roster = UI.Roster()
    local q = string.lower(f.search:GetText() or "")
    local online, inRaid = f.online:GetChecked(), f.raid:GetChecked()
    local rows = {}
    for i = 1, table.getn(roster) do
      local m = roster[i]
      if not m.main and (q == "" or string.find(string.lower(m.name), q, 1, true))
        and (not online or m.online) and (not inRaid or m.inRaid) then
        table.insert(rows, { id = m.name, data = m.name, ticked = f.ticks[m.name] and true or false,
          cells = { "", UI.ClassName(m.name, m.class), m.rank, m.hasEPGP and UI.Fmt(m.ep) or "-", m.hasEPGP and UI.Fmt(m.gp) or "-", m.hasEPGP and UI.FmtPR(m.pr) or "-" },
          sort = { name = m.name, rank = m.rankIndex, ep = m.ep, gp = m.gp, pr = m.pr, tie = m.name } })
      end
    end
    f.list:SetRows(rows, true)
    local n = table.getn(QP.Ticked(f))
    f.count:SetText(table.getn(rows) .. " shown")
    f.tickInfo:SetText(n == 1 and "1 member ticked" or (n .. " members ticked"))
  end,
}
