-- shootyepgp :: new window, part 3 - the pages
-- Each page = UI.Page{ key, label, tip, build(frame), refresh(frame) }.
-- Data is read fresh on every refresh; buttons that change EPGP, talk in chat
-- or clear saved lists ask first (UI.Confirm) and then call the addon's own
-- function, the same one its old menu calls.

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H

-- ------------------------------------------------------------------ helpers

local function Refreshers(f)
  f.refreshers = f.refreshers or {}
  return f.refreshers
end
local function RunRefreshers(f)
  local r = f.refreshers
  if not r then return end
  for i = 1, table.getn(r) do r[i]() end
end

-- Run something from the addon; print the error instead of breaking the window.
local function Call(fn, a1, a2)
  local ok, err = pcall(fn, a1, a2)
  if not ok then UI.Print("|cffff5555" .. tostring(err) .. "|r") end
  UI.rosterDirty = true
  UI.Refresh()
end
UI.Call = Call

local function Dim(fs) fs:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
local function Bright(fs) fs:SetTextColor(C.text[1], C.text[2], C.text[3]) end

-- toggle + label; locked() greys it out (still shows its tooltip)
local function ToggleRow(f, parent, x, y, label, tip, get, set, locked)
  local t = UI.Switch(parent)
  t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local l = UI.Text(parent, 12)
  l:SetPoint("LEFT", t, "RIGHT", 8, 0)
  l:SetText(label)
  UI.Tip(t, label, tip)
  t.onToggle = function(v)
    Call(set, v)
  end
  table.insert(Refreshers(f), function()
    t.locked = locked and locked() or false
    t.Set(get() and true or false)
    if t.locked then Dim(l) else Bright(l) end
  end)
  return t, l
end

-- a button that is only usable when allowed() says so
local function Gate(f, b, allowed)
  table.insert(Refreshers(f), function() UI.Enable(b, allowed() and true or false) end)
end

local function Admin() return UI.IsAdmin() end
local function GL() return UI.IsGL() end
local function ML() return sepgp and sepgp.lootMaster and sepgp:lootMaster() end

-- label on the left, value on the right of a card line
local function InfoLine(card, y, label, tip)
  local l = UI.Text(card, 12, C.dim)
  l:SetPoint("TOPLEFT", card, "TOPLEFT", 12, y)
  l:SetText(label)
  local v = UI.Text(card, 12)
  v:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, y)
  v:SetJustifyH("RIGHT")
  if tip then
    local hit = CreateFrame("Frame", nil, card)
    hit:SetPoint("TOPLEFT", card, "TOPLEFT", 8, y + 3)
    hit:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, y + 3)
    hit:SetHeight(18)
    hit:EnableMouse(true)
    UI.Tip(hit, label, tip)
  end
  return v
end

-- the item:... part of an item link
function UI.ItemString(link)
  local _, _, s = string.find(link or "", "|H(item:[%-%d:]+)|h")
  return s
end
local function ItemTip(owner, link)
  local s = UI.ItemString(link)
  if not s then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink(s)
  GameTooltip:Show()
end
local function LinkToChat(link)
  if link and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
    ChatFrameEditBox:Insert(link)
    return true
  end
end

-- a number box with a little "+EP" style button beside it
local function AmountBox(parent, width, default)
  local eb = UI.EditBox(parent, width)
  eb:SetNumeric(false)
  eb:SetMaxLetters(6)
  if default then eb:SetText(tostring(default)) end
  return eb
end
local function Amount(eb)
  return tonumber(eb:GetText() or "")
end

local function Suggested()
  local ok, v = pcall(sepgp.suggestedAwardEP, sepgp)
  if ok and tonumber(v) then return tonumber(v) end
  return (sepgp and sepgp.VARS and sepgp.VARS.baseaward_ep) or 100
end

local function MaxPoints() return (sepgp and sepgp.VARS and sepgp.VARS.max) or 1000 end

-- Members with an {EP:GP} note and 1 .. minimum-1 EP: { index, name, note, ep }
function UI.LowEP()
  local floor = tonumber(sepgp_minep) or 0
  local low = {}
  if floor <= 0 then return low end
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, _, _, _, onote = GetGuildRosterInfo(i)
    if name and onote then
      local ep = sepgp:get_ep_v3(name, onote)
      if ep and ep > 0 and ep < floor then table.insert(low, { i, name, onote, ep }) end
    end
  end
  return low
end

