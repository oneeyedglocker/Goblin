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

local COLORS_GUILD = { 0.55, 0.72, 0.92 }
local COLORS_CLASS = { 0.68, 0.70, 0.66 }
local COLORS_STALE = {
  fresh = { 0.30, 0.86, 0.50 },
  stale = { 0.99, 0.62, 0.20 },
  never = { 0.55, 0.55, 0.58 },
}
local COLORS_SUBTLE = { 0.58, 0.63, 0.61 }

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

-- Pill checkbox: filled yellow square + label, sized to fit inside a card cell.
local function PillCheckbox(parent, label, get, set, width)
  local pill = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  pill:SetSize(width or 148, 22); Backdrop(pill, 1, COLORS.primary, COLORS.primary)
  local box = CreateFrame("Frame", nil, pill, BackdropTemplateMixin and "BackdropTemplate" or nil)
  box:SetSize(13, 13); box:SetPoint("LEFT", 6, 0); Backdrop(box, 1, COLORS.primaryAlt, COLORS.active)
  box.fill = box:CreateTexture(nil, "ARTWORK"); box.fill:SetPoint("TOPLEFT", 2, -2); box.fill:SetPoint("BOTTOMRIGHT", -2, 2)
  SetColor(function(...) box.fill:SetColorTexture(...) end, COLORS.indicator)
  pill.text = Text(pill, "LEFT", 12); pill.text:SetPoint("LEFT", box, "RIGHT", 8, 0); pill.text:SetPoint("RIGHT", -4, 0)
  pill.text:SetText(label); SetColor(function(...) pill.text:SetTextColor(...) end, COLORS.text)
  pill.highlight = pill:CreateTexture(nil, "HIGHLIGHT"); pill.highlight:SetAllPoints()
  SetColor(function(...) pill.highlight:SetColorTexture(...) end, COLORS.activeAlt, 0.05)
  pill.Update = function() box.fill:SetShown(get() and true or false) end
  pill:SetScript("OnClick", function() set(not get() and true or false); pill.Update(); SL:RefreshUI() end)
  pill:SetScript("OnShow", pill.Update); pill.Update()
  return pill
end

-- Guild switch toggle: yellow-on / gray-off pill with a moving thumb.
local function ToggleSwitch(parent, get, set)
  local sw = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  sw:SetSize(34, 16); Backdrop(sw, 1, COLORS.primaryAlt, COLORS.active)
  sw.thumb = sw:CreateTexture(nil, "ARTWORK")
  sw.thumb:SetSize(14, 12)
  SetColor(function(...) sw.thumb:SetColorTexture(...) end, COLORS.indicator)
  sw.Update = function()
    local on = get() and true or false
    if on then
      SetColor(function(...) sw:SetBackdropColor(...) end, COLORS.primary)
      SetColor(function(...) sw.thumb:SetColorTexture(...) end, COLORS.indicator)
      sw.thumb:ClearAllPoints(); sw.thumb:SetPoint("RIGHT", -2, 0)
    else
      SetColor(function(...) sw:SetBackdropColor(...) end, COLORS.primaryAlt)
      sw.thumb:SetColorTexture(0.55, 0.55, 0.58, 1)
      sw.thumb:ClearAllPoints(); sw.thumb:SetPoint("LEFT", 2, 0)
    end
  end
  sw:SetScript("OnClick", function() set(not get() and true or false); sw.Update(); SL:RefreshUI() end)
  sw:SetScript("OnShow", sw.Update); sw.Update()
  return sw
end

local function FreshnessBadge(parent)
  local frame = CreateFrame("Frame", nil, parent); frame:SetSize(120, 14)
  frame.dot = frame:CreateTexture(nil, "ARTWORK"); frame.dot:SetSize(6, 6); frame.dot:SetPoint("LEFT", 0, 0)
  frame.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
  frame.text = Text(frame, "LEFT", 11); frame.text:SetPoint("LEFT", frame.dot, "RIGHT", 6, 0); frame.text:SetPoint("RIGHT", 0, 0)
  frame.Set = function(status, label)
    local c = COLORS_STALE[status] or COLORS_STALE.never
    frame.dot:SetColorTexture(c[1], c[2], c[3], 1)
    if status == "never" then frame.text:SetText("Never scanned")
    else frame.text:SetText("Scanned " .. (label or "?")) end
    frame.text:SetTextColor(0.72, 0.75, 0.72)
  end
  return frame
