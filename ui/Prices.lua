-- shootyepgp :: new window, part 9 - Prices, wish list, ignore list
-- The guild leader asked (29 Oct 2026) for one place where everyone sees what
-- an item costs: pick a raid, pick a boss, the boss's loot with icons; hover
-- for the real tooltip plus the mainspec and offspec GP.
--
--   Loot        raid buttons, bosses on the left, their items on the right
--   Wish list   items you right-clicked "wish list": a big alert when one is up for bids
--   Ignored     items you never want a bid pop-up for
--   Changes     (officers) prices changed in game, waiting to go into prices.lua
--
-- Raids, bosses and items come from loot_db.lua (made once from AtlasLoot by
-- tools\build_lootdb.ps1; AtlasLoot is not needed in game). Prices are the
-- addon's own (prices.lua via sepgp_prices:GetPrice).
--
-- Officers' price changes: a WoW addon cannot write files, so a change goes
-- into the saved variable sepgp_price_edits (account-wide) and is used by this
-- copy at once. tools\write_prices.ps1 writes them into prices.lua in its own
-- layout; once prices.lua has the same price, the saved change clears itself.
--
-- Wish list and ignore list are your own (sepgp_wish, per character).

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local PR = { version = 0 }
UI.Prices = PR

local ROW_H = 22
local QHEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
PR.WISH_ICON = "Interface\\Buttons\\UI-CheckBox-Check"                -- tick (1.12 has no single raid-star file)
PR.XMOG_ICON = "Interface\\Icons\\INV_Shirt_White_01"                  -- a shirt: wanted for its looks
PR.IGNORE_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"           -- red cross

-- ------------------------------------------------------------------ data

function PR.DB()
  if type(sepgp_wish) ~= "table" then sepgp_wish = {} end
  local db = sepgp_wish
  if type(db.wish) ~= "table" then db.wish = {} end
  if type(db.xmog) ~= "table" then db.xmog = {} end
  if type(db.ignore) ~= "table" then db.ignore = {} end
  if db.popups == nil then db.popups = true end
  return db
end

function PR.Loot() return type(sepgp_lootdb) == "table" and sepgp_lootdb or { raids = {}, items = {} } end

-- item id -> raid, boss (the first boss that drops it)
local home
function PR.Find(id)
  if not home then
    home = {}
    local raids = PR.Loot().raids
    for r = 1, table.getn(raids) do
      local bosses = raids[r].bosses
      for b = 1, table.getn(bosses) do
        local items = bosses[b].items
        for i = 1, table.getn(items) do
          if not home[items[i]] then home[items[i]] = { raids[r], bosses[b], r * 10000 + b * 100 + i } end
        end
      end
    end
  end
  local h = home[id]
  if h then return h[1], h[2], h[3] end
end

function PR.Info(id)
  local d = PR.Loot().items[id]
  local name, _, q, _, _, _, _, _, tex = GetItemInfo(id)
  name = name or (d and d[3]) or ("item " .. tostring(id))
  q = q or (d and d[2]) or 1
  tex = tex or (d and d[1] and ("Interface\\Icons\\" .. d[1])) or "Interface\\Icons\\INV_Misc_QuestionMark"
  return name, q, tex
end

function PR.Colored(id)
  local name, q = PR.Info(id)
  return "|cff" .. (QHEX[q] or "ffffff") .. name .. "|r"
end

function PR.Link(id)
  local name, q = PR.Info(id)
  return "|cff" .. (QHEX[q] or "ffffff") .. "|Hitem:" .. id .. ":0:0:0|h[" .. name .. "]|h|r"
end

-- mainspec and offspec GP (nil when the item has no price)
function PR.Price(id)
  if not sepgp_prices or not sepgp_prices.GetPrice then return nil end
  local ms, tier = sepgp_prices:GetPrice(tonumber(id), sepgp_progress)
  if not ms then return nil end
  return ms, math.floor(ms * PR.Rate(tier)), tier
end

function PR.State(id)
  local db = PR.DB()
  if db.wish[id] then return "wish" end
  if db.xmog[id] then return "xmog" end
  if db.ignore[id] then return "ignore" end
end
-- state = "wish", "xmog", "ignore" or nil (none); an item is on one list at most
function PR.SetState(id, state)
  local db = PR.DB()
  db.wish[id] = (state == "wish") and true or nil
  db.xmog[id] = (state == "xmog") and true or nil
  db.ignore[id] = (state == "ignore") and true or nil
  PR.version = PR.version + 1
end

local function Count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- ------------------------------------------------------------------ price changes

PR.filePrice = {}   -- id -> { gp, tier } as prices.lua has it (nil = not in prices.lua)
function PR.Edits()
  if type(sepgp_price_edits) ~= "table" then sepgp_price_edits = {} end
  return sepgp_price_edits
end

