-- shootyepgp :: new window, part 10 - bid pop-up for every raider
-- When the loot master calls for bids in raid chat, every copy already prints
-- the clickable [MAINSPEC] / [OFFSPEC] line (sepgp:bidPrint). Now a box comes
-- up too: the item, its GP, Mainspec / Offspec / Transmog / Pass, and "Ignore
-- this item for good". The buttons whisper the loot master "+", "-" or "tmog",
-- as the chat links and typing by hand do, so the loot master's side is unchanged
-- (a transmog roll lands in sepgp.bids_xmog).
--
-- Ignored items (Prices > Ignored) never pop up. Wish list items also get a
-- big alert in the middle of the screen. Off: Prices > "Bid pop-ups".
--
-- Where it sits, its size and whether it is locked: Settings > Pop-up windows
-- (UI.Place below, also used by the officers' bid window), with a test pop-up.

local UI = SEPGP_UI
local C = UI.C
local BP = {}
UI.BidPopup = BP

local SHOW_FOR = 120      -- seconds before an unanswered pop-up goes away
local ALERT_FOR = 6
local TEST_ITEM = 19019   -- Thunderfury, for the test pop-up

-- ------------------------------------------------------------------ placing pop-ups
-- sepgp_ui.place[key] = { x, y (centre, in the frame's own scale), scale, locked }
local P = {}
UI.Place = P

function P.DB(key)
  local db = UI.DB()
  if type(db.place) ~= "table" then db.place = {} end
  if type(db.place[key]) ~= "table" then db.place[key] = { scale = 1 } end
  return db.place[key]
end

-- drag to move while not locked; the spot is saved when let go
function P.Attach(frame, key, dx, dy)
  frame.placeKey, frame.placeX, frame.placeY = key, dx or 0, dy or 0
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function()
    if not P.DB(this.placeKey).locked then this:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    local x, y = this:GetCenter()
    local p = P.DB(this.placeKey)
    p.x, p.y = x, y
  end)
end

function P.Apply(frame)
  local p = P.DB(frame.placeKey)
  frame:SetScale(p.scale or 1)
  frame:ClearAllPoints()
  if p.x and p.y then
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.x, p.y)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", frame.placeX, frame.placeY)
  end
end

-- a new size keeps the pop-up's centre where it is on screen
function P.SetScale(key, s, frame)
  local p = P.DB(key)
  local old = p.scale or 1
  if p.x and p.y then p.x, p.y = p.x * old / s, p.y * old / s end
  p.scale = s
  if frame then P.Apply(frame) end
end

function P.SetLocked(key, on) P.DB(key).locked = on and true or nil end

function P.Reset(key, frame)
  local db = UI.DB()
  if type(db.place) == "table" then db.place[key] = nil end
  if frame then P.Apply(frame) end
end

local function Whisper(bid, ml)
  if not ml then return end
  if sepgp and sepgp.inRaid and not sepgp:inRaid(ml) then
    UI.Print(ml .. " is not in your raid any more - bid not sent")
    return
  end
  SendChatMessage(bid, "WHISPER", nil, ml)
end

local BID_NAME = { ["+"] = "Mainspec", ["-"] = "Offspec", ["tmog"] = "Transmog" }

-- ------------------------------------------------------------------ the box

local function Build()
  local PR = UI.Prices
  local d = CreateFrame("Frame", "SepgpUIBidPopup", UIParent)
  d:SetWidth(400)
  d:SetHeight(150)
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true)
  P.Attach(d, "bid", 0, 160)
  -- the spot came from the old per-character setting (10.23.0)
  local db = PR.DB()
  if db.popupX and db.popupY and not P.DB("bid").x then
    P.DB("bid").x, P.DB("bid").y = db.popupX, db.popupY
  end
  db.popupX, db.popupY = nil, nil
  UI.Flat(d, C.bg, 0.97, C.accent)
  local bar = UI.Fill(d, C.head, 1, "BORDER")
  bar:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -1)
  bar:SetHeight(26)
  d.title = UI.Text(d, 12, C.gold)
  d.title:SetPoint("TOPLEFT", d, "TOPLEFT", 10, -7)
  local close = UI.Button(d, "X", 20, 18)
  close:SetPoint("TOPRIGHT", d, "TOPRIGHT", -4, -4)
  close:SetScript("OnClick", function() d:Hide() end)
  UI.Tip(close, "Close", "Same as Pass: nothing is sent.")

  -- the item: icon (hover = tooltip) and name
  local ib = CreateFrame("Button", nil, d)
  ib:SetWidth(36)
  ib:SetHeight(36)
  ib:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -36)
  d.icon = ib:CreateTexture(nil, "ARTWORK")
  d.icon:SetAllPoints(ib)
  d.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  ib:SetScript("OnEnter", function() if d.id then PR.Tooltip(this, d.id) end end)
  ib:SetScript("OnLeave", function() GameTooltip:Hide() end)
  d.star = ib:CreateTexture(nil, "OVERLAY")
  d.star:SetTexture(PR.WISH_ICON)
  d.star:SetWidth(16)
  d.star:SetHeight(16)
  d.star:SetPoint("TOPRIGHT", ib, "TOPRIGHT", 6, 6)
  d.name = UI.Text(d, 14)
  d.name:SetPoint("TOPLEFT", ib, "TOPRIGHT", 10, -1)
  d.name:SetWidth(330)
  d.name:SetJustifyH("LEFT")
  d.price = UI.Text(d, 11, C.dim)
  d.price:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -5)

  local function Bid(label, bid, col)
    local b = UI.Button(d, label, 88, 26)
    if col then b:SetBackdropBorderColor(col[1], col[2], col[3], 1) end
    b.bid = bid
    b:SetScript("OnClick", function()
      if this.bid and d.test then
        UI.Print("test pop-up: this would whisper " .. this.bid .. " to the loot master (" .. BID_NAME[this.bid] .. ")")
      elseif this.bid then
        Whisper(this.bid, d.ml)
        UI.Print("you " .. (this.bid == "tmog" and "rolled Transmog" or ("bid " .. BID_NAME[this.bid])) .. " on " .. (d.link or "")
          .. " (whispered " .. this.bid .. " to " .. tostring(d.ml) .. ")")
      end
      d:Hide()
    end)
    return b
  end
  d.ms = Bid("Mainspec", "+", C.accent)
  d.ms:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 34)
  d.os = Bid("Offspec", "-", C.on)
  d.os:SetPoint("LEFT", d.ms, "RIGHT", 6, 0)
  d.xmog = Bid("Transmog", "tmog", C.gold)
  d.xmog:SetPoint("LEFT", d.os, "RIGHT", 6, 0)
  d.pass = Bid("Pass", nil)
  d.pass:SetPoint("LEFT", d.xmog, "RIGHT", 6, 0)
  UI.Tip(d.ms, "Mainspec", "Whispers + to the loot master, as typing + does.")
  UI.Tip(d.os, "Offspec", "Whispers - to the loot master, as typing - does.")
  UI.Tip(d.xmog, "Transmog roll", "Whispers tmog to the loot master: you want it for its looks. Officers see transmog rolls next to the bids.")
  UI.Tip(d.pass, "Pass", "Closes this box. Nothing is sent.")

  -- "ignore for good": a quiet text button
  local ig = CreateFrame("Button", nil, d)
  ig:SetHeight(16)
  ig:SetWidth(200)
  ig:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, 10)
  local igIcon = ig:CreateTexture(nil, "ARTWORK")
  igIcon:SetTexture(PR.IGNORE_ICON)
  igIcon:SetWidth(14)
  igIcon:SetHeight(14)
  igIcon:SetPoint("LEFT", ig, "LEFT", 0, 0)
  local igText = UI.Text(ig, 11, C.dim)
  igText:SetPoint("LEFT", igIcon, "RIGHT", 5, 0)
  igText:SetText("Ignore this item for good")
  ig:SetScript("OnEnter", function()
    igText:SetTextColor(1, 1, 1)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Ignore this item for good")
    GameTooltip:AddLine("It never pops up again. Undo in the window: Prices > Ignored.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  ig:SetScript("OnLeave", function()
    igText:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    GameTooltip:Hide()
  end)
  ig:SetScript("OnClick", function()
    if d.test then
      UI.Print("test pop-up: nothing is ignored")
    elseif d.id then
      PR.SetState(d.id, "ignore")
      UI.Print((d.link or "the item") .. " will not pop up again (undo: /epgp prices > Ignored)")
    end
    d:Hide()
  end)
  d.ignore = ig
  -- test mode: what to do, at the bottom right
  d.hint = UI.Text(d, 10, C.gold)
  d.hint:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -12, 12)

  d.timeLeft = 0
  d:SetScript("OnUpdate", function()
    this.timeLeft = this.timeLeft - arg1
    if this.timeLeft <= 0 then this:Hide() end
  end)
  d:Hide()
  BP.frame = d
  return d