end

-- Card container with a clickable header row and a collapsible body Frame.
local function CreateCard(parent)
  local card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Backdrop(card, 1, COLORS.primary, COLORS.frame)
  card.header = CreateFrame("Button", nil, card, BackdropTemplateMixin and "BackdropTemplate" or nil)
  card.header:SetHeight(36); card.header:SetPoint("TOPLEFT", 0, 0); card.header:SetPoint("TOPRIGHT", 0, 0)
  Backdrop(card.header, 1, COLORS.primaryAlt, COLORS.primaryAlt)
  local hl = card.header:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
  SetColor(function(...) hl:SetColorTexture(...) end, COLORS.activeAlt, 0.05)
  card.caret = Text(card.header, "LEFT", 11); card.caret:SetPoint("LEFT", 10, 0); card.caret:SetText("v")
  SetColor(function(...) card.caret:SetTextColor(...) end, COLORS.indicator)
  card.body = CreateFrame("Frame", nil, card); card.body:SetPoint("TOPLEFT", 0, -36); card.body:SetPoint("TOPRIGHT", 0, -36)
  card.expanded = true
  card.SetExpanded = function(v)
    card.expanded = v and true or false
    card.caret:SetText(card.expanded and "v" or ">")
    card.body:SetShown(card.expanded)
    card:SetHeight(card.expanded and (36 + (card.bodyHeight or 0)) or 36)
    if SL.RelayoutSources then SL:RelayoutSources() end
  end
  card.header:SetScript("OnClick", function() card.SetExpanded(not card.expanded) end)
  return card
end

-- Sources panel: dark-card layout matching the goblin-sources-panel mockup.
-- One card per character (pills for gold + each location) and one per guild
-- (master switch + guild-gold pill + one pill per known tab). All cards share
-- the same collapsible frame so users can hide seldom-touched alts.

local CARD_PADDING_X = 12
local CARD_BODY_ROW_H = 24
local CARD_BODY_TOP = 6
local CARD_BODY_BOTTOM = 8
local CARDS_GAP = 8

function SL:CreateOptions()
  local frame = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -8, -40)
  frame:SetSize(560, 620); frame:SetFrameLevel(self.frame:GetFrameLevel() + 20); Backdrop(frame, 1, COLORS.primary, COLORS.frame); frame:Hide()
  self.options = frame

  local titleBar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  titleBar:SetPoint("TOPLEFT", 1, -1); titleBar:SetPoint("TOPRIGHT", -1, -1); titleBar:SetHeight(36); Backdrop(titleBar, 1, COLORS.frame, COLORS.frame)
  local brand = Text(titleBar, "LEFT", 15, true); brand:SetPoint("LEFT", 12, 0); brand:SetText("Goblin")
  SetColor(function(...) brand:SetTextColor(...) end, COLORS.text)
  local section = Text(titleBar, "LEFT", 15, true); section:SetPoint("LEFT", brand, "RIGHT", 8, 0); section:SetText("Sources")
  SetColor(function(...) section:SetTextColor(...) end, COLORS.indicator)
  local close = Button(titleBar, "×", 26, function() frame:Hide() end); close:SetPoint("RIGHT", -6, 0)

  local intro = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  intro:SetPoint("TOPLEFT", 1, -37); intro:SetPoint("TOPRIGHT", -1, -37); intro:SetHeight(48); Backdrop(intro, 1, COLORS.primary, COLORS.primary)
  local heading = Text(intro, "LEFT", 13, true); heading:SetPoint("TOPLEFT", 12, -8); heading:SetText("Included in net worth")
  SetColor(function(...) heading:SetTextColor(...) end, COLORS.text)
  local desc = Text(intro, "LEFT", 11); desc:SetPoint("TOPLEFT", 12, -26); desc:SetText("Choose the characters, locations, and guild banks Goblin should count.")
  SetColor(function(...) desc:SetTextColor(...) end, COLORS_SUBTLE)
  local enableAll = Button(intro, "Enable all", 72, function() self:BulkSetSources(true) end); enableAll:SetPoint("TOPRIGHT", -90, -12)
  Backdrop(enableAll, 0, COLORS.primary, COLORS.primary); SetColor(function(...) enableAll.label:SetTextColor(...) end, COLORS.indicator)
  local disableAll = Button(intro, "Disable all", 76, function() self:BulkSetSources(false) end); disableAll:SetPoint("TOPRIGHT", -10, -12)
  Backdrop(disableAll, 0, COLORS.primary, COLORS.primary); SetColor(function(...) disableAll.label:SetTextColor(...) end, COLORS_SUBTLE)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -88); scroll:SetPoint("BOTTOMRIGHT", -28, 34)
  local content = CreateFrame("Frame", nil, scroll); content:SetSize(524, 1); scroll:SetScrollChild(content)
  self.optionsScroll, self.optionsContent = scroll, content

  local footer = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  footer:SetPoint("BOTTOMLEFT", 1, 1); footer:SetPoint("BOTTOMRIGHT", -1, 1); footer:SetHeight(30); Backdrop(footer, 1, COLORS.frame, COLORS.frame)
  local footerHint = Text(footer, "LEFT", 11); footerHint:SetPoint("LEFT", 12, 0); footerHint:SetText("Changes update net worth immediately.")
  SetColor(function(...) footerHint:SetTextColor(...) end, COLORS_SUBTLE)
  local staleText = Text(footer, "RIGHT", 11, true); staleText:SetPoint("RIGHT", -12, 0); self.staleFooter = staleText
  return frame
end

-- Bulk enable/disable used by the Enable all / Disable all header buttons.
function SL:BulkSetSources(enabled)
  local v = enabled and true or false
  for key in pairs(self.db.characters or {}) do
    self.db.settings.characters[key] = v
    self.db.settings.characterGold[key] = v
    self.db.settings.characterCategories[key] = self.db.settings.characterCategories[key] or {}
    for _, category in ipairs(self.CATEGORIES) do
      if category ~= "guild" then self.db.settings.characterCategories[key][category] = v end
    end
  end
  for key, guild in pairs(self.db.guilds or {}) do
    self.db.settings.guilds[key] = v
    self.db.settings.guildGold[key] = v
    self.db.settings.guildTabs[key] = self.db.settings.guildTabs[key] or {}
    for tab in pairs(guild.tabs or {}) do self.db.settings.guildTabs[key][tab] = v end
  end
  self:RefreshUI()
end

local function FormatClass(class)
  if not class then return nil end
  local pretty = class:sub(1, 1) .. class:sub(2):lower()
  return pretty
end

function SL:BuildCharacterCard(parent, characterKey)
  local character = self.db.characters[characterKey]
  local card = CreateCard(parent)
  local nameStr = Text(card.header, "LEFT", 13, true); nameStr:SetPoint("LEFT", 28, 0)
  nameStr:SetText(character.name or "?"); SetColor(function(...) nameStr:SetTextColor(...) end, COLORS.text)
  local realm = Text(card.header, "LEFT", 13, true); realm:SetPoint("LEFT", nameStr, "RIGHT", 8, 0)
  realm:SetText("— " .. (character.realm or "?")); SetColor(function(...) realm:SetTextColor(...) end, COLORS.indicator)
  local meta = Text(card.header, "LEFT", 11); meta:SetPoint("LEFT", realm, "RIGHT", 8, 0); meta:SetPoint("RIGHT", -140, 0)
  local class = FormatClass(character.class)
  if character.guildName then
    meta:SetText(string.format("|cff8fb6f0<%s>|r  |cffababab· %s|r", character.guildName, class or ""))
  else
    meta:SetText(string.format("|cff787878No guild|r  |cffababab· %s|r", class or ""))
  end
  local badge = FreshnessBadge(card.header); badge:SetPoint("RIGHT", -12, 0)
  local locations = { "bags", "bank", "equipped", "mail", "auctions" }
  local newestStamp, newestStatus
  for _, loc in ipairs(locations) do
    local info = self:GetLocationFreshness(characterKey, loc)
    if info.stamp and (not newestStamp or info.stamp > newestStamp) then newestStamp, newestStatus = info.stamp, info.status end
  end
  local goldInfo = self:GetLocationFreshness(characterKey, "gold")
  if goldInfo.stamp and (not newestStamp or goldInfo.stamp > newestStamp) then newestStamp, newestStatus = goldInfo.stamp, goldInfo.status end
  badge.Set(newestStamp and newestStatus or "never", newestStamp and self:FormatAge(time() - newestStamp) or nil)

  local pillWidth = math.floor((512 - CARD_PADDING_X * 2 - 8) / 3)
  local pills = {
    { key = "gold", label = "Gold" },
    { key = "bags", label = "Bags" },
    { key = "bank", label = "Bank" },
    { key = "equipped", label = "Equipped" },
    { key = "mail", label = "Mail" },
    { key = "auctions", label = "Auctions" },
  }
  for index, pillDef in ipairs(pills) do
    local col = ((index - 1) % 3)
    local row = math.floor((index - 1) / 3)
    local get, set
    if pillDef.key == "gold" then
      get = function() return self:IsCharacterGoldIncluded(characterKey) end
      set = function(v) self.db.settings.characterGold[characterKey] = v end
    else
      local loc = pillDef.key
      get = function() return self:IsCharacterCategoryIncluded(characterKey, loc) end
      set = function(v)
        self.db.settings.characterCategories[characterKey] = self.db.settings.characterCategories[characterKey] or {}
        self.db.settings.characterCategories[characterKey][loc] = v
      end
    end
    local pill = PillCheckbox(card.body, pillDef.label, get, set, pillWidth)
    pill:SetPoint("TOPLEFT", CARD_PADDING_X + col * (pillWidth + 4), -(CARD_BODY_TOP + row * (CARD_BODY_ROW_H)))
  end
  card.bodyHeight = CARD_BODY_TOP + CARD_BODY_ROW_H * 2 + CARD_BODY_BOTTOM
  card.body:SetHeight(card.bodyHeight)
  card:SetHeight(36 + card.bodyHeight)
  return card
