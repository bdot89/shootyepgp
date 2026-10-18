-- shootyepgp :: Raids practice mode (TEMPORARY)
-- Guild leader's wish (18 Oct 2026): a way for officers to try the raid fix
-- (EP / GP to a raid that has already disbanded) and see what officers see,
-- without touching the EP table. While "Practice mode" is on (Raids page,
-- top right, officers only):
--   * a sample raid from three days ago is listed, made of real guild
--     members, next to the real raids;
--   * every fix button works as normal in the window, but NOTHING is written:
--     no officer notes, no officer chat, no log, no guild messages, no
--     history entries. The changes live in memory only and are thrown away
--     when practice mode is switched off or the UI reloads.
--
-- TO REMOVE practice mode: delete this file and the "ui\RaidsPractice.lua"
-- line in shootyepgp.toc. Nothing else needs changing (Raids.lua falls back
-- to the real data when UI.Practice does not exist).

local UI = SEPGP_UI
local C = UI.C
local H = UI.History
local P = { on = false, practice = true, adds = {}, awards = {} }
UI.Practice = P

local SAMPLE_ID = "PRACTICE-SAMPLE"

-- ------------------------------------------------------------------ data

-- A finished Molten Core run three days ago: the top 10 of the standings in
-- the raid, the next 2 on standby; two 100 EP awards.
local function Sample()
  if P.sample then return P.sample end
  UI.Roster()
  local ranked = UI.ranked or {}
  local t0 = time() - 3 * 86400
  local r = { id = SAMPLE_ID, t = t0, last = t0 + 3 * 3600, z = "Molten Core (practice sample)", by = { Practice = true },
              byMain = "Practice", byList = { "Practice sample" }, members = {}, awards = {}, events = {}, nNamed = 0 }
  local raiders = 0
  for i = 1, math.min(12, table.getn(ranked)) do
    local name = ranked[i].name
    local standby = i > 10
    r.members[name] = { name = name, ep = standby and 100 or 200, gp = 0, role = standby and "standby" or "raid" }
    r.nNamed = r.nNamed + 1
    if not standby then raiders = raiders + 1 end
  end
  r.awardList = {
    { t = t0, n = 100, kind = "raid", count = raiders },
    { t = t0 + 3 * 3600, n = 100, kind = "raid", count = raiders },
    { t = t0 + 3 * 3600, n = 100, kind = "standby", count = r.nNamed - raiders },
  }
  -- the list's "EP each" / "Total EP" columns (they showed "nil" without these)
  local each, total = 0, 0
  for name, m in pairs(r.members) do
    if m.ep > each then each = m.ep end
    total = total + m.ep
  end
  r.epEach, r.epTotal = each, total
  P.sample = r
  return r
end

-- a raid with this session's practice changes laid over it (a copy: the
-- real raid objects are never touched)
local function Adjusted(r)
  local adds, extra = P.adds[r.id], P.awards[r.id]
  if not adds and not extra then return r end
  local c = {}
  for k, v in pairs(r) do c[k] = v end
  c.members = {}
  for name, m in pairs(r.members) do c.members[name] = { name = m.name, ep = m.ep, gp = m.gp, role = m.role } end
  for name, d in pairs(adds or {}) do
    local m = c.members[name]
    if m then
      m.ep = m.ep + d.ep
      m.gp = m.gp + d.gp
    end
  end
  c.awardList = {}
  for i = 1, table.getn(r.awardList or {}) do table.insert(c.awardList, r.awardList[i]) end
  for i = 1, table.getn(extra or {}) do table.insert(c.awardList, extra[i]) end
  local each, total = 0, 0
  for name, m in pairs(c.members) do
    if m.ep > each then each = m.ep end
    total = total + m.ep
  end
  c.epEach, c.epTotal = each, total
  return c
end

