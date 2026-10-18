-- shootyepgp :: new window, part 5 - shared loot and EP / GP history
-- The guild leader asked (18 Oct 2026) that every member can see loot history
-- and EP / GP history, and click a name to see that player's history.
--
-- The addon itself only writes loot on the loot master's PC (sepgp_looted) and
-- EP / GP lines on officers' PCs (sepgp_log), so a member's copy knows almost
-- nothing about other players. This file keeps one history store per guild
-- (saved variable sepgp_history, account-wide) and fills it from:
--   1. this PC's own sepgp_looted and sepgp_log (read, never changed);
--   2. the addon's own guild broadcasts ("name;EP|GP;amount;newEP;newGP",
--      "ALL;DECAY;pct", "RAID;AWARD;n", "RESERVES;AWARD;n") heard by everyone;
--   3. officers' copies of this file sending what the addon does not send:
--      loot charges and the names in raid / standby awards;
--   4. asking: a member who opens a player's history sends "HQ;Name" and one
--      officer's copy that is online answers with that player's events.
--
-- Wire, prefix SEPGPH on the GUILD addon channel (whispers do not work on this
-- client, see profsync.lua). Events are "k,t,n,ep,gp,item,action,name,itemname":
--   HE;ev~ev~...          new events (officers)
--   HR;t,n,kind;a,b,c     raid / standby EP award n to names a, b, c (officers)
--   HQ;Name   HQ;*        ask for a player's history / the newest guild history
--   HA;Name;ev~ev~...     an answer (others who were about to answer stop)
-- Messages are sent one at a time with a gap, through ChatThrottleLib's BULK
-- queue when one is loaded. The addon's own messages are unchanged.

local UI = SEPGP_UI
local H = { queue = {}, pending = {}, replied = {}, asked = {}, version = 0 }
UI.History = H

local PREFIX = "SEPGPH"
local MAX_MSG = 230          -- addon message limit is 255 with the prefix
local GAP = 0.5              -- seconds between our messages
local MAX_EVENTS = 6000      -- kept per guild; the oldest go first
local REPLY_MAX = 40         -- events per answer
local KINDS = { L = 1, E = 1, G = 1, D = 1, R = 1, Z = 1 }

-- ------------------------------------------------------------------ helpers

local function Split(s, sep)
  local out, pos = {}, 1
  while true do
    local a = string.find(s, sep, pos, true)
    if not a then
      table.insert(out, string.sub(s, pos))
      return out
    end
    table.insert(out, string.sub(s, pos, a - 1))
    pos = a + 1
  end
end
H.Split = Split

local function Plain(s)
  s = tostring(s or "")
  s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")
  s = string.gsub(s, "|r", "")
  return s
end
local function Clean(s, len)
  s = string.gsub(Plain(s), "[,~;|]", " ")
  return string.sub(s, 1, len or 24)
end
H.Plain = Plain

local function Me() return (sepgp and sepgp._playerName) or UnitName("player") end

local MON = { Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6, Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12 }
-- the addon's "Sep/27 18:44:56" (no year) -> epoch seconds, this year or last
function H.ParseStamp(s)
  local _, _, mon, d, hh, mm, ss = string.find(s or "", "(%a+)/(%d+) (%d+):(%d+):(%d+)")
  if not mon or not MON[mon] then return nil end
  local now = time()
  local y = tonumber(date("%Y")) or 2026
  local function At(year)
    local ok, t = pcall(time, { year = year, month = MON[mon], day = tonumber(d), hour = tonumber(hh), min = tonumber(mm), sec = tonumber(ss) })
    if ok and type(t) == "number" then return t end
  end
  local t = At(y)
  if t and t > now + 86400 then t = At(y - 1) end
  return t
end

-- ------------------------------------------------------------------ store

function H.Store()
  local g = GetGuildInfo("player")
  if not g then return nil end
  if type(sepgp_history) ~= "table" then sepgp_history = {} end
  if type(sepgp_history[g]) ~= "table" then sepgp_history[g] = { events = {} } end
  if H.guild ~= g then
    H.guild = g
    H.keys, H.byName = nil, nil
  end
  return sepgp_history[g]
end

