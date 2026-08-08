local _, SL = ...

-- Summary dashboard: single-pass aggregation of the ledger DB into per-widget
-- rollups, then a fixed grid of widgets rendered inside the main frame's
-- content area. v1 uses a static layout (drag/drop deferred). Data updates
-- ride on the same RefreshUI cycle that feeds the Inventory table.

local T = SL.THEME
local COLORS_SUMMARY = {
  primary    = T.bgDeep,
  primaryAlt = T.bgRow,
  frame      = T.chrome,
  edge       = T.edge,
  text       = T.text,
  dim        = T.dim,
  dimmer     = T.dimmer,
  yellow     = T.gold,
  green      = T.green,
  orange     = T.orange,
  guild      = T.blue,
  purple     = T.purple,
  subtle     = T.subtle,
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
  SL.RegisterTint(target, color, alpha)
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
    -- totalUnits counts individual items (200 cloth = 200). uniqueItems counts
    -- distinct item types. The old field was named "stacks" and meant neither.
    itemValue = 0, gold = 0, totalUnits = 0, uniqueItems = 0,
    soulboundUnits = 0, soulboundStacks = 0,
    perLocation = { bags = 0, bank = 0, equipped = 0, mail = 0, auctions = 0, guild = 0 },
    perCharacter = {},
    perCharacterMap = {},
    topItems = {},
    unpricedUnits = 0,
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
    local bound = item.boundCount or 0
    if not self.db.settings.includeSoulbound and bound > 0 then
      count = math.max(0, count - bound)
      data.soulboundUnits = data.soulboundUnits + bound
      data.soulboundStacks = data.soulboundStacks + 1
    end
    if count <= 0 then return end
    local unitPrice = self:GetPrice(itemString) or 0
    local value = count * unitPrice
    data.itemValue = data.itemValue + value
    data.totalUnits = data.totalUnits + count
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
    if unitPrice == 0 then data.unpricedUnits = data.unpricedUnits + count end
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
  -- Drives the "not shown: X (off)" vs "(empty)" caption. A character source
  -- counts as on if any included character has it on -- this widget is
  -- account-wide, the matrix is per character.
  data.locationEnabled = {}
  for _, location in ipairs(LOC_ORDER) do
    if location == "guild" then
      data.locationEnabled[location] = self.db.settings.categories.guild ~= false
    else
      local any = false
      for key in pairs(self.db.characters or {}) do
        if self:IsCharacterIncluded(key) and self:IsCharacterCategoryIncluded(key, location) then
          any = true
          break
        end
      end
      data.locationEnabled[location] = any
    end
  end
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
  big:SetPoint("TOPLEFT", 12, -26); big:SetJustifyH("LEFT"); big:SetWordWrap(false)
  big:SetFont(BODY_BOLD_FONT, 28)
  SetColor(function(...) big:SetTextColor(...) end, COLORS_SUMMARY.yellow)
  local delta = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  delta:SetPoint("LEFT", big, "RIGHT", 10, 1); delta:SetWordWrap(false)

  -- Split bar: items vs gold, with the legend on its own line underneath. The
  -- previous build drew a sparkline in this space and the breakdown caption
  -- landed on top of it -- yellow text on yellow bars, unreadable.
  local track = w:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("TOPLEFT", 12, -62); track:SetPoint("TOPRIGHT", -12, -62); track:SetHeight(6)
  track:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) track:SetVertexColor(...) end, COLORS_SUMMARY.edge)
  local itemsBar = w:CreateTexture(nil, "ARTWORK")
  itemsBar:SetPoint("TOPLEFT", 12, -62); itemsBar:SetHeight(6)
  itemsBar:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) itemsBar:SetVertexColor(...) end, COLORS_SUMMARY.yellow)
  local goldBar = w:CreateTexture(nil, "ARTWORK")
  goldBar:SetHeight(6); goldBar:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) goldBar:SetVertexColor(...) end, COLORS_SUMMARY.green)

  local breakdown = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  breakdown:SetPoint("TOPLEFT", 12, -74); breakdown:SetPoint("TOPRIGHT", -12, -74)
  breakdown:SetHeight(14); breakdown:SetWordWrap(false)

  w.big = big; w.delta = delta; w.breakdown = breakdown
  w.Update = function(_, data)
    big:SetText(SL:FormatMoney(data.netWorth))

    local trend, reason = SL.GetTrend and SL:GetTrend(7 * 86400, data.netWorth)
    if trend then
      local sign = trend.diff >= 0 and "|cff4dd280up|r " or "|cffff9d33down|r "
      delta:SetText(string.format("%s%s over %dd", sign, SL:FormatMoney(math.abs(trend.diff)), trend.days))
    else
      delta:SetText(string.format("|cff7a7f7f%s|r", reason or "no trend yet"))
    end

    local total = math.max(1, data.netWorth)
    local width = math.max(1, w:GetWidth() - 24)
    local itemsW = math.max(0, (data.itemValue / total) * width)
    itemsBar:SetWidth(math.max(0.1, itemsW))
    goldBar:ClearAllPoints()
    goldBar:SetPoint("TOPLEFT", 12 + itemsW, -62)
    goldBar:SetWidth(math.max(0.1, (data.gold / total) * width))

    breakdown:SetText(string.format("|cffffd839items %s|r  |cff4ee07fgold %s|r  |cff9c9c9c%s items, %d types|r",
      SL:FormatMoney(data.itemValue), SL:FormatMoney(data.gold),
      SL.CommaNumber(data.totalUnits), data.uniqueItems))
  end
  return w
