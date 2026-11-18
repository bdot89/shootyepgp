-- shootyepgp :: new window, part 12 - paid loot on item tooltips
-- Guild leader, 18 Nov 2026: hovering a guild member's worn item (inspect
-- screen, or your own character sheet) shows whether they got it in our
-- raids and what they paid:
--     2 x Paid
--     Paid Mainspec 07-07-2027  (175 GP)
--     Paid Offspec 12-08-2027  (43 GP)
-- From the guild's loot history (ui\History.lua, kept and shared by every
-- officer's copy) and sepgp_lootarchive (older loot from the guild website's
-- database, loot_archive.lua by tools\build_lootarchive.ps1). Matched by item id, or by
-- item name when the id differs.

local UI = SEPGP_UI
local C = UI.C
local H = UI.History
local P = {}
UI.PaidLoot = P

local function Label(a, n)
  a = a or ""
  if string.find(a, "^Mainspec") then return "Paid Mainspec" end
  if string.find(a, "^Offspec") then return "Paid Offspec" end
  if string.find(a, "^Xmog") or string.find(a, "[Tt]ransmog") then return "Transmog" end
  if string.find(a, "Bank") or string.find(a, "D/E") then return "Bank / disenchant" end
  if (n or 0) > 0 then return "Paid" end
  return (a ~= "" and a) or "Free"
end

local function ItemInfo(link)
  local _, _, id = string.find(link or "", "item:(%d+)")
  local _, _, nm = string.find(link or "", "%[(.-)%]")
  return tonumber(id), nm
end

-- 18 Nov 2026: tier pieces swapped by a quest for another version (Circlet /
-- Coronet / Crown of Prophecy) count as the one that dropped. Groups come
-- from loot_variants.lua (sepgp_lootvariants, built from AtlasLoot's set
-- pages by tools\build_variants.lua): item id -> its group.
local variantOf
local function Group(id)
  if not variantOf then
    variantOf = {}
    local g = type(sepgp_lootvariants) == "table" and sepgp_lootvariants or {}
    for k = 1, table.getn(g) do
      for j = 1, table.getn(g[k]) do variantOf[g[k][j]] = k end
    end
  end
  return id and variantOf[id]
end
function P.SameItem(a, b)
  if not a or not b then return false end
  if a == b then return true end
  local ga = Group(a)
  return ga ~= nil and ga == Group(b)
end

-- this member's records of the item, oldest first: { t, label, n, other }
-- (other = the name of the version that dropped, when it is not this one)
function P.Records(name, link)
  local id, nm = ItemInfo(link)
  local out = {}
  if not name or (not id and not nm) then return out end
  local function Take(t, a, n, i, inm)
    local same = (id and P.SameItem(id, i)) or (nm and inm and inm == nm)
    -- only what the member paid for: bank / disenchant, transmog and free
    -- items go to the loot master or someone else's look, not to the wearer
    local label = Label(a, n)
    if same and string.find(label, "^Paid") then
      -- the archive (website) and the addon's history overlap from 16 Aug:
      -- the same sale is in both, seconds apart
      local dup = false
      for k = 1, table.getn(out) do
        local o = out[k]
        if o.n == (n or 0) and math.abs(o.t - (t or 0)) < 3 * 3600 then dup = true end
      end
      if not dup then
        local other = (id and i and i ~= id and inm and inm ~= nm) and inm or nil
        table.insert(out, { t = t or 0, label = label, n = n or 0, other = other })
      end
    end
  end
  H.Index()
  local list = H.byName and H.byName[name] or {}
  for i = 1, table.getn(list) do
    local e = list[i]
    if e.k == "L" then Take(e.t, e.a, e.n, e.i, e.nm) end
  end
  local arch = type(sepgp_lootarchive) == "table" and sepgp_lootarchive[name]
  if type(arch) == "table" then
    for i = 1, table.getn(arch) do
      local r = arch[i]   -- { time, item id, item name, action, gp }
      Take(r[1], r[4], r[5], r[2], r[3])
    end
  end
  table.sort(out, function(a, b) return a.t < b.t end)
  return out
end

-- ------------------------------------------------------------------ the box
-- 18 Nov 2026 (guild leader): officers only, a switch in Settings, and a
-- square box of its own so it stands out: a header strip ("PAID 2x", the
-- member), then one row per purchase with a coloured Mainspec / Offspec
-- tag, the date and the GP. It sits beside the tooltip's top right corner
-- (top left when the screen edge is too close), at the tooltip's own
-- scale, and is as wide as its text.

