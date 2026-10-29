-- shootyepgp :: new window, part 12 - the officers' bid window
-- A small window of its own for the item up for bids: everyone who bid
-- mainspec, offspec, or rolled transmog, best PR first, as the officers'
-- copies hear them (sepgp.bids_main / bids_off / bids_xmog). It opens by
-- itself when bids come in (the addon's sepgp_bids:Toggle(true), Settings >
-- "Open bid window by itself"); "Full bids page" opens the window's Bids topic
-- to announce a winner.
--
-- Where it sits, its size and whether it is locked: Settings > Pop-up windows
-- (UI.Place, ui\BidPopup.lua), with a test window filled with sample bids.

local UI = SEPGP_UI
local C = UI.C
local BW = {}
UI.BidWindow = BW

local W = 340
local ROWS = 5
local ROW_H = 16
local SECTIONS = {
  { key = "bids_main", title = "Mainspec", col = C.accent },
  { key = "bids_off", title = "Offspec", col = C.on },
  { key = "bids_xmog", title = "Transmog rolls", col = C.gold },
}
local SAMPLE = {
  item = "|cffff8000|Hitem:19019:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
  bids_main = { { "Testwarrior", "Warrior", 2400, 600, 4.0, "", "" }, { "Testrogue", "Rogue", 1800, 600, 3.0, "", "" } },
  bids_off = { { "Testpaladin", "Paladin", 2000, 800, 2.5, "", "OSPRIO" }, { "Testhunter", "Hunter", 900, 450, 2.0, "Testmain", "" } },
  bids_xmog = { { "Testmage", "Mage", 1200, 400, 3.0, "", "XMOG" } },
}

local function Source()
  if BW.test then return SAMPLE end
  return sepgp or {}
end

-- best first, as the addon orders bids: at / above minimum EP, then PR
local function Sorted(bids)
  local minep = sepgp_minep or 0
  local list = {}
  for i = 1, table.getn(bids or {}) do table.insert(list, bids[i]) end
  table.sort(list, function(a, b)
    local ab, bb = minep > 0 and (tonumber(a[3]) or 0) < minep, minep > 0 and (tonumber(b[3]) or 0) < minep
    if ab ~= bb then return bb end
    return (tonumber(a[5]) or 0) > (tonumber(b[5]) or 0)
  end)
  return list
end

local function Build()
  local d = CreateFrame("Frame", "SepgpUIBidWindow", UIParent)
  d:SetWidth(W)
  d:SetHeight(60 + table.getn(SECTIONS) * (20 + ROWS * ROW_H + 8) + 30)
  d:SetFrameStrata("HIGH")
  d:SetToplevel(true)
  UI.Place.Attach(d, "officer", 420, 60)
  UI.Flat(d, C.bg, 0.97, C.lineHi)
  local bar = UI.Fill(d, C.head, 1, "BORDER")
  bar:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -1)
  bar:SetHeight(24)
  d.title = UI.Text(d, 12, C.gold)
  d.title:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -6)
  local close = UI.Button(d, "X", 20, 18)
  close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -3)
  close:SetScript("OnClick", function() d:Hide() end)
  d.item = UI.Text(d, 12)
  d.item:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -32)
  d.item:SetWidth(W - 20)
  d.item:SetJustifyH("LEFT")
  d.cost = UI.Text(d, 10, C.dim)
  d.cost:SetPoint("TOPLEFT", d.item, "BOTTOMLEFT", 0, -3)
  d.sections = {}
  local y = -62
  for s = 1, table.getn(SECTIONS) do
    local sec = SECTIONS[s]
    local h = UI.Text(d, 11, sec.col)
    h:SetPoint("TOPLEFT", d, "TOPLEFT", 10, y)
    local cnt = UI.Text(d, 10, C.dim)
    cnt:SetPoint("LEFT", h, "RIGHT", 6, 0)
    local hh = UI.Text(d, 10, C.dim)
    hh:SetPoint("TOPRIGHT", d, "TOPRIGHT", -12, y)
    hh:SetText("PR        EP / GP")
    local lines = {}
    for r = 1, ROWS do
      local ly = y - 16 - (r - 1) * ROW_H
      local ln = {}
      ln.name = UI.Text(d, 11)
      ln.name:SetPoint("TOPLEFT", d, "TOPLEFT", 16, ly)
      ln.name:SetWidth(170)
      ln.name:SetJustifyH("LEFT")
      ln.pr = UI.Text(d, 11, C.gold)
      ln.pr:SetPoint("TOPRIGHT", d, "TOPRIGHT", -96, ly)
      ln.epgp = UI.Text(d, 10, C.dim)
      ln.epgp:SetPoint("TOPRIGHT", d, "TOPRIGHT", -12, ly)
      lines[r] = ln
    end
    local empty = UI.Text(d, 10, C.dim)
    empty:SetPoint("TOPLEFT", d, "TOPLEFT", 16, y - 16)
    d.sections[s] = { head = h, count = cnt, lines = lines, empty = empty, more = UI.Text(d, 10, C.dim) }
    d.sections[s].more:SetPoint("TOPLEFT", d, "TOPLEFT", 16, y - 16 - ROWS * ROW_H)
    h:SetText(sec.title)
    y = y - (20 + ROWS * ROW_H + 8)
  end
  local full = UI.Button(d, "Full bids page", 120, 20)
  full:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 10, 8)
  full:SetScript("OnClick", function() UI.Open("bids") end)
  UI.Tip(full, "Full bids page", "Opens the Bids topic: click a bidder there to announce the winner.")
  d.hint = UI.Text(d, 10, C.gold)
  d.hint:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -12, 12)
  d.elapsed = 0
  d:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 0.5 then return end
    this.elapsed = 0
    BW.Draw()
  end)
  d:Hide()
  BW.frame = d
  return d
