-- Matrix - Keeper Gnarlmoon Team Assignment Tool
-- Only usable by Officers and Supreme Leaders
-- Assigns raid members to Red (Left) or Blue (Right) teams

local C = AceLibrary("Crayon-2.0")
local BC = AceLibrary("Babble-Class-2.2")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")

-- Module creation
sepgp_matrix = sepgp:NewModule("sepgp_matrix", "AceEvent-2.0")

-- Local state
local playerAssignments = {} -- [playerName] = "red" or "blue" or nil
local raidRoster = {} -- Current raid roster cache
local matrixFrame = nil
local playerFrames = {} -- UI frames for each player
local isUpdating = false

-- Constants
local FRAME_WIDTH = 670
local FRAME_HEIGHT = 410
local PLAYER_WIDTH = 105
local PLAYER_HEIGHT = 16
local CHECKBOX_SIZE = 12
local GROUP_HEADER_HEIGHT = 18
local COLUMNS = 4
local GROUPS_PER_COLUMN = 2

-- Colors
local COLOR_RED = {r = 0.9, g = 0.2, b = 0.2}
local COLOR_BLUE = {r = 0.2, g = 0.4, b = 0.9}
local COLOR_AWKWARD = {r = 0.7, g = 0.7, b = 0.7}
local COLOR_RED_BG = {r = 0.5, g = 0.1, b = 0.1, a = 0.6}
local COLOR_BLUE_BG = {r = 0.1, g = 0.2, b = 0.5, a = 0.6}

-------------------------------------------------------------------------------
-- Permission Check
-------------------------------------------------------------------------------
local function canUseMatrix()
    -- Check if player is in a raid
    if GetNumRaidMembers() == 0 then
        return false, "You must be in a raid to use this feature."
    end

    -- Check guild rank
    local guildName, guildRankName = GetGuildInfo("player")
    if not guildName then
        return false, "You must be in a guild to use this feature."
    end

    -- Check for Officer or Supreme leader rank, or raid leader/assistant
    if guildRankName == "Officer" or guildRankName == "Supreme leader" then
        return true
    end

    -- Also allow raid leaders and assistants
    if IsRaidLeader() or IsRaidOfficer() then
        return true
    end

    return false, "Only Officers or Supreme Leaders can use this feature."
end

-------------------------------------------------------------------------------
-- Raid Roster Management
-------------------------------------------------------------------------------
local function buildRaidRoster()
    local roster = {}
    local numRaid = GetNumRaidMembers()

    if numRaid == 0 then
        return roster
    end

    for i = 1, numRaid do
        local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
        if name then
            table.insert(roster, {
                name = name,
                class = fileName or class,
                subgroup = subgroup,
                online = online,
                index = i
            })
        end
    end

    -- Sort by subgroup, then by name
    table.sort(roster, function(a, b)
        if a.subgroup ~= b.subgroup then
            return a.subgroup < b.subgroup
        end
        return a.name < b.name
    end)

    return roster
end

-------------------------------------------------------------------------------
-- Pill Counter Calculations
-------------------------------------------------------------------------------
local function calculatePillCounts()
    local numRaid = GetNumRaidMembers()
    local halfCount = math.floor(numRaid / 2)
    local awkwardCount = numRaid - (halfCount * 2) -- 0 or 1

    -- Count current assignments
    local redAssigned = 0
    local blueAssigned = 0

    for _, player in ipairs(raidRoster) do
        local assignment = playerAssignments[player.name]
        if assignment == "red" then
            redAssigned = redAssigned + 1
        elseif assignment == "blue" then
            blueAssigned = blueAssigned + 1
        end
    end

    -- Calculate remaining pills
    local redRemaining = halfCount - redAssigned
    local blueRemaining = halfCount - blueAssigned

    -- Handle overflow into awkward
    local awkwardUsed = 0
    if redRemaining < 0 then
        awkwardUsed = awkwardUsed - redRemaining
        redRemaining = 0
    end
    if blueRemaining < 0 then
        awkwardUsed = awkwardUsed - blueRemaining
        blueRemaining = 0
    end

    local awkwardRemaining = awkwardCount - awkwardUsed
    if awkwardRemaining < 0 then awkwardRemaining = 0 end

    return {
        redTotal = halfCount,
        blueTotal = halfCount,
        awkwardTotal = awkwardCount,
        redRemaining = redRemaining,
        blueRemaining = blueRemaining,
        awkwardRemaining = awkwardRemaining,
        redAssigned = redAssigned,
        blueAssigned = blueAssigned
    }
