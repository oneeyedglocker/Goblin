local _, SL = ...

-- TSM's Stormwind theme. Goblin intentionally mirrors the parent addon's
-- visual language while remaining independent of LibTSMUI's private API.
local COLORS = {
  primary = { 0x14 / 255, 0x16 / 255, 0x16 / 255 },
  primaryAlt = { 0x24 / 255, 0x29 / 255, 0x29 / 255 },
  frame = { 0x42 / 255, 0x4c / 255, 0x4f / 255 },
  active = { 0x6b / 255, 0x76 / 255, 0x73 / 255 },
  activeAlt = { 0xd9 / 255, 0xdc / 255, 0xd3 / 255 },
  indicator = { 0xff / 255, 0xd8 / 255, 0x39 / 255 },
  text = { 1, 1, 1 },
  textAlt = { 0xe2 / 255, 0xe2 / 255, 0xe2 / 255 },
}
local BODY_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Regular.ttf"
local BODY_BOLD_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Bold.ttf"
local TABLE_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Roboto-Medium.ttf"
local ROW_HEIGHT, MAX_VISIBLE_ROWS = 20, 40
local COLUMNS = {
  { key = "name", label = "Item", width = 230, align = "LEFT" },
  { key = "total", label = "Total", width = 55 },
  { key = "bags", label = "Bags", width = 55 },
  { key = "bank", label = "Bank", width = 55 },
  { key = "equipped", label = "Equipped", width = 70 },
  { key = "mail", label = "Mail", width = 55 },
  { key = "auctions", label = "AH", width = 55 },
  { key = "guild", label = "Guild", width = 55 },
  { key = "value", label = "Value", width = 130, align = "RIGHT" },
}

local function SetColor(target, color, alpha)
  target(color[1], color[2], color[3], alpha or 1)
end

local function Backdrop(frame, alpha, background, border)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  SetColor(function(...) frame:SetBackdropColor(...) end, background or COLORS.primaryAlt, alpha or 1)
  SetColor(function(...) frame:SetBackdropBorderColor(...) end, border or COLORS.active)
end

local function Text(parent, align, size, bold, tableFont)
  local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetJustifyH(align or "RIGHT")
  text:SetFont(tableFont and TABLE_FONT or (bold and BODY_BOLD_FONT or BODY_FONT), size or 12)
  SetColor(function(...) text:SetTextColor(...) end, COLORS.textAlt)
  return text
end

local function Button(parent, label, width, callback)
  local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  button:SetSize(width, 22)
  Backdrop(button, 1, COLORS.active)
  button.label = Text(button, "CENTER", 12, true)
  button.label:SetPoint("CENTER")
  button.label:SetText(label)
  button:SetScript("OnClick", callback)
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(); SetColor(function(...) highlight:SetColorTexture(...) end, COLORS.activeAlt, 0.16)
  return button
end

local function Input(parent, width, height)
  local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  edit:SetSize(width, height or 22)
  edit:SetAutoFocus(false)
  edit:SetTextInsets(6, 6, 0, 0)
  return edit
end

function SL:SetSort(key)
  if self.db.settings.sort == key then self.db.settings.descending = not self.db.settings.descending
  else self.db.settings.sort, self.db.settings.descending = key, key ~= "name" end
  self:RefreshUI()
end

local function CreateCheckbox(parent, label, get, set)
  local check = CreateFrame("CheckButton", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  check:SetSize(16, 16); Backdrop(check, 1, COLORS.primaryAlt, COLORS.active)
  check.mark = check:CreateTexture(nil, "ARTWORK"); check.mark:SetPoint("TOPLEFT", 3, -3); check.mark:SetPoint("BOTTOMRIGHT", -3, 3)
  SetColor(function(...) check.mark:SetColorTexture(...) end, COLORS.indicator)
  check:SetCheckedTexture(check.mark)
  check.highlight = check:CreateTexture(nil, "HIGHLIGHT"); check.highlight:SetAllPoints()
  SetColor(function(...) check.highlight:SetColorTexture(...) end, COLORS.activeAlt, 0.15)
  check.text = Text(check, "LEFT", 12); check.text:SetPoint("LEFT", check, "RIGHT", 7, 0); check.text:SetText(label)
  check:SetScript("OnShow", function(self) self:SetChecked(get()) end)
  check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); SL:RefreshUI() end)
  return check
end

