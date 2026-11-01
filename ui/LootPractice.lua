-- shootyepgp :: new window, part 13 - practice a loot hand-out (officers)
-- The guild leader asked (29 Oct 2026) to try the whole cycle on their own:
-- a pretend bid start on an item, the raider bid pop-up, bidding on it, the
-- bid landing in the officers' bid window, the countdown, announcing the
-- winner and giving the GP.
--
-- Everything stays in this copy: nothing goes to officer notes, raid / guild
-- chat or other players' addons. The real bid data (sepgp.bid_item, bids_*)
-- is not touched - practice has its own (LP.data). Every window says PRACTICE.
-- Start: Settings > Pop-up windows > "Practice a loot hand-out", or /epgp practice.
-- Stop: "Stop practice" in the bid window, or /epgp practice again.

local UI = SEPGP_UI
local C = UI.C
local LP = {}
UI.LootPractice = LP

local ITEMS = { 19019, 17076, 16900, 18814, 19375, 21126, 22954 }
-- pretend raiders so the lists have something to sort against
local OTHERS = {
  { "Practicewarrior", "Warrior", 2400, 900 }, { "Practicerogue", "Rogue", 1500, 700 },
  { "Practicepriest", "Priest", 1800, 500 }, { "Practicemage", "Mage", 900, 600 },
}

local function Me()
  local me = UI.Me and UI.Me()
  local name = (sepgp and sepgp._playerName) or UnitName("player")
  local _, class = UnitClass("player")
  local ep, gp = (me and me.ep) or 0, (me and me.gp) or ((sepgp and sepgp.VARS and sepgp.VARS.basegp) or 300)
  return name, me and me.class or class or "", ep, math.max(1, gp)
end

local function Row(name, class, ep, gp, flag, roll)
  return { name, class, ep, gp, ep / math.max(1, gp), "", flag or "", roll }
end

-- ------------------------------------------------------------------ the cycle

function LP.Start(id)
  if not UI.IsAdmin() then UI.Print("practice is for officers") return end
  id = id or ITEMS[math.random(1, table.getn(ITEMS))]
  local link = UI.Prices.Link(id)
  LP.on = true
  LP.data = {
    id = id, bid_item = { link = "item:" .. id .. ":0:0:0", linkFull = link, name = link },
    bids_main = {}, bids_off = {}, bids_xmog = {},
  }
  LP.counter, LP.count, LP.winner, LP.given = nil, nil, nil, nil
  -- the pretend raiders bid too
  local o = OTHERS
  table.insert(LP.data.bids_main, Row(o[1][1], o[1][2], o[1][3], o[1][4]))
  table.insert(LP.data.bids_off, Row(o[2][1], o[2][2], o[2][3], o[2][4]))
  table.insert(LP.data.bids_xmog, Row(o[3][1], o[3][2], o[3][3], o[3][4], "XMOG", math.random(1, 69)))
  UI.Print("|cffffc840PRACTICE|r loot hand-out on " .. link .. " - only on your screen. Bid on the pop-up, then hand it out in the bid window.")
  UI.BidPopup.Practice(id, link)
  UI.BidWindow.Open()
  LP.version = (LP.version or 0) + 1
end

function LP.Stop()
  if not LP.on then return end
  LP.on, LP.data = nil, nil
  if UI.BidPopup.frame and UI.BidPopup.frame.test == "practice" then UI.BidPopup.frame:Hide() end
  if UI.BidWindow.frame then UI.BidWindow.frame:Hide() end
  UI.Print("|cffffc840PRACTICE|r over - nothing was sent or written.")
end

function LP.Toggle()
  if LP.on then LP.Stop() else LP.Start() end
end

-- your own bid from the practice pop-up: "+", "-" or "roll"
function LP.Bid(bid)
  if not LP.on then return end
  local name, class, ep, gp = Me()
  local d = LP.data
  for _, key in ipairs({ "bids_main", "bids_off", "bids_xmog" }) do
    for i = table.getn(d[key]), 1, -1 do
      if d[key][i][1] == name then table.remove(d[key], i) end
    end
  end
  if bid == "+" then
    table.insert(d.bids_main, Row(name, class, ep, gp))
  elseif bid == "-" then
    table.insert(d.bids_off, Row(name, class, ep, gp))
  elseif bid == "roll" then
    local roll = math.random(1, 69)
    table.insert(d.bids_xmog, Row(name, class, ep, gp, "XMOG", roll))
    UI.Print("|cffffc840PRACTICE|r you rolled " .. roll .. " (1-69)")
  end
  UI.BidWindow.Open()
end

-- the countdown, counted on your screen only
function LP.Countdown()
  LP.count = 6
  LP.counter = "|cff33ff33Starting|r"
  LP.ticker = LP.ticker or CreateFrame("Frame")
  LP.ticker.left = 1
  LP.ticker:SetScript("OnUpdate", function()
    this.left = this.left - arg1
    if this.left > 0 then return end
    this.left = 1
    LP.count = LP.count - 1
    if not LP.on then this:SetScript("OnUpdate", nil) return end
    if LP.count > 0 then
      LP.counter = "|cffffff00" .. LP.count .. "|r"
      UI.Print("|cffffc840PRACTICE|r countdown: " .. LP.count .. "  (would be said in raid chat)")
    else
      LP.counter = "|cffff3333Finished|r"
      this:SetScript("OnUpdate", nil)
    end
  end)
end

-- announce, then offer to give the GP (all pretend)
function LP.Announce(kind, name, pr, roll)
  local d = LP.data
  if not d then return end
  local what = (kind == "MS" and "Mainspec") or (kind == "OS" and "Offspec") or "Transmog / Mounts / Bags"
  UI.Print("|cffffc840PRACTICE|r would announce: Winning " .. what .. (kind == "XMOG" and (" roll: " .. name .. " (rolled " .. tostring(roll) .. ")") or (" Bid: " .. name .. string.format(" (%.3f PR)", pr or 0))))
  LP.winner = { kind = kind, name = name }
  local ms, os = UI.Prices.Price(d.id)
  local gp = (kind == "MS" and ms) or (kind == "OS" and os) or 0
  if kind == "XMOG" or not gp or gp == 0 then
    LP.given = name .. " wins it - no GP for " .. string.lower(what)
    return
  end
  UI.Confirm("|cffffc840PRACTICE|r - nothing is written.\n\nGive " .. name .. " " .. gp .. " GP for the item (" .. string.lower(what) .. ")?", function()
    local m = UI.byName and UI.byName[name]
    local now = m and m.gp
    LP.given = name .. " +" .. gp .. " GP" .. (now and ("  (" .. now .. " -> " .. (now + gp) .. ", not written)") or "  (not written)")
    UI.Print("|cffffc840PRACTICE|r " .. LP.given)
  end, "Practice: give the GP?", "Yes, give it (practice)")
end
