RaidStrike = {}
local strikes = {}
local frames = {}
local groupHeaders = {}
local mainFrame = nil
local initialSyncDone = false

-- Session tracking: lastResetTime is the timestamp of the last reset
-- Data from before this timestamp is considered stale and ignored
local lastResetTime = 0

-- Class colors for vanilla WoW
local CLASS_COLORS = {
    ["WARRIOR"] = {r = 0.78, g = 0.61, b = 0.43},
    ["PALADIN"] = {r = 0.96, g = 0.55, b = 0.73},
    ["HUNTER"] = {r = 0.67, g = 0.83, b = 0.45},
    ["ROGUE"] = {r = 1.0, g = 0.96, b = 0.41},
    ["PRIEST"] = {r = 1.0, g = 1.0, b = 1.0},
    ["SHAMAN"] = {r = 0.0, g = 0.44, b = 0.87},
    ["MAGE"] = {r = 0.41, g = 0.8, b = 0.94},
    ["WARLOCK"] = {r = 0.58, g = 0.51, b = 0.79},
    ["DRUID"] = {r = 1.0, g = 0.49, b = 0.04}
}

-- Localized class name mapping for various localizations
local LOCALIZED_CLASS_LOOKUP = {
    -- English
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Shaman"] = "SHAMAN",
    ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
    -- German
    ["Krieger"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Jäger"] = "HUNTER",
    ["Schurke"] = "ROGUE", ["Priester"] = "PRIEST", ["Schamane"] = "SHAMAN",
    ["Magier"] = "MAGE", ["Hexenmeister"] = "WARLOCK", ["Druide"] = "DRUID",
    -- French
    ["Guerrier"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Chasseur"] = "HUNTER",
    ["Voleur"] = "ROGUE", ["Prêtre"] = "PRIEST", ["Chaman"] = "SHAMAN",
    ["Mage"] = "MAGE", ["Démoniste"] = "WARLOCK", ["Druide"] = "DRUID",
}

-- Check if the current player is an Officer or Supreme Leader in their guild
function RaidStrike:IsOfficer()
    local numMembers = GetNumGuildMembers()
    local playerName = UnitName("player")

    for i = 1, numMembers do
        local name, rank, rankIndex = GetGuildRosterInfo(i)
        if name == playerName then
            if rank == "Officer" or rank == "Supreme Leader" then
                return true
            end
            return false
        end
    end
    return false
end

-- Get English class name from localized
function RaidStrike:GetEnglishClass(localizedClass)
    if not localizedClass then return nil end
    
    -- Try direct lookup first (in case it's already English)
    local upperClass = string.upper(localizedClass)
    if CLASS_COLORS[upperClass] then
        return upperClass
    end
    
    -- Try localized lookup
    local englishClass = LOCALIZED_CLASS_LOOKUP[localizedClass]
    if englishClass then
        return englishClass
    end
    
    -- Fallback: return uppercase version
    return upperClass
end

-- Initialize saved variables
function RaidStrike:Initialize()
    if not RaidStrikeDB then
        RaidStrikeDB = {}
    end
    strikes = RaidStrikeDB

    -- Load the last reset timestamp (used to identify stale data)
    if not RaidStrikeResetTime then
        RaidStrikeResetTime = 0
    end
    lastResetTime = RaidStrikeResetTime
end

-- Create the main window
function RaidStrike:CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "RaidStrikeFrame", UIParent)
    mainFrame:SetWidth(260)
    mainFrame:SetHeight(320)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    mainFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    mainFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function() this:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    mainFrame:Hide()
    
    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mainFrame, "TOP", 0, -8)
    title:SetText("RaidStrike")
    title:SetTextColor(0.9, 0.9, 0.9, 1)
    
    -- Close button (much smaller custom button) - moved left to avoid scrollbar
    local closeButton = CreateFrame("Button", nil, mainFrame)
    closeButton:SetWidth(12)
    closeButton:SetHeight(12)
    closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -6)  -- Moved left to avoid scrollbar
    closeButton:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    closeButton:SetBackdropColor(0.8, 0.2, 0.2, 0.8)
    closeButton:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    
    local closeText = closeButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeText:SetPoint("CENTER", closeButton, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(1, 1, 1, 1)
    
    closeButton:SetScript("OnEnter", function()
        this:SetBackdropColor(1, 0.3, 0.3, 1)
    end)
    closeButton:SetScript("OnLeave", function()
        this:SetBackdropColor(0.8, 0.2, 0.2, 0.8)
    end)
    closeButton:SetScript("OnClick", function() mainFrame:Hide() end)
    
    -- Scroll frame with working template
    local scrollFrame = CreateFrame("ScrollFrame", "RaidStrikeScrollFrame", mainFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -25)
    scrollFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -8, 30)
    
    local content = CreateFrame("Frame", "RaidStrikeContent", scrollFrame)
    content:SetWidth(225)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    mainFrame.content = content
    mainFrame.scrollFrame = scrollFrame
    
    -- Style the automatically created scrollbar
    local function StyleScrollbar()
        local scrollBar = getglobal(scrollFrame:GetName().."ScrollBar")
        if scrollBar then
            -- Reposition to avoid close button (start lower)
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -8, -25)  -- Start lower to avoid close button
            scrollBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -8, 30)
            scrollBar:SetWidth(5)
            
            -- Apply custom styling
            scrollBar:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 8, edgeSize = 2,
                insets = {left = 1, right = 1, top = 1, bottom = 1}
            })
            scrollBar:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
            scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
            
            -- Style the thumb
            local thumb = getglobal(scrollBar:GetName().."ThumbTexture")
            if thumb then
                thumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
                thumb:SetVertexColor(0.9, 0.9, 0.9, 0.9)
                thumb:SetWidth(8)
            end
            
            -- Style the up/down buttons
            local upButton = getglobal(scrollBar:GetName().."ScrollUpButton")
            local downButton = getglobal(scrollBar:GetName().."ScrollDownButton")
            if upButton then upButton:SetWidth(0) end
            if downButton then downButton:SetWidth(0) end
        end
    end
    
    -- Style immediately and on show
    StyleScrollbar()
    scrollFrame:SetScript("OnShow", StyleScrollbar)
    
    -- Reset button (smaller and modern)
    local resetButton = CreateFrame("Button", nil, mainFrame)
    resetButton:SetWidth(50)
    resetButton:SetHeight(16)
    resetButton:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 8)
    resetButton:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    resetButton:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    resetButton:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    
    local resetText = resetButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetText:SetPoint("CENTER", resetButton, "CENTER", 0, 0)
    resetText:SetText("Reset")
    resetText:SetTextColor(0.9, 0.9, 0.9, 1)
    
    resetButton:SetScript("OnEnter", function()
        this:SetBackdropColor(0.3, 0.3, 0.3, 1)
    end)
    resetButton:SetScript("OnLeave", function()
        this:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    end)
    resetButton:SetScript("OnClick", function()
        RaidStrike:ResetAllStrikes()
    end)
    mainFrame.resetButton = resetButton