local function Key(e, b)
  if e.k == "L" then return "L:" .. (e.w or "") .. ":" .. tostring(e.i or e.nm or "") .. ":" .. b end
  return e.k .. ":" .. (e.w or "") .. ":" .. tostring(e.n or "") .. ":" .. tostring(e.a or "") .. ":" .. b
end

function H.Index()
  local s = H.Store()
  if not s then return end
  if H.keys then return s end
  H.keys, H.byName = {}, {}
  for i = 1, table.getn(s.events) do
    local e = s.events[i]
    H.keys[Key(e, math.floor(e.t / 60))] = e
    if e.w then
      H.byName[e.w] = H.byName[e.w] or {}
      table.insert(H.byName[e.w], e)
    end
  end
  return s
end

-- Add an event; returns the stored event and whether it was new. Events
-- within a minute of an identical one are the same event (heard twice).
function H.Add(e)
  if not e or not e.t or not KINDS[e.k] then return end
  local s = H.Index()
  if not s then return end
  local b = math.floor(e.t / 60)
  for d = -1, 1 do
    local old = H.keys[Key(e, b + d)]
    if old then
      -- a loot entry first seen as "Unassigned" gets its real action later
      if e.k == "L" and e.a and e.a ~= old.a and (not old.a or string.find(old.a, "Unassigned")) then
        old.a, old.n = e.a, e.n
        H.version = H.version + 1
      end
      return old, false
    end
  end
  table.insert(s.events, e)
  H.keys[Key(e, b)] = e
  if e.w then
    H.byName[e.w] = H.byName[e.w] or {}
    table.insert(H.byName[e.w], e)
  end
  if table.getn(s.events) > MAX_EVENTS + 300 then
    table.sort(s.events, function(a, c) return a.t > c.t end)
    for i = table.getn(s.events), MAX_EVENTS + 1, -1 do table.remove(s.events, i) end
    H.keys = nil
  end
  H.version = H.version + 1
  return e, true
end

-- A player's events (with their alts'), newest first.
function H.For(name)
  H.Index()
  local out = {}
  if not H.byName then return out end
  local names = { name }
  local m = UI.byName and UI.byName[name]
  if m and m.alts then
    for i = 1, table.getn(m.alts) do table.insert(names, m.alts[i]) end
  end
  for j = 1, table.getn(names) do
    local l = H.byName[names[j]]
    if l then for i = 1, table.getn(l) do table.insert(out, l[i]) end end
  end
  table.sort(out, function(a, b) return a.t > b.t end)
  return out
end

-- Every event of the given kinds (a set), newest first.
function H.All(kinds)
  local s = H.Index()
  local out = {}
  if not s then return out end
  for i = 1, table.getn(s.events) do
    local e = s.events[i]
    if not kinds or kinds[e.k] then table.insert(out, e) end
  end
  table.sort(out, function(a, b) return a.t > b.t end)
  return out
end

-- ------------------------------------------------------------------ wire

-- fields: k,t,n,ep,gp,item,action,name,itemname,by,zone,raid id
function H.Enc(e)
  return table.concat({ e.k, e.t, e.n or "", e.ep or "", e.gp or "", e.i or "", Clean(e.a, 20), e.w or "", Clean(e.nm, 32),
                        e.by or "", Clean(e.z, 24), e.r or "" }, ",")
end

function H.Dec(s, w)
  local f = Split(s, ",")
  if table.getn(f) < 2 or not KINDS[f[1]] then return nil end
  local e = { k = f[1], t = tonumber(f[2]), n = tonumber(f[3] or ""), ep = tonumber(f[4] or ""), gp = tonumber(f[5] or ""),
              i = tonumber(f[6] or "") }
  if not e.t then return nil end
  if f[7] and f[7] ~= "" then e.a = f[7] end
  if f[8] and f[8] ~= "" then e.w = f[8] else e.w = w end
  if f[9] and f[9] ~= "" then e.nm = f[9] end
  if f[10] and f[10] ~= "" then e.by = f[10] end
  if f[11] and f[11] ~= "" then e.z = f[11] end
  if f[12] and f[12] ~= "" then e.r = f[12] end
  return e
end

