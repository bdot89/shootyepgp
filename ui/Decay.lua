-- shootyepgp :: new window, part 9 - Decay log (officers)
-- The guild leader asked (22 Oct 2026) for a log of every decay: when, which
-- officer, everyone's EP and GP before and after, proof that it went through,
-- and a way to undo the latest one (e.g. a decay given twice by mistake).
--
-- Recording: sepgp.decay_epgp_v3 is wrapped. The guild notes are read just
-- before it runs and every officer note it writes is caught on its way to
-- GuildRosterSetOfficerNote, so "before" and "after" are exactly what the
-- addon read and wrote. A few seconds later the notes are fetched from the
-- server again and compared with "after" (the log's check). Records are kept
-- in sepgp_history[guild].decays, the newest 20.
--
-- Undo gives each member back exactly what the decay took (EP before - EP
-- after, the same for GP) on top of what they have now, so awards given since
-- are kept. Only the newest decay that is not undone can be undone; it is
-- refused when most notes already show their before-decay values, and a
-- record from another officer's copy must follow the decay rule.
--
-- Decays from before this log (the decay lines in the EP / GP history) are
-- listed too, with no before / after: their page checks the GP of everyone
-- whose GP was known just before the decay and has not changed since.
--
-- Officers' copies tell each other on the guild's hidden addon channel, so an
-- officer online at the time can see and undo the decay too. Wire, prefix
-- SEPGPD on GUILD (only officers' copies keep it):
--   DD;id;t,by,pct,minep,basegp,n     a decay (id = time-officer)
--   DM;id;name,epB,gpB,epA,gpA~...    its members (several messages)
--   DK;id;t,ok,missed,other,gone      the check a few seconds after it
--   DU;id;t,by,n                      it was undone

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local H = UI.History
local D = { queue = {}, version = 0 }
UI.Decay = D

local PREFIX = "SEPGPD"
local KEEP = 20            -- records kept per guild
local GAP = 0.5            -- seconds between our messages
local CHECK_AFTER = 4      -- seconds after a decay / undo: fetch the guild notes
local CHECK_WAIT = 10      -- compare when they arrive, or after this long anyway

local function Me() return (sepgp and sepgp._playerName) or UnitName("player") end
local function When(t) return date("%a %d %b %H:%M", t or 0) end

-- EP, GP of an officer note, read the way the addon reads them
local function EPGP(note)
  if not note or note == "" then return nil, nil end
  return sepgp:get_ep_v3(nil, note), sepgp:get_gp_v3(nil, note)
end

function D.Ago(t)
  local d = time() - (t or 0)
  if d < 3600 then return math.max(1, math.floor(d / 60)) .. " min" end
  if d < 172800 then return math.floor(d / 3600) .. " hours" end
  return math.floor(d / 86400) .. " days"
end

-- "Ann, Bob, Cid and 4 more"
local function Names(list, max)
  local out = {}
  for i = 1, math.min(max, table.getn(list)) do out[i] = list[i] end
  local s = table.concat(out, ", ")
  if table.getn(list) > max then s = s .. " and " .. (table.getn(list) - max) .. " more" end
  return s
end

-- ------------------------------------------------------------------ store

-- this guild's records by id, kept with its EP / GP history (sepgp_history)
function D.Store()
  local s = H.Store()
  if not s then return nil end
  if type(s.decays) ~= "table" then s.decays = {} end
  return s.decays
end

-- every record, newest first
function D.List()
  local s, out = D.Store(), {}
  if not s then return out end
  for id, r in pairs(s) do
    if type(r) == "table" and r.t and type(r.m) == "table" then table.insert(out, r) end
  end
  table.sort(out, function(a, b) return a.t > b.t end)
  return out
end

function D.Get(id)
  local s = D.Store()
  return s and id and s[id]
end

local function Put(rec)
  local s = D.Store()
  if not s then return end
  s[rec.id] = rec
  local list = D.List()
  for i = KEEP + 1, table.getn(list) do s[list[i].id] = nil end
  D.version = D.version + 1
end

-- Decay lines in the EP / GP history with no record here (from before this
-- log, or from an officer whose copy sent none), newest first. An hour-late
-- copy of a decay (see H.ParseStamp) is left out.
function D.HistoryOnly(recs)
  local found = {}
  local evs = H.All({ D = 1 })
  for i = 1, table.getn(evs) do
    local e, dup = evs[i], false
    for j = 1, table.getn(recs) do
      if math.abs(recs[j].t - e.t) <= 120 then dup = true end
    end
    for j = 1, table.getn(found) do
      if math.abs(found[j].t - e.t) <= 120 then dup = true end
    end
    if not dup then table.insert(found, e) end
  end
  local out = {}
  for i = 1, table.getn(found) do
    local e, twin = found[i], false
    if not e.by then
      for j = 1, table.getn(found) do
        if found[j].by and math.abs(e.t - 3600 - found[j].t) <= 120 then twin = true end
      end
      for j = 1, table.getn(recs) do
        if math.abs(e.t - 3600 - recs[j].t) <= 120 then twin = true end
      end
    end
    if not twin then table.insert(out, e) end
  end
  return out
end

-- The newest decay that still counts (not undone): { t, by } or nil
function D.Last()
  local recs = D.List()
  local best
  for i = 1, table.getn(recs) do
    if not recs[i].undo then
      best = { t = recs[i].t, by = recs[i].by }
      break
    end
  end
  local hist = D.HistoryOnly(recs)
  if hist[1] and (not best or hist[1].t > best.t) then best = { t = hist[1].t, by = hist[1].by } end
  return best
end

-- ------------------------------------------------------------------ roster

-- The guild notes now, by index and by name ({ i, name, note, ep, gp }), and
-- how many members the client does not show to addons.
function D.ReadRoster()
  local byIndex, byName, seen = {}, {}, 0
  local n = GetNumGuildMembers(1) or 0
  for i = 1, n do
    local name, _, _, _, _, _, _, onote = GetGuildRosterInfo(i)
    if name and name ~= "" then
      seen = seen + 1
      local x = { i = i, name = name, note = onote or "" }
      x.ep, x.gp = EPGP(x.note)
      byIndex[i], byName[name] = x, x
    end
  end
  return byIndex, byName, n - seen
end

-- A decay or undo only reaches the members the client shows to addons. When
-- some are hidden ("Show Offline Members" off, or the list still loading):
-- show them, say so and change nothing this time.
function D.Hidden(what)
  local _, _, missing = D.ReadRoster()
  local off = GetGuildRosterShowOffline and not GetGuildRosterShowOffline() and not D.shownOffline
  if missing <= 0 and not off then return false end
  D.shownOffline = true
  if SetGuildRosterShowOffline then pcall(SetGuildRosterShowOffline, 1) end
  UI.RequestRoster(true)
  UI.Confirm("Offline guild members may be hidden from addons right now (\"Show Offline Members\" is off in the guild window, "
    .. "or the guild list was still loading), so the " .. what .. " could have skipped them.\n\n"
    .. "They are being shown now. Wait a few seconds and press the button again.",
    nil, "Nothing was changed", "OK")
  return true
end

-- ------------------------------------------------------------------ checking

-- One row { name, ep before, gp before, ep after, gp after } against the note
-- now (x from D.ReadRoster, or nil): "same" (the change did nothing there),
-- "after" (as written), "before" (not changed), "other" (changed since), "gone"
function D.State(r, x)
  if r[2] == r[4] and r[3] == r[5] then return "same" end
  if not x or not x.ep or not x.gp then return "gone" end
  if x.ep == r[4] and x.gp == r[5] then return "after" end
  if x.ep == r[2] and x.gp == r[3] then return "before" end
  return "other"
end

function D.Count(rows, byName)
  local c = { same = 0, after = 0, before = 0, other = 0, gone = 0, missed = {} }
  for i = 1, table.getn(rows) do
    local s = D.State(rows[i], byName[rows[i][1]])
    c[s] = c[s] + 1
    if s == "before" then table.insert(c.missed, rows[i][1]) end
  end
  return c
end

-- kind = "decay" or "undo": fetch the notes in a moment, then compare
function D.CheckSoon(id, kind)
  D.check = { id = id, kind = kind, at = GetTime() + CHECK_AFTER }
end

function D.RunCheck(id, kind)
  local rec = D.Get(id)
  if not rec then return end
  local rows = rec.m
  if kind == "undo" then rows = rec.undo and rec.undo.m end
  if not rows then return end
  local _, byName = D.ReadRoster()
  local c = D.Count(rows, byName)
  local res = { t = time(), ok = c.after + c.same, missed = c.before, other = c.other, gone = c.gone }
  if c.before > 0 then res.names = Names(c.missed, 12) end
  if kind == "undo" then
    rec.undo.check = res
  else
    rec.check = res
    table.insert(D.queue, "DK;" .. rec.id .. ";" .. table.concat({ res.t, res.ok, res.missed, res.other, res.gone }, ","))
  end
  D.version = D.version + 1
  local what = (kind == "undo") and "undo" or "decay"
  if c.before == 0 then
    UI.Print("|cff38b86b" .. what .. " checked: all " .. res.ok .. " officer notes show the new EP and GP.|r"
      .. ((c.other + c.gone > 0) and ("  (" .. (c.other + c.gone) .. " changed again since or left the guild)") or ""))
  else
    UI.Print("|cffff5a4d" .. what .. " checked: " .. c.before .. " of " .. table.getn(rows) .. " officer notes did NOT change: "
      .. res.names .. ". See Officer > Decay log.|r")
  end
end

-- ------------------------------------------------------------------ recording

local function Pct() return math.floor((1 - (sepgp_decay or 0.9)) * 1000 + 0.5) / 10 end

-- before = D.ReadRoster() just before the decay, written = { [index] = note }
function D.Record(before, written, pct)
  local t, me = time(), Me()
  local rec = { id = t .. "-" .. me, t = t, by = me, pct = pct, minep = tonumber(sepgp_minep) or 0,
                basegp = sepgp.VARS.basegp, m = {} }
  for i, note in pairs(written) do
    local b = before[i]
    if b and b.ep and b.gp then
      local ep, gp = EPGP(note)
      if ep and gp then table.insert(rec.m, { b.name, b.ep, b.gp, ep, gp }) end
    end
  end
  rec.n = table.getn(rec.m)
  if rec.n == 0 then return end
  table.sort(rec.m, function(a, b) return a[1] < b[1] end)
  Put(rec)
  D.SendRecord(rec)
  D.CheckSoon(rec.id, "decay")
  UI.Print("decay recorded in Officer > Decay log (" .. rec.n .. " members). Checking the officer notes in a few seconds...")
  return rec
end

-- Wrap the addon's decay without changing what it does. Done at load: this
-- file loads after shootyepgp.lua.
local function Wrap()
  if D.wrapped or not (sepgp and sepgp.decay_epgp_v3) then return end
  D.wrapped = true
  local orig = sepgp.decay_epgp_v3
  sepgp.decay_epgp_v3 = function(self)
    local set = GuildRosterSetOfficerNote
    if not CanEditOfficerNote() or type(set) ~= "function" then return orig(self) end
    if D.Hidden("decay") then return end
    local before = D.ReadRoster()
    local pct, written = Pct(), {}
    GuildRosterSetOfficerNote = function(i, note, a3)
      if i then written[i] = note end
      return set(i, note, a3)
    end
    local ok, err = pcall(orig, self)
    GuildRosterSetOfficerNote = set
    local rok, rerr = pcall(D.Record, before, written, pct)
    if not rok then UI.Print("decay log: " .. tostring(rerr)) end
    if not ok then error(err, 0) end
  end
end
Wrap()

-- ------------------------------------------------------------------ undo

-- May this record be undone here? true, or false and why
function D.CanUndo(rec)
  if not rec then return false, "That decay is not in the log." end
  if not UI.IsAdmin() then return false, "Officers only." end
  if rec.undo then return false, "Already undone, " .. When(rec.undo.t) .. " by " .. (rec.undo.by or "?") .. "." end
  if rec.n and table.getn(rec.m) < rec.n then
    return false, "Only " .. table.getn(rec.m) .. " of " .. rec.n .. " members of this decay reached this PC. Undo it on " .. (rec.by or "that officer") .. "'s PC."
  end
  local list = D.List()
  for i = 1, table.getn(list) do
    local o = list[i]
    if o.t > rec.t and not o.undo then
      return false, "A newer decay (" .. When(o.t) .. " by " .. (o.by or "?") .. ") has to be undone first."
    end
  end
  return true
end

-- Does a record follow the decay rule (round(x * (1 - pct)), the minimum EP
-- kept, GP not below the base)? Records from other copies are only trusted
-- that far. Returns ok, members that do not fit.
function D.Fits(rec)
  local f = 1 - (tonumber(rec.pct) or 0) / 100
  local base, floor = tonumber(rec.basegp) or sepgp.VARS.basegp, tonumber(rec.minep) or 0
  local bad = 0
  for i = 1, table.getn(rec.m) do
    local r = rec.m[i]
    local ep = math.floor(r[2] * f + 0.5)
    if floor > 0 and r[2] >= floor then ep = math.max(floor, ep) end
    local gp = math.max(base, math.floor(r[3] * f + 0.5))
    if math.abs(ep - r[4]) > 1 or math.abs(gp - r[5]) > 1 then bad = bad + 1 end
  end
  return bad <= math.floor(table.getn(rec.m) / 10), bad
end

-- Why an undo would be refused right now (nil = fine), and the counts
function D.Refuse(rec)
  local ok, why = D.CanUndo(rec)
  if not ok then return why end
  local fits, bad = D.Fits(rec)
  if not fits then
    return bad .. " of " .. table.getn(rec.m) .. " members in this record do not fit a " .. tostring(rec.pct) .. "% decay, so it is not trusted for an undo."
  end
  local _, byName = D.ReadRoster()
  local c = D.Count(rec.m, byName)
  if c.before > c.after and c.before >= 2 then
    return c.before .. " of " .. (c.before + c.after + c.other) .. " members already have the EP and GP they had before this decay, "
      .. "so it looks undone already (or it never went through)."
  end
  return nil, c, byName
end

function D.Undo(id)
  local rec = D.Get(id)
  local why = D.Refuse(rec)
  if why then UI.Confirm(why .. "\n\nNothing was changed.", nil, "Cannot undo", "OK") return end
  if D.Hidden("undo") then return end
  local _, byName = D.ReadRoster()
  local done, skip = {}, 0
  for i = 1, table.getn(rec.m) do
    local r = rec.m[i]
    local dEP, dGP = r[2] - r[4], r[3] - r[5]
    if dEP ~= 0 or dGP ~= 0 then
      local x = byName[r[1]]
      if x and x.ep and x.gp then
        local ep, gp = x.ep + dEP, x.gp + dGP
        sepgp:update_epgp_v3(ep, gp, x.i, x.name, x.note)
        table.insert(done, { r[1], x.ep, x.gp, ep, gp })
      else
        skip = skip + 1
      end
    end
  end
  local t, me = time(), Me()
  rec.undo = { t = t, by = me, n = table.getn(done), skip = skip, m = done }
  D.version = D.version + 1
  table.insert(D.queue, "DU;" .. rec.id .. ";" .. t .. "," .. me .. "," .. table.getn(done))
  local e = H.Add({ k = "U", t = t, n = rec.pct, by = me })
  if e then H.Send("HE;" .. H.Enc(e)) end
  D.CheckSoon(rec.id, "undo")
  -- then tell the guild, as the decay itself does
  local msg = string.format("Decay of %s (%s%%, by %s) undone: %d members got back the EP and GP it took.",
    date("%d %b %H:%M", rec.t), tostring(rec.pct), rec.by or "?", table.getn(done))
  sepgp:simpleSay(msg)
  if sepgp_saychannel ~= "OFFICER" then sepgp:adminSay(msg) end
  sepgp:addToLog(msg)
  sepgp:refreshPRTablets()
end

-- Members whose note did not change at all: give them the decayed value now.
function D.Finish(id)
  local rec = D.Get(id)
  if not rec or rec.undo or not UI.IsAdmin() then return end
  if D.Hidden("decay") then return end
  local _, byName = D.ReadRoster()
  local names = {}
  for i = 1, table.getn(rec.m) do
    local r = rec.m[i]
    local x = byName[r[1]]
    if D.State(r, x) == "before" then
      sepgp:update_epgp_v3(r[4], r[5], x.i, x.name, x.note)
      table.insert(names, r[1])
    end
  end
  if table.getn(names) == 0 then return end
  rec.finished = { t = time(), by = Me(), n = table.getn(names) }
  D.version = D.version + 1
  local msg = string.format("Decay of %s finished for %d members whose notes had not changed: %s",
    date("%d %b %H:%M", rec.t), table.getn(names), Names(names, 10))
  sepgp:adminSay(string.sub(msg, 1, 240))
  sepgp:addToLog(msg)
  D.CheckSoon(rec.id, "decay")
  sepgp:refreshPRTablets()
end

-- ------------------------------------------------------------------ old decays

-- A decay with no record: everyone whose GP the history knew just before it
-- (a GP award with the new total, after the decay before) and whose GP has
-- not changed since. Rows { name, gp before, known at, expected, gp now, state }
-- with state "after", "before", "twice" (decayed twice) or "other".
function D.Guess(dT, pct)
  H.Index()
  local f = 1 - (tonumber(pct) or 10) / 100
  local base = sepgp.VARS.basegp
  local since = 0
  local marks = H.All({ D = 1, Z = 1 })
  for i = 1, table.getn(marks) do
    local t = marks[i].t
    if t < dT - 120 and t > since then since = t end
  end
  local _, byName = D.ReadRoster()
  local rows = {}
  for name, list in pairs(H.byName or {}) do
    local x = byName[name]
    if x and x.gp then
      local last, known, knownT, later = 0, nil, nil, false
      for i = 1, table.getn(list) do
        local e = list[i]
        if e.k == "G" or (e.k == "L" and (e.n or 0) ~= 0) then
          if e.t > dT + 60 then
            later = true
          elseif e.t < dT - 60 and e.t > since then
            if e.t > last then last = e.t end
            if e.k == "G" and e.gp and (not knownT or e.t > knownT) then known, knownT = e.gp, e.t end
          end
        end
      end
      -- a loot charge a moment before its GP line is the same change
      if known and not later and known > base and knownT >= last - 10 then
        local exp = math.max(base, math.floor(known * f + 0.5))
        local twice = math.max(base, math.floor(exp * f + 0.5))
        local state = "other"
        if x.gp == exp then state = "after" elseif x.gp == known then state = "before" elseif x.gp == twice then state = "twice" end
        table.insert(rows, { name, known, knownT, exp, x.gp, state })
      end
    end
  end
  return rows
end

-- ------------------------------------------------------------------ wire

local function SendNow(msg)
  local ctl = ChatThrottleLib
  if ctl and ctl.SendAddonMessage then
    local ok = pcall(ctl.SendAddonMessage, ctl, "BULK", PREFIX, msg, "GUILD")
    if ok then return end
  end
  pcall(SendAddonMessage, PREFIX, msg, "GUILD")
end

function D.SendRecord(rec)
  if not IsInGuild() then return end
  table.insert(D.queue, "DD;" .. rec.id .. ";" .. table.concat({ rec.t, rec.by, rec.pct, rec.minep, rec.basegp, rec.n }, ","))
  local parts = {}
  for i = 1, table.getn(rec.m) do
    local r = rec.m[i]
    table.insert(parts, r[1] .. "," .. r[2] .. "," .. r[3] .. "," .. r[4] .. "," .. r[5])
  end
  local msgs = H.Pack("DM;" .. rec.id .. ";", parts, "~")
  for i = 1, table.getn(msgs) do table.insert(D.queue, msgs[i]) end
end

-- from another officer's copy; the sender must be the officer who decayed
function D.OnMessage(msg, sender)
  if not sender or sender == Me() or not UI.IsAdmin() then return end
  local _, byName = UI.Roster()
  if byName and next(byName) and not byName[sender] then return end   -- guild members only
  local _, _, op, id, body = string.find(msg or "", "^(D%u);([^;]+);(.*)$")
  if not op then return end
  local _, _, idT, idBy = string.find(id, "^(%d+)%-(.+)$")
  if not idT then return end
  local s = D.Store()
  if not s then return end
  local rec = s[id]
  local f = H.Split(body, ",")
  if op == "DD" or op == "DM" then
    if idBy ~= sender then return end
    if not rec then
      rec = { id = id, t = tonumber(idT), by = idBy, m = {}, from = sender }
      Put(rec)
    end
    if op == "DD" then
      rec.pct, rec.minep, rec.basegp, rec.n = tonumber(f[3] or ""), tonumber(f[4] or ""), tonumber(f[5] or ""), tonumber(f[6] or "")
    else
      local have = {}
      for i = 1, table.getn(rec.m) do have[rec.m[i][1]] = true end
      for p in string.gfind(body, "([^~]+)") do
        local v = H.Split(p, ",")
        local r = { v[1], tonumber(v[2] or ""), tonumber(v[3] or ""), tonumber(v[4] or ""), tonumber(v[5] or "") }
        if r[1] and r[1] ~= "" and r[2] and r[3] and r[4] and r[5] and not have[r[1]] then
          table.insert(rec.m, r)
          have[r[1]] = true
        end
      end
      table.sort(rec.m, function(a, b) return a[1] < b[1] end)
    end
  elseif op == "DK" and rec and idBy == sender then
    rec.check = { t = tonumber(f[1] or ""), ok = tonumber(f[2] or "") or 0, missed = tonumber(f[3] or "") or 0,
                  other = tonumber(f[4] or "") or 0, gone = tonumber(f[5] or "") or 0 }
  elseif op == "DU" and rec and not rec.undo then
    rec.undo = { t = tonumber(f[1] or "") or time(), by = f[2] or sender, n = tonumber(f[3] or "") or 0, heard = sender }
  else
    return
  end
  D.version = D.version + 1
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    if arg1 == PREFIX and arg3 == "GUILD" then pcall(D.OnMessage, arg2, arg4) end
  elseif D.check and D.check.asked and GetTime() > D.check.asked + 0.3 then
    D.check.fresh = D.check.fresh or GetTime()
  end
end)
ev.wait = 0
ev:SetScript("OnUpdate", function()
  local now = GetTime()
  local k = D.check
  if k then
    if not k.asked then
      if now >= k.at then
        k.asked = now
        if GuildRoster then GuildRoster() end
      end
    elseif (k.fresh and now >= k.fresh + 1) or now >= k.asked + CHECK_WAIT then
      D.check = nil
      local ok, err = pcall(D.RunCheck, k.id, k.kind)
      if not ok then UI.Print("decay check: " .. tostring(err)) end
    end
  end
  if table.getn(D.queue) > 0 and now >= ev.wait then
    SendNow(table.remove(D.queue, 1))
    ev.wait = now + GAP
  end
end)

-- ------------------------------------------------------------------ page

local STATE = {
  after = { "decayed", C.on }, before = { "NOT decayed", C.red }, twice = { "decayed twice", C.red },
  other = { "changed since", C.dim }, gone = { "left guild", C.dim }, same = { "at minimum", C.dim },
  back = { "put back", C.gold }, notback = { "NOT put back", C.red },
}
local ORDER = { before = 1, notback = 1, twice = 2, after = 3, back = 3, other = 4, same = 5, gone = 6 }
local DETAIL_COLS = {
  record = { "Name", "EP before", "EP after", "GP before", "GP after", "Now" },
  guess = { "Name", "GP before", "known", "expected", "GP now", "Result" },
}

local function StateText(s)
  local x = STATE[s] or STATE.other
  return UI.Paint(x[2], x[1])
end

local function Member(name)
  local m = UI.byName and UI.byName[name]
  return m and UI.ClassName(name, m.class) or name
end

local function ResultText(rec)
  if rec.undo then
    return UI.Paint(C.gold, "Undone " .. date("%d %b %H:%M", rec.undo.t or 0) .. " by " .. (rec.undo.by or "?"))
  end
  local got, n = table.getn(rec.m), rec.n or table.getn(rec.m)
  if got < n then return UI.Paint(C.dim, "only " .. got .. " of " .. n .. " members reached this PC") end
  if D.check and D.check.id == rec.id then return UI.Paint(C.gold, "checking the officer notes...") end
  local k = rec.check
  if not k then return UI.Paint(C.dim, "not checked - click to see the notes now") end
  if (k.missed or 0) > 0 then return UI.Paint(C.red, k.missed .. " of " .. n .. " officer notes did NOT change") end
  return UI.Paint(C.on, "OK") .. UI.Paint(C.dim, "  -  all " .. (k.ok or n) .. " officer notes changed (checked " .. date("%H:%M", k.t or 0) .. ")")
end

local function BuildList(f)
  local lv = CreateFrame("Frame", nil, f)
  lv:SetAllPoints(f)
  f.lv = lv
  local info = UI.Text(lv, 11, C.dim)
  info:SetPoint("TOPLEFT", lv, "TOPLEFT", 2, -4)
  info:SetWidth(PW - 4)
  info:SetJustifyH("LEFT")
  info:SetText("Every decay: when, which officer, and everyone's EP and GP before and after. Click a decay for the details, a check of the officer notes and Undo.")
  local cols = {
    { key = "t", label = "When", width = 120, sort = true },
    { key = "by", label = "Officer", width = 96, sort = "asc" },
    { key = "pct", label = "Decay", width = 44, align = "RIGHT", sort = true },
    { key = "n", label = "Members", width = 56, align = "RIGHT", sort = true },
    { key = "res", label = "Result", width = 310 },
  }
  local nRows = math.floor((PH - 30 - 24 - 20) / 18)
  local l = UI.List(lv, cols, 18, nRows)
  l:SetPoint("TOPLEFT", lv, "TOPLEFT", 0, -28)
  l:SetWidth(PW)
  l:SetHeight(nRows * 18 + 24)
  l.sortKey, l.sortDesc = "t", true
  l.emptyText = "No decays yet. Every decay from now on is listed here with everyone's EP and GP before and after."
  l.onClick = function(r) UI.pages.decay.open(f, r.id) end
  l.onEnter = function(r, line)
    GameTooltip:SetOwner(line, "ANCHOR_TOP")
    GameTooltip:AddLine(r.title)
    GameTooltip:AddLine(r.tip, 1, 1, 1, 1)
    GameTooltip:AddLine("Click for the details", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end
  lv.list = l
  lv.count = UI.Text(lv, 10, C.dim)
  lv.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
end

local function AskUndo(f)
  local rec = D.Get(f.id)
  local why, c, byName = D.Refuse(rec)
  if why then UI.Confirm(why .. "\n\nNothing was changed.", nil, "Cannot undo", "OK") return end
  local n, ex = 0, ""
  for i = 1, table.getn(rec.m) do
    local r = rec.m[i]
    local x = byName[r[1]]
    if (r[2] ~= r[4] or r[3] ~= r[5]) and x and x.ep and x.gp then
      n = n + 1
      if ex == "" then
        ex = string.format("\ne.g. %s: %d -> %d EP, %d -> %d GP", r[1], x.ep, x.ep + r[2] - r[4], x.gp, x.gp + r[3] - r[5])
      end
    end
  end
  local warn = ""
  local hist = D.HistoryOnly(D.List())
  if hist[1] and hist[1].t > rec.t then
    warn = "\n\n" .. UI.Paint(C.gold, "There is a newer decay with no record here (" .. When(hist[1].t) .. " by " .. (hist[1].by or "?") .. ").")
  end
  UI.Confirm(string.format("Undo the %s%% decay of %s by %s?\n\n%d members get back exactly what it took, on top of what they have now "
      .. "(awards since then are kept).%s\n\nEvery officer note is rewritten, the undo is posted to the guild and logged.",
      tostring(rec.pct), When(rec.t), rec.by or "?", n, ex) .. warn,
    function() UI.Call(function() D.Undo(rec.id) end) end, "Undo this decay?", "Yes, undo it")
end

local function AskFinish(f)
  local rec = D.Get(f.id)
  if not rec then return end
  local _, byName = D.ReadRoster()
  local c = D.Count(rec.m, byName)
  if c.before == 0 then UI.Confirm("Every officer note of this decay changed. Nothing to do.", nil, "Nothing missed", "OK") return end
  UI.Confirm(string.format("%d members still have the EP and GP they had before the decay of %s:\n%s\n\nGive them the decayed values now? Their officer notes are rewritten; officers are told and it is logged.",
      c.before, When(rec.t), Names(c.missed, 12)),
    function() UI.Call(function() D.Finish(rec.id) end) end, "Decay the " .. c.before .. " missed?", "Yes, decay them")
end

local function BuildDetail(f)
  local dv = CreateFrame("Frame", nil, f)
  dv:SetAllPoints(f)
  dv:Hide()
  f.dv = dv
  local back = UI.Button(dv, "< All decays", 100, 20)
  back:SetPoint("TOPLEFT", dv, "TOPLEFT", 0, 0)
  back:SetScript("OnClick", function() UI.pages.decay.open(f, nil) end)
  UI.Tip(back, "Back", "Back to the list of decays.")
  dv.title = UI.Text(dv, 13)
  dv.title:SetPoint("LEFT", back, "RIGHT", 10, 0)
  dv.cols = {
    { key = "name", label = "Name", width = 96, sort = "asc" },
    { key = "a", label = "", width = 54, align = "RIGHT", sort = true },
    { key = "b", label = "", width = 54, align = "RIGHT", sort = true },
    { key = "c", label = "", width = 54, align = "RIGHT", sort = true },
    { key = "d", label = "", width = 54, align = "RIGHT", sort = true },
    { key = "s", label = "", width = 84, sort = "asc" },
  }
  local nRows = math.floor((PH - 30 - 24 - 20) / 18)
  local l = UI.List(dv, dv.cols, 18, nRows)
  l:SetPoint("TOPLEFT", dv, "TOPLEFT", 0, -28)
  l:SetWidth(PW - 214)
  l:SetHeight(nRows * 18 + 24)
  l.sortKey, l.sortDesc = "s", false
  l.onClick = function(r) if UI.byName and UI.byName[r.id] then UI.OpenHistory(r.id) end end
  l.onEnter = function(r, line)
    GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.id)
    for i = 1, table.getn(r.tip) do GameTooltip:AddLine(r.tip[i], 1, 1, 1) end
    GameTooltip:AddLine("Click for " .. r.id .. "'s history", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end
  dv.list = l
  dv.count = UI.Text(dv, 10, C.dim)
  dv.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
  dv.count:SetWidth(PW - 216)
  dv.count:SetJustifyH("LEFT")

  local d = UI.Card(dv, "This decay", 206, PH - 28)
  d:SetPoint("TOPRIGHT", dv, "TOPRIGHT", 0, -28)
  dv.about = UI.Text(d, 11, C.dim)
  dv.about:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -32)
  dv.about:SetWidth(184)
  dv.about:SetJustifyH("LEFT")
  local function B(label, y, fn, tip)
    local b = UI.Button(d, label, 182, 22)
    b:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 12, y)
    b:SetScript("OnClick", fn)
    UI.Tip(b, label, tip)
    return b
  end
  dv.undo = B("Undo this decay", 12, function() AskUndo(f) end,
    "Gives every member back exactly what this decay took, on top of what they have now. Asks first.")
  dv.finish = B("Decay the missed", 40, function() AskFinish(f) end,
    "Members whose officer note did not change get the decayed EP and GP now. Asks first.")
  dv.recheck = B("Check notes now", 68, function()
    UI.RequestRoster(true)
    UI.rosterDirty = true
    UI.Refresh()
  end, "Fetches the newest officer notes from the server and compares them with this decay again.")