end

-- Create player frame
function RaidStrike:CreatePlayerFrame(parent, index)
    local frame = CreateFrame("Frame", "RaidStrikePlayer"..index, parent)
    frame:SetWidth(225)
    frame:SetHeight(16)
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil,
        tile = true, tileSize = 16,
        insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    frame:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
    
    -- Enable mouse interaction for hover effects
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function()
        this:SetBackdropColor(0.25, 0.35, 0.45, 0.8)  -- Highlight color (blue-ish)
    end)
    frame:SetScript("OnLeave", function()
        this:SetBackdropColor(0.15, 0.15, 0.15, 0.6)  -- Original color
    end)
    
    -- Strike count with minimal background (circle)
    local strikeCircle = CreateFrame("Frame", nil, frame)
    strikeCircle:SetWidth(14)
    strikeCircle:SetHeight(14)
    strikeCircle:SetPoint("LEFT", frame, "LEFT", 2, 0)
    strikeCircle:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    frame.strikeCircle = strikeCircle

    local strikeText = strikeCircle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    strikeText:SetPoint("CENTER", strikeCircle, "CENTER", 0, 0)
    strikeText:SetText("0")
    strikeText:SetTextColor(1, 1, 1, 1)
    frame.strikeText = strikeText

    -- Player name
    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", strikeCircle, "RIGHT", 3, 0)
    nameText:SetWidth(90)
    nameText:SetJustifyH("LEFT")
    frame.nameText = nameText
    
    -- Minus button (modern small button)
    local minusButton = CreateFrame("Button", nil, frame)
    minusButton:SetWidth(12)
    minusButton:SetHeight(12)
    minusButton:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    minusButton:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    minusButton:SetBackdropColor(0.2, 0.6, 0.2, 0.8)
    minusButton:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local minusText = minusButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minusText:SetPoint("CENTER", minusButton, "CENTER", 0, 0)
    minusText:SetText("-")
    minusText:SetTextColor(1, 1, 1, 1)

    minusButton:SetScript("OnEnter", function()
        this:SetBackdropColor(0.3, 0.8, 0.3, 1)
    end)
    minusButton:SetScript("OnLeave", function()
        this:SetBackdropColor(0.2, 0.6, 0.2, 0.8)
    end)
    frame.minusButton = minusButton

    -- Plus button (modern small button)
    local plusButton = CreateFrame("Button", nil, frame)
    plusButton:SetWidth(12)
    plusButton:SetHeight(12)
    plusButton:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    plusButton:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    plusButton:SetBackdropColor(0.6, 0.2, 0.2, 0.8)
    plusButton:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local plusText = plusButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    plusText:SetPoint("CENTER", plusButton, "CENTER", 0, 0)
    plusText:SetText("+")
    plusText:SetTextColor(1, 1, 1, 1)

    plusButton:SetScript("OnEnter", function()
        this:SetBackdropColor(0.8, 0.3, 0.3, 1)
    end)
    plusButton:SetScript("OnLeave", function()
        this:SetBackdropColor(0.6, 0.2, 0.2, 0.8)
    end)
    frame.plusButton = plusButton

    frame:Hide()
    return frame
