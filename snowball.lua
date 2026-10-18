-- Idiot Addon
-- Announces snowball throws.

local SNOWBALL_PREFIX = "SHOOTYSNOW"
local SNOWBALL_SPELL_ID = 21343
local playerName = UnitName("player")
local playerGUID = nil

local snowballEnabled = false

-- Snowball deduplication
local lastSnowballKey = ""
local lastSnowballTime = 0
local DEDUP_WINDOW = 2

local function AnnounceSnowball(thrower, target)
    local key = thrower .. ">" .. target
    local now = GetTime()
    if key == lastSnowballKey and (now - lastSnowballTime) < DEDUP_WINDOW then
        return
    end
    lastSnowballKey = key
    lastSnowballTime = now
    SendChatMessage(thrower .. " YOU IDIOT! YOU THREW A SNOWBALL AT " .. target .. "!!!!", "YELL")
end

local function BroadcastSnowball(target)
    local message = "THROW:" .. target
    if IsInGuild() then
        SendAddonMessage(SNOWBALL_PREFIX, message, "GUILD")
    end
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(SNOWBALL_PREFIX, message, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(SNOWBALL_PREFIX, message, "PARTY")
    end
end

-- Event frame
local frame = CreateFrame("Frame")

-- Snowball events
frame:RegisterEvent("UNIT_CASTEVENT")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        playerName = UnitName("player")
        local _, guid = UnitExists("player")
        playerGUID = guid
        return
    end

    -- Snowball detection via SuperWoW
    if event == "UNIT_CASTEVENT" and snowballEnabled then
        if arg3 == "CAST" and arg4 == SNOWBALL_SPELL_ID then
            local casterName = UnitName(arg1)
            local targetName = UnitName(arg2)
            if casterName and targetName then
                AnnounceSnowball(casterName, targetName)
                if arg1 == playerGUID then
                    BroadcastSnowball(targetName)
                end
            end
        end
        return
    end

    -- Snowball addon broadcast from other users
    if event == "CHAT_MSG_ADDON" and snowballEnabled then
        if arg1 == SNOWBALL_PREFIX and arg4 ~= playerName then
            local _, _, target = string.find(arg2, "^THROW:(.+)$")
            if target then
                AnnounceSnowball(arg4, target)
            end
        end
        return
    end
end)

-- Slash commands
SLASH_SNOWBALL1 = "/snowball"
SlashCmdList["SNOWBALL"] = function()
    snowballEnabled = not snowballEnabled
    if snowballEnabled then
        DEFAULT_CHAT_FRAME:AddMessage("Snowball tracking |cFF00FF00Enabled|r")
    else
        DEFAULT_CHAT_FRAME:AddMessage("Snowball tracking |cFFFF0000Disabled|r")
    end
end