-- Officer button: raise everyone in UI.LowEP() to the minimum EP (same note
-- writer the addon's own awards use), tell officers and log it.
function UI.LiftLowEP()
  if not CanEditOfficerNote() then return end
  local floor = tonumber(sepgp_minep) or 0
  local low = UI.LowEP()
  local H, parts, t = UI.History, {}, time()
  for k = 1, table.getn(low) do
    local e = low[k]
    sepgp:update_epgp_v3(floor, nil, e[1], e[2], e[3])
    -- into the EP history (here and, for everyone else, over the guild channel)
    local ev = H.Add({ k = "E", t = t, n = floor - e[4], ep = floor, w = e[2], a = "lift", by = sepgp._playerName })
    if ev then table.insert(parts, H.Enc(ev)) end
  end
  local msgs = H.Pack("HE;", parts, "~")
  for k = 1, table.getn(msgs) do H.Send(msgs[k]) end
  local msg = string.format("Raised %d members below %d EP up to %d EP.", table.getn(low), floor, floor)
  sepgp:adminSay(msg)
  sepgp:addToLog(msg)
  sepgp:refreshPRTablets()
end

-- a toolbar row of buttons from the left at y
local function Buttons(parent, x, y, list)
  local made = {}
  for i = 1, table.getn(list) do
    local d = list[i]
    local b = UI.Button(parent, d[1], d[2] or 120, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetScript("OnClick", d[3])
    UI.Tip(b, d[1], d[4])
    x = x + (d[2] or 120) + 6
    made[i] = b
  end
  return made
end

local function Slash(name, msg)
  return function()
    local fn = SlashCmdList and SlashCmdList[name]
    if fn then Call(fn, msg or "") else UI.Print("that tool is not loaded") end
  end
end

-- ================================================================== Home

UI.Page{ key = "home", label = "Home", tip = "Your EPGP, the guild's rules and what is going on right now.",
  build = function(f)
    local cw = math.floor((PW - 8) / 2)
    local g = UI.Card(f, "Guild rules", cw, 214)
    g:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.tier = InfoLine(g, -34, "Raid progress", "The highest raid tier the guild is doing. Item GP prices and suggested EP awards are scaled by it.")
    f.decay = InfoLine(g, -56, "Decay per run", "When an officer runs a decay, everyone's EP and GP are multiplied down by this much. Keeps old points from piling up.")
    f.osp = InfoLine(g, -78, "Offspec price", "An offspec item costs this share of its normal GP. Each raid tier has its own share (Prices shows each item's offspec GP); this is the current tier's.")
    f.minep = InfoLine(g, -100, "Minimum EP", "Members below this EP are listed after everyone above it in standings and bids.")
    f.basegp = InfoLine(g, -122, "Starting GP", "Everyone's GP starts here and never drops below it (so PR = EP / GP never divides by zero).")
    f.alts = InfoLine(g, -144, "Alts use main's EPGP", "When on, an alt's EP and GP go to the main named in the alt's officer note as {Main}.")
    f.chan = InfoLine(g, -166, "Report channel", "Where officers' award messages are posted.")
    f.reschan = InfoLine(g, -188, "Standby channel", "The chat channel used for the standby (reserves) list.")

    local y = UI.Card(f, "You", cw, 214)
    y:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.char = InfoLine(y, -34, "Character")
    f.main = InfoLine(y, -56, "Main", "The character whose EPGP you use. Set it under Standby if it is wrong.")
    f.rank = InfoLine(y, -78, "Guild rank")
    f.place = InfoLine(y, -100, "Standings place")
    f.decayPR = InfoLine(y, -122, "Next decay", "How your PR changes at the next decay run (near the EPGP cap the decay costs you PR).")
    f.standby = InfoLine(y, -144, "On standby list", "Whether you have joined the standby (reserves) list.")
    f.strikes = InfoLine(y, -166, "Strikes", "Raid strikes officers gave you (Strikes topic).")
    f.access = InfoLine(y, -188, "Your access", "Officers who can edit officer notes see the Officer topic.")

    local n = UI.Card(f, "Right now", PW, 112)
    n:SetPoint("TOPLEFT", g, "BOTTOMLEFT", 0, -8)
    local function Tile(x, caption, page)
      local t = UI.Tile(n, caption, 122)
      t:SetPoint("TOPLEFT", n, "TOPLEFT", x, -32)
      t:EnableMouse(true)
      t.page = page
      t:SetScript("OnMouseUp", function() UI.Select(this.page) end)
      UI.Hover(t, 0.05)
      return t
    end
    f.tMembers = Tile(10, "members with EP", "standings")
    f.tRaid = Tile(140, "in your raid", "standings")
    f.tBids = Tile(270, "bids open", "bids")
    f.tLoot = Tile(400, "items in loot history", "loot")
    f.tRes = Tile(530, "on standby", "reserves")
    f.bidItem = UI.Text(n, 11, C.dim)
    f.bidItem:SetPoint("TOPLEFT", n, "TOPLEFT", 12, -86)

    local b = Buttons(f, 0, -342, {
      { "Open standings", 130, function() UI.Select("standings") end, "The whole guild's EP, GP and PR." },
      { "My EPGP in chat", 130, function()
          Call(function() sepgp:my_epgp(sepgp_main ~= nil and sepgp_main ~= sepgp._playerName) end)
        end, "Prints your EP, GP and PR in your chat window (only you see it) after re-reading the guild notes." },
      { "Ask for new data", 130, function() UI.RequestRoster(true) UI.rosterDirty = true UI.Refresh() end,
        "EP and GP live in the guild's officer notes. This asks the server for the newest notes." },
    })
    local help = UI.Text(f, 11, C.dim)
    help:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -376)
    help:SetWidth(PW)
    help:SetJustifyH("LEFT")
    help:SetText("How it works: you earn EP for raiding and standby, you pay GP for loot. Your priority is PR = EP / GP; "
      .. "the highest PR who bids on an item gets it. Decay lowers everyone's EP and GP now and then so recent effort counts most. "
      .. "To bid, click the [MAINSPEC] or [OFFSPEC] link the loot master posts, or whisper them + (mainspec) or - (offspec).")
  end,
  refresh = function(f)
    local me, char = UI.Me()
    local V = sepgp.VARS
    local decay = math.floor((1 - (sepgp_decay or V.decay)) * 100 + 0.5)
    f.tier:SetText(tostring(sepgp_progress or "T1"))
    f.decay:SetText(decay .. "%")
    f.osp:SetText(math.floor(UI.Prices.Rate(sepgp_progress) * 100 + 0.5) .. "%" .. UI.Paint(C.dim, "  (" .. tostring(sepgp_progress or "T1") .. ")"))
    f.minep:SetText((sepgp_minep or 0) > 0 and tostring(sepgp_minep) or "none")
    f.basegp:SetText(tostring(V.basegp))
    f.alts:SetText(sepgp_altspool and UI.Paint(C.on, "on") .. "  (" .. math.floor((sepgp_altpercent or 1) * 100 + 0.5) .. "% of EP)" or UI.Paint(C.dim, "off"))
    f.chan:SetText(tostring(sepgp_saychannel or "GUILD"))
    f.reschan:SetText(tostring(sepgp_reservechannel or "-"))

    local myName = sepgp._playerName
    f.char:SetText(char and UI.ClassName(char.name, char.class) or myName)
    f.main:SetText(me and me ~= char and UI.ClassName(me.name, me.class) or (sepgp_main or UI.Paint(C.dim, "not set")))
    f.rank:SetText(char and char.rank or "-")
    f.place:SetText(me and me.pos and ("#" .. me.pos .. " of " .. table.getn(UI.ranked or {})) or UI.Paint(C.dim, "no EP yet"))
    if me and me.hasEPGP and sepgp.capcalc then
      local ok, prDecay = pcall(sepgp.capcalc, sepgp, me.ep, me.gp)
      if ok and prDecay and prDecay < 0 then
        f.decayPR:SetText(UI.Paint(C.red, string.format("PR %.3f", prDecay)) .. UI.Paint(C.dim, " (near the cap)"))
      else
        f.decayPR:SetText(UI.Paint(C.on, "no PR loss"))
      end
    else
      f.decayPR:SetText("-")
    end
    local inRes = sepgp.reservesChannelID ~= nil and sepgp.reservesChannelID ~= 0
    f.standby:SetText(inRes and UI.Paint(C.on, "yes") or UI.Paint(C.dim, "no"))
    local s = type(RaidStrikeDB) == "table" and RaidStrikeDB[myName]
    f.strikes:SetText(s and s > 0 and UI.Paint(C.red, tostring(s)) or UI.Paint(C.dim, "none"))
    f.access:SetText(UI.IsGL() and "guild leader" or (UI.IsAdmin() and "officer" or "member"))

    local inRaid = 0
    local roster = UI.roster or {}
    for i = 1, table.getn(roster) do if roster[i].inRaid then inRaid = inRaid + 1 end end
    f.tMembers.value:SetText(tostring(table.getn(UI.ranked or {})))
    f.tRaid.value:SetText(GetNumRaidMembers() > 0 and tostring(inRaid) or UI.Paint(C.dim, "-"))
    local nb = table.getn(sepgp.bids_main or {}) + table.getn(sepgp.bids_off or {})
    f.tBids.value:SetText(tostring(nb))
    f.tLoot.value:SetText(tostring(table.getn(UI.History.All({ L = 1 }))))
    f.tRes.value:SetText(tostring(table.getn(sepgp.reserves or {})))
    -- bids, loot and the standby list are officer pages
    local admin = UI.IsAdmin()
    local tiles = { f.tBids, f.tRes }
    for i = 1, 2 do
      if admin then tiles[i]:Show() else tiles[i]:Hide() end
    end
    local link = sepgp.bid_item and sepgp.bid_item.link
    f.bidItem:SetText(link and ("Bidding on: " .. link) or "No item is up for bids.")
  end,
}

-- ================================================================== Standings

UI.Page{ key = "standings", label = "Standings", tip = "Everyone's EP, GP and PR from the guild notes. Click a name for details.",
  badge = function() return nil end,
  build = function(f)
    f.search = UI.EditBox(f, 150)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Hint(f.search, "Search name or rank...")
    f.search.onChange = function() f.list:Filter() end
    ToggleRow(f, f, 164, -2, "My raid only", "Only members in your raid. (Same switch as the old standings window.)",
      function() return sepgp_raidonly end,
      function() sepgp_raidonly = not sepgp_raidonly if sepgp.SetRefresh then sepgp:SetRefresh(true) end end)
    ToggleRow(f, f, 290, -2, "Online", "Only members who are online now.",
      function() return f.online end, function(v) f.online = v end)
    ToggleRow(f, f, 382, -2, "Everyone", "Also list members with 0 EP.",
      function() return f.everyone end, function(v) f.everyone = v end)
    local ex = UI.Button(f, "Export standings", 120, 20)
    ex:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ex:SetScript("OnClick", function() Call(function() sepgp_standings:Export() end) end)
    UI.Tip(ex, "Export", "Shows the standings as text (Name;EP;GP;PR) to copy with Ctrl-C.")

    local cols = {
      { key = "pos", label = "#", width = 24, align = "RIGHT", sort = "asc" },
      { key = "name", label = "Name", width = 112, sort = "asc" },
      { key = "rank", label = "Rank", width = 90, sort = "asc" },
      { key = "ep", label = "EP", width = 44, align = "RIGHT", sort = true },
      { key = "gp", label = "GP", width = 44, align = "RIGHT", sort = true },
      { key = "pr", label = "PR", width = 50, align = "RIGHT", sort = true },
    }
    local nRows = math.floor((PH - 30 - 22 - 20) / 18)
    local list = UI.List(f, cols, 18, nRows)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
    list:SetWidth(PW - 214)
    list:SetHeight(nRows * 18 + 24)
    list.sortKey, list.sortDesc = "pos", false
    list.emptyText = "No one to show. EP and GP live in the guild's officer notes - press Refresh at the top if the guild list is still loading."
    list.filter = function(r)
      local m = r.data
      if not f.everyone and m.ep <= 0 then return false end
      if f.online and not m.online then return false end
      if sepgp_raidonly and GetNumRaidMembers() > 0 and not m.inRaid then return false end
      local q = f.search:GetText()
      if q and q ~= "" then
        q = string.lower(q)
        if not string.find(string.lower(m.name), q, 1, true) and not string.find(string.lower(m.rank), q, 1, true) then return false end
      end
      return true
    end
    list.onClick = function(r)
      list.selected = r.id
      f.sel = r.data.name
      list:Draw()
      UI.pages.standings.detail(f)
      UI.pages.standings.showHistory(f, true)
    end
    list.onEnter = function(r, line)
      local m = r.data
      GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
      GameTooltip:AddLine(UI.ClassName(m.name, m.class))
      GameTooltip:AddLine(m.rank .. "  -  level " .. m.level .. (m.online and ("  -  " .. m.zone) or "  -  offline"), 0.8, 0.8, 0.8)
      if m.main then GameTooltip:AddLine("Alt of " .. m.main, 1, 0.82, 0) end
      GameTooltip:AddLine("Click for details" .. (UI.IsAdmin() and " and EP / GP awards" or ""), 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end
    f.list = list
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 2, -5)
    f.count:SetWidth(PW - 216)
    f.count:SetJustifyH("LEFT")

    -- a member's history: shown in place of the list when a name is clicked
    local hv = CreateFrame("Frame", nil, f)
    hv:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    hv:SetWidth(PW - 214)
    hv:SetHeight(nRows * 18 + 24 + 22)
    hv:Hide()
    f.hv = hv
    local back = UI.Button(hv, "< Standings", 96, 20)
    back:SetPoint("TOPLEFT", hv, "TOPLEFT", 0, 0)
    back:SetScript("OnClick", function() UI.pages.standings.showHistory(f, false) end)
    UI.Tip(back, "Back", "Back to the whole guild's standings.")
    hv.title = UI.Text(hv, 12)
    hv.title:SetPoint("LEFT", back, "RIGHT", 10, 0)
    hv.tabs = {}
    local TABS = { { "all", "All" }, { "loot", "Loot" }, { "points", "EP / GP" } }
    for i = 1, 3 do
      local b = UI.Button(hv, TABS[i][2], 62, 20)
      b:SetPoint("TOPRIGHT", hv, "TOPRIGHT", -(3 - i) * 66, 0)
      b.key = TABS[i][1]
      b:SetScript("OnClick", function() f.histTab = this.key UI.pages.standings.fillHistory(f) end)
      hv.tabs[i] = b
    end
    local hcols = {
      { key = "t", label = "When", width = 82, sort = true },
      { key = "what", label = "What", width = 250, sort = "asc" },
      { key = "ep", label = "EP", width = 40, align = "RIGHT", sort = true },
      { key = "gp", label = "GP", width = 40, align = "RIGHT", sort = true },
    }
    local hl = UI.List(hv, hcols, 18, nRows - 1)
    hl:SetPoint("TOPLEFT", hv, "TOPLEFT", 0, -26)
    hl:SetWidth(PW - 214)
    hl:SetHeight((nRows - 1) * 18 + 24)
    hl.sortKey, hl.sortDesc = "t", true
    hl.onEnter = function(r, line)
      local e = r.data
      if e.k == "L" then
        local s = UI.ItemString(UI.History.ItemLink(e))
        if s then
          GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
          GameTooltip:SetHyperlink(s)
          GameTooltip:AddLine(" ")
        else
          GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
        end
      else
        GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
      end
      GameTooltip:AddLine(date("%A %d %B %Y, %H:%M", e.t), 0.8, 0.8, 0.8)
      if e.by then GameTooltip:AddLine("By " .. e.by, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end
    hl.onClick = function(r) if r.data.k == "L" and IsShiftKeyDown() then LinkToChat(UI.History.ItemLink(r.data)) end end
    hv.list = hl
    f.histTab = "all"

    -- details of the picked member
    local d = UI.Card(f, "Details", 206, PH - 28)
    d:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -28)
    f.d = d
    d.name = UI.Text(d, 14)
    d.name:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -32)
    d.info = UI.Text(d, 10, C.dim)
    d.info:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
    d.info:SetWidth(184)
    d.info:SetJustifyH("LEFT")
    d.ep = InfoLine(d, -84, "EP")
    d.gp = InfoLine(d, -104, "GP")
    d.pr = InfoLine(d, -124, "PR")
    d.pos = InfoLine(d, -144, "Place")
    d.decay = InfoLine(d, -164, "Next decay", "How this member's PR changes at the next decay run.")
    d.alts = UI.Text(d, 10, C.dim)
    d.alts:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -186)
    d.alts:SetWidth(184)
    d.alts:SetJustifyH("LEFT")
    local w = UI.Button(d, "Whisper", 88, 20)
    w:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -232)
    w:SetScript("OnClick", function() if f.sel then ChatFrame_SendTell(f.sel) end end)
    UI.Tip(w, "Whisper", "Opens a whisper to this member.")
    d.whisper = w
    -- officer box
    d.adminTitle = UI.Text(d, 11, C.gold)
    d.adminTitle:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -266)
    d.adminTitle:SetText("Officer: give points")
    d.amount = AmountBox(d, 70, Suggested())
    d.amount:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -284)
    UI.Tip(d.amount, "Amount", "How many points. Use a minus for an EP penalty, e.g. -50.")
    local gep = UI.Button(d, "+ EP", 50, 20)
    gep:SetPoint("LEFT", d.amount, "RIGHT", 6, 0)
    local ggp = UI.Button(d, "+ GP", 50, 20)
    ggp:SetPoint("LEFT", gep, "RIGHT", 4, 0)
    UI.Tip(gep, "Give EP", "Adds the amount to this member's EP (to their main when alts share EPGP). Posted to officers and logged.")
    UI.Tip(ggp, "Give GP", "Adds the amount to this member's GP (to their main when alts share EPGP). Posted to officers and logged.")
    gep:SetScript("OnClick", function()
      local n, who = Amount(d.amount), f.sel
      if not who or not n or n == 0 or math.abs(n) >= MaxPoints() then UI.Print("type an amount between -" .. MaxPoints() .. " and " .. MaxPoints()) return end
      UI.Confirm(string.format("Give %d EP to %s?", n, who), function()
        Call(function() sepgp:givename_ep(who, n) sepgp:refreshPRTablets() end)
      end)
    end)
    ggp:SetScript("OnClick", function()
      local n, who = Amount(d.amount), f.sel
      if not who or not n or n == 0 or n >= MaxPoints() then UI.Print("type an amount below " .. MaxPoints()) return end
      UI.Confirm(string.format("Give %d GP to %s?", n, who), function()
        Call(function() sepgp:givename_gp(who, n) sepgp:refreshPRTablets() end)
      end)
    end)
    d.adminBits = { d.adminTitle, d.amount, gep, ggp }
    d.adminNote = UI.Text(d, 10, C.dim)
    d.adminNote:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -312)
    d.adminNote:SetWidth(184)
    d.adminNote:SetJustifyH("LEFT")
    d.adminNote:SetText("Changes the guild officer note. Every award is posted to officers and kept in Logs.")
    table.insert(d.adminBits, d.adminNote)
  end,
  -- swap the guild list for the picked member's history (or back)
  showHistory = function(f, on)
    if on and f.sel then
      f.list:Hide()
      f.count:Hide()
      f.hv:Show()
      UI.History.Ask(f.sel)
      UI.pages.standings.fillHistory(f)
    else
      f.hv:Hide()
      f.list:Show()
      f.count:Show()
    end
  end,
  fillHistory = function(f)
    local hv = f.hv
    if not hv:IsShown() or not f.sel then return end
    for i = 1, 3 do UI.Pick(hv.tabs[i], hv.tabs[i].key == f.histTab) end
    local m = UI.byName and UI.byName[f.sel]
    local evs = UI.History.For(f.sel)
    -- decays: everyone's, with this member's before / after when the decay log has them
    if UI.Decay and UI.Decay.ForMember then
      local copy = {}
      for i = 1, table.getn(evs) do copy[i] = evs[i] end
      local dec = UI.Decay.ForMember(f.sel)
      for i = 1, table.getn(dec) do table.insert(copy, dec[i]) end
      evs = copy
    end
    local rows = {}
    for i = 1, table.getn(evs) do
      local e = evs[i]
      local keep = f.histTab == "all" or (f.histTab == "loot" and e.k == "L") or (f.histTab == "points" and e.k ~= "L")
      if keep then
        local what, ep, gp
        if e.k == "X" then
          what = UI.Paint(C.gold, (e.pct or 0) .. "% decay") .. UI.Paint(C.dim, "  (now " .. tostring(e.epA) .. " EP, " .. tostring(e.gpA) .. " GP)")
          local dEP, dGP = (e.epA or 0) - (e.epB or 0), (e.gpA or 0) - (e.gpB or 0)
          ep = dEP ~= 0 and UI.Paint(C.red, tostring(dEP)) or ""
          gp = dGP ~= 0 and UI.Paint(C.on, tostring(dGP)) or ""
        elseif e.k == "XU" then
          what, ep, gp = UI.Paint(C.gold, (e.pct or 0) .. "% decay undone") .. UI.Paint(C.dim, "  (put back)"), "", ""
        else
          what, ep, gp = UI.History.Describe(e)
        end
        if m and e.w and e.w ~= f.sel then what = what .. UI.Paint(C.dim, "  (" .. e.w .. ")") end
        table.insert(rows, { id = i, data = e, cells = { UI.Paint(C.dim, UI.History.When(e.t)), what, ep, gp },
          sort = { t = e.t, what = e.k .. (e.nm or ""), ep = (e.k == "E") and e.n or 0, gp = (e.k == "G" or e.k == "L") and e.n or 0, tie = i } })
      end
    end
    hv.list.emptyText = "Nothing recorded for " .. f.sel .. " yet. Officers' copies are being asked - if one is online, their history arrives in a few seconds."
    hv.list:SetRows(rows, true)
    hv.title:SetText((m and UI.ClassName(m.name, m.class) or f.sel) .. UI.Paint(C.dim, "  -  " .. table.getn(rows) .. " entries"))
  end,
  detail = function(f)
    local d = f.d
    local m = f.sel and UI.byName and UI.byName[f.sel]
    local admin = UI.IsAdmin()
    for i = 1, table.getn(d.adminBits) do
      if admin and m then d.adminBits[i]:Show() else d.adminBits[i]:Hide() end
    end
    if not m then
      d.name:SetText(UI.Paint(C.dim, "Pick a name"))
      d.info:SetText("Click anyone in the list to see their points" .. (admin and " and give EP or GP." or "."))
      d.ep:SetText("") d.gp:SetText("") d.pr:SetText("") d.pos:SetText("") d.decay:SetText("") d.alts:SetText("")
      d.whisper:Hide()
      return
    end
    d.whisper:Show()
    d.name:SetText(UI.ClassName(m.name, m.class))
    d.info:SetText(m.rank .. "  -  level " .. m.level .. "\n" .. (m.online and UI.Paint(C.on, "online") .. "  " .. m.zone or "offline"))
    local minep = sepgp_minep or 0
    d.ep:SetText((minep > 0 and m.ep < minep) and UI.Paint(C.red, UI.Fmt(m.ep)) or UI.Fmt(m.ep))
    d.gp:SetText(UI.Fmt(m.gp))
    d.pr:SetText(UI.Paint(C.gold, UI.FmtPR(m.pr)))
    d.pos:SetText(m.pos and ("#" .. m.pos) or "-")
    local ok, prDecay = pcall(sepgp.capcalc, sepgp, m.ep, m.gp)
    d.decay:SetText((ok and prDecay and prDecay < 0) and UI.Paint(C.red, string.format("%.3f", prDecay)) or UI.Paint(C.dim, "no loss"))
    local txt = ""
    if m.main then txt = "Alt of " .. m.main .. (sepgp_altspool and " - EPGP goes to the main." or " (alts pool is off).") end
    if m.alts then txt = "Alts: " .. table.concat(m.alts, ", ") end
    if not m.hasEPGP then txt = txt .. (txt ~= "" and "\n" or "") .. "No {EP:GP} in the officer note yet." end
    d.alts:SetText(txt)
  end,
  refresh = function(f)
    RunRefreshers(f)
    local rows = {}
    local list = UI.roster or {}
    for i = 1, table.getn(list) do
      local m = list[i]
      local minep = sepgp_minep or 0
      local below = minep > 0 and m.ep < minep
      local isMe = (m.name == sepgp._playerName) or (sepgp_main and m.name == sepgp_main)
      local name = UI.ClassName(m.name, m.class)
      if isMe then name = UI.Paint(C.gold, "> ") .. name end
      if m.main then name = name .. UI.Paint(C.dim, " (alt)") end
      if not m.online then name = name .. "" end
      table.insert(rows, {
        id = m.name, data = m,
        cells = {
          m.pos and UI.Paint(C.dim, m.pos) or "",
          name,
          UI.Paint(m.online and C.text or C.dim, m.rank),
          below and UI.Paint(C.red, UI.Fmt(m.ep)) or UI.Fmt(m.ep),
          UI.Fmt(m.gp),
          below and UI.Paint(C.red, UI.FmtPR(m.pr)) or UI.Paint(C.gold, UI.FmtPR(m.pr)),
        },
        sort = { pos = m.pos or 99999, name = m.name, rank = m.rankIndex, ep = m.ep, gp = m.gp, pr = m.pr, tie = m.name },
      })
    end
    f.list:SetRows(rows, true)
    f.count:SetText(table.getn(f.list.view) .. " of " .. table.getn(list) .. " members  -  red = below minimum EP  -  click a name for their history")
    UI.pages.standings.detail(f)
    UI.pages.standings.fillHistory(f)
  end,
}

