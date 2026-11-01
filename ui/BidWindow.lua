-- shootyepgp :: new window, part 12 - the officers' bid window
-- A small window of its own for the item up for bids, made for the loot
-- master to read at a glance (guild leader, 29 Oct 2026):
--   the item (icon, name with tooltip / shift-click link, MS and OS GP),
--   Countdown and Attention (loot master), the live countdown,
--   three coloured bands - Mainspec, Offspec (best PR first) and
--   Transmog / Mounts / Bags (/roll 69, highest roll first) - with a count badge,
--   striped bidder rows: click one to announce the winner (asks first).
-- Data: sepgp.bids_main / bids_off / bids_xmog as the officers' copies hear them.
-- It opens by itself when bids come in (sepgp_bids:Toggle(true), legacy.lua) and
-- grows and shrinks with its lists. "Full bids page" opens the window's Bids topic.
--
-- Where it sits, its size and whether it is locked: Settings > Pop-up windows
-- (UI.Place, ui\BidPopup.lua), with a test window filled with sample bids.

local UI = SEPGP_UI
local C = UI.C
local BW = {}
UI.BidWindow = BW

local W = 400
local MAX_ROWS = 8        -- per band; more are counted, the full bids page has them all
local ROW_H = 20
local QHEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local SECTIONS = {
  { key = "bids_main", title = "MAINSPEC", col = C.accent, kind = "MS" },
  { key = "bids_off", title = "OFFSPEC", col = C.on, kind = "OS" },
  { key = "bids_xmog", title = "TRANSMOG / MOUNTS / BAGS", col = C.gold, kind = "XMOG", roll = true },
}
local SAMPLE = {
  item = "|cffff8000|Hitem:19019:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
  itemString = "item:19019:0:0:0",
  bids_main = { { "Testwarrior", "Warrior", 2400, 600, 4.0, "", "" }, { "Testrogue", "Rogue", 1800, 600, 3.0, "", "" } },
  bids_off = { { "Testpaladin", "Paladin", 2000, 800, 2.5, "", "" }, { "Testhunter", "Hunter", 900, 450, 2.0, "Testmain", "" } },
  bids_xmog = { { "Testmage", "Mage", 1200, 400, 3.0, "", "XMOG", 41 }, { "Testpriest", "Priest", 800, 400, 2.0, "", "XMOG", 63 } },
}

local function Practice() return UI.LootPractice and UI.LootPractice.on end
local function ML() return Practice() or (sepgp and sepgp.lootMaster and sepgp:lootMaster()) end

local function Source()
  if BW.test then return SAMPLE end
  if Practice() then return UI.LootPractice.data end
  return sepgp or {}
end

-- the item up for bids: full link (name), item string, id
local function Item()
  if BW.test then return SAMPLE.item, SAMPLE.itemString, 19019 end
  local it = Practice() and UI.LootPractice.data.bid_item or (sepgp and sepgp.bid_item)
  if not it or not it.link then return nil end
  local _, _, id = string.find(it.link, "item:(%d+)")
  return it.linkFull or it.name or it.link, it.link, tonumber(id)
end

