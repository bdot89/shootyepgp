local T = AceLibrary("Tablet-2.0")
local D = AceLibrary("Dewdrop-2.0")
local C = AceLibrary("Crayon-2.0")

local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")

sepgp_installs_window = sepgp:NewModule("sepgp_installs_window", "AceDB-2.0", "AceEvent-2.0")

function sepgp_installs_window:OnEnable()
  if not T:IsRegistered("sepgp_installs_window") then
    T:Register("sepgp_installs_window",
      "children", function()
        T:SetTitle(L["shootyepgp addon installs"])
        self:OnTooltipUpdate()
      end,
      "showTitleWhenDetached", true,
      "showHintWhenDetached", true,
      "cantAttach", true,
      "menu", function()
        D:AddLine(
          "text", L["Refresh"],
          "tooltipText", L["Refresh window"],
          "func", function() sepgp_installs_window:Refresh() end
        )
        D:AddLine(
          "text", L["Send Ping"],
          "tooltipText", L["Send a ping to detect updated clients"],
          "func", function()
            sepgp:addonMessage("PING","GUILD")
            if GetNumRaidMembers() > 0 then
              sepgp:addonMessage("PING","RAID")
            elseif GetNumPartyMembers() > 0 then
              sepgp:addonMessage("PING","PARTY")
            end
          end
        )
        D:AddLine(
          "text", L["Clear"],
          "tooltipText", L["Clear cache and rescan"],
          "func", function() sepgp_installs_window:ClearAndRescan() end
        )
      end
    )
  end
  if not T:IsAttached("sepgp_installs_window") then
    T:Open("sepgp_installs_window")
  end
end

function sepgp_installs_window:OnDisable()
  T:Close("sepgp_installs_window")
  if self:IsEventScheduled("AutoRefreshInstalls") then
    self:CancelScheduledEvent("AutoRefreshInstalls")
  end
end

function sepgp_installs_window:Refresh()
  T:Refresh("sepgp_installs_window")
end

function sepgp_installs_window:setHideScript()
  local i = 1
  local tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  while (tablet) and i<100 do
    if tablet.owner ~= nil and tablet.owner == "sepgp_installs_window" then
      sepgp:make_escable(string.format("Tablet20DetachedFrame%d",i),"add")
      tablet:SetScript("OnHide",nil)
      tablet:SetScript("OnHide",function()
          if not T:IsAttached("sepgp_installs_window") then
            T:Attach("sepgp_installs_window")
            this:SetScript("OnHide",nil)
            -- Stop auto-refresh when window closes
            if sepgp_installs_window:IsEventScheduled("AutoRefreshInstalls") then
              sepgp_installs_window:CancelScheduledEvent("AutoRefreshInstalls")
            end
          end
        end)
      break
    end
    i = i+1
    tablet = getglobal(string.format("Tablet20DetachedFrame%d",i))
  end
end

function sepgp_installs_window:Top()
  if T:IsRegistered("sepgp_installs_window") and (T.registry.sepgp_installs_window.tooltip) then
    T.registry.sepgp_installs_window.tooltip.scroll=0
  end
end

function sepgp_installs_window:Toggle(forceShow)
  self:Top()
  if T:IsAttached("sepgp_installs_window") then
    T:Detach("sepgp_installs_window")
    if (T:IsLocked("sepgp_installs_window")) then
      T:ToggleLocked("sepgp_installs_window")
    end
    self:setHideScript()
    -- Start auto-refresh when window is opened
    if not self:IsEventScheduled("AutoRefreshInstalls") then
      self:ScheduleRepeatingEvent("AutoRefreshInstalls", self.AutoRefresh, 5, self)
    end
    -- Send a ping when opening the window to guild and raid
    sepgp:addonMessage("PING","GUILD")
    if GetNumRaidMembers() > 0 then
      sepgp:addonMessage("PING","RAID")
    elseif GetNumPartyMembers() > 0 then
      sepgp:addonMessage("PING","PARTY")
    end

    -- Also broadcast our VERSION so even old clients can detect us
    local versionMsg = string.format("VERSION;%s;1", sepgp._versionString)
    sepgp:addonMessage(versionMsg,"GUILD")
    if GetNumRaidMembers() > 0 then
      sepgp:addonMessage(versionMsg,"RAID")
    elseif GetNumPartyMembers() > 0 then
      sepgp:addonMessage(versionMsg,"PARTY")
    end
  else
    if (forceShow) then
      sepgp_installs_window:Refresh()
    else
      T:Attach("sepgp_installs_window")
      -- Stop auto-refresh when window closes
      if self:IsEventScheduled("AutoRefreshInstalls") then
        self:CancelScheduledEvent("AutoRefreshInstalls")
      end
    end
  end
end

function sepgp_installs_window:AutoRefresh()
  if not T:IsAttached("sepgp_installs_window") then
    self:Refresh()
  end
end