function P.Raids()
  local list = { Adjusted(Sample()) }
  local real = H.Raids()
  for i = 1, table.getn(real) do table.insert(list, Adjusted(real[i])) end
  table.sort(list, function(a, b) return a.t > b.t end)
  return list
end

function P.RaidById(id)
  if id == SAMPLE_ID then return Adjusted(Sample()) end
  local r = H.RaidById(id)
  return r and Adjusted(r)
end

-- The practice version of H.Fix: remembers the change in memory, nothing else.
function P.Fix(raid, names, n, what)
  if not CanEditOfficerNote() or not raid then return end
  P.adds[raid.id] = P.adds[raid.id] or {}
  for i = 1, table.getn(names) do
    local d = P.adds[raid.id][names[i]] or { ep = 0, gp = 0 }
    if what == "EP" then d.ep = d.ep + n else d.gp = d.gp + n end
    P.adds[raid.id][names[i]] = d
  end
  P.awards[raid.id] = P.awards[raid.id] or {}
  table.insert(P.awards[raid.id], { t = time(), n = n, kind = "practice", gp = (what == "GP"), count = table.getn(names) })
  UI.Print("|cffffc840practice:|r " .. ((n > 0) and "+" or "") .. n .. " " .. what .. " to " .. table.getn(names)
    .. " members - nothing was written or sent.")
end

-- ------------------------------------------------------------------ page

local page = UI.pages.raids

local function Paint(f)
  if not f.practiceSwitch then return end
  local admin = UI.IsAdmin()
  if not admin then P.on = false end
  if admin then
    f.practiceSwitch:Show()
    f.practiceLabel:Show()
  else
    f.practiceSwitch:Hide()
    f.practiceLabel:Hide()
  end
  f.practiceSwitch.Set(P.on)
  -- the banner takes the footer line's place (they overlapped)
  if P.on then
    f.practiceLabel:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    f.practiceBanner:Show()
    f.lv.count:Hide()
    f.rv.count:Hide()
  else
    f.practiceLabel:SetTextColor(C.text[1], C.text[2], C.text[3])
    f.practiceBanner:Hide()
    f.lv.count:Show()
    f.rv.count:Show()
  end
end

local origBuild, origList, origRaid = page.build, page.fillList, page.fillRaid

page.build = function(f)
  origBuild(f)
  local sw = UI.Switch(f)
  sw:SetPoint("TOPRIGHT", f, "TOPRIGHT", -112, -2)
  sw:SetFrameLevel(f:GetFrameLevel() + 10)
  local label = UI.Text(f, 12)
  label:SetPoint("LEFT", sw, "RIGHT", 8, 0)
  label:SetText("Practice mode")
  UI.Tip(sw, "Practice mode", "Try the raid fix buttons on a sample raid (or a real one) without changing anything: no officer notes, chat, log or messages. Switch it off to throw the practice changes away.")
  sw.onToggle = function(v)
    P.on = v and UI.IsAdmin() and true or false
    if not P.on then
      P.adds, P.awards = {}, {}
      if f.raidId == SAMPLE_ID then f.raidId = nil end
    end
    page.open(f, f.raidId)
  end
  f.practiceSwitch, f.practiceLabel = sw, label
  -- a stripe along the bottom while practising
  local b = CreateFrame("Frame", nil, f)
  b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  b:SetHeight(18)
  b:SetFrameLevel(f:GetFrameLevel() + 10)
  UI.Flat(b, { 0.3, 0.22, 0.05 }, 1, C.gold)
  local bt = UI.Text(b, 11, C.gold)
  bt:SetPoint("CENTER", b, "CENTER", 0, 0)
  bt:SetText("PRACTICE MODE  -  changes here are not saved, posted or sent  -  switch it off to throw them away")
  b:Hide()
  f.practiceBanner = b
end

page.fillList = function(f)
  origList(f)
  Paint(f)
end

page.fillRaid = function(f)
  origRaid(f)
  Paint(f)
end
