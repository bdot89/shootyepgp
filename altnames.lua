-- AltNames: Display main character names from guild public notes
-- Reads @Mainname from guild officer/public notes and appends (Mainname)
-- Hooks into pfUI unit frames/nameplates (if installed), Blizzard chat and raid UI

AltNames = CreateFrame("Frame")

-- Lookup table: lowercase charname -> main name (proper case)
AltNames.cache = {}
-- Lookup table: lowercase charname -> class token (MAGE, ...), for colouring the main
AltNames.classes = {}

-- Off when the player unticked "Show alts' main names" (Settings page).
function AltNames:Enabled()
  return not (type(sepgp_ui) == "table" and sepgp_ui.altNamesOff)
end

-- Scan guild roster and build the cache
function AltNames:ScanGuildRoster()
  local num = GetNumGuildMembers(true)
  if num == 0 then return end

  local newcache, classes = {}, {}
  for i = 1, num do
    local name, _, _, _, class, _, note = GetGuildRosterInfo(i)
    if name and class then classes[string.lower(name)] = string.upper(class) end
    if name and note then
      local main = string.gsub(note, "^.*@(%w+).*$", "%1")
      -- Only store if the pattern actually matched (main ~= note means it matched)
      if main ~= note and main ~= "" then
        newcache[string.lower(name)] = main
      end
    end
  end
  self.cache = newcache
  self.classes = classes
end

-- Get main name for a character name, returns nil if none (or switched off)
function AltNames:GetMain(name)
  if not name or name == "" or not self:Enabled() then return nil end
  return self.cache[string.lower(name)]
end

-- " (Main)" in the main's class colour, closed with |r so nothing after it changes
function AltNames:Tag(main)
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[self.classes[string.lower(main)] or ""]
  if not c then return " (" .. main .. ")" end
  return string.format(" |cff%02x%02x%02x(%s)|r", c.r * 255, c.g * 255, c.b * 255, main)
end

-- Append " (Main)" to a name string if alt is found
function AltNames:AppendMain(name)
  if not name or name == "" then return name end
  local main = self:GetMain(name)
  if main then
    return name .. " (" .. main .. ")"
  end
  return name
end

---------------------------------------------------------------------------
-- Event handling: scan guild roster on relevant events
---------------------------------------------------------------------------
AltNames:RegisterEvent("GUILD_ROSTER_UPDATE")
AltNames:RegisterEvent("PLAYER_ENTERING_WORLD")
AltNames:RegisterEvent("PLAYER_GUILD_UPDATE")

AltNames:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- Request guild roster data
    if IsInGuild() then
      GuildRoster()
    end
  end
  -- Scan on any guild roster event
  if IsInGuild() then
    AltNames:ScanGuildRoster()
  end
end)

-- Also rescan periodically (every 30s) to catch updates
AltNames.elapsed = 0
AltNames:SetScript("OnUpdate", function()
  AltNames.elapsed = AltNames.elapsed + arg1
  if AltNames.elapsed > 30 then
    AltNames.elapsed = 0
    if IsInGuild() then
      GuildRoster()
    end
  end
end)

---------------------------------------------------------------------------
-- HOOK 1: pfUI unit frames (raid frames, group frames, player, target, etc.)
-- Hook pfUI.uf:GetNameString to append main name
---------------------------------------------------------------------------
local function HookUnitFrames()
  if not pfUI or not pfUI.uf or not pfUI.uf.GetNameString then return end

  local origGetNameString = pfUI.uf.GetNameString

  pfUI.uf.GetNameString = function(self, unitstr)
    local name = origGetNameString(self, unitstr)
    if not name or not unitstr then return name end

    -- Only modify for players
    if not UnitIsPlayer(unitstr) then return name end

    local main = AltNames:GetMain(name)
    if main then
      return name .. " (" .. main .. ")"
    end
    return name
  end
end

