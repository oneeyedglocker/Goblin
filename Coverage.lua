local _, SL = ...

-- Coverage tab: visual version of /goblin coverage. Each character and each
-- guild is a compact row showing per-source status pills (item count,
-- unpriced count, last-scan age, disabled flag). Warnings section at bottom.

local COL_PRIMARY   = { 0x14/255, 0x16/255, 0x16/255 }
local COL_ALT       = { 0x1c/255, 0x20/255, 0x20/255 }
local COL_EDGE      = { 0x2a/255, 0x2f/255, 0x31/255 }
local COL_TEXT      = { 1, 1, 1 }
local COL_DIM       = { 0x93/255, 0x99/255, 0x9a/255 }
local COL_SUBTLE    = { 0.58, 0.63, 0.61 }
local COL_YELLOW    = { 1.00, 0.85, 0.22 }
local COL_GREEN     = { 0.30, 0.86, 0.50 }
local COL_ORANGE    = { 0.99, 0.62, 0.20 }
local COL_RED       = { 0.99, 0.34, 0.34 }
local COL_GUILD     = { 0.55, 0.72, 0.92 }
local COL_DIMMER    = { 0.42, 0.44, 0.44 }

local BODY_FONT      = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Regular.ttf"
local BODY_BOLD_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Bold.ttf"

local function SetColor(target, color, alpha)
  target(color[1], color[2], color[3], alpha or 1)
end

local function Backdrop(frame, alpha, background, border)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  SetColor(function(...) frame:SetBackdropColor(...) end, background or COL_PRIMARY, alpha or 1)
  SetColor(function(...) frame:SetBackdropBorderColor(...) end, border or COL_EDGE)
end

local function Text(parent, align, size, bold, color)
  local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t:SetJustifyH(align or "LEFT")
  t:SetFont(bold and BODY_BOLD_FONT or BODY_FONT, size or 12)
  local c = color or COL_TEXT
  t:SetTextColor(c[1], c[2], c[3])
  return t
end

local SOURCE_ORDER = { "gold", "bags", "bank", "equipped", "mail", "auctions" }
local SOURCE_LABEL = { gold = "Gold", bags = "Bags", bank = "Bank", equipped = "Equip", mail = "Mail", auctions = "AH" }

-- Pill widget: one per source in a character row. Colored dot + label + counts.
-- Label is anchored on BOTH sides so text truncates at the pill edge instead
-- of bleeding into the next pill.
local function BuildSourcePill(parent, source, info, disabled, labelOverride)
  local pill = CreateFrame("Frame", nil, parent)
  pill:SetHeight(20)
  local dot = pill:CreateTexture(nil, "ARTWORK"); dot:SetSize(6, 6); dot:SetTexture("Interface\\Buttons\\WHITE8X8")
  dot:SetPoint("LEFT", 2, 0)
  local statusColor = COL_DIMMER
  if info and info.itemCount and info.itemCount > 0 then
    if info.status == "fresh" then statusColor = COL_GREEN
    elseif info.status == "stale" then statusColor = COL_ORANGE
    else statusColor = COL_RED end
  elseif info and info.lastScanned then
    statusColor = info.status == "stale" and COL_ORANGE or COL_GREEN
  else
    statusColor = COL_RED
  end
  dot:SetColorTexture(statusColor[1], statusColor[2], statusColor[3], 1)

  local label = Text(pill, "LEFT", 11, true, disabled and COL_DIMMER or COL_TEXT)
  label:SetPoint("LEFT", dot, "RIGHT", 6, 0); label:SetPoint("RIGHT", -4, 0)
  label:SetJustifyH("LEFT"); label:SetWordWrap(false); label:SetHeight(14)
  local ageStr = info and info.lastScanned and SL:FormatAge(time() - info.lastScanned) or "never"
  local sourceLabel = labelOverride or SOURCE_LABEL[source] or source
  local countStr
  if not info or not info.lastScanned then
    countStr = "never"
  elseif not info.itemCount or info.itemCount == 0 then
    countStr = "empty · " .. ageStr
  elseif info.unpricedCount and info.unpricedCount > 0 then
    countStr = string.format("%di · |cffff9d33%du|r · %s", info.itemCount, info.unpricedCount, ageStr)
  else
    countStr = string.format("%di · %s", info.itemCount, ageStr)
  end
  local disabledSuffix = disabled and " |cff787878off|r" or ""
  label:SetText(string.format("%s  %s%s", sourceLabel, countStr, disabledSuffix))
  pill.label = label
  return pill