-- header;part~part~part... split into messages that fit
function H.Pack(header, parts, sep)
  local msgs, cur = {}, nil
  for i = 1, table.getn(parts) do
    local p = parts[i]
    if cur and string.len(cur) + 1 + string.len(p) > MAX_MSG then
      table.insert(msgs, cur)
      cur = nil
    end
    if cur then cur = cur .. sep .. p else cur = header .. p end
  end
  if cur then table.insert(msgs, cur) end
  return msgs
end

function H.Send(msg)
  table.insert(H.queue, msg)
end
local function SendNow(msg)
  local ctl = ChatThrottleLib
  if ctl and ctl.SendAddonMessage then
    local ok = pcall(ctl.SendAddonMessage, ctl, "BULK", PREFIX, msg, "GUILD")
    if ok then return end
  end
  pcall(SendAddonMessage, PREFIX, msg, "GUILD")
end

-- ------------------------------------------------------------------ sources

-- one sepgp_looted entry: {time, player, player coloured, link, bind, price, offspec price, action}
function H.FromLoot(data, live)
  if type(data) ~= "table" then return end
  local player, link, price, off, action = data[2], data[4], tonumber(data[6]), tonumber(data[7]), data[8]
  if not player or not link then return end
  if player == YOU then player = Me() end
  local _, _, id = string.find(link, "item:(%d+)")
  local _, _, nm = string.find(link, "%[(.-)%]")
  local V = sepgp and sepgp.VARS or {}
  local n = 0
  if action == V.msgp then n = price or 0 elseif action == V.osgp then n = off or 0 end
  local t = live and time() or H.ParseStamp(data[1])
  if not t then return end
  local e, new = H.Add({ k = "L", t = t, w = player, i = tonumber(id), nm = nm, l = link, n = n, a = action and Clean(action, 40) or nil })
  return e, new
end

-- one sepgp_log line (the formats in shootyepgp.lua)
function H.FromLog(stamp, line)
  local t = H.ParseStamp(stamp)
  if not t or not line then return end
  line = Plain(line)
  local _, _, n, who, new
  _, _, n, who, new = string.find(line, "^Awarding (%-?%d+) GP to ([^%s,%.]+).-New: (%-?%d+)")
  if n then return H.Add({ k = "G", t = t, n = tonumber(n), gp = tonumber(new), w = who }) end
  _, _, n, who, new = string.find(line, "^Awarded (%-?%d+) EP to ([^%s,%.]+).-New: (%-?%d+)")
  if n then return H.Add({ k = "E", t = t, n = tonumber(n), ep = tonumber(new), w = who }) end
  _, _, n, who, new = string.find(line, "^(%-%d+) EP Penalty to ([^%s,%.]+).-New: (%-?%d+)")
  if n then return H.Add({ k = "E", t = t, n = tonumber(n), ep = tonumber(new), w = who }) end
  local mine = sepgp_main or Me()
  _, _, n = string.find(line, "^You have been awarded (%d+) EP")
  if n then return H.Add({ k = "E", t = t, n = tonumber(n), w = mine }) end
  _, _, n = string.find(line, "^You have received a (%-%d+) EP penalty")
  if n then return H.Add({ k = "E", t = t, n = tonumber(n), w = mine }) end
  _, _, n = string.find(line, "^You have gained (%d+) GP")
  if n then return H.Add({ k = "G", t = t, n = tonumber(n), w = mine }) end
  _, _, n = string.find(line, "^Giving (%d+) ep to all raidmembers")
  if not n then _, _, n = string.find(line, "^(%d+) EP awarded to Raid") end
  if n then return H.Add({ k = "R", t = t, n = tonumber(n), a = "raid" }) end
  _, _, n = string.find(line, "^Giving (%d+) ep to active reserves")
  if not n then _, _, n = string.find(line, "^(%d+) EP awarded to Reserves") end
  if n then return H.Add({ k = "R", t = t, n = tonumber(n), a = "standby" }) end
  _, _, n = string.find(line, "decayed by ([%d%.]+)%%")
  if not n then _, _, n = string.find(line, "^([%d%.]+)%% decay to EP and GP") end
  if n then return H.Add({ k = "D", t = t, n = tonumber(n) }) end
  if string.find(line, "has been reset to") then return H.Add({ k = "Z", t = t }) end
end

