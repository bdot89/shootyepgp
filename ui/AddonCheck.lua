-- shootyepgp :: new window, part 7 - Addon check (officers)
-- From a responder the guild leader's friend sent (18 Oct 2026,
-- Downloads\shootyepgp-addoncheck.lua). Same protocol, so it works with the
-- friend's tool too. Addon message prefix "ADDONCHECK":
--   query:  "Q1:<id>:<Addon1>,<Addon2>,..."   (folder names, to RAID / PARTY / GUILD)
--   answer: "A1:<id>:<Addon1>=L/<version>;<Addon2>=D;<Addon3>=M"   (same channel)
--   L = loaded (version from its .toc, "?" if none), D = installed but not loaded,
--   M = not installed. A long answer comes in several messages with the same head.
-- Added here: the responder only answers guild / group members, at most once
-- per asker every 10 s and 8 answers per 30 s in all (the friend's version
-- answered every new id, so one person could make the whole guild send);
-- and the asking side, an officer page that lists everyone's answer.

local UI = SEPGP_UI
local C = UI.C
local PW, PH = UI.PAGE_W, UI.PAGE_H
local A = { answers = {} }
UI.AddonCheck = A

local PREFIX = "ADDONCHECK"
local MAXLEN = 240
local MAXNAMES = 16
local DEFAULT_LIST = "shootyepgp,BigWigs,pfUI"

-- ------------------------------------------------------------------ answering

local lastId, lastAt, recent = {}, {}, {}

local function Clean(s)
  s = tostring(s or "?")
  s = string.gsub(s, "[:;=,/|]", " ")
  return string.sub(s, 1, 24)
end

function A.State(name)
  if IsAddOnLoaded(name) then
    return "L/" .. Clean(GetAddOnMetadata(name, "Version"))
  end
  local ok, _, title, _, _, _, reason = pcall(GetAddOnInfo, name)
  if not ok or not title or reason == "MISSING" then return "M" end
  return "D"
end

-- someone we may answer: in our guild, raid or party
local function Known(sender)
  if not sender then return false end
  local _, byName = UI.Roster()
  if byName and byName[sender] then return true end
  for i = 1, GetNumRaidMembers() do
    if GetRaidRosterInfo(i) == sender then return true end
  end
  for i = 1, GetNumPartyMembers() do
    if UnitName("party" .. i) == sender then return true end
  end
  return sender == UnitName("player")
end

local function Allowed(sender)
  local now = GetTime()
  if lastAt[sender] and now - lastAt[sender] < 10 then return false end
  local n = 0
  for i = table.getn(recent), 1, -1 do
    if now - recent[i] > 30 then table.remove(recent, i) else n = n + 1 end
  end
  if n >= 8 then return false end
  lastAt[sender] = now
  table.insert(recent, now)
  return true
end

function A.Answer(msg, channel, sender)
  if channel ~= "RAID" and channel ~= "PARTY" and channel ~= "GUILD" and channel ~= "BATTLEGROUND" then return end
  local _, _, id, list = string.find(msg or "", "^Q1:(%w+):(.+)$")
  if not id or lastId[sender or ""] == id then return end   -- not a query, or answered already
  if not Known(sender) or not Allowed(sender) then return end
  lastId[sender or ""] = id
  local head = "A1:" .. id .. ":"
  local out, n = head, 0
  for name in string.gfind(list, "([%w_%-%.]+)") do
    n = n + 1
    if n > MAXNAMES then break end
    local part = name .. "=" .. A.State(name)
    if out ~= head and string.len(out) + 1 + string.len(part) > MAXLEN then
      pcall(SendAddonMessage, PREFIX, out, channel)
      out = head
    end
    if out ~= head then out = out .. ";" end
    out = out .. part
  end
  if out ~= head then pcall(SendAddonMessage, PREFIX, out, channel) end
end

-- ------------------------------------------------------------------ asking

function A.Names(text)
  local names = {}
  for name in string.gfind(text or "", "([%w_%-%.]+)") do
    if table.getn(names) < MAXNAMES then table.insert(names, name) end
  end
  return names
end

-- channel: "RAID", "PARTY" or "GUILD"
function A.Ask(text, channel)
  local names = A.Names(text)
  if table.getn(names) == 0 then return nil, "type at least one addon folder name" end
  local id = tostring(math.mod(time(), 100000)) .. tostring(math.random(10, 99))
  local msg = "Q1:" .. id .. ":" .. table.concat(names, ",")
  while string.len(msg) > MAXLEN and table.getn(names) > 1 do
    table.remove(names)
    msg = "Q1:" .. id .. ":" .. table.concat(names, ",")
  end
  A.id, A.names, A.channel, A.at = id, names, channel, time()
  A.answers = {}
  A.version = (A.version or 0) + 1
  -- our own answer straight away (the server may not echo our message to us)
  local mine = {}
  for i = 1, table.getn(names) do mine[names[i]] = A.State(names[i]) end
  A.answers[UnitName("player")] = mine
  pcall(SendAddonMessage, PREFIX, msg, channel)
  return names