end

-------------------------------------------------------------------------------
-- UI Helper Functions
-------------------------------------------------------------------------------
local function getClassColor(class)
    if class and BC:GetHexColor(class) then
        return BC:GetHexColor(class)
    end
    return "ffffff"
end

local function createPillIndicator(parent, color, x, y, name)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetWidth(80)
    frame:SetHeight(24)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    -- Count text
    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.count:SetPoint("LEFT", 4, 0)
    frame.count:SetText("0")
    frame.count:SetTextColor(1, 1, 1)

    return frame
end

-- Check if a color can be assigned (has remaining pills)
local function canAssignColor(colorType)
    local counts = calculatePillCounts()

    if colorType == "red" then
        -- Can assign red if red pills remain, or if awkward remains and red is full
        return counts.redRemaining > 0 or counts.awkwardRemaining > 0
    elseif colorType == "blue" then
        -- Can assign blue if blue pills remain, or if awkward remains and blue is full
        return counts.blueRemaining > 0 or counts.awkwardRemaining > 0
    end

    return false
end

local function createSmallCheckbox(parent, color, onClick)
    local cb = CreateFrame("Button", nil, parent)
    cb:SetWidth(CHECKBOX_SIZE)
    cb:SetHeight(CHECKBOX_SIZE)

    -- Border (outer colored frame)
    cb.border = cb:CreateTexture(nil, "BORDER")
    cb.border:SetPoint("TOPLEFT", cb, "TOPLEFT", 0, 0)
    cb.border:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", 0, 0)
    cb.border:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    cb.border:SetVertexColor(color.r, color.g, color.b, 1)

    -- Dark background (inner area)
    cb.bg = cb:CreateTexture(nil, "ARTWORK")
    cb.bg:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -1)
    cb.bg:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, 1)
    cb.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    cb.bg:SetVertexColor(0.1, 0.1, 0.1, 0.9)

    -- Fill (shown when checked)
    cb.fill = cb:CreateTexture(nil, "OVERLAY")
    cb.fill:SetPoint("TOPLEFT", cb, "TOPLEFT", 1, -1)
    cb.fill:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -1, 1)
    cb.fill:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    cb.fill:SetVertexColor(color.r, color.g, color.b, 1)
    cb.fill:Hide()

    cb.isChecked = false
    cb.color = color

    cb:SetScript("OnClick", function()
        if onClick then
            onClick(this)
        end
    end)

    -- Hover effect - slightly brighten the border
    cb:SetScript("OnEnter", function()
        local brighten = 0.3
        local r = math.min(1, this.color.r + brighten)
        local g = math.min(1, this.color.g + brighten)
        local b = math.min(1, this.color.b + brighten)
        this.border:SetVertexColor(r, g, b, 1)
    end)

    cb:SetScript("OnLeave", function()
        this.border:SetVertexColor(this.color.r, this.color.g, this.color.b, 1)
    end)

    return cb
end

local function setCheckboxState(cb, checked)
    cb.isChecked = checked
    if checked then
        cb.fill:Show()
    else
        cb.fill:Hide()
    end
end

-------------------------------------------------------------------------------
-- Update Functions
-------------------------------------------------------------------------------
local function updatePillIndicators()
    if not matrixFrame then return end

    local counts = calculatePillCounts()

    -- Update remaining pills (top)
    matrixFrame.redPillRemaining.count:SetText(tostring(counts.redRemaining))
    matrixFrame.bluePillRemaining.count:SetText(tostring(counts.blueRemaining))
    matrixFrame.awkwardRemaining.count:SetText(tostring(counts.awkwardRemaining))

    -- Update assigned pills (bottom)
    matrixFrame.redPillAssigned.count:SetText(tostring(counts.redAssigned))
    matrixFrame.bluePillAssigned.count:SetText(tostring(counts.blueAssigned))

    -- Update button state - only enable when all pills are assigned
    local allAssigned = (counts.redRemaining == 0 and counts.blueRemaining == 0 and counts.awkwardRemaining == 0)
    if allAssigned then
        matrixFrame.assignButton:Enable()
        matrixFrame.assignButton:SetTextColor(1, 1, 1)
    else
        matrixFrame.assignButton:Disable()
        matrixFrame.assignButton:SetTextColor(0.5, 0.5, 0.5)
    end