-- at login: put the officers' saved changes over prices.lua's; a change prices.lua already has is done
function PR.ApplyEdits()
  local prices = sepgp and sepgp.gp_prices
  if type(prices) ~= "table" then return end
  local edits = PR.Edits()
  for id, e in pairs(edits) do
    local file = prices[id]
    if type(e) ~= "table" or not tonumber(e.gp) then
      edits[id] = nil
    elseif file and file[1] == e.gp then
      edits[id] = nil
    else
      PR.filePrice[id] = file and { file[1], file[2] } or false
      local r = PR.Find(id)
      prices[id] = { e.gp, (file and file[2]) or (r and r.tier) or "T1" }
    end
  end
end

local function Me() return (sepgp and sepgp._playerName) or UnitName("player") end
local function Now() return time and time() or 0 end

-- by / at: who changed it and when (a change heard from another officer); quiet = do not send it on
function PR.SetPrice(id, gp, by, at, quiet)
  local prices = sepgp and sepgp.gp_prices
  if type(prices) ~= "table" then return end
  gp = math.floor(tonumber(gp) or 0)
  if PR.filePrice[id] == nil then
    local f = prices[id]
    PR.filePrice[id] = f and { f[1], f[2] } or false
  end
  local file = PR.filePrice[id]
  if file and file[1] == gp then
    PR.UndoPrice(id, quiet)
    return
  end
  local r = PR.Find(id)
  prices[id] = { gp, (file and file[2]) or (prices[id] and prices[id][2]) or (r and r.tier) or "T1" }
  PR.Edits()[id] = { gp = gp, by = by or Me(), at = at or Now() }
  PR.version = PR.version + 1
  if not quiet then PR.SendPrices({ id }) end
end

function PR.UndoPrice(id, quiet)
  local prices = sepgp and sepgp.gp_prices
  local file = PR.filePrice[id]
  if type(prices) == "table" and file ~= nil then
    prices[id] = file and { file[1], file[2] } or nil
  end
  PR.Edits()[id] = nil
  PR.version = PR.version + 1
  if not quiet then PR.SendPrices({ id }, true) end
end

-- ------------------------------------------------------------------ sharing
-- So that every copy shows the same prices (guild leader, 29 Oct 2026):
--   OSTIER;T1=0.25,T2=0.4,...;1    the guild leader's offspec price per tier
--   PRICE;id:gp:at,id:gp:at;1      officers' price changes; gp -1 = back to prices.lua
-- Both go on the addon's own GUILD prefix (sepgp:addonMessage). OSTIER is sent with the
-- guild leader's settings (sepgp:shareSettings, also when someone logs in), PRICE when an
-- officer saves or undoes a price, and every saved change again with the settings.

PR.TIERS = {
  { key = "T1", label = "T1 - Molten Core" },
  { key = "T1.5", label = "T1.5 - ZG, AQ20, Kara10" },
  { key = "T2", label = "T2 - Onyxia, Blackwing Lair" },
  { key = "T2.5", label = "T2.5 - Temple of Ahn'Qiraj" },
  { key = "T3", label = "T3 - Naxxramas" },
  { key = "T3.5", label = "T3.5 - Tower of Karazhan" },
}

function PR.Rate(tier)
  if sepgp_prices and sepgp_prices.OffspecRate then return sepgp_prices:OffspecRate(tier) end
  return sepgp_discount or 0.25
end
function PR.SetRate(tier, rate)
  if type(sepgp_discount_tier) ~= "table" then sepgp_discount_tier = {} end
  sepgp_discount_tier[tier] = math.floor(rate * 100 + 0.5) / 100
  PR.version = PR.version + 1
end

local function Send(msg)
  if sepgp and sepgp.addonMessage and IsInGuild() then sepgp:addonMessage(msg, "GUILD") end
end

function PR.SendPrices(ids, undo)
  local edits, parts = PR.Edits(), {}
  for i = 1, table.getn(ids) do
    local e = edits[ids[i]]
    if undo or not e then
      table.insert(parts, ids[i] .. ":-1:" .. Now())
    else
      table.insert(parts, ids[i] .. ":" .. e.gp .. ":" .. (e.at or 0))
    end
  end
  -- a few changes per message (addon messages stop at 255 characters)
  local msg = ""
  for i = 1, table.getn(parts) do
    if msg ~= "" and string.len(msg) + string.len(parts[i]) > 200 then
      Send("PRICE;" .. msg .. ";1")
      msg = ""
    end
    msg = (msg == "") and parts[i] or (msg .. "," .. parts[i])
  end
  if msg ~= "" then Send("PRICE;" .. msg .. ";1") end
end

function PR.Share()
  if IsGuildLeader() then
    local parts = {}
    for i = 1, table.getn(PR.TIERS) do
      local k = PR.TIERS[i].key
      table.insert(parts, k .. "=" .. PR.Rate(k))
    end
    Send("OSTIER;" .. table.concat(parts, ",") .. ";1")
  end
  local ids = {}
  for id in pairs(PR.Edits()) do table.insert(ids, id) end
  if table.getn(ids) > 0 then PR.SendPrices(ids) end