end

function SL:BuildGuildCard(parent, guildKey)
  local guild = self.db.guilds[guildKey]
  local card = CreateCard(parent)
  local guildName = guild.name or guildKey
  local realmName = guild.realm or (guildKey:match(" %- (.+)$")) or ""
  local nameStr = Text(card.header, "LEFT", 13, true); nameStr:SetPoint("LEFT", 28, 0)
  nameStr:SetText(guildName); SetColor(function(...) nameStr:SetTextColor(...) end, COLORS.text)
  local realm = Text(card.header, "LEFT", 13, true); realm:SetPoint("LEFT", nameStr, "RIGHT", 8, 0)
  realm:SetText("— " .. realmName); SetColor(function(...) realm:SetTextColor(...) end, COLORS.indicator)
  local memberNames = {}
  for _, character in pairs(self.db.characters) do
    if character.guildKey == guildKey then memberNames[#memberNames + 1] = character.name or "?" end
  end
  table.sort(memberNames)
  local tabCount = 0
  for _ in pairs(guild.tabs or {}) do tabCount = tabCount + 1 end
  local memberText = #memberNames > 0 and table.concat(memberNames, ", ") or "No associated character"
  local meta = Text(card.header, "LEFT", 11); meta:SetPoint("LEFT", realm, "RIGHT", 8, 0); meta:SetPoint("RIGHT", -60, 0)
  meta:SetText(string.format("|cff9c9c9c%s  · %d tab%s scanned|r", memberText, tabCount, tabCount == 1 and "" or "s"))
  local sw = ToggleSwitch(card.header, function() return self:IsGuildIncluded(guildKey) end, function(v) self.db.settings.guilds[guildKey] = v end)
  sw:SetPoint("RIGHT", -12, 0)

  local pillWidth = math.floor((512 - CARD_PADDING_X * 2 - 8) / 3)
  local pillDefs = { { key = "gold", label = "Guild gold" } }
  local tabs = {}
  for tab in pairs(guild.tabs or {}) do tabs[#tabs + 1] = tab end
  table.sort(tabs)
  for _, tab in ipairs(tabs) do
    local label = (guild.tabNames and guild.tabNames[tab]) or ("Tab " .. tab)
    pillDefs[#pillDefs + 1] = { key = tab, label = tab .. ": " .. label }
  end
  for index, pillDef in ipairs(pillDefs) do
    local col = ((index - 1) % 3)
    local row = math.floor((index - 1) / 3)
    local get, set
    if pillDef.key == "gold" then
      get = function() return self:IsGuildGoldIncluded(guildKey) end
      set = function(v) self.db.settings.guildGold[guildKey] = v end
    else
      local tabIndex = pillDef.key
      get = function() return self:IsGuildTabIncluded(guildKey, tabIndex) end
      set = function(v)
        self.db.settings.guildTabs[guildKey] = self.db.settings.guildTabs[guildKey] or {}
        self.db.settings.guildTabs[guildKey][tabIndex] = v
      end
    end
    local pill = PillCheckbox(card.body, pillDef.label, get, set, pillWidth)
    pill:SetPoint("TOPLEFT", CARD_PADDING_X + col * (pillWidth + 4), -(CARD_BODY_TOP + row * CARD_BODY_ROW_H))
  end
  local rowsUsed = math.max(1, math.ceil(#pillDefs / 3))
  card.bodyHeight = CARD_BODY_TOP + CARD_BODY_ROW_H * rowsUsed + CARD_BODY_BOTTOM
  card.body:SetHeight(card.bodyHeight)
  card:SetHeight(36 + card.bodyHeight)
  return card
end

function SL:RelayoutSources()
  local y = -4
  for _, group in ipairs(self.sourceGroups or {}) do
    group.label:ClearAllPoints(); group.label:SetPoint("TOPLEFT", 10, y)
    group.count:ClearAllPoints(); group.count:SetPoint("LEFT", group.label, "RIGHT", 8, 0)
    y = y - 22
    for _, card in ipairs(group.cards) do
      card:ClearAllPoints(); card:SetPoint("TOPLEFT", 6, y); card:SetPoint("TOPRIGHT", -6, y)
      y = y - (card:GetHeight() + CARDS_GAP)
    end
    y = y - 8
  end
  self.optionsContent:SetHeight(math.max(1, -y + 8))
end

function SL:RefreshOptions()
  if not self.options or not self.options:IsShown() then return end
  for _, group in ipairs(self.sourceGroups or {}) do
    for _, card in ipairs(group.cards) do card:Hide(); card:SetParent(nil) end
    group.label:Hide(); group.label:SetParent(nil)
    group.count:Hide(); group.count:SetParent(nil)
  end
  self.sourceGroups = {}
  local content = self.optionsContent

  local characterLabel = Text(content, "LEFT", 12, true); characterLabel:SetText("CHARACTERS")
  SetColor(function(...) characterLabel:SetTextColor(...) end, COLORS.indicator)
  local characterKeys = {}
  for key in pairs(self.db.characters or {}) do characterKeys[#characterKeys + 1] = key end
  table.sort(characterKeys)
  local characterCount = Text(content, "LEFT", 11); characterCount:SetText(string.format("%d recorded", #characterKeys))
  SetColor(function(...) characterCount:SetTextColor(...) end, COLORS_SUBTLE)
  local characterCards = {}
  for _, key in ipairs(characterKeys) do characterCards[#characterCards + 1] = self:BuildCharacterCard(content, key) end
  self.sourceGroups[#self.sourceGroups + 1] = { label = characterLabel, count = characterCount, cards = characterCards }

  local guildLabel = Text(content, "LEFT", 12, true); guildLabel:SetText("GUILD BANKS")
  SetColor(function(...) guildLabel:SetTextColor(...) end, COLORS.indicator)
  local guildKeys = {}
  for key in pairs(self.db.guilds or {}) do guildKeys[#guildKeys + 1] = key end
  table.sort(guildKeys)
  local guildCount = Text(content, "LEFT", 11); guildCount:SetText(string.format("%d recorded", #guildKeys))
  SetColor(function(...) guildCount:SetTextColor(...) end, COLORS_SUBTLE)
  local guildCards = {}
  for _, key in ipairs(guildKeys) do guildCards[#guildCards + 1] = self:BuildGuildCard(content, key) end
  self.sourceGroups[#self.sourceGroups + 1] = { label = guildLabel, count = guildCount, cards = guildCards }

  self:RelayoutSources()

  local stale = self.GetStaleSources and self:GetStaleSources() or {}
  if self.staleFooter then
    if #stale == 0 then
      self.staleFooter:SetText("All sources fresh")
      SetColor(function(...) self.staleFooter:SetTextColor(...) end, COLORS_STALE.fresh)
    else
      self.staleFooter:SetText(string.format("%d source%s has stale data", #stale, #stale == 1 and "" or "s"))
      SetColor(function(...) self.staleFooter:SetTextColor(...) end, COLORS.indicator)
    end
  end
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