end

local function updatePlayerFrame(playerFrame, playerData)
    if not playerFrame or not playerData then return end

    local assignment = playerAssignments[playerData.name]

    -- Update background color
    if assignment == "red" then
        playerFrame.bg:SetVertexColor(COLOR_RED_BG.r, COLOR_RED_BG.g, COLOR_RED_BG.b, COLOR_RED_BG.a)
        playerFrame.bg:Show()
    elseif assignment == "blue" then
        playerFrame.bg:SetVertexColor(COLOR_BLUE_BG.r, COLOR_BLUE_BG.g, COLOR_BLUE_BG.b, COLOR_BLUE_BG.a)
        playerFrame.bg:Show()
    else
        playerFrame.bg:Hide()
    end

    -- Update checkbox states
    setCheckboxState(playerFrame.redCB, assignment == "red")
    setCheckboxState(playerFrame.blueCB, assignment == "blue")
end

local function createPlayerFrame(parent, playerData, x, y)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(PLAYER_WIDTH)
    frame:SetHeight(PLAYER_HEIGHT)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    -- Background (for assignment highlight)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    frame.bg:Hide()

    -- Red checkbox
    frame.redCB = createSmallCheckbox(frame, COLOR_RED, function(cb)
        local name = frame.playerName
        if not name then return end

        local currentAssignment = playerAssignments[name]
        if currentAssignment == "red" then
            -- Unassign
            playerAssignments[name] = nil
        else
            -- Check if we can assign red
            if not canAssignColor("red") then
                return -- No red pills available
            end
            -- Assign to red
            playerAssignments[name] = "red"
        end
        updatePlayerFrame(frame, {name = name})
        updatePillIndicators()
    end)
    frame.redCB:SetPoint("LEFT", 2, 0)

    -- Blue checkbox
    frame.blueCB = createSmallCheckbox(frame, COLOR_BLUE, function(cb)
        local name = frame.playerName
        if not name then return end

        local currentAssignment = playerAssignments[name]
        if currentAssignment == "blue" then
            -- Unassign
            playerAssignments[name] = nil
        else
            -- Check if we can assign blue
            if not canAssignColor("blue") then
                return -- No blue pills available
            end
            -- Assign to blue
            playerAssignments[name] = "blue"
        end
        updatePlayerFrame(frame, {name = name})
        updatePillIndicators()
    end)
    frame.blueCB:SetPoint("LEFT", frame.redCB, "RIGHT", 3, 0)

    -- Player name
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.nameText:SetPoint("LEFT", frame.blueCB, "RIGHT", 4, 0)
    frame.nameText:SetWidth(PLAYER_WIDTH - 30)
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetText("")

    frame.playerName = nil

    return frame
end

local function createGroupHeader(parent, groupNum, x, y)
    local header = CreateFrame("Frame", nil, parent)
    header:SetWidth(PLAYER_WIDTH)
    header:SetHeight(GROUP_HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    -- Background
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    header.bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)

    -- Text
    header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.text:SetPoint("LEFT", 4, 0)
    header.text:SetText("Group " .. groupNum)
    header.text:SetTextColor(1, 0.82, 0) -- Gold

    return header
end