end

function RaidStrike:UpdateRaidDisplay()
    if not mainFrame or not mainFrame:IsVisible() then return end

    -- Check if player is an officer (can modify strikes)
    local isOfficer = RaidStrike:IsOfficer()

    -- Show/hide reset button based on officer status
    if mainFrame.resetButton then
        if isOfficer then
            mainFrame.resetButton:Show()
        else
            mainFrame.resetButton:Hide()
        end
    end

    -- Hide all existing frames and group headers
    for i = 1, table.getn(frames) do
        frames[i]:Hide()
    end
    for i = 1, table.getn(groupHeaders) do
        groupHeaders[i]:Hide()
    end

    local frameIndex = 1
    local headerIndex = 1
    local yOffset = -2
    local raidSize = GetNumRaidMembers()

    -- Store officer status for use when creating player frames
    mainFrame.isOfficer = isOfficer
    
    if raidSize > 0 then
        -- Raid groups
        for group = 1, 8 do
            local groupMembers = {}
            
            for i = 1, raidSize do
                local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
                if subgroup == group and name then
                    table.insert(groupMembers, {name = name, class = class})
                end
            end
            
            if table.getn(groupMembers) > 0 then
                -- Group header (reuse existing or create new)
                if not groupHeaders[headerIndex] then
                    groupHeaders[headerIndex] = mainFrame.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                end
                
                local groupHeader = groupHeaders[headerIndex]
                groupHeader:ClearAllPoints()
                groupHeader:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 2, yOffset)
                groupHeader:SetText("Group " .. group)
                groupHeader:SetTextColor(0.6, 0.6, 0.6, 1)
                groupHeader:Show()
                headerIndex = headerIndex + 1
                yOffset = yOffset - 10
                
                -- Group members
                for j = 1, table.getn(groupMembers) do
                    local member = groupMembers[j]
                    
                    if not frames[frameIndex] then
                        frames[frameIndex] = RaidStrike:CreatePlayerFrame(mainFrame.content, frameIndex)
                    end
                    
                    local frame = frames[frameIndex]
                    frame:ClearAllPoints()
                    frame:SetPoint("TOPLEFT", mainFrame.content, "TOPLEFT", 0, yOffset)
                    frame:Show()
                    
                    -- Set name and color
                    frame.nameText:SetText(member.name)
                    local englishClass = RaidStrike:GetEnglishClass(member.class)
                    local color = CLASS_COLORS[englishClass] or {r = 0.5, g = 0.5, b = 0.5}
                    frame.nameText:SetTextColor(color.r, color.g, color.b, 1)
                    
                    -- Store player name on frame for click handlers
                    frame.playerName = member.name

                    -- Update strike count with color coding
                    local strikeCount = strikes[member.name] or 0
                    frame.strikeText:SetText(tostring(strikeCount))
                    if strikeCount == 0 then
                        frame.strikeCircle:SetBackdropColor(0.2, 0.7, 0.2, 0.7)
                        frame.strikeCircle:SetBackdropBorderColor(0.1, 0.5, 0.1, 0.9)
                    else
                        frame.strikeCircle:SetBackdropColor(0.8, 0.2, 0.2, 0.7)
                        frame.strikeCircle:SetBackdropBorderColor(0.6, 0.1, 0.1, 0.9)
                    end

                    -- Show/hide buttons based on officer status
                    if isOfficer then
                        frame.plusButton:Show()
                        frame.minusButton:Show()
                        -- Set button handlers (use stored playerName to avoid closure issues)
                        frame.plusButton:SetScript("OnClick", function()
                            RaidStrike:AddStrike(this:GetParent().playerName)
                        end)
                        frame.minusButton:SetScript("OnClick", function()
                            RaidStrike:RemoveStrike(this:GetParent().playerName)
                        end)
                    else
                        frame.plusButton:Hide()
                        frame.minusButton:Hide()
                    end

                    frameIndex = frameIndex + 1
                    yOffset = yOffset - 16
                end

                yOffset = yOffset - 2
            end
        end
    end

    -- Update content height and refresh scroll frame
    local contentHeight = math.abs(yOffset) + 20
    mainFrame.content:SetHeight(contentHeight)
    
    -- Force the scroll frame to update its scrollable range
    -- This is the key fix for the scrolling issue
    if mainFrame.scrollFrame then
        mainFrame.scrollFrame:UpdateScrollChildRect()
        
        -- Also ensure the scroll position is valid
        local maxScroll = math.max(0, contentHeight - mainFrame.scrollFrame:GetHeight())
        local currentScroll = mainFrame.scrollFrame:GetVerticalScroll()
        if currentScroll > maxScroll then
            mainFrame.scrollFrame:SetVerticalScroll(maxScroll)
        end
    end
