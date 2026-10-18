--[[---------------------------------------------------------------------------
  profsync.lua — profession / recipe sync for the ERROR guild website

  WHAT IT DOES
  Reports which recipes this character knows to the guild-chat relay character
  ("Gchat"), which forwards them to errorguild.com. The website then shows, per
  recipe, which guild members can craft it.

  HOW IT TALKS
  Everything goes out as a hidden ADDON message on the GUILD channel, never as
  real chat. That matters for three reasons:
    * it never appears in anybody's chat frame, so nobody sees anything;
    * the server tags it LANG_ADDON, which bypasses the chat flood filter, so a
      burst of chunks can never produce "you must wait before sending";
    * the relay is in the guild and already receives these packets (it used to
      discard them), so no extra channel, character or connection is needed.
  Nothing is sent unless the guild roster says the relay is online, so an absent
  relay costs the guild no traffic at all.

  WHEN IT TALKS — the whole point of the design
  It never opens anything and never acts on a timer. The trigger is the player
  opening a profession window themselves, which they have to do to use it:
    * FIRST time a profession is opened, its whole recipe list is sent.
    * Every open after that costs ONE INTEGER COMPARISON — a confirmed
      profession whose window still has the same number of rows cannot have
      changed, so the rows are not walked, nothing is built, nothing is sent.
    * Learn something and the count moves, so the next look sends just the
      delta. Learning with the window open is caught immediately.
    * Skill levels and dropped professions come from the Skills pane, which
      needs no window at all.
  An idle character costs exactly zero messages, and so does a busy one that has
  not learned anything.

  ⚠ THERE IS DELIBERATELY NO AUTOMATIC SCAN. Earlier versions cast the
  profession spell a minute after login to read it unattended. It could not be
  made to work: on this client the cast is answered with "Unknown unit." unless
  it is self-targeted, three UI addons wrap CastSpellByName, the window it opens
  reports "UNKNOWN" until its data arrives, and a window read too early publishes
  a partial list — or an empty one, which once wiped a player's whole catalog.
  Reading the window the player opened has never once failed. Do not add it back.

  NOTHING IS BELIEVED UNTIL THE WEBSITE SAYS SO
  Every batch is parked in `pending` and only written to the SavedVariable when
  an acknowledgement comes back. A dropped packet, an offline relay or a logout
  mid-send therefore means the work is redone later, never that the addon thinks
  it has synced something the website never received.

  WIRE FORMAT (see errorguild_com/api/professions.php for the other end)
      EGPROF <tab> 1:<op>:<part>:<total>:<body>
  out over the GUILD addon channel — see RawSendAddonMessage for why it cannot be
  a whisper on this client — and answered on that same channel by the relay.
  The relay concatenates the bodies of parts 1..total and posts the result. Ops:
      F  <prof>:<rank>:<max>:<k>:<ids>  full recipe set for a profession (replaces)
      A  <prof>:<rank>:<max>:<k>:<ids>  newly learned recipes only (adds)
      X  <prof>                         profession dropped (removes)
      P  <prof>:<rank>:<max>            skill level changed, no recipe change
      M  <prof>:<id>~<icon>~<q>~<name>;… labels the website asked for
  <k> says what the ids ARE: "i" for a trade skill, where the id is the crafted
  item and the website can join its own item metadata onto it, or "e" for a craft
  (enchanting, poisons), where the recipe produces no item and the id is the
  enchant spell instead. It is sent rather than inferred from the profession so
  that a client which moves a profession between the two APIs cannot silently
  file spell ids as item ids.
  and back from the website, via the relay, ALSO on the guild channel:
      K  <player>:<prof>                stored, nothing else needed
      N  <player>:<prof>:<id>,<id>,…    stored, but send me names for these
  The reply carries the player it is for because it is a broadcast, and because
  the relay cannot whisper: OctoWoW blocks whispers from characters below level
  5, and the relay character is a parked level-1. Everyone's addon hears every
  reply and acts only on its own.

  <ids> is compact on purpose. A maxed crafter knows a few hundred recipes and a
  message holds ~240 characters, so a naive "12345,12346,…" would be ten-plus
  messages. Instead the ids are sorted, delta-encoded, and each delta written as
  a base-64 varint carrying 5 data bits per character (the 6th bit means "another
  character follows"). Recipe ids cluster, so most deltas fit in one or two
  characters and a whole profession lands in one or two messages. That beats a
  generic LZW+base64 pass (what ConsumesManager uses for its multi-account sync)
  on this particular data, is a tenth of the code, and needs no bit library —
  which matters, because vanilla's Lua 5.0 has none.

  LUA 5.0 / 1.12 NOTES
  No bit library, no '#', no '%' operator, no string.gmatch. Uses table.getn,
  string.gfind, getglobal, and plain arithmetic for the base conversion.
-----------------------------------------------------------------------------]]

-- Every profession in 1.12 caps at 75 from its very first tier. Used only to
-- keep a same-named class skill line out of the skill-level messages.
local PROF_MIN_CAP = 75

local ADDON_PREFIX = "EGPROF"
local PROTO        = "1"
local GUILD_NAME   = "ERROR"
local RELAY_NAME   = "Gchat"

-- Timing. Nothing here is urgent; every value is picked to stay out of the
-- player's way rather than to be quick.
-- Just enough for guild data and the skill pane to exist; nothing is opened or
-- cast at login any more, so there is nothing to wait for beyond that.
local LOGIN_DELAY      = 15    -- settle time after entering the world
-- One message every 1.5s is comfortably under any per-second chat rule even
-- though addon traffic is exempt from the flood filter, and no batch is urgent:
-- a full first-time sync of a maxed crafter is a handful of messages.
local SEND_SPACING     = 1.5   -- seconds between two outgoing addon messages
local SCAN_SETTLE      = 0.4   -- re-read a window this often until its count stops moving
local WIN_MAX_TRIES    = 15    -- ...for at most this many looks (6s)
local PASSIVE_THROTTLE = 10    -- min seconds between two passive reads of one window
local LEARN_SETTLE     = 12    -- quiet time after the last "you have learned"
local LEARN_MAX_WAIT   = 90    -- ...but never postpone a learn batch longer than this
local RANK_MIN_GAP     = 300   -- min seconds between two skill-level-only messages
local SKILL_DEBOUNCE   = 15    -- settle time after SKILL_LINES_CHANGED
-- ⚠ Expanding or collapsing a skill header FIRES SKILL_LINES_CHANGED — see the
-- warning above ReadSkills. This is how long the addon disbelieves that event
-- after having caused it itself. A genuine skill-up landing inside the window is
-- simply missed, which costs a cosmetic rank line until the next idle sweep.
local SKILL_ECHO_GRACE = 1
local IDLE_CHECK       = 300   -- background skill re-check cadence
local ACK_TIMEOUT      = 60    -- how long a batch may sit unacknowledged
local RETRY_DELAY      = 600   -- pause everything after finding the relay offline
local ROSTER_THROTTLE  = 20    -- min seconds between two GuildRoster() requests
local GATE_CACHE       = 5     -- how long a "can we send" answer stays valid

local MAX_MSG         = 240    -- payload chars (prefix + tab + this must stay < 256)
local CHUNK_BODY      = 224    -- body chars per chunk, leaves room for "1:F:nn:nn:"
local MAX_CHUNKS      = 16     -- a single logical message may never exceed this
local MAX_META        = 6      -- name/icon entries per metadata message
local MAX_META_ROUNDS = 12     -- metadata batches answered per session

--[[ Professions the website tracks.
     skill  — the name in the Skills pane (where the rank comes from)
     window — the name GetTradeSkillLine()/GetCraftName() reports, which is NOT
              always the skill name: Mining's recipe window is "Smelting"
     spell  — the spellbook entry that opens that window
     A profession with no window/spell has no recipes (gathering) and only ever
     reports its skill level. Anything not in this list is ignored entirely, so
     an unknown custom profession is skipped rather than mis-filed.

     Ids 1-13 are the vanilla set. 14 and 15 are OctoWoW/Turtle additions:
     Jewelcrafting (SkillLine 755) and Survival (142) — checked against Turtle's
     own SkillLine data, which adds no other craftable profession. These numbers
     are OUR OWN, not SkillLine.dbc ids; nothing in the client exposes those to
     Lua, so the table would have to be maintained by hand either way.

     ⚠ Which API a profession uses is NOT declared here, and must not be: the
     reader is chosen by whichever event the client fires, so a profession that
     moves between the TradeSkill and Craft frames keeps working. ]]
local PROFS = {
  { id = 1,  skill = "Alchemy",        window = "Alchemy",        spell = "Alchemy"        },
  { id = 2,  skill = "Blacksmithing",  window = "Blacksmithing",  spell = "Blacksmithing"  },
  { id = 3,  skill = "Enchanting",     window = "Enchanting",     spell = "Enchanting"     },
  { id = 4,  skill = "Engineering",    window = "Engineering",    spell = "Engineering"    },
  { id = 5,  skill = "Herbalism"                                                           },
  { id = 6,  skill = "Leatherworking", window = "Leatherworking", spell = "Leatherworking" },
  { id = 7,  skill = "Mining",         window = "Smelting",       spell = "Smelting"       },
  { id = 8,  skill = "Skinning"                                                            },
  { id = 9,  skill = "Tailoring",      window = "Tailoring",      spell = "Tailoring"      },
  { id = 10, skill = "Cooking",        window = "Cooking",        spell = "Cooking"        },
  { id = 14, skill = "Jewelcrafting",  window = "Jewelcrafting",  spell = "Jewelcrafting"  },
  { id = 15, skill = "Survival",       window = "Survival",       spell = "Survival"       },
}
-- Deliberately NOT tracked, though ids 11/12/13 are reserved for them: First Aid
-- and Poisons are things every character has for itself and nobody ever asks a
-- guildmate to make, and Fishing has no recipes at all. The point of this page
-- is "who can make the thing I want", so listing them is noise. Cooking stays
-- because raid food genuinely is requested, and Mining stays because it carries
-- the Smelting recipes (Dark Iron, Elementium), which are a real service.

local PROF_BY_SKILL, PROF_BY_WINDOW, PROF_BY_ID = {}, {}, {}
for i = 1, table.getn(PROFS) do
  local p = PROFS[i]
  PROF_BY_SKILL[p.skill] = p
  PROF_BY_ID[p.id] = p
  if p.window then PROF_BY_WINDOW[p.window] = p end
end

-- ---------------------------------------------------------------------------
-- Runtime state (never saved)
-- ---------------------------------------------------------------------------

local outbox        = {}     -- queued payload strings
local nextSendAt    = 0
local readyAt       = nil    -- end of the post-login grace period
-- Settle state for whichever profession window is open, silent scan or not.
local winSeen       = nil    -- row count seen on the previous look
local winProf       = nil    -- which profession that count belonged to
local winIsCraft    = nil    -- which API the open window belongs to
local winRecheckAt  = nil    -- when to look again for a stable count
local winTries      = 0      -- bounded, so an untracked window stops being polled
local lastPassive   = {}     -- [profId] = GetTime() of the last passive read
local pending       = {}     -- [profId] = batch awaiting acknowledgement
local metaCache     = {}     -- [profId][recipeId] = { n = name, i = icon }
local metaRounds    = 0
local skillsCheckAt = nil    -- debounced SKILL_LINES_CHANGED handler
local skillEchoUntil = nil   -- ignore SKILL_LINES_CHANGED we caused ourselves
local nextIdleCheck = nil
local learnSettleAt = nil    -- debounced "you have learned" burst
local learnFirstAt  = nil    -- start of the current burst, bounds the debounce
local lastRankSend  = {}     -- [profId] = GetTime() of the last skill-level message
local pauseUntil    = nil    -- set when the relay turns out to be offline
local rosterAskedAt = 0
local gateAt, gateOk = 0, false
local reading       = false  -- re-entrancy guard around a window read

-- Counters and the last notable event, for /profsync status. This feature is
-- invisible by design — no chat output, no frames — so without somewhere to look
-- a failure is indistinguishable from "nothing needed doing". Writing a string
-- costs nothing and is never shown unless a human asks.
local statSent, statAcked = 0, 0
local notes = {}
local NOTE_KEEP = 8
-- A single "last thing that happened" freezes whichever moment the player
-- happened to type the command in, which during a multi-profession scan is
-- almost never the interesting one. Keeping the last few turns one status call
-- into the whole story.
local function Note(msg)
  table.insert(notes, msg)
  if table.getn(notes) > NOTE_KEEP then table.remove(notes, 1) end
end

local function Say(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffC8A84EProfession sync:|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Compact id encoding
-- ---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-"

-- One unsigned integer as base-64 characters holding 5 data bits each, most
-- significant first; every character except the last has bit 6 set to mean
-- "keep reading". 0-31 is one character, up to 1023 two, up to 32767 three.
local function EncodeNum(v)
  local digits, n = {}, 0
  repeat
    local q = math.floor(v / 32)
    table.insert(digits, 1, v - q * 32)
    v = q
    n = n + 1
  until v == 0
  local out = ""
  for i = 1, n do
    local d = digits[i]
    if i < n then d = d + 32 end
    out = out .. string.sub(B64, d + 1, d + 1)
  end
  return out
end

-- Sorted ids -> delta-encoded string. The first delta is the id itself, so the
-- decoder just keeps a running total and needs no separate base value.
local function EncodeIds(sorted)
  local parts, prev = {}, 0
  for i = 1, table.getn(sorted) do
    table.insert(parts, EncodeNum(sorted[i] - prev))
    prev = sorted[i]
  end
  return table.concat(parts, "")
end

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function IconName(path)
  if not path or path == "" then return "" end
  return string.lower((string.gsub(path, ".*\\", "")))
end

-- Recipe identity: the crafted item for a trade skill, the enchant spell for a
-- craft (an enchant produces no item, so there is nothing else to key on).
local function IdFromLink(link)
  if not link then return nil end
  local _, _, id = string.find(link, "item:(%d+)")
  if not id then _, _, id = string.find(link, "enchant:(%d+)") end
  if not id then _, _, id = string.find(link, "spell:(%d+)") end
  return id and tonumber(id) or nil
end

-- Rarity, read out of the hyperlink's own colour. There is no GetItemInfo call
-- that works for an item the player has never held, but the tradeskill link is
-- already tinted by the product's quality, so the colour IS the answer. The
-- website has item metadata for only a fraction of what gets crafted, so
-- without this most of the catalog would render as plain white.
local QUALITY_BY_COLOR = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
  ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
}
local function QualityFromLink(link)
  if not link then return -1 end
  local _, _, hex = string.find(link, "|c%x%x(%x%x%x%x%x%x)")
  if not hex then return -1 end
  local q = QUALITY_BY_COLOR[string.lower(hex)]
  return q or -1     -- an enchant link is gold, which is not a rarity
end

local function EditBoxFilled(name)
  local frame = getglobal(name)
  if frame and frame.GetText then
    local t = frame:GetText()
    if t and t ~= "" then return true end
  end
  return false
end

local function BoxChecked(name)
  local frame = getglobal(name)
  if frame and frame.GetChecked and frame:GetChecked() then return true end
  return false
end

local function FrameShown(name)
  local frame = getglobal(name)
  return (frame and frame.IsVisible and frame:IsVisible()) and true or false
end

local function InGuild()
  if not IsInGuild() then return false end
  return GetGuildInfo("player") == GUILD_NAME
end

local function RelayOnline()
  local n = GetNumGuildMembers()
  if not n or n == 0 then return nil end          -- roster not loaded yet
  for i = 1, n do
    local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if name == RELAY_NAME then return (online and true) or false end
  end
  return false
end

-- The single gate every outbound decision passes through. Answering it costs a
-- walk of the guild roster, so the answer is cached for a few seconds.
local function CanSend()
  local now = GetTime()
  if now < gateAt then return gateOk end
  gateAt = now + GATE_CACHE
  gateOk = false

  if not InGuild() then
    Note("not in <" .. GUILD_NAME .. ">")
    return false
  end

  local online = RelayOnline()
  if online == nil then
    -- Nobody has asked the server for the roster yet this session. Ask, and let
    -- the next call decide — this is not an error, just not knowable yet.
    if now - rosterAskedAt > ROSTER_THROTTLE then
      rosterAskedAt = now
      GuildRoster()
    end
    Note("waiting for the guild roster")
    gateAt = now + 1
    return false
  end
  if not online then
    Note(RELAY_NAME .. " is offline")
    pauseUntil = now + RETRY_DELAY
    return false
  end

  gateOk = true
  return true
end

-- ---------------------------------------------------------------------------
-- Saved state
-- ---------------------------------------------------------------------------
-- sepgp_profsync = {
--   v = 1, synced = <initial pass confirmed>,
--   profs = { [profId] = { r, m, full, gone, ids = { [recipeId] = true } } }
-- }
-- r / m are the rank and cap the WEBSITE has confirmed, not the live ones, so a
-- lost message is always noticed on the next comparison.

local function DB()
  if type(sepgp_profsync) ~= "table" then sepgp_profsync = {} end
  local db = sepgp_profsync
  -- ⚠ Bump this after any bug that could have stored WRONG data, not just after
  -- a shape change. v3 also carries a row count per profession (see
  -- OnWindowVisible). v2 discarded everything collected on 2026-08-09, when a
  -- window that had not populated yet could be committed as a confirmed full
  -- set — an alchemist ended up with a confirmed set of nothing, and a cook with
  -- 4 of 50 recipes, neither of which would ever re-scan itself. A full re-scan
  -- costs one message set and is always correct.
  if db.v ~= 3 then
    for k in pairs(db) do db[k] = nil end
    db.v = 3
  end
  if type(db.profs) ~= "table" then db.profs = {} end
  if db.synced == nil then db.synced = false end
  return db
end

local function ProfState(id)
  local db = DB()
  local st = db.profs[id]
  if type(st) ~= "table" then
    st = { r = -1, m = -1, full = false, rows = nil }
    db.profs[id] = st
  end
  if type(st.ids) ~= "table" then st.ids = {} end
  return st
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

-- Split one logical message into wire chunks. `body` is opaque here; the relay
-- glues the bodies back together in order before anything parses them.
local function Send(op, body)
  local len = string.len(body)
  local total = 1
  if len > CHUNK_BODY then total = math.floor((len - 1) / CHUNK_BODY) + 1 end
  if total > MAX_CHUNKS then return end
  if table.getn(outbox) + total > 64 then return end   -- runaway guard
  local pos = 1
  for part = 1, total do
    table.insert(outbox, PROTO .. ":" .. op .. ":" .. part .. ":" .. total .. ":" ..
                 string.sub(body, pos, pos + CHUNK_BODY - 1))
    pos = pos + CHUNK_BODY
  end
end

--[[ ⚠ THE TRANSPORT IS THE GUILD ADDON CHANNEL, NOT A WHISPER.

  A whisper is the obvious choice — point to point, nobody else's client has to
  hear it — and it CANNOT be made to work on this client.

  A normal OctoWoW install ships four copies of ChatThrottleLib (aux-addon,
  Cartographer's AceComm-2.0, Spy's AceComm-3.0, TWLC2). Whichever wins replaces
  the global with a three-argument wrapper:

      SendAddonMessage = function(a1,a2,a3) return Hook_SendAddonMessage(a1,a2,a3) end

  and the whisper target is the fourth argument. A targetless WHISPER addon
  message makes the client throw "Unknown addon chat type". Reaching past the
  hook for the library's captured original is not a fix either, because the
  library is target-blind the whole way down: its own public API is
  `:SendAddonMessage(prio, prefix, text, chattype)` and its despooler calls
  `ORIG_SendAddonMessage(prefix, text, chattype)` — four addons, no target
  anywhere. There is no whisper path through any of them.

  GUILD needs no target, so it survives every one of those hooks untouched, and
  it is what the addon chat channel exists for. The relay is in the guild and
  hears it. Other members' clients receive it too, which is precisely why the
  batching above matters: one member's entire sync is a handful of tiny messages,
  once, and an idle member sends none. The relay still answers by whisper — it
  builds its own packets and no hook is involved on that side.
]]
local function RawSendAddonMessage(prefix, msg)
  local ctl = ChatThrottleLib
  if ctl and ctl.SendAddonMessage then
    -- Use the library properly when it is there. BULK is paced and metered, and
    -- is exactly the priority for something nobody is waiting on.
    local ok = pcall(ctl.SendAddonMessage, ctl, "BULK", prefix, msg, "GUILD")
    if ok then return true end
  end
  -- No library, or its queue refused it: go direct. Still under pcall, because
  -- somebody else's hook must never put an error on screen over a cosmetic sync.
  local ok, err = pcall(SendAddonMessage, prefix, msg, "GUILD")
  if not ok then Note("send failed: " .. tostring(err)) end
  return ok
end

local function FlushOutbox()
  if table.getn(outbox) == 0 then return end
  local now = GetTime()
  if now < nextSendAt then return end
  if not CanSend() then
    -- The relay went away mid-batch. Drop the queue rather than hold it: none of
    -- it was committed, so the same work is rebuilt from scratch next time.
    outbox = {}
    pending = {}
    return
  end
  local payload = table.remove(outbox, 1)
  if string.len(payload) <= MAX_MSG then
    if RawSendAddonMessage(ADDON_PREFIX, payload) then
      statSent = statSent + 1
      Note("sent " .. string.sub(payload, 1, 10) .. " (" .. string.len(payload) .. " chars)")
    else
      -- The send itself blew up, which can only be a third-party hook. Stop for
      -- a while rather than reproduce the failure every 1.5 seconds; nothing was
      -- committed, so the batch is rebuilt later. RawSendAddonMessage has
      -- already recorded what the client actually complained about.
      outbox, pending = {}, {}
      pauseUntil = now + RETRY_DELAY
      return
    end
  end
  nextSendAt = now + SEND_SPACING
end

-- ---------------------------------------------------------------------------
-- Reading the Skills pane
-- ---------------------------------------------------------------------------

-- Skill lines under a collapsed header are not returned at all, so the headers
-- have to be open to read a rank. Expanding is visible if the player has the
-- Skills pane up, so it is skipped while it is — the caller simply retries.
local function ExpandSkillHeaders()
  if FrameShown("SkillFrame") then return nil end
  local collapsed, guard = {}, 0
  while guard < 40 do
    guard = guard + 1
    local found = nil
    for i = 1, GetNumSkillLines() do
      local name, isHeader, isExpanded = GetSkillLineInfo(i)
      if isHeader and not isExpanded then
        found = i
        collapsed[name] = true
        break
      end
    end
    if not found then break end
    ExpandSkillHeader(found)
  end
  return collapsed
end

local function RestoreSkillHeaders(collapsed)
  if not collapsed then return end
  for i = GetNumSkillLines(), 1, -1 do
    local name, isHeader = GetSkillLineInfo(i)
    if isHeader and collapsed[name] then CollapseSkillHeader(i) end
  end
end

local function AnyCollapsedHeader()
  for i = 1, GetNumSkillLines() do
    local _, isHeader, isExpanded = GetSkillLineInfo(i)
    if isHeader and not isExpanded then return true end
  end
  return false
end

-- ⚠ A NAME CAN APPEAR TWICE. "Survival" is both a Turtle profession and a
-- hunter's class skill line, and a hunter sees both in this pane, so the last
-- one read must not win by accident — the higher cap does, which is always the
-- profession. A hunter who does NOT have the profession is caught later and
-- more cheaply: nothing in their spellbook opens it, so it is never scanned
-- and never reported.
--
-- Deliberately no minimum-cap gate here. It would be a second way to tell the
-- two apart, but it is also a single condition that could silently blank every
-- profession on a client whose returns differ, and the spellbook check already
-- covers the case.
local function ScanSkillLines()
  local out = {}
  for i = 1, GetNumSkillLines() do
    local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
    if not isHeader then
      local p = PROF_BY_SKILL[name]
      if p then
        local prev = out[p.id]
        if not prev or (maxRank or 0) > prev.m then
          out[p.id] = { r = rank or 0, m = maxRank or 0 }
        end
      end
    end
  end
  return out
end

--[[ ⚠ EXPANDING A SKILL HEADER IS EXPENSIVE FOR THE WHOLE UI, NOT JUST FOR US.

  ExpandSkillHeader/CollapseSkillHeader fire SKILL_LINES_CHANGED — FrameXML's own
  expand button calls nothing else and relies on that event to redraw the pane —
  and that event goes to EVERY addon. On a normal OctoWoW install it lands on
  pfQuest, whose handler compares the visible skill-line names and, because
  collapsing a header hides its children from GetSkillLineInfo, sees a change
  every single time and runs a full pfDatabase:SearchQuests() quest-giver rebuild;
  and on Cartographer's Professions module, which walks GetNumAddOns() calling
  GetAddOnMetadata on every installed addon.

  Worse, it used to feed itself: this addon listens to SKILL_LINES_CHANGED too,
  so its own expand/collapse re-armed the debounced check, which read the skills
  again, which expanded again — a permanent 15-second cycle of quest-giver
  rebuilds on every guild member, whether or not they ever opened a profession.
  That is what made the whole guild lag (2026-08-09).

  So: the plain read NEVER touches a header, and callers that can live with a
  partial answer ask for one. `mayExpand` is for the rare case where the
  difference actually matters — telling "profession abandoned" apart from
  "profession hidden under a collapsed header" — and it brackets the mutation in
  skillEchoUntil so our own echo is not mistaken for a real skill change.

  Returns skills, complete. `complete` false means a collapsed header may be
  hiding professions, so a MISSING one proves nothing. ]]
local function ReadSkills(mayExpand)
  local skills = ScanSkillLines()
  if not AnyCollapsedHeader() then return skills, true end
  if not mayExpand then return skills, false end

  skillEchoUntil = GetTime() + SKILL_ECHO_GRACE
  local restore = ExpandSkillHeaders()      -- nil when the Skills pane is open
  if not restore then return skills, false end
  skills = ScanSkillLines()
  RestoreSkillHeaders(restore)
  skillEchoUntil = GetTime() + SKILL_ECHO_GRACE
  return skills, true
end

-- ---------------------------------------------------------------------------
-- Reading an open profession window
-- ---------------------------------------------------------------------------

local function RememberMeta(profId, recipeId, name, icon, quality)
  if not name or name == "" then return end
  if not metaCache[profId] then metaCache[profId] = {} end
  metaCache[profId][recipeId] = { n = name, i = IconName(icon), q = quality or -1 }
end

-- A filtered window shows a subset, which would read as "this player forgot half
-- their recipes". Such a read is still used — but only ever to ADD recipes,
-- never to replace the stored set.
local function TradeSkillClean(anyCollapsed)
  if EditBoxFilled("TradeSkillFrameEditBox") then return false end
  if EditBoxFilled("TradeSkillFrameSearchBox") then return false end
  if BoxChecked("TradeSkillFrameMatsCheckButton") then return false end
  if BoxChecked("TradeSkillMatsCheckButton") then return false end
  if BoxChecked("TradeSkillFrameAvailableFilterCheckButton") then return false end
  if BoxChecked("TradeSkillFrameSkillCheckButton") then return false end
  if BoxChecked("TradeSkillSkillCheckButton") then return false end
  -- Collapsed headers are spotted by the read loop, which is already visiting
  -- every row; a second pass here would double the cost of every open.
  return not anyCollapsed
end

local function CraftClean(anyCollapsed)
  if EditBoxFilled("CraftFrameEditBox") then return false end
  if EditBoxFilled("CraftFrameSearchBox") then return false end
  if BoxChecked("CraftFrameMatsCheckButton") then return false end
  if BoxChecked("CraftMatsCheckButton") then return false end
  if BoxChecked("CraftFrameAvailableFilterCheckButton") then return false end
  if BoxChecked("CraftFrameSkillCheckButton") then return false end
  if BoxChecked("CraftSkillCheckButton") then return false end
  return not anyCollapsed
end

-- Only ever called for a window this addon opened itself, so reorganising it is
-- safe: the player never sees it.
local function ExpandTradeSkillHeaders()
  if not ExpandTradeSkillSubClass then return end
  ExpandTradeSkillSubClass(0)
  local guard = 0
  while guard < 40 do
    guard = guard + 1
    local found = nil
    for i = 1, GetNumTradeSkills() do
      local _, skillType, _, isExpanded = GetTradeSkillInfo(i)
      if skillType == "header" and not isExpanded then found = i break end
    end
    if not found then break end
    ExpandTradeSkillSubClass(found)
  end
end

local function ExpandCraftHeaders()
  if not ExpandCraftSubClass then return end
  ExpandCraftSubClass(0)
  local guard = 0
  while guard < 40 do
    guard = guard + 1
    local found = nil
    for i = 1, GetNumCrafts() do
      local _, _, craftType, _, isExpanded = GetCraftInfo(i)
      if craftType == "header" and not isExpanded then found = i break end
    end
    if not found then break end
    ExpandCraftSubClass(found)
  end
end

-- Returns prof, sorted ids, clean — or nil when the open window belongs to
-- something not tracked (Beast Training, a custom profession, ...).
local function ReadTradeSkill(mayMutate)
  local line = GetTradeSkillLine()
  local prof = line and PROF_BY_WINDOW[line]
  if not prof then return nil end
  if mayMutate then ExpandTradeSkillHeaders() end

  -- What actually separates a recipe from a category header is that a header
  -- has no product, so the LINK decides. Testing skillType is only a hint here:
  -- if a client ever returns it in a different slot the link test still holds,
  -- whereas requiring skillType to be a non-nil string would silently skip
  -- every row.
  local rows = GetNumTradeSkills()
  local ids, seen, collapsed = {}, {}, false
  for i = 1, rows do
    local name, skillType, _, isExpanded = GetTradeSkillInfo(i)
    if skillType == "header" then
      if not isExpanded then collapsed = true end
    elseif name then
      local link = GetTradeSkillItemLink(i)
      local id = IdFromLink(link)
      if id and not seen[id] then
        seen[id] = true
        table.insert(ids, id)
        RememberMeta(prof.id, id, name, GetTradeSkillIcon(i), QualityFromLink(link))
      end
    end
  end
  table.sort(ids)
  Note("read " .. prof.skill .. ": " .. table.getn(ids) .. " of " .. rows .. " rows")
  return prof, ids, TradeSkillClean(collapsed), "i"
end

local function ReadCraft(mayMutate)
  -- Which craft is open is asked two ways: the display skill line is the right
  -- answer, but not every 1.12-derived client exposes it, and the craft's own
  -- name is the same string for everything this addon tracks.
  local line = nil
  if GetCraftDisplaySkillLine then line = GetCraftDisplaySkillLine() end
  if (not line or line == "") and GetCraftName then line = GetCraftName() end
  local prof = line and PROF_BY_WINDOW[line]
  if not prof then return nil end
  if mayMutate then ExpandCraftHeaders() end

  local rows = GetNumCrafts()
  local ids, seen, collapsed = {}, {}, false
  for i = 1, rows do
    local name, _, craftType, _, isExpanded = GetCraftInfo(i)
    if craftType == "header" then
      if not isExpanded then collapsed = true end
    elseif name then
      local link = GetCraftItemLink(i)
      local id = IdFromLink(link)
      if id and not seen[id] then
        seen[id] = true
        table.insert(ids, id)
        RememberMeta(prof.id, id, name, GetCraftIcon(i), QualityFromLink(link))
      end
    end
  end
  table.sort(ids)
  Note("read " .. prof.skill .. ": " .. table.getn(ids) .. " of " .. rows .. " rows")
  return prof, ids, CraftClean(collapsed), "e"
end

-- ---------------------------------------------------------------------------
-- Turning a read into messages
-- ---------------------------------------------------------------------------

-- A skill-level-only message. Levelling a profession with the window open fires
-- an update per craft, so without this the player would emit one whisper every
-- few seconds for an hour. Suppressing one costs nothing: state.r is only
-- written when the website confirms, so the difference is still pending and the
-- next check sends the CURRENT level rather than the one that was skipped.
local function SendRank(profId, rank, max)
  local now = GetTime()
  if lastRankSend[profId] and (now - lastRankSend[profId]) < RANK_MIN_GAP then return end
  lastRankSend[profId] = now
  pending[profId] = { r = rank, m = max, at = now }
  Send("P", profId .. ":" .. rank .. ":" .. max)
end

local function Report(prof, ids, clean, kind, rank, max)
  if not CanSend() then return end
  -- ⚠ An empty read is never news. A profession window always holds at least one
  -- recipe, so zero rows means the window was not readable — and sending that as
  -- a full sync tells the website to delete everything it knows. Same rule the
  -- bank stock sweep learned: a report of nothing is a bad read, not an empty
  -- inventory.
  if table.getn(ids) == 0 then
    Note("ignoring empty read of " .. prof.skill)
    return
  end
  local state = ProfState(prof.id)

  local fresh = {}
  for i = 1, table.getn(ids) do
    if not state.ids[ids[i]] then table.insert(fresh, ids[i]) end
  end
  local freshCount = table.getn(fresh)
  local isFull = (clean and true or false)
  local rankChanged = (state.r ~= rank or state.m ~= max)

  if not isFull then
    -- A possibly filtered read may only add: recipes are never unlearned in
    -- 1.12, so "I did not see it" is never evidence that it is gone.
    if freshCount == 0 then
      if rankChanged then SendRank(prof.id, rank, max) end
      return
    end
    pending[prof.id] = { ids = ids, full = false, rows = winSeen, r = rank, m = max, at = GetTime() }
    Send("A", prof.id .. ":" .. rank .. ":" .. max .. ":" .. kind .. ":" .. EncodeIds(fresh))
    return
  end

  -- A clean read is authoritative and MAY replace the stored set — but doing so
  -- every time would mean re-sending a whole profession after learning one
  -- recipe. Once a full set has been confirmed, the only thing that can differ
  -- is an addition (1.12 has no way to unlearn a recipe, and abandoning the
  -- profession sends X instead), so the delta says everything the replace would.
  -- The replace is kept for the first sync, and for the one case that proves the
  -- stored set is wrong: a clean read that is MISSING something we think we have.
  local stale = false
  if state.full then
    local seen = {}
    for i = 1, table.getn(ids) do seen[ids[i]] = true end
    for id in pairs(state.ids) do
      if not seen[id] then stale = true break end
    end
  end

  if state.full and not stale then
    if freshCount == 0 then
      if rankChanged then SendRank(prof.id, rank, max) end
      return
    end
    pending[prof.id] = { ids = ids, full = false, rows = winSeen, r = rank, m = max, at = GetTime() }
    Send("A", prof.id .. ":" .. rank .. ":" .. max .. ":" .. kind .. ":" .. EncodeIds(fresh))
    return
  end

  pending[prof.id] = { ids = ids, full = true, rows = winSeen, r = rank, m = max, at = GetTime() }
  Send("F", prof.id .. ":" .. rank .. ":" .. max .. ":" .. kind .. ":" .. EncodeIds(ids))
end

-- ---------------------------------------------------------------------------
-- Profession set: additions, drops and rank changes
-- ---------------------------------------------------------------------------

local function CheckSkills()
  if not CanSend() then return end
  local skills, complete = ReadSkills(false)
  local db = DB()

  -- ⚠ Only pay for a header expand when a profession we ALREADY KNOW ABOUT has
  -- vanished from the read, because that is the single decision a partial read
  -- cannot make (see ReadSkills for what an expand costs the rest of the UI). A
  -- rank read off a visible line is trustworthy on its own, and a BRAND NEW
  -- profession hidden under a collapsed header is not worth an expand either:
  -- opening its window is the only way to use it, and that reports the rank
  -- alongside the recipes.
  if not complete then
    local suspect = false
    for id in pairs(db.profs) do
      if PROF_BY_ID[id] and not skills[id] then suspect = true break end
    end
    if suspect then
      local full, ok = ReadSkills(true)
      if not ok then
        skillsCheckAt = GetTime() + SKILL_DEBOUNCE   -- Skills pane open, come back
        return
      end
      skills, complete = full, ok
    end
  end

  -- Gone from the pane means abandoned. The row is kept, flagged, and only
  -- deleted once the website confirms — otherwise a lost "dropped" message
  -- would leave the site advertising recipes the player no longer has.
  for id, state in pairs(db.profs) do
    if not PROF_BY_ID[id] then
      -- Not tracked any more (First Aid, Fishing and Poisons were dropped from
      -- the list). Telling the website about it is pointless — it does not know
      -- the id either, so it cannot acknowledge, and the message repeats
      -- forever. Just forget it locally.
      db.profs[id] = nil
      pending[id] = nil
    elseif not skills[id] then
      -- Belt and braces: the suspect check above should have upgraded the read
      -- to a complete one before we get here. Never announce a drop off a read
      -- that a collapsed header could have censored.
      if complete and (not state.gone or not pending[id]) then
        state.gone = true
        pending[id] = { drop = true, at = GetTime() }
        Send("X", tostring(id))
      end
    elseif state.gone then
      state.gone = nil    -- re-learned before the drop was ever confirmed
    end
  end

  for id, info in pairs(skills) do
    local prof = PROF_BY_ID[id]
    local state = ProfState(id)

    -- ⚠ These two are INDEPENDENT, and used not to be. Chaining them behind an
    -- elseif meant a profession whose recipe scan had not succeeded never
    -- reported its skill level either — so a miner with a failing Smelting scan
    -- was completely absent from the site rather than merely missing recipes.
    -- The rank comes free from the Skills pane and is worth having on its own.
    -- ⚠ Only a plausible cap gets a rank line. Every real profession is capped
    -- at 75 or more from its first tier, and a class skill line that merely
    -- shares a profession's name (a hunter's "Survival") never is — without
    -- this, such a hunter would publish "Survival 0/0". The threshold gates ONLY
    -- this cosmetic message: recipes are gated by the spellbook check instead,
    -- so a client with odd numbers still syncs everything that matters.
    if (info.m or 0) >= PROF_MIN_CAP and (state.r ~= info.r or state.m ~= info.m) then
      SendRank(id, info.r, info.m)
    end

  end
