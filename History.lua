local _, SL = ...

-- Net-worth history: hourly-capped snapshots + a small bar chart.
-- Snapshots are written when the UI is open and the ledger recomputes, but
-- throttled so /reload / rapid inbox events don't spam the log. Cap at 720
-- entries (~30 days hourly) so SavedVariables stays tiny.

local SNAPSHOT_INTERVAL = 3600
local SNAPSHOT_CAP = 720
local CHART_LOOKBACK = 7 * 86400
local CHART_BUCKET_MAX = 168

local BAR_COLOR = { 1.00, 0.85, 0.22, 0.90 }
local GOLD_COLOR = { 1.00, 0.85, 0.22, 0.35 }
local GRID_COLOR = { 0.28, 0.32, 0.34, 1.00 }
local LABEL_COLOR = { 0.72, 0.75, 0.72, 1.00 }

function SL:MaybeSnapshot(itemValue, gold)
  self.db.history = self.db.history or {}
  local history = self.db.history
  local now = time()
  local last = history[#history]
  if last and (now - last.t) < SNAPSHOT_INTERVAL then return end
  local total = (itemValue or 0) + (gold or 0)
  if total <= 0 and not last then return end
  history[#history + 1] = { t = now, net = total, items = itemValue or 0, gold = gold or 0 }
  while #history > SNAPSHOT_CAP do table.remove(history, 1) end
end

local function FormatMoneyShort(copper)
  copper = tonumber(copper) or 0
  local gold = copper / 10000
  if gold >= 1000000 then return string.format("%.1fMg", gold / 1000000)
  elseif gold >= 1000 then return string.format("%.1fkg", gold / 1000)
  elseif gold >= 1 then return string.format("%.0fg", gold)
  else return string.format("%dc", copper) end
end

local function FormatWhen(seconds)
  if not seconds or seconds <= 0 then return "" end
  local days = math.floor(seconds / 86400)
  if days >= 1 then return string.format("%dd ago", days) end
  local hours = math.floor(seconds / 3600)
  if hours >= 1 then return string.format("%dh ago", hours) end
  return string.format("%dm ago", math.max(1, math.floor(seconds / 60)))
end

function SL:CreateHistoryPanel()
  if not self.frame then return end
  local panel = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetPoint("TOPLEFT", 10, -68); panel:SetPoint("BOTTOMRIGHT", -4, 43)
  panel:SetFrameLevel(self.frame:GetFrameLevel() + 5); panel:Hide()
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    panel:SetBackdropColor(0x14 / 255, 0x16 / 255, 0x16 / 255, 1)
    panel:SetBackdropBorderColor(0x42 / 255, 0x4c / 255, 0x4f / 255, 1)
  end
  self.historyPanel = panel

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Net worth — last 7 days")
  title:SetTextColor(1, 1, 1, 1)
  panel.title = title

  local subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 12, -30)
  subtitle:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1)
  panel.subtitle = subtitle

  local minLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  minLabel:SetPoint("TOPRIGHT", -12, -10); minLabel:SetJustifyH("RIGHT")
  minLabel:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1)
  panel.minLabel = minLabel

  local maxLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  maxLabel:SetPoint("TOPRIGHT", -12, -30); maxLabel:SetJustifyH("RIGHT")
  maxLabel:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1)
  panel.maxLabel = maxLabel

  local plot = CreateFrame("Frame", nil, panel)
  plot:SetPoint("TOPLEFT", 40, -60); plot:SetPoint("BOTTOMRIGHT", -20, 40)
  panel.plot = plot
  panel.bars = {}
  panel.goldBars = {}
  panel.gridLines = {}

  local axisY = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  axisY:SetPoint("TOPLEFT", 10, -60); axisY:SetJustifyH("LEFT")
  axisY:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1)
  panel.axisYMax = axisY

  local axisY0 = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  axisY0:SetPoint("BOTTOMLEFT", 10, 42); axisY0:SetJustifyH("LEFT")
  axisY0:SetText("0"); axisY0:SetTextColor(LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1)

  local hover = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hover:SetPoint("BOTTOMRIGHT", -12, 22); hover:SetJustifyH("RIGHT")
  hover:SetTextColor(1, 0.85, 0.22, 1)
  panel.hover = hover

  return panel
end