-- this PC's own lists, once per session (the store skips what it has)
function H.Seed()
  if H.seeded or not H.Store() then return end
  H.seeded = true
  local loot = type(sepgp_looted) == "table" and sepgp_looted or {}
  for i = 1, table.getn(loot) do pcall(H.FromLoot, loot[i], false) end
  local log = type(sepgp_log) == "table" and sepgp_log or {}
  for i = 1, table.getn(log) do
    local l = log[i]
    if type(l) == "table" then pcall(H.FromLog, l[1], l[2]) end
  end
end

-- Who gets an award given to this character: the main when alts share EPGP
-- (as sepgp:givename_ep does), with the alts' share of the EP.
local function Receiver(name, n)
  local m = UI.byName and UI.byName[name]
  if sepgp_altspool and m and m.main then
    return m.main, math.floor((sepgp_altpercent or 1) * n + 0.5)
  end
  return name, n
end

-- Names of an award, grouped by amount: { [amount] = { names } }
local function AwardGroups(names, n)
  local groups = {}
  for i = 1, table.getn(names) do
    local who, amount = Receiver(names[i], n)
    groups[amount] = groups[amount] or {}
    table.insert(groups[amount], who)
  end
  return groups
end

-- the addon's guild / raid message, heard from someone or sent by us
function H.FromAddon(msg, sender)
  local f = Split(msg or "", ";")
  local who, what, amount = f[1], f[2], tonumber(f[3] or "")
  if not who or not what or not amount then return end
  local t = time()
  if what == "EP" or what == "GP" then
    if string.find(who, "^%u+$") then return end   -- ALL, RAID... are not names
    H.Add({ k = (what == "EP") and "E" or "G", t = t, n = amount, ep = tonumber(f[4] or ""), gp = tonumber(f[5] or ""), w = who, by = sender })
  elseif who == "ALL" and what == "DECAY" then
    H.Add({ k = "D", t = t, n = amount, by = sender })
  elseif (who == "RAID" or who == "RESERVES") and what == "AWARD" then
    local kind = (who == "RAID") and "raid" or "standby"
    H.Add({ k = "R", t = t, n = amount, a = kind, by = sender })
    -- raid members can tell who was in the raid themselves
    if who == "RAID" and sender ~= Me() and GetNumRaidMembers() > 0 then
      local names = {}
      for i = 1, GetNumRaidMembers() do
        local nm = GetRaidRosterInfo(i)
        if nm then table.insert(names, nm) end
      end
      local z = Clean(GetRealZoneText() or "", 24)
      for amt, list in pairs(AwardGroups(names, amount)) do
        for i = 1, table.getn(list) do H.Add({ k = "E", t = t, n = amt, w = list[i], a = kind, by = sender, z = z }) end
      end
    end
  end
end

-- An award to many names (we are the officer giving it): store it, file it
-- under a raid and tell the guild who got it.
function H.Award(names, n, kind)
  local t = time()
  local zone = Clean(GetRealZoneText() or "", 24)
  local mains = {}
  local groups = AwardGroups(names, n)
  for amt, list in pairs(groups) do
    for i = 1, table.getn(list) do table.insert(mains, list[i]) end
  end
  local rid = H.RaidIdFor(Me(), zone, mains, t, kind)
  for amt, list in pairs(groups) do
    for i = 1, table.getn(list) do H.Add({ k = "E", t = t, n = amt, w = list[i], a = kind, by = Me(), z = zone, r = rid }) end
    local msgs = H.Pack("HR;" .. t .. "," .. amt .. "," .. kind .. "," .. zone .. "," .. rid .. ";", list, ",")
    for i = 1, table.getn(msgs) do H.Send(msgs[i]) end
  end
end