end

-- ---------------------------------------------------------------------------
-- Replies from the website (relayed by Gchat)
-- ---------------------------------------------------------------------------

local function Commit(profId)
  local p = pending[profId]
  if not p then return end
  pending[profId] = nil
  local db = DB()

  if p.drop then
    db.profs[profId] = nil
    metaCache[profId] = nil
    return
  end

  local state = ProfState(profId)
  if p.ids then
    if p.full then
      state.ids = {}
      state.full = true
    end
    for i = 1, table.getn(p.ids) do state.ids[p.ids[i]] = true end
    -- The row count this set corresponds to, so a later open can be answered
    -- with one integer comparison instead of a read.
    state.rows = p.rows
  end
  state.r, state.m = p.r, p.m

  -- The one-off startup pass is complete once every scannable profession this
  -- character has holds a confirmed full set.
  local allFull = true
  for id, st in pairs(db.profs) do
    if PROF_BY_ID[id] and PROF_BY_ID[id].spell and not st.full and not st.gone then
      allFull = false
    end
  end
  if allFull then db.synced = true end
end

-- Is a metadata batch still going out? Used to ignore the replies its own
-- messages provoke — see HandleReply.
local function MetaQueued()
  for i = 1, table.getn(outbox) do
    if string.sub(outbox[i], 1, 4) == PROTO .. ":M:" then return true end
  end
  return false