-- bids: at / above minimum EP, then PR (the addon's order); rolls: highest roll first
local function Sorted(bids, byRoll)
  local minep = sepgp_minep or 0
  local list = {}
  for i = 1, table.getn(bids or {}) do table.insert(list, bids[i]) end
  table.sort(list, function(a, b)
    if byRoll then return (tonumber(a[8]) or -1) > (tonumber(b[8]) or -1) end
    local ab, bb = minep > 0 and (tonumber(a[3]) or 0) < minep, minep > 0 and (tonumber(b[3]) or 0) < minep
    if ab ~= bb then return bb end
    return (tonumber(a[5]) or 0) > (tonumber(b[5]) or 0)
  end)
  return list
end

-- ------------------------------------------------------------------ announcing

-- the winner in raid chat, as the full Bids page does (asks first)
function UI.AnnounceBid(kind, name, pr, roll)
  if not UI.IsAdmin() or not name then return end
  local what = (kind == "MS" and "mainspec") or (kind == "OS" and "offspec") or "transmog / mounts / bags"
  local detail = (kind == "XMOG") and ("rolled " .. tostring(roll or "-")) or string.format("%.3f PR", pr or 0)
  UI.Confirm(string.format("Announce %s as the %s winner (%s)?", name, what, detail), function()
    if Practice() then UI.LootPractice.Announce(kind, name, pr, roll) return end
    UI.Call(function()
      if BW.test then UI.Print("test window: this would announce " .. name .. " (" .. what .. ")") return end
      if kind == "MS" then sepgp_bids:announceWinnerMS(name, pr or 0)
      elseif kind == "OS" then sepgp_bids:announceWinnerOS(name, pr or 0)
      else sepgp:widestAudience(string.format("Winning Transmog / Mounts / Bags roll: %s (rolled %s)", name, tostring(roll or "-"))) end
    end)
  end, "Announce the winner?", "Yes, announce")
end

-- ------------------------------------------------------------------ building

local function Row(d, sec)
  local r = CreateFrame("Button", nil, d)
  r:SetHeight(ROW_H)
  r:SetWidth(W - 24)
  r.bg = UI.Fill(r, C.card, 1)
  r.bg:SetAllPoints(r)
  r.top = UI.Fill(r, sec.col, 0.14, "BORDER")
  r.top:SetAllPoints(r)
  local edge = UI.Fill(r, sec.col, 0.6, "ARTWORK")
  edge:SetWidth(2)
  edge:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
  edge:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
  UI.Hover(r, 0.1)
  r.pos = UI.Text(r, 10, C.dim)
  r.pos:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.pos:SetWidth(16)
  r.pos:SetJustifyH("RIGHT")
  r.name = UI.Text(r, 12)
  r.name:SetPoint("LEFT", r, "LEFT", 30, 0)
  r.name:SetWidth(190)
  r.name:SetJustifyH("LEFT")
  r.a = UI.Text(r, 13, C.gold)
  r.a:SetPoint("RIGHT", r, "RIGHT", -92, 0)
  r.a:SetWidth(60)
  r.a:SetJustifyH("RIGHT")
  r.b = UI.Text(r, 10, C.dim)
  r.b:SetPoint("RIGHT", r, "RIGHT", -8, 0)
  r.b:SetWidth(80)
  r.b:SetJustifyH("RIGHT")
  r:SetScript("OnClick", function()
    local b = this.bid
    if b then UI.AnnounceBid(this.kind, b[1], tonumber(b[5]), b[8]) end
  end)
  r:SetScript("OnEnter", function()
    local b = this.bid
    if not b then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine(UI.ClassName(b[1], b[2]))
    if b[6] and b[6] ~= "" then GameTooltip:AddLine("alt of " .. b[6] .. " (main's EPGP)", 0.6, 0.6, 0.6) end
    GameTooltip:AddLine("EP " .. UI.Fmt(tonumber(b[3])) .. "   GP " .. UI.Fmt(tonumber(b[4])) .. "   PR " .. UI.FmtPR(tonumber(b[5])), 1, 1, 1)
    if b[8] then GameTooltip:AddLine("Rolled " .. b[8] .. " (1-69)", 1, 0.78, 0.25) end
    if UI.IsAdmin() then GameTooltip:AddLine("Click: announce as the winner", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r.kind = sec.kind
  return r
end

local function Band(d, sec)
  local b = { rows = {} }
  b.head = CreateFrame("Frame", nil, d)
  b.head:SetHeight(24)
  b.head:SetWidth(W - 24)
  local fill = UI.Fill(b.head, sec.col, 0.22)
  fill:SetAllPoints(b.head)
  local bar = UI.Fill(b.head, sec.col, 1, "ARTWORK")
  bar:SetWidth(4)
  bar:SetPoint("TOPLEFT", b.head, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", b.head, "BOTTOMLEFT", 0, 0)
  b.title = UI.Text(b.head, 12, { 1, 1, 1 })
  b.title:SetPoint("LEFT", b.head, "LEFT", 12, 0)
  b.title:SetText(sec.title)
  -- the count badge
  b.badge = CreateFrame("Frame", nil, b.head)
  b.badge:SetWidth(24)
  b.badge:SetHeight(16)
  b.badge:SetPoint("LEFT", b.title, "RIGHT", 8, 0)
  local bf = UI.Fill(b.badge, sec.col, 0.95)
  bf:SetAllPoints(b.badge)
  b.count = UI.Text(b.badge, 11, { 0.05, 0.05, 0.06 })
  b.count:SetPoint("CENTER", b.badge, "CENTER", 0, 0)
  b.cols = UI.Text(b.head, 10, { 0.85, 0.85, 0.88 })
  b.cols:SetPoint("RIGHT", b.head, "RIGHT", -8, 0)
  b.cols:SetText(sec.roll and "ROLL              PR" or "PR           EP / GP")
  b.empty = UI.Text(d, 11, C.dim)
  for i = 1, MAX_ROWS do b.rows[i] = Row(d, sec) end
  b.more = UI.Text(d, 10, C.dim)
  return b
end

local function Build()
  local PR = UI.Prices
  local d = CreateFrame("Frame", "SepgpUIBidWindow", UIParent)
  d:SetWidth(W)
  d:SetHeight(300)
  d:SetFrameStrata("HIGH")
  d:SetToplevel(true)
  UI.Place.Attach(d, "officer", 420, 60)
  UI.Flat(d, C.bg, 0.97, C.accent)
  -- title bar
  local bar = UI.Fill(d, C.head, 1, "BORDER")
  bar:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -1)
  bar:SetHeight(28)
  local gavel = d:CreateTexture(nil, "ARTWORK")
  gavel:SetTexture("Interface\\Icons\\INV_Hammer_05")
  gavel:SetWidth(18)
  gavel:SetHeight(18)
  gavel:SetPoint("TOPLEFT", d, "TOPLEFT", 8, -6)
  gavel:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.title = UI.Text(d, 14, C.gold)
  d.title:SetPoint("LEFT", gavel, "RIGHT", 8, 0)
  local close = UI.Button(d, "X", 22, 20)
  close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -5, -5)
  close:SetScript("OnClick", function() d:Hide() end)
  d.counter = UI.Text(d, 16)
  d.counter:SetPoint("RIGHT", close, "LEFT", -10, 0)

  -- the item
  local card = CreateFrame("Frame", nil, d)
  card:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -36)
  card:SetWidth(W - 24)
  card:SetHeight(54)
  UI.Flat(card, C.card, 1, C.line)
  d.iconEdge = CreateFrame("Frame", nil, card)
  d.iconEdge:SetWidth(42)
  d.iconEdge:SetHeight(42)
  d.iconEdge:SetPoint("LEFT", card, "LEFT", 6, 0)
  UI.Flat(d.iconEdge, C.field, 1, C.line)
  local ib = CreateFrame("Button", nil, d.iconEdge)
  ib:SetPoint("TOPLEFT", d.iconEdge, "TOPLEFT", 2, -2)
  ib:SetPoint("BOTTOMRIGHT", d.iconEdge, "BOTTOMRIGHT", -2, 2)
  d.icon = ib:CreateTexture(nil, "ARTWORK")
  d.icon:SetAllPoints(ib)
  d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local nb = CreateFrame("Button", nil, card)
  nb:SetPoint("TOPLEFT", d.iconEdge, "TOPRIGHT", 10, -3)
  nb:SetWidth(W - 90)
  nb:SetHeight(18)
  d.item = UI.Text(nb, 14)
  d.item:SetAllPoints(nb)
  d.item:SetJustifyH("LEFT")
  local function Tip()
    local _, s = Item()
    if not s then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(s)
    GameTooltip:Show()
  end
  for _, h in ipairs({ ib, nb }) do
    h:SetScript("OnEnter", Tip)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    h:SetScript("OnClick", function()
      local link = Item()
      if link and IsShiftKeyDown() and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then ChatFrameEditBox:Insert(link) end
    end)
  end
  d.cost = UI.Text(card, 11, C.dim)
  d.cost:SetPoint("TOPLEFT", nb, "BOTTOMLEFT", 0, -6)

  -- loot master: countdown, attention; everyone: full page
  local function B(label, w, fn, tip)
    local b = UI.Button(d, label, w, 24)
    b:SetScript("OnClick", fn)
    UI.Tip(b, label, tip)
    return b
  end
  d.countdown = B("Countdown", 116, function()
    if BW.test then UI.Print("test window: this would count 5 to 1 in raid chat") return end
    if Practice() then UI.LootPractice.Countdown() return end
    UI.Call(function() sepgp_bids:bidCountdown() end)
  end, "Loot master: counts 5 to 1 in raid chat, then bidding is finished.")
  d.countdown:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -8)
  d.countdown:SetBackdropBorderColor(C.gold[1], C.gold[2], C.gold[3], 1)
  d.attention = B("Attention", 116, function()
    if BW.test or Practice() then UI.Print("practice / test: this would ping the officers' bid windows") return end
    UI.Call(function() sepgp_bids:sendAttention() end)
  end, "Loot master: pings the officers' bid windows.")
  d.attention:SetPoint("LEFT", d.countdown, "RIGHT", 6, 0)
  d.full = B("Full bids page", 128, function() UI.Open("bids") end, "Opens the Bids topic in the main window.")
  d.full:SetPoint("LEFT", d.attention, "RIGHT", 6, 0)
  d.stop = B("Stop practice", 128, function() UI.LootPractice.Stop() end, "Ends the practice hand-out. Nothing was sent or written.")
  d.stop:SetPoint("LEFT", d.attention, "RIGHT", 6, 0)
  d.stop:SetBackdropBorderColor(1, 0.78, 0.25, 1)

  d.bands = {}
  for s = 1, table.getn(SECTIONS) do d.bands[s] = Band(d, SECTIONS[s]) end
  d.hint = UI.Text(d, 10, C.dim)
  d.hint:SetWidth(W - 28)
  d.hint:SetJustifyH("LEFT")
  d.elapsed = 0
  d:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 0.5 then return end
    this.elapsed = 0
    BW.Draw()
  end)
  d:Hide()
  BW.frame = d
  BW.PR = PR
  return d