-- ------------------------------------------------------------------ raids
-- A raid = the EP awards one officer gives one group in one zone on one
-- night. Awards carry a raid id (first award's time + officer), chosen by the
-- awarding officer's copy: the same officer, same zone, within 6 hours of
-- that raid's last award and at least half the same people = the same raid;
-- otherwise a new raid. Two groups raiding at the same time have their own
-- officers, so they never mix. Standby EP joins the officer's latest raid
-- within 6 hours. Older awards (no raid id) are grouped the same way here.

local RAID_GAP = 6 * 3600
local RAID_KINDS = { raid = 1, standby = 1, fix = 1 }

local function Overlap(names, members)
  local n, hit = 0, 0
  for i = 1, table.getn(names) do
    n = n + 1
    if members[names[i]] then hit = hit + 1 end
  end
  return n > 0 and hit / n or 0
end

function H.RaidIdFor(by, zone, names, t, kind)
  local raids = H.Raids()
  for i = 1, table.getn(raids) do
    local r = raids[i]
    if not string.find(r.id, "^L") and r.byMain == by and t - r.last <= RAID_GAP and t >= r.t then
      if kind == "standby" then return r.id end
      if (r.z or "") == (zone or "") and Overlap(names, r.members) >= 0.5 then return r.id end
    end
  end
  return t .. "-" .. by
end

local function NewRaid(id, e)
  return { id = id, t = e.t, last = e.t, z = e.z, by = {}, byMain = e.by, members = {}, awards = {}, events = {}, nNamed = 0 }
end

local function AddToRaid(r, e)
  table.insert(r.events, e)
  if e.t < r.t then r.t = e.t end
  if e.t > r.last then r.last = e.t end
  if e.z and not r.z then r.z = e.z end
  if e.by then r.by[e.by] = true end
  if e.k == "R" then
    r.unknown = true
  elseif e.w then
    local m = r.members[e.w]
    if not m then
      m = { name = e.w, ep = 0, gp = 0, role = e.a }
      r.members[e.w] = m
      r.nNamed = r.nNamed + 1
    end
    if e.k == "E" then m.ep = m.ep + (e.n or 0) else m.gp = m.gp + (e.n or 0) end
    if e.a == "raid" then m.role = "raid" end
  end
  -- awards: one line per (minute, kind, amount)
  local ak = math.floor(e.t / 60) .. ":" .. (e.a or e.k) .. ":" .. (e.k) .. ":" .. tostring(e.n or 0)
  local aw = r.awards[ak]
  if not aw then
    aw = { t = e.t, n = e.n or 0, kind = (e.k == "R") and (e.a or "raid") or e.a, gp = (e.k == "G"), count = 0, by = e.by }
    r.awards[ak] = aw
  end
  if e.k ~= "R" then aw.count = aw.count + 1 end
end

-- Every raid, newest first. Cached until the history changes.
function H.Raids()
  if H.raidCache and H.raidCacheV == H.version then return H.raidCache end
  local s = H.Index()
  if not s then return {} end
  local byId, loose, named = {}, {}, {}
  for i = 1, table.getn(s.events) do
    local e = s.events[i]
    if (e.k == "E" or e.k == "G") and RAID_KINDS[e.a or ""] then
      if e.r then
        byId[e.r] = byId[e.r] or NewRaid(e.r, e)
        AddToRaid(byId[e.r], e)
      else
        table.insert(loose, e)
      end
      named[math.floor(e.t / 60)] = true
    end
  end
  -- awards logged without names ("100 EP to the raid") unless the same minute has names
  for i = 1, table.getn(s.events) do
    local e = s.events[i]
    if e.k == "R" then
      local b = math.floor(e.t / 60)
      if not (named[b] or named[b - 1] or named[b + 1]) then table.insert(loose, e) end
    end
  end
  -- older awards: group like the officer's copy would
  table.sort(loose, function(a, b) return a.t < b.t end)
  local open = {}
  for i = 1, table.getn(loose) do
    local e = loose[i]
    local found
    for j = table.getn(open), 1, -1 do
      local r = open[j]
      if (r.byMain or "?") == (e.by or "?") and e.t - r.last <= RAID_GAP then
        if e.k == "R" or r.unknown or (e.a == "standby") or r.members[e.w] or r.nNamed < 3 or e.t - r.last <= 120 then
          found = r
          break
        end
      end
    end
    if not found then
      found = NewRaid("L" .. e.t .. "-" .. (e.by or "?"), e)
      table.insert(open, found)
      byId[found.id] = found
    end
    AddToRaid(found, e)
  end
  local list = {}
  for id, r in pairs(byId) do
    local aw = {}
    for k, a in pairs(r.awards) do table.insert(aw, a) end
    table.sort(aw, function(a, b) return a.t < b.t end)
    r.awardList = aw
    local each, total = 0, 0
    for name, m in pairs(r.members) do
      if m.ep > each then each = m.ep end
      total = total + m.ep
    end
    if r.nNamed == 0 then
      for k = 1, table.getn(aw) do each = each + (aw[k].n or 0) end
    end
    r.epEach, r.epTotal = each, total
    local by = {}
    for name in pairs(r.by) do table.insert(by, name) end
    table.sort(by)
    r.byList = by
    table.insert(list, r)
  end
  table.sort(list, function(a, b) return a.t > b.t end)
  H.raidCache, H.raidCacheV = list, H.version
  return list
end

function H.RaidById(id)
  local raids = H.Raids()
  for i = 1, table.getn(raids) do
    if raids[i].id == id then return raids[i] end
  end
end

-- Officer correction: EP or GP to some or all of a raid's members (e.g. an
-- award that was forgotten). Uses the addon's own note writers quietly, then
-- one summary to officers, the addon log and the guild's history.
function H.Fix(raid, names, n, what)
  if not CanEditOfficerNote() or not raid or table.getn(names) == 0 or not n or n == 0 then return end
  local t = time()
  local parts = {}
  for i = 1, table.getn(names) do
    local name = names[i]
    if what == "EP" then
      sepgp:givename_ep(name, n, true)
    else
      local old = sepgp:get_gp_v3(name) or sepgp.VARS.basegp
      sepgp:update_gp_v3(name, old + n)
    end
    local e = H.Add({ k = (what == "EP") and "E" or "G", t = t, n = n, w = name, a = "fix", by = Me(), z = raid.z, r = raid.id })
    if e then table.insert(parts, H.Enc(e)) end
  end
  local msg = string.format("Raid correction (%s, %s): %s%d %s to %d members: %s", raid.z or "raid", date("%d %b %H:%M", raid.t),
    (n > 0) and "+" or "", n, what, table.getn(names), table.concat(names, ", "))
  sepgp:adminSay(string.sub(msg, 1, 250))
  sepgp:addToLog(msg)
  local msgs = H.Pack("HE;", parts, "~")
  for i = 1, table.getn(msgs) do H.Send(msgs[i]) end
  sepgp:refreshPRTablets()