---------------------------------------------------------------------------
-- HOOK 2: pfUI nameplates
-- The nameplate module uses a local GetNameString, so we hook the SetText
-- on the nameplate name FontString after OnDataChanged runs
---------------------------------------------------------------------------
local function HookNameplates()
  if not pfUI or not pfUI.nameplates or not pfUI.nameplates.OnDataChanged then return end

  local origOnDataChanged = pfUI.nameplates.OnDataChanged

  pfUI.nameplates.OnDataChanged = function(self, plate)
    origOnDataChanged(self, plate)

    -- After pfUI sets the name, append main name if applicable
    if plate and plate.name then
      local text = plate.name:GetText()
      if text and text ~= "" then
        -- Only modify if not already modified (avoid double-appending)
        if not string.find(text, " %(") then
          local main = AltNames:GetMain(text)
          if main then
            plate.name:SetText(text .. " (" .. main .. ")")
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- HOOK 3: Chat messages
-- Hook each ChatFrame's AddMessage to inject main names into player links
---------------------------------------------------------------------------
local function HookChat()
  -- Hook each ChatFrame's AddMessage
  for i = 1, NUM_CHAT_WINDOWS do
    local cf = _G["ChatFrame" .. i]
    if cf and cf.AddMessage then
      local prevAddMessage = cf.AddMessage

      cf.AddMessage = function(frame, text, a1, a2, a3, a4, a5)
        if text and AltNames:Enabled() and string.find(text, "|Hplayer:") then
          -- ⚠ The link itself is left untouched and (Main) goes AFTER it, opened
          -- with |r in case the link sat inside a class colour. Rewriting the
          -- name inside the link (the old way) stopped other chat addons from
          -- finding it, so alts lost their class colour. The display may hold
          -- colour codes, so it is matched up to the first |h, not as "no pipes".
          text = string.gsub(text, "(|Hplayer:([^|:]+)[^|]*|h.-|h)", function(link, pname)
            local real = pname
            local dashpos = string.find(real, "%-")
            if dashpos then
              real = string.sub(real, 1, dashpos - 1)
            end
            local main = AltNames:GetMain(real)
            if main and string.lower(main) ~= string.lower(real) then
              return link .. "|r" .. AltNames:Tag(main)
            end
            return link
          end)
        end

        return prevAddMessage(frame, text, a1, a2, a3, a4, a5)
      end
    end
  end
end

---------------------------------------------------------------------------
-- HOOK 4: Blizzard Raid UI (Blizzard_RaidUI)
-- Hook the raid member name buttons in the default raid window
---------------------------------------------------------------------------
local function HookBlizzardRaidUI()
  -- Hook RaidGroupFrame name updates
  local origRaidGroupFrame_Update = _G.RaidGroupFrame_Update
  if origRaidGroupFrame_Update then
    _G.RaidGroupFrame_Update = function()
      origRaidGroupFrame_Update()
      -- After the default update, modify displayed names
      for i = 1, 40 do
        local btn = _G["RaidGroupButton" .. i]
        if btn and btn:IsVisible() then
          local nameLabel = _G["RaidGroupButton" .. i .. "Name"]
          if nameLabel then
            local text = nameLabel:GetText()
            if text and text ~= "" and not string.find(text, " %(") then
              local main = AltNames:GetMain(text)
              if main then
                nameLabel:SetText(text .. " (" .. main .. ")")
              end
            end
          end
        end
      end
    end
  end

  -- Also hook RaidGroup_Update for the group sub-frames
  local origRaidGroup_Update = _G.RaidGroup_Update
  if origRaidGroup_Update then
    _G.RaidGroup_Update = function(a1, a2, a3, a4, a5)
      origRaidGroup_Update(a1, a2, a3, a4, a5)
      for group = 1, 8 do
        for slot = 1, 5 do
          local fname = "RaidGroup" .. group .. "Slot" .. slot
          local nameLabel = _G[fname .. "Name"]
          if nameLabel then
            local text = nameLabel:GetText()
            if text and text ~= "" and not string.find(text, " %(") then
              local main = AltNames:GetMain(text)
              if main then
                nameLabel:SetText(text .. " (" .. main .. ")")
              end
            end
          end
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Initialize hooks after pfUI has loaded
---------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
  -- Delay to ensure addon modules are loaded
  initFrame.timer = 0
  initFrame:SetScript("OnUpdate", function()
    initFrame.timer = initFrame.timer + arg1
    if initFrame.timer > 2 then
      initFrame:SetScript("OnUpdate", nil)
      -- PLAYER_ENTERING_WORLD fires on every zone change; hooking again each
      -- time stacked the hooks and tagged a name once per loading screen.
      initFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
      HookUnitFrames()
      HookNameplates()
      HookChat()
      HookBlizzardRaidUI()
    end
  end)
end)

