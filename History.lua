local _, SL = ...

-- Net-worth history: hourly-capped snapshots + a small bar chart.
-- Snapshots are written when the UI is open and the ledger recomputes, but
-- throttled so /reload / rapid inbox events don't spam the log. Cap at 720
-- entries (~30 days hourly) so SavedVariables stays tiny.

local SNAPSHOT_INTERVAL = 3600
local SNAPSHOT_CAP = 720
local CHART_LOOKBACK = 7 * 86400
local CHART_BUCKET_MAX = 168

-- Aliases, not copies: SL.THEME's tables are rewritten in place when the theme
-- changes, so holding the table itself means the chart follows the palette.
local T = SL.THEME
local BAR_COLOR   = T.green
local GOLD_COLOR  = T.gold
local GRID_COLOR  = T.edge
local LABEL_COLOR = T.dim
local BAR_ALPHA, GOLD_ALPHA = 0.90, 0.45

function SL:MaybeSnapshot(itemValue, gold)
  self.db.history = self.db.history or {}
  local history = self.db.history
  local now = time()
  local last = history[#history]
  if last and (now - last.t) < SNAPSHOT_INTERVAL then return end
  -- Don't record while the Sources panel is open: the user is mid-edit and
  -- every checkbox click would otherwise stamp a half-configured total.
  if self.options and self.options:IsShown() then return end
  -- Don't record before TSM can price anything, or the trend line picks up a
  -- phantom crash every time the addon loads ahead of its dependency.
  if self.IsPricingReady and not self:IsPricingReady() then return end
  local total = (itemValue or 0) + (gold or 0)
  if total <= 0 and not last then return end
  -- A snapshot with no fingerprint can never be compared fairly, so don't
  -- write one at all rather than leaving a landmine in the trend line.
  local cfg = self.GetConfigFingerprint and self:GetConfigFingerprint() or nil
  if cfg == nil then return end
  history[#history + 1] = {
    t = now, net = total, items = itemValue or 0, gold = gold or 0, cfg = cfg,
  }
  while #history > SNAPSHOT_CAP do table.remove(history, 1) end
end

-- Oldest snapshot inside the window that was taken under *exactly* the current
-- source selection. Returns nil plus a reason when there is nothing fair to
-- compare against, so callers can say so instead of reporting a bogus swing.
--
-- Snapshots with no fingerprint at all (written by builds from before
-- GetConfigFingerprint existed) are deliberately NOT comparable. Accepting
-- them was the reason a trend could still read "down 27%" off a total that
-- included a guild bank the user had since switched off.
function SL:GetComparableBaseline(windowSeconds)
  local history = self.db.history or {}
  if #history < 2 then return nil, "need more history" end
  local current = self.GetConfigFingerprint and self:GetConfigFingerprint() or nil
  if current == nil then return nil, "need more history" end
  local cutoff = time() - (windowSeconds or CHART_LOOKBACK)
  local latest = history[#history]
  local baseline, sawMismatch, sawLegacy
  for _, snapshot in ipairs(history) do
    if snapshot.t >= cutoff and snapshot ~= latest then
      if snapshot.cfg == current then
        baseline = baseline or snapshot
      elseif snapshot.cfg == nil then
        sawLegacy = true
      else
        sawMismatch = true
      end
    end
  end
  if not baseline then
    if sawMismatch or sawLegacy then return nil, "sources changed" end
    return nil, "need more history"
  end
  if baseline.net <= 0 then return nil, "need more history" end
  return baseline, nil
end

-- The trend, expressed against a net worth the caller computed *now* rather
-- than against the newest stored snapshot. Snapshots are hourly, so comparing
-- snapshot-to-snapshot meant the headline number could lag reality by an hour
-- and, worse, the newest snapshot's own fingerprint was never checked.
function SL:GetTrend(windowSeconds, currentNet)
  local baseline, reason = self:GetComparableBaseline(windowSeconds)
  if not baseline then return nil, reason end
  local now = time()
  local diff = currentNet - baseline.net
  return {
    baseline = baseline,
    net = currentNet,
    diff = diff,
    pct = diff / baseline.net * 100,
    seconds = now - baseline.t,
    days = math.max(1, math.floor((now - baseline.t) / 86400)),
  }
end

-- Drop every snapshot that can't be compared against the current source
-- selection. Cheaper than a full reset: whatever was recorded under today's
-- configuration survives, so the trend keeps whatever history is still valid.
function SL:PruneHistory()
  local history = self.db.history or {}
  local current = self.GetConfigFingerprint and self:GetConfigFingerprint() or nil
  if current == nil then
    print("|cffffd839Goblin:|r can't fingerprint the current sources yet — try again once TSM has loaded.")
    return
  end
  local kept, dropped = {}, 0
  for _, snapshot in ipairs(history) do
    if snapshot.cfg == current then kept[#kept + 1] = snapshot else dropped = dropped + 1 end
  end
  self.db.history = kept
  print(string.format("|cffffd839Goblin:|r dropped %d snapshot%s taken under a different source selection, kept %d.",
    dropped, dropped == 1 and "" or "s", #kept))
  if self.RefreshUI then self:RefreshUI() end
end

-- Says out loud what the trend widget is doing, including why it might be
-- refusing to show a number.
function SL:ExplainTrend()
  local history = self.db.history or {}
  local current = self.GetConfigFingerprint and self:GetConfigFingerprint() or nil
  local cutoff = time() - CHART_LOOKBACK
  local inWindow, matching, legacy, mismatched = 0, 0, 0, 0
  for _, snapshot in ipairs(history) do
    if snapshot.t >= cutoff then
      inWindow = inWindow + 1
      if snapshot.cfg == nil then legacy = legacy + 1
      elseif snapshot.cfg == current then matching = matching + 1
      else mismatched = mismatched + 1 end
    end
  end
  print("|cffffd839Goblin trend diagnostics|r")
  print(string.format("  source fingerprint now: |cffffffff%s|r", tostring(current)))
  print(string.format("  snapshots: %d total, %d in the last 7 days", #history, inWindow))
  print(string.format("  of those: |cff30d97f%d comparable|r · |cffff9d33%d from a different source selection|r · |cff9c9c9c%d with no fingerprint (pre-0.9 builds)|r",
    matching, mismatched, legacy))
  local _, itemValue, gold, grandValue = self:BuildLedger("")
  local net = (grandValue or itemValue or 0) + (gold or 0)
  local trend, reason = self:GetTrend(CHART_LOOKBACK, net)
  if trend then
    print(string.format("  comparing |cffffffff%s|r now against |cffffffff%s|r from %s (%d day%s ago) → %s%.1f%%|r",
      self:FormatMoney(net), self:FormatMoney(trend.baseline.net),
      date("%Y-%m-%d %H:%M", trend.baseline.t), trend.days, trend.days == 1 and "" or "s",
      trend.pct >= 0 and "|cff30d97f+" or "|cffff9d33", trend.pct))
  else
    print(string.format("  no trend shown: |cffff9d33%s|r", tostring(reason)))
  end
  if mismatched > 0 or legacy > 0 then
    print("  |cffababab/goblin history prune drops the incomparable ones and keeps the rest.|r")
  end
end

function SL:ResetHistory()
  self.db.history = {}
  print("|cffffd839Goblin:|r net-worth history cleared. A fresh baseline is recorded on the next refresh.")
  if self.RefreshUI then self:RefreshUI() end
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
    panel:SetBackdropColor(T.bgDeep[1], T.bgDeep[2], T.bgDeep[3], 1)
    panel:SetBackdropBorderColor(T.chrome[1], T.chrome[2], T.chrome[3], 1)
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

  -- Bars whose fingerprint doesn't match the current source selection are
  -- still drawn (they happened) but greyed out, and the headline delta only
  -- ever spans comparable snapshots. Otherwise switching a guild bank off
  -- leaves a permanent cliff in the chart with no explanation.
  local current = self.GetConfigFingerprint and self:GetConfigFingerprint() or nil
  local yMax, yMin = 0, math.huge
  local oldest, newest, incomparable = nil, nil, 0
  for _, s in ipairs(snapshots) do
    if s.net > yMax then yMax = s.net end
    if s.net < yMin then yMin = s.net end
    s.comparable = (current ~= nil and s.cfg == current)
    if s.comparable then
      if not oldest or s.t < oldest.t then oldest = s end
      if not newest or s.t > newest.t then newest = s end
    else
      incomparable = incomparable + 1
    end
  end
  if yMax <= 0 then yMax = 1 end
  local totalNow = newest and newest.net or 0
  local totalOldest = oldest and oldest.net or 0
  local note = incomparable > 0
    and string.format("   |cffff9d33%d snapshot%s from a different source selection (greyed)|r",
      incomparable, incomparable == 1 and "" or "s") or ""
  if oldest and newest and oldest ~= newest then
    local delta = totalNow - totalOldest
    local sign = delta >= 0 and "|cff30d97fup|r" or "|cffff5555down|r"
    panel.subtitle:SetText(string.format("Now %s · %s %s over %s (from %s)%s",
      SL:FormatMoney(totalNow), sign, SL:FormatMoney(math.abs(delta)),
      FormatWhen(now - oldest.t), SL:FormatMoney(totalOldest), note))
  else
    panel.subtitle:SetText("Not enough history under the current source selection yet." .. note)
  end
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
    if snap.comparable then
      goldBar:SetColorTexture(GOLD_COLOR[1], GOLD_COLOR[2], GOLD_COLOR[3], GOLD_ALPHA)
    else
      goldBar:SetColorTexture(0.42, 0.44, 0.43, 0.30)
    end
    goldBar:ClearAllPoints()
    goldBar:SetPoint("BOTTOMLEFT", x, 0)
    goldBar:SetSize(barWidth, math.max(1, goldFrac * h))
    goldBar:Show()
    if snap.comparable then
      bar:SetColorTexture(BAR_COLOR[1], BAR_COLOR[2], BAR_COLOR[3], BAR_ALPHA)
    else
      bar:SetColorTexture(0.42, 0.44, 0.43, 0.45)
    end
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
