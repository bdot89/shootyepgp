-- shootyepgp :: new window, part 9 - who runs which shootyepgp (officers)
-- The guild leader asked (19 Oct 2026) for a counter in the window's corner:
-- how many online members have this version, and who needs to update (hover).
--
-- Three ways to learn another member's copy, all on the GUILD addon channel:
--   1. every shootyepgp sends "VERSION;<version>;<major>" (prefix SEPGP_PREFIX)
--      when it logs in - heard and kept in sepgp_ui.versions (account-wide);
--   2. copies with this file answer "VQ" with "VA;<version>" (prefix SEPGPV),
--      at most once every 30 s, after a random 0.5-3 s wait;
--   3. every shootyepgp since March 2026 answers "SWOW_Q" with "SWOW_R" (its
--      SuperWoW check in shootyepgp.lua), so an old copy that cannot tell its
--      version still shows it is there.
-- An officer's window asks (VQ + SWOW_Q) when it opens, at most once a minute,
-- and when the counter is clicked.

local UI = SEPGP_UI
local C = UI.C
local V = { version = 0, swow = {} }
UI.Versions = V

local PREFIX = "SEPGPV"
local ANSWER_EVERY = 30
local ASK_EVERY = 60
local WAIT = 6                 -- seconds to wait for answers before "no addon"

-- "10.21.1 <ERROR>" -> 10, 21, 1
function V.Parse(s)
  local _, _, a, b, c = string.find(tostring(s or ""), "(%d+)%.?(%d*)%.?(%d*)")
  if not a then return nil end
  return tonumber(a), tonumber(b) or 0, tonumber(c) or 0
end
-- -1 older, 0 same, 1 newer (nil when either is unknown)
function V.Compare(x, y)
  local a1, b1, c1 = V.Parse(x)
  local a2, b2, c2 = V.Parse(y)
  if not a1 or not a2 then return nil end
  if a1 ~= a2 then return a1 < a2 and -1 or 1 end
  if b1 ~= b2 then return b1 < b2 and -1 or 1 end
  if c1 ~= c2 then return c1 < c2 and -1 or 1 end
  return 0
end

function V.Mine()
  local v = GetAddOnMetadata and GetAddOnMetadata("shootyepgp", "Version") or ""
  local a, b, c = V.Parse(v)
  return a and (a .. "." .. b .. "." .. c) or "?"
end

local function Seen()
  local db = UI.DB()
  if type(db.versions) ~= "table" then db.versions = {} end
  return db.versions
end

function V.Heard(sender, ver, live)
  if not sender or not V.Parse(ver) then return end
  local a, b, c = V.Parse(ver)
  Seen()[sender] = { v = a .. "." .. b .. "." .. c, t = time() }
  if live then V.swow[sender] = GetTime() end   -- a live answer: online with it now
  V.version = V.version + 1
end

-- ------------------------------------------------------------------ asking

function V.Ask(force)
  if not UI.IsAdmin() or not IsInGuild() then return end
  local now = GetTime()
  if not force and V.askedAt and now - V.askedAt < ASK_EVERY then return end
  V.askedAt, V.settled = now, nil
  V.answered = {}
  pcall(SendAddonMessage, PREFIX, "VQ", "GUILD")
  pcall(SendAddonMessage, "SWOW_Q", "1", "GUILD")
  V.version = V.version + 1
end

-- online member -> "current", "old", "newer", "none" or "wait"
function V.Status(name)
  local mine = V.Mine()
  if name == UnitName("player") then return "current", mine end
  local s = Seen()[name]
  local fresh = V.askedAt and V.answered and V.answered[name]
  local cmp = s and V.Compare(s.v, mine)
  if fresh or (s and V.swow[name]) then
    if cmp == 0 then return "current", s.v end
    if cmp == 1 then return "newer", s.v end
    -- answered the SuperWoW ping but not "VQ": a copy older than this file
    return "old", s and s.v
  end
  if V.askedAt and GetTime() - V.askedAt < WAIT then return "wait", s and s.v end
  if not V.askedAt then
    if cmp == 0 then return "current", s.v end
    if s then return (cmp == 1) and "newer" or "old", s.v end
    return "wait"
  end
  return "none", s and s.v
end

function V.Count()
  local roster = UI.Roster()
  local out = { current = {}, old = {}, newer = {}, none = {}, wait = {} }
  for i = 1, table.getn(roster) do
    local m = roster[i]
    if m.online then
      local st, ver = V.Status(m.name)
      table.insert(out[st], { name = m.name, class = m.class, v = ver })
    end
  end
  for _, l in pairs(out) do table.sort(l, function(a, b) return a.name < b.name end) end
  return out