end

-- The website only asks for names no guild member has taught it yet, so this
-- converges to nothing once the catalog is populated.
local function SendMeta(profId, idList)
  if metaRounds >= MAX_META_ROUNDS then return end
  metaRounds = metaRounds + 1
  local cache = metaCache[profId]
  if not cache then return end

  local batch, count = {}, 0
  for id in string.gfind(idList, "%d+") do
    local n = tonumber(id)
    local m = n and cache[n]
    if m then
      table.insert(batch, n .. "~" .. m.i .. "~" .. m.q .. "~" .. m.n)
      count = count + 1
      if count >= MAX_META then
        Send("M", profId .. ":" .. table.concat(batch, ";"))
        batch, count = {}, 0
      end
    end
  end
  if count > 0 then Send("M", profId .. ":" .. table.concat(batch, ";")) end
end

local function HandleReply(text)
  -- Replies are broadcast to the whole guild, so each one names its recipient.
  local _, _, op, who, rest = string.find(text, "^" .. PROTO .. ":(%a):([^:]+):(.*)$")
  if not op then return end
  if who ~= UnitName("player") then return end     -- somebody else's answer
  statAcked = statAcked + 1
  if op == "K" then
    local id = tonumber(rest)
    if id then
      Note("website stored " .. ((PROF_BY_ID[id] and PROF_BY_ID[id].skill) or id))
      Commit(id)
    end
  elseif op == "N" then
    local _, _, profId, ids = string.find(rest, "^(%d+):(.*)$")
    profId = tonumber(profId)
    if profId then
      Commit(profId)          -- the data landed; only the names are missing
      -- ⚠ EVERY metadata message gets its own answer, so acting on all of them
      -- multiplies: one request became seven messages, each of which drew
      -- another request, each of which... The guild channel filled up and the
      -- relay's flood guard cut the character off mid-catalog. A reply that
      -- arrives while a batch is still going out is stale by definition — the
      -- last message of the batch will draw a fresh, correct one.
      if MetaQueued() then return end
      Note("website wants names for " .. ((PROF_BY_ID[profId] and PROF_BY_ID[profId].skill) or profId))
      SendMeta(profId, ids or "")
    end
  end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- One shared handler for the four window events. `silent` says whether this is