end

function A.OnAnswer(msg, sender)
  if not A.id or not sender then return end
  local _, _, id, body = string.find(msg or "", "^A1:(%w+):(.+)$")
  if id ~= A.id then return end
  local got = A.answers[sender] or {}
  for part in string.gfind(body, "([^;]+)") do
    local _, _, name, state = string.find(part, "^([^=]+)=(.+)$")
    if name then got[name] = state end
  end
  A.answers[sender] = got
  A.version = (A.version or 0) + 1
end

-- who should answer: the raid / party, or online guild members
function A.Expected(channel)
  local out = {}
  if channel == "RAID" then
    for i = 1, GetNumRaidMembers() do
      local n = GetRaidRosterInfo(i)
      if n then out[n] = true end
    end
  elseif channel == "PARTY" then
    out[UnitName("player")] = true
    for i = 1, GetNumPartyMembers() do
      local n = UnitName("party" .. i)
      if n then out[n] = true end
    end
  else
    local roster = UI.Roster()
    for i = 1, table.getn(roster) do
      if roster[i].online then out[roster[i].name] = true end
    end
  end
  return out
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function()
  if arg1 ~= PREFIX then return end
  if string.find(arg2 or "", "^Q1:") then
    pcall(A.Answer, arg2, arg3, arg4)
  elseif string.find(arg2 or "", "^A1:") then
    pcall(A.OnAnswer, arg2, arg4)
  end
end)

-- ------------------------------------------------------------------ page

local STATE_TEXT = { D = "off", M = "missing" }

local function Describe(answer, names)
  if not answer then return UI.Paint(C.dim, "no answer"), 0, "" end
  local parts, missing, tip = {}, 0, {}
  for i = 1, table.getn(names) do
    local name = names[i]
    local s = answer[name]
    local label
    if not s then
      label = UI.Paint(C.dim, name .. " ?")
      table.insert(tip, name .. ": not in the answer")
    elseif string.sub(s, 1, 1) == "L" then
      local v = string.sub(s, 3)
      label = UI.Paint(C.on, name)
      table.insert(tip, name .. ": loaded" .. ((v ~= "" and v ~= "?") and (", version " .. v) or ""))
    elseif s == "D" then
      missing = missing + 1
      label = UI.Paint(C.gold, name .. " off")
      table.insert(tip, name .. ": installed but switched off")
    else
      missing = missing + 1
      label = UI.Paint(C.red, name .. " missing")
      table.insert(tip, name .. ": not installed")
    end
    table.insert(parts, label)
  end
  return table.concat(parts, "  "), missing, table.concat(tip, "\n")
end

local CHANNELS = { { key = "RAID", label = "My raid" }, { key = "PARTY", label = "My party" }, { key = "GUILD", label = "Online guild" } }