end

-- the sender's guild rank: 0 = guild leader
local function RankIndex(name)
  for i = 1, GetNumGuildMembers(1) do
    local n, _, ri = GetGuildRosterInfo(i)
    if n == name then return ri end
  end
end

-- from sepgp:addonComms (guild members only); rank = the sender's rank name
function PR.Receive(kind, what, sender, rank)
  local ri = RankIndex(sender)
  if kind == "OSTIER" then
    if ri ~= 0 then return end   -- only the guild leader sets the guild's rules
    local changed
    for tier, rate in string.gfind(what or "", "([^=,]+)=([%d%.]+)") do
      rate = tonumber(rate)
      if rate and rate >= 0 and rate <= 1 and math.abs(PR.Rate(tier) - rate) > 0.001 then
        PR.SetRate(tier, rate)
        changed = true
      end
    end
    if changed then UI.Print("offspec prices per tier updated by " .. tostring(sender)) end
  elseif kind == "PRICE" then
    -- officers only: the guild leader or the ranks the addon already trusts with bid data
    if not (ri == 0 or rank == "Officer" or rank == "Supreme leader") then return end
    for id, gp, at in string.gfind(what or "", "(%d+):(%-?%d+):(%d+)") do
      id, gp, at = tonumber(id), tonumber(gp), tonumber(at)
      local mine = PR.Edits()[id]
      if not (mine and (mine.at or 0) > at) then
        if gp < 0 then
          if mine then PR.UndoPrice(id, true) end
        elseif not (mine and mine.gp == gp) then
          PR.SetPrice(id, gp, sender, at, true)
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ item cache

-- items this client has not seen: ask the server once through a hidden
-- tooltip (as AtlasLoot does), so names, icons and hover tooltips fill in
local cacheTip, asked = nil, {}
function PR.Query(id)
  if asked[id] or GetItemInfo(id) then return end
  asked[id] = true
  if not cacheTip then
    cacheTip = CreateFrame("GameTooltip", "SepgpUIPriceCacheTip", UIParent, "GameTooltipTemplate")
  end
  cacheTip:SetOwner(UIParent, "ANCHOR_NONE")
  cacheTip:SetHyperlink("item:" .. id .. ":0:0:0")
  cacheTip:Hide()
end