end

-- answer "HQ;#R": the newest raid awards, one HS line per award group
local function AnswerRaids()
  local raids = H.Raids()
  local sent = 0
  for i = 1, table.getn(raids) do
    local r = raids[i]
    if sent >= 12 then break end
    if not string.find(r.id, "^L") then
      -- regroup this raid's events by (time, amount, kind)
      local groups, order = {}, {}
      for j = 1, table.getn(r.events) do
        local e = r.events[j]
        if e.w then
          local gk = e.k .. ":" .. e.t .. ":" .. tostring(e.n) .. ":" .. (e.a or "") .. ":" .. (e.by or "")
          if not groups[gk] then
            groups[gk] = { e = e, names = {} }
            table.insert(order, gk)
          end
          table.insert(groups[gk].names, e.w)
        end
      end
      for j = 1, table.getn(order) do
        local g = groups[order[j]]
        local e = g.e
        local head = "HS;" .. e.k .. "," .. e.t .. "," .. (e.n or 0) .. "," .. (e.a or "") .. "," .. Clean(e.z, 24) .. "," .. r.id .. "," .. (e.by or "") .. ";"
        local msgs = H.Pack(head, g.names, ",")
        for m = 1, table.getn(msgs) do H.Send(msgs[m]) end
      end
      sent = sent + 1
    end
  end
  H.replied["#R"] = GetTime()
end
H.AnswerRaids = AnswerRaids

-- ------------------------------------------------------------------ asking

-- What we answer with: a player's newest events, or for "*" the newest of
-- the whole guild (loot first).
function H.ForReply(name)
  local list
  if name == "*" then list = H.All() else list = H.For(name) end
  local out = {}
  for i = 1, math.min(REPLY_MAX, table.getn(list)) do table.insert(out, list[i]) end
  return out
end

function H.Ask(name)
  if not name or name == "" then return end
  local now = GetTime()
  if H.asked[name] and now - H.asked[name] < 60 then return end
  H.asked[name] = now
  H.Send("HQ;" .. name)
end