-- our own scan (window hidden, safe to reorganise) or the player's (read-only).
-- Which tracked profession the currently open window belongs to, without
-- walking its rows. Used to throttle before doing the expensive part.
local function OpenWindowProf(isCraft)
  local line
  if isCraft then
    if GetCraftDisplaySkillLine then line = GetCraftDisplaySkillLine() end
    if (not line or line == "") and GetCraftName then line = GetCraftName() end
  else
    line = GetTradeSkillLine()
  end
  return (line and PROF_BY_WINDOW[line]) or nil
end

-- How many rows the open window has, without walking any of them.
local function OpenWindowRows(isCraft)
  if isCraft then return GetNumCrafts() end
  return GetNumTradeSkills()
end

--[[ ⚠ THE LIST FILLS IN OVER SEVERAL FRAMES, AND A PARTIAL READ IS POISON.

  A window event only means "the window is opening": the list behind it can be
  empty (GetTradeSkillLine() answering "UNKNOWN", GetNumTradeSkills() 0) and then
  arrive in pieces. Trusting it produced two real failures on 2026-08-09 — an
  alchemist's still-empty window published a FULL SYNC OF NOTHING that replaced
  everything the site knew about her, and a cook's first read caught 3 of 4 rows.

  So a count is only believed once it stops changing: look, wait, look again, and
  only walk the rows when two consecutive looks agree on a non-zero number. This
  applies to BOTH paths — the window the player opened is filling in exactly the
  same way as one this addon opened.

  Checking the count is a single cheap call, which is also why it happens before
  the expensive part: crafting with the window open fires an update per craft,
  and each one used to build a full id list only to have it thrown away.
]]
local function OnWindowVisible(isCraft)
  if reading then return end

  local prof = OpenWindowProf(isCraft)
  local rows = (prof and OpenWindowRows(isCraft)) or 0

  if learnSettleAt then return end          -- mid-burst; the settle timer returns
  -- The throttle is only stamped once something is actually reported, so a
  -- glance at a half-filled window never costs the real read that follows it.
  if prof and lastPassive[prof.id] and (GetTime() - lastPassive[prof.id]) < PASSIVE_THROTTLE then return end

  local settled = (prof and rows > 0 and winSeen == rows and winProf == prof.id) and true or false
  winSeen = rows
  winProf = prof and prof.id
  winIsCraft = isCraft

  if not settled then
    -- ⚠ Keep looking even when the window is not identifiable YET. Until the
    -- data lands GetTradeSkillLine() answers "UNKNOWN", and returning here would
    -- leave the read depending on a second event that a complete list never
    -- sends. Bounded, so an untracked window (Beast Training) costs a couple of
    -- seconds of glances and then stops.
    winTries = winTries + 1
    if winTries <= WIN_MAX_TRIES then winRecheckAt = GetTime() + SCAN_SETTLE end
    return
  end
  winTries = 0

  --[[ ⚠ ALREADY DONE? THEN DO NOTHING — not even read.

    This runs every time anybody opens a profession, so the cheap path has to be
    the common one. A confirmed profession whose window still has the same number
    of rows cannot have changed, and comparing two integers is the whole check:
    no walking ~95 rows, no building an id list, no diff, no message. Learning or
    unlearning anything moves the count, which is exactly when the real read is
    worth doing.
  ]]
  local known = ProfState(prof.id)
  if known.full and known.rows == rows then
    lastPassive[prof.id] = GetTime()
    return
  end

  -- Something changed (or this profession has never been confirmed): now it is
  -- worth walking the rows.
  reading = true
  local ids, clean, kind
  if isCraft then
    prof, ids, clean, kind = ReadCraft(false)
  else
    prof, ids, clean, kind = ReadTradeSkill(false)
  end
  if prof then lastPassive[prof.id] = GetTime() end
  winRecheckAt = nil

  if prof then
    local state = ProfState(prof.id)
    -- The cheap read first; only if THIS profession is the one hidden under a
    -- collapsed header is an expand worth it — and here it is, because the
    -- alternative is publishing a rank of 0/0. This path already only runs when
    -- the recipe list actually changed, so it is rare.
    local skills = ReadSkills(false)
    local info = skills and skills[prof.id]
    if not info then
      skills = ReadSkills(true)
      info = skills and skills[prof.id]
    end
    -- The stored rank is -1 until the website has confirmed one, which is not
    -- a number to put on the wire; fall back to 0 when the pane is unreadable.
    local rank = (info and info.r) or state.r
    local max  = (info and info.m) or state.m
    if rank < 0 then rank = 0 end
    if max  < 0 then max  = 0 end
    Report(prof, ids, clean, kind, rank, max)
  end

  reading = false