end

function BW.Draw()
  local d = BW.frame
  if not d or not d:IsShown() then return end
  local src = Source()
  local link = BW.test and SAMPLE.item or (src.bid_item and (src.bid_item.linkFull or src.bid_item.name or src.bid_item.link))
  d.title:SetText(BW.test and "Test officer bid window" or "Bids")
  d.item:SetText(link or UI.Paint(C.dim, "No item up for bids"))
  local itemStr = BW.test and "item:19019:0:0:0" or (src.bid_item and src.bid_item.link)
  local ok, osPrice, price = false, nil, nil
  if itemStr and sepgp_prices and sepgp_prices.GetOffspec then ok, osPrice, price = pcall(sepgp_prices.GetOffspec, sepgp_prices, itemStr, sepgp_progress) end
  d.cost:SetText((ok and price) and ("Mainspec " .. price .. " GP  -  Offspec " .. osPrice .. " GP") or "")
  for s = 1, table.getn(SECTIONS) do
    local sec, ui = SECTIONS[s], d.sections[s]
    local list = Sorted(src[sec.key])
    ui.count:SetText(table.getn(list) > 0 and ("(" .. table.getn(list) .. ")") or "")
    for r = 1, ROWS do
      local ln, b = ui.lines[r], list[r]
      if b then
        local label = UI.ClassName(b[1], b[2])
        if b[7] == "OSPRIO" then label = UI.Paint(C.red, "[PRIO] ") .. label end
        if b[6] and b[6] ~= "" then label = label .. UI.Paint(C.dim, "  (" .. b[6] .. ")") end
        ln.name:SetText(label)
        ln.pr:SetText(UI.FmtPR(tonumber(b[5])))
        ln.epgp:SetText(UI.Fmt(tonumber(b[3])) .. " / " .. UI.Fmt(tonumber(b[4])))
      else
        ln.name:SetText("")
        ln.pr:SetText("")
        ln.epgp:SetText("")
      end
    end
    ui.empty:SetText(table.getn(list) == 0 and "nobody yet" or "")
    ui.more:SetText(table.getn(list) > ROWS and ("and " .. (table.getn(list) - ROWS) .. " more - see the full bids page") or "")
  end
  if BW.test then
    d.hint:SetText(UI.Place.DB("officer").locked and "Locked" or "Drag it where you want it")
  else
    d.hint:SetText("")
  end
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