end

local function BuildCharacterRow(parent, char, sourceMap, rowWidth)
  local row = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Backdrop(row, 1, COL_ALT, COL_EDGE)
  row:SetHeight(78)

  local nameStr = Text(row, "LEFT", 12, true, COL_TEXT)
  nameStr:SetPoint("TOPLEFT", 10, -6); nameStr:SetPoint("TOPRIGHT", -180, -6); nameStr:SetHeight(14); nameStr:SetWordWrap(false)
  local realmSuffix = char.realm and (" |cffffd839— " .. char.realm .. "|r") or ""
  local disabledTag = char.enabled == false and " |cff787878DISABLED|r" or ""
  nameStr:SetText(string.format("|cffffffff%s|r%s%s", char.name or char.key, realmSuffix, disabledTag))

  local goldInfo = char.gold and SL:GetLocationFreshness(char.key, "gold") or nil
  local goldStr = Text(row, "RIGHT", 11, false, COL_DIM)
  goldStr:SetPoint("TOPRIGHT", -10, -6); goldStr:SetWidth(170); goldStr:SetHeight(14); goldStr:SetWordWrap(false)
  goldStr:SetText(string.format("gold %s · %s", SL:FormatMoney(char.gold and char.gold.amount or 0), goldInfo and goldInfo.stamp and SL:FormatAge(time() - goldInfo.stamp) or "never"))

  -- 6 pills laid out as 2 rows × 3 columns. Each pill is a real fraction of
  -- the row width with a small gap; label truncates at pill boundary.
  local usable = (rowWidth or 720) - 20
  local pillGap = 4
  local pillW = math.floor((usable - pillGap * 2) / 3)
  local order = { "gold", "bags", "bank", "equipped", "mail", "auctions" }
  for i, s in ipairs(order) do
    local col = (i - 1) % 3
    local ro = math.floor((i - 1) / 3)
    local x = 10 + col * (pillW + pillGap)
    local y = -28 - ro * 22
    local info, disabled
    if s == "gold" then
      info = { itemCount = char.gold and char.gold.amount or 0, lastScanned = char.gold and char.gold.updatedAt, unpricedCount = 0, status = goldInfo and goldInfo.status or "never" }
      disabled = not (char.gold and char.gold.enabled)
    else
      info = sourceMap[s]
      disabled = char.enabled == false or (info and not info.enabled)
    end
    local pill = BuildSourcePill(row, s, info, disabled)
    pill:SetPoint("TOPLEFT", x, y); pill:SetWidth(pillW)
  end
  return row
end