-- the tooltip of an item row: the real item tooltip, then its GP
function PR.Tooltip(owner, id)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  if GetItemInfo(id) then
    GameTooltip:SetHyperlink("item:" .. id .. ":0:0:0")
  else
    PR.Query(id)
    GameTooltip:AddLine(PR.Colored(id))
    GameTooltip:AddLine("Your client has not seen this item yet - hover again in a moment.", C.dim[1], C.dim[2], C.dim[3], 1)
  end
  local ms, os = PR.Price(id)
  GameTooltip:AddLine(" ")
  if ms then
    GameTooltip:AddDoubleLine("Mainspec", ms .. " GP", 0.2, 0.7, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Offspec", os .. " GP", 0.23, 0.87, 0.18, 1, 1, 1)
  else
    GameTooltip:AddLine("No GP price set", C.dim[1], C.dim[2], C.dim[3])
  end
  local st = PR.State(id)
  if st == "wish" then GameTooltip:AddLine("On your wish list", C.gold[1], C.gold[2], C.gold[3]) end
  if st == "xmog" then GameTooltip:AddLine("On your transmog list: X-Mog roll", C.gold[1], C.gold[2], C.gold[3]) end
  if st == "ignore" then GameTooltip:AddLine("Ignored: no bid pop-up", C.red[1], C.red[2], C.red[3]) end
  GameTooltip:AddLine(UI.IsAdmin() and "Right-click: wish list, transmog, ignore, change price" or "Right-click: wish list, transmog list or ignore", C.dim[1], C.dim[2], C.dim[3])
  GameTooltip:Show()
end

-- ------------------------------------------------------------------ item list

-- A scrolling list of item rows: icon, name, [where], MS GP, OS GP, wish / ignore mark, [button].
-- L:SetItems({ { id = , where = , extra = }, ... }); L.onAction(entry) for the row button
local function ItemList(parent, width, nRows, withWhere, actionLabel)
  local L = CreateFrame("Frame", nil, parent)
  L:SetWidth(width)
  L:SetHeight(20 + nRows * ROW_H + 2)
  UI.Flat(L, C.field, 1, C.line)
  L.items, L.offset, L.nRows = {}, 0, nRows
  local whereW = withWhere and 170 or 0
  local actW = actionLabel and 62 or 0
  local nameW = width - 30 - whereW - 58 - 58 - 22 - actW - 20
  local head = CreateFrame("Frame", nil, L)
  head:SetPoint("TOPLEFT", L, "TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", L, "TOPRIGHT", -1, -1)
  head:SetHeight(20)
  local hbg = UI.Fill(head, C.head, 1)
  hbg:SetAllPoints(head)
  local function Head(text, x, w, align)
    local t = UI.Text(head, 11, C.gold)
    t:SetPoint("LEFT", head, "LEFT", x, 0)
    t:SetWidth(w)
    t:SetJustifyH(align or "LEFT")
    t:SetText(text)
  end
  local xName = 30
  local xWhere = xName + nameW + 6
  local xMS = xWhere + whereW
  local xOS = xMS + 58
  local xMark = xOS + 58 + 4
  Head("Item", xName, nameW)
  if withWhere then Head(withWhere, xWhere, whereW - 6) end
  Head("MS GP", xMS, 52, "RIGHT")
  Head("OS GP", xOS, 52, "RIGHT")
  L.lines = {}
  for r = 1, nRows do
    local line = CreateFrame("Button", nil, L)
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -(r - 1) * ROW_H)
    line:SetPoint("RIGHT", L, "RIGHT", -9, 0)
    line:SetHeight(ROW_H)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if math.mod(r, 2) == 0 then
      local stripe = UI.Fill(line, C.panel, 0.6)
      stripe:SetAllPoints(line)
    end
    UI.Hover(line, 0.06)
    line.icon = line:CreateTexture(nil, "ARTWORK")
    line.icon:SetWidth(18)
    line.icon:SetHeight(18)
    line.icon:SetPoint("LEFT", line, "LEFT", 6, 0)
    line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    line.name = UI.Text(line, 11)
    line.name:SetPoint("LEFT", line, "LEFT", xName, 0)
    line.name:SetWidth(nameW)
    line.name:SetHeight(ROW_H)
    line.name:SetJustifyH("LEFT")
    line.where = UI.Text(line, 10, C.dim)
    line.where:SetPoint("LEFT", line, "LEFT", xWhere, 0)
    line.where:SetWidth(math.max(1, whereW - 6))
    line.where:SetHeight(ROW_H)
    line.where:SetJustifyH("LEFT")
    line.ms = UI.Text(line, 11)
    line.ms:SetPoint("LEFT", line, "LEFT", xMS, 0)
    line.ms:SetWidth(52)
    line.ms:SetJustifyH("RIGHT")
    line.os = UI.Text(line, 11, C.dim)
    line.os:SetPoint("LEFT", line, "LEFT", xOS, 0)
    line.os:SetWidth(52)
    line.os:SetJustifyH("RIGHT")
    line.mark = line:CreateTexture(nil, "OVERLAY")
    line.mark:SetWidth(16)
    line.mark:SetHeight(16)
    line.mark:SetPoint("LEFT", line, "LEFT", xMark, 0)
    if actionLabel then
      local b = UI.Button(line, actionLabel, 56, 18)
      b:SetPoint("RIGHT", line, "RIGHT", -2, 0)
      b:SetScript("OnClick", function()
        local e = this:GetParent().entry
        if e and L.onAction then L.onAction(e) end
      end)
      line.action = b
    end
    line:SetScript("OnClick", function()
      local e = this.entry
      if not e then return end
      if arg1 == "LeftButton" and IsShiftKeyDown() and ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
        ChatFrameEditBox:Insert(PR.Link(e.id))
        return
      end
      if L.onClick then L.onClick(e, arg1, this) end
    end)
    line:SetScript("OnEnter", function() if this.entry then PR.Tooltip(this, this.entry.id) end end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    L.lines[r] = line
  end
  L.empty = UI.Text(L, 12, C.dim)
  L.empty:SetPoint("TOP", head, "BOTTOM", 0, -40)
  L.empty:SetWidth(width - 40)
  local sb = CreateFrame("Slider", nil, L)
  sb:SetOrientation("VERTICAL")
  sb:SetPoint("TOPRIGHT", L, "TOPRIGHT", -2, -22)
  sb:SetPoint("BOTTOMRIGHT", L, "BOTTOMRIGHT", -2, 2)
  sb:SetWidth(6)
  local track = UI.Fill(sb, C.panel, 1)
  track:SetAllPoints(sb)
  sb:SetThumbTexture(UI.WHITE)
  local th = sb:GetThumbTexture()
  if th then
    th:SetWidth(6)
    th:SetHeight(30)
    th:SetVertexColor(C.lineHi[1], C.lineHi[2], C.lineHi[3], 1)
  end
  sb:SetMinMaxValues(0, 0)
  sb:SetValueStep(1)
  sb:SetScript("OnValueChanged", function()
    local v = math.floor(this:GetValue() + 0.5)
    if v ~= L.offset then
      L.offset = v
      L:Draw()
    end
  end)
  L.bar = sb
  L:EnableMouseWheel(true)
  L:SetScript("OnMouseWheel", function()
    local maxOff = math.max(0, table.getn(L.items) - L.nRows)
    local v = math.max(0, math.min(maxOff, L.offset - arg1 * (IsShiftKeyDown() and 10 or 3)))
    L.bar:SetValue(v)
    if v ~= L.offset then
      L.offset = v
      L:Draw()
    end
  end)

  function L:SetItems(items, keepScroll)
    self.items = items or {}
    local maxOff = math.max(0, table.getn(self.items) - self.nRows)
    if not keepScroll then self.offset = 0 end
    self.offset = math.min(self.offset, maxOff)
    self.bar:SetMinMaxValues(0, maxOff)
    self.bar:SetValue(self.offset)
    if maxOff > 0 then self.bar:Show() else self.bar:Hide() end
    self:Draw()
  end
  function L:Draw()
    for r = 1, self.nRows do
      local line = self.lines[r]
      local e = self.items[self.offset + r]
      line.entry = e
      if e then
        local _, _, tex = PR.Info(e.id)
        PR.Query(e.id)
        line.icon:SetTexture(tex)
        local st = PR.State(e.id)
        line.name:SetText(PR.Colored(e.id))
        line.where:SetText(e.where or "")
        local ms, os = PR.Price(e.id)
        line.ms:SetText(ms and tostring(ms) or UI.Paint(C.dim, "-"))
        line.os:SetText(os and tostring(os) or "")
        if st == "wish" then
          line.mark:SetTexture(PR.WISH_ICON)
          line.mark:Show()
        elseif st == "xmog" then
          line.mark:SetTexture(PR.XMOG_ICON)
          line.mark:Show()
        elseif st == "ignore" then
          line.mark:SetTexture(PR.IGNORE_ICON)
          line.mark:Show()
        else
          line.mark:Hide()
        end
        -- wish list and ignored items fade back, their mark says which
        line.icon:SetAlpha(st and 0.4 or 1)
        line.name:SetAlpha(st and 0.5 or 1)
        line:Show()
      else
        line:Hide()
      end
    end
    if table.getn(self.items) == 0 then
      self.empty:SetText(self.emptyText or "Nothing here.")
      self.empty:Show()
    else
      self.empty:Hide()
    end
  end
  return L
end
PR.ItemList = ItemList

-- ------------------------------------------------------------------ right-click menu

local menu
local function MenuButton(i)
  local e = CreateFrame("Button", nil, menu)
  e:SetWidth(176)
  e:SetHeight(18)
  e:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 18)
  e.text = UI.Text(e, 11)
  e.text:SetPoint("LEFT", e, "LEFT", 22, 0)
  e.icon = e:CreateTexture(nil, "ARTWORK")
  e.icon:SetWidth(14)
  e.icon:SetHeight(14)
  e.icon:SetPoint("LEFT", e, "LEFT", 4, 0)
  local hl = e:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(e)
  hl:SetTexture(UI.WHITE)
  hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
  e:SetScript("OnClick", function()
    menu:Hide()
    if this.fn then this.fn() end
  end)
  return e
