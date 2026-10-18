-- shootyepgp :: what is left of the old windows
-- 18 Oct 2026 (guild leader: "remove the old windows etc that are not needed"):
-- the Tablet windows (standings, bids, loot, standby, alts, logs), the FuBar
-- minimap icon and the Dewdrop right-click menu were replaced by the new
-- window (ui\*.lua). This file keeps the names the core still calls -
-- sepgp_standings / _bids / _loot / _logs / _alts / _reserves - and what of
-- them is not just a window: standings export / import (copied unchanged
-- from standings.lua), the bid countdown, winner announcements and the
-- attention ping (from bids.lua). Every "open / refresh the old window"
-- now opens or redraws the matching page of the new window.
-- The old files are in _Backups\shootyepgp_before-cleanup_2026-10-18.

local C = AceLibrary("Crayon-2.0")
local L = AceLibrary("AceLocale-2.2"):new("shootyepgp")

-- the new window (ui\Window.lua loads after this file: looked up when called)
local function Redraw()
  local UI = SEPGP_UI
  if UI and UI.Refresh then
    UI.rosterDirty = true
    UI.Refresh()
  end
end
-- Toggle(true) = "show it": open the window on that page if it is closed
-- (an open window is only redrawn, so a new bid does not pull an officer off
-- the page they are on); Toggle() = open / close that page.
local function Toggler(page)
  return function(self, forceShow)
    local UI = SEPGP_UI
    if not UI or not UI.Open then return end
    if forceShow then
      if UI.frame and UI.frame:IsShown() then Redraw() else UI.Open(page) end
    else
      UI.Toggle(page)
    end
  end
end

sepgp_standings = { Toggle = Toggler("standings"), Refresh = Redraw }
sepgp_loot = { Toggle = Toggler("loot"), Refresh = Redraw }
sepgp_logs = { Toggle = Toggler("logs"), Refresh = Redraw }
sepgp_alts = { Toggle = Toggler("alts"), Refresh = Redraw }
sepgp_reserves = { Toggle = Toggler("reserves"), Refresh = Redraw }

-- ------------------------------------------------------------------ bids
-- (from bids.lua; the bid list itself is the new window's Bids page)
sepgp_bids = sepgp:NewModule("sepgp_bids", "AceEvent-2.0")
sepgp_bids.Toggle = Toggler("bids")
sepgp_bids.Refresh = Redraw

function sepgp_bids:announceWinnerMS(name, pr)
  sepgp:widestAudience(string.format(L["Winning Mainspec Bid: %s (%.03f PR)"],name,pr))
end

function sepgp_bids:announceWinnerOS(name, pr)
  sepgp:widestAudience(string.format(L["Winning Offspec Bid: %s (%.03f PR)"],name,pr))
end

function sepgp_bids:countdownCounter()
  self._counter = (self._counter or 6) - 1
  if GetNumRaidMembers()>0 and self._counter > 0 then
    self._counterText = C:Yellow(tostring(self._counter))
    sepgp:widestAudience(tostring(self._counter))
    self:Refresh()
  end
end

function sepgp_bids:countdownFinish(reset)
  if self:IsEventScheduled("shootyepgpBidCountdown") then
    self:CancelScheduledEvent("shootyepgpBidCountdown")
  end
  self._counter = 6
  if (reset) then
    self._counterText = C:Green("Starting")
  else
    self._counterText = C:Red("Finished")
  end
  self:Refresh()
end

function sepgp_bids:bidCountdown()
  self:countdownFinish(true)
  self:ScheduleRepeatingEvent("shootyepgpBidCountdown",self.countdownCounter,1,self)
  self:ScheduleEvent("shootyepgpBidCountdownFinish",self.countdownFinish,6,self)
end

-- Send attention signal to officers (ML only)
function sepgp_bids:sendAttention()
  if sepgp:lootMaster() then
    sepgp:broadcastBidAttention()
    sepgp:defaultPrint(L["Attention signal sent to officers."])
  end
end

-- ------------------------------------------------------------------ standings export / import
-- (unchanged from standings.lua)
local shooty_export = CreateFrame("Frame", "shooty_exportframe", UIParent)
shooty_export:SetWidth(250)
shooty_export:SetHeight(150)
shooty_export:SetPoint('TOP', UIParent, 'TOP', 0,-80)
shooty_export:SetFrameStrata('DIALOG')
shooty_export:Hide()
shooty_export:SetBackdrop({
  bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
  edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]],
  tile = true,
  tileSize = 16,
  edgeSize = 16,
  insets = {left = 5, right = 5, top = 5, bottom = 5}
  })