end

-- the history-only decay a list row id ("H<time>") stands for
local function HistoryEvent(id)
  local t = tonumber(string.sub(id or "", 2))
  local hist = D.HistoryOnly(D.List())
  for i = 1, table.getn(hist) do
    if hist[i].t == t then return hist[i] end
  end
end

local function Labels(dv, which)
  local names = DETAIL_COLS[which]
  for i = 1, table.getn(dv.cols) do dv.cols[i].label = names[i] end
end

local function FillRecord(f, rec)
  local dv = f.dv
  Labels(dv, "record")
  dv.title:SetText(tostring(rec.pct or "?") .. "% decay  -  " .. date("%a %d %b %Y, %H:%M", rec.t))
  local _, byName = D.ReadRoster()
  local undoBy = {}
  if rec.undo and rec.undo.m then
    for i = 1, table.getn(rec.undo.m) do undoBy[rec.undo.m[i][1]] = rec.undo.m[i] end
  end
  local rows, c = {}, { after = 0, before = 0, other = 0, gone = 0, same = 0, back = 0, notback = 0 }
  local missed = 0
  for i = 1, table.getn(rec.m) do
    local r = rec.m[i]
    local x = byName[r[1]]
    local s = D.State(r, x)
    if rec.undo and undoBy[r[1]] then
      local u = D.State(undoBy[r[1]], x)
      s = (u == "after" and "back") or (u == "before" and "notback") or u
    end
    if s == "before" then missed = missed + 1 end
    c[s] = (c[s] or 0) + 1
    local tip = {
      string.format("EP  %d  ->  %d", r[2], r[4]), string.format("GP  %d  ->  %d", r[3], r[5]),
      string.format("PR  %.3f  ->  %.3f", r[2] / math.max(1, r[3]), r[4] / math.max(1, r[5])),
      (x and x.ep) and string.format("Now  %d EP, %d GP", x.ep, x.gp) or "Not in the guild now",
    }
    table.insert(rows, { id = r[1], tip = tip,
      cells = { Member(r[1]), r[2], r[4], r[3], r[5], StateText(s) },
      sort = { name = r[1], a = r[2], b = r[4], c = r[3], d = r[5], s = ORDER[s] or 9, tie = r[1] } })
  end
  dv.list.emptyText = "No members in this record."
  dv.list:SetRows(rows, true)
  local k = rec.check
  local checked = "not yet"
  if D.check and D.check.id == rec.id then
    checked = "checking..."
  elseif k then
    checked = date("%H:%M", k.t or 0) .. ((k.missed or 0) > 0 and UI.Paint(C.red, ", " .. k.missed .. " did NOT change") or UI.Paint(C.on, ", all changed"))
  end
  local now = (c.after > 0 and (c.after .. " as decayed") or "")
  if rec.undo then now = c.back .. " put back" .. (c.notback > 0 and UI.Paint(C.red, ", " .. c.notback .. " NOT") or "") end
  if c.before > 0 then now = now .. UI.Paint(C.red, ", " .. c.before .. " NOT decayed") end
  if c.other > 0 then now = now .. ", " .. c.other .. " changed since" end
  if c.gone > 0 then now = now .. ", " .. c.gone .. " left" end
  local undone = "no"
  if rec.undo then
    undone = UI.Paint(C.gold, date("%d %b %H:%M", rec.undo.t or 0) .. " by " .. (rec.undo.by or "?")) .. " (" .. (rec.undo.n or 0) .. " members)"
  end
  local from = rec.from and ("\nRecord from " .. rec.from .. "'s copy") or ""
  local got = (rec.n and table.getn(rec.m) < rec.n) and UI.Paint(C.red, "  (only " .. table.getn(rec.m) .. " of " .. rec.n .. " here)") or ""
  dv.about:SetText("|cffffffffDate:|r  " .. date("%A %d %B %Y", rec.t) .. "\n"
    .. "|cffffffffTime:|r  " .. date("%H:%M:%S", rec.t) .. "\n"
    .. "|cffffffffOfficer:|r  " .. (rec.by or "?") .. "\n"
    .. "|cffffffffDecay:|r  " .. tostring(rec.pct or "?") .. "%" .. ((rec.minep or 0) > 0 and ("  (min EP " .. rec.minep .. " kept)") or "") .. "\n"
    .. "|cffffffffMembers:|r  " .. (rec.n or table.getn(rec.m)) .. got .. "\n"
    .. "|cffffffffChecked:|r  " .. checked .. "\n"
    .. "|cffffffffNow:|r  " .. (now ~= "" and now or "-") .. "\n"
    .. "|cffffffffUndone:|r  " .. undone .. from)
  dv.count:SetText(table.getn(rows) .. " members  -  hover a row for PR before and after, click for their history")
  local ok, why = D.CanUndo(rec)
  dv.undo:Show()
  UI.Enable(dv.undo, ok)
  dv.undo.tipText = ok and "Gives every member back exactly what this decay took, on top of what they have now (awards since are kept). Asks first." or why
  if missed > 0 and not rec.undo then
    dv.finish:SetText("Decay the " .. missed .. " missed")
    dv.finish:Show()
  else
    dv.finish:Hide()
  end
  dv.recheck:Show()