local function BuildGuildRow(parent, guild, rowWidth)
  local row = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  Backdrop(row, 1, COL_ALT, COL_EDGE)
  local tabCount = guild.tabs and #guild.tabs or 0
  local pillRows = tabCount > 0 and math.ceil(tabCount / 3) or 0
  row:SetHeight(28 + math.max(1, pillRows) * 22)

  local nameStr = Text(row, "LEFT", 12, true, COL_TEXT)
  nameStr:SetPoint("TOPLEFT", 10, -6); nameStr:SetPoint("TOPRIGHT", -180, -6); nameStr:SetHeight(14); nameStr:SetWordWrap(false)
  local disabledTag = guild.enabled == false and " |cff787878DISABLED|r" or ""
  nameStr:SetText(string.format("|cff8fb6f0<%s>|r%s", guild.name or guild.key, disabledTag))

  local goldStr = Text(row, "RIGHT", 11, false, COL_DIM)
  goldStr:SetPoint("TOPRIGHT", -10, -6); goldStr:SetWidth(170); goldStr:SetHeight(14); goldStr:SetWordWrap(false)
  local goldAge = guild.gold and guild.gold.updatedAt and SL:FormatAge(time() - guild.gold.updatedAt) or "never"
  goldStr:SetText(string.format("guild gold %s · %s", SL:FormatMoney(guild.gold and guild.gold.amount or 0), goldAge))

  local usable = (rowWidth or 720) - 20
  local pillGap = 4
  local pillW = math.floor((usable - pillGap * 2) / 3)
  for i, tab in ipairs(guild.tabs or {}) do
    local col = (i - 1) % 3
    local ro  = math.floor((i - 1) / 3)
    local x = 10 + col * (pillW + pillGap)
    local y = -28 - ro * 22
    local info = { itemCount = tab.itemCount, unpricedCount = tab.unpricedCount, lastScanned = tab.lastScanned, status = tab.lastScanned and "fresh" or "never" }
    local tabLabel = string.format("t%d %s", tab.index, tab.name or ("Tab " .. tab.index))
    local pill = BuildSourcePill(row, "guild", info, guild.enabled == false or not tab.enabled, tabLabel)
    pill:SetPoint("TOPLEFT", x, y); pill:SetWidth(pillW)
  end
  return row
end

function SL:CreateCoverageTab()
  if self.coveragePanel or not self.frame then return end
  local panel = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetPoint("TOPLEFT", 10, -38); panel:SetPoint("BOTTOMRIGHT", -10, 43)
  panel:SetFrameLevel(self.frame:GetFrameLevel() + 5)
  Backdrop(panel, 1, COL_PRIMARY, COL_EDGE)
  panel:Hide()
  self.coveragePanel = panel
  self.coverageRows = {}

  local summary = Text(panel, "LEFT", 12, true, COL_TEXT)
  summary:SetPoint("TOPLEFT", 12, -10); summary:SetHeight(14); summary:SetWordWrap(false)
  panel.summary = summary

  -- Warnings-only toggle: hides rows with all-fresh sources so users can
  -- focus on characters/tabs that actually need attention.
  local filterBtn = CreateFrame("CheckButton", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
  filterBtn:SetSize(14, 14); filterBtn:SetPoint("LEFT", summary, "RIGHT", 20, 0)
  Backdrop(filterBtn, 1, COL_ALT, COL_EDGE)
  filterBtn.mark = filterBtn:CreateTexture(nil, "ARTWORK"); filterBtn.mark:SetPoint("TOPLEFT", 2, -2); filterBtn.mark:SetPoint("BOTTOMRIGHT", -2, 2)
  filterBtn.mark:SetColorTexture(COL_YELLOW[1], COL_YELLOW[2], COL_YELLOW[3], 1)
  filterBtn:SetCheckedTexture(filterBtn.mark)
  local filterLabel = Text(panel, "LEFT", 11, false, COL_DIM); filterLabel:SetPoint("LEFT", filterBtn, "RIGHT", 6, 0); filterLabel:SetText("Warnings only")
  filterBtn:SetChecked(false)
  filterBtn:SetScript("OnClick", function(b) panel.warningsOnly = b:GetChecked() and true or false; SL:RefreshCoverage() end)
  panel.filterBtn = filterBtn

  local hint = Text(panel, "RIGHT", 11, false, COL_SUBTLE)
  hint:SetPoint("TOPRIGHT", -12, -10); hint:SetHeight(14); hint:SetWordWrap(false)
  hint:SetText("green fresh · orange stale · red never · off disabled")
  panel.hint = hint

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -36); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(panel:GetWidth() - 40, 1); scroll:SetScrollChild(content)
  panel.scroll = scroll; panel.content = content

  panel:SetScript("OnSizeChanged", function()
    content:SetWidth(panel:GetWidth() - 40)
    SL:RefreshCoverage()
  end)
  return panel
end

