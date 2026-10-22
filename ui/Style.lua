-- shootyepgp :: new window, part 1 - the look
-- Flat style taken from OctoBG (user's choice, 18 Oct 2026): dark panels with
-- 1 px borders, slim toggle switches, square tick boxes, thin sliders, one
-- accent colour, Roboto when it loads. Everything here only draws; the data
-- and the EPGP actions stay in the addon's own files.
--
-- Lua 5.0 / 1.12 client: no #, no %, no string methods, "this" and arg1 in
-- scripts, no EditBox:HasFocus.

SEPGP_UI = SEPGP_UI or {}
local UI = SEPGP_UI

UI.VERSION = "1.2.0"
local MEDIA = "Interface\\AddOns\\shootyepgp\\media\\"
UI.WHITE = "Interface\\ChatFrame\\ChatFrameBackground"
UI.DISC = MEDIA .. "disc"
UI.TRI = MEDIA .. "tri"

-- the flat palette (same values as OctoBG's Widgets.lua)
local C = {
  bg = { 0.067, 0.071, 0.078 },
  panel = { 0.094, 0.098, 0.11 },
  card = { 0.125, 0.13, 0.145 },
  head = { 0.165, 0.17, 0.19 },
  field = { 0.07, 0.073, 0.08 },
  btn = { 0.18, 0.19, 0.21 },
  line = { 0.23, 0.24, 0.27 },
  lineHi = { 0.36, 0.38, 0.43 },
  text = { 0.92, 0.92, 0.93 },
  dim = { 0.6, 0.61, 0.65 },
  accent = { 0.2, 0.7, 1 },
  gold = { 1, 0.78, 0.25 },
  on = { 0.22, 0.72, 0.42 },
  off = { 0.3, 0.31, 0.35 },
  red = { 1, 0.35, 0.3 },
}
UI.C = C

-- ------------------------------------------------------------------ fonts

UI.FONT = "Fonts\\FRIZQT__.TTF"
local ROBOTO = MEDIA .. "fonts\\Roboto.ttf"
local fontChecked
-- A failed SetFont keeps the old font, so compare what GetFont says.
function UI.UIFont()
  if not fontChecked then
    fontChecked = true
    local f = CreateFrame("Frame", nil, UIParent)
    local probe = f:CreateFontString(nil, "OVERLAY")
    probe:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    local base = probe:GetFont()
    probe:SetFont(ROBOTO, 12, "")
    local now = probe:GetFont()
    local function N(s) return string.lower(string.gsub(s or "", "/", "\\")) end
    if type(base) ~= "string" or (type(now) == "string" and N(now) == N(ROBOTO)) then
      UI.FONT = ROBOTO
    end
  end
  return UI.FONT
end

function UI.Font(fs, size, col)
  fs:SetFont(UI.UIFont(), size or 12, "")
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetShadowOffset(1, -1)
  col = col or C.text
  fs:SetTextColor(col[1], col[2], col[3])
  return fs
end

function UI.Text(parent, size, col, layer)
  return UI.Font(parent:CreateFontString(nil, layer or "OVERLAY"), size, col)
end

-- ------------------------------------------------------------------ colours

function UI.Hex(col)
  return string.format("%02x%02x%02x", col[1] * 255, col[2] * 255, col[3] * 255)
end
function UI.Paint(col, text)
  return "|cff" .. UI.Hex(col) .. tostring(text) .. "|r"
end

-- Class colour from a localized class name (the guild roster gives those).
local classToken = {}
function UI.ClassHex(class)
  if not class then return "cccccc" end
  local token = classToken[class]
  if not token then
    token = string.upper(class)
    local ok, BC = pcall(AceLibrary, "Babble-Class-2.2")
    if ok and BC and BC:HasReverseTranslation(class) then
      token = string.upper(BC:GetReverseTranslation(class))
    end
    classToken[class] = token
  end
  local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if not c then return "cccccc" end
  return string.format("%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end
function UI.ClassName(name, class)
  return "|cff" .. UI.ClassHex(class) .. tostring(name) .. "|r"
end

-- ------------------------------------------------------------------ flat parts

function UI.Flat(f, col, alpha, line)
  f:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, tile = false, tileSize = 0, edgeSize = 1,
                  insets = { left = 1, right = 1, top = 1, bottom = 1 } })
  col = col or C.panel
  line = line or C.line
  f:SetBackdropColor(col[1], col[2], col[3], alpha or 1)
  f:SetBackdropBorderColor(line[1], line[2], line[3], 1)
end

function UI.Fill(parent, col, alpha, layer)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(UI.WHITE)
  t:SetVertexColor(col[1], col[2], col[3], alpha or 1)
  return t
end

local function Hover(b, alpha)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(UI.WHITE)
  hl:SetVertexColor(1, 1, 1, alpha or 0.07)
  hl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
  hl:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
  return hl
end
UI.Hover = Hover

-- Hover help: a title and what it does, in white.
function UI.Tip(frame, title, text)
  frame.tipTitle, frame.tipText = title, text
  frame:SetScript("OnEnter", function()
    if not this.tipTitle and not this.tipText then return end
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    if this.tipTitle then GameTooltip:AddLine(this.tipTitle) end
    if this.tipText then GameTooltip:AddLine(this.tipText, 1, 1, 1, 1) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A flat button. b:SetText works.
function UI.Button(parent, text, width, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(width or 120)
  b:SetHeight(height or 22)
  UI.Flat(b, C.btn, 1, C.line)
  local fs = UI.Text(b, 11)
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetFontString(fs)
  b.label = fs
  b:SetText(text)
  Hover(b)
  b:SetScript("OnMouseDown", function() this:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) end)
  b:SetScript("OnMouseUp", function()
    if not this.picked then this:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1) end
  end)
  return b
end

-- A button painted as the picked one (tabs, sort headers).
function UI.Pick(b, on)
  b.picked = on
  local l = on and C.accent or C.line
  b:SetBackdropBorderColor(l[1], l[2], l[3], 1)
  if on then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
  local f = on and C.head or C.btn
  b:SetBackdropColor(f[1], f[2], f[3], 1)
end

-- A greyed-out button still shows its tooltip (why it is off).
function UI.Enable(b, on)
  b.disabledLook = not on
  if on then
    b:Enable()
    b.label:SetTextColor(C.text[1], C.text[2], C.text[3])
  else
    b:Disable()
    b.label:SetTextColor(C.off[1] + 0.15, C.off[2] + 0.15, C.off[3] + 0.15)
  end
end

-- A slim toggle switch. b.Set(on) paints it; b.onToggle(newState) is called on click.
function UI.Switch(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetWidth(32)
  b:SetHeight(16)
  local function Disc(size, layer)
    local t = b:CreateTexture(nil, layer or "ARTWORK")
    t:SetTexture(UI.DISC)
    t:SetWidth(size)
    t:SetHeight(size)
    return t
  end
  local l, r = Disc(18), Disc(18)
  l:SetPoint("LEFT", b, "LEFT", -1, 0)
  r:SetPoint("RIGHT", b, "RIGHT", 1, 0)
  local m = b:CreateTexture(nil, "ARTWORK")
  m:SetTexture(UI.WHITE)
  m:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -1)
  m:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 1)
  local knob = Disc(14, "OVERLAY")
  knob:SetVertexColor(0.95, 0.95, 0.96, 1)
  function b.Set(on)
    local col = on and C.on or C.off
    if b.locked then col = C.line end
    l:SetVertexColor(col[1], col[2], col[3], 1)
    r:SetVertexColor(col[1], col[2], col[3], 1)
    m:SetVertexColor(col[1], col[2], col[3], 1)
    knob:ClearAllPoints()
    if on then knob:SetPoint("RIGHT", b, "RIGHT", -1, 0) else knob:SetPoint("LEFT", b, "LEFT", 1, 0) end
    b.on = on
  end
  b:SetScript("OnClick", function()
    if this.locked then return end
    if this.onToggle then this.onToggle(not this.on) end
  end)
  b.Set(false)
  return b
end

-- A flat text box; focus is tracked by hand (1.12 has no HasFocus).
function UI.EditBox(parent, width)
  local eb = CreateFrame("EditBox", nil, parent)
  eb:SetWidth(width)
  eb:SetHeight(20)
  UI.Flat(eb, C.field, 1, C.line)
  eb:SetTextInsets(6, 6, 0, 0)
  eb:SetFont(UI.UIFont(), 12, "")
  eb:SetTextColor(C.text[1], C.text[2], C.text[3])
  eb:SetAutoFocus(false)
  eb:EnableMouse(true)
  eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function()
    this:ClearFocus()
    if this.onEnter then this.onEnter(this:GetText()) end
  end)
  eb:SetScript("OnEditFocusGained", function()
    this.typing = true
    this:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
  end)
  eb:SetScript("OnEditFocusLost", function()
    this.typing = nil
    this:SetBackdropBorderColor(C.line[1], C.line[2], C.line[3], 1)
  end)
  eb:SetScript("OnTextChanged", function()
    if this.hint then
      if this:GetText() == "" then this.hint:Show() else this.hint:Hide() end
    end
    if this.onChange then this.onChange(this:GetText()) end
  end)
  return eb
end

-- A grey hint inside an empty edit box ("Search names...").
function UI.Hint(eb, text)
  local h = UI.Text(eb, 11, C.dim)
  h:SetPoint("LEFT", eb, "LEFT", 7, 0)
  h:SetText(text)
  eb.hint = h
end

-- A thin slider; s.onValue(v) while dragging.
local sliderCount = 0
function UI.Slider(parent, width)
  sliderCount = sliderCount + 1
  local s = CreateFrame("Slider", "SepgpUISlider" .. sliderCount, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetWidth(width)
  s:SetHeight(16)
  s:EnableMouse(true)
  s:SetThumbTexture(UI.DISC)
  local th = s:GetThumbTexture()
  if th then
    th:SetWidth(14)
    th:SetHeight(14)
    th:SetVertexColor(0.95, 0.95, 0.96, 1)
  end
  local track = UI.Fill(s, C.off, 1, "BACKGROUND")
  track:SetHeight(4)
  track:SetPoint("LEFT", s, "LEFT", 3, 0)
  track:SetPoint("RIGHT", s, "RIGHT", -3, 0)
  s.fill = UI.Fill(s, C.accent, 1, "BORDER")
  s.fill:SetHeight(4)
  s.fill:SetPoint("LEFT", s, "LEFT", 3, 0)
  s.fill:SetWidth(1)
  s.width = width
  s:SetScript("OnValueChanged", function()
    UI.SliderPaint(this)
    if this.onValue and not this.quiet then this.onValue(this:GetValue()) end
  end)
  return s
end
function UI.SliderPaint(s)
  local lo, hi = s:GetMinMaxValues()
  local f = 0
  if hi and lo and hi > lo then f = (s:GetValue() - lo) / (hi - lo) end
  s.fill:SetWidth(math.max(1, f * (s.width - 14) + 4))
end
-- Set a slider's value without running onValue.
function UI.SliderSet(s, v)
  s.quiet = true
  s:SetValue(v)
  s.quiet = nil
  UI.SliderPaint(s)
end

-- ------------------------------------------------------------------ dropdown

UI.menus = {}
function UI.CloseMenus()
  for i = 1, table.getn(UI.menus) do UI.menus[i]:Hide() end
end

-- options = { { key = , label = }, ... }; get() returns the picked key.
function UI.Dropdown(parent, width, options, get, set)
  local d = CreateFrame("Button", nil, parent)
  d:SetWidth(width)
  d:SetHeight(20)
  UI.Flat(d, C.field, 1, C.line)
  Hover(d)
  local t = UI.Text(d, 11)
  t:SetPoint("LEFT", d, "LEFT", 7, 0)
  t:SetPoint("RIGHT", d, "RIGHT", -18, 0)
  t:SetJustifyH("LEFT")
  local arrow = d:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture(UI.TRI)
  arrow:SetWidth(9)
  arrow:SetHeight(9)
  arrow:SetPoint("RIGHT", d, "RIGHT", -6, 0)
  arrow:SetVertexColor(C.dim[1], C.dim[2], C.dim[3], 1)
  arrow:SetTexCoord(0, 1, 1, 0) -- flipped: pointing down
  local menu = CreateFrame("Frame", nil, UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu:SetClampedToScreen(true)
  menu:SetWidth(width)
  UI.Flat(menu, C.card, 0.98, C.lineHi)
  menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
  menu:Hide()
  table.insert(UI.menus, menu)
  local n = table.getn(options)
  for i = 1, n do
    local e = CreateFrame("Button", nil, menu)
    e:SetWidth(width - 8)
    e:SetHeight(17)
    e:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 17)
    local et = UI.Text(e, 11)
    et:SetPoint("LEFT", e, "LEFT", 6, 0)
    et:SetText(options[i].label)
    local hl = e:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(e)
    hl:SetTexture(UI.WHITE)
    hl:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.25)
    e.key = options[i].key
    e:SetScript("OnClick", function()
      menu:Hide()
      set(this.key)
      d.Refresh()
    end)
  end
  menu:SetHeight(n * 17 + 8)
  d:SetScript("OnClick", function()
    if d.locked then return end
    local open = menu:IsShown()
    UI.CloseMenus()
    if not open then menu:Show() end
  end)
  function d.Refresh()
    local k = get()
    local label = tostring(k or "")
    for i = 1, n do
      if options[i].key == k then label = options[i].label end
    end
    t:SetText(label)
  end
  d:SetScript("OnHide", function() menu:Hide() end)
  d.Refresh()
  return d
end

-- ------------------------------------------------------------------ confirm

-- One "are you sure" box for everything that changes guild data, clears a
-- list or talks in chat (guild leader, 18 Oct 2026: in the middle of the
-- screen, saying what is about to happen). The screen behind is dimmed and
-- cannot be clicked until Yes or Cancel; Escape cancels.
--   UI.Confirm("what will happen", function() ... end [, "Title", "Yes label"])
local function BuildConfirm()
  local shade = CreateFrame("Frame", nil, UIParent)
  shade:SetAllPoints(UIParent)
  shade:SetFrameStrata("FULLSCREEN_DIALOG")
  shade:EnableMouse(true)
  local dark = UI.Fill(shade, { 0, 0, 0 }, 0.45)
  dark:SetAllPoints(shade)
  shade:Hide()
  local d = CreateFrame("Frame", "SepgpUIConfirm", UIParent)
  d:SetWidth(440)
  d:SetHeight(196)
  d:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d:SetFrameLevel(shade:GetFrameLevel() + 5)
  d:SetToplevel(true)
  d:EnableMouse(true)
  UI.Flat(d, C.bg, 0.98, C.accent)
  local bar = UI.Fill(d, C.head, 1, "BORDER")
  bar:SetPoint("TOPLEFT", d, "TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", d, "TOPRIGHT", -1, -1)
  bar:SetHeight(34)
  d.title = UI.Text(d, 15, C.gold)
  d.title:SetPoint("TOP", d, "TOP", 0, -10)
  d.text = UI.Text(d, 12)
  d.text:SetPoint("TOP", d, "TOP", 0, -50)
  d.text:SetWidth(400)
  d.text:SetJustifyH("CENTER")
  d.yes = UI.Button(d, "Yes", 160, 26)
  d.yes:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
  d.yes:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
  d.no = UI.Button(d, "Cancel", 160, 26)
  d.no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 16)
  d.yes:SetScript("OnClick", function()
    local fn = d.fn
    d.fn = nil
    d:Hide()
    if fn then fn() end
  end)
  d.no:SetScript("OnClick", function() d:Hide() end)
  d:SetScript("OnHide", function()
    d.fn = nil
    shade:Hide()
  end)
  d:Hide()
  table.insert(UISpecialFrames, "SepgpUIConfirm")   -- Escape = Cancel
  d.shade = shade
  UI.confirmFrame = d
  return d
end

function UI.Confirm(text, fn, title, yesLabel)
  local d = UI.confirmFrame or BuildConfirm()
  UI.CloseMenus()
  d.fn = fn
  d.title:SetText(title or "Are you sure?")
  d.text:SetText(text)
  -- long texts (the decay log's undo) make the box taller
  local h = d.text:GetHeight()
  d:SetHeight(math.max(196, (type(h) == "number" and h or 0) + 50 + 66))
  d.yes:SetText(yesLabel or "Yes, do it")
  d.shade:Show()
  d:Show()
end

-- (tests and keyboard users) press Yes on the open box
function UI.ConfirmYes()
  local d = UI.confirmFrame
  if d and d:IsShown() then
    this = d.yes
    d.yes:GetScript("OnClick")()
  end
end

-- A small square tick box: blue inside when ticked.
function UI.CheckBox(parent, size)
  local cb = CreateFrame("CheckButton", nil, parent)
  cb:SetWidth(size or 14)
  cb:SetHeight(size or 14)
  UI.Flat(cb, C.field, 1, C.lineHi)
  cb:SetCheckedTexture(UI.WHITE)
  local t = cb:GetCheckedTexture()
  if t then
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", cb, "TOPLEFT", 3, -3)
    t:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -3, 3)
    t:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
  end
  Hover(cb, 0.12)
  return cb
end

-- ------------------------------------------------------------------ list

-- A scrolling table with clickable column headers.
-- cols = { { key = "name", label = "Name", width = 150, align = "LEFT", sort = true }, ... }
-- list:SetRows(rows) where each row = { cells = { "text", ... }, sort = { name = "x", ep = 1 }, data = ... }
-- list.onClick(row, button), list.onEnter(row, frame)
function UI.List(parent, cols, rowH, nRows)
  local L = CreateFrame("Frame", nil, parent)
  L.cols, L.rowH, L.nRows, L.offset = cols, rowH or 18, nRows, 0
  L.rows, L.view = {}, {}
  UI.Flat(L, C.field, 1, C.line)
  -- header
  local head = CreateFrame("Frame", nil, L)
  head:SetPoint("TOPLEFT", L, "TOPLEFT", 1, -1)
  head:SetPoint("TOPRIGHT", L, "TOPRIGHT", -1, -1)
  head:SetHeight(20)
  local hbg = UI.Fill(head, C.head, 1)
  hbg:SetAllPoints(head)
  L.heads = {}
  local x = 6
  for i = 1, table.getn(cols) do
    local c = cols[i]
    local h = CreateFrame("Button", nil, head)
    h:SetPoint("TOPLEFT", head, "TOPLEFT", x, 0)
    h:SetWidth(c.width)
    h:SetHeight(20)
    local ht = UI.Text(h, 11, C.gold)
    ht:SetAllPoints(h)
    ht:SetJustifyH(c.align or "LEFT")
    ht:SetText(c.label)
    h.text, h.col = ht, c
    if c.sort then
      Hover(h, 0.05)
      h:SetScript("OnClick", function()
        if L.sortKey == this.col.key then
          L.sortDesc = not L.sortDesc
        else
          L.sortKey, L.sortDesc = this.col.key, (this.col.sort ~= "asc")
        end
        L:Sort()
        L:Draw()
        if L.onSort then L.onSort(L.sortKey, L.sortDesc) end
      end)
    end
    L.heads[i] = h
    x = x + c.width + 6
  end
  -- body rows
  L.lines = {}
  for r = 1, nRows do
    local line = CreateFrame("Button", nil, L)
    line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -(r - 1) * L.rowH)
    line:SetPoint("RIGHT", L, "RIGHT", -10, 0)
    line:SetHeight(L.rowH)
    line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if math.mod(r, 2) == 0 then
      local stripe = UI.Fill(line, C.panel, 0.6)
      stripe:SetAllPoints(line)
    end
    line.sel = UI.Fill(line, C.accent, 0.18, "BORDER")
    line.sel:SetAllPoints(line)
    line.sel:Hide()
    Hover(line, 0.06)
    line.cells = {}
    line.checks = {}
    local cx = 6
    for i = 1, table.getn(cols) do
      if cols[i].check then
        -- a tick box column: row.ticked, L.onCheck(row); shown while L.checksOn
        local cb = UI.CheckBox(line, 14)
        cb:SetPoint("LEFT", line, "LEFT", cx, 0)
        cb:SetScript("OnClick", function()
          local row = this:GetParent().row
          if row then
            row.ticked = this:GetChecked() and true or false
            if L.onCheck then L.onCheck(row) end
          end
        end)
        line.checks[i] = cb
      end
      local fs = UI.Text(line, 11)
      fs:SetPoint("LEFT", line, "LEFT", cx, 0)
      fs:SetWidth(cols[i].width)
      fs:SetHeight(L.rowH)
      fs:SetJustifyH(cols[i].align or "LEFT")
      line.cells[i] = fs
      cx = cx + cols[i].width + 6
    end
    line:SetScript("OnClick", function()
      if this.row and L.onClick then L.onClick(this.row, arg1) end
    end)
    line:SetScript("OnEnter", function()
      if this.row and L.onEnter then L.onEnter(this.row, this) end
    end)
    line:SetScript("OnLeave", function() GameTooltip:Hide() end)
    L.lines[r] = line
  end
  -- empty text
  L.empty = UI.Text(L, 12, C.dim)
  L.empty:SetPoint("TOP", head, "BOTTOM", 0, -30)
  L.empty:SetWidth(360)
  -- slim scroll bar
  local sb = CreateFrame("Slider", nil, L)
  sb:SetOrientation("VERTICAL")
  sb:SetPoint("TOPRIGHT", L, "TOPRIGHT", -2, -22)
  sb:SetPoint("BOTTOMRIGHT", L, "BOTTOMRIGHT", -2, 2)
  sb:SetWidth(6)
  local track = UI.Fill(sb, C.panel, 1)
  track:SetAllPoints(sb)
  sb:SetThumbTexture(UI.WHITE)
  local th = sb:GetThumbTexture()
  if th then
    th:SetWidth(6)
    th:SetHeight(30)
    th:SetVertexColor(C.lineHi[1], C.lineHi[2], C.lineHi[3], 1)
  end
  sb:SetMinMaxValues(0, 0)
  sb:SetValueStep(1)
  sb:SetValue(0)
  sb:SetScript("OnValueChanged", function()
    local v = math.floor(this:GetValue() + 0.5)
    if v ~= L.offset then
      L.offset = v
      L:Draw()
    end
  end)
  L.bar = sb
  L:EnableMouseWheel(true)
  L:SetScript("OnMouseWheel", function()
    local n = (IsShiftKeyDown() and 10 or 3)
    L:Scroll(-arg1 * n)
  end)

  function L:Scroll(by)
    local maxOff = math.max(0, table.getn(self.view) - self.nRows)
    local v = math.max(0, math.min(maxOff, self.offset + by))
    self.bar:SetValue(v)
    if v ~= self.offset then
      self.offset = v
      self:Draw()
    end
  end

  function L:Sort()
    local k, desc = self.sortKey, self.sortDesc
    if not k then return end
    table.sort(self.view, function(a, b)
      local va, vb = a.sort and a.sort[k], b.sort and b.sort[k]
      if va == vb then
        local ta, tb = a.sort and a.sort.tie, b.sort and b.sort.tie
        if ta and tb and ta ~= tb then return ta < tb end
        return false
      end
      if va == nil then return false end
      if vb == nil then return true end
      if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
      if desc then return va > vb end
      return va < vb
    end)
  end

  -- rows: all rows; filter(row) -> keep
  function L:SetRows(rows, keepScroll)
    self.rows = rows or {}
    self:Filter(keepScroll)
  end
  function L:Filter(keepScroll)
    local shown = {}
    for i = 1, table.getn(self.rows) do
      local r = self.rows[i]
      if not self.filter or self.filter(r) then table.insert(shown, r) end
    end
    self.view = shown
    self:Sort()
    local maxOff = math.max(0, table.getn(shown) - self.nRows)
    if not keepScroll then self.offset = 0 end
    self.offset = math.min(self.offset, maxOff)
    self.bar:SetMinMaxValues(0, maxOff)
    self.bar:SetValue(self.offset)
    if maxOff > 0 then self.bar:Show() else self.bar:Hide() end
    self:Draw()
  end
  function L:Draw()
    for r = 1, self.nRows do
      local line = self.lines[r]
      local row = self.view[self.offset + r]
      line.row = row
      if row then
        for i = 1, table.getn(self.cols) do
          line.cells[i]:SetText(tostring(row.cells[i] or ""))
          local cb = line.checks[i]
          if cb then
            if self.checksOn then
              cb:SetChecked(row.ticked and 1 or nil)
              cb:Show()
            else
              cb:Hide()
            end
          end
        end
        if self.selected and row.id and row.id == self.selected then line.sel:Show() else line.sel:Hide() end
        line:Show()
      else
        line:Hide()
      end
    end
    for i = 1, table.getn(self.heads) do
      local h = self.heads[i]
      local label = h.col.label
      if h.col.key == self.sortKey and h.col.sort then
        label = label .. (self.sortDesc and " v" or " ^")
      end
      h.text:SetText(label)
    end
    if table.getn(self.view) == 0 then
      self.empty:SetText(self.emptyText or "Nothing here yet.")
      self.empty:Show()
    else
      self.empty:Hide()
    end
  end
  return L