end

local function FillGuess(f, e)
  local dv = f.dv
  Labels(dv, "guess")
  dv.title:SetText(tostring(e.n or "?") .. "% decay  -  " .. date("%a %d %b %Y, %H:%M", e.t))
  local list = D.Guess(e.t, e.n)
  local rows, c = {}, { after = 0, before = 0, twice = 0, other = 0 }
  for i = 1, table.getn(list) do
    local g = list[i]
    c[g[6]] = c[g[6]] + 1
    table.insert(rows, { id = g[1],
      tip = { "GP " .. g[2] .. " after the award of " .. date("%d %b %H:%M", g[3]), "A " .. tostring(e.n) .. "% decay makes that " .. g[4], "GP now " .. g[5] },
      cells = { Member(g[1]), g[2], date("%d %b", g[3]), g[4], g[5], StateText(g[6]) },
      sort = { name = g[1], a = g[2], b = g[3], c = g[4], d = g[5], s = ORDER[g[6]] or 9, tie = g[1] } })
  end
  dv.list.emptyText = "Nobody's GP was known just before this decay (no GP awards since the decay before it), or it has changed since."
  dv.list:SetRows(rows, true)
  local verdict
  if table.getn(rows) == 0 then
    verdict = "nothing to compare"
  elseif c.before + c.twice == 0 and c.after > 0 then
    verdict = UI.Paint(C.on, "went through") .. " for all " .. c.after .. " that could be checked"
  else
    verdict = UI.Paint(C.red, (c.before > 0 and (c.before .. " NOT decayed ") or "") .. (c.twice > 0 and (c.twice .. " decayed twice") or ""))
  end
  dv.about:SetText("|cffffffffDate:|r  " .. date("%A %d %B %Y", e.t) .. "\n"
    .. "|cffffffffTime:|r  " .. date("%H:%M:%S", e.t) .. "\n"
    .. "|cffffffffOfficer:|r  " .. (e.by or "?") .. "\n"
    .. "|cffffffffDecay:|r  " .. tostring(e.n or "?") .. "%\n\n"
    .. "This decay is only in the EP / GP history (from before the decay log, or from an officer whose copy sent no record), "
    .. "so there is no before / after for everyone and it cannot be undone here.\n\n"
    .. "|cffffffffGP check:|r  " .. verdict .. ".\n"
    .. c.after .. " decayed, " .. c.before .. " not, " .. c.twice .. " twice, " .. c.other .. " other.")
  dv.count:SetText(table.getn(rows) .. " members whose GP was known just before the decay and has not changed since")
  dv.undo:Hide()
  dv.finish:Hide()
  dv.recheck:Show()