local function Answer(name)
  if name == "#R" then return H.AnswerRaids() end
  local evs = H.ForReply(name)
  if table.getn(evs) == 0 then return end
  local parts = {}
  for i = 1, table.getn(evs) do table.insert(parts, H.Enc(evs[i])) end
  local msgs = H.Pack("HA;" .. name .. ";", parts, "~")
  for i = 1, table.getn(msgs) do H.Send(msgs[i]) end
  H.replied[name] = GetTime()
end

-- Only officers answer (they hold the loot master's and officers' lists);
-- each waits a random moment so that only one of them does.
function H.OnQuery(name, sender)
  if sender == Me() or not UI.IsAdmin() then return end
  if H.replied[name] and GetTime() - H.replied[name] < 30 then return end
  if name == "#R" then
    if table.getn(H.Raids()) == 0 then return end
  elseif table.getn(H.ForReply(name)) == 0 then
    return
  end
  H.pending[name] = GetTime() + 0.4 + math.random() * 2.5
end

-- Messages from our own kind. Accepted from guild members only.
function H.FromOurs(msg, sender)
  if sender == Me() then return end
  if UI.byName and not UI.byName[sender] then return end
  local f = Split(msg or "", ";")
  local op = f[1]
  if op == "HQ" and f[2] then
    H.OnQuery(f[2], sender)
  elseif (op == "HA" or op == "HE") then
    local body, w = f[3], f[2]
    if op == "HE" then body, w = f[2], nil end
    if op == "HA" and w then
      H.pending[w] = nil           -- someone else answered
      H.replied[w] = GetTime()
    end
    if body then
      local evs = Split(body, "~")
      for i = 1, table.getn(evs) do
        local e = H.Dec(evs[i], (w ~= "*") and w or nil)
        if e then e.by = e.by or sender H.Add(e) end
      end
    end
  elseif op == "HR" and f[2] and f[3] then
    -- HR;t,n,kind,zone,raid id;names (an award as it happens)
    local h = Split(f[2], ",")
    local t, n, kind = tonumber(h[1]), tonumber(h[2]), h[3]
    local z, rid = (h[4] ~= "" and h[4]) or nil, (h[5] ~= "" and h[5]) or nil
    if t and n then
      local names = Split(f[3], ",")
      for i = 1, table.getn(names) do
        if names[i] ~= "" then H.Add({ k = "E", t = t, n = n, w = names[i], a = kind, by = sender, z = z, r = rid }) end
      end
    end
  elseif op == "HS" and f[2] and f[3] then
    -- HS;kind,t,n,action,zone,raid id,officer;names (an answer to HQ;#R)
    H.pending["#R"] = nil
    H.replied["#R"] = GetTime()
    local h = Split(f[2], ",")
    local k, t, n = h[1], tonumber(h[2] or ""), tonumber(h[3] or "")
    if (k == "E" or k == "G") and t and n then
      local a, z, rid, by = h[4], h[5], h[6], h[7]
      local names = Split(f[3], ",")
      for i = 1, table.getn(names) do
        if names[i] ~= "" then
          H.Add({ k = k, t = t, n = n, w = names[i], a = (a ~= "" and a) or nil, z = (z ~= "" and z) or nil,
                  r = (rid ~= "" and rid) or nil, by = (by ~= "" and by) or sender })
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ hooks

-- Wrap the addon's functions without changing what they do. Done at load:
-- this file loads after shootyepgp.lua.
local function Wrap()
  if not sepgp or H.wrapped then return end
  if not (sepgp.addonMessage and sepgp.award_raid_ep and sepgp.award_reserve_ep and sepgp.addOrUpdateLoot) then return end
  H.wrapped = true
  local origMsg = sepgp.addonMessage
  sepgp.addonMessage = function(self, message, channel, sender)
    origMsg(self, message, channel, sender)
    pcall(H.FromAddon, message, Me())
  end
  local origRaid = sepgp.award_raid_ep
  sepgp.award_raid_ep = function(self, ep)
    local names = {}
    for i = 1, GetNumRaidMembers() do
      local nm = GetRaidRosterInfo(i)
      if nm then table.insert(names, nm) end
    end
    local before = H.LastLog()
    origRaid(self, ep)
    -- the addon blocks a second raid award within 2 minutes: only record a real one
    if H.LastLog() ~= before then pcall(H.Award, names, tonumber(ep) or 0, "raid") end
  end
  local origRes = sepgp.award_reserve_ep
  sepgp.award_reserve_ep = function(self, ep)
    local names = {}
    local r = sepgp.reserves or {}
    for i = 1, table.getn(r) do table.insert(names, r[i][1]) end
    local before = H.LastLog()
    origRes(self, ep)
    if H.LastLog() ~= before then pcall(H.Award, names, tonumber(ep) or 0, "standby") end
  end
  local origLoot = sepgp.addOrUpdateLoot
  sepgp.addOrUpdateLoot = function(self, data, update)
    origLoot(self, data, update)
    local ok, e = pcall(H.FromLoot, data, true)
    if ok and e and UI.IsAdmin() then H.Send("HE;" .. H.Enc(e)) end
  end
end
function H.LastLog()
  local l = type(sepgp_log) == "table" and sepgp_log or {}
  return l[table.getn(l)]
end
Wrap()

-- ------------------------------------------------------------------ frame

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    if arg1 == PREFIX then
      pcall(H.FromOurs, arg2, arg4)
    elseif sepgp and sepgp.VARS and arg1 == sepgp.VARS.prefix and arg4 ~= Me() then
      pcall(H.FromAddon, arg2, arg4)
    end
  else
    pcall(H.Seed)
  end
end)
f.wait = 0
f:SetScript("OnUpdate", function()
  local now = GetTime()
  for name, due in pairs(H.pending) do
    if now >= due then
      H.pending[name] = nil
      pcall(Answer, name)
    end
  end
  if table.getn(H.queue) > 0 and now >= f.wait then
    SendNow(table.remove(H.queue, 1))
    f.wait = now + GAP
  end
end)