end

-- End of a learn burst: read the open window once, for everything at once.
--
-- If no window is open there is nothing to do — the recipe is in the game and
-- will be reported the next time the player opens that profession, which they
-- have to do to use it anyway.
local function FlushLearned()
  learnSettleAt, learnFirstAt = nil, nil
  lastPassive = {}                        -- a real change outranks the throttle
  winSeen, winProf = nil, nil             -- force a fresh settle
  if FrameShown("TradeSkillFrame") then OnWindowVisible(false) return end
  if FrameShown("CraftFrame") then OnWindowVisible(true) end
end

local f = CreateFrame("Frame", "ShootyProfSyncFrame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_UPDATE")
f:RegisterEvent("CRAFT_SHOW")
f:RegisterEvent("CRAFT_UPDATE")
-- Only to forget the settle state: a window that closed cannot be looked at
-- again, and a stale row count would make the NEXT one look already-settled.
f:RegisterEvent("TRADE_SKILL_CLOSE")
f:RegisterEvent("CRAFT_CLOSE")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:RegisterEvent("CHAT_MSG_ADDON")

f:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- Also fires on every zone change; only the first one matters.
    if not readyAt then readyAt = GetTime() + LOGIN_DELAY end
    return
  end

  if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
    if readyAt then OnWindowVisible(false) end
    return
  end

  if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
    if readyAt then OnWindowVisible(true) end
    return
  end

  if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
    winSeen, winProf, winIsCraft, winRecheckAt, winTries = nil, nil, nil, nil, 0
    return
  end

  if event == "SKILL_LINES_CHANGED" then
    -- ⚠ IGNORE OUR OWN ECHO. Expanding or collapsing a header to read the pane
    -- fires this event, so without the grace window the check that did the
    -- expanding re-arms itself and runs again forever, every SKILL_DEBOUNCE
    -- seconds, dragging pfQuest's quest-giver rebuild along with it. See
    -- ReadSkills.
    if skillEchoUntil and GetTime() < skillEchoUntil then return end
    -- Fires on every point of skill-up, so it only arms a debounced check; that
    -- check sends nothing unless a profession appeared, vanished, or moved.
    skillsCheckAt = GetTime() + SKILL_DEBOUNCE
    return
  end

  if event == "CHAT_MSG_SYSTEM" then
    -- "You have learned how to create a new item: X." — learned from a trainer
    -- or a recipe item, so no window is open and only a re-scan can see it.
    --
    -- Buying out a trainer produces a burst of these. Reacting to each one
    -- would re-read the window thirty times and send thirty messages, so a learn
    -- only pushes the settle timer; the read happens once the player stops, and
    -- every recipe learned in the burst leaves in a single message.
    if arg1 and string.find(arg1, "learned how to create") then
      local now = GetTime()
      if not learnFirstAt then learnFirstAt = now end
      learnSettleAt = now + LEARN_SETTLE
    end
    return
  end

  if event == "CHAT_MSG_ADDON" then
    if arg1 == ADDON_PREFIX and arg4 == RELAY_NAME then HandleReply(arg2 or "") end
    return
  end