end

function PR.Menu(id, anchor)
  if not menu then
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:SetWidth(184)
    UI.Flat(menu, C.card, 0.98, C.lineHi)
    menu:Hide()
    table.insert(UI.menus, menu)
    menu.title = UI.Text(menu, 11)
    menu.buttons = {}
    for i = 1, 5 do menu.buttons[i] = MenuButton(i) end
  end
  UI.CloseMenus()
  local st = PR.State(id)
  local opts = {}
  if st == "wish" then
    table.insert(opts, { "Remove from wish list", PR.WISH_ICON, function() PR.SetState(id, nil) end })
  else
    table.insert(opts, { "Add to wish list", PR.WISH_ICON, function() PR.SetState(id, "wish") end })
  end
  if st == "xmog" then
    table.insert(opts, { "Remove from transmog list", PR.XMOG_ICON, function() PR.SetState(id, nil) end })
  else
    table.insert(opts, { "Add to transmog list", PR.XMOG_ICON, function() PR.SetState(id, "xmog") end })
  end
  if st == "ignore" then
    table.insert(opts, { "Stop ignoring", PR.IGNORE_ICON, function() PR.SetState(id, nil) end })
  else
    table.insert(opts, { "Ignore (no bid pop-up)", PR.IGNORE_ICON, function() PR.SetState(id, "ignore") end })
  end
  if UI.IsAdmin() then
    table.insert(opts, { "Change price...", "Interface\\Icons\\INV_Misc_Coin_01", function() PR.Editor(id) end })
  end
  for i = 1, 5 do
    local b, o = menu.buttons[i], opts[i]
    if o then
      b.text:SetText(o[1])
      b.icon:SetTexture(o[2])
      b.fn = function() o[3]() UI.RefreshPage() end
      b:Show()
    else
      b:Hide()
    end
  end
  menu:SetHeight(table.getn(opts) * 18 + 8)
  menu:ClearAllPoints()
  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  if x and s and s > 0 then
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s + 4, y / s - 4)
  else
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 30, 0)
  end
  menu:Show()
  PR.menu = menu