function SL:RefreshCoverage()
  local panel = self.coveragePanel
  if not panel or not panel:IsShown() then return end
  local report = self:GetCoverageReport()
  panel.summary:SetText(string.format("|cffffd839%d|r priced · |cffff9d33%d|r unpriced · |cffff5555%d|r warning%s",
    report.totals.itemsPriced, report.totals.itemsUnpriced, #report.warnings, #report.warnings == 1 and "" or "s"))

  for _, row in ipairs(self.coverageRows) do row:Hide(); row:SetParent(nil) end
  self.coverageRows = {}

  local content = panel.content
  local y = -4

  local charHead = Text(content, "LEFT", 11, true, COL_YELLOW)
  charHead:SetPoint("TOPLEFT", 4, y); charHead:SetText(string.format("CHARACTERS  |cff9c9c9c%d|r", #report.characters))
  self.coverageRows[#self.coverageRows + 1] = charHead
  y = y - 20

  local rowWidth = content:GetWidth() - 8
  local warningsOnly = panel.warningsOnly and true or false
  for _, char in ipairs(report.characters) do
    local sourceMap = {}
    local hasWarning = char.enabled == false
    for _, src in ipairs(char.sources) do
      sourceMap[src.name] = src
      if src.itemCount > 0 and not src.enabled then hasWarning = true end
      if src.enabled and src.lastScanned then
        local age = time() - src.lastScanned
        local threshold = self.STALE_SECONDS[src.name]
        if threshold and age >= threshold then hasWarning = true end
      end
      if src.unpricedCount and src.unpricedCount > 0 then hasWarning = true end
    end
    if not warningsOnly or hasWarning then
      local row = BuildCharacterRow(content, char, sourceMap, rowWidth)
      row:SetPoint("TOPLEFT", 4, y); row:SetPoint("TOPRIGHT", -4, y)
      y = y - row:GetHeight() - 4
      self.coverageRows[#self.coverageRows + 1] = row
    end
  end

  y = y - 8
  local guildHead = Text(content, "LEFT", 11, true, COL_YELLOW)
  guildHead:SetPoint("TOPLEFT", 4, y); guildHead:SetText(string.format("GUILD BANKS  |cff9c9c9c%d|r", #report.guilds))
  self.coverageRows[#self.coverageRows + 1] = guildHead
  y = y - 20

  for _, guild in ipairs(report.guilds) do
    local hasWarning = guild.enabled == false
    for _, tab in ipairs(guild.tabs or {}) do
      if tab.itemCount and tab.itemCount > 0 and not tab.enabled then hasWarning = true end
      if tab.unpricedCount and tab.unpricedCount > 0 then hasWarning = true end
    end
    if not warningsOnly or hasWarning then
      local row = BuildGuildRow(content, guild, rowWidth)
      row:SetPoint("TOPLEFT", 4, y); row:SetPoint("TOPRIGHT", -4, y)
      y = y - row:GetHeight() - 4
      self.coverageRows[#self.coverageRows + 1] = row
    end
  end

  if #report.warnings > 0 then
    y = y - 12
    local warnHead = Text(content, "LEFT", 11, true, COL_ORANGE)
    warnHead:SetPoint("TOPLEFT", 4, y); warnHead:SetText(string.format("WARNINGS  |cff9c9c9c%d|r", #report.warnings))
    self.coverageRows[#self.coverageRows + 1] = warnHead
    y = y - 20
    for _, w in ipairs(report.warnings) do
      local warn = Text(content, "LEFT", 11, false, COL_SUBTLE)
      warn:SetPoint("TOPLEFT", 12, y); warn:SetPoint("TOPRIGHT", -12, y)
      warn:SetJustifyH("LEFT"); warn:SetWordWrap(true)
      warn:SetText("· " .. w)
      self.coverageRows[#self.coverageRows + 1] = warn
      y = y - 16
    end
  end

  content:SetHeight(math.max(1, -y + 8))
end

function SL:ShowCoverage()
  if not self.coveragePanel then self:CreateCoverageTab() end
  self.uiMode = "coverage"
  self:ApplyUIMode()
end
