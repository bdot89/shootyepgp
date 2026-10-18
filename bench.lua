BenchTracker = {}
local mainFrame = nil
local playerFrames = {}
local benchSessionActive = false
local lastSeenCheckNum = nil

-- Class colors
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

local LOCALIZED_CLASS_LOOKUP = {
    ["Warrior"] = "WARRIOR", ["Paladin"] = "PALADIN", ["Hunter"] = "HUNTER",
    ["Rogue"] = "ROGUE", ["Priest"] = "PRIEST", ["Shaman"] = "SHAMAN",
    ["Mage"] = "MAGE", ["Warlock"] = "WARLOCK", ["Druid"] = "DRUID",
    ["Krieger"] = "WARRIOR", ["Jager"] = "HUNTER",
    ["Schurke"] = "ROGUE", ["Priester"] = "PRIEST", ["Schamane"] = "SHAMAN",
    ["Magier"] = "MAGE", ["Hexenmeister"] = "WARLOCK", ["Druide"] = "DRUID",
    ["Guerrier"] = "WARRIOR", ["Chasseur"] = "HUNTER",
    ["Voleur"] = "ROGUE", ["Chaman"] = "SHAMAN",
}

function BenchTracker:GetEnglishClass(localizedClass)
    if not localizedClass then return nil end
    local upperClass = string.upper(localizedClass)
    if CLASS_COLORS[upperClass] then
        return upperClass
    end
    local englishClass = LOCALIZED_CLASS_LOOKUP[localizedClass]
    if englishClass then
        return englishClass
    end
    return upperClass
end

function BenchTracker:IsOfficer()
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

function BenchTracker:GetRaidMembers()
    local members = {}
    local raidSize = GetNumRaidMembers()
    if raidSize == 0 then return members end
    for i = 1, raidSize do
        local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
        if name then
            table.insert(members, {name = name, class = class, subgroup = subgroup})
        end
    end
    table.sort(members, function(a, b)
        return a.name < b.name
    end)
    return members
end

function BenchTracker:GetRaidURL()
    local url = "https://errorguild.com/raids"
    if WEBLINK_RAID_EVENT_ID and WEBLINK_RAID_EVENT_ID ~= "" then
        url = "https://errorguild.com/raids/" .. WEBLINK_RAID_EVENT_ID
    end
    return url
end

----------------------------------------------------------------
-- MAIN FRAME
----------------------------------------------------------------
function BenchTracker:CreateMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "BenchTrackerFrame", UIParent)
    mainFrame:SetWidth(220)
    mainFrame:SetHeight(340)
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
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:Hide()

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", mainFrame, "TOP", 0, -8)
    title:SetText("Bench Tracker")
    title:SetTextColor(0.9, 0.9, 0.9, 1)

    -- Close button
    local closeButton = CreateFrame("Button", nil, mainFrame)
    closeButton:SetWidth(12)
    closeButton:SetHeight(12)
    closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -6, -6)
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
    closeText:SetText("x")
    closeText:SetTextColor(1, 1, 1, 1)
    closeButton:SetScript("OnEnter", function()
        this:SetBackdropColor(1, 0.3, 0.3, 1)
    end)
    closeButton:SetScript("OnLeave", function()
        this:SetBackdropColor(0.8, 0.2, 0.2, 0.8)
    end)
    closeButton:SetScript("OnClick", function() mainFrame:Hide() end)

    -- Member count label
    local countLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 8, -24)
    countLabel:SetTextColor(0.6, 0.6, 0.6, 1)
    mainFrame.countLabel = countLabel

    -- Content area
    local content = CreateFrame("Frame", "BenchContent", mainFrame)
    content:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 6, -38)
    content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -6, 30)
    content:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil, tile = true, tileSize = 16,
        insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    content:SetBackdropColor(0.08, 0.08, 0.08, 0.5)
    mainFrame.content = content

    -- Scroll frame for member list
    local scrollFrame = CreateFrame("ScrollFrame", "BenchScrollFrame", content, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -2, 2)

    local scrollChild = CreateFrame("Frame", "BenchScrollChild", scrollFrame)
    scrollChild:SetWidth(185)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    mainFrame.scrollFrame = scrollFrame
    mainFrame.scrollChild = scrollChild

    BenchTracker:StyleScrollbar(scrollFrame)

    -- Bench Session button (bottom)
    local benchBtn = CreateFrame("Button", nil, mainFrame)
    benchBtn:SetWidth(200)
    benchBtn:SetHeight(18)
    benchBtn:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 6)
    benchBtn:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 4,
        insets = {left = 1, right = 1, top = 1, bottom = 1}
    })
    benchBtn:SetBackdropColor(0.4, 0.2, 0.6, 0.9)
    benchBtn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    local benchBtnText = benchBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    benchBtnText:SetPoint("CENTER", benchBtn, "CENTER", 0, 0)
    benchBtnText:SetText("Bench this Raid")
    benchBtnText:SetTextColor(1, 0.85, 0.5, 1)
    benchBtn:SetScript("OnEnter", function()
        this:SetBackdropColor(0.5, 0.3, 0.7, 1)
    end)
    benchBtn:SetScript("OnLeave", function()
        if benchSessionActive then
            this:SetBackdropColor(0.2, 0.5, 0.2, 0.9)
        else
            this:SetBackdropColor(0.4, 0.2, 0.6, 0.9)
        end
    end)
    benchBtn:SetScript("OnClick", function()
        if not BenchTracker:IsOfficer() then return end
        if benchSessionActive then
            BenchTracker:EndBenchSession()
            benchBtnText:SetText("Bench this Raid")
            benchBtnText:SetTextColor(1, 0.85, 0.5, 1)
            benchBtn:SetBackdropColor(0.4, 0.2, 0.6, 0.9)
        else
            BenchTracker:StartBenchSession()
            benchBtnText:SetText("End Bench Session")
            benchBtnText:SetTextColor(0.5, 1, 0.5, 1)
            benchBtn:SetBackdropColor(0.2, 0.5, 0.2, 0.9)
        end
    end)
    -- Start disabled until live check confirms a raid
    benchBtn:Disable()
    benchBtnText:SetText("Checking...")
    benchBtnText:SetTextColor(0.5, 0.5, 0.5, 1)
    benchBtn:SetBackdropColor(0.2, 0.2, 0.2, 0.9)

    mainFrame.benchButton = benchBtn
    mainFrame.benchButtonText = benchBtnText

    -- Update bench button state based on DLL globals (every 2s)
    local benchBtnUpdateFrame = CreateFrame("Frame")
    benchBtnUpdateFrame.elapsed = 0
    benchBtnUpdateFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed < 2 then return end
        this.elapsed = 0
        if not mainFrame or not mainFrame.benchButton then return end

        -- Sync session state from website via DLL (survives /reload)
        if WEBLINK_BENCH_SESSION and not benchSessionActive then
            benchSessionActive = true
            mainFrame.benchButtonText:SetText("End Bench Session")
            mainFrame.benchButtonText:SetTextColor(0.5, 1, 0.5, 1)
            mainFrame.benchButton:SetBackdropColor(0.2, 0.5, 0.2, 0.9)
            mainFrame.benchButton:Enable()
        elseif not WEBLINK_BENCH_SESSION and benchSessionActive then
            benchSessionActive = false
        end

        if not BenchTracker:IsOfficer() then
            mainFrame.benchButton:Hide()
            return
        end
        mainFrame.benchButton:Show()
        if benchSessionActive then return end
        if WEBLINK_RAID_LIVE then
            mainFrame.benchButton:Enable()
            mainFrame.benchButtonText:SetTextColor(1, 0.85, 0.5, 1)
            mainFrame.benchButton:SetBackdropColor(0.4, 0.2, 0.6, 0.9)
            local title = WEBLINK_RAID_TITLE or ""
            if title ~= "" then
                mainFrame.benchButtonText:SetText("Bench: " .. title)
            else
                mainFrame.benchButtonText:SetText("Bench this Raid")
            end
        else
            mainFrame.benchButton:Disable()
            mainFrame.benchButtonText:SetText("No Live Raid")
            mainFrame.benchButtonText:SetTextColor(0.5, 0.5, 0.5, 1)
            mainFrame.benchButton:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
        end
    end)
end

function BenchTracker:StyleScrollbar(scrollFrame)
    local scrollBar = getglobal(scrollFrame:GetName() .. "ScrollBar")
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 0, -16)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 16)
        scrollBar:SetWidth(5)
        scrollBar:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 2,
            insets = {left = 1, right = 1, top = 1, bottom = 1}
        })
        scrollBar:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        scrollBar:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
        local thumb = getglobal(scrollBar:GetName() .. "ThumbTexture")
        if thumb then
            thumb:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
            thumb:SetVertexColor(0.9, 0.9, 0.9, 0.9)
            thumb:SetWidth(8)
        end
        local upButton = getglobal(scrollBar:GetName() .. "ScrollUpButton")
        local downButton = getglobal(scrollBar:GetName() .. "ScrollDownButton")
        if upButton then upButton:SetWidth(0) end
        if downButton then downButton:SetWidth(0) end
    end
end

----------------------------------------------------------------
-- PLAYER ROW
----------------------------------------------------------------
function BenchTracker:CreatePlayerRow(parent, index)
    local frame = CreateFrame("Frame", "BenchPlayerRow" .. index, parent)
    frame:SetWidth(185)
    frame:SetHeight(16)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = nil, tile = true, tileSize = 16,
        insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    frame:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function()
        this:SetBackdropColor(0.25, 0.35, 0.45, 0.8)
    end)
    frame:SetScript("OnLeave", function()
        this:SetBackdropColor(0.15, 0.15, 0.15, 0.6)
    end)

    local nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", frame, "LEFT", 4, 0)
    nameText:SetWidth(175)
    nameText:SetJustifyH("LEFT")
    frame.nameText = nameText

    frame:Hide()
    return frame
end

----------------------------------------------------------------
-- MEMBER LIST DISPLAY
----------------------------------------------------------------
function BenchTracker:UpdateMemberDisplay()
    if not mainFrame or not mainFrame:IsVisible() then return end

    local members = BenchTracker:GetRaidMembers()
    local scrollChild = mainFrame.scrollChild

    -- Update count label
    if mainFrame.countLabel then
        mainFrame.countLabel:SetText("Bench: " .. table.getn(members) .. " players")
    end

    -- Hide all existing rows
    for i = 1, table.getn(playerFrames) do
        playerFrames[i]:Hide()
    end

    local yOffset = 0
    for i = 1, table.getn(members) do
        local member = members[i]

        if not playerFrames[i] then
            playerFrames[i] = BenchTracker:CreatePlayerRow(scrollChild, i)
        end

        local row = playerFrames[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        row:Show()

        row.nameText:SetText(member.name)
        local englishClass = BenchTracker:GetEnglishClass(member.class)
        local color = CLASS_COLORS[englishClass] or {r = 0.5, g = 0.5, b = 0.5}
        row.nameText:SetTextColor(color.r, color.g, color.b, 1)

        yOffset = yOffset - 17
    end

    local contentHeight = table.getn(members) * 17 + 10
    scrollChild:SetHeight(contentHeight)
    if mainFrame.scrollFrame then
        mainFrame.scrollFrame:UpdateScrollChildRect()
    end
end

----------------------------------------------------------------
-- BENCH SESSION (website sync via DLL)
----------------------------------------------------------------
function BenchTracker:SendBenchRoster()
    if not WebLink_PostBench then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000BenchTracker: WebLink DLL not loaded! Cannot sync bench.|r")
        return
    end
    local members = BenchTracker:GetRaidMembers()
    if table.getn(members) == 0 then return end

    local classMap = {
        ["Warrior"] = "Warrior", ["Hunter"] = "Hunter", ["Mage"] = "Mage",
        ["Priest"] = "Priest", ["Rogue"] = "Rogue", ["Shaman"] = "Shaman",
        ["Warlock"] = "Warlock", ["Druid"] = "Druid", ["Paladin"] = "Paladin",
    }

    local parts = {}
    for i = 1, table.getn(members) do
        local m = members[i]
        local cls = classMap[m.class] or m.class or "Unknown"
        table.insert(parts, '{"name":"' .. m.name .. '","class":"' .. cls .. '"}')
    end
    local officer = UnitName("player") or "Unknown"
    local json = '{"action":"sync_roster","officer":"' .. officer .. '","players":[' .. table.concat(parts, ",") .. ']}'

    WebLink_PostBench(json)
end

function BenchTracker:StartBenchSession()
    if not BenchTracker:IsOfficer() then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000BenchTracker: Only officers can start bench sessions.|r")
        return
    end
    if GetNumRaidMembers() == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000BenchTracker: You must be in a raid to start a bench session.|r")
        return
    end
    benchSessionActive = true
    lastSeenCheckNum = nil
    BenchTracker:SendBenchRoster()

    local url = BenchTracker:GetRaidURL()
    local msg = "BENCH SESSION STARTED. SIGN HERE: " .. url
    SendChatMessage(msg, "RAID_WARNING")

    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00BenchTracker: Bench session started! Roster synced to website.|r")
end

function BenchTracker:EndBenchSession()
    if not benchSessionActive then return end
    benchSessionActive = false
    lastSeenCheckNum = nil
    if WebLink_PostBench then
        WebLink_PostBench('{"action":"end_session"}')
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00BenchTracker: Bench session ended.|r")
end

----------------------------------------------------------------
-- BENCH CHECK DETECTION (polls WEBLINK_BENCH_CHECK_NUM every 5s)
----------------------------------------------------------------
function BenchTracker:OnBenchCheckDetected(checkNum)
    local url = BenchTracker:GetRaidURL()
    local msg = "AFK Check for the bench group! Please respond at " .. url
    SendChatMessage(msg, "RAID_WARNING")
    SendChatMessage(msg, "GUILD")
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFCC00BenchTracker: AFK Check #" .. checkNum .. " triggered from website. Messages sent.|r")
end

local pollFrame = CreateFrame("Frame", "BenchCheckPollFrame", UIParent)
pollFrame.elapsed = 0
pollFrame:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed < 5 then return end
    this.elapsed = 0

    local checkNum = WEBLINK_BENCH_CHECK_NUM

    if not benchSessionActive then return end
    if GetNumRaidMembers() == 0 then return end

    if checkNum and checkNum ~= lastSeenCheckNum then
        lastSeenCheckNum = checkNum
        BenchTracker:OnBenchCheckDetected(checkNum)
    elseif not checkNum then
        lastSeenCheckNum = nil
    end

    -- Refresh member list if frame is open
    if mainFrame and mainFrame:IsVisible() then
        BenchTracker:UpdateMemberDisplay()
    end
end)

----------------------------------------------------------------
-- SLASH COMMAND
----------------------------------------------------------------
SLASH_BENCH1 = "/bench"
SlashCmdList["BENCH"] = function(msg)
    if not mainFrame then
        BenchTracker:CreateMainFrame()
    end

    if mainFrame:IsVisible() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        if WebLink_RefreshBenchLive then
            WebLink_RefreshBenchLive()
        end
        BenchTracker:UpdateMemberDisplay()
    end
end

----------------------------------------------------------------
-- EVENT HANDLING
----------------------------------------------------------------
local benchEventFrame = CreateFrame("Frame", "BenchEventFrame", UIParent)
benchEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
benchEventFrame:RegisterEvent("ADDON_LOADED")

benchEventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "shootyepgp" then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00BenchTracker loaded! Type /bench to open.|r")

    elseif event == "RAID_ROSTER_UPDATE" then
        if mainFrame and mainFrame:IsVisible() then
            BenchTracker:UpdateMemberDisplay()
        end
        -- Auto-sync bench roster if session is active
        if benchSessionActive then
            if GetNumRaidMembers() == 0 then
                BenchTracker:EndBenchSession()
                if mainFrame and mainFrame.benchButtonText then
                    mainFrame.benchButtonText:SetText("Bench this Raid")
                    mainFrame.benchButtonText:SetTextColor(1, 0.85, 0.5, 1)
                    mainFrame.benchButton:SetBackdropColor(0.4, 0.2, 0.6, 0.9)
                end
            else
                BenchTracker:SendBenchRoster()
            end
        end
    end
end)