local TAG = { ["Paid Mainspec"] = { "MAINSPEC", C.gold }, ["Paid Offspec"] = { "OFFSPEC", C.accent }, ["Paid"] = { "PAID", C.on } }
local ROW, SUB, HEAD, TAGW, PAD = 16, 12, 20, 60, 8

local function Scale(f)
  local s = f and f.GetEffectiveScale and f:GetEffectiveScale()
  return (type(s) == "number" and s > 0) and s or 1
end

-- right of the tooltip, or left of it when the box would leave the screen
local function Place(b)
  local tip = b.tip
  local right = tip.GetRight and tip:GetRight()
  local screen = (GetScreenWidth and GetScreenWidth() or 0) * Scale(UIParent)
  local side = "R"
  if type(right) == "number" and screen > 0
    and right * Scale(tip) + 2 + (b:GetWidth() or 0) * Scale(b) > screen then side = "L" end
  if side == b.side then return end
  b.side = side
  b:ClearAllPoints()
  if side == "R" then b:SetPoint("TOPLEFT", tip, "TOPRIGHT", 2, 0)
  else b:SetPoint("TOPRIGHT", tip, "TOPLEFT", -2, 0) end
end

function P.Enabled()
  return UI.IsAdmin() and not UI.DB().paidTipsOff
end

local function Build()
  if P.box then return P.box end
  local b = CreateFrame("Frame", "SepgpPaidLootBox", UIParent)
  b:SetFrameStrata("TOOLTIP")
  b:SetClampedToScreen(true)
  UI.Flat(b, C.bg, 0.97, C.gold)
  local head = UI.Fill(b, C.head, 1, "BORDER")
  head:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
  head:SetHeight(HEAD)
  local bar = UI.Fill(b, C.gold, 1, "ARTWORK")
  bar:SetWidth(3)
  bar:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 1, 1)
  b.title = UI.Text(b, 11, C.gold)
  b.title:SetPoint("TOPLEFT", b, "TOPLEFT", 10, -5)
  b.who = UI.Text(b, 10)
  b.who:SetPoint("TOPRIGHT", b, "TOPRIGHT", -PAD, -6)
  b.rows = {}
  -- other tooltip addons may replace GameTooltip's OnHide: never outlive it,
  -- go when the tooltip moves on to another item (bag slot, spell...), and
  -- keep beside it when addons widen it after us
  b:SetScript("OnUpdate", function()
    local tip = this.tip
    if not tip or not tip:IsVisible()
      or (this.line1 and this.line1:GetText() ~= this.first) then
      this:Hide()
      return
    end
    Place(this)
  end)
  b:Hide()
  P.box = b
  return b
end

local function Row(b, k)
  local r = b.rows[k]
  if r then return r end
  r = {}
  r.tagBg = UI.Fill(b, C.btn, 1, "ARTWORK")
  r.tagBg:SetWidth(TAGW)
  r.tagBg:SetHeight(13)
  r.tag = UI.Text(b, 8)
  r.tag:SetPoint("CENTER", r.tagBg, "CENTER", 0, 0)
  r.date = UI.Text(b, 10)
  r.date:SetPoint("LEFT", r.tagBg, "RIGHT", 8, 0)
  r.gp = UI.Text(b, 10, C.gold)
  r.gp:SetPoint("RIGHT", b, "RIGHT", -PAD, 0)
  r.gp:SetPoint("TOP", r.tagBg, "TOP", 0, 0)
  r.sub = UI.Text(b, 9, C.dim)
  b.rows[k] = r
  return r
end