-- ------------------------------------------------------------------ text

local function When(t)
  return date("%d %b %H:%M", t)
end
H.When = When

function H.ItemLink(e)
  if e.l then return e.l end
  if e.i then
    local name, link, q = GetItemInfo(e.i)
    if name and link and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
      return ITEM_QUALITY_COLORS[q].hex .. "|H" .. link .. "|h[" .. name .. "]|h|r"
    end
  end
  return "|cffa335ee[" .. (e.nm or ("item " .. tostring(e.i or "?"))) .. "]|r"
end

-- what an event says, in plain words: text, EP column, GP column
function H.Describe(e)
  local C = UI.C
  if e.k == "L" then
    return H.ItemLink(e) .. UI.Paint(C.dim, "  " .. (e.a or "")), "", (e.n and e.n > 0) and ("+" .. e.n) or ""
  elseif e.k == "E" then
    local what = (e.n or 0) < 0 and UI.Paint(C.red, "EP penalty") or "EP award"
    if e.a == "raid" then what = "Raid EP" elseif e.a == "standby" then what = "Standby EP"
    elseif e.a == "lift" then what = "Lifted to the minimum EP"
    elseif e.a == "fix" then what = UI.Paint(C.gold, "Raid correction") end
    if e.z and e.z ~= "" then what = what .. UI.Paint(C.dim, "  " .. e.z) end
    local amt = (e.n or 0) < 0 and UI.Paint(C.red, tostring(e.n)) or UI.Paint(C.on, "+" .. tostring(e.n or 0))
    return what .. (e.ep and UI.Paint(C.dim, "  (now " .. e.ep .. " EP)") or ""), amt, ""
  elseif e.k == "G" then
    local what = (e.a == "fix") and UI.Paint(C.gold, "GP raid correction") or "GP added"
    local amt = ((e.n or 0) < 0) and tostring(e.n) or ("+" .. tostring(e.n or 0))
    return what .. (e.gp and UI.Paint(C.dim, "  (now " .. e.gp .. " GP)") or ""), "", amt
  elseif e.k == "D" then
    return UI.Paint(C.gold, (e.n or 0) .. "% decay") .. UI.Paint(C.dim, "  (everyone's EP and GP)"), "", ""
  elseif e.k == "R" then
    return "+" .. (e.n or 0) .. " EP to the " .. (e.a or "raid") .. UI.Paint(C.dim, "  (everyone in it)"), "", ""
  elseif e.k == "Z" then
    return UI.Paint(C.red, "EPGP reset") .. UI.Paint(C.dim, "  (everyone)"), "", ""
  end
  return e.k, "", ""
end