end

-- Add strike
function RaidStrike:AddStrike(playerName)
    strikes[playerName] = (strikes[playerName] or 0) + 1
    RaidStrikeDB[playerName] = strikes[playerName]

    -- Send raid warning
    SendChatMessage(playerName .. " received a strike! (Total: " .. strikes[playerName] .. ")", "RAID_WARNING")

    -- Send sync message (operation-based, not absolute value)
    RaidStrike:SendSync("ADD", playerName)

    -- Update display
    RaidStrike:UpdateRaidDisplay()
end

-- Remove strike
function RaidStrike:RemoveStrike(playerName)
    if not strikes[playerName] or strikes[playerName] <= 0 then return end

    strikes[playerName] = strikes[playerName] - 1
    RaidStrikeDB[playerName] = strikes[playerName]

    -- Send raid warning
    SendChatMessage(playerName .. " had a strike removed! (Total: " .. strikes[playerName] .. ")", "RAID_WARNING")

    -- Send sync message (operation-based, not absolute value)
    RaidStrike:SendSync("REMOVE", playerName)

    -- Update display
    RaidStrike:UpdateRaidDisplay()
end

-- Reset all strikes and start a new session
function RaidStrike:ResetAllStrikes()
    -- Generate new session epoch (current timestamp)
    lastResetTime = time()
    RaidStrikeResetTime = lastResetTime

    -- Clear all strikes
    strikes = {}
    RaidStrikeDB = {}

    SendChatMessage("All strikes have been reset!", "RAID_WARNING")

    -- Broadcast the new session epoch to all officers
    -- They will adopt this new epoch and clear their data
    if GetNumRaidMembers() > 0 then
        local message = "RESET:" .. lastResetTime
        SendAddonMessage("RAIDSTRIKE", message, "RAID")
    end

    -- Update display
    RaidStrike:UpdateRaidDisplay()