function sepgp_installs_window:ClearAndRescan()
  -- Clear the cached data
  sepgp_installs = {}

  -- Send pings to all channels
  sepgp:addonMessage("PING","GUILD")
  if GetNumRaidMembers() > 0 then
    sepgp:addonMessage("PING","RAID")
  elseif GetNumPartyMembers() > 0 then
    sepgp:addonMessage("PING","PARTY")
  end

  -- Also broadcast our VERSION so even old clients can detect us
  local versionMsg = string.format("VERSION;%s;1", sepgp._versionString)
  sepgp:addonMessage(versionMsg,"GUILD")
  if GetNumRaidMembers() > 0 then
    sepgp:addonMessage(versionMsg,"RAID")
  elseif GetNumPartyMembers() > 0 then
    sepgp:addonMessage(versionMsg,"PARTY")
  end

  -- Wait a moment for responses, then refresh
  self:ScheduleEvent("ClearAndRescanRefresh", function()
    sepgp_installs_window:Refresh()
  end, 2, self)

  -- Show message
  sepgp:defaultPrint(L["Cache cleared. Rescanning..."])
end

function sepgp_installs_window:OnTooltipUpdate()
  local has_data = false

  if sepgp_installs and next(sepgp_installs) then
    has_data = true
  end

  if not has_data then
    local cat = T:AddCategory(
      "text", L["No Data"],
      "columns", 1
    )
    cat:AddLine(
      "text", L["No players detected yet. Players will be detected automatically as they use the addon."]
    )
    T:SetHint(L["Wait for players to use addon features or login."])
    return
  end

  -- Build list of online players with addon
  local online = {}
  local offline = {}
  local num_total = GetNumGuildMembers(true)

  -- First, add guild members with roster info
  for i = 1, num_total do
    local name, rank, rankIndex, level, class, zone, note, officernote, online_status = GetGuildRosterInfo(i)
    if name and sepgp_installs[name] then
      local player_data = {
        name = name,
        class = class or sepgp_installs[name].class,
        level = level or "??",
        zone = zone or L["Unknown"],
        version = sepgp_installs[name].version or L["Unknown"],
        rank = rank or sepgp_installs[name].rank or L["Unknown"],
      }
      if online_status then
        table.insert(online, player_data)
      else
        table.insert(offline, player_data)
      end
    end
  end

  -- Then, add any non-guild players (from raid/party) that aren't already in the list
  for name, data in pairs(sepgp_installs) do
    local already_added = false
    for _, player in ipairs(online) do
      if player.name == name then
        already_added = true
        break
      end
    end
    for _, player in ipairs(offline) do
      if player.name == name then
        already_added = true
        break
      end
    end

    if not already_added then
      -- This is a non-guild member, check if they're online via recent activity
      local time_since = time() - (data.time or 0)
      local is_online = time_since < 300 -- Consider online if seen in last 5 minutes

      local player_data = {
        name = name,
        class = data.class or "Unknown",
        level = "??",
        zone = L["Unknown"],
        version = data.version or L["Unknown"],
        rank = data.rank or L["Unknown"],
      }

      if is_online then
        table.insert(online, player_data)
      else
        table.insert(offline, player_data)
      end
    end
  end

  -- Sort by name
  table.sort(online, function(a, b) return a.name < b.name end)
  table.sort(offline, function(a, b) return a.name < b.name end)

  -- Display online players
  if table.getn(online) > 0 then
    local cat = T:AddCategory(
      "text", C:Green(string.format(L["Online (%d)"], table.getn(online))),
      "columns", 5
    )
    cat:AddLine(
      "text", C:White(L["Name"]),
      "text2", C:White(L["Level"]),
      "text3", C:White(L["Rank"]),
      "text4", C:White(L["Zone"]),
      "text5", C:White(L["Version"])
    )
    for _, player in ipairs(online) do
      local classColor = BC:GetHexColor(player.class) or "ffffff"
      cat:AddLine(
        "text", C:Colorize(classColor, player.name),
        "text2", tostring(player.level),
        "text3", player.rank,
        "text4", player.zone,
        "text5", player.version
      )
    end
  else
    local cat = T:AddCategory(
      "text", C:Green(L["Online (0)"]),
      "columns", 1
    )
    cat:AddLine(
      "text", L["No online players detected yet."]
    )
  end

  -- Display offline players (collapsed by default)
  if table.getn(offline) > 0 then
    local cat = T:AddCategory(
      "text", C:Colorize("999999", string.format(L["Offline (%d)"], table.getn(offline))),
      "columns", 4
    )
    cat:AddLine(
      "text", C:White(L["Name"]),
      "text2", C:White(L["Level"]),
      "text3", C:White(L["Rank"]),
      "text4", C:White(L["Version"])
    )
    for _, player in ipairs(offline) do
      local classColor = BC:GetHexColor(player.class) or "888888"
      cat:AddLine(
        "text", C:Colorize(classColor, player.name),
        "text2", tostring(player.level),
        "text3", player.rank,
        "text4", player.version
      )
    end
  end

  T:SetHint(L["Right-click for options. Updates every 5 seconds."])
end