-------------------------------------------------------------------------------
-- Main UI Creation
-------------------------------------------------------------------------------
local function createMatrixFrame()
    if matrixFrame then
        return matrixFrame
    end

    -- Main frame
    local frame = CreateFrame("Frame", "ShootyMatrixFrame", UIParent)
    frame:SetWidth(FRAME_WIDTH)
    frame:SetHeight(FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() this:StartMoving() end)
    frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    frame:Hide()

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Title bar
    frame.titleBar = CreateFrame("Frame", nil, frame)
    frame.titleBar:SetHeight(24)
    frame.titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
    frame.titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    frame.titleBar.bg = frame.titleBar:CreateTexture(nil, "BACKGROUND")
    frame.titleBar.bg:SetAllPoints()
    frame.titleBar.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    frame.titleBar.bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)

    frame.titleText = frame.titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.titleText:SetPoint("LEFT", 8, 0)
    frame.titleText:SetText("Matrix - Keeper Gnarlmoon Assignment")
    frame.titleText:SetTextColor(1, 0.82, 0) -- Gold

    -- Close button
    frame.closeBtn = CreateFrame("Button", nil, frame.titleBar, "UIPanelCloseButton")
    frame.closeBtn:SetPoint("TOPRIGHT", frame.titleBar, "TOPRIGHT", 3, 3)
    frame.closeBtn:SetScript("OnClick", function() frame:Hide() end)

    -- Pill indicators section (top) - "Pills to assign"
    frame.pillSection = CreateFrame("Frame", nil, frame)
    frame.pillSection:SetHeight(50)
    frame.pillSection:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -32)
    frame.pillSection:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -32)

    frame.pillSection.bg = frame.pillSection:CreateTexture(nil, "BACKGROUND")
    frame.pillSection.bg:SetAllPoints()
    frame.pillSection.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    frame.pillSection.bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

    frame.pillSection.title = frame.pillSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.pillSection.title:SetPoint("TOP", 0, -4)
    frame.pillSection.title:SetText("Pills to Distribute")
    frame.pillSection.title:SetTextColor(0.8, 0.8, 0.8)

    -- Pill indicators
    frame.redPillRemaining = createPillIndicator(frame.pillSection, COLOR_RED, 175, -20, "MatrixRedPillRemaining")
    frame.redPillRemaining.label = frame.redPillRemaining:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.redPillRemaining.label:SetPoint("LEFT", frame.redPillRemaining.count, "RIGHT", 4, 0)
    frame.redPillRemaining.label:SetText("Red (Left)")
    frame.redPillRemaining.label:SetTextColor(COLOR_RED.r, COLOR_RED.g, COLOR_RED.b)

    frame.bluePillRemaining = createPillIndicator(frame.pillSection, COLOR_BLUE, 295, -20, "MatrixBluePillRemaining")
    frame.bluePillRemaining.label = frame.bluePillRemaining:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.bluePillRemaining.label:SetPoint("LEFT", frame.bluePillRemaining.count, "RIGHT", 4, 0)
    frame.bluePillRemaining.label:SetText("Blue (Right)")
    frame.bluePillRemaining.label:SetTextColor(COLOR_BLUE.r, COLOR_BLUE.g, COLOR_BLUE.b)

    frame.awkwardRemaining = createPillIndicator(frame.pillSection, COLOR_AWKWARD, 425, -20, "MatrixAwkwardRemaining")
    frame.awkwardRemaining.label = frame.awkwardRemaining:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.awkwardRemaining.label:SetPoint("LEFT", frame.awkwardRemaining.count, "RIGHT", 4, 0)
    frame.awkwardRemaining.label:SetText("Awkward")
    frame.awkwardRemaining.label:SetTextColor(COLOR_AWKWARD.r, COLOR_AWKWARD.g, COLOR_AWKWARD.b)

    -- Player list container (scrollable area)
    frame.playerContainer = CreateFrame("Frame", nil, frame)
    frame.playerContainer:SetPoint("TOPLEFT", frame.pillSection, "BOTTOMLEFT", 0, -8)
    frame.playerContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 80)

    frame.playerContainer.bg = frame.playerContainer:CreateTexture(nil, "BACKGROUND")
    frame.playerContainer.bg:SetAllPoints()
    frame.playerContainer.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    frame.playerContainer.bg:SetVertexColor(0.08, 0.08, 0.08, 0.5)

    -- Assigned section (bottom) - "Pills taken"
    frame.assignedSection = CreateFrame("Frame", nil, frame)
    frame.assignedSection:SetHeight(40)
    frame.assignedSection:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 36)
    frame.assignedSection:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 36)

    frame.assignedSection.bg = frame.assignedSection:CreateTexture(nil, "BACKGROUND")
    frame.assignedSection.bg:SetAllPoints()
    frame.assignedSection.bg:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    frame.assignedSection.bg:SetVertexColor(0.1, 0.1, 0.1, 0.7)

    frame.assignedSection.title = frame.assignedSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.assignedSection.title:SetPoint("TOP", 0, -4)
    frame.assignedSection.title:SetText("Pills Taken")
    frame.assignedSection.title:SetTextColor(0.8, 0.8, 0.8)

    frame.redPillAssigned = createPillIndicator(frame.assignedSection, COLOR_RED, 220, -18, "MatrixRedPillAssigned")
    frame.redPillAssigned.label = frame.redPillAssigned:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.redPillAssigned.label:SetPoint("LEFT", frame.redPillAssigned.count, "RIGHT", 4, 0)
    frame.redPillAssigned.label:SetText("Red")
    frame.redPillAssigned.label:SetTextColor(COLOR_RED.r, COLOR_RED.g, COLOR_RED.b)

    frame.bluePillAssigned = createPillIndicator(frame.assignedSection, COLOR_BLUE, 360, -18, "MatrixBluePillAssigned")
    frame.bluePillAssigned.label = frame.bluePillAssigned:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.bluePillAssigned.label:SetPoint("LEFT", frame.bluePillAssigned.count, "RIGHT", 4, 0)
    frame.bluePillAssigned.label:SetText("Blue")
    frame.bluePillAssigned.label:SetTextColor(COLOR_BLUE.r, COLOR_BLUE.g, COLOR_BLUE.b)

    -- Reset button
    frame.resetButton = CreateFrame("Button", "MatrixResetButton", frame, "UIPanelButtonTemplate")
    frame.resetButton:SetWidth(80)
    frame.resetButton:SetHeight(24)
    frame.resetButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 80, 8)
    frame.resetButton:SetText("Reset")
    frame.resetButton:SetScript("OnClick", function()
        sepgp_matrix:ResetAssignments()
    end)

    -- Assign button
    frame.assignButton = CreateFrame("Button", "MatrixAssignButton", frame, "UIPanelButtonTemplate")
    frame.assignButton:SetWidth(140)
    frame.assignButton:SetHeight(24)
    frame.assignButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -80, 8)
    frame.assignButton:SetText("Announce Teams")
    frame.assignButton:Disable()
    frame.assignButton:SetScript("OnClick", function()
        sepgp_matrix:AnnounceTeams()
    end)

    -- Make escapable
    sepgp:make_escable("ShootyMatrixFrame", "add")

    matrixFrame = frame
    return frame