end)

f:SetScript("OnUpdate", function()
  local now = GetTime()

  -- Nothing happens during the login grace period: guild data, the spellbook
  -- and the skill pane are all still settling in the first seconds.
  if not readyAt or now < readyAt then return end
  if pauseUntil then
    if now < pauseUntil then return end
    pauseUntil = nil
  end

  -- Background sweep. Cheap, local, and silent unless something really moved.
  if not nextIdleCheck then nextIdleCheck = now end
  if now >= nextIdleCheck then
    nextIdleCheck = now + IDLE_CHECK
    if skillsCheckAt == nil then skillsCheckAt = now end
  end

  -- The learn burst has gone quiet (or has run so long it is no longer a burst).
  if learnSettleAt and (now >= learnSettleAt or (learnFirstAt and now - learnFirstAt >= LEARN_MAX_WAIT)) then
    FlushLearned()
  end

  if skillsCheckAt and now >= skillsCheckAt then
    skillsCheckAt = nil
    CheckSkills()
  end

  -- Look at an open window again to see whether its row count has stopped
  -- moving. TRADE_SKILL_UPDATE only fires when the list CHANGES, so a list that
  -- is already complete would otherwise never produce a second look — and the
  -- window the PLAYER opened needs this just as much as one we opened.
  if winRecheckAt and now >= winRecheckAt then
    winRecheckAt = nil
    if winIsCraft ~= nil then OnWindowVisible(winIsCraft) end
  end


  -- A batch nobody acknowledged is abandoned rather than retried on the spot:
  -- the relay may be down, and hammering it would not help. Because none of it
  -- was committed, the next trigger rebuilds it.
  for id, p in pairs(pending) do
    if (now - p.at) > ACK_TIMEOUT then pending[id] = nil end
  end

  FlushOutbox()
end)

