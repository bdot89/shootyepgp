-- shootyepgp :: new window, part 12 - the officers' bid window
-- A small window of its own for the item up for bids: everyone who bid
-- mainspec or offspec (best PR first) and everyone who rolled for
-- transmog / mounts / bags (/roll 69, highest roll first), as the officers'
-- copies hear them (sepgp.bids_main / bids_off / bids_xmog). It opens by
-- itself when bids come in (the addon's sepgp_bids:Toggle(true), Settings >
-- "Open bid window by itself"); "Full bids page" opens the window's Bids topic
-- to announce a winner. The window grows and shrinks with its lists.
--
-- Where it sits, its size and whether it is locked: Settings > Pop-up windows
-- (UI.Place, ui\BidPopup.lua), with a test window filled with sample bids.

local UI = SEPGP_UI
local C = UI.C
local BW = {}
UI.BidWindow = BW

local W = 340
local MAX_ROWS = 8        -- per list; more are counted, the full bids page has them all
local ROW_H = 16
local SECTIONS = {
  { key = "bids_main", title = "Mainspec", col = C.accent },
  { key = "bids_off", title = "Offspec", col = C.on },
  { key = "bids_xmog", title = "Transmog / Mounts / Bags", col = C.gold, roll = true },
}
local SAMPLE = {
  item = "|cffff8000|Hitem:19019:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker]|h|r",
  bids_main = { { "Testwarrior", "Warrior", 2400, 600, 4.0, "", "" }, { "Testrogue", "Rogue", 1800, 600, 3.0, "", "" } },
  bids_off = { { "Testpaladin", "Paladin", 2000, 800, 2.5, "", "OSPRIO" }, { "Testhunter", "Hunter", 900, 450, 2.0, "Testmain", "" } },
  bids_xmog = { { "Testmage", "Mage", 1200, 400, 3.0, "", "XMOG", 41 }, { "Testpriest", "Priest", 800, 400, 2.0, "", "XMOG", 63 } },
}

local function Source()
  if BW.test then return SAMPLE end
  return sepgp or {}
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

local function Line(d)
  local ln = {}
  ln.name = UI.Text(d, 11)
  ln.name:SetWidth(176)
  ln.name:SetJustifyH("LEFT")
  ln.a = UI.Text(d, 11, C.gold)
  ln.a:SetWidth(60)
  ln.a:SetJustifyH("RIGHT")
  ln.b = UI.Text(d, 10, C.dim)
  ln.b:SetWidth(76)
  ln.b:SetJustifyH("RIGHT")
  return ln
end

local function Build()
  local d = CreateFrame("Frame", "SepgpUIBidWindow", UIParent)
  d:SetWidth(W)
  d:SetHeight(200)
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
  for s = 1, table.getn(SECTIONS) do
    local sec = SECTIONS[s]
    local ui = { lines = {} }
    ui.head = UI.Text(d, 11, sec.col)
    ui.head:SetText(sec.title)
    ui.count = UI.Text(d, 10, C.dim)
    ui.cols = UI.Text(d, 10, C.dim)
    ui.cols:SetText(sec.roll and "Roll         PR" or "PR        EP / GP")
    ui.empty = UI.Text(d, 10, C.dim)
    ui.more = UI.Text(d, 10, C.dim)
    for r = 1, MAX_ROWS do ui.lines[r] = Line(d) end
    d.sections[s] = ui
  end
  d.full = UI.Button(d, "Full bids page", 120, 20)
  d.full:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 10, 8)
  d.full:SetScript("OnClick", function() UI.Open("bids") end)
  UI.Tip(d.full, "Full bids page", "Opens the Bids topic: click a bidder there to announce the winner.")
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

local function Place(fs, d, point, x, y)
  fs:ClearAllPoints()
  fs:SetPoint(point, d, "TOP" .. point, x, y)
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
  -- lay the lists out one under the other, as long as they are
  local y = (ok and price) and -62 or -52
  for s = 1, table.getn(SECTIONS) do
    local sec, ui = SECTIONS[s], d.sections[s]
    local list = Sorted(src[sec.key], sec.roll)
    local n = table.getn(list)
    Place(ui.head, d, "LEFT", 10, y)
    ui.count:ClearAllPoints()
    ui.count:SetPoint("LEFT", ui.head, "RIGHT", 6, 0)
    ui.count:SetText(n > 0 and ("(" .. n .. ")") or "")
    Place(ui.cols, d, "RIGHT", -12, y)
    if n > 0 then ui.cols:Show() else ui.cols:Hide() end
    y = y - 16
    for r = 1, MAX_ROWS do
      local ln, b = ui.lines[r], list[r]
      if b then
        Place(ln.name, d, "LEFT", 16, y)
        local label = UI.ClassName(b[1], b[2])
        if b[7] == "OSPRIO" then label = UI.Paint(C.red, "[PRIO] ") .. label end
        if b[6] and b[6] ~= "" then label = label .. UI.Paint(C.dim, " (" .. b[6] .. ")") end
        ln.name:SetText(label)
        if sec.roll then
          Place(ln.a, d, "RIGHT", -96, y)
          ln.a:SetText(b[8] and tostring(b[8]) or UI.Paint(C.dim, "no roll"))
          Place(ln.b, d, "RIGHT", -12, y)
          ln.b:SetText(UI.FmtPR(tonumber(b[5])))
        else
          Place(ln.a, d, "RIGHT", -96, y)
          ln.a:SetText(UI.FmtPR(tonumber(b[5])))
          Place(ln.b, d, "RIGHT", -12, y)
          ln.b:SetText(UI.Fmt(tonumber(b[3])) .. " / " .. UI.Fmt(tonumber(b[4])))
        end
        ln.name:Show() ln.a:Show() ln.b:Show()
        y = y - ROW_H
      else
        ln.name:Hide() ln.a:Hide() ln.b:Hide()
      end
    end
    if n == 0 then
      Place(ui.empty, d, "LEFT", 16, y)
      ui.empty:SetText(sec.roll and ("nobody rolled yet (/roll " .. ((UI.BidPopup and UI.BidPopup.ROLL_MAX) or 69) .. ")") or "nobody yet")
      ui.empty:Show()
      y = y - ROW_H
    else
      ui.empty:Hide()
    end
    if n > MAX_ROWS then
      Place(ui.more, d, "LEFT", 16, y)
      ui.more:SetText("and " .. (n - MAX_ROWS) .. " more - see the full bids page")
      ui.more:Show()
      y = y - ROW_H
    else
      ui.more:Hide()
    end
    y = y - 8
  end
  d:SetHeight(-y + 36)
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