end

-- Request full sync from other officers
function RaidStrike:RequestSync()
    if GetNumRaidMembers() == 0 then return end
    local message = "REQUEST:" .. lastResetTime
    SendAddonMessage("RAIDSTRIKE", message, "RAID")
end

-- Send sync message (all messages include reset time for epoch validation)
function RaidStrike:SendSync(action, playerName)
    local message
    if action == "ADD" or action == "REMOVE" then
        -- Operation-based: send action, player name, and reset time
        message = action .. ":" .. playerName .. ":" .. lastResetTime
    elseif action == "SYNC" then
        -- Full data sync: send player name, count, and reset time
        local strikeCount = strikes[playerName] or 0
        message = "SYNC:" .. playerName .. ":" .. strikeCount .. ":" .. lastResetTime
    end

    if message and GetNumRaidMembers() > 0 then
        SendAddonMessage("RAIDSTRIKE", message, "RAID")
    end
end

-- Send all strike data (for responding to sync requests)
function RaidStrike:SendFullSync()
    if GetNumRaidMembers() == 0 then return end

    -- First send our epoch so the receiver knows our session
    local epochMsg = "EPOCH:" .. lastResetTime
    SendAddonMessage("RAIDSTRIKE", epochMsg, "RAID")

    -- Then send all strike data
    for name, count in pairs(strikes) do
        if count and count > 0 then
            local message = "SYNC:" .. name .. ":" .. count .. ":" .. lastResetTime
            SendAddonMessage("RAIDSTRIKE", message, "RAID")
        end
    end
end

-- Handle sync message
function RaidStrike:HandleSync(message, sender)
    if sender == UnitName("player") then return end  -- Ignore own messages

    -- Parse the message
    local parts = RaidStrike:ParseSyncMessage(message)
    local action = parts[1]

    if action == "ADD" then
        local playerName = parts[2]
        local incomingResetTime = tonumber(parts[3]) or 0

        -- Check epoch: only accept if from same or newer session
        if incomingResetTime > lastResetTime then
            -- They have a newer session, adopt it first
            RaidStrike:AdoptNewEpoch(incomingResetTime)
        end

        if incomingResetTime >= lastResetTime then
            -- Same session or we just adopted theirs, apply the operation
            strikes[playerName] = (strikes[playerName] or 0) + 1
            RaidStrikeDB[playerName] = strikes[playerName]
            RaidStrike:UpdateRaidDisplay()
        end
        -- If incomingResetTime < lastResetTime, ignore (stale data from old session)

    elseif action == "REMOVE" then
        local playerName = parts[2]
        local incomingResetTime = tonumber(parts[3]) or 0

        if incomingResetTime > lastResetTime then
            RaidStrike:AdoptNewEpoch(incomingResetTime)
        end

        if incomingResetTime >= lastResetTime then
            if strikes[playerName] and strikes[playerName] > 0 then
                strikes[playerName] = strikes[playerName] - 1
                RaidStrikeDB[playerName] = strikes[playerName]
            end
            RaidStrike:UpdateRaidDisplay()
        end

    elseif action == "RESET" then
        -- Another officer triggered a reset with a new epoch
        local incomingResetTime = tonumber(parts[2]) or 0

        if incomingResetTime > lastResetTime then
            -- New session started, adopt it and clear our data
            RaidStrike:AdoptNewEpoch(incomingResetTime)
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00RaidStrike: " .. sender .. " has reset all strikes. New session started.|r")
            RaidStrike:UpdateRaidDisplay()
        end

    elseif action == "EPOCH" then
        -- Receiving epoch info (sent before SYNC data)
        local incomingResetTime = tonumber(parts[2]) or 0

        if incomingResetTime > lastResetTime then
            -- They have a newer session, adopt it (clears our stale data)
            RaidStrike:AdoptNewEpoch(incomingResetTime)
        end

    elseif action == "REQUEST" then
        -- Another officer is requesting sync
        local theirResetTime = tonumber(parts[2]) or 0

        -- Only send our data if we have the same or newer epoch
        -- If they have a newer epoch, they'll send us their data instead
        if lastResetTime >= theirResetTime then
            RaidStrike:SendFullSync()
        end

    elseif action == "SYNC" then
        -- Receiving sync data
        local playerName = parts[2]
        local incomingCount = tonumber(parts[3]) or 0
        local incomingResetTime = tonumber(parts[4]) or 0

        if incomingResetTime > lastResetTime then
            -- They have a newer session, adopt it first (clears stale data)
            RaidStrike:AdoptNewEpoch(incomingResetTime)
        end

        if incomingResetTime >= lastResetTime then
            -- Same session, accept the data
            -- Use the incoming count directly (they have authoritative data for this sync)
            local currentCount = strikes[playerName] or 0
            if incomingCount ~= currentCount then
                strikes[playerName] = incomingCount
                RaidStrikeDB[playerName] = incomingCount
                RaidStrike:UpdateRaidDisplay()
            end
        end
        -- If incomingResetTime < lastResetTime, ignore (stale data from old session)
    end