end

-- ------------------------------------------------------------------ price editor (officers)

local editor
local function BuildEditor()
  local d = CreateFrame("Frame", "SepgpUIPriceEditor", UIParent)
  d:SetWidth(360)
  d:SetHeight(176)
  d:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetToplevel(true)
  d:EnableMouse(true)
  UI.Flat(d, C.bg, 0.98, C.accent)
  local bar = UI.Fill(d, C.head, 1, "BORDER")
  bar:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -1)
  bar:SetHeight(30)
  local t = UI.Text(d, 14, C.gold)
  t:SetPoint("TOP", d, "TOP", 0, -9)
  t:SetText("Change price")
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetWidth(28)
  d.icon:SetHeight(28)
  d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 16, -42)
  d.name = UI.Text(d, 13)
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -1)
  d.file = UI.Text(d, 10, C.dim)
  d.file:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
  UI.Label(d, "Mainspec GP", 16, -90)
  d.box = UI.EditBox(d, 80)
  d.box:SetPoint("TOPLEFT", d, "TOPLEFT", 110, -87)
  d.os = UI.Text(d, 11, C.dim)
  d.os:SetPoint("LEFT", d.box, "RIGHT", 10, 0)
  d.box.onChange = function(txt)
    local n = tonumber(txt)
    local cur = d.id and sepgp and sepgp.gp_prices and sepgp.gp_prices[d.id]
    local r = d.id and PR.Find(d.id)
    local rate = PR.Rate((cur and cur[2]) or (r and r.tier))
    d.os:SetText(n and ("offspec " .. math.floor(n * rate) .. " GP (" .. math.floor(rate * 100 + 0.5) .. "%)") or "numbers only")
  end
  d.box.onEnter = function() d.save:GetScript("OnClick")() end
  d.save = UI.Button(d, "Save", 100, 24)
  d.save:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 16, 14)
  d.save:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
  d.save:SetScript("OnClick", function()
    local n = tonumber(d.box:GetText())
    if not n or n < 0 then
      UI.Print("the price must be a number")
      return
    end
    PR.SetPrice(d.id, n)
    UI.Print(PR.Link(d.id) .. " now costs " .. math.floor(n) .. " GP (saved in your copy; Prices > Changes)")
    d:Hide()
    UI.RefreshPage()
  end)
  d.undo = UI.Button(d, "Back to file price", 130, 24)
  d.undo:SetPoint("LEFT", d.save, "RIGHT", 6, 0)
  d.undo:SetScript("OnClick", function()
    PR.UndoPrice(d.id)
    d:Hide()
    UI.RefreshPage()
  end)
  UI.Tip(d.undo, "Back to file price", "Drops your change: the price in prices.lua counts again.")
  local cancel = UI.Button(d, "Cancel", 80, 24)
  cancel:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -16, 14)
  cancel:SetScript("OnClick", function() d:Hide() end)
  d:Hide()
  table.insert(UISpecialFrames, "SepgpUIPriceEditor")
  return d
end

function PR.Editor(id)
  if not UI.IsAdmin() then return end
  editor = editor or BuildEditor()
  UI.CloseMenus()
  editor.id = id
  local _, _, tex = PR.Info(id)
  editor.icon:SetTexture(tex)
  editor.name:SetText(PR.Colored(id))
  local file = PR.filePrice[id]
  local cur = sepgp and sepgp.gp_prices and sepgp.gp_prices[id]
  if file == nil then file = cur end
  if file then
    editor.file:SetText("In prices.lua: " .. file[1] .. " GP (" .. tostring(file[2]) .. ")")
  else
    editor.file:SetText("Not in prices.lua yet")
  end
  if PR.Edits()[id] then UI.Enable(editor.undo, true) else UI.Enable(editor.undo, false) end
  editor.box:SetText(cur and tostring(cur[1]) or "")
  editor:Show()
  editor.box:SetFocus()
  editor.box:HighlightText()
  PR.editor = editor
end

-- ------------------------------------------------------------------ the page

local VIEWS = {
  { key = "loot", label = "Loot" },
  { key = "wish", label = "Wish list" },
  { key = "xmog", label = "Transmog" },
  { key = "ignore", label = "Ignored" },
  { key = "changes", label = "Changes", admin = true },
}

-- entries for a set of ids, in raid / boss order, with "Raid - Boss"
local function Entries(set, extra)
  local list = {}
  for id in pairs(set) do
    local r, b, order = PR.Find(id)
    table.insert(list, { id = id, where = r and (r.key .. " - " .. b.name) or "", order = order or 9999999, extra = extra and extra(id) })
  end
  table.sort(list, function(a, b) return a.order < b.order end)
  return list