-- ================================================================== Bids

local function BidList(f, title, y, nRows)
  local t = UI.Text(f, 12, C.gold)
  t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
  t:SetText(title)
  local cols = {
    { key = "name", label = "Name", width = 150, sort = "asc" },
    { key = "rank", label = "Rank", width = 110, sort = "asc" },
    { key = "ep", label = "EP", width = 60, align = "RIGHT", sort = true },
    { key = "gp", label = "GP", width = 60, align = "RIGHT", sort = true },
    { key = "pr", label = "PR", width = 60, align = "RIGHT", sort = true },
    { key = "main", label = "Main / note", width = 150, sort = "asc" },
  }
  local l = UI.List(f, cols, 18, nRows)
  l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y - 18)
  l:SetWidth(PW)
  l:SetHeight(nRows * 18 + 24)
  l.sortKey, l.sortDesc = "order", false
  return l
end

local function BidRows(bids, offspec)
  local rows = {}
  local minep = sepgp_minep or 0
  for i = 1, table.getn(bids or {}) do
    local b = bids[i]
    local name, class, ep, gp, pr, main, flag = b[1], b[2], tonumber(b[3]) or 0, tonumber(b[4]) or 0, tonumber(b[5]) or 0, b[6] or "", b[7] or ""
    local below = minep > 0 and ep < minep
    local m = UI.byName and UI.byName[name]
    local label = UI.ClassName(name, class)
    if flag == "OSPRIO" then label = UI.Paint(C.red, "[PRIO] ") .. label end
    -- the addon's order: at / above minimum EP first, then PR, then EP
    local order = (below and 1000000 or 0) - pr * 1000 - ep / 100000
    table.insert(rows, {
      id = name, data = { name = name, pr = pr, offspec = offspec, prio = (flag == "OSPRIO") },
      cells = { label, m and m.rank or "", below and UI.Paint(C.red, UI.Fmt(ep)) or UI.Fmt(ep), UI.Fmt(gp),
                below and UI.Paint(C.red, UI.FmtPR(pr)) or UI.Paint(C.gold, UI.FmtPR(pr)), main ~= "" and ("alt of " .. main) or "" },
      sort = { order = order, name = name, rank = m and m.rankIndex or 99, ep = ep, gp = gp, pr = pr, main = main, tie = name },
    })
  end
  return rows
end

UI.Page{ key = "bids", label = "Bids", tip = "The item up for bids and everyone who bid on it. Officers only.", admin = true,
  badge = function() return table.getn(sepgp.bids_main or {}) + table.getn(sepgp.bids_off or {}) end,
  build = function(f)
    local h = UI.Card(f, nil, PW, 52)
    h:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.item = CreateFrame("Button", nil, h)
    f.item:SetPoint("TOPLEFT", h, "TOPLEFT", 12, -8)
    f.item:SetWidth(330)
    f.item:SetHeight(18)
    f.itemText = UI.Text(f.item, 13)
    f.itemText:SetAllPoints(f.item)
    f.itemText:SetJustifyH("LEFT")
    f.item:SetScript("OnEnter", function() ItemTip(this, sepgp.bid_item and sepgp.bid_item.link) end)
    f.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.item:SetScript("OnClick", function() if IsShiftKeyDown() then LinkToChat(sepgp.bid_item and sepgp.bid_item.link) end end)
    f.cost = UI.Text(h, 11, C.dim)
    f.cost:SetPoint("TOPLEFT", h, "TOPLEFT", 12, -30)
    f.cost:SetWidth(PW - 340)
    f.cost:SetJustifyH("LEFT")
    f.counter = UI.Text(h, 12)
    f.counter:SetPoint("TOPRIGHT", h, "TOPRIGHT", -12, -10)
    local b = Buttons(h, PW - 210, -26, {
      { "Countdown", 96, function() Call(function() sepgp_bids:bidCountdown() end) end,
        "Loot master: counts 5 to 1 in raid chat, then bidding is finished." },
      { "Attention", 96, function() Call(function() sepgp_bids:sendAttention() end) end,
        "Loot master: pings the officers' bid windows." },
    })
    Gate(f, b[1], ML)
    Gate(f, b[2], ML)
    local nRows = math.floor((PH - 60 - 36 - 48 - 30) / 2 / 18)
    f.ms = BidList(f, "Mainspec bids", -60, nRows)
    f.os = BidList(f, "Offspec bids", -60 - nRows * 18 - 50, nRows)
    f.ms.emptyText = "No mainspec bids."
    f.os.emptyText = "No offspec bids."
    local function Winner(r)
      if not UI.IsAdmin() then return end
      local d = r.data
      UI.Confirm(string.format("Announce %s as the %s winner (%.3f PR)?", d.name, d.offspec and "offspec" or "mainspec", d.pr), function()
        Call(function()
          if d.offspec then sepgp_bids:announceWinnerOS((d.prio and "[PRIO] " or "") .. d.name, d.pr)
          else sepgp_bids:announceWinnerMS(d.name, d.pr) end
        end)
      end)
    end
    f.ms.onClick, f.os.onClick = Winner, Winner
    f.help = UI.Text(f, 10, C.dim)
    f.help:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 2)
    f.help:SetWidth(PW)
    f.help:SetJustifyH("LEFT")
  end,
  refresh = function(f)
    RunRefreshers(f)
    local it = sepgp.bid_item or {}
    if it.link then
      f.itemText:SetText(it.link)
      local ok, osPrice, price = pcall(sepgp_prices.GetOffspec, sepgp_prices, it.link, sepgp_progress)
      if ok and price then
        f.cost:SetText("Mainspec " .. price .. " GP   -   Offspec " .. osPrice .. " GP")
      else
        f.cost:SetText("No GP price known for this item.")
      end
    else
      f.itemText:SetText(UI.Paint(C.dim, "No item up for bids"))
      f.cost:SetText("Shows here when the loot master calls for bids.")
    end
    f.counter:SetText(sepgp_bids and sepgp_bids._counterText or "")
    f.ms:SetRows(BidRows(sepgp.bids_main, false), true)
    f.os:SetRows(BidRows(sepgp.bids_off, true), true)
    if UI.IsAdmin() then
      f.help:SetText("Click a bidder to announce them as the winner. Shift-click the item to link it in chat. Bids reach officers only.")
    else
      f.help:SetText("To bid, click [MAINSPEC] or [OFFSPEC] in the loot master's raid message, or whisper them + or -. Officers see the bid list.")
    end
  end,
}

-- ================================================================== Loot

UI.Page{ key = "loot", label = "Loot", tip = "Loot history: every item handed out, who got it and the GP it cost.",
  badge = function() return nil end,
  build = function(f)
    f.search = UI.EditBox(f, 170)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Hint(f.search, "Search item or player...")
    f.search.onChange = function() f.list:Filter() end
    -- officers only: the addon's per-raid list (the history is kept either way)
    f.offBtns = Buttons(f, PW - 130, 0, {
      { "Clear raid list", 130, function()
          UI.Confirm("Clear the addon's loot list for this raid? (" .. table.getn(sepgp_looted or {}) .. " entries. Loot history and EP / GP are kept.)", function()
            Call(function() sepgp_looted = {} sepgp_loot:Refresh() sepgp:defaultPrint("Loot info cleared") end)
          end)
        end, "Empties the addon's own loot list (it suggests this before each raid). The loot history on this page is kept." },
    })
    local cols = {
      { key = "t", label = "When", width = 86, sort = true },
      { key = "item", label = "Item", width = 214, sort = "asc" },
      { key = "who", label = "Looter", width = 110, sort = "asc" },
      { key = "gp", label = "GP", width = 46, align = "RIGHT", sort = true },
      { key = "action", label = "Charged as", width = 150, sort = "asc" },
    }
    local nRows = math.floor((PH - 30 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "t", true
    l.emptyText = "No loot history yet. Officers' copies are being asked - if one is online, the newest loot arrives in a few seconds."
    l.filter = function(r)
      local q = f.search:GetText()
      if not q or q == "" then return true end
      return string.find(r.search, string.lower(q), 1, true) ~= nil
    end
    l.onEnter = function(r, line)
      ItemTip(line, UI.History.ItemLink(r.data))
      if r.data.by then
        GameTooltip:AddLine("Recorded by " .. r.data.by, 0.6, 0.6, 0.6)
        GameTooltip:Show()
      end
    end
    l.onClick = function(r)
      if IsShiftKeyDown() then LinkToChat(UI.History.ItemLink(r.data))
      elseif r.data.w and UI.byName and UI.byName[r.data.w] then
        -- click a row: that player's history in Standings
        UI.Select("standings")
        local st = UI.pages.standings.frame
        st.sel = r.data.w
        st.list.selected = r.data.w
        UI.pages.standings.detail(st)
        UI.pages.standings.showHistory(st, true)
      end
    end
    f.list = l
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
  end,
  refresh = function(f)
    if UI.IsAdmin() then f.offBtns[1]:Show() else f.offBtns[1]:Hide() end
    UI.History.Seed()
    UI.History.Ask("*")
    local rows = {}
    local evs = UI.History.All({ L = 1 })
    for i = 1, table.getn(evs) do
      local e = evs[i]
      local m = UI.byName and e.w and UI.byName[e.w]
      local who = m and UI.ClassName(e.w, m.class) or (e.w or "?")
      table.insert(rows, {
        id = i, data = e, search = string.lower((e.nm or "") .. " " .. (e.w or "") .. " " .. (e.a or "")),
        cells = { UI.Paint(C.dim, UI.History.When(e.t)), UI.History.ItemLink(e), who,
                  (e.n and e.n > 0) and tostring(e.n) or UI.Paint(C.dim, "0"), e.a or "" },
        sort = { t = e.t, item = e.nm or "", who = e.w or "", gp = e.n or 0, action = e.a or "", tie = i },
      })
    end
    f.list:SetRows(rows, true)
    f.count:SetText(table.getn(rows) .. " items in the loot history  -  click a row for that player's history, Shift-click to link the item")
  end,
}

-- ================================================================== Reserves (standby)

UI.Page{ key = "reserves", label = "Standby", tip = "Join the standby (reserves) list and set your main. Officers also see who is on it.",
  badge = function() return UI.IsAdmin() and table.getn(sepgp.reserves or {}) or nil end,
  build = function(f)
    local you = UI.Card(f, "You", 260, 196)
    you:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    ToggleRow(f, you, 12, -36, "I'm on standby", "Joins the guild's standby chat channel so officers' standby checks reach you. Needs your main's name.",
      function() return sepgp.reservesChannelID ~= nil and sepgp.reservesChannelID ~= 0 end,
      function(v) sepgp:reservesToggle(v) end,
      function() return sepgp_main == nil end)
    UI.Label(you, "Your main", 12, -70)
    f.main = UI.EditBox(you, 140)
    f.main:SetPoint("TOPLEFT", you, "TOPLEFT", 12, -88)
    f.main:SetMaxLetters(12)
    local set = UI.Button(you, "Set", 60, 20)
    set:SetPoint("LEFT", f.main, "RIGHT", 6, 0)
    local function SetMain()
      local v = f.main:GetText()
      Call(function() sepgp_main = sepgp:verifyGuildMember(sepgp:camelCase(v or "")) end)
    end
    set:SetScript("OnClick", SetMain)
    f.main.onEnter = SetMain
    UI.Tip(set, "Set main", "The character whose EPGP you use (yourself if this is your main). Must be in the guild at raid level.")
    f.youNote = UI.Text(you, 10, C.dim)
    f.youNote:SetPoint("TOPLEFT", you, "TOPLEFT", 12, -118)
    f.youNote:SetWidth(236)
    f.youNote:SetJustifyH("LEFT")
    f.youNote:SetText("When an officer runs a standby check you get a popup: answer Yes within the time to get standby EP.")

    local off = UI.Card(f, "Officer", 260, PH - 204)
    off:SetPoint("TOPLEFT", you, "BOTTOMLEFT", 0, -8)
    f.offCard = off
    local afk = UI.Button(off, "Standby check", 236, 22)
    afk:SetPoint("TOPLEFT", off, "TOPLEFT", 12, -34)
    afk:SetScript("OnClick", function()
      UI.Confirm("Post a standby check in the standby channel? Everyone on standby gets " .. sepgp.VARS.timeout .. " seconds to answer.", function()
        Call(function() sepgp:afkcheck_reserves() end)
      end)
    end)
    UI.Tip(afk, "Standby check", "Asks everyone on standby to answer within the time; who answers is listed on the right.")
    Gate(f, afk, Admin)
    f.resAmount = AmountBox(off, 70, Suggested())
    f.resAmount:SetPoint("TOPLEFT", off, "TOPLEFT", 12, -66)
    local give = UI.Button(off, "+ EP to everyone listed", 160, 20)
    give:SetPoint("LEFT", f.resAmount, "RIGHT", 6, 0)
    give:SetScript("OnClick", function()
      local n = Amount(f.resAmount)
      if not n or n <= 0 or n >= MaxPoints() then UI.Print("type an amount from 1 to " .. (MaxPoints() - 1)) return end
      UI.Confirm(string.format("Give %d EP to the %d people on the standby list? The list is emptied afterwards.", n, table.getn(sepgp.reserves or {})), function()
        Call(function() sepgp:award_reserve_ep(n) end)
      end)
    end)
    UI.Tip(give, "Standby EP", "Gives the amount to everyone on the list (to their mains), posts it, logs it and empties the list.")
    Gate(f, give, function() return Admin() and table.getn(sepgp.reserves or {}) > 0 end)

    local cols = {
      { key = "name", label = "Name", width = 140, sort = "asc" },
      { key = "rank", label = "Rank", width = 110, sort = "asc" },
      { key = "alt", label = "Answered on", width = 100, sort = "asc" },
    }
    local nRows = math.floor((PH - 26 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -26)
    l:SetWidth(PW - 268)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "name", false
    l.emptyText = "Nobody on the standby list right now."
    l.onClick = function(r) ChatFrame_SendTell(r.data) end
    f.list = l
    f.cd = UI.Text(f, 12, C.gold)
    f.cd:SetPoint("TOPLEFT", l, "TOPLEFT", 0, 20)
  end,
  refresh = function(f)
    RunRefreshers(f)
    if not f.main.typing then f.main:SetText(sepgp_main or "") end
    -- who is on standby and the officer buttons: officers only
    if not UI.IsAdmin() then
      f.offCard:Hide()
      f.list:Hide()
      f.cd:Hide()
      return
    end
    f.offCard:Show()
    f.list:Show()
    f.cd:Show()
    local rows = {}
    local t = sepgp.reserves or {}
    for i = 1, table.getn(t) do
      local name, class, rank, alt = t[i][1], t[i][2], t[i][3], t[i][4]
      table.insert(rows, { id = name, data = alt or name,
        cells = { UI.ClassName(name, class), rank or "", alt or "" },
        sort = { name = name, rank = rank or "", alt = alt or "", tie = name } })
    end
    f.list:SetRows(rows, true)
    local cd = sepgp.timer and sepgp.timer.cd_text or ""
    f.cd:SetText("Standby list  " .. (cd ~= "" and UI.Paint(C.text, "- check running: " .. cd) or ""))
  end,
}

-- ================================================================== Alts

UI.Page{ key = "alts", label = "Alts", tip = "Which characters are alts of which mains (from {Main} in officer notes). Officers only.", admin = true,
  build = function(f)
    f.info = UI.Text(f, 11, C.dim)
    f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
    f.info:SetWidth(PW)
    f.info:SetJustifyH("LEFT")
    local cols = {
      { key = "main", label = "Main", width = 130, sort = "asc" },
      { key = "n", label = "Alts", width = 34, align = "RIGHT", sort = true },
      { key = "alts", label = "Alt characters", width = 460, sort = "asc" },
    }
    local nRows = math.floor((PH - 30 - 24) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "main", false
    l.emptyText = "No alts found. An officer marks an alt by putting {MainName} in the alt's officer note."
    f.list = l
  end,
  refresh = function(f)
    local rows = {}
    local list = UI.roster or {}
    for i = 1, table.getn(list) do
      local m = list[i]
      if m.alts then
        local names = {}
        for j = 1, table.getn(m.alts) do
          local a = UI.byName[m.alts[j]]
          table.insert(names, a and UI.ClassName(a.name, a.class) or m.alts[j])
        end
        table.insert(rows, { id = m.name, data = m,
          cells = { UI.ClassName(m.name, m.class), table.getn(m.alts), table.concat(names, ", ") },
          sort = { main = m.name, n = table.getn(m.alts), alts = m.alts[1] or "", tie = m.name } })
      end
    end
    f.list:SetRows(rows, true)
    f.info:SetText("Alts share their main's EPGP: " .. (sepgp_altspool and UI.Paint(C.on, "on") .. " - an alt earns " .. math.floor((sepgp_altpercent or 1) * 100 + 0.5) .. "% of the EP, all to the main." or UI.Paint(C.dim, "off - alts keep their own points.")))
  end,
}

-- ================================================================== Logs

UI.Page{ key = "logs", label = "EP / GP history", tip = "Every EP and GP award, penalty, decay and reset in the guild (newest first).",
  build = function(f)
    f.search = UI.EditBox(f, 200)
    f.search:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Hint(f.search, "Search name or event...")
    f.search.onChange = function() f.list:Filter() end
    -- officers: the addon's own log as it is, and its buttons
    f.rawT, f.rawL = ToggleRow(f, f, 214, -2, "Addon's own log", "Shows shootyepgp's own log lines on this character instead of the guild history.",
      function() return f.raw end, function(v) f.raw = v end)
    f.logBtns = Buttons(f, PW - 110, 0, {
      { "Clear log", 110, function()
          UI.Confirm("Clear this character's addon log? (" .. table.getn(sepgp_log or {}) .. " lines. The EP / GP history and officer notes are kept.)", function()
            Call(function() sepgp_log = {} sepgp_logs:Refresh() sepgp:defaultPrint("Logs cleared") end)
          end)
        end, "Empties the addon's own log. The guild history on this page and EP / GP are kept. A copy of the log as it was on 18 Oct 2026 is in the backup folder." },
    })
    local cols = {
      { key = "t", label = "When", width = 86, sort = true },
      { key = "who", label = "Who", width = 110, sort = "asc" },
      { key = "line", label = "What happened", width = 340, sort = "asc" },
      { key = "ep", label = "EP", width = 44, align = "RIGHT", sort = true },
      { key = "gp", label = "GP", width = 44, align = "RIGHT", sort = true },
    }
    local nRows = math.floor((PH - 30 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "t", true
    l.emptyText = "No history yet. Officers' copies are being asked - if one is online, the newest history arrives in a few seconds."
    l.filter = function(r)
      local q = f.search:GetText()
      if not q or q == "" then return true end
      return string.find(r.search, string.lower(q), 1, true) ~= nil
    end
    l.onEnter = function(r, line)
      GameTooltip:SetOwner(line, "ANCHOR_TOP")
      GameTooltip:AddLine(r.tip, 1, 1, 1, 1)
      if r.by then GameTooltip:AddLine("By " .. r.by, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end
    l.onClick = function(r)
      local w = r.data and r.data.w
      if w and UI.byName and UI.byName[w] then
        UI.Select("standings")
        local st = UI.pages.standings.frame
        st.sel = w
        st.list.selected = w
        UI.pages.standings.detail(st)
        UI.pages.standings.showHistory(st, true)
      end
    end
    f.list = l
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
  end,
  refresh = function(f)
    local admin = UI.IsAdmin()
    if not admin then f.raw = nil end
    for i = 1, 1 do if admin then f.logBtns[i]:Show() else f.logBtns[i]:Hide() end end
    if admin then f.rawT:Show() f.rawL:Show() else f.rawT:Hide() f.rawL:Hide() end
    RunRefreshers(f)
    local rows = {}
    if f.raw then
      local t = sepgp_log or {}
      for i = 1, table.getn(t) do
        local stamp, line = t[i][1], tostring(t[i][2] or "")
        table.insert(rows, { id = i, tip = line, search = string.lower(line),
          cells = { UI.Paint(C.dim, stamp or ""), "", line, "", "" },
          sort = { t = i, who = "", line = line, ep = 0, gp = 0, tie = i } })
      end
      f.list:SetRows(rows, true)
      f.count:SetText(table.getn(t) .. " addon log lines on this character (it keeps the newest " .. ((sepgp.VARS and sepgp.VARS.maxloglines) or 500) .. ")")
      return
    end
    UI.History.Seed()
    UI.History.Ask("*")
    local evs = UI.History.All({ E = 1, G = 1, D = 1, R = 1, Z = 1, U = 1 })
    for i = 1, table.getn(evs) do
      local e = evs[i]
      local what, ep, gp = UI.History.Describe(e)
      local m = UI.byName and e.w and UI.byName[e.w]
      local who = e.w and (m and UI.ClassName(e.w, m.class) or e.w) or UI.Paint(C.dim, "everyone")
      table.insert(rows, { id = i, data = e, tip = UI.History.Plain(what), by = e.by,
        search = string.lower((e.w or "everyone") .. " " .. UI.History.Plain(what)),
        cells = { UI.Paint(C.dim, UI.History.When(e.t)), who, what, ep, gp },
        sort = { t = e.t, who = e.w or "", line = e.k, ep = (e.k == "E") and e.n or 0, gp = (e.k == "G") and e.n or 0, tie = i } })
    end
    f.list:SetRows(rows, true)
    f.count:SetText(table.getn(rows) .. " events in the guild's EP / GP history  -  click a row for that player's history")
  end,
}

-- ================================================================== Strikes

UI.Page{ key = "strikes", label = "Strikes", tip = "Raid strikes officers gave out (the /strike panel's data). Officers only.", admin = true,
  build = function(f)
    f.info = UI.Text(f, 11, C.dim)
    f.info:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -4)
    local b = Buttons(f, PW - 150, 0, {
      { "Strike panel", 150, Slash("RAIDSTRIKE"), "Opens the strike panel (/strike): officers add or remove strikes for raid members there." },
    })
    local cols = {
      { key = "name", label = "Name", width = 160, sort = "asc" },
      { key = "n", label = "Strikes", width = 60, align = "RIGHT", sort = true },
      { key = "rank", label = "Rank", width = 120, sort = "asc" },
      { key = "raid", label = "In your raid", width = 90, sort = true },
    }
    local nRows = math.floor((PH - 30 - 24) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -28)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "n", true
    l.emptyText = "No strikes."
    f.list = l
  end,
  refresh = function(f)
    local rows = {}
    local db = type(RaidStrikeDB) == "table" and RaidStrikeDB or {}
    for name, n in pairs(db) do
      if type(n) == "number" and n > 0 then
        local m = UI.byName and UI.byName[name]
        table.insert(rows, { id = name, data = name,
          cells = { m and UI.ClassName(name, m.class) or name, UI.Paint(n >= 3 and C.red or C.text, n), m and m.rank or UI.Paint(C.dim, "not in guild"), (m and m.inRaid) and UI.Paint(C.on, "yes") or "" },
          sort = { name = name, n = n, rank = m and m.rankIndex or 99, raid = (m and m.inRaid) and 1 or 0, tie = name } })
      end
    end
    f.list:SetRows(rows, true)
    local reset = type(RaidStrikeResetTime) == "number" and RaidStrikeResetTime > 0 and date("%d %b %Y", RaidStrikeResetTime)
    f.info:SetText(table.getn(rows) .. " players with strikes" .. (reset and ("  -  last reset " .. reset) or ""))
  end,
}

-- ================================================================== Tools

local function ToolCard(f, x, y, title, text, buttons)
  local c = UI.Card(f, title, 326, 92)
  c:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  local t = UI.Text(c, 10, C.dim)
  t:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -30)
  t:SetWidth(302)
  t:SetJustifyH("LEFT")
  t:SetText(text)
  return c, Buttons(c, 12, -62, buttons)
end

UI.Page{ key = "tools", label = "Tools", tip = "The extra tools that come with this version of shootyepgp.", gap = true, admin = true,
  build = function(f)
    local R = 338
    ToolCard(f, 0, 0, "Bench tracker", "Who sits on the bench this raid, with a bench check for the guild website (/bench).",
      { { "Open", 90, Slash("BENCH"), "Opens the bench tracker." } })
    ToolCard(f, R, 0, "Gnarlmoon sides", "Puts raid members on the left or right side for Gnarlmoon and announces it (/matrix).",
      { { "Open", 90, Slash("MATRIX"), "Opens the side planner." } })
    ToolCard(f, 0, -100, "Raid strikes", "Strikes for naughty raiders, shared between officers (/strike). The list is in Strikes.",
      { { "Open", 90, Slash("RAIDSTRIKE"), "Opens the strike panel." },
        { "See list", 90, function() UI.Select("strikes") end, "The Strikes topic in this window." } })
    -- (profession sync is for everyone: it lives in Settings)
    ToolCard(f, 0, -300, "Troubleshooting", "If shootyepgp had trouble starting (no standings, no bids), restart it here or type /reload.",
      { { "Restart", 96, function() Call(function() sepgp:OnEnable() sepgp:defaultPrint("Restarted") end) end,
          "Restarts shootyepgp (the old /shooty restart)." } })
    local _, io = ToolCard(f, R, -100, "Export / import", "Standings as text to copy (Name;EP;GP;PR). Import writes officer notes: guild leader only.",
      { { "Export", 90, function() Call(function() sepgp_standings:Export() end) end, "Shows the standings to copy with Ctrl-C." },
        { "Import", 90, function()
            UI.Confirm("Open the import box? Pasted values OVERWRITE the officer notes of the names in them.", function()
              Call(function() sepgp_standings:Import() end)
            end)
          end, "Guild leader only: paste standings text to write EP and GP into officer notes." } })
    Gate(f, io[2], GL)
    ToolCard(f, 0, -200, "Snowball tracking", "Counts snowball hits for fun (/snowball switches it on or off).",
      { { "On / off", 90, Slash("SNOWBALL"), "Switches snowball tracking on or off (it says which in chat)." } })
    ToolCard(f, R, -200, "Item ID", "Type /parseid then Shift-click an item to see its item ID. GP prices also show on item tooltips.",
      {})
  end,
  refresh = function(f) RunRefreshers(f) end,
}

-- ================================================================== Settings

UI.Page{ key = "settings", label = "Settings", tip = "Your own shootyepgp settings and this window's look.",
  build = function(f)
    local cw = math.floor((PW - 8) / 2)
    local a = UI.Card(f, "Loot and bids", cw, 150)
    a:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    ToggleRow(f, a, 12, -36, "Loot sounds", "Plays a sound when loot is announced for bids.",
      function() return sepgp_sound == 1 end, function(v) sepgp_sound = v and 1 or 0 end)
    ToggleRow(f, a, 12, -64, "Standings: my raid only", "Standings show only your raid's members while you are in a raid.",
      function() return sepgp_raidonly end,
      function() sepgp_raidonly = not sepgp_raidonly if sepgp.SetRefresh then sepgp:SetRefresh(true) end end)
    ToggleRow(f, a, 12, -92, "Standby list", "Join the standby (reserves) channel. Set your main first (Standby topic).",
      function() return sepgp.reservesChannelID ~= nil and sepgp.reservesChannelID ~= 0 end,
      function(v) sepgp:reservesToggle(v) end,
      function() return sepgp_main == nil end)
    -- officers only: hidden for everyone else
    local bt, bl = ToggleRow(f, a, 12, -120, "Open bid window by itself", "Opens the bids window when loot is announced.",
      function() return sepgp_autobidwindow == 1 end, function(v) sepgp_autobidwindow = v and 1 or 0 end)
    table.insert(Refreshers(f), function()
      if UI.IsAdmin() then bt:Show() bl:Show() else bt:Hide() bl:Hide() end
    end)

    ToolCard(f, 0, -266, "Profession sync", "Shares which recipes you know with the guild website (/profsync).",
      { { "Status", 90, Slash("SHOOTYPROFSYNC", "status"), "Prints what has been synced so far." },
        { "Sync now", 90, Slash("SHOOTYPROFSYNC", ""), "Sends your professions to the guild again." } })

    local w = UI.Card(f, "This window", cw, 214)
    w:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    ToggleRow(f, w, 12, -36, "Minimap button", "The round button on the minimap that opens this window. /epgp opens it too.",
      function() return not UI.DB().minimapHide end,
      function(v) UI.DB().minimapHide = not v UI.Minimap.Update() end)
    UI.Label(w, "Window size", 12, -96)
    f.scale = UI.Slider(w, cw - 110)
    f.scale:SetPoint("TOPLEFT", w, "TOPLEFT", 96, -94)
    f.scale:SetMinMaxValues(0.7, 1.3)
    f.scale:SetValueStep(0.05)
    f.scaleText = UI.Text(w, 11, C.dim)
    f.scaleText:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -112)
    f.scale:SetScript("OnMouseUp", function()
      UI.DB().scale = math.floor(this:GetValue() * 20 + 0.5) / 20
      UI.frame:SetScale(UI.DB().scale)
    end)
    f.scale.onValue = function(v) f.scaleText:SetText(math.floor(v * 100 + 0.5) .. "%") end
    UI.Label(w, "Background", 12, -136)
    f.alpha = UI.Slider(w, cw - 110)
    f.alpha:SetPoint("TOPLEFT", w, "TOPLEFT", 96, -134)
    f.alpha:SetMinMaxValues(0.5, 1)
    f.alpha:SetValueStep(0.01)
    f.alphaText = UI.Text(w, 11, C.dim)
    f.alphaText:SetPoint("TOPRIGHT", w, "TOPRIGHT", -12, -152)
    f.alpha.onValue = function(v)
      UI.DB().alpha = v
      UI.frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], v)
      f.alphaText:SetText(math.floor(v * 100 + 0.5) .. "%")
    end
    local reset = UI.Button(w, "Reset window", 120, 20)
    reset:SetPoint("TOPLEFT", w, "TOPLEFT", 12, -180)
    reset:SetScript("OnClick", function()
      UI.DB().scale, UI.DB().alpha = 1, 0.97
      UI.frame:SetScale(1)
      UI.frame:ClearAllPoints()
      UI.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
      UI.frame:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.97)
      UI.RefreshPage()
    end)
    UI.Tip(reset, "Reset window", "Size 100%, background 97%, back in the middle of the screen.")

    local n = UI.Card(f, "Good to know", cw, 100)
    n:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -8)
    local t = UI.Text(n, 10, C.dim)
    t:SetPoint("TOPLEFT", n, "TOPLEFT", 12, -32)
    t:SetWidth(cw - 24)
    t:SetJustifyH("LEFT")
    t:SetText("Guild rules (decay, prices, minimum EP) are set by officers in the Officer topic. A chat window named \"debug\" catches shootyepgp's messages.")
  end,
  refresh = function(f)
    RunRefreshers(f)
    UI.SliderSet(f.scale, UI.DB().scale or 1)
    f.scaleText:SetText(math.floor((UI.DB().scale or 1) * 100 + 0.5) .. "%")
    UI.SliderSet(f.alpha, UI.DB().alpha or 0.97)
    f.alphaText:SetText(math.floor((UI.DB().alpha or 0.97) * 100 + 0.5) .. "%")
  end,
}

