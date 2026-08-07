local _, SL = ...

-- Summary dashboard: single-pass aggregation of the ledger DB into per-widget
-- rollups, then a fixed grid of widgets rendered inside the main frame's
-- content area. v1 uses a static layout (drag/drop deferred). Data updates
-- ride on the same RefreshUI cycle that feeds the Inventory table.

local COLORS_SUMMARY = {
  primary    = { 0x14/255, 0x16/255, 0x16/255 },
  primaryAlt = { 0x1c/255, 0x20/255, 0x20/255 },
  frame      = { 0x42/255, 0x4c/255, 0x4f/255 },
  edge       = { 0x2a/255, 0x2f/255, 0x31/255 },
  text       = { 1, 1, 1 },
  dim        = { 0x93/255, 0x99/255, 0x9a/255 },
  dimmer     = { 0x6a/255, 0x6f/255, 0x6f/255 },
  yellow     = { 1.00, 0.85, 0.22 },
  green      = { 0.30, 0.86, 0.50 },
  orange     = { 0.99, 0.62, 0.20 },
  guild      = { 0.55, 0.72, 0.92 },
  purple     = { 0.65, 0.40, 0.83 },
  subtle     = { 0.58, 0.63, 0.61 },
}
local LOC_COLORS = {
  guild    = COLORS_SUMMARY.yellow,
  bags     = COLORS_SUMMARY.guild,
  bank     = COLORS_SUMMARY.purple,
  mail     = COLORS_SUMMARY.green,
  auctions = COLORS_SUMMARY.orange,
  equipped = { 0.48, 0.50, 0.50 },
}
local LOC_ORDER = { "guild", "bags", "bank", "mail", "auctions", "equipped" }
local LOC_LABEL = { guild = "Guild", bags = "Bags", bank = "Bank", mail = "Mail", auctions = "AH", equipped = "Equipped" }

local BODY_FONT      = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Regular.ttf"
local BODY_BOLD_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Bold.ttf"
local TABLE_FONT     = "Interface\\AddOns\\TradeSkillMaster\\Media\\Roboto-Medium.ttf"

local function SetColor(target, color, alpha)
  target(color[1], color[2], color[3], alpha or 1)
end

local function Backdrop(frame, alpha, background, border)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  SetColor(function(...) frame:SetBackdropColor(...) end, background or COLORS_SUMMARY.primary, alpha or 1)
  SetColor(function(...) frame:SetBackdropBorderColor(...) end, border or COLORS_SUMMARY.edge)
end

local function Text(parent, align, size, bold, color)
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetJustifyH(align or "LEFT")
  t:SetFont(bold and BODY_BOLD_FONT or BODY_FONT, size or 12)
  local c = color or COLORS_SUMMARY.text
  t:SetTextColor(c[1], c[2], c[3])
  return t
end

local function FormatShortMoney(copper)
  copper = tonumber(copper) or 0
  local gold = copper / 10000
  if gold >= 1000000 then return string.format("%.1fM", gold / 1000000) .. "g"
  elseif gold >= 1000 then return string.format("%.1fk", gold / 1000) .. "g"
  elseif gold >= 1 then return string.format("%.0fg", gold)
  else return string.format("%ds", math.floor(copper / 100)) end
end

-- ============================================================================
-- Aggregation: build every rollup the widgets need in a single pass over the DB
-- ============================================================================