function P.Show(tip, name, link)
  local b = Build()
  b:Hide()
  if not P.Enabled() then return end
  local recs = P.Records(name, link)
  local m = UI.byName and UI.byName[name]
  -- 18 Nov 2026: a guild member's item with no record still gets a small
  -- "NOT PAID" box, so an officer can tell the box is working
  if table.getn(recs) == 0 and not m then return end
  b.who:SetText(m and UI.ClassName(name, m.class) or name)
  local y = -HEAD - 6
  for k = 1, table.getn(b.rows) do
    local r = b.rows[k]
    r.tagBg:Hide() r.tag:Hide() r.date:Hide() r.gp:Hide() r.sub:Hide()
  end
  b.none = b.none or UI.Text(b, 10, C.dim)
  b.none:Hide()
  -- as wide as the widest line (header, rows, quest lines)
  local function SW(fs) return fs:GetStringWidth() or 0 end
  local w = 0
  if table.getn(recs) == 0 then
    b.title:SetText(UI.Paint(C.dim, "NOT PAID"))
    b.none:ClearAllPoints()
    b.none:SetPoint("TOPLEFT", b, "TOPLEFT", 10, y)
    b.none:SetText("No GP paid for this in our raids")
    b.none:Show()
    w = math.max(w, 10 + SW(b.none) + PAD)
    y = y - ROW
  else
    b.title:SetText("PAID  " .. table.getn(recs) .. "x")
  end
  w = math.max(w, 10 + SW(b.title) + 16 + SW(b.who) + PAD)
  for k = 1, table.getn(recs) do
    local rec = recs[k]
    local r = Row(b, k)
    local t = TAG[rec.label] or TAG.Paid
    r.tagBg:ClearAllPoints()
    r.tagBg:SetPoint("TOPLEFT", b, "TOPLEFT", 10, y)
    r.tagBg:SetVertexColor(t[2][1] * 0.35, t[2][2] * 0.35, t[2][3] * 0.35, 1)
    r.tag:SetText(UI.Paint(t[2], t[1]))
    r.date:SetText(date("%d-%m-%Y", rec.t))
    r.gp:SetText(rec.n ~= 0 and (rec.n .. " GP") or "")
    r.tagBg:Show() r.tag:Show() r.date:Show() r.gp:Show()
    w = math.max(w, 10 + TAGW + 8 + SW(r.date) + 16 + SW(r.gp) + PAD)
    y = y - ROW
    if rec.other then
      r.sub:ClearAllPoints()
      r.sub:SetPoint("TOPLEFT", b, "TOPLEFT", 10, y + 2)
      r.sub:SetText("dropped as " .. rec.other .. " (changed by quest)")
      r.sub:Show()
      w = math.max(w, 10 + SW(r.sub) + PAD)
      y = y - SUB
    end
  end
  -- the tooltip's scale, whatever pfUI or other addons set it to
  b:SetScale(Scale(tip) / Scale(UIParent))
  b:SetWidth(math.ceil(math.max(w, 150)))
  b:SetHeight(-y + 4)
  b.tip = tip
  b.side = nil
  Place(b)
  b.line1 = tip.GetName and tip:GetName() and getglobal(tip:GetName() .. "TextLeft1") or nil
  b.first = b.line1 and b.line1:GetText() or nil
  b:Show()
end

-- hover on a worn item: the inspect screen and the character sheet both use
-- GameTooltip:SetInventoryItem(unit, slot)
local orig = GameTooltip.SetInventoryItem
if type(orig) ~= "function" then orig = function() end end
GameTooltip.SetInventoryItem = function(self, unit, slot, a3, a4)
  local r1, r2, r3 = orig(self, unit, slot, a3, a4)
  if P.box then P.box:Hide() end
  if unit and slot and UnitIsPlayer and UnitIsPlayer(unit) then
    pcall(P.Show, self, UnitName(unit), GetInventoryItemLink(unit, slot))
  end
  return r1, r2, r3
end
-- pfUI's inspect skin shows a slot's item from its cache with SetHyperlink
-- when the server sends no link (out of range): the slot button is `this`
local origLink = GameTooltip.SetHyperlink
if type(origLink) ~= "function" then origLink = function() end end
GameTooltip.SetHyperlink = function(self, link, a2, a3)
  local r1, r2, r3 = origLink(self, link, a2, a3)
  if P.box then P.box:Hide() end
  local slot = this
  local unit = InspectFrame and InspectFrame.unit
  if unit and type(slot) == "table" and slot.GetName and string.find(slot:GetName() or "", "^Inspect.+Slot$") then
    local name = UnitName(unit) or (InspectNameText and InspectNameText:GetText())
    if name and type(link) == "string" then pcall(P.Show, self, name, link) end
  end
  return r1, r2, r3
end
-- the box goes with the tooltip
local prevHide = GameTooltip:GetScript("OnHide")
GameTooltip:SetScript("OnHide", function()
  if P.box then P.box:Hide() end
  if prevHide then prevHide() end
end)