shooty_export:SetBackdropBorderColor(TOOLTIP_DEFAULT_COLOR.r, TOOLTIP_DEFAULT_COLOR.g, TOOLTIP_DEFAULT_COLOR.b)
shooty_export:SetBackdropColor(TOOLTIP_DEFAULT_BACKGROUND_COLOR.r, TOOLTIP_DEFAULT_BACKGROUND_COLOR.g, TOOLTIP_DEFAULT_BACKGROUND_COLOR.b)
shooty_export.action = CreateFrame("Button","shooty_exportaction", shooty_export, "UIPanelButtonTemplate")
shooty_export.action:SetWidth(100)
shooty_export.action:SetHeight(22)
shooty_export.action:SetPoint("BOTTOM",0,-20)
shooty_export.action:SetText("Import")
shooty_export.action:Hide()
shooty_export.action:SetScript("OnClick",function() sepgp_standings.import() end)
shooty_export.title = shooty_export:CreateFontString(nil,"OVERLAY")
shooty_export.title:SetPoint("TOP",0,-5)
shooty_export.title:SetFont("Fonts\\ARIALN.TTF", 12)
shooty_export.title:SetWidth(200)
shooty_export.title:SetJustifyH("LEFT")
shooty_export.title:SetJustifyV("CENTER")
shooty_export.title:SetShadowOffset(1, -1)
shooty_export.edit = CreateFrame("EditBox", "shooty_exportedit", shooty_export)
shooty_export.edit:SetMultiLine(true)
shooty_export.edit:SetAutoFocus(true)
shooty_export.edit:EnableMouse(true)
shooty_export.edit:SetMaxLetters(0)
shooty_export.edit:SetHistoryLines(1)
shooty_export.edit:SetFont('Fonts\\ARIALN.ttf', 12, 'THINOUTLINE')
shooty_export.edit:SetWidth(290)
shooty_export.edit:SetHeight(190)
shooty_export.edit:SetScript("OnEscapePressed", function() 
    shooty_export.edit:SetText("")
    shooty_export:Hide() 
  end)
shooty_export.edit:SetScript("OnEditFocusGained", function()
  shooty_export.edit:HighlightText()
end)
shooty_export.edit:SetScript("OnCursorChanged", function() 
  shooty_export.edit:HighlightText()
end)
shooty_export.AddSelectText = function(txt)
  shooty_export.edit:SetText(txt)
  shooty_export.edit:HighlightText()
end
shooty_export.scroll = CreateFrame("ScrollFrame", "shooty_exportscroll", shooty_export, 'UIPanelScrollFrameTemplate')
shooty_export.scroll:SetPoint('TOPLEFT', shooty_export, 'TOPLEFT', 8, -30)
shooty_export.scroll:SetPoint('BOTTOMRIGHT', shooty_export, 'BOTTOMRIGHT', -30, 8)
shooty_export.scroll:SetScrollChild(shooty_export.edit)
sepgp:make_escable("shooty_exportframe","add")

function sepgp_standings:Export()
  shooty_export.action:Hide()
  shooty_export.title:SetText(C:Gold(L["Ctrl-C to copy. Esc to close."]))
  local t = {}
  for i = 1, GetNumGuildMembers(1) do
    local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
    local ep = (sepgp:get_ep_v3(name,officernote) or 0) 
    local gp = (sepgp:get_gp_v3(name,officernote) or sepgp.VARS.basegp) 
    if ep > 0 then
      table.insert(t,{name,ep,gp,ep/gp})
    end
  end 
  table.sort(t, function(a,b)
      return tonumber(a[4]) > tonumber(b[4])
    end)
  shooty_export:Show()
  local txt = "Name;EP;GP;PR\n"
  for i,val in ipairs(t) do
    txt = string.format("%s%s;%d;%d;%.4f\n",txt,val[1],val[2],val[3],val[4])
  end
  shooty_export.AddSelectText(txt)
end

function sepgp_standings:Import()
  if not IsGuildLeader() then return end
  shooty_export.action:Show()
  shooty_export.title:SetText(C:Red("Ctrl-V to paste data. Esc to close."))
  shooty_export.AddSelectText(L.IMPORT_WARNING)
  shooty_export:Show()
end

function sepgp_standings.import()
  if not IsGuildLeader() then return end
  local text = shooty_export.edit:GetText()
  local t = {}
  local found
  for line in string.gfind(text,"[^\r\n]+") do
    local name,ep,gp,pr = sepgp:strsplit(";",line)
    ep,gp,pr = tonumber(ep),tonumber(gp),tonumber(pr)
    if (name) and (ep) and (gp) and (pr) then
      t[name]={ep,gp}
      found = true
    end
  end
  if (found) then
    local count = 0
    shooty_export.edit:SetText("")
    for i=1,GetNumGuildMembers(1) do
      local name, _, _, _, class, _, note, officernote, _, _ = GetGuildRosterInfo(i)
      local name_epgp = t[name]
      if (name_epgp) then
        count = count + 1
        sepgp:update_epgp_v3(name_epgp[1],name_epgp[2],i,name,officernote)
        t[name]=nil
      end
    end
    sepgp:defaultPrint(string.format(L["Imported %d members."],count))
    local report = string.format(L["Imported %d members.\n"],count)
    report = string.format(L["%s\nFailed to import:"],report)
    for name,epgp in pairs(t) do
      report = string.format("%s%s {%s:%s}\n",report,name,t[1],t[2])
    end
    shooty_export.AddSelectText(report)
  end
end