end

local function StatWidget(SL, parent, label, getter, subGetter, tooltipFn)
  local w = WidgetShell(parent, label)
  local num = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  num:SetPoint("TOPLEFT", 12, -28); num:SetPoint("TOPRIGHT", -8, -28)
  num:SetJustifyH("LEFT"); num:SetWordWrap(false)
  num:SetFont(BODY_BOLD_FONT, 22); num:SetTextColor(1, 1, 1)
  local sub = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  sub:SetPoint("BOTTOMLEFT", 12, 10); sub:SetPoint("BOTTOMRIGHT", -12, 10); sub:SetWordWrap(false)
  w.Update = function(_, data)
    w.data = data
    num:SetText(getter(data) or "?")
    sub:SetText(subGetter(data) or "")
  end
  if tooltipFn then
    w:EnableMouse(true)
    w:SetScript("OnEnter", function(self) tooltipFn(self) end)
    w:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return w
end

function Widgets.gold(SL, parent)
  return StatWidget(SL, parent, "Gold on hand",
    function(d) return SL:FormatMoney(d.gold) end,
    function(d)
      local guildNote = SL.db.settings.includeGuildGold and " · incl. guild" or ""
      return string.format("|cffababab%d character%s|r%s", #d.perCharacter, #d.perCharacter == 1 and "" or "s", guildNote)
    end)
end

-- "Items held" is the count of individual items across every included source
-- (200 Netherweave = 200), not stacks and not slots. The subtitle gives the
-- number of distinct item types, which is the figure most people expect.
-- The "N with no price" note used to be a dead end -- it told you a count and
-- gave you no way to find out which item it meant. Hovering the tile now names
-- them and says where they are.
local function ItemsHeldTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("Items held")
  local data = owner.data
  if data then
    GameTooltip:AddDoubleLine("Individual items", SL.CommaNumber(data.totalUnits), 0.9, 0.9, 0.9, 1, 1, 1)
    GameTooltip:AddDoubleLine("Distinct types", tostring(data.uniqueItems), 0.9, 0.9, 0.9, 1, 1, 1)
  end
  local unpriced = SL.GetUnpricedItems and SL:GetUnpricedItems() or {}
  GameTooltip:AddLine(" ")
  if #unpriced == 0 then
    GameTooltip:AddLine("|cff4ee07fEverything counted has a price.|r")
  else
    GameTooltip:AddLine(string.format("|cffff9d33%d item type%s with no %s price|r",
      #unpriced, #unpriced == 1 and "" or "s", tostring(SL.db.settings.priceSource)))
    GameTooltip:AddLine("These contribute 0 to net worth.", 0.7, 0.75, 0.72, true)
    GameTooltip:AddLine(" ")
    for i, row in ipairs(unpriced) do
      if i > 10 then
        GameTooltip:AddLine(string.format("… and %d more", #unpriced - 10), 0.6, 0.7, 0.62)
        break
      end
      GameTooltip:AddDoubleLine(string.format("%s x%d", row.name or row.itemString, row.count),
        row.places[1] or "?", 1, 1, 1, 0.7, 0.75, 0.72)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffababab/goblin unpriced|r — full list with item links", 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end

function Widgets.itemStacks(SL, parent)
  return StatWidget(SL, parent, "Items held",
    function(d) return SL.CommaNumber(d.totalUnits) end,
    function(d)
      local unpricedNote = d.unpricedUnique > 0
        and string.format(" · |cffff9d33%d with no price|r", d.unpricedUnique) or ""
      return string.format("|cffababab%d different items|r%s", d.uniqueItems, unpricedNote)
    end,
    ItemsHeldTooltip)
end

local function TrendTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("7-day trend")
  GameTooltip:AddLine("Compares your net worth right now against the oldest snapshot in the last 7 days that was taken with exactly the same sources switched on.", 0.8, 0.85, 0.8, true)
  local trend = owner.trend
  if trend then
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Now", SL:FormatMoney(trend.net), 0.9, 0.9, 0.9, 1, 0.85, 0.22)
    GameTooltip:AddDoubleLine("Baseline", SL:FormatMoney(trend.baseline.net), 0.9, 0.9, 0.9, 1, 0.85, 0.22)
    GameTooltip:AddDoubleLine("Taken", date("%d %b %H:%M", trend.baseline.t), 0.9, 0.9, 0.9, 0.7, 0.75, 0.72)
    GameTooltip:AddDoubleLine("Change", string.format("%s%s", trend.diff >= 0 and "+" or "-", SL:FormatMoney(math.abs(trend.diff))),
      0.9, 0.9, 0.9, trend.diff >= 0 and 0.3 or 0.99, trend.diff >= 0 and 0.85 or 0.62, trend.diff >= 0 and 0.5 or 0.2)
  elseif owner.reason then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffff9d33" .. owner.reason .. "|r")
    if owner.reason == "sources changed" then
      GameTooltip:AddLine("Snapshots taken under a different source selection are never used as a baseline. A new one is recorded within the hour.", 0.7, 0.75, 0.72, true)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("|cffababab/goblin history why|r — full diagnostics", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function Widgets.trend(SL, parent)
  local w = WidgetShell(parent, "7-day trend")
  w:EnableMouse(true)
  local num = w:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  num:SetPoint("TOPLEFT", 12, -28); num:SetPoint("TOPRIGHT", -8, -28); num:SetFont(BODY_BOLD_FONT, 22); num:SetWordWrap(false)
  local sub = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  sub:SetPoint("BOTTOMLEFT", 12, 10); sub:SetPoint("BOTTOMRIGHT", -12, 10); sub:SetWordWrap(false)
  w:SetScript("OnEnter", TrendTooltip)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Sparkline of the last 7 days. Bars from a different source selection are
  -- greyed rather than hidden, so a step in the line is visibly explained
  -- instead of looking like money vanished.
  local plot = CreateFrame("Frame", nil, w)
  plot:SetPoint("TOPLEFT", 12, -56); plot:SetPoint("BOTTOMRIGHT", -12, 28)
  w.plot, w.bars = plot, {}

  local function DrawSparkline()
    local history = SL.db.history or {}
    local cutoff = time() - 7 * 86400
    local current = SL.GetConfigFingerprint and SL:GetConfigFingerprint() or nil
    local points = {}
    for _, snapshot in ipairs(history) do
      if snapshot.t >= cutoff then points[#points + 1] = snapshot end
    end
    -- Cap the bar count so a busy week doesn't produce sub-pixel slivers.
    local maxBars = math.max(8, math.floor(plot:GetWidth() / 3))
    if #points > maxBars then
      local step, reduced = math.ceil(#points / maxBars), {}
      for i = 1, #points, step do reduced[#reduced + 1] = points[i] end
      points = reduced
    end
    for _, bar in ipairs(w.bars) do bar:Hide() end
    local plotW, plotH = plot:GetWidth(), plot:GetHeight()
    if #points < 2 or plotW <= 1 or plotH <= 1 then return end
    local peak = 0
    for _, snapshot in ipairs(points) do if snapshot.net > peak then peak = snapshot.net end end
    if peak <= 0 then return end
    local spacing = plotW / #points
    for i, snapshot in ipairs(points) do
      local bar = w.bars[i]
      if not bar then
        bar = plot:CreateTexture(nil, "ARTWORK")
        bar:SetTexture("Interface\\Buttons\\WHITE8X8")
        w.bars[i] = bar
      end
      local comparable = (current ~= nil and snapshot.cfg == current)
      local c = comparable and COLORS_SUMMARY.yellow or COLORS_SUMMARY.dimmer
      bar:SetColorTexture(c[1], c[2], c[3], comparable and 0.85 or 0.5)
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", (i - 1) * spacing, 0)
      bar:SetSize(math.max(1, spacing - 1), math.max(1, (snapshot.net / peak) * plotH))
      bar:Show()
    end
  end

  w.Update = function(_, data)
    DrawSparkline()
    -- Measured against the live net worth, not the newest stored snapshot:
    -- snapshots are hourly, and the newest one's own fingerprint was never
    -- validated, so a source change could survive in the headline for an hour.
    local trend, reason = SL.GetTrend and SL:GetTrend(7 * 86400, data.netWorth)
    w.trend, w.reason = trend, reason
    if not trend then
      num:SetText("—")
      SetColor(function(...) num:SetTextColor(...) end, COLORS_SUMMARY.dimmer)
      sub:SetText(reason == "sources changed"
        and "|cffff9d33sources changed — new baseline pending|r"
        or "|cffababab need more history|r")
      return
    end
    if trend.pct >= 0 then
      num:SetText(string.format("up %.1f%%", trend.pct))
      SetColor(function(...) num:SetTextColor(...) end, COLORS_SUMMARY.green)
    else
      num:SetText(string.format("down %.1f%%", -trend.pct))
      SetColor(function(...) num:SetTextColor(...) end, COLORS_SUMMARY.orange)
    end
    sub:SetText(string.format("|cffababab vs %s · %dd ago|r",
      FormatShortMoney(trend.baseline.net), trend.days))
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
    -- Only draw the rows that actually fit in the current widget height. The
    -- fixed 8 rows used to spill out of the bottom edge when the window was
    -- short.
    local fits = math.max(1, math.floor((w:GetHeight() - 36) / 20))
    for i, row in ipairs(w.rows) do
      local item = i <= fits and data.topItems[i] or nil
      if item then
        row:Show()
        local icon = item.link and (select(10, GetItemInfo(item.link)) or 134400) or 134400
        row.icon:SetTexture(icon)
        row.name:SetText(string.format("%s |cff9c9c9c×%d|r", item.link or item.name, item.count))
        row.value:SetText(SL:FormatMoney(item.value))
        local accent = COLORS_SUMMARY.yellow
        row.bar:SetColorTexture(accent[1], accent[2], accent[3], 0.9)
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
  legend:SetPoint("TOPLEFT", 12, -64); legend:SetPoint("BOTTOMRIGHT", -12, 24)
  w.legendItems = {}
  for i = 1, #LOC_ORDER do
    local item = CreateFrame("Frame", nil, legend)
    item:SetSize(180, 18)
    local sw = item:CreateTexture(nil, "ARTWORK"); sw:SetTexture("Interface\\Buttons\\WHITE8X8")
    sw:SetSize(10, 10); sw:SetPoint("LEFT", 0, 0)
    local label = Text(item, "LEFT", 11, false, COLORS_SUMMARY.dim)
    label:SetPoint("LEFT", sw, "RIGHT", 6, 0); label:SetPoint("RIGHT", 0, 0)
    label:SetHeight(12); label:SetWordWrap(false)
    w.legendItems[i] = { frame = item, swatch = sw, label = label }
    item:Hide()
  end
  -- Anything switched off in Sources is named here rather than drawn as a
  -- zero-width segment with a 0c legend entry, which just looked like a bug.
  local excluded = Text(w, "LEFT", 10, false, COLORS_SUMMARY.dimmer)
  excluded:SetPoint("BOTTOMLEFT", 12, 8); excluded:SetPoint("BOTTOMRIGHT", -12, 8)
  excluded:SetHeight(12); excluded:SetWordWrap(false)
  w.bar = bar
  w.Update = function(_, data)
    local visible, total = {}, 0
    for _, loc in ipairs(LOC_ORDER) do
      local value = data.perLocation[loc] or 0
      if value > 0 then
        visible[#visible + 1] = { loc = loc, value = value }
        total = total + value
      end
    end
    if total <= 0 then total = 1 end

    local x = 0
    for i, seg in ipairs(w.segments) do
      local entry = visible[i]
      if entry then
        local segW = math.max(0.1, (entry.value / total) * bar:GetWidth())
        seg:ClearAllPoints(); seg:SetPoint("BOTTOMLEFT", x, 0); seg:SetSize(segW, 22)
        local c = LOC_COLORS[entry.loc]; seg:SetColorTexture(c[1], c[2], c[3], 0.9)
        seg:Show(); x = x + segW
      else
        seg:Hide()
      end
    end

    for i, li in ipairs(w.legendItems) do
      local entry = visible[i]
      if entry then
        local col = math.floor((i - 1) / 3)
        local rowInLegend = (i - 1) % 3
        li.frame:ClearAllPoints()
        li.frame:SetPoint("TOPLEFT", col * 190, -rowInLegend * 20)
        local c = LOC_COLORS[entry.loc]
        li.swatch:SetColorTexture(c[1], c[2], c[3], 1)
        li.label:SetText(string.format("%s  |cffffffff%s|r  |cff6d7f72%d%%|r",
          LOC_LABEL[entry.loc], SL:FormatMoney(entry.value), math.floor(entry.value / total * 100 + 0.5)))
        li.frame:Show()
      else
        li.frame:Hide()
      end
    end

    local off = {}
    for _, loc in ipairs(LOC_ORDER) do
      if (data.perLocation[loc] or 0) <= 0 then
        off[#off + 1] = string.format("%s %s", LOC_LABEL[loc],
          data.locationEnabled[loc] == false and "(off)" or "(empty)")
      end
    end
    excluded:SetText(#off > 0 and ("not shown: " .. table.concat(off, " · ")) or "")
  end
  return w
end

-- Guild-bank contents are deliberately not attributed to any character: a
-- guild bank belongs to the guild, and splitting it across whoever happens to
-- be a member would double-count as soon as two alts share one. It shows up in
-- Value by location instead.
function Widgets.perCharacter(SL, parent)
  local w = WidgetShell(parent, "Per character")
  local note = Text(w, "RIGHT", 10, false, COLORS_SUMMARY.dimmer)
  note:SetPoint("TOPRIGHT", -12, -10); note:SetHeight(12); note:SetWordWrap(false)
  note:SetText("bags · bank · equipped · mail · AH · gold — no guild bank")
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
      -- Re-applied every refresh so rows created before a theme change still
      -- pick the new palette up (they aren't in the tint registry).
      SetColor(function(...) row.gold:SetTextColor(...) end, COLORS_SUMMARY.dim)
      SetColor(function(...) row.value:SetTextColor(...) end, COLORS_SUMMARY.yellow)
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
  local w = WidgetShell(parent, "Needs a visit")
  Backdrop(w, 1, COLORS_SUMMARY.primary, COLORS_SUMMARY.edge)
  SetColor(function(...) w.label:SetTextColor(...) end, COLORS_SUMMARY.orange)

  local big = w:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  big:SetPoint("TOPLEFT", 12, -26); big:SetFont(BODY_BOLD_FONT, 26)
  local caption = Text(w, "LEFT", 11, false, COLORS_SUMMARY.dim)
  caption:SetPoint("LEFT", big, "RIGHT", 8, -2); caption:SetWordWrap(false)

  local divider = w:CreateTexture(nil, "ARTWORK")
  divider:SetPoint("TOPLEFT", 12, -60); divider:SetPoint("TOPRIGHT", -12, -60); divider:SetHeight(1)
  divider:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) divider:SetVertexColor(...) end, COLORS_SUMMARY.edge)

  -- Fixed row pool. Each row is a dot, an owner, and the source that is out of
  -- date, so the widget reads as a to-do list rather than a wall of text.
  local ROWS = 7
  w.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, w)
    row:SetPoint("TOPLEFT", 12, -68 - (i - 1) * 17); row:SetPoint("TOPRIGHT", -12, -68 - (i - 1) * 17)
    row:SetHeight(15)
    row.dot = row:CreateTexture(nil, "ARTWORK")
    row.dot:SetSize(5, 5); row.dot:SetPoint("LEFT", 1, 0); row.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.who = Text(row, "LEFT", 11, true, COLORS_SUMMARY.text)
    row.who:SetPoint("LEFT", row.dot, "RIGHT", 6, 0); row.who:SetPoint("RIGHT", -78, 0)
    row.who:SetHeight(13); row.who:SetWordWrap(false)
    row.what = Text(row, "RIGHT", 11, false, COLORS_SUMMARY.subtle)
    row.what:SetPoint("RIGHT", 0, 0); row.what:SetWidth(74); row.what:SetHeight(13); row.what:SetWordWrap(false)
    row:Hide()
    w.rows[i] = row
  end

  local more = Text(w, "LEFT", 10, false, COLORS_SUMMARY.dimmer)
  more:SetPoint("BOTTOMLEFT", 12, 8); more:SetPoint("BOTTOMRIGHT", -12, 8)
  more:SetHeight(12); more:SetWordWrap(false)

  w.Update = function(_, _)
    local stale = SL:GetStaleSources()
    local fits = math.max(1, math.min(ROWS, math.floor((w:GetHeight() - 92) / 17)))
    big:SetText(tostring(#stale))
    if #stale == 0 then
      SetColor(function(...) big:SetTextColor(...) end, COLORS_SUMMARY.green)
      caption:SetText("|cff4ee07feverything is current|r")
      for _, row in ipairs(w.rows) do row:Hide() end
      more:SetText("")
      return
    end
    SetColor(function(...) big:SetTextColor(...) end, COLORS_SUMMARY.orange)
    local owners = {}
    for _, entry in ipairs(stale) do owners[entry.name or entry.guildName or entry.key] = true end
    local ownerCount = 0
    for _ in pairs(owners) do ownerCount = ownerCount + 1 end
    caption:SetText(string.format("|cffababab source%s across %d place%s|r",
      #stale == 1 and "" or "s", ownerCount, ownerCount == 1 and "" or "s"))

    for i, row in ipairs(w.rows) do
      local entry = i <= fits and stale[i] or nil
      if entry then
        local isGuild = entry.kind ~= "character"
        local c = entry.status == "never" and COLORS_SUMMARY.orange or COLORS_SUMMARY.yellow
        row.dot:SetColorTexture(c[1], c[2], c[3], 1)
        if isGuild then
          row.who:SetText(string.format("|cff8fb6f0<%s>|r", entry.guildName or entry.key))
          row.what:SetText(string.format("tab %s · %s", tostring(entry.location), entry.label or entry.status))
        else
          row.who:SetText(entry.name or entry.key)
          row.what:SetText(string.format("%s · %s", entry.location, entry.label or entry.status))
        end
        row:Show()
      else
        row:Hide()
      end
    end
    more:SetText(#stale > fits
      and string.format("+ %d more — Coverage tab has the full list", #stale - fits)
      or "open each mailbox, bank and guild bank to refresh")
  end
  return w
end

-- ============================================================================
-- Layout + lifecycle
-- ============================================================================

-- Layout is a stack of rows. Widths are fractions of a 12-column grid; heights
-- come from `minH` plus a share of whatever vertical space is left over,
-- weighted by `flex`. Nothing is positioned at a fixed pixel offset from the
-- top any more -- that was why the bottom row hung outside the frame as soon as
-- the window was shorter than the 536px the old grid silently assumed.
--
-- When the panel is too short even for the minimums, the whole stack scrolls
-- instead of overflowing.
local LAYOUT_ROWS = {
  { minH = 92,  flex = 0,   cells = {
      { kind = "netWorthHero",    w = 6 },
      { kind = "gold",            w = 3 },
      { kind = "itemStacks",      w = 3 },
    } },
  { minH = 180, flex = 1,   cells = {
      { kind = "topItems",        w = 6 },
      { kind = "valueByLocation", w = 6 },
    } },
  { minH = 180, flex = 1.1, cells = {
      { kind = "perCharacter",    w = 6 },
      { kind = "trend",           w = 3 },
      { kind = "staleSources",    w = 3 },
    } },
}

local PANEL_PAD = 8
local ROW_GAP = 6
local CELL_GAP = 6

local function MinimumStackHeight()
  local total = PANEL_PAD * 2
  for index, row in ipairs(LAYOUT_ROWS) do
    total = total + row.minH
    if index < #LAYOUT_ROWS then total = total + ROW_GAP end
  end
  return total
end

function SL:CreateSummary()
  if self.summaryPanel or not self.frame then return end
  local panel = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetPoint("TOPLEFT", 10, -38); panel:SetPoint("BOTTOMRIGHT", -10, 43)
  panel:SetFrameLevel(self.frame:GetFrameLevel() + 5)
  if panel.SetClipsChildren then pcall(panel.SetClipsChildren, panel, true) end
  Backdrop(panel, 1, COLORS_SUMMARY.primary, COLORS_SUMMARY.edge)
  panel:Hide()
  self.summaryPanel = panel
  self.summaryWidgets = {}

  -- Plain ScrollFrame rather than UIPanelScrollFrameTemplate: the template
  -- permanently reserves ~28px on the right for its scrollbar even when the
  -- content fits. Here the slim bar is drawn over the content and only when
  -- there is something to scroll.
  local scroll = CreateFrame("ScrollFrame", nil, panel)
  scroll:SetPoint("TOPLEFT", 1, -1); scroll:SetPoint("BOTTOMRIGHT", -1, 1)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  panel.scroll, panel.content = scroll, content

  local bar = CreateFrame("Slider", nil, panel)
  bar:SetFrameLevel(panel:GetFrameLevel() + 20)
  bar:SetOrientation("VERTICAL"); bar:SetWidth(10)
  bar:SetPoint("TOPRIGHT", -2, -4); bar:SetPoint("BOTTOMRIGHT", -2, 4)
  bar:SetMinMaxValues(0, 0); bar:SetValue(0); bar:SetValueStep(1); bar:SetObeyStepOnDrag(true)
  local thumb = bar:CreateTexture(nil, "ARTWORK"); thumb:SetSize(4, 40)
  SetColor(function(...) thumb:SetColorTexture(...) end, COLORS_SUMMARY.dim, 0.8)
  bar:SetThumbTexture(thumb)
  bar:SetScript("OnValueChanged", function(s, value) scroll:SetVerticalScroll(value) end)
  bar:Hide()
  panel.bar = bar

  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta)
    if not bar:IsShown() then return end
    local _, maximum = bar:GetMinMaxValues()
    bar:SetValue(math.max(0, math.min(maximum, bar:GetValue() - delta * 30)))
  end)

  panel:SetScript("OnSizeChanged", function() SL:LayoutSummary() end)
  self:LayoutSummary()
  return panel
end

function SL:LayoutSummary()
  local panel = self.summaryPanel
  if not panel then return end
  local content = panel.content
  -- Build widgets on first layout, then only reposition on resize.
  if #self.summaryWidgets == 0 then
    for _, row in ipairs(LAYOUT_ROWS) do
      for _, cell in ipairs(row.cells) do
        local builder = Widgets[cell.kind]
        if builder then
          local widget = builder(self, content)
          widget.cell = cell
          self.summaryWidgets[#self.summaryWidgets + 1] = widget
        end
      end
    end
  end

  local viewportW = math.max(120, panel:GetWidth() - 2)
  local viewportH = math.max(80, panel:GetHeight() - 2)
  local minimum = MinimumStackHeight()
  local needsScroll = viewportH < minimum
  local stackH = needsScroll and minimum or viewportH
  local usableW = viewportW - PANEL_PAD * 2 - (needsScroll and 12 or 0)

  -- Distribute the leftover height across the flexible rows.
  local spare = math.max(0, stackH - minimum)
  local totalFlex = 0
  for _, row in ipairs(LAYOUT_ROWS) do totalFlex = totalFlex + (row.flex or 0) end

  content:SetSize(viewportW, stackH)

  local colW = usableW / 12
  local index, y = 1, -PANEL_PAD
  for rowIndex, row in ipairs(LAYOUT_ROWS) do
    local rowH = row.minH
    if totalFlex > 0 and (row.flex or 0) > 0 then
      rowH = rowH + spare * (row.flex / totalFlex)
    end
    local x = PANEL_PAD
    for _, cell in ipairs(row.cells) do
      local widget = self.summaryWidgets[index]
      if widget then
        local cellW = cell.w * colW
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", content, "TOPLEFT", x, y)
        widget:SetSize(math.max(60, cellW - CELL_GAP), math.max(40, rowH))
        x = x + cellW
      end
      index = index + 1
    end
    y = y - rowH - (rowIndex < #LAYOUT_ROWS and ROW_GAP or 0)
  end

  local maximum = math.max(0, stackH - viewportH)
  panel.bar:SetMinMaxValues(0, maximum)
  if maximum <= 0 then
    panel.bar:SetValue(0)
    panel.scroll:SetVerticalScroll(0)
    panel.bar:Hide()
  else
    if panel.bar:GetValue() > maximum then panel.bar:SetValue(maximum) end
    panel.bar:Show()
  end

  if self.summaryData then self:RefreshSummary() end
end

-- Widget Update functions re-apply their own colours on every refresh, so they
-- must not feed the theme tint registry -- otherwise it would gain a few dozen
-- entries per refresh forever.
function SL:RefreshSummary()
  SL.WithoutTintCollection(function() self:RefreshSummaryImpl() end)
end

function SL:RefreshSummaryImpl()
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
  local isMail = mode == "mail"
  local isInventory = mode == "inventory"
  if self.summaryPanel then self.summaryPanel:SetShown(isSummary) end
  if self.coveragePanel then self.coveragePanel:SetShown(isCoverage) end
  if self.mailPanel then self.mailPanel:SetShown(isMail) end
  if self.search then self.search:SetShown(isInventory) end
  if self.priceEdit then self.priceEdit:SetShown(isInventory) end
  if self.headerFrame then self.headerFrame:SetShown(isInventory) end
  for _, row in ipairs(self.rows or {}) do row:SetShown(isInventory) end
  if self.scroll then self.scroll:SetShown(isInventory) end
  if self.summary then self.summary:SetShown(isInventory) end
  if self.sectionTabs then self.sectionTabs.updateHighlight() end
  if isSummary and self.RefreshSummary then self:RefreshSummary() end
  if isCoverage and self.RefreshCoverage then self:RefreshCoverage() end
  if isMail and self.RefreshMail then self:RefreshMail() end
end