function SL:CreateOptions()
  local frame = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, -70)
  frame:SetSize(360, 552); frame:SetFrameLevel(self.frame:GetFrameLevel() + 20); Backdrop(frame, 1, COLORS.primaryAlt); frame:Hide()
  self.options = frame
  local titleBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  titleBar:SetPoint("TOPLEFT", 1, -1); titleBar:SetPoint("TOPRIGHT", -1, -1); titleBar:SetHeight(32); Backdrop(titleBar, 1, COLORS.frame, COLORS.frame)
  local title = Text(titleBar, "LEFT", 14, true); title:SetPoint("LEFT", 10, 0); title:SetText("Included in net worth")
  local close = Button(frame, "Close", 52, function() frame:Hide() end); close:SetPoint("TOPRIGHT", -10, -6)
  local y = -46
  local gold = CreateCheckbox(frame, "Character gold", function() return self.db.settings.includeGold end, function(v) self.db.settings.includeGold = v end)
  gold:SetPoint("TOPLEFT", 10, y); y = y - 27
  local guildGold = CreateCheckbox(frame, "Guild bank gold", function() return self.db.settings.includeGuildGold end, function(v) self.db.settings.includeGuildGold = v end)
  guildGold:SetPoint("TOPLEFT", 10, y); y = y - 34
  local soulbound = CreateCheckbox(frame, "Soulbound items", function() return self.db.settings.includeSoulbound end, function(v) self.db.settings.includeSoulbound = v end)
  soulbound:SetPoint("TOPLEFT", 10, y); y = y - 34
  for _, category in ipairs(self.CATEGORIES) do
    local key = category
    local check = CreateCheckbox(frame, self.CATEGORY_LABELS[key], function() return self.db.settings.categories[key] end, function(v) self.db.settings.categories[key] = v end)
    check:SetPoint("TOPLEFT", 10, y); y = y - 27
  end
  self.optionsDynamicTop = y - 8
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, self.optionsDynamicTop)
  scroll:SetPoint("BOTTOMRIGHT", -28, 10)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(316, 1)
  scroll:SetScrollChild(content)
  self.optionsScroll = scroll
  self.optionsContent = content
  return frame
end