-- ---------------------------------------------------------------------------
-- Manual override
-- ---------------------------------------------------------------------------
-- Deliberately the only thing in this file that ever prints, and only when a
-- human typed the command.

-- Everything this feature knows about itself, in six lines. It sends no chat and
-- draws nothing, so when it does not work there is otherwise nowhere to look.
local function PrintStatus()
  local guild = GetGuildInfo("player") or "none"
  local online = RelayOnline()
  local relay = RELAY_NAME .. (online == nil and " (roster not loaded)"
                or (online and " online" or " OFFLINE"))
  Say("guild " .. guild .. " | relay " .. relay)

  -- A human typed this, so the expand is worth it here whatever it costs.
  local skills, complete = ReadSkills(true)
  if not complete then
    Say("partial reading — close the character window for the full picture")
  end
  do
    local parts, any = {}, false
    for id, info in pairs(skills) do
      local prof = PROF_BY_ID[id]
      local st = ProfState(id)
      local mark = st.full and "synced" or (st.gone and "dropped" or "pending")
      if not prof.spell then mark = "no recipes" end
      table.insert(parts, prof.skill .. " " .. info.r .. "/" .. info.m .. " (" .. mark .. ")")
      any = true
    end
    Say(any and table.concat(parts, ", ") or "no tracked professions on this character")
  end

  Say("outbox " .. table.getn(outbox) ..
      " | sent " .. statSent .. " | replies " .. statAcked)
  if pauseUntil then
    Say("paused for " .. math.floor(pauseUntil - GetTime()) .. "s")
  end
  local n = table.getn(notes)
  if n == 0 then
    Say("nothing has happened yet")
  else
    for i = 1, n do Say("  " .. i .. ". " .. notes[i]) end
  end
end

SLASH_SHOOTYPROFSYNC1 = "/profsync"
SlashCmdList["SHOOTYPROFSYNC"] = function(msg)
  if msg and string.find(string.lower(msg), "status") then
    PrintStatus()
    return
  end
  if not InGuild() then
    Say("only <" .. GUILD_NAME .. "> members sync.")
    return
  end
  local db = DB()
  db.synced = false
  for id, st in pairs(db.profs) do
    st.full = false
    st.ids = {}
    st.rows = nil
    st.r, st.m = -1, -1
  end
  outbox, pending = {}, {}
  lastPassive, lastRankSend, metaRounds = {}, {}, 0
  winSeen, winProf, winRecheckAt, winTries = nil, nil, nil, 0
  learnSettleAt, learnFirstAt = nil, nil
  gateAt, pauseUntil = 0, nil
  readyAt = GetTime()
  skillsCheckAt = GetTime()
  statSent, statAcked, notes = 0, 0, {}
  Note("manual rescan requested")
  if RelayOnline() then
    Say("forgotten — open each profession once and it will re-send.")
  else
    Say(RELAY_NAME .. " is offline — this will sync by itself once it is back.")
  end
end