end

local function PickRaid(f, i)
  f.raid = i
  f.boss = 1
  UI.DB().priceRaid = i
  PR.Draw(f)
end

local function OnItemClick(e, button, line)
  if button == "RightButton" then
    PR.Menu(e.id, line)
  elseif UI.IsAdmin() then
    PR.Editor(e.id)
  end
end

local function Build(f)
  local raids = PR.Loot().raids
  -- view tabs
  f.tabs = {}
  local x = 0
  for i = 1, table.getn(VIEWS) do
    local v = VIEWS[i]
    local b = UI.Button(f, v.label, 96, 22)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", x, 0)
    b.key = v.key
    b:SetScript("OnClick", function()
      f.view = this.key
      PR.Draw(f)
    end)
    f.tabs[i] = b
    x = x + 100
  end
  -- your bid pop-ups on / off
  f.popups = UI.Switch(f)
  f.popups:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -3)
  f.popups.onToggle = function(on)
    PR.DB().popups = on and true or false
    f.popups.Set(on)
  end
  local pl = UI.Text(f, 11, C.dim)
  pl:SetPoint("RIGHT", f.popups, "LEFT", -6, 0)
  pl:SetText("Bid pop-ups")
  local hit = CreateFrame("Frame", nil, f)
  hit:SetAllPoints(pl)
  hit:EnableMouse(true)
  UI.Tip(hit, "Bid pop-ups", "When the loot master calls for bids, a box with Mainspec / Offspec / Pass comes up. Ignored items never pop up; wish list items also get a big alert.")

  -- loot view: raid buttons, bosses, items
  local lv = CreateFrame("Frame", nil, f)
  lv:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
  lv:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  f.lootView = lv
  lv.raidButtons = {}
  local n = table.getn(raids)
  local bw = math.floor((PW - (n - 1) * 4) / math.max(1, n))
  for i = 1, n do
    local b = UI.Button(lv, raids[i].name, bw, 22)
    b:SetPoint("TOPLEFT", lv, "TOPLEFT", (i - 1) * (bw + 4), 0)
    b.i = i
    b:SetScript("OnClick", function() PickRaid(f, this.i) end)
    UI.Tip(b, raids[i].name, "Tier " .. raids[i].tier .. ".")
    lv.raidButtons[i] = b
  end
  local rows = math.floor((PH - 30 - 28 - 20 - 18) / ROW_H)
  lv.bosses = UI.List(lv, { { key = "name", label = "Boss", width = 156 } }, ROW_H, rows)
  lv.bosses:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, -28)
  lv.bosses:SetWidth(180)
  lv.bosses:SetHeight(20 + rows * ROW_H + 2)
  lv.bosses.onClick = function(row)
    f.boss = row.id
    PR.Draw(f)
  end
  lv.items = ItemList(lv, PW - 186, rows)
  lv.items:SetPoint("TOPLEFT", lv.bosses, "TOPRIGHT", 6, 0)
  lv.items.onClick = OnItemClick
  lv.items.emptyText = "No loot listed for this boss."
  lv.hint = UI.Text(lv, 10, C.dim)
  lv.hint:SetPoint("TOPLEFT", lv.bosses, "BOTTOMLEFT", 2, -5)

  -- wish / ignored / changes: one full-width list each
  local function ListView(where, action, empty)
    local v = CreateFrame("Frame", nil, f)
    v:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
    v:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    v.info = UI.Text(v, 11, C.dim)
    v.info:SetPoint("TOPLEFT", v, "TOPLEFT", 2, -2)
    v.info:SetWidth(PW - 4)
    v.info:SetJustifyH("LEFT")
    local r = math.floor((PH - 30 - 40 - 22) / ROW_H)
    v.list = ItemList(v, PW, r, where, action)
    v.list:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -40)
    v.list.onClick = OnItemClick
    v.list.emptyText = empty
    v:Hide()
    return v
  end
  f.wishView = ListView("Drops from", "Remove", "Your wish list is empty. Right-click an item under Loot and pick \"Add to wish list\".")
  f.wishView.list.onAction = function(e) PR.SetState(e.id, nil) PR.Draw(f) end
  f.xmogView = ListView("Drops from", "Remove", "Your transmog list is empty. Right-click an item under Loot and pick \"Add to transmog list\".")
  f.xmogView.list.onAction = function(e) PR.SetState(e.id, nil) PR.Draw(f) end
  f.ignoreView = ListView("Drops from", "Undo", "You ignore nothing. Right-click an item under Loot, or press \"Ignore this item for good\" on a bid pop-up.")
  f.ignoreView.list.onAction = function(e) PR.SetState(e.id, nil) PR.Draw(f) end
  f.changesView = ListView("Change", "Undo", "No price changes. Right-click an item under Loot and pick \"Change price...\".")
  f.changesView.list.onAction = function(e)
    UI.Confirm("Drop your change to " .. PR.Colored(e.id) .. "?\nThe price in prices.lua counts again.", function()
      PR.UndoPrice(e.id)
      PR.Draw(f)
    end, "Undo price change", "Yes, undo")
  end

  f.view = "loot"
  f.raid = UI.DB().priceRaid or 1
  if f.raid > n then f.raid = 1 end
  f.boss = 1