end

-------------------------------------------------------------------------------
-- Refresh Display
-------------------------------------------------------------------------------
local function refreshPlayerList()
    if not matrixFrame then return end
    if isUpdating then return end
    isUpdating = true

    -- Hide all existing player frames
    for _, pf in pairs(playerFrames) do
        if pf and pf.Hide then
            pf:Hide()
        end
    end

    -- Get current roster
    raidRoster = buildRaidRoster()

    -- Clean up assignments for players no longer in raid
    local rosterLookup = {}
    for _, player in ipairs(raidRoster) do
        rosterLookup[player.name] = true
    end

    for name, _ in pairs(playerAssignments) do
        if not rosterLookup[name] then
            playerAssignments[name] = nil
        end
    end

    -- Create player frames organized by group
    local groups = {}
    for i = 1, 8 do
        groups[i] = {}
    end

    for _, player in ipairs(raidRoster) do
        local g = player.subgroup
        if g and g >= 1 and g <= 8 then
            table.insert(groups[g], player)
        end
    end

    -- Layout: 4 columns, 2 groups per column
    local COLUMN_WIDTH = 175
    local START_Y = -8
    local GROUP_SPACING = 4

    local playerIndex = 0

    for col = 1, 4 do
        local x = (col - 1) * COLUMN_WIDTH + 8
        local y = START_Y

        local startGroup = (col - 1) * 2 + 1
        local endGroup = col * 2

        for groupNum = startGroup, endGroup do
            local groupPlayers = groups[groupNum]

            if groupPlayers and table.getn(groupPlayers) > 0 then
                -- Create group header
                local headerKey = "header_" .. groupNum
                if not playerFrames[headerKey] then
                    playerFrames[headerKey] = createGroupHeader(matrixFrame.playerContainer, groupNum, x, y)
                else
                    playerFrames[headerKey]:SetPoint("TOPLEFT", matrixFrame.playerContainer, "TOPLEFT", x, y)
                end
                playerFrames[headerKey].text:SetText("Group " .. groupNum)
                playerFrames[headerKey]:Show()

                y = y - GROUP_HEADER_HEIGHT

                -- Create player frames
                for _, player in ipairs(groupPlayers) do
                    playerIndex = playerIndex + 1
                    local key = "player_" .. playerIndex

                    if not playerFrames[key] then
                        playerFrames[key] = createPlayerFrame(matrixFrame.playerContainer, player, x, y)
                    else
                        playerFrames[key]:SetPoint("TOPLEFT", matrixFrame.playerContainer, "TOPLEFT", x, y)
                    end

                    local pf = playerFrames[key]
                    pf.playerName = player.name

                    -- Set name with class color
                    local colorHex = getClassColor(player.class)
                    pf.nameText:SetText("|cff" .. colorHex .. player.name .. "|r")

                    -- Update assignment state
                    updatePlayerFrame(pf, player)
                    pf:Show()

                    y = y - PLAYER_HEIGHT
                end

                y = y - GROUP_SPACING
            end
        end
    end

    -- Update pill indicators
    updatePillIndicators()

    isUpdating = false
end

-------------------------------------------------------------------------------
-- Announce Teams
-------------------------------------------------------------------------------
function sepgp_matrix:AnnounceTeams()
    local redTeam = {}
    local blueTeam = {}

    for _, player in ipairs(raidRoster) do
        local assignment = playerAssignments[player.name]
        if assignment == "red" then
            table.insert(redTeam, {name = player.name, class = player.class})
        elseif assignment == "blue" then
            table.insert(blueTeam, {name = player.name, class = player.class})
        end
    end

    -- Sort alphabetically
    table.sort(redTeam, function(a, b) return a.name < b.name end)
    table.sort(blueTeam, function(a, b) return a.name < b.name end)

    -- Build message strings with class colors
    local redNames = {}
    for _, p in ipairs(redTeam) do
        local colorHex = getClassColor(p.class)
        table.insert(redNames, "|cff" .. colorHex .. p.name .. "|r")
    end

    local blueNames = {}
    for _, p in ipairs(blueTeam) do
        local colorHex = getClassColor(p.class)
        table.insert(blueNames, "|cff" .. colorHex .. p.name .. "|r")
    end

    -- Send messages
    local channel = "RAID"
    if IsRaidLeader() or IsRaidOfficer() then
        channel = "RAID_WARNING"
    end

    -- Helper function to send names in chunks of 9
    local NAMES_PER_MESSAGE = 9
    local function sendTeamMessages(names, teamLabel, teamColor)
        local totalNames = table.getn(names)
        if totalNames == 0 then return end

        local chunk = {}
        for i, name in ipairs(names) do
            table.insert(chunk, name)
            if table.getn(chunk) == NAMES_PER_MESSAGE or i == totalNames then
                local msg = teamColor .. teamLabel .. "|r: " .. table.concat(chunk, ", ")
                SendChatMessage(msg, channel)
                chunk = {}
            end
        end
    end

    -- Red team announcement
    sendTeamMessages(redNames, "RED TEAM (Left)", "|cffff3333")

    -- Empty line separator (send a simple divider)
    SendChatMessage("---", channel)

    -- Blue team announcement
    sendTeamMessages(blueNames, "BLUE TEAM (Right)", "|cff3366ff")

    -- Also print locally
    sepgp:defaultPrint("Matrix teams have been announced!")
end

-------------------------------------------------------------------------------
-- Reset Assignments
-------------------------------------------------------------------------------
function sepgp_matrix:ResetAssignments()
    -- Clear all assignments
    for name, _ in pairs(playerAssignments) do
        playerAssignments[name] = nil
    end

    -- Refresh the display
    refreshPlayerList()
end

-------------------------------------------------------------------------------
-- Toggle Window
-------------------------------------------------------------------------------
function sepgp_matrix:Toggle()
    local canUse, errorMsg = canUseMatrix()

    if not canUse then
        sepgp:defaultPrint(errorMsg)
        return
    end

    if not matrixFrame then
        createMatrixFrame()
    end

    if matrixFrame:IsVisible() then
        matrixFrame:Hide()
    else
        refreshPlayerList()
        matrixFrame:Show()
    end
end

-------------------------------------------------------------------------------
-- Event Handlers
-------------------------------------------------------------------------------
function sepgp_matrix:OnEnable()
    self:RegisterEvent("RAID_ROSTER_UPDATE", "OnRaidRosterUpdate")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED", "OnRaidRosterUpdate")
end

function sepgp_matrix:OnDisable()
    if matrixFrame then
        matrixFrame:Hide()
    end
end

function sepgp_matrix:OnRaidRosterUpdate()
    if matrixFrame and matrixFrame:IsVisible() then
        refreshPlayerList()
    end
end

-------------------------------------------------------------------------------
-- Slash Command Registration
-------------------------------------------------------------------------------
SLASH_MATRIX1 = "/matrix"
SlashCmdList["MATRIX"] = function(msg)
    sepgp_matrix:Toggle()
end