end

-- Adopt a new epoch (session), clearing any stale data
function RaidStrike:AdoptNewEpoch(newResetTime)
    lastResetTime = newResetTime
    RaidStrikeResetTime = newResetTime
    strikes = {}
    RaidStrikeDB = {}
end

-- Parse sync message into components
function RaidStrike:ParseSyncMessage(message)
    local parts = {}
    local from = 1
    local delim_from, delim_to = string.find(message, ":", from)
    while delim_from do
        table.insert(parts, string.sub(message, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(message, ":", from)
    end
    table.insert(parts, string.sub(message, from))

    return parts
end

-- Slash command
SLASH_RAIDSTRIKE1 = "/strike"
SlashCmdList["RAIDSTRIKE"] = function(msg)
    if not mainFrame then
        RaidStrike:CreateMainFrame()
    end
    
    if mainFrame:IsVisible() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RaidStrike:UpdateRaidDisplay()
    end
end

-- Event frame
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Timer frame for delayed sync requests
local timerFrame = CreateFrame("Frame")
timerFrame.elapsed = 0
timerFrame.delay = 0
timerFrame.callback = nil
timerFrame:Hide()

timerFrame:SetScript("OnUpdate", function()
    timerFrame.elapsed = timerFrame.elapsed + arg1
    if timerFrame.elapsed >= timerFrame.delay then
        timerFrame:Hide()
        if timerFrame.callback then
            timerFrame.callback()
        end
    end
end)

-- Schedule a delayed function call
function RaidStrike:ScheduleTimer(delay, callback)
    timerFrame.elapsed = 0
    timerFrame.delay = delay
    timerFrame.callback = callback
    timerFrame:Show()
end

-- Track if we were in a raid before
local wasInRaid = false

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "shootyepgp" then
        RaidStrike:Initialize()
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00RaidStrike loaded! Type /strike to open.|r")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Request sync after a short delay when entering world (covers login, reload, zone changes)
        RaidStrike:ScheduleTimer(3, function()
            if GetNumRaidMembers() > 0 then
                if not initialSyncDone then
                    initialSyncDone = true
                    RaidStrike:RequestSync()
                end
            end
        end)

    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        local inRaid = GetNumRaidMembers() > 0

        -- If we just joined a raid, request sync after a short delay
        if inRaid and not wasInRaid then
            RaidStrike:ScheduleTimer(2, function()
                RaidStrike:RequestSync()
            end)
        end

        wasInRaid = inRaid
        RaidStrike:UpdateRaidDisplay()

    elseif event == "CHAT_MSG_ADDON" and arg1 == "RAIDSTRIKE" then
        RaidStrike:HandleSync(arg2, arg4)
    end
end)