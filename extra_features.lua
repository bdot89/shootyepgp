
-- PARSE ID
SLASH_PARSEID1 = "/parseid"

SlashCmdList["PARSEID"] = function(msg)

  local _, _, itemID = string.find(msg, "Hitem:(%d+)")
  
  if itemID then
    DEFAULT_CHAT_FRAME:AddMessage("Item ID is: " .. itemID)
  else
    DEFAULT_CHAT_FRAME:AddMessage(
      "No item ID found. Make sure to shift-click an actual item link.\nReceived: " .. (msg or "nil")
    )
  end
end




-- ROLL COLORS
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_SYSTEM")

-- Function to get guild rank
local function GetGuildRankForPlayer(name)
    if not IsInGuild() then return nil end
    
    GuildRoster() -- Update guild data
    local numMembers = GetNumGuildMembers(true)
    
    for i = 1, numMembers do
        local memberName, rank = GetGuildRosterInfo(i)
        -- Remove server name if present
        local shortName = memberName
        local dashPos = string.find(memberName or "", "-")
        if dashPos then
            shortName = string.sub(memberName, 1, dashPos - 1)
        end
        
        if shortName == name then
            return rank
        end
    end
    return nil
end

-- Store the original function
local originalChatFrame_OnEvent = ChatFrame_OnEvent

-- Function to get color based on roll value
local function GetRollColor(rollValue)
    local rollNum = tonumber(rollValue)
    if rollNum >= 90 then
        return "|cFF00FF00" -- Green
    elseif rollNum >= 70 then
        return "|cFFFFFF00" -- Yellow
    elseif rollNum >= 50 then
        return "|cFFFF8800" -- Orange
    else
        return "|cFFFF0000" -- Red
    end
end

-- Replace the event handler to filter out the original roll message
ChatFrame_OnEvent = function(event)
    if event == "CHAT_MSG_SYSTEM" then
        local message = arg1
        if message then
            local _, _, name, roll, range = string.find(message, "^([^%s]+) rolls (%d+) %(1%-(%d+)%)$")

            if name and roll then
                local rank = GetGuildRankForPlayer(name)
                local rollColor = GetRollColor(roll)

                -- Create the modified message with color based on roll value
                local modifiedMessage

                if rank and rank ~= "" then
                    -- Include rank for guild members
                    modifiedMessage = name .. " <" .. rank .. "> rolls " .. rollColor .. roll .. "|r (1-" .. range .. ")"
                else
                    -- No rank, but still color the number
                    modifiedMessage = name .. " rolls " .. rollColor .. roll .. "|r (1-" .. range .. ")"
                end
                
                -- Display the message with proper yellow system color
                DEFAULT_CHAT_FRAME:AddMessage(modifiedMessage, 1, 1, 0)
                
                -- Skip original message
                return
            end
        end
    end
    
    -- Call original handler for all other messages
    originalChatFrame_OnEvent(event)
end



-- Initialize loot sounds setting (default: enabled)
if sepgp_sound == nil then
    sepgp_sound = 1
end