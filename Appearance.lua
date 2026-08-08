local _, SL = ...

-- Appearance panel. Same shape as the Sources window: a free-floating,
-- movable, escape-closable frame with a title bar and a scrolling body.
--
-- Everything here writes into db.settings.appearance and then calls
-- SL:ApplyTheme(), which rewrites SL.THEME in place and re-paints every
-- registered widget. Nothing needs a /reload.

local T = SL.THEME
local COLORS = {
  primary    = T.bgDeep,
  primaryAlt = T.bgPanel,
  row        = T.bgRow,
  frame      = T.chrome,
  active     = T.active,
  activeAlt  = T.activeAlt,
  indicator  = T.gold,
  text       = T.text,
  textAlt    = T.textAlt,
  dim        = T.dim,
  subtle     = T.subtle,
  dimmer     = T.dimmer,
}

local BODY_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Regular.ttf"
local BODY_BOLD_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Bold.ttf"

local PANEL_W, PANEL_H = 560, 620
local CONTENT_W = PANEL_W - 40

local function SetColor(target, color, alpha)
  target(color[1], color[2], color[3], alpha or 1)
  SL.RegisterTint(target, color, alpha)
end

local function Backdrop(frame, alpha, background, border)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  SetColor(function(...) frame:SetBackdropColor(...) end, background or COLORS.primaryAlt, alpha or 1)
  SetColor(function(...) frame:SetBackdropBorderColor(...) end, border or COLORS.active)
end

local function Text(parent, align, size, bold, color)
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetJustifyH(align or "LEFT")
  t:SetFont(bold and BODY_BOLD_FONT or BODY_FONT, size or 12)
  SetColor(function(...) t:SetTextColor(...) end, color or COLORS.textAlt)
  return t
end

local function Button(parent, label, width, callback)
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(width, 22)
  Backdrop(b, 1, COLORS.active)
  b.label = Text(b, "CENTER", 12, true, COLORS.text)
  b.label:SetPoint("CENTER"); b.label:SetText(label)
  b:SetScript("OnClick", callback)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
  SetColor(function(...) hl:SetColorTexture(...) end, COLORS.activeAlt, 0.16)
  return b
end

-- Section header with a hairline under it, so the panel reads as grouped
-- settings rather than one long list.
local function Section(parent, label, hint)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(hint and 34 or 22)
  local title = Text(frame, "LEFT", 11, true, COLORS.indicator)
  title:SetPoint("TOPLEFT", 0, 0); title:SetText(label:upper())
  if hint then
    local sub = Text(frame, "LEFT", 10, false, COLORS.subtle)
    sub:SetPoint("TOPLEFT", 0, -14); sub:SetPoint("TOPRIGHT", 0, -14)
    sub:SetHeight(12); sub:SetWordWrap(false); sub:SetText(hint)
  end
  local rule = frame:CreateTexture(nil, "ARTWORK")
  rule:SetPoint("BOTTOMLEFT", 0, 0); rule:SetPoint("BOTTOMRIGHT", 0, 0); rule:SetHeight(1)
  rule:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) rule:SetVertexColor(...) end, COLORS.active, 0.7)
  return frame
end

local function Checkbox(parent, label, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(20)
  local box = CreateFrame("Frame", nil, b, BackdropTemplateMixin and "BackdropTemplate" or nil)
  box:SetSize(14, 14); box:SetPoint("LEFT", 0, 0)
  Backdrop(box, 1, COLORS.primaryAlt, COLORS.active)
  box.fill = box:CreateTexture(nil, "ARTWORK")
  box.fill:SetPoint("TOPLEFT", 2, -2); box.fill:SetPoint("BOTTOMRIGHT", -2, 2)
  SetColor(function(...) box.fill:SetColorTexture(...) end, COLORS.indicator)
  local text = Text(b, "LEFT", 12, false, COLORS.text)
  text:SetPoint("LEFT", box, "RIGHT", 8, 0); text:SetPoint("RIGHT", 0, 0)
  text:SetHeight(14); text:SetWordWrap(false); text:SetText(label)
  b.Update = function() box.fill:SetShown(get() and true or false) end
  b:SetScript("OnClick", function() set(not get()); b.Update() end)
  b.Update()
  return b
end

-- Slider with a live value readout on the right. Fires `set` continuously so
-- the change is visible while dragging, which is the whole point of a slider
-- in a look-and-feel panel.
local function Slider(parent, label, minimum, maximum, step, get, set, format)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(38)
  local caption = Text(frame, "LEFT", 12, false, COLORS.text)
  caption:SetPoint("TOPLEFT", 0, 0); caption:SetHeight(14); caption:SetWordWrap(false)
  caption:SetText(label)
  local readout = Text(frame, "RIGHT", 12, true, COLORS.indicator)
  readout:SetPoint("TOPRIGHT", 0, 0); readout:SetWidth(70); readout:SetHeight(14); readout:SetWordWrap(false)

  local slider = CreateFrame("Slider", nil, frame)
  slider:SetOrientation("HORIZONTAL")
  slider:SetPoint("BOTTOMLEFT", 0, 4); slider:SetPoint("BOTTOMRIGHT", 0, 4); slider:SetHeight(12)
  slider:SetMinMaxValues(minimum, maximum); slider:SetValueStep(step); slider:SetObeyStepOnDrag(true)

  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT", 0, 0); track:SetPoint("RIGHT", 0, 0); track:SetHeight(3)
  track:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) track:SetVertexColor(...) end, COLORS.active)

  local thumb = slider:CreateTexture(nil, "ARTWORK")
  thumb:SetSize(10, 12); thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) thumb:SetVertexColor(...) end, COLORS.indicator)
  slider:SetThumbTexture(thumb)

  frame.Update = function()
    slider.suppress = true
    slider:SetValue(get())
    slider.suppress = false
    readout:SetText(format and format(get()) or tostring(get()))
  end
  slider:SetScript("OnValueChanged", function(_, value)
    if slider.suppress then return end
    set(value)
    readout:SetText(format and format(value) or tostring(value))
  end)
  frame.Update()
  return frame
end

-- Colour chip used for both the theme presets and the accent swatches. A
-- selected chip gets a bright inner border so the current choice is obvious at
-- a glance.
local function Swatch(parent, color, label, isSelected, onClick, width)
  local b = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetSize(width or 84, 44)
  Backdrop(b, 1, COLORS.primaryAlt, COLORS.active)
  local chip = b:CreateTexture(nil, "ARTWORK")
  chip:SetPoint("TOPLEFT", 5, -5); chip:SetPoint("TOPRIGHT", -5, -5); chip:SetHeight(18)
  chip:SetTexture("Interface\\Buttons\\WHITE8X8")
  chip:SetVertexColor(color[1], color[2], color[3], 1)
  local text = Text(b, "CENTER", 10, false, COLORS.dim)
  text:SetPoint("BOTTOMLEFT", 3, 5); text:SetPoint("BOTTOMRIGHT", -3, 5)
  text:SetHeight(12); text:SetWordWrap(false); text:SetText(label)
  local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
  SetColor(function(...) hl:SetColorTexture(...) end, COLORS.activeAlt, 0.10)
  b.chip, b.text = chip, text
  b.SetSelected = function(selected)
    if selected then
      SetColor(function(...) b:SetBackdropBorderColor(...) end, COLORS.indicator)
      SetColor(function(...) text:SetTextColor(...) end, COLORS.text)
    else
      SetColor(function(...) b:SetBackdropBorderColor(...) end, COLORS.active)
      SetColor(function(...) text:SetTextColor(...) end, COLORS.dim)
    end
  end
  b.SetSelected(isSelected)
  b:SetScript("OnClick", onClick)
  return b
end

local function OpenColorPicker(current, onChange)
  local picker = _G.ColorPickerFrame
  if not picker then return end
  local r, g, b = current[1], current[2], current[3]
  local function apply()
    local nr, ng, nb = picker:GetColorRGB()
    onChange({ nr, ng, nb })
  end
  picker.func, picker.swatchFunc = apply, apply
  picker.opacityFunc, picker.cancelFunc = nil, function() onChange({ r, g, b }) end
  picker.hasOpacity = false
  picker.previousValues = { r, g, b }
  if picker.SetColorRGB then picker:SetColorRGB(r, g, b) end
  picker:Hide()
  picker:Show()
end

function SL:CreateAppearancePanel()
  if self.appearanceFrame then return self.appearanceFrame end
  local frame = CreateFrame("Frame", "GoblinAppearanceFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(PANEL_W, PANEL_H)
  Backdrop(frame, 1, COLORS.primary, COLORS.frame)
  frame:Hide()
  frame:SetFrameStrata("HIGH"); frame:SetToplevel(true); frame:SetClampedToScreen(true)
  frame:SetMovable(true); frame:EnableMouse(true)
  self.appearanceFrame = frame

  self.db.window.appearance = self.db.window.appearance or { point = "CENTER", relPoint = "CENTER", x = -60, y = 0 }
  local saved = self.db.window.appearance
  frame:ClearAllPoints()
  frame:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or "CENTER", saved.x or -60, saved.y or 0)

  if UISpecialFrames then
    local already = false
    for _, name in ipairs(UISpecialFrames) do if name == "GoblinAppearanceFrame" then already = true; break end end
    if not already then table.insert(UISpecialFrames, "GoblinAppearanceFrame") end
  end

  local titleBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  titleBar:SetPoint("TOPLEFT", 1, -1); titleBar:SetPoint("TOPRIGHT", -1, -1); titleBar:SetHeight(36)
  Backdrop(titleBar, 1, COLORS.frame, COLORS.frame)
  titleBar:EnableMouse(true); titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
  titleBar:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, relPoint, x, y = frame:GetPoint()
    self.db.window.appearance = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  local brand = Text(titleBar, "LEFT", 15, true, COLORS.text)
  brand:SetPoint("LEFT", 12, 0); brand:SetText("Goblin")
  local section = Text(titleBar, "LEFT", 15, true, COLORS.indicator)
  section:SetPoint("LEFT", brand, "RIGHT", 8, 0); section:SetText("Appearance")
  local close = Button(titleBar, "×", 26, function() frame:Hide() end)
  close:SetPoint("RIGHT", -6, 0)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -42); scroll:SetPoint("BOTTOMRIGHT", -28, 38)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_W, 1)
  scroll:SetScrollChild(content)
  frame.content = content

  local footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(34)
  Backdrop(footer, 1, COLORS.frame, COLORS.frame)
  local hint = Text(footer, "LEFT", 11, false, COLORS.subtle)
  hint:SetPoint("LEFT", 12, 0); hint:SetWidth(320); hint:SetWordWrap(false)
  hint:SetText("Changes apply immediately — no reload needed.")
  local reset = Button(footer, "Reset to defaults", 130, function() self:ResetAppearance() end)
  reset:SetPoint("RIGHT", -10, 0)

  self:BuildAppearanceBody()
  return frame
end

function SL:ResetAppearance()
  local appearance = self:GetAppearance()
  local minimap = appearance.minimap or {}
  appearance.theme = "goblin"
  appearance.accent = "gold"
  appearance.accentCustom = nil
  appearance.opacity = 1
  appearance.scale = 1
  appearance.stripes = true
  minimap.style = "coin"
  minimap.size = 30
  minimap.radius = 5
  minimap.locked = false
  minimap.shown = true
  minimap.letter = true
  appearance.minimap = minimap
  self:ApplyTheme()
  self:BuildAppearanceBody()
end

-- Rebuilt in full whenever a selection changes, so highlight state never
-- drifts from the saved settings. Tint collection stays off for the duration:
-- these widgets are thrown away and remade, so registering their setters would
-- grow the registry every time you click a swatch.
function SL:BuildAppearanceBody()
  local frame = self.appearanceFrame
  if not frame then return end
  SL.WithoutTintCollection(function() self:BuildAppearanceBodyImpl() end)
end

function SL:BuildAppearanceBodyImpl()
  local frame = self.appearanceFrame
  local content = frame.content
  for _, widget in ipairs(self.appearanceWidgets or {}) do widget:Hide(); widget:SetParent(nil) end
  self.appearanceWidgets = {}
  local widgets = self.appearanceWidgets
  local appearance = self:GetAppearance()
  local minimap = appearance.minimap

  local y = -6
  local function place(widget, height, indent)
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", indent or 4, y)
    widget:SetPoint("TOPRIGHT", -4, y)
    if height then widget:SetHeight(height) end
    widgets[#widgets + 1] = widget
    y = y - (height or widget:GetHeight()) - 6
  end

  -- ---------------------------------------------------------------- theme
  place(Section(content, "Theme", "Window chrome and background"), 34)
  local themeRow = CreateFrame("Frame", nil, content)
  themeRow:SetHeight(44)
  local presetW = math.floor((CONTENT_W - 16 - (#self.THEME_PRESETS - 1) * 6) / #self.THEME_PRESETS)
  for index, preset in ipairs(self.THEME_PRESETS) do
    local key = preset.key
    local swatch = Swatch(themeRow, preset.swatch, preset.label, appearance.theme == key, function()
      appearance.theme = key
      self:ApplyTheme()
      self:BuildAppearanceBody()
    end, presetW)
    swatch:ClearAllPoints()
    swatch:SetPoint("LEFT", (index - 1) * (presetW + 6), 0)
  end
  place(themeRow, 44)

  -- --------------------------------------------------------------- accent
  place(Section(content, "Accent", "Highlights, totals, checkboxes and the active tab"), 34)
  local accentRow = CreateFrame("Frame", nil, content)
  local perRow = 5
  local accentW = math.floor((CONTENT_W - 16 - (perRow - 1) * 6) / perRow)
  local entries = {}
  for _, accent in ipairs(self.ACCENTS) do entries[#entries + 1] = accent end
  entries[#entries + 1] = { key = "custom", label = "Custom…", color = appearance.accentCustom or self:GetAccentColor() }
  local accentRows = math.ceil(#entries / perRow)
  accentRow:SetHeight(accentRows * 50)
  for index, accent in ipairs(entries) do
    local col = (index - 1) % perRow
    local row = math.floor((index - 1) / perRow)
    local key = accent.key
    local swatch = Swatch(accentRow, accent.color, accent.label, appearance.accent == key, function()
      if key == "custom" then
        OpenColorPicker(self:GetAccentColor(), function(color)
          appearance.accent = "custom"
          appearance.accentCustom = color
          self:ApplyTheme()
          self:BuildAppearanceBody()
        end)
      else
        appearance.accent = key
        self:ApplyTheme()
        self:BuildAppearanceBody()
      end
    end, accentW)
    swatch:ClearAllPoints()
    swatch:SetPoint("TOPLEFT", col * (accentW + 6), -row * 50)
  end
  place(accentRow, accentRows * 50)

  -- --------------------------------------------------------------- window
  place(Section(content, "Window"), 22)
  place(Slider(content, "Opacity", 0.3, 1, 0.05,
    function() return appearance.opacity or 1 end,
    function(value) appearance.opacity = value; self:ApplyWindowSettings() end,
    function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end), 38, 10)
  place(Slider(content, "Scale", 0.7, 1.4, 0.05,
    function() return appearance.scale or 1 end,
    function(value) appearance.scale = value; self:ApplyWindowSettings() end,
    function(value) return string.format("%d%%", math.floor(value * 100 + 0.5)) end), 38, 10)
  place(Checkbox(content, "Alternating row colours in the item list",
    function() return appearance.stripes ~= false end,
    function(value) appearance.stripes = value; self:RefreshUI() end), 20, 10)

  -- -------------------------------------------------------------- minimap
  place(Section(content, "Minimap icon"), 22)
  place(Checkbox(content, "Show the minimap button",
    function() return minimap.shown ~= false end,
    function(value) minimap.shown = value; self:RefreshMinimapButton(); self:BuildAppearanceBody() end), 20, 10)

  if minimap.shown ~= false then
    local styleRow = CreateFrame("Frame", nil, content)
    local stylePerRow = 3
    local styleW = math.floor((CONTENT_W - 24 - (stylePerRow - 1) * 6) / stylePerRow)
    local styleRows = math.ceil(#self.MINIMAP_STYLES / stylePerRow)
    styleRow:SetHeight(styleRows * 62)
    for index, style in ipairs(self.MINIMAP_STYLES) do
      local col = (index - 1) % stylePerRow
      local row = math.floor((index - 1) / stylePerRow)
      local key = style.key
      local cell = CreateFrame("Button", nil, styleRow, BackdropTemplateMixin and "BackdropTemplate" or nil)
      cell:SetSize(styleW, 56)
      cell:SetPoint("TOPLEFT", col * (styleW + 6), -row * 62)
      local selected = (minimap.style or "coin") == key
      Backdrop(cell, 1, COLORS.primaryAlt, selected and COLORS.indicator or COLORS.active)
      local hl = cell:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
      SetColor(function(...) hl:SetColorTexture(...) end, COLORS.activeAlt, 0.10)

      -- Rendered by the exact same paint routine as the live button.
      local preview = self:CreateMinimapPreview(cell, 30)
      preview:SetPoint("LEFT", 12, 0)
      self:PaintMinimapStyle(preview, key, 30, minimap.letter ~= false)

      local label = Text(cell, "LEFT", 11, true, selected and COLORS.text or COLORS.dim)
      label:SetPoint("TOPLEFT", 50, -12); label:SetPoint("TOPRIGHT", -6, -12)
      label:SetHeight(13); label:SetWordWrap(false); label:SetText(style.label)
      local note = Text(cell, "LEFT", 10, false, COLORS.subtle)
      note:SetPoint("TOPLEFT", 50, -27); note:SetPoint("TOPRIGHT", -6, -27)
      note:SetHeight(12); note:SetWordWrap(false); note:SetText(style.note)

      cell:SetScript("OnClick", function()
        minimap.style = key
        self:RefreshMinimapButton()
        self:BuildAppearanceBody()
      end)
    end
    place(styleRow, styleRows * 62, 10)

    -- The three drawn styles are built around the letter, so the overlay
    -- toggle only means anything on the artwork ones.
    local style = minimap.style or "coin"
    if not (style == "coin" or style == "minimal" or style == "badge") then
      place(Checkbox(content, "Overlay the green G on the artwork",
        function() return minimap.letter ~= false end,
        function(value) minimap.letter = value; self:RefreshMinimapButton(); self:BuildAppearanceBody() end), 20, 10)
    end

    place(Slider(content, "Icon size", 18, 44, 1,
      function() return minimap.size or 30 end,
      function(value) minimap.size = value; self:RefreshMinimapButton() end,
      function(value) return string.format("%dpx", math.floor(value)) end), 38, 10)
    place(Slider(content, "Distance from minimap", -6, 24, 1,
      function() return minimap.radius or 5 end,
      function(value) minimap.radius = value; self:RefreshMinimapButton() end,
      function(value) return string.format("%d", math.floor(value)) end), 38, 10)
    place(Checkbox(content, "Lock position (disable dragging)",
      function() return minimap.locked and true or false end,
      function(value) minimap.locked = value; self:RefreshMinimapButton() end), 20, 10)
  end

  content:SetHeight(math.max(1, -y + 10))
end

function SL:ToggleAppearance()
  if not self.appearanceFrame then self:CreateAppearancePanel() end
  local frame = self.appearanceFrame
  if not frame then return end
  frame:SetShown(not frame:IsShown())
  if frame:IsShown() then self:BuildAppearanceBody() end
end
