-- shootyepgp :: new window, part 4 - minimap button
-- Left-click: the shootyepgp window. Right-click: straight to Standings.
-- Drag: move the button around the minimap. (shootyepgp's old FuBar icon
-- and its right-click menu were removed on 18 Oct 2026: everything they did
-- is in the window.)

local UI = SEPGP_UI
local MB = {}
UI.Minimap = MB

local RADIUS = 78

function MB.Place()
  local a = math.rad(UI.DB().minimapPos or 200)
  MB.button:ClearAllPoints()
  MB.button:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 54 - RADIUS * math.cos(a), RADIUS * math.sin(a) - 55)
end

function MB.Drag()
  local x, y = GetCursorPosition()
  local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
  if not left or not bottom then return end
  local s = Minimap:GetEffectiveScale()
  x = left - x / s + 70
  y = y / s - bottom - 70
  local deg = math.deg(math.atan2(y, x))
  if deg < 0 then deg = deg + 360 end
  UI.DB().minimapPos = deg
  MB.Place()
end

function MB.Update()
  if not MB.button then return end
  if UI.DB().minimapHide then MB.button:Hide() else MB.button:Show() end
end

function MB.Later() end   -- (kept for Window.lua's PLAYER_ENTERING_WORLD call)

function MB.Tooltip(b)
  GameTooltip:SetOwner(b, "ANCHOR_LEFT")
  GameTooltip:AddLine("shootyepgp")
  local me
  if UI.Ready() then
    local ok, m = pcall(UI.Me)
    if ok then me = m end
  end
  if me and me.hasEPGP then
    GameTooltip:AddDoubleLine("EP / GP", me.ep .. " / " .. me.gp, 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("PR", string.format("%.3f", me.pr), 0.8, 0.8, 0.8, 1, 0.78, 0.25)
    if me.pos then GameTooltip:AddDoubleLine("Place", "#" .. me.pos, 0.8, 0.8, 0.8, 1, 1, 1) end
  end
  if UI.IsAdmin() then
    local nb = sepgp and ((sepgp.bids_main and table.getn(sepgp.bids_main) or 0) + (sepgp.bids_off and table.getn(sepgp.bids_off) or 0)) or 0
    if nb > 0 then GameTooltip:AddLine(nb .. " bids open", 0.2, 0.7, 1) end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click: open the window", 0.6, 0.61, 0.65)
  GameTooltip:AddLine("Right-click: standings", 0.6, 0.61, 0.65)
  GameTooltip:AddLine("Drag: move this button", 0.6, 0.61, 0.65)
  GameTooltip:Show()
end

function MB.Build()
  if MB.button then return end
  local b = CreateFrame("Button", "SepgpUIMinimapButton", Minimap)
  b:SetWidth(33)
  b:SetHeight(33)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton", "RightButton")
  local icon = b:CreateTexture(nil, "BORDER")
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", b, "CENTER", -2, 1)
  icon:SetTexture("Interface\\PetitionFrame\\GuildCharter-Icon")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(52)
  border:SetHeight(52)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  local hl = b:CreateTexture()
  hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  hl:SetBlendMode("ADD")
  b:SetHighlightTexture(hl)
  b:SetScript("OnClick", function()
    GameTooltip:Hide()
    if arg1 == "RightButton" then UI.Toggle("standings") else UI.Toggle() end
  end)
  b:SetScript("OnDragStart", function()
    GameTooltip:Hide()
    this:SetScript("OnUpdate", function() MB.Drag() end)
  end)
  b:SetScript("OnDragStop", function() this:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function() MB.Tooltip(this) end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  MB.button = b
  MB.Place()
  MB.Update()
end