end

-- ------------------------------------------------------------------ boxes

-- A titled card on a page: c.body is where content goes.
function UI.Card(parent, title, width, height)
  local c = CreateFrame("Frame", nil, parent)
  c:SetWidth(width)
  c:SetHeight(height)
  UI.Flat(c, C.card, 1, C.line)
  if title then
    local bar = UI.Fill(c, C.head, 1, "BORDER")
    bar:SetPoint("TOPLEFT", c, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", c, "TOPRIGHT", -1, -1)
    bar:SetHeight(22)
    local t = UI.Text(c, 12, C.text)
    t:SetPoint("TOPLEFT", c, "TOPLEFT", 9, -6)
    t:SetText(title)
    c.title = t
  end
  return c
end

-- A small figure tile: big value, small caption.
function UI.Tile(parent, caption, width)
  local t = CreateFrame("Frame", nil, parent)
  t:SetWidth(width or 120)
  t:SetHeight(46)
  UI.Flat(t, C.card, 1, C.line)
  t.value = UI.Text(t, 17, C.text)
  t.value:SetPoint("TOPLEFT", t, "TOPLEFT", 9, -7)
  t.caption = UI.Text(t, 10, C.dim)
  t.caption:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 9, 6)
  t.caption:SetText(caption)
  return t
end

-- A label + control row inside a card. Returns the label.
function UI.Label(parent, text, x, y, width)
  local l = UI.Text(parent, 12)
  l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if width then l:SetWidth(width) l:SetJustifyH("LEFT") end
  l:SetText(text)
  return l
end