-- ================================================================== Officer

local TIERS = {
  { key = "T1", label = "T1 - Molten Core" }, { key = "T2", label = "T2 - Blackwing Lair" },
  { key = "T2.5", label = "T2.5 - Temple of Ahn'Qiraj" }, { key = "T3", label = "T3 - Naxxramas" },
  { key = "T3.5", label = "T3.5 - Tower of Karazhan" },
}
local CHANNELS = { { key = "PARTY", label = "Party" }, { key = "RAID", label = "Raid" }, { key = "GUILD", label = "Guild" }, { key = "OFFICER", label = "Officer" } }

-- the old menu shares these settings with the guild when the guild leader changes them
local function Share()
  if IsGuildLeader() then sepgp:shareSettings(true) end
end

UI.Page{ key = "officer", label = "Officer", tip = "EP awards, decay and the guild's EPGP rules. Click to unfold the officer tools (Quick EP / GP, Decay log, Addon check, Accounts), click again to fold them away. Officers only.", admin = true,
  build = function(f)
    local cw = math.floor((PW - 8) / 2)
    -- awards
    local a = UI.Card(f, "Award EP", cw, 152)
    a:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Label(a, "Whole raid", 12, -36)
    f.raidAmount = AmountBox(a, 64, Suggested())
    f.raidAmount:SetPoint("TOPLEFT", a, "TOPLEFT", 110, -33)
    local rb = UI.Button(a, "Give", 70, 20)
    rb:SetPoint("LEFT", f.raidAmount, "RIGHT", 6, 0)
    rb:SetScript("OnClick", function()
      local n = Amount(f.raidAmount)
      if not n or n <= -MaxPoints() or n >= MaxPoints() or n == 0 then UI.Print("type an amount between -" .. MaxPoints() .. " and " .. MaxPoints()) return end
      UI.Confirm(string.format("Give %d EP to all %d raid members?", n, GetNumRaidMembers()), function()
        Call(function() sepgp:award_raid_ep(n) end)
      end)
    end)
    UI.Tip(rb, "Raid EP", "Gives the amount to everyone in the raid (alts to their mains), posts it in the report channel and logs it. Blocked for 2 minutes after another officer's raid award.")
    UI.Label(a, "Standby list", 12, -66)
    f.resAmount = AmountBox(a, 64, Suggested())
    f.resAmount:SetPoint("TOPLEFT", a, "TOPLEFT", 110, -63)
    local sb = UI.Button(a, "Give", 70, 20)
    sb:SetPoint("LEFT", f.resAmount, "RIGHT", 6, 0)
    sb:SetScript("OnClick", function()
      local n = Amount(f.resAmount)
      if not n or n <= 0 or n >= MaxPoints() then UI.Print("type an amount from 1 to " .. (MaxPoints() - 1)) return end
      UI.Confirm(string.format("Give %d EP to the %d people on the standby list? The list is emptied afterwards.", n, table.getn(sepgp.reserves or {})), function()
        Call(function() sepgp:award_reserve_ep(n) end)
      end)
    end)
    UI.Tip(sb, "Standby EP", "Gives the amount to everyone who answered the standby check, then empties the list.")
    Gate(f, sb, function() return table.getn(sepgp.reserves or {}) > 0 end)
    local chk = UI.Button(a, "Standby check", 120, 20)
    chk:SetPoint("TOPLEFT", a, "TOPLEFT", 12, -96)
    chk:SetScript("OnClick", function()
      UI.Confirm("Post a standby check in the standby channel?", function() Call(function() sepgp:afkcheck_reserves() end) end)
    end)
    UI.Tip(chk, "Standby check", "Asks everyone on standby to answer; the answers fill the Standby list.")
    f.suggest = UI.Text(a, 10, C.dim)
    f.suggest:SetPoint("TOPLEFT", a, "TOPLEFT", 12, -126)
    f.suggest:SetWidth(cw - 24)
    f.suggest:SetJustifyH("LEFT")
    local tip = UI.Text(a, 10, C.dim)
    tip:SetPoint("LEFT", chk, "RIGHT", 8, 0)
    tip:SetText("One member: Standings, click a name.")

    -- alts
    local al = UI.Card(f, "Alts (guild leader)", cw, 100)
    al:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -8)
    ToggleRow(f, al, 12, -36, "Alts use main's EPGP", "An alt's EP and GP go to the main in its officer note ({Main}). Shared with the guild.",
      function() return sepgp_altspool end,
      function() sepgp_altspool = not sepgp_altspool Share() end,
      function() return not IsGuildLeader() end)
    UI.Label(al, "Alt EP share", 12, -70)
    f.altPct = UI.Slider(al, cw - 160)
    f.altPct:SetPoint("TOPLEFT", al, "TOPLEFT", 100, -68)
    f.altPct:SetMinMaxValues(0.5, 1)
    f.altPct:SetValueStep(0.05)
    f.altPctText = UI.Text(al, 11)
    f.altPctText:SetPoint("TOPRIGHT", al, "TOPRIGHT", -12, -70)
    -- the value is kept while dragging; it is sent to the guild on release
    f.altPct.onValue = function(v)
      sepgp_altpercent = math.floor(v * 20 + 0.5) / 20
      f.altPctText:SetText(math.floor(sepgp_altpercent * 100 + 0.5) .. "%")
    end
    f.altPct:SetScript("OnMouseUp", function() Call(Share) end)

    -- big actions
    local big = UI.Card(f, "Big actions", cw, PH - 152 - 100 - 16)
    big:SetPoint("TOPLEFT", al, "BOTTOMLEFT", 0, -8)
    local dec = UI.Button(big, "Decay EPGP now", 150, 22)
    dec:SetPoint("TOPLEFT", big, "TOPLEFT", 12, -34)
    dec:SetScript("OnClick", function()
      local pct = math.floor((1 - (sepgp_decay or 0.9)) * 100 + 0.5)
      local floor = tonumber(sepgp_minep) or 0
      -- a decay given twice by mistake: say when the last one was (22 Oct 2026)
      local warn = ""
      local last = UI.Decay and UI.Decay.Last()
      if last and time() - last.t < 6 * 86400 then
        warn = UI.Paint(C.red, "The last decay was only " .. UI.Decay.Ago(last.t) .. " ago (" .. date("%a %d %b %H:%M", last.t)
          .. " by " .. (last.by or "?") .. ").") .. "\n\n"
      end
      UI.Confirm(warn .. "Every member's EP and GP will be lowered by " .. pct .. "%.\n"
        .. (floor > 0 and ("Anyone at " .. floor .. " EP or more stops at " .. floor .. " EP.\n") or "")
        .. "GP never goes below " .. sepgp.VARS.basegp .. ". Every officer note is rewritten and the decay is posted to the guild.\n"
        .. "Everyone's EP and GP before and after go into Officer > Decay log, where it can be undone.",
        function() Call(function() sepgp:decay_epgp_v3() end) end,
        "Decay EPGP by " .. pct .. "%?", "Yes, decay now")
    end)
    UI.Tip(dec, "Decay", "Multiplies every member's EP and GP down by the decay %. Usually done once a week. Recorded in the Decay log.")
    local rs = UI.Button(big, "Reset all EPGP", 150, 22)
    rs:SetPoint("LEFT", dec, "RIGHT", 8, 0)
    rs:SetScript("OnClick", function()
      UI.Confirm("EVERY member's EP goes to 0 and GP to " .. sepgp.VARS.basegp .. ".\nAll points earned so far are wiped from the officer notes.\n"
        .. "This cannot be undone from the game (the 18 Oct backup holds a copy of the saved files).",
        function() Call(function() sepgp:gp_reset_v3() end) end,
        "|cffff5555Reset ALL EPGP?|r", "Yes, reset everyone")
    end)
    UI.Tip(rs, "Reset", "Guild leader only: sets EVERYONE to 0 EP and the starting GP. Asks first.")
    Gate(f, rs, GL)
    local lift = UI.Button(big, "Lift low EP to the minimum", 308, 22)
    lift:SetPoint("TOPLEFT", big, "TOPLEFT", 12, -64)
    lift:SetScript("OnClick", function()
      local floor = tonumber(sepgp_minep) or 0
      local low = UI.LowEP()
      if floor <= 0 then UI.Confirm("There is no minimum EP set, so there is nothing to lift to.", nil, "No minimum EP", "OK") return end
      if table.getn(low) == 0 then UI.Confirm("Nobody has between 1 and " .. (floor - 1) .. " EP.", nil, "Nothing to lift", "OK") return end
      local names = {}
      for k = 1, math.min(8, table.getn(low)) do table.insert(names, low[k][2] .. " (" .. low[k][4] .. ")") end
      if table.getn(low) > 8 then table.insert(names, "and " .. (table.getn(low) - 8) .. " more") end
      UI.Confirm(string.format("%d members with 1-%d EP will be raised to %d EP:\n%s\n\nTheir officer notes are rewritten; officers are told and it is logged.",
          table.getn(low), floor - 1, floor, table.concat(names, ", ")),
        function() Call(UI.LiftLowEP) end, "Lift low EP to " .. floor .. "?", "Yes, lift them")
    end)
    UI.Tip(lift, "Lift low EP", "Everyone with EP between 1 and the minimum EP (the red rows in Standings) is raised to the minimum. Members with 0 EP are left alone. Asks first.")
    f.liftBtn = lift
    local dlog = UI.Button(big, "Decay log  -  check or undo a decay", 308, 22)
    dlog:SetPoint("TOPLEFT", big, "TOPLEFT", 12, -94)
    dlog:SetScript("OnClick", function() UI.Select("decay") end)
    UI.Tip(dlog, "Decay log", "Every decay with everyone's EP and GP before and after, whether the officer notes really changed, and Undo for the latest one.")
    f.decayLogBtn = dlog
    local note = UI.Text(big, 10, C.dim)
    note:SetPoint("TOPLEFT", big, "TOPLEFT", 12, -126)
    note:SetWidth(cw - 24)
    note:SetJustifyH("LEFT")
    note:SetText("Decay never takes anyone from the minimum EP or above to below it, and new members start at the minimum EP. "
      .. "EP and GP live in the officer notes as {EP:GP}. Every button here asks first.")

    -- rules
    local r = UI.Card(f, "Guild rules", cw, PH)
    r:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    UI.Label(r, "Raid progress", 12, -36)
    f.tier = UI.Dropdown(r, 190, TIERS, function() return sepgp_progress end, function(k)
      Call(function() sepgp_progress = k sepgp:refreshPRTablets() Share() end)
    end)
    f.tier:SetPoint("TOPRIGHT", r, "TOPRIGHT", -12, -33)
    UI.Tip(f.tier, "Raid progress", "The highest tier the guild raids. GP prices of older tiers are scaled down and EP suggestions follow it.")
    UI.Label(r, "Report channel", 12, -68)
    f.chan = UI.Dropdown(r, 190, CHANNELS, function() return sepgp_saychannel end, function(k)
      Call(function() sepgp_saychannel = k end)
    end)
    f.chan:SetPoint("TOPRIGHT", r, "TOPRIGHT", -12, -65)
    UI.Tip(f.chan, "Report channel", "Where award and decay messages are posted.")

    UI.Label(r, "Minimum EP", 12, -100)
    f.minep = AmountBox(r, 70, sepgp_minep)
    f.minep:SetPoint("TOPRIGHT", r, "TOPRIGHT", -78, -97)
    local ms = UI.Button(r, "Set", 60, 20)
    ms:SetPoint("LEFT", f.minep, "RIGHT", 6, 0)
    local function SetMin()
      local n = Amount(f.minep)
      if not n or n < 0 or n > MaxPoints() then UI.Print("minimum EP must be 0 to " .. MaxPoints()) return end
      Call(function() sepgp_minep = n sepgp:refreshPRTablets() Share() end)
    end
    ms:SetScript("OnClick", SetMin)
    f.minep.onEnter = SetMin
    UI.Tip(ms, "Minimum EP", "Members below it are listed after everyone above it in standings and bids. 0 = no minimum.")

    UI.Label(r, "Decay per run", 12, -134)
    f.decay = UI.Slider(r, cw - 170)
    f.decay:SetPoint("TOPLEFT", r, "TOPLEFT", 110, -132)
    f.decay:SetMinMaxValues(0.01, 0.5)
    f.decay:SetValueStep(0.01)
    f.decayText = UI.Text(r, 11)
    f.decayText:SetPoint("TOPRIGHT", r, "TOPRIGHT", -12, -134)
    f.decay.onValue = function(v)
      v = math.floor(v * 100 + 0.5) / 100
      sepgp_decay = 1 - v
      f.decayText:SetText(math.floor(v * 100 + 0.5) .. "%")
    end
    f.decay:SetScript("OnMouseUp", function() Call(Share) end)

    -- offspec price, one per tier (guild leader, 29 Oct 2026: MC 25%, BWL 40%, ...)
    local oh = UI.Text(r, 12, C.gold)
    oh:SetPoint("TOPLEFT", r, "TOPLEFT", 12, -170)
    oh:SetText("Offspec price per tier")
    f.osp = {}
    local tiers = UI.Prices.TIERS
    for i = 1, table.getn(tiers) do
      local tier, y = tiers[i].key, -194 - (i - 1) * 26
      local lab = UI.Text(r, 11)
      lab:SetPoint("TOPLEFT", r, "TOPLEFT", 12, y)
      lab:SetWidth(150)
      lab:SetJustifyH("LEFT")
      lab:SetText(tiers[i].label)
      local s = UI.Slider(r, cw - 230)
      s:SetPoint("TOPLEFT", r, "TOPLEFT", 168, y + 2)
      s:SetMinMaxValues(0, 1)
      s:SetValueStep(0.05)
      s.tier = tier
      s.text = UI.Text(r, 11)
      s.text:SetPoint("TOPRIGHT", r, "TOPRIGHT", -12, y)
      s.onValue = function(v)
        UI.Prices.SetRate(tier, math.floor(v * 20 + 0.5) / 20)
        s.text:SetText(math.floor(UI.Prices.Rate(tier) * 100 + 0.5) .. "%")
      end
      s:SetScript("OnMouseUp", function() Call(Share) end)
      UI.Tip(s, "Offspec price - " .. tiers[i].label, "Offspec bids on this tier's items cost this share of the mainspec GP.")
      f.osp[i] = s
    end

    f.rulesNote = UI.Text(r, 10, C.dim)
    f.rulesNote:SetPoint("TOPLEFT", r, "TOPLEFT", 12, -194 - table.getn(tiers) * 26 - 8)
    f.rulesNote:SetWidth(cw - 24)
    f.rulesNote:SetJustifyH("LEFT")
  end,
  refresh = function(f)
    RunRefreshers(f)
    f.tier.Refresh()
    f.chan.Refresh()
    if not f.minep.typing then f.minep:SetText(tostring(sepgp_minep or 0)) end
    for i = 1, table.getn(f.osp) do
      local s = f.osp[i]
      UI.SliderSet(s, UI.Prices.Rate(s.tier))
      s.text:SetText(math.floor(UI.Prices.Rate(s.tier) * 100 + 0.5) .. "%")
    end
    UI.SliderSet(f.decay, 1 - (sepgp_decay or 0.9))
    f.decayText:SetText(math.floor((1 - (sepgp_decay or 0.9)) * 100 + 0.5) .. "%")
    UI.SliderSet(f.altPct, sepgp_altpercent or 1)
    f.altPctText:SetText(math.floor((sepgp_altpercent or 1) * 100 + 0.5) .. "%")
    f.suggest:SetText("Suggested award here: " .. Suggested() .. " EP (base " .. sepgp.VARS.baseaward_ep .. ", scaled by zone and raid progress).")
    if IsGuildLeader() then
      f.rulesNote:SetText("You are the guild leader: rule changes are sent to everyone's shootyepgp.")
    else
      f.rulesNote:SetText("Only the guild leader's changes are sent to the guild. Yours change this character only and are replaced when the guild leader's settings arrive.")
    end
  end,
}