end

UI.Page{ key = "decay", label = "Decay log", after = "officer", parent = "officer", admin = true,
  tip = "Every decay: when, which officer, everyone's EP and GP before and after, a check that the officer notes changed, and Undo. Officers only.",
  build = function(f)
    BuildList(f)
    BuildDetail(f)
  end,
  -- id = a record id or "H<time>" (a decay from the history only), nil = the list
  open = function(f, id)
    f.id = id
    if id then
      f.lv:Hide()
      f.dv:Show()
      UI.pages.decay.fillDetail(f)
    else
      f.dv:Hide()
      f.lv:Show()
      UI.pages.decay.fillList(f)
    end
  end,
  fillList = function(f)
    local recs = D.List()
    local rows = {}
    for i = 1, table.getn(recs) do
      local r = recs[i]
      local n = r.n or table.getn(r.m)
      table.insert(rows, { id = r.id, title = tostring(r.pct or "?") .. "% decay, " .. date("%a %d %b %Y %H:%M:%S", r.t),
        tip = "By " .. (r.by or "?") .. ", " .. n .. " members." .. (r.from and (" Record from " .. r.from .. "'s copy.") or ""),
        cells = { date("%a %d %b %H:%M", r.t), r.by or "?", tostring(r.pct or "?") .. "%", n, ResultText(r) },
        sort = { t = r.t, by = r.by or "", pct = tonumber(r.pct) or 0, n = n, tie = r.id } })
    end
    local hist = D.HistoryOnly(recs)
    for i = 1, math.min(KEEP, table.getn(hist)) do
      local e = hist[i]
      table.insert(rows, { id = "H" .. e.t, title = tostring(e.n or "?") .. "% decay, " .. date("%a %d %b %Y %H:%M:%S", e.t),
        tip = "From the EP / GP history: no before / after here. Click to check the GP of members whose GP was known just before it.",
        cells = { date("%a %d %b %H:%M", e.t), e.by or UI.Paint(C.dim, "?"), tostring(e.n or "?") .. "%", UI.Paint(C.dim, "?"),
                  UI.Paint(C.dim, "in the history only  -  click for a GP check") },
        sort = { t = e.t, by = e.by or "", pct = tonumber(e.n) or 0, n = -1, tie = "H" .. e.t } })
    end
    f.lv.list:SetRows(rows, true)
    local last = D.Last()
    f.lv.count:SetText(table.getn(recs) .. " decays recorded here, " .. table.getn(hist) .. " older ones from the history"
      .. (last and ("  -  last decay " .. D.Ago(last.t) .. " ago") or ""))
  end,
  fillDetail = function(f)
    local id = f.id
    if string.sub(id or "", 1, 1) == "H" then
      local e = HistoryEvent(id)
      if e then FillGuess(f, e) return end
    else
      local rec = D.Get(id)
      if rec then FillRecord(f, rec) return end
    end
    UI.pages.decay.open(f, nil)
  end,
  refresh = function(f)
    H.Seed()
    if f.id then UI.pages.decay.fillDetail(f) else UI.pages.decay.fillList(f) end
  end,
}