end

function PR.Draw(f)
  if not f or not f.tabs then return end
  local admin = UI.IsAdmin()
  if f.view == "changes" and not admin then f.view = "loot" end
  local db = PR.DB()
  local nWish, nXmog, nIgnore, nEdits = Count(db.wish), Count(db.xmog), Count(db.ignore), Count(PR.Edits())
  for i = 1, table.getn(VIEWS) do
    local v, b = VIEWS[i], f.tabs[i]
    local label = v.label
    if v.key == "wish" and nWish > 0 then label = label .. "  " .. UI.Paint(C.gold, nWish) end
    if v.key == "xmog" and nXmog > 0 then label = label .. "  " .. UI.Paint(C.gold, nXmog) end
    if v.key == "ignore" and nIgnore > 0 then label = label .. "  " .. UI.Paint(C.gold, nIgnore) end
    if v.key == "changes" and nEdits > 0 then label = label .. "  " .. UI.Paint(C.gold, nEdits) end
    b:SetText(label)
    UI.Pick(b, f.view == v.key)
    if v.admin and not admin then b:Hide() else b:Show() end
  end
  f.popups.Set(db.popups and true or false)
  f.lootView:Hide()
  f.wishView:Hide()
  f.xmogView:Hide()
  f.ignoreView:Hide()
  f.changesView:Hide()
  if f.view == "wish" then
    f.wishView:Show()
    f.wishView.info:SetText("You get a big alert and a bid pop-up when one of these comes up for bids.")
    f.wishView.list:SetItems(Entries(db.wish), true)
  elseif f.view == "xmog" then
    f.xmogView:Show()
    f.xmogView.info:SetText("Items you want for their looks (or a mount, a bag): the bid pop-up says X-Mog Roll and lights up the roll button.")
    f.xmogView.list:SetItems(Entries(db.xmog), true)
  elseif f.view == "ignore" then
    f.ignoreView:Show()
    f.ignoreView.info:SetText("No bid pop-up for these. You can still bid on them in raid chat.")
    f.ignoreView.list:SetItems(Entries(db.ignore), true)
  elseif f.view == "changes" then
    local v = f.changesView
    v:Show()
    v.info:SetText("Prices changed in game. Your copy uses them now. To save them into prices.lua for everyone: log out, run tools\\write_prices.ps1, publish the addon.")
    local edits = PR.Edits()
    local list = Entries(edits)
    for i = 1, table.getn(list) do
      local e, file = edits[list[i].id], PR.filePrice[list[i].id]
      list[i].where = (file and (file[1] .. " -> ") or "new: ") .. UI.Paint(C.gold, e.gp) .. UI.Paint(C.dim, "  " .. tostring(e.by or ""))
    end
    v.list:SetItems(list, true)
  else
    local lv = f.lootView
    lv:Show()
    local raids = PR.Loot().raids
    for i = 1, table.getn(lv.raidButtons) do UI.Pick(lv.raidButtons[i], i == f.raid) end
    local raid = raids[f.raid]
    local rows = {}
    if raid then
      for b = 1, table.getn(raid.bosses) do
        local boss = raid.bosses[b]
        table.insert(rows, { id = b, cells = { boss.name .. UI.Paint(C.dim, "  " .. table.getn(boss.items)) } })
      end
    end
    lv.bosses.selected = f.boss
    lv.bosses:SetRows(rows, true)
    local boss = raid and raid.bosses[f.boss]
    local items = {}
    if boss then
      for i = 1, table.getn(boss.items) do table.insert(items, { id = boss.items[i] }) end
    end
    if f.shownBoss ~= (f.raid .. ":" .. f.boss) then
      f.shownBoss = f.raid .. ":" .. f.boss
      lv.items:SetItems(items)
    else
      lv.items:SetItems(items, true)
    end
    lv.hint:SetText(admin and "Hover: tooltip and GP.  Right-click: wish / transmog / ignore.  Left-click: change the price.  Shift-click: link in chat."
      or "Hover: tooltip and GP.  Right-click: wish / transmog / ignore.  Shift-click: link in chat.")
  end
end

UI.Page{ key = "prices", label = "Prices", after = "home",
  tip = "What every raid item costs in GP, boss by boss. Right-click items for your wish list and ignore list.",
  badge = function() return nil end,
  build = Build,
  refresh = function(f) PR.Draw(f) end,
}

-- ------------------------------------------------------------------ load

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function()
  if arg1 == "shootyepgp" then
    PR.DB()
    PR.ApplyEdits()
  end
end)