end

-- the big wish list alert
local function BuildAlert()
  local a = CreateFrame("Frame", nil, UIParent)
  a:SetWidth(700)
  a:SetHeight(70)
  a:SetPoint("TOP", UIParent, "TOP", 0, -150)
  a:SetFrameStrata("FULLSCREEN_DIALOG")
  a.top = UI.Text(a, 16, C.gold)
  a.top:SetPoint("TOP", a, "TOP", 0, 0)
  a.top:SetText("WISH LIST ITEM UP FOR BIDS")
  a.text = UI.Text(a, 26)
  a.text:SetPoint("TOP", a.top, "BOTTOM", 0, -6)
  a.left = 0
  a:SetScript("OnUpdate", function()
    this.left = this.left - arg1
    if this.left <= 0 then this:Hide() return end
    if this.left < 1 then this:SetAlpha(this.left) else this:SetAlpha(1) end
  end)
  a:Hide()
  BP.alert = a
  return a
end

-- fill the box for an item (test = the Settings test pop-up: nothing is sent)
local function Fill(d, id, ml, link, need, greed, bid, test)
  local PR = UI.Prices
  d.id, d.ml, d.link, d.test = id, ml, link, test
  local _, _, tex = PR.Info(id)
  d.icon:SetTexture(tex)
  local shown
  local _, _, full = string.find(link or "", "^(|c%x+|H.-|h.-|h|r)")
  if full then shown = string.gsub(full, "|H.-|h(.-)|h", "%1") end
  d.name:SetText(shown or PR.Colored(id))
  if not GetItemInfo(id) then PR.Query(id) end
  local ms, os = PR.Price(id)
  d.price:SetText((ms and ("Mainspec " .. UI.Paint(C.text, ms .. " GP") .. "    Offspec " .. UI.Paint(C.text, os .. " GP")) or "No GP price set")
    .. UI.Paint(C.dim, "    called by " .. tostring(ml)))
  local st = PR.State(id)
  if test then
    d.title:SetText("Test bid pop-up")
    d.hint:SetText(P.DB("bid").locked and "Locked - unlock it in Settings to move it" or "Drag it where you want it")
  else
    d.title:SetText(st == "wish" and "Bids are open - on your wish list!" or "Bids are open")
    d.hint:SetText("")
  end
  if st == "wish" and not test then d.star:Show() else d.star:Hide() end
  -- as the chat line: a call for + only offers mainspec, a call for - only offspec
  UI.Enable(d.ms, (need or bid or not greed) and true or false)
  UI.Enable(d.os, (greed or bid or not need) and true or false)
  P.Apply(d)
  d.timeLeft = test and 600 or SHOW_FOR
  d:Show()
end

-- from sepgp:bidPrint: link = the item link, ml = who called, need / greed / bid = the call's keywords
function BP.OnCall(link, ml, need, greed, bid)
  local PR = UI.Prices
  if not PR or not link then return end
  local _, _, id = string.find(link, "item:(%d+)")
  id = tonumber(id)
  if not id then return end
  local st = PR.State(id)
  if st == "ignore" or not PR.DB().popups then return end
  local d = BP.frame or Build()
  Fill(d, id, ml, link, need, greed, bid)
  if st == "wish" then
    local a = BP.alert or BuildAlert()
    a.text:SetText(PR.Colored(id))
    a.left = ALERT_FOR
    a:SetAlpha(1)
    a:Show()
    PlaySound("RaidWarning")
  end
end

-- Settings: show a sample pop-up to place, size and lock
function BP.Test()
  local d = BP.frame or Build()
  Fill(d, TEST_ITEM, (sepgp and sepgp._playerName) or UnitName("player"), nil, 1, 1, nil, true)
end

function BP.Frame() return BP.frame or Build() end