end

-- ------------------------------------------------------------------ comms

local lastAnswer
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function()
  if arg3 ~= "GUILD" or not arg4 then return end
  if arg1 == PREFIX then
    if arg2 == "VQ" then
      if arg4 ~= UnitName("player") and (not lastAnswer or GetTime() - lastAnswer >= ANSWER_EVERY) then
        lastAnswer = GetTime()
        V.answerAt = GetTime() + 0.5 + math.random() * 2.5
      end
    else
      local _, _, ver = string.find(arg2 or "", "^VA;(.+)$")
      if ver then
        if V.answered then V.answered[arg4] = true end
        V.Heard(arg4, ver, true)
      end
    end
  elseif arg1 == "SWOW_R" then
    V.swow[arg4] = GetTime()
    if V.answered then V.answered[arg4] = V.answered[arg4] or false end
    V.version = V.version + 1
  elseif sepgp and sepgp.VARS and arg1 == sepgp.VARS.prefix then
    local _, _, ver = string.find(arg2 or "", "^VERSION;([^;]+)")
    if ver then V.Heard(arg4, ver, true) end
  end
end)
f:SetScript("OnUpdate", function()
  if V.answerAt and GetTime() >= V.answerAt then
    V.answerAt = nil
    pcall(SendAddonMessage, PREFIX, "VA;" .. V.Mine(), "GUILD")
  end
  -- redraw the counter once the answers are in
  if V.askedAt and not V.settled and GetTime() - V.askedAt >= WAIT then
    V.settled = true
    V.version = V.version + 1
  end
end)

-- ------------------------------------------------------------------ counter

local LABEL = { current = "Up to date", newer = "Newer than yours", old = "Needs to update",
                none = "No shootyepgp answering", wait = "Waiting for an answer" }
local ORDER = { "old", "none", "newer", "wait", "current" }

local function Tooltip(b)
  local n = V.Count()
  GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("shootyepgp versions online (yours: " .. V.Mine() .. ")")
  local colour = { current = C.on, newer = C.accent, old = C.red, none = C.dim, wait = C.dim }
  for i = 1, table.getn(ORDER) do
    local key = ORDER[i]
    local l = n[key]
    if table.getn(l) > 0 then
      local col = colour[key]
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(LABEL[key] .. " (" .. table.getn(l) .. ")", col[1], col[2], col[3])
      local shown = 0
      for j = 1, table.getn(l) do
        if key == "current" and shown >= 12 then
          GameTooltip:AddLine("  ...and " .. (table.getn(l) - shown) .. " more", 0.6, 0.6, 0.6)
          break
        end
        local e = l[j]
        local right = e.v and ("v" .. e.v) or ((key == "old") and "older version" or "")
        GameTooltip:AddDoubleLine("  " .. UI.ClassName(e.name, e.class), right, 1, 1, 1, 0.6, 0.6, 0.6)
        shown = shown + 1
      end
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to ask again. \"No shootyepgp answering\" = not installed, switched off, or a copy from before March 2026.", 0.6, 0.6, 0.6, 1)
  GameTooltip:Show()
end

function V.BuildCounter(parent, anchor)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(22)
  b:SetWidth(190)
  b:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
  UI.Hover(b, 0.05)
  local t = UI.Text(b, 11, C.dim)
  t:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  t:SetJustifyH("RIGHT")
  b.text = t
  b:SetScript("OnClick", function()
    V.Ask(true)
    V.Refresh()
    if GameTooltip:IsOwned(this) then Tooltip(this) end
  end)
  b:SetScript("OnEnter", function() Tooltip(this) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  V.counter = b
  b:Hide()
  return b
end

function V.Refresh()
  local b = V.counter
  if not b then return end
  if not UI.IsAdmin() then b:Hide() return end
  b:Show()
  local n = V.Count()
  local up = table.getn(n.current) + table.getn(n.newer)
  local total = up + table.getn(n.old) + table.getn(n.none) + table.getn(n.wait)
  local behind = table.getn(n.old) + table.getn(n.none)
  local col = (table.getn(n.wait) > 0 and C.dim) or (behind > 0 and C.gold) or C.on
  b.text:SetText(UI.Paint(C.dim, "v" .. V.Mine() .. ": ") .. UI.Paint(col, up .. " / " .. total .. " online up to date"))
  b:SetWidth(math.max(120, b.text:GetStringWidth() + 14))
  if GameTooltip:IsOwned(b) then Tooltip(b) end
end