function SL:BuildSummaryData()
  local data = {
    itemValue = 0, gold = 0, totalStacks = 0, uniqueItems = 0,
    perLocation = { bags = 0, bank = 0, equipped = 0, mail = 0, auctions = 0, guild = 0 },
    perCharacter = {},
    perCharacterMap = {},
    topItems = {},
    unpricedStacks = 0,
    unpricedUnique = 0,
    history = self.db.history or {},
  }
  local itemTotals = {}

  local function ensureCharacter(key, includeGold)
    local pc = data.perCharacterMap[key]
    if pc then return pc end
    local char = self.db.characters[key]
    pc = { key = key, name = char.name, realm = char.realm, class = char.class, guildName = char.guildName, itemValue = 0, gold = 0 }
    data.perCharacterMap[key] = pc
    data.perCharacter[#data.perCharacter + 1] = pc
    return pc
  end

  local function addItem(itemString, item, location, characterKey)
    local count = item.count or 0
    if not self.db.settings.includeSoulbound then
      count = math.max(0, count - (item.boundCount or 0))
    end
    if count <= 0 then return end
    local unitPrice = self:GetPrice(itemString) or 0
    local value = count * unitPrice
    data.itemValue = data.itemValue + value
    data.totalStacks = data.totalStacks + count
    data.perLocation[location] = (data.perLocation[location] or 0) + value
    local row = itemTotals[itemString]
    if not row then
      row = { itemString = itemString, link = item.link, name = item.name or item.itemString, count = 0, unitPrice = unitPrice, value = 0 }
      itemTotals[itemString] = row
      data.uniqueItems = data.uniqueItems + 1
      if unitPrice == 0 then data.unpricedUnique = data.unpricedUnique + 1 end
    end
    row.count = row.count + count
    row.value = row.value + value
    if unitPrice == 0 then data.unpricedStacks = data.unpricedStacks + count end
    if characterKey then
      local pc = ensureCharacter(characterKey)
      pc.itemValue = pc.itemValue + value
    end
  end

  for key, character in pairs(self.db.characters or {}) do
    if self:IsCharacterIncluded(key) then
      if self.db.settings.includeGold and self:IsCharacterGoldIncluded(key) then
        data.gold = data.gold + (character.gold or 0)
        local pc = ensureCharacter(key)
        pc.gold = pc.gold + (character.gold or 0)
      end
      for _, location in ipairs({ "bags", "bank", "equipped", "mail", "auctions" }) do
        if self:IsCharacterCategoryIncluded(key, location) then
          for itemString, item in pairs((character.locations or {})[location] or {}) do
            addItem(itemString, item, location, key)
          end
        end
      end
    end
  end
  if self.db.settings.categories.guild then
    for gkey, guild in pairs(self.db.guilds or {}) do
      if self:IsGuildIncluded(gkey) then
        if self.db.settings.includeGuildGold and self:IsGuildGoldIncluded(gkey) then
          data.gold = data.gold + (guild.gold or 0)
        end
        for tab, items in pairs(guild.tabs or {}) do
          if self:IsGuildTabIncluded(gkey, tab) then
            for itemString, item in pairs(items) do
              addItem(itemString, item, "guild", nil)
            end
          end
        end
      end
    end
  end
  local topList = {}
  for _, row in pairs(itemTotals) do topList[#topList + 1] = row end
  table.sort(topList, function(a, b) return a.value > b.value end)
  for i = 1, math.min(8, #topList) do data.topItems[i] = topList[i] end
  table.sort(data.perCharacter, function(a, b) return (a.itemValue + a.gold) > (b.itemValue + b.gold) end)
  data.netWorth = data.itemValue + data.gold
  return data
end

-- ============================================================================
-- Widget primitives
-- ============================================================================

local function WidgetShell(parent, label)
  local w = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Backdrop(w, 1, COLORS_SUMMARY.primary, COLORS_SUMMARY.edge)
  local lbl = Text(w, "LEFT", 10, true, COLORS_SUMMARY.dim)
  lbl:SetPoint("TOPLEFT", 12, -10); lbl:SetText(label:upper())
  w.label = lbl
  return w
end

-- ============================================================================
-- Widget definitions (create + refresh in one place per widget type)
-- ============================================================================

local Widgets = {}

function Widgets.netWorthHero(SL, parent)
  local w = WidgetShell(parent, "Net worth")
  local big = w:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  big:SetPoint("TOPLEFT", 12, -28); big:SetJustifyH("LEFT"); big:SetWordWrap(false)
  big:SetFont(BODY_BOLD_FONT, 30); big:SetTextColor(1, 0.85, 0.22)
  local delta = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  delta:SetPoint("LEFT", big, "RIGHT", 8, 2); delta:SetWordWrap(false)
  local breakdown = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  breakdown:SetPoint("TOPLEFT", 12, -66); breakdown:SetPoint("TOPRIGHT", -12, -66); breakdown:SetWordWrap(false)
  local spark = CreateFrame("Frame", nil, w)
  spark:SetPoint("BOTTOMLEFT", 12, 10); spark:SetPoint("BOTTOMRIGHT", -12, 10); spark:SetHeight(28)
  w.spark = spark; w.big = big; w.delta = delta; w.breakdown = breakdown
  w.Update = function(_, data)
    big:SetText(SL:FormatMoney(data.netWorth))
    local history = data.history or {}
    if #history >= 2 then
      local oldest = history[1]; local latest = history[#history]
      local diff = latest.net - oldest.net
      local sign = diff >= 0 and "|cff4dd280▲|r " or "|cffff9d33▼|r "
      delta:SetText(string.format("%s%s / %dd", sign, SL:FormatMoney(math.abs(diff)),
        math.max(1, math.floor((latest.t - oldest.t) / 86400))))
    else
      delta:SetText("|cff7a7f7fno trend yet|r")
    end
    breakdown:SetText(string.format("|cffababab%s items · %s gold · %s stacks|r",
      SL:FormatMoney(data.itemValue), SL:FormatMoney(data.gold), data.totalStacks))
    if spark.bars then for _, b in ipairs(spark.bars) do b:Hide() end end
    spark.bars = spark.bars or {}
    local recent = {}
    local cutoff = time() - 7 * 86400
    for _, s in ipairs(history) do if s.t >= cutoff then recent[#recent + 1] = s end end
    if #recent > 0 then
      local sw, sh = spark:GetWidth(), spark:GetHeight()
      local yMax = 1
      for _, s in ipairs(recent) do if s.net > yMax then yMax = s.net end end
      local barSpace = sw / #recent
      for i, s in ipairs(recent) do
        local bar = spark.bars[i]
        if not bar then
          bar = spark:CreateTexture(nil, "ARTWORK"); bar:SetTexture("Interface\\Buttons\\WHITE8X8")
          spark.bars[i] = bar
        end
        bar:SetColorTexture(1, 0.85, 0.22, 0.75)
        local h = math.max(1, (s.net / yMax) * sh)
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", (i - 1) * barSpace, 0)
        bar:SetSize(math.max(1, barSpace - 0.5), h); bar:Show()
      end
    end
  end
  return w
end

local function StatWidget(SL, parent, label, getter, subGetter)
  local w = WidgetShell(parent, label)
  local num = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  num:SetPoint("TOPLEFT", 12, -28); num:SetPoint("TOPRIGHT", -8, -28)
  num:SetJustifyH("LEFT"); num:SetWordWrap(false)
  num:SetFont(BODY_BOLD_FONT, 22); num:SetTextColor(1, 1, 1)
  local sub = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  sub:SetPoint("BOTTOMLEFT", 12, 10); sub:SetPoint("BOTTOMRIGHT", -12, 10); sub:SetWordWrap(false)
  w.Update = function(_, data)
    num:SetText(getter(data) or "?")
    sub:SetText(subGetter(data) or "")
  end
  return w
end

function Widgets.gold(SL, parent)
  return StatWidget(SL, parent, "Gold on hand",
    function(d) return SL:FormatMoney(d.gold) end,
    function(d) return string.format("|cffababab%d character%s|r", #d.perCharacter, #d.perCharacter == 1 and "" or "s") end)
end

function Widgets.itemStacks(SL, parent)
  return StatWidget(SL, parent, "Item stacks",
    function(d) return tostring(d.totalStacks) end,
    function(d)
      local unpricedNote = d.unpricedUnique > 0 and string.format(" · |cffff9d33%d unpriced|r", d.unpricedUnique) or ""
      return string.format("|cffababab%d unique|r%s", d.uniqueItems, unpricedNote)
    end)
end

function Widgets.trend(SL, parent)
  local w = WidgetShell(parent, "7-day trend")
  local num = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  num:SetPoint("TOPLEFT", 12, -28); num:SetPoint("TOPRIGHT", -8, -28); num:SetFont(BODY_BOLD_FONT, 22); num:SetWordWrap(false)
  local sub = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  sub:SetPoint("BOTTOMLEFT", 12, 10); sub:SetPoint("BOTTOMRIGHT", -12, 10); sub:SetWordWrap(false)
  w.Update = function(_, data)
    local history = data.history or {}
    local cutoff = time() - 7 * 86400
    local base
    for _, s in ipairs(history) do if s.t >= cutoff then base = base or s end end
    if not base or base.net == 0 then
      num:SetText("—"); num:SetTextColor(0.7, 0.7, 0.7)
      sub:SetText("|cffababab need more history|r")
      return
    end
    local latest = history[#history]
    local pct = (latest.net - base.net) / base.net * 100
    if pct >= 0 then num:SetText(string.format("▲ %.1f%%", pct)); num:SetTextColor(0.30, 0.86, 0.50)
    else num:SetText(string.format("▼ %.1f%%", -pct)); num:SetTextColor(0.99, 0.62, 0.20) end
    sub:SetText(string.format("|cffababab from %s a week ago|r", SL:FormatMoney(base.net)))
  end
  return w
end

function Widgets.topItems(SL, parent)
  local w = WidgetShell(parent, "Top items by value")
  w.rows = {}
  for i = 1, 8 do
    local row = CreateFrame("Frame", nil, w)
    row:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 20); row:SetPoint("TOPRIGHT", -12, -28 - (i - 1) * 20); row:SetHeight(18)
    row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(16, 16); row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    row.name = Text(row, "LEFT", 11)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 4); row.name:SetPoint("RIGHT", -90, 4)
    row.name:SetHeight(12); row.name:SetWordWrap(false)
    row.value = Text(row, "RIGHT", 11, true, COLORS_SUMMARY.yellow)
    row.value:SetPoint("RIGHT", 0, 4)
    row.bar = row:CreateTexture(nil, "ARTWORK"); row.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bar:SetPoint("BOTTOMLEFT", 22, 0); row.bar:SetHeight(2)
    row.barBg = row:CreateTexture(nil, "BACKGROUND"); row.barBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.barBg:SetColorTexture(0.2, 0.22, 0.22, 1)
    row.barBg:SetPoint("BOTTOMLEFT", 22, 0); row.barBg:SetPoint("BOTTOMRIGHT", 0, 0); row.barBg:SetHeight(2)
    w.rows[i] = row; row:Hide()
  end
  w.Update = function(_, data)
    local maxValue = (data.topItems[1] and data.topItems[1].value) or 1
    for i, row in ipairs(w.rows) do
      local item = data.topItems[i]
      if item then
        row:Show()
        local icon = item.link and (select(10, GetItemInfo(item.link)) or 134400) or 134400
        row.icon:SetTexture(icon)
        row.name:SetText(string.format("%s |cff9c9c9c×%d|r", item.link or item.name, item.count))
        row.value:SetText(SL:FormatMoney(item.value))
        row.bar:SetColorTexture(1, 0.85, 0.22, 0.9)
        local pct = maxValue > 0 and (item.value / maxValue) or 0
        row.bar:SetWidth(math.max(1, (row:GetWidth() - 22) * pct))
      else row:Hide() end
    end
  end
  return w
end

function Widgets.valueByLocation(SL, parent)
  local w = WidgetShell(parent, "Value by location")
  local bar = CreateFrame("Frame", nil, w); bar:SetPoint("TOPLEFT", 12, -34); bar:SetPoint("TOPRIGHT", -12, -34); bar:SetHeight(22)
  w.segments = {}
  for i = 1, #LOC_ORDER do
    local seg = bar:CreateTexture(nil, "ARTWORK"); seg:SetTexture("Interface\\Buttons\\WHITE8X8")
    w.segments[i] = seg
  end
  local legend = CreateFrame("Frame", nil, w)
  legend:SetPoint("TOPLEFT", 12, -66); legend:SetPoint("BOTTOMRIGHT", -12, 8)
  w.legendItems = {}
  for i, loc in ipairs(LOC_ORDER) do
    local col = math.floor((i - 1) / 3)
    local rowInLegend = (i - 1) % 3
    local item = CreateFrame("Frame", nil, legend)
    item:SetSize(180, 18)
    item:SetPoint("TOPLEFT", col * 190, -rowInLegend * 22)
    local sw = item:CreateTexture(nil, "ARTWORK"); sw:SetTexture("Interface\\Buttons\\WHITE8X8")
    sw:SetSize(10, 10); sw:SetPoint("LEFT", 0, 0)
    local c = LOC_COLORS[loc]; sw:SetColorTexture(c[1], c[2], c[3], 1)
    local label = Text(item, "LEFT", 11, false, COLORS_SUMMARY.dim)
    label:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    w.legendItems[loc] = { swatch = sw, label = label }
  end
  w.bar = bar
  w.Update = function(_, data)
    local total = 0
    for _, loc in ipairs(LOC_ORDER) do total = total + (data.perLocation[loc] or 0) end
    if total <= 0 then total = 1 end
    local x = 0
    for i, loc in ipairs(LOC_ORDER) do
      local value = data.perLocation[loc] or 0
      local pct = value / total
      local segW = math.max(0, pct * bar:GetWidth())
      local seg = w.segments[i]
      seg:ClearAllPoints(); seg:SetPoint("BOTTOMLEFT", x, 0); seg:SetSize(math.max(0.1, segW), 22)
      local c = LOC_COLORS[loc]; seg:SetColorTexture(c[1], c[2], c[3], 0.9)
      x = x + segW
      local li = w.legendItems[loc]
      if li then li.label:SetText(string.format("%s  |cffffffff%s|r", LOC_LABEL[loc], SL:FormatMoney(value))) end
    end
  end
  return w
end

function Widgets.perCharacter(SL, parent)
  local w = WidgetShell(parent, "Per character")
  local scroll = CreateFrame("ScrollFrame", nil, w, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -28); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local content = CreateFrame("Frame", nil, scroll); content:SetSize(1, 1); scroll:SetScrollChild(content)
  w.content = content; w.rows = {}
  w.Update = function(_, data)
    for _, row in ipairs(w.rows) do row:Hide() end
    local maxRows = #data.perCharacter
    local rowH = 20
    for i, pc in ipairs(data.perCharacter) do
      local row = w.rows[i]
      if not row then
        row = CreateFrame("Frame", nil, content)
        row.name = Text(row, "LEFT", 11, true); row.name:SetPoint("LEFT", 4, 0); row.name:SetPoint("RIGHT", row, "LEFT", 220, 0); row.name:SetHeight(14); row.name:SetWordWrap(false)
        row.gold = Text(row, "RIGHT", 11, false, COLORS_SUMMARY.dim); row.gold:SetPoint("LEFT", row.name, "RIGHT", 8, 0); row.gold:SetPoint("RIGHT", -120, 0); row.gold:SetHeight(14); row.gold:SetWordWrap(false)
        row.value = Text(row, "RIGHT", 11, true, COLORS_SUMMARY.yellow); row.value:SetPoint("RIGHT", -4, 0); row.value:SetWidth(112); row.value:SetHeight(14); row.value:SetWordWrap(false)
        w.rows[i] = row
      end
      row:SetHeight(rowH); row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH); row:SetPoint("TOPRIGHT", 0, -(i - 1) * rowH)
      row.name:SetText(string.format("|cffffffff%s|r  |cffffd839%s|r  |cff9c9c9c· %s|r", pc.name or "?", pc.realm or "?", (pc.class and pc.class:sub(1,1) .. pc.class:sub(2):lower()) or "?"))
      row.gold:SetText(SL:FormatMoney(pc.gold))
      row.value:SetText(SL:FormatMoney(pc.itemValue + pc.gold))
      row:Show()
    end
    content:SetHeight(math.max(1, maxRows * rowH + 8))
    content:SetWidth(scroll:GetWidth())
  end
  return w
end

function Widgets.staleSources(SL, parent)
  local w = WidgetShell(parent, "Stale sources")
  Backdrop(w, 1, { 0x1a/255, 0x14/255, 0x0a/255 }, { 0x66/255, 0x40/255, 0x14/255 })
  w.label:SetTextColor(0.99, 0.62, 0.20)
  local big = w:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  big:SetPoint("TOPLEFT", 12, -28); big:SetFont(BODY_BOLD_FONT, 24); big:SetTextColor(0.99, 0.62, 0.20)
  local list = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  list:SetPoint("TOPLEFT", 12, -60); list:SetPoint("TOPRIGHT", -12, -60); list:SetHeight(60); list:SetWordWrap(true); list:SetJustifyV("TOP")
  w.Update = function(_, data)
    local stale = SL:GetStaleSources()
    big:SetText(tostring(#stale))
    if #stale == 0 then
      big:SetTextColor(0.30, 0.86, 0.50)
      list:SetText("|cff30d97fEvery source is fresh.|r")
    else
      big:SetTextColor(0.99, 0.62, 0.20)
      local names = {}
      for i = 1, math.min(3, #stale) do
        local s = stale[i]
        if s.kind == "character" then names[#names + 1] = string.format("|cffffffff%s|r · %s", s.name or s.key, s.location)
        else names[#names + 1] = string.format("|cff8fb6f0<%s>|r tab %s", s.guildName or s.key, tostring(s.location)) end
      end
      local extra = #stale > 3 and string.format("\n|cff787878+ %d more|r", #stale - 3) or ""
      list:SetText(table.concat(names, "\n") .. extra .. "\n|cffababab/goblin coverage for details|r")
    end
  end
  return w
end

-- ============================================================================
-- Layout + lifecycle
-- ============================================================================

local LAYOUT_ACTIVE = {
  { kind = "netWorthHero",   x = 0,   y = 0,    w = 6, h = 96  },
  { kind = "gold",           x = 6,   y = 0,    w = 3, h = 96  },
  { kind = "itemStacks",     x = 9,   y = 0,    w = 3, h = 96  },
  { kind = "topItems",       x = 0,   y = 100,  w = 6, h = 196 },
  { kind = "valueByLocation",x = 6,   y = 100,  w = 6, h = 196 },
  { kind = "perCharacter",   x = 0,   y = 300,  w = 6, h = 220 },
  { kind = "trend",          x = 6,   y = 300,  w = 3, h = 100 },
  { kind = "staleSources",   x = 9,   y = 300,  w = 3, h = 220 },
}

function SL:CreateSummary()
  if self.summaryPanel or not self.frame then return end
  local panel = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetPoint("TOPLEFT", 10, -38); panel:SetPoint("BOTTOMRIGHT", -10, 43)
  panel:SetFrameLevel(self.frame:GetFrameLevel() + 5)
  Backdrop(panel, 1, COLORS_SUMMARY.primary, COLORS_SUMMARY.edge)
  panel:Hide()
  self.summaryPanel = panel
  self.summaryWidgets = {}
  panel:SetScript("OnSizeChanged", function() SL:LayoutSummary() end)
  self:LayoutSummary()
  return panel
end

function SL:LayoutSummary()
  if not self.summaryPanel then return end
  -- Rebuild widgets on first layout, then just reposition on resize.
  if #self.summaryWidgets == 0 then
    for _, def in ipairs(LAYOUT_ACTIVE) do
      local builder = Widgets[def.kind]
      if builder then
        local widget = builder(self, self.summaryPanel)
        widget.def = def
        self.summaryWidgets[#self.summaryWidgets + 1] = widget
      end
    end
  end
  local panelW = self.summaryPanel:GetWidth() - 16
  local colW = panelW / 12
  local gap = 4
  for _, widget in ipairs(self.summaryWidgets) do
    local d = widget.def
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT", 8 + d.x * colW, -8 - d.y)
    widget:SetSize(math.max(80, d.w * colW - gap), d.h)
  end
end

function SL:RefreshSummary()
  if not self.summaryPanel or not self.summaryPanel:IsShown() then return end
  local data = self:BuildSummaryData()
  self.summaryData = data
  for _, widget in ipairs(self.summaryWidgets) do
    if widget.Update then widget:Update(data) end
  end
end

function SL:ShowSummary()
  if not self.summaryPanel then self:CreateSummary() end
  self.uiMode = "summary"
  self:ApplyUIMode()
end

function SL:ShowInventory()
  self.uiMode = "inventory"
  self:ApplyUIMode()
end

function SL:ApplyUIMode()
  if not self.frame then return end
  local mode = self.uiMode or "inventory"
  local isSummary = mode == "summary"
  local isCoverage = mode == "coverage"
  local isInventory = mode == "inventory"
  if self.summaryPanel then self.summaryPanel:SetShown(isSummary) end
  if self.coveragePanel then self.coveragePanel:SetShown(isCoverage) end
  if self.search then self.search:SetShown(isInventory) end
  if self.priceEdit then self.priceEdit:SetShown(isInventory) end
  if self.headerFrame then self.headerFrame:SetShown(isInventory) end
  for _, row in ipairs(self.rows or {}) do row:SetShown(isInventory) end
  if self.scroll then self.scroll:SetShown(isInventory) end
  if self.summary then self.summary:SetShown(isInventory) end
  if self.sectionTabs then self.sectionTabs.updateHighlight() end
  if isSummary and self.RefreshSummary then self:RefreshSummary() end
  if isCoverage and self.RefreshCoverage then self:RefreshCoverage() end
end