end

local function At(obj, d, x, y)
  obj:ClearAllPoints()
  obj:SetPoint("TOPLEFT", d, "TOPLEFT", x, y)
end

-- ------------------------------------------------------------------ drawing

function BW.Draw()
  local d = BW.frame
  if not d or not d:IsShown() then return end
  local src = Source()
  local link, itemString, id = Item()
  local practice = Practice() and not BW.test
  d.title:SetText((BW.test and "Bids  (test window)") or (practice and "|cffffc840PRACTICE|r  Bids") or "Bids")
  d.counter:SetText((BW.test and "") or (practice and (UI.LootPractice.counter or "")) or ((sepgp_bids and sepgp_bids._counterText) or ""))
  if practice then d.full:Hide() d.stop:Show() else d.stop:Hide() d.full:Show() end
  d:SetBackdropBorderColor(practice and 1 or C.accent[1], practice and 0.78 or C.accent[2], practice and 0.25 or C.accent[3], 1)
  if id then
    local _, q, tex = UI.Prices.Info(id)
    d.icon:SetTexture(tex)
    local hx = QHEX[q] or "ffffff"
    d.iconEdge:SetBackdropBorderColor(tonumber(string.sub(hx, 1, 2), 16) / 255, tonumber(string.sub(hx, 3, 4), 16) / 255, tonumber(string.sub(hx, 5, 6), 16) / 255, 1)
    d.item:SetText(link and string.gsub(link, "|H.-|h(.-)|h", "%1") or UI.Prices.Colored(id))
  else
    d.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    d.iconEdge:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
    d.item:SetText(UI.Paint(C.dim, "No item up for bids"))
  end
  local ok, osPrice, price = false, nil, nil
  if itemString and sepgp_prices and sepgp_prices.GetOffspec then ok, osPrice, price = pcall(sepgp_prices.GetOffspec, sepgp_prices, itemString, sepgp_progress) end
  if ok and price then
    d.cost:SetText(UI.Paint(C.accent, "Mainspec ") .. UI.Paint(C.text, price .. " GP") .. "      " .. UI.Paint(C.on, "Offspec ") .. UI.Paint(C.text, osPrice .. " GP"))
  else
    d.cost:SetText(id and "No GP price set" or "Opens by itself when the loot master calls for bids")
  end
  local ml = ML() or BW.test
  UI.Enable(d.countdown, ml and true or false)
  UI.Enable(d.attention, ml and true or false)

  -- the bands, one under the other
  local y = -128
  for s = 1, table.getn(SECTIONS) do
    local sec, b = SECTIONS[s], d.bands[s]
    local list = Sorted(src[sec.key], sec.roll)
    local n = table.getn(list)
    At(b.head, d, 12, y)
    b.count:SetText(tostring(n))
    y = y - 26
    for r = 1, MAX_ROWS do
      local row, bid = b.rows[r], list[r]
      if bid then
        At(row, d, 12, y)
        row.bid = bid
        row.bg:SetVertexColor((math.mod(r, 2) == 0) and C.panel[1] or C.card[1], (math.mod(r, 2) == 0) and C.panel[2] or C.card[2], (math.mod(r, 2) == 0) and C.panel[3] or C.card[3], 1)
        if r == 1 then row.top:Show() else row.top:Hide() end
        row.pos:SetText(r .. ".")
        local label = UI.ClassName(bid[1], bid[2])
        if bid[6] and bid[6] ~= "" then label = label .. UI.Paint(C.dim, "  (" .. bid[6] .. ")") end
        row.name:SetText(label)
        if sec.roll then
          row.a:SetText(bid[8] and tostring(bid[8]) or UI.Paint(C.dim, "-"))
          row.b:SetText(UI.FmtPR(tonumber(bid[5])))
        else
          row.a:SetText(UI.FmtPR(tonumber(bid[5])))
          row.b:SetText(UI.Fmt(tonumber(bid[3])) .. " / " .. UI.Fmt(tonumber(bid[4])))
        end
        row:Show()
        y = y - ROW_H - 1
      else
        row.bid = nil
        row:Hide()
      end
    end
    if n == 0 then
      At(b.empty, d, 24, y - 3)
      b.empty:SetText(sec.roll and ("Nobody rolled yet  (/roll " .. ((UI.BidPopup and UI.BidPopup.ROLL_MAX) or 69) .. ")") or "No bids yet")
      b.empty:Show()
      y = y - 20
    else
      b.empty:Hide()
    end
    if n > MAX_ROWS then
      At(b.more, d, 24, y - 2)
      b.more:SetText("and " .. (n - MAX_ROWS) .. " more on the full bids page")
      b.more:Show()
      y = y - 16
    else
      b.more:Hide()
    end
    y = y - 8
  end
  At(d.hint, d, 14, y - 2)
  if practice then
    d.hint:SetText(UI.Paint(C.gold, "PRACTICE - only on your screen.  ") .. (UI.LootPractice.given or "Bid on the pop-up, count down, click the winner."))
  elseif BW.test then
    d.hint:SetText(UI.Place.DB("officer").locked and "Locked - unlock it in Settings to move it" or "Drag it where you want it, then lock it in Settings")
  else
    d.hint:SetText("Click a bidder to announce the winner.  Shift-click the item to link it.")
  end
  d:SetHeight(-y + 22)
end

-- officers only; test = sample bids, to place it
function BW.Open(test)
  if not UI.IsAdmin() then return end
  local d = BW.frame or Build()
  BW.test = test and true or nil
  UI.Place.Apply(d)
  d:Show()
  BW.Draw()
end

function BW.Test() BW.Open(true) end
function BW.Frame() return BW.frame or Build() end