function SL:RefreshHistoryPanel()
  local panel = self.historyPanel
  if not panel or not panel:IsShown() then return end
  local history = self.db.history or {}
  local now = time()
  local cutoff = now - CHART_LOOKBACK
  local snapshots = {}
  for _, snap in ipairs(history) do
    if snap.t >= cutoff then snapshots[#snapshots + 1] = snap end
  end
  local n = #snapshots
  if n > CHART_BUCKET_MAX then
    local step = math.ceil(n / CHART_BUCKET_MAX)
    local reduced = {}
    for i = 1, n, step do reduced[#reduced + 1] = snapshots[i] end
    snapshots = reduced; n = #snapshots
  end

  local yMax, yMin = 0, math.huge
  local totalNow, totalOldest, oldest, newest
  for _, s in ipairs(snapshots) do
    if s.net > yMax then yMax = s.net end
    if s.net < yMin then yMin = s.net end
    if not oldest or s.t < oldest.t then oldest = s end
    if not newest or s.t > newest.t then newest = s end
  end
  if yMax <= 0 then yMax = 1 end
  totalNow = newest and newest.net or 0
  totalOldest = oldest and oldest.net or 0
  local delta = totalNow - totalOldest
  local sign = delta >= 0 and "|cff30d97fup|r" or "|cffff5555down|r"
  panel.subtitle:SetText(string.format("Now %s · %s %s over %s (from %s)",
    SL:FormatMoney(totalNow), sign, SL:FormatMoney(math.abs(delta)),
    (oldest and FormatWhen(now - oldest.t)) or "?",
    (oldest and SL:FormatMoney(totalOldest)) or "?"))
  panel.axisYMax:SetText(FormatMoneyShort(yMax))
  panel.minLabel:SetText("Low: " .. SL:FormatMoney(yMin == math.huge and 0 or yMin))
  panel.maxLabel:SetText("High: " .. SL:FormatMoney(yMax))

  for _, bar in ipairs(panel.bars) do bar:Hide() end
  for _, bar in ipairs(panel.goldBars) do bar:Hide() end
  for _, line in ipairs(panel.gridLines) do line:Hide() end

  local plot = panel.plot
  local w, h = plot:GetWidth(), plot:GetHeight()
  if w <= 0 or h <= 0 then return end

  for step = 1, 3 do
    local line = panel.gridLines[step]
    if not line then
      line = plot:CreateTexture(nil, "BACKGROUND")
      line:SetTexture("Interface\\Buttons\\WHITE8X8")
      panel.gridLines[step] = line
    end
    line:SetColorTexture(GRID_COLOR[1], GRID_COLOR[2], GRID_COLOR[3], 0.6)
    line:SetHeight(1); line:SetWidth(w)
    line:ClearAllPoints(); line:SetPoint("BOTTOMLEFT", 0, (step / 4) * h)
    line:Show()
  end

  if n == 0 then panel.subtitle:SetText("No snapshots yet — open the ledger periodically to accrue history."); return end
  local barSpacing = math.max(2, w / n)
  local barWidth = math.max(1, barSpacing - 1)
  for i, snap in ipairs(snapshots) do
    local goldBar = panel.goldBars[i]
    if not goldBar then
      goldBar = plot:CreateTexture(nil, "ARTWORK")
      goldBar:SetTexture("Interface\\Buttons\\WHITE8X8")
      panel.goldBars[i] = goldBar
    end
    local bar = panel.bars[i]
    if not bar then
      bar = plot:CreateTexture(nil, "ARTWORK")
      bar:SetTexture("Interface\\Buttons\\WHITE8X8")
      panel.bars[i] = bar
    end
    local x = (i - 1) * barSpacing
    local netFrac = snap.net / yMax
    local goldFrac = (snap.gold or 0) / yMax
    goldBar:SetColorTexture(GOLD_COLOR[1], GOLD_COLOR[2], GOLD_COLOR[3], GOLD_COLOR[4])
    goldBar:ClearAllPoints()
    goldBar:SetPoint("BOTTOMLEFT", x, 0)
    goldBar:SetSize(barWidth, math.max(1, goldFrac * h))
    goldBar:Show()
    bar:SetColorTexture(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3], BAR_COLOR[4])
    bar:ClearAllPoints()
    bar:SetPoint("BOTTOMLEFT", x, math.max(1, goldFrac * h))
    bar:SetSize(barWidth, math.max(1, (netFrac - goldFrac) * h))
    bar:Show()
  end
end

function SL:ToggleHistory()
  if not self.historyPanel then self:CreateHistoryPanel() end
  local panel = self.historyPanel
  if not panel then return end
  panel:SetShown(not panel:IsShown())
  if panel:IsShown() then self:RefreshHistoryPanel() end
end