function SL:RefreshOptions()
  if not self.options or not self.options:IsShown() then return end
  for _, widget in ipairs(self.optionDynamic or {}) do widget:Hide(); widget:SetParent(nil) end
  self.optionDynamic = {}
  local content = self.optionsContent
  local y = -2
  local header = Text(content, "LEFT", 12, true); header:SetPoint("TOPLEFT", 8, y); header:SetText("Characters"); SetColor(function(...) header:SetTextColor(...) end, COLORS.indicator)
  self.optionDynamic[#self.optionDynamic + 1] = header; y = y - 24
  local characterKeys = {}
  for key in pairs(self.db.characters) do characterKeys[#characterKeys + 1] = key end
  table.sort(characterKeys)
  for _, key in ipairs(characterKeys) do
    local characterKey = key
    local character = self.db.characters[key]
    local check = CreateCheckbox(content, key, function() return self:IsCharacterIncluded(characterKey) end, function(v) self.db.settings.characters[characterKey] = v end)
    check:SetPoint("TOPLEFT", 6, y); check:SetChecked(self:IsCharacterIncluded(key)); y = y - 21
    self.optionDynamic[#self.optionDynamic + 1] = check
    local guildText = Text(content, "LEFT", 11)
    guildText:SetPoint("TOPLEFT", 30, y)
    guildText:SetText(character.guildName and ("Guild: " .. character.guildName) or "Guild: none recorded")
    guildText:SetTextColor(0.58, 0.63, 0.61)
    self.optionDynamic[#self.optionDynamic + 1] = guildText; y = y - 20
    local goldCheck = CreateCheckbox(content, "Gold", function() return self:IsCharacterGoldIncluded(characterKey) end, function(v) self.db.settings.characterGold[characterKey] = v end)
    goldCheck:SetPoint("TOPLEFT", 30, y); goldCheck:SetChecked(self:IsCharacterGoldIncluded(key)); y = y - 23
    self.optionDynamic[#self.optionDynamic + 1] = goldCheck
    for _, category in ipairs(self.CATEGORIES) do
      if category ~= "guild" then
        local location = category
        local sourceCheck = CreateCheckbox(content, self.CATEGORY_LABELS[location], function() return self:IsCharacterCategoryIncluded(characterKey, location) end, function(v)
          self.db.settings.characterCategories[characterKey] = self.db.settings.characterCategories[characterKey] or {}
          self.db.settings.characterCategories[characterKey][location] = v
        end)
        sourceCheck:SetPoint("TOPLEFT", 30, y); sourceCheck:SetChecked(self:IsCharacterCategoryIncluded(key, location)); y = y - 23
        self.optionDynamic[#self.optionDynamic + 1] = sourceCheck
      end
    end
    y = y - 8
  end
  if next(self.db.guilds) then
    local guildHeader = Text(content, "LEFT", 12, true); guildHeader:SetPoint("TOPLEFT", 8, y - 4); guildHeader:SetText("Guild banks"); SetColor(function(...) guildHeader:SetTextColor(...) end, COLORS.indicator)
    self.optionDynamic[#self.optionDynamic + 1] = guildHeader; y = y - 28
    local guildKeys = {}
    for key in pairs(self.db.guilds) do guildKeys[#guildKeys + 1] = key end
    table.sort(guildKeys)
    for _, key in ipairs(guildKeys) do
      local guildKey = key
      local guild = self.db.guilds[key]
      local check = CreateCheckbox(content, key, function() return self:IsGuildIncluded(guildKey) end, function(v) self.db.settings.guilds[guildKey] = v end)
      check:SetPoint("TOPLEFT", 6, y); check:SetChecked(self:IsGuildIncluded(key)); y = y - 21
      self.optionDynamic[#self.optionDynamic + 1] = check
      local memberNames = {}
      for _, character in pairs(self.db.characters) do
        if character.guildKey == guildKey then memberNames[#memberNames + 1] = character.name or "?" end
      end
      table.sort(memberNames)
      local members = Text(content, "LEFT", 11); members:SetPoint("TOPLEFT", 30, y)
      members:SetText(#memberNames > 0 and ("Characters: " .. table.concat(memberNames, ", ")) or "Characters: none recorded")
      members:SetTextColor(0.58, 0.63, 0.61)
      self.optionDynamic[#self.optionDynamic + 1] = members; y = y - 20
      local goldCheck = CreateCheckbox(content, "Guild gold", function() return self:IsGuildGoldIncluded(guildKey) end, function(v) self.db.settings.guildGold[guildKey] = v end)
      goldCheck:SetPoint("TOPLEFT", 30, y); goldCheck:SetChecked(self:IsGuildGoldIncluded(key)); y = y - 23
      self.optionDynamic[#self.optionDynamic + 1] = goldCheck
      local tabs = {}
      for tab in pairs(guild.tabs or {}) do tabs[#tabs + 1] = tab end
      table.sort(tabs)
      for _, tab in ipairs(tabs) do
        local tabIndex = tab
        local tabLabel = (guild.tabNames and guild.tabNames[tab]) or ("Tab " .. tab)
        local tabCheck = CreateCheckbox(content, tabIndex .. ": " .. tabLabel, function() return self:IsGuildTabIncluded(guildKey, tabIndex) end, function(v)
          self.db.settings.guildTabs[guildKey] = self.db.settings.guildTabs[guildKey] or {}
          self.db.settings.guildTabs[guildKey][tabIndex] = v
        end)
        tabCheck:SetPoint("TOPLEFT", 30, y); tabCheck:SetChecked(self:IsGuildTabIncluded(key, tab)); y = y - 23
        self.optionDynamic[#self.optionDynamic + 1] = tabCheck
      end
      y = y - 8
    end
  end
  content:SetHeight(math.max(1, -y + 8))
end

function SL:InitializeUI()
  local frame = CreateFrame("Frame", "GoblinFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(math.min(1200, math.max(790, self.db.window.width or 790)), math.min(900, math.max(450, self.db.window.height or 650))); frame:SetPoint("CENTER"); frame:SetMovable(true); frame:SetResizable(true); frame:EnableMouse(true); frame:EnableMouseWheel(true); frame:SetClampedToScreen(true)
  frame:SetResizeBounds(790, 450, 1200, 900)
  frame:RegisterForDrag("LeftButton"); frame:SetScript("OnDragStart", frame.StartMoving); frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  Backdrop(frame, 1, COLORS.primaryAlt); frame:Hide(); self.frame = frame
  local titleBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  titleBar:SetPoint("TOPLEFT", 1, -1); titleBar:SetPoint("TOPRIGHT", -1, -1); titleBar:SetHeight(30); Backdrop(titleBar, 1, COLORS.frame, COLORS.frame)
  local title = Text(titleBar, "LEFT", 16, true); title:SetPoint("LEFT", 10, 0); title:SetText("Goblin")
  local section = Text(titleBar, "LEFT", 13, true); section:SetPoint("LEFT", title, "RIGHT", 18, 0); section:SetText("Inventory")
  SetColor(function(...) section:SetTextColor(...) end, COLORS.indicator)
  local close = Button(titleBar, "×", 24, function() frame:Hide() end); close:SetPoint("RIGHT", -3, 0)
  local options = Button(titleBar, "Sources", 70, function() self.options:SetShown(not self.options:IsShown()); self:RefreshOptions() end); options:SetPoint("RIGHT", close, "LEFT", -6, 0)
  local search = Input(frame, 270, 22); search:SetPoint("TOPLEFT", 10, -38)
  search:SetScript("OnTextChanged", function() self:RefreshUI() end); self.search = search
  local hint = Text(search, "LEFT"); hint:SetPoint("LEFT", 6, 0); hint:SetText("Filter by keyword"); hint:SetTextColor(0.5, 0.54, 0.58)
  search:SetScript("OnEditFocusGained", function() hint:Hide() end); search:SetScript("OnEditFocusLost", function(s) if s:GetText() == "" then hint:Show() end end)
  local sourceLabel = Text(frame, "LEFT", 12); sourceLabel:SetPoint("LEFT", search, "RIGHT", 12, 0); sourceLabel:SetText("Value Price Source")
  local source = Input(frame, 210, 22); source:SetPoint("LEFT", sourceLabel, "RIGHT", 8, 0); source:SetText(self.db.settings.priceSource)
  source:SetScript("OnEnterPressed", function(edit)
    local valid, err = self:ValidatePriceSource(edit:GetText())
    if valid then self.db.settings.priceSource = strtrim(edit:GetText()); edit:ClearFocus(); self:RefreshUI()
    else print("|cffff5555Goblin:|r " .. tostring(err or "Invalid TSM price source")) end
  end)
  source:SetScript("OnEscapePressed", function(edit) edit:SetText(self.db.settings.priceSource); edit:ClearFocus() end); self.priceEdit = source
  local header = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil); header:SetPoint("TOPLEFT", 10, -68); header:SetSize(766, 24); Backdrop(header, 1, COLORS.frame, COLORS.active)
  self.headers = {}; local x = 4
  for _, column in ipairs(COLUMNS) do
    local col = column
    local button = CreateFrame("Button", nil, header); button:SetPoint("TOPLEFT", x, 0); button:SetSize(col.width, 24)
    button.text = Text(button, col.align or "RIGHT", 12, true, true); button.text:SetAllPoints(); button.text:SetText(col.label)
    button.indicator = button:CreateTexture(nil, "ARTWORK"); button.indicator:SetPoint("BOTTOMLEFT"); button.indicator:SetPoint("BOTTOMRIGHT"); button.indicator:SetHeight(2)
    SetColor(function(...) button.indicator:SetColorTexture(...) end, COLORS.indicator); button.indicator:Hide()
    button:SetScript("OnClick", function() self:SetSort(col.key) end); x = x + col.width
    self.headers[col.key] = button
  end
  self.rows = {}
  for index = 1, MAX_VISIBLE_ROWS do
    local row = CreateFrame("Button", nil, frame); row:SetPoint("TOPLEFT", 10, -92 - (index - 1) * ROW_HEIGHT); row:SetSize(766, ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints(); SetColor(function(...) row.bg:SetColorTexture(...) end, COLORS.primary)
    row.highlight = row:CreateTexture(nil, "HIGHLIGHT"); row.highlight:SetAllPoints(); SetColor(function(...) row.highlight:SetColorTexture(...) end, COLORS.active, 0.55)
    row.columns = {}; local columnX = 4
    for _, column in ipairs(COLUMNS) do
      local cell = Text(row, column.align or "RIGHT", 12, false, column.key ~= "name"); cell:SetPoint("TOPLEFT", columnX, 0); cell:SetSize(column.width - 6, ROW_HEIGHT); cell:SetJustifyV("MIDDLE")
      row.columns[column.key] = cell; columnX = columnX + column.width
    end
    row:SetScript("OnEnter", function(r) if r.data and r.data.link then GameTooltip:SetOwner(r, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(r.data.link); GameTooltip:AddLine(" "); GameTooltip:AddDoubleLine("TSM unit value", self:FormatMoney(r.data.unitPrice)); GameTooltip:Show() end end)
    row:SetScript("OnLeave", GameTooltip_Hide); self.rows[index] = row
  end
  local scroll = CreateFrame("Slider", nil, frame); scroll:SetOrientation("VERTICAL"); scroll:SetWidth(12); scroll:SetPoint("TOPRIGHT", -2, -96); scroll:SetPoint("BOTTOMRIGHT", -2, 43); scroll:SetMinMaxValues(0, 0); scroll:SetValueStep(1); scroll:SetObeyStepOnDrag(true)
  local thumb = scroll:CreateTexture(nil, "ARTWORK"); thumb:SetSize(4, 42); SetColor(function(...) thumb:SetColorTexture(...) end, COLORS.activeAlt); scroll:SetThumbTexture(thumb)
  scroll:SetScript("OnValueChanged", function() self:RefreshUI(true) end); self.scroll = scroll
  local footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil); footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(38); Backdrop(footer, 1, COLORS.frame, COLORS.frame)
  local summary = Text(footer, "RIGHT", 12, true); summary:SetPoint("RIGHT", -12, 0); summary:SetSize(600, 22); self.summary = summary
  local resize = CreateFrame("Button", nil, frame); resize:SetSize(18, 18); resize:SetPoint("BOTTOMRIGHT", -2, 2)
  resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  resize:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
  resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
  self.headerFrame = header
  self.visibleRows = 25
  local function UpdateLayout()
    self.db.window.width, self.db.window.height = frame:GetWidth(), frame:GetHeight()
    local extraWidth = frame:GetWidth() - 790
    header:SetWidth(766 + extraWidth)
    self.headers.value:SetWidth(130 + extraWidth)
    for _, row in ipairs(self.rows) do
      row:SetWidth(766 + extraWidth)
      row.columns.value:SetWidth(124 + extraWidth)
    end
    self.visibleRows = math.max(1, math.min(MAX_VISIBLE_ROWS, math.floor((frame:GetHeight() - 131) / ROW_HEIGHT)))
    self:RefreshUI()
  end
  frame:SetScript("OnSizeChanged", UpdateLayout)
  frame:SetScript("OnMouseWheel", function(_, delta)
    scroll:SetValue(math.max(0, math.min(select(2, scroll:GetMinMaxValues()), scroll:GetValue() - delta * 3)))
  end)
  self:CreateOptions(); self:RefreshUI()
end

function SL:RefreshUI(fromScroll)
  if not self.frame or not self.frame:IsShown() then return end
  for key, header in pairs(self.headers or {}) do header.indicator:SetShown(key == self.db.settings.sort) end
  local rows, itemValue, gold = self:BuildLedger(self.search and self.search:GetText())
  self.ledgerRows = rows
  local maximum = math.max(0, #rows - (self.visibleRows or 25))
  self.scroll:SetMinMaxValues(0, maximum)
  if not fromScroll and self.scroll:GetValue() > maximum then self.scroll:SetValue(maximum) end
  local offset = math.floor(self.scroll:GetValue() + 0.5)
  for index, widget in ipairs(self.rows) do
    local row = rows[index + offset]; widget.data = row
    if index <= (self.visibleRows or 25) and row then
      widget:Show(); widget.columns.name:SetText((row.link and "|T" .. (select(10, GetItemInfo(row.link)) or 134400) .. ":16|t " or "") .. (row.link or row.name or row.itemString))
      for _, key in ipairs({ "total", "bags", "bank", "equipped", "mail", "auctions", "guild" }) do widget.columns[key]:SetText((row[key] or 0) > 0 and row[key] or "") end
      widget.columns.value:SetText(self:FormatMoney(row.value))
    else widget:Hide() end
  end
  self.summary:SetText(string.format("Items: %s   Gold: %s   |cffffd839Net worth: %s|r", self:FormatMoney(itemValue), self:FormatMoney(gold), self:FormatMoney(itemValue + gold)))
  self:RefreshOptions()
end

function SL:ToggleUI()
  if not self.frame then return end
  self.frame:SetShown(not self.frame:IsShown())
  if self.frame:IsShown() then self:RefreshUI() end
end