UI.Page{ key = "addons", label = "Addon check", after = "officer", admin = true,
  tip = "Ask your raid or the guild which addons they have loaded. Officers only.",
  build = function(f)
    local top = UI.Card(f, "Check addons", PW, 92)
    top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    UI.Label(top, "Addons", 12, -36)
    f.names = UI.EditBox(top, 330)
    f.names:SetPoint("TOPLEFT", top, "TOPLEFT", 70, -33)
    f.names:SetMaxLetters(220)
    UI.Tip(f.names, "Addons to check", "Addon FOLDER names (as in Interface\\AddOns), separated by commas. Up to " .. MAXNAMES .. ".")
    f.names.onChange = function(text) UI.DB().addonList = text end
    f.chan = UI.Dropdown(top, 120, CHANNELS, function() return f.channel end, function(k) f.channel = k end)
    f.chan:SetPoint("LEFT", f.names, "RIGHT", 8, 0)
    UI.Tip(f.chan, "Who to ask", "Your raid, your party, or every online guild member.")
    local ask = UI.Button(top, "Check", 90, 22)
    ask:SetPoint("LEFT", f.chan, "RIGHT", 8, 0)
    ask:SetScript("OnClick", function()
      local ch = f.channel
      if ch == "RAID" and GetNumRaidMembers() == 0 then
        UI.Confirm("You are not in a raid. Pick \"My party\" or \"Online guild\" instead.", nil, "Not in a raid", "OK")
        return
      end
      if ch == "PARTY" and GetNumPartyMembers() == 0 then
        UI.Confirm("You are not in a party. Pick \"Online guild\" instead.", nil, "Not in a party", "OK")
        return
      end
      local names, err = A.Ask(f.names:GetText(), ch)
      if not names then
        UI.Confirm("Type at least one addon folder name, e.g. " .. DEFAULT_LIST .. ".", nil, "No addons to check", "OK")
        return
      end
      UI.RefreshPage()
    end)
    UI.Tip(ask, "Check", "Sends one question on the hidden addon channel. Members whose shootyepgp (or another addon-check responder) is up to date answer within a few seconds. Nothing shows in chat.")
    f.status = UI.Text(top, 11, C.dim)
    f.status:SetPoint("TOPLEFT", top, "TOPLEFT", 12, -66)
    f.status:SetWidth(PW - 24)
    f.status:SetJustifyH("LEFT")
    f.problems = UI.Switch(f)
    f.problems:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -100)
    f.problems.onToggle = function(v) f.onlyProblems = v UI.RefreshPage() end
    local pl = UI.Text(f, 12)
    pl:SetPoint("LEFT", f.problems, "RIGHT", 8, 0)
    pl:SetText("Only show problems")
    UI.Tip(f.problems, "Only problems", "Hide members who have everything loaded.")

    local cols = {
      { key = "name", label = "Name", width = 110, sort = "asc" },
      { key = "ans", label = "Answered", width = 64, sort = true },
      { key = "miss", label = "Missing", width = 52, align = "RIGHT", sort = true },
      { key = "list", label = "Addons", width = 390 },
    }
    local nRows = math.floor((PH - 124 - 24 - 20) / 18)
    local l = UI.List(f, cols, 18, nRows)
    l:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -124)
    l:SetWidth(PW)
    l:SetHeight(nRows * 18 + 24)
    l.sortKey, l.sortDesc = "miss", true
    l.emptyText = "Type the addons, pick who to ask and press Check."
    l.filter = function(r) return not f.onlyProblems or r.problem end
    l.onEnter = function(r, line)
      GameTooltip:SetOwner(line, "ANCHOR_RIGHT")
      GameTooltip:AddLine(r.id)
      GameTooltip:AddLine(r.tip ~= "" and r.tip or "No answer: offline, an older shootyepgp, or no addon-check responder.", 1, 1, 1, 1)
      GameTooltip:Show()
    end
    l.onClick = function(r) if UI.byName and UI.byName[r.id] then UI.OpenHistory(r.id) end end
    f.list = l
    f.count = UI.Text(f, 10, C.dim)
    f.count:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 2, -5)
    f.channel = (GetNumRaidMembers() > 0) and "RAID" or "GUILD"
  end,
  refresh = function(f)
    if not f.names.typing and f.names:GetText() == "" then f.names:SetText(UI.DB().addonList or DEFAULT_LIST) end
    f.chan.Refresh()
    f.problems.Set(f.onlyProblems and true or false)
    if not A.id then
      f.status:SetText("Asks over the hidden addon channel - nobody sees it in chat. Only members with this shootyepgp (or another addon-check responder) can answer.")
      f.list:SetRows({}, true)
      f.count:SetText("")
      return
    end
    local expected = A.Expected(A.channel)
    for name in pairs(A.answers) do expected[name] = true end
    local rows, answered, total, bad = {}, 0, 0, 0
    for name in pairs(expected) do
      total = total + 1
      local ans = A.answers[name]
      if ans then answered = answered + 1 end
      local text, missing, tip = Describe(ans, A.names)
      local problem = (not ans) or missing > 0
      if problem then bad = bad + 1 end
      local m = UI.byName and UI.byName[name]
      table.insert(rows, { id = name, tip = tip, problem = problem,
        cells = { m and UI.ClassName(name, m.class) or name, ans and UI.Paint(C.on, "yes") or UI.Paint(C.red, "no"),
                  (missing > 0) and UI.Paint(C.red, tostring(missing)) or (ans and "0" or ""), text },
        sort = { name = name, ans = ans and 1 or 0, miss = ans and missing or 99, tie = name } })
    end
    f.list:SetRows(rows, true)
    local where = (A.channel == "RAID" and "raid") or (A.channel == "PARTY" and "party") or "online guild members"
    f.status:SetText("Asked your " .. where .. " at " .. date("%H:%M:%S", A.at) .. " about " .. table.concat(A.names, ", ")
      .. "  -  " .. answered .. " of " .. total .. " answered")
    f.count:SetText(bad .. " with a problem or no answer  -  hover a row for details")
  end,
}
