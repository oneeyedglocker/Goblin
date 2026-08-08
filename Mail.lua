local _, SL = ...

-- Mail tab.
--
-- Using the mailbox as bulk storage is normal goblin practice, but the game
-- gives you no account-wide view of what is sitting where or how long it has.
-- This tab reconstructs one from two sources:
--
--   1. Inbox snapshots (Scanner:SnapshotInbox) -- authoritative. Every message
--      an alt had the last time its mailbox was opened, with the game's own
--      daysLeft value captured next to the scan timestamp. The countdown runs
--      in real time whether or not you are logged in, so remaining time is
--      projected forward from the snapshot rather than re-read.
--
--   2. The transit ledger (Ledger.lua) -- shipments hooked at SendMail that no
--      inbox scan has confirmed yet. Shown separately and clearly marked,
--      because they are inferred rather than observed.
--
-- Two deadlines matter and they are not the same deadline. Player-to-player
-- mail returns to the sender after MAIL_RETURN_DAYS -- the items are not gone,
-- they have moved to a different inbox and reset their clock. Only after
-- MAIL_GRACE_DAYS more are they destroyed. Auction-house mail and mail that
-- has already bounced once have no return leg: their single countdown runs
-- straight to deletion.

local T = SL.THEME
local DAY = 86400

local COL_BG      = T.bgDeep
local COL_PANEL   = T.bgPanel
local COL_ROW     = T.bgRow
local COL_ROW_ALT = T.bgRowAlt
local COL_EDGE    = T.edge
local COL_TEXT    = T.text
local COL_DIM     = T.dim
local COL_SUBTLE  = T.subtle
local COL_DIMMER  = T.dimmer
local COL_GOLD    = T.gold
local COL_GREEN   = T.green
local COL_ORANGE  = T.orange
local COL_RED     = T.red
local COL_BLUE    = T.blue

local BODY_FONT      = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Regular.ttf"
local BODY_BOLD_FONT = "Interface\\AddOns\\TradeSkillMaster\\Media\\Montserrat-Bold.ttf"

local ROW_HEIGHT = 48

local function SetColor(target, color, alpha)
  target(color[1], color[2], color[3], alpha or 1)
  SL.RegisterTint(target, color, alpha)
end

local function Backdrop(frame, alpha, background, border)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  SetColor(function(...) frame:SetBackdropColor(...) end, background or COL_BG, alpha or 1)
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

local function ToHex(color)
  return string.format("%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

-- Countdowns are shown at day resolution above a day, hour resolution below,
-- because "0d" on something about to vanish is not a useful thing to read.
local function FormatDuration(days)
  if not days then return "—" end
  if days <= 0 then return "due" end
  if days >= 2 then return string.format("%dd", math.floor(days)) end
  local hours = days * 24
  if hours >= 1 then return string.format("%dh", math.floor(hours)) end
  return string.format("%dm", math.max(1, math.floor(hours * 60)))
end

local function UrgencyColor(days)
  if not days then return COL_DIMMER end
  if days <= 1 then return COL_RED end
  if days <= 3 then return COL_ORANGE end
  if days <= SL.MAIL_URGENT_DAYS then return COL_GOLD end
  return COL_GREEN
end

--------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------

local function ValueItems(self, items)
  local value, stacks, units, unpriced = 0, 0, 0, 0
  local priced = {}
  for itemString, entry in pairs(items or {}) do
    local count = entry.count or 0
    local unit = self:GetPrice(itemString) or 0
    if unit <= 0 then unpriced = unpriced + 1 end
    value = value + unit * count
    stacks = stacks + 1
    units = units + count
    priced[#priced + 1] = {
      itemString = itemString, itemID = entry.itemID, link = entry.link,
      name = entry.name or (entry.link and GetItemInfo(entry.link)) or itemString,
      count = count, unit = unit, value = unit * count,
    }
  end
  table.sort(priced, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.name or "") < (b.name or "")
  end)
  return priced, value, stacks, units, unpriced
end

-- Turn one stored message into a pair of live deadlines.
local function ProjectMessage(self, message, scannedAt, holderName, ownerName)
  local elapsedDays = (time() - (scannedAt or time())) / DAY
  local remaining = (message.daysLeft or 0) - elapsedDays

  local row = {
    sender = message.sender or "?",
    subject = message.subject or "",
    kind = message.kind or "player",
    wasRead = message.wasRead,
    wasReturned = message.wasReturned,
    money = message.money or 0,
    cod = message.cod or 0,
    holder = holderName,
    origin = message.sender or "?",
    observed = true,
    stale = false,
  }

  -- Mail that had not landed yet at scan time.
  if message.pending then
    row.arrivingIn = math.max(0, -remaining)
    remaining = self.MAIL_RETURN_DAYS
  end

  if row.kind == "player" then
    if remaining > 0 then
      row.daysToReturn = remaining
      row.daysToDeletion = remaining + self.MAIL_GRACE_DAYS
      row.totalLifetime = self.MAIL_RETURN_DAYS + self.MAIL_GRACE_DAYS
    else
      -- The return window elapsed since the last scan: the parcel has bounced
      -- back to whoever sent it and restarted its clock there.
      row.bounced = true
      row.holder = row.sender
      row.origin = ownerName or holderName
      row.daysToReturn = nil
      row.daysToDeletion = math.max(0, remaining + self.MAIL_GRACE_DAYS)
      row.totalLifetime = self.MAIL_GRACE_DAYS
    end
  else
    row.daysToReturn = nil
    row.daysToDeletion = math.max(0, remaining)
    row.totalLifetime = self.MAIL_RETURN_DAYS
  end

  row.deadline = row.daysToReturn or row.daysToDeletion
  row.priced, row.value, row.stacks, row.units, row.unpriced = ValueItems(self, message.items)
  return row
end

-- Shipments the SendMail hook recorded but no inbox scan has confirmed.
local function ProjectTransit(self, record)
  local ageDays = (time() - (record.sentAt or time())) / DAY
  local row = {
    sender = record.senderName or "?",
    subject = record.subject or "",
    kind = "player",
    money = record.money or 0,
    cod = 0,
    origin = record.senderName or "?",
    observed = false,
    returned = record.returned,
  }
  if ageDays < self.MAIL_RETURN_DAYS then
    row.holder = record.recipientName or "?"
    row.daysToReturn = self.MAIL_RETURN_DAYS - ageDays
    row.daysToDeletion = (self.MAIL_RETURN_DAYS + self.MAIL_GRACE_DAYS) - ageDays
    row.totalLifetime = self.MAIL_RETURN_DAYS + self.MAIL_GRACE_DAYS
  else
    row.bounced = true
    row.holder = record.senderName or "?"
    row.origin = record.recipientName or "?"
    row.daysToDeletion = math.max(0, (self.MAIL_RETURN_DAYS + self.MAIL_GRACE_DAYS) - ageDays)
    row.totalLifetime = self.MAIL_GRACE_DAYS
  end
  row.deadline = row.daysToReturn or row.daysToDeletion
  row.priced, row.value, row.stacks, row.units, row.unpriced = ValueItems(self, record.items)
  return row
end

function SL:BuildMailReport()
  local report = {
    inboxes = {},
    totals = { messages = 0, stacks = 0, units = 0, value = 0, money = 0, urgent = 0, unconfirmed = 0 },
  }

  for key, character in pairs(self.db.characters or {}) do
    local mailbox = character.mailbox
    if mailbox and mailbox.messages then
      local age = time() - (mailbox.scannedAt or 0)
      local threshold = self.STALE_SECONDS.mail or (7 * DAY)
      local inbox = {
        key = key,
        name = character.name or key,
        realm = character.realm,
        scannedAt = mailbox.scannedAt,
        age = age,
        stale = age >= threshold,
        capped = mailbox.capped,
        rows = {},
        value = 0, money = 0, stacks = 0, units = 0, urgent = 0,
      }
      for _, message in ipairs(mailbox.messages) do
        local row = ProjectMessage(self, message, mailbox.scannedAt, inbox.name, inbox.name)
        row.stale = inbox.stale
        row.inboxKey = key
        inbox.rows[#inbox.rows + 1] = row
        inbox.value = inbox.value + row.value
        inbox.money = inbox.money + row.money
        inbox.stacks = inbox.stacks + row.stacks
        inbox.units = inbox.units + row.units
        if (row.deadline or 999) <= self.MAIL_URGENT_DAYS then inbox.urgent = inbox.urgent + 1 end
      end
      table.sort(inbox.rows, function(a, b) return (a.deadline or 999) < (b.deadline or 999) end)
      if #inbox.rows > 0 then
        inbox.soonest = inbox.rows[1].deadline
        report.inboxes[#report.inboxes + 1] = inbox
        report.totals.messages = report.totals.messages + #inbox.rows
        report.totals.stacks = report.totals.stacks + inbox.stacks
        report.totals.units = report.totals.units + inbox.units
        report.totals.value = report.totals.value + inbox.value
        report.totals.money = report.totals.money + inbox.money
        report.totals.urgent = report.totals.urgent + inbox.urgent
      end
    end
  end

  table.sort(report.inboxes, function(a, b) return (a.soonest or 999) < (b.soonest or 999) end)

  -- Unconfirmed shipments get their own pseudo-inbox pinned to the bottom.
  local transitRows = {}
  for _, record in pairs(self.db.mailTransit or {}) do
    if record.status == "pending" then
      transitRows[#transitRows + 1] = ProjectTransit(self, record)
    end
  end
  if #transitRows > 0 then
    table.sort(transitRows, function(a, b) return (a.deadline or 999) < (b.deadline or 999) end)
    local inbox = {
      key = "__transit", name = "In transit", transit = true, rows = transitRows,
      value = 0, money = 0, stacks = 0, units = 0, urgent = 0,
    }
    for _, row in ipairs(transitRows) do
      inbox.value = inbox.value + row.value
      inbox.money = inbox.money + row.money
      inbox.stacks = inbox.stacks + row.stacks
      inbox.units = inbox.units + row.units
      if (row.deadline or 999) <= self.MAIL_URGENT_DAYS then inbox.urgent = inbox.urgent + 1 end
    end
    report.inboxes[#report.inboxes + 1] = inbox
    report.totals.unconfirmed = #transitRows
    report.totals.messages = report.totals.messages + #transitRows
    report.totals.stacks = report.totals.stacks + inbox.stacks
    report.totals.units = report.totals.units + inbox.units
    report.totals.value = report.totals.value + inbox.value
    report.totals.money = report.totals.money + inbox.money
    report.totals.urgent = report.totals.urgent + inbox.urgent
  end

  return report
end

-- Cheap counters for the minimap tooltip; avoids pricing every attachment.
function SL:GetMailUrgency()
  local urgent, soonest = 0, nil
  for _, character in pairs(self.db.characters or {}) do
    local mailbox = character.mailbox
    if mailbox and mailbox.messages then
      local elapsed = (time() - (mailbox.scannedAt or time())) / DAY
      for _, message in ipairs(mailbox.messages) do
        local remaining = (message.daysLeft or 0) - elapsed
        local deadline
        if message.kind == "player" then
          deadline = remaining > 0 and remaining or math.max(0, remaining + self.MAIL_GRACE_DAYS)
        else
          deadline = math.max(0, remaining)
        end
        if deadline <= self.MAIL_URGENT_DAYS then urgent = urgent + 1 end
        if not soonest or deadline < soonest then soonest = deadline end
      end
    end
  end
  return urgent, soonest
end

--------------------------------------------------------------------------
-- Row widget
--------------------------------------------------------------------------

local function MessageTooltip(row)
  local data = row.data
  if not data then return end
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(data.subject ~= "" and data.subject or "(no subject)", 1, 1, 1)
  GameTooltip:AddDoubleLine("Sitting in", data.holder or "?", 0.6, 0.7, 0.62, 1, 0.85, 0.22)
  GameTooltip:AddDoubleLine("From", data.origin or "?", 0.6, 0.7, 0.62, 0.9, 0.9, 0.9)
  if data.arrivingIn then
    GameTooltip:AddDoubleLine("Arrives in", FormatDuration(data.arrivingIn), 0.6, 0.7, 0.62, 1, 0.85, 0.22)
  end
  if data.daysToReturn then
    local c = UrgencyColor(data.daysToReturn)
    GameTooltip:AddDoubleLine("Returns to sender in", FormatDuration(data.daysToReturn), 0.6, 0.7, 0.62, c[1], c[2], c[3])
  end
  local dc = UrgencyColor(data.daysToDeletion)
  GameTooltip:AddDoubleLine("Deleted forever in", FormatDuration(data.daysToDeletion), 0.6, 0.7, 0.62, dc[1], dc[2], dc[3])
  if data.bounced then
    GameTooltip:AddLine("Already bounced back to the sender.", 0.99, 0.62, 0.2, true)
  end
  if not data.observed then
    GameTooltip:AddLine("Sent by Goblin's hook but not yet seen in an inbox — estimated.", 0.99, 0.62, 0.2, true)
  elseif data.stale then
    GameTooltip:AddLine("Projected from an old scan. Open this mailbox to confirm.", 0.99, 0.62, 0.2, true)
  end
  if #data.priced > 0 then
    GameTooltip:AddLine(" ")
    for index, item in ipairs(data.priced) do
      if index > 14 then
        GameTooltip:AddLine(string.format("… and %d more", #data.priced - 14), 0.6, 0.7, 0.62)
        break
      end
      GameTooltip:AddDoubleLine(
        string.format("%s x%d", item.name or item.itemString, item.count),
        item.unit > 0 and SL:FormatMoney(item.value) or "|cff9c9c9cno price|r",
        1, 1, 1, 1, 0.85, 0.22)
    end
  end
  if data.money > 0 then
    GameTooltip:AddDoubleLine("Attached gold", SL:FormatMoney(data.money), 0.6, 0.7, 0.62, 1, 0.85, 0.22)
  end
  if data.cod > 0 then
    GameTooltip:AddDoubleLine("COD due", SL:FormatMoney(data.cod), 0.99, 0.34, 0.34, 0.99, 0.34, 0.34)
  end
  GameTooltip:Show()
end

local function BuildMessageRow(parent)
  local row = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  row:SetHeight(ROW_HEIGHT)
  Backdrop(row, 1, COL_ROW, COL_EDGE)
  row:EnableMouse(true)

  row.stripe = row:CreateTexture(nil, "ARTWORK")
  row.stripe:SetPoint("TOPLEFT", 1, -1); row.stripe:SetPoint("BOTTOMLEFT", 1, 1); row.stripe:SetWidth(3)
  row.stripe:SetTexture("Interface\\Buttons\\WHITE8X8")

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(24, 24); row.icon:SetPoint("TOPLEFT", 10, -5)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  row.contents = Text(row, "LEFT", 12, true, COL_TEXT)
  row.contents:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -1)
  row.contents:SetPoint("TOPRIGHT", -150, -6)
  row.contents:SetHeight(14); row.contents:SetWordWrap(false)

  row.route = Text(row, "LEFT", 11, false, COL_DIM)
  row.route:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, -16)
  row.route:SetPoint("TOPRIGHT", -150, -21)
  row.route:SetHeight(13); row.route:SetWordWrap(false)

  row.value = Text(row, "RIGHT", 12, true, COL_GOLD)
  row.value:SetPoint("TOPRIGHT", -10, -6); row.value:SetWidth(140); row.value:SetHeight(14); row.value:SetWordWrap(false)

  row.clock = Text(row, "RIGHT", 11, true, COL_GREEN)
  row.clock:SetPoint("TOPRIGHT", -10, -21); row.clock:SetWidth(140); row.clock:SetHeight(13); row.clock:SetWordWrap(false)

  -- Lifetime bar. Two segments: the bright one is time left before the parcel
  -- moves (returns to sender), the dim one is the grace period after that.
  row.track = row:CreateTexture(nil, "ARTWORK")
  row.track:SetPoint("BOTTOMLEFT", 41, 6); row.track:SetPoint("BOTTOMRIGHT", -10, 6)
  row.track:SetHeight(4); row.track:SetTexture("Interface\\Buttons\\WHITE8X8")
  SetColor(function(...) row.track:SetVertexColor(...) end, COL_EDGE, 1)

  row.fillReturn = row:CreateTexture(nil, "OVERLAY")
  row.fillReturn:SetHeight(4); row.fillReturn:SetTexture("Interface\\Buttons\\WHITE8X8")
  row.fillGrace = row:CreateTexture(nil, "OVERLAY")
  row.fillGrace:SetHeight(4); row.fillGrace:SetTexture("Interface\\Buttons\\WHITE8X8")

  row:SetScript("OnEnter", function(self) MessageTooltip(self) end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local function FillMessageRow(row, data, width)
  row.data = data

  local accent = UrgencyColor(data.deadline)
  SetColor(function(...) row.stripe:SetVertexColor(...) end, accent, 1)
  Backdrop(row, 1, data.observed and COL_ROW or COL_ROW_ALT, COL_EDGE)

  local first = data.priced[1]
  local icon = 134400
  if first and first.itemID then
    icon = select(5, GetItemInfoInstant(first.itemID)) or icon
  end
  if data.money > 0 and not first then icon = "Interface\\Icons\\INV_Misc_Coin_01" end
  row.icon:SetTexture(icon)

  -- Contents line: biggest stacks first, overflow collapsed into a counter.
  local parts = {}
  for index, item in ipairs(data.priced) do
    if index > 3 then break end
    parts[#parts + 1] = string.format("%s |cff9c9c9cx%d|r", item.name or item.itemString, item.count)
  end
  if #data.priced > 3 then
    parts[#parts + 1] = string.format("|cff%s+%d more|r", ToHex(COL_SUBTLE), #data.priced - 3)
  end
  if data.money > 0 then
    parts[#parts + 1] = string.format("|cff%s%s|r", ToHex(COL_GOLD), SL:FormatMoney(data.money))
  end
  if #parts == 0 then
    parts[1] = string.format("|cff%s%s|r", ToHex(COL_SUBTLE), data.subject ~= "" and data.subject or "(empty message)")
  end
  row.contents:SetText(table.concat(parts, "  ·  "))

  -- Route line: who holds it now, where it came from, and any caveats.
  local flags = {}
  if data.kind == "auction" then flags[#flags + 1] = string.format("|cff%sAH|r", ToHex(COL_BLUE)) end
  if data.wasReturned or data.bounced then flags[#flags + 1] = string.format("|cff%sbounced|r", ToHex(COL_ORANGE)) end
  if data.cod > 0 then flags[#flags + 1] = string.format("|cff%sCOD %s|r", ToHex(COL_RED), SL:FormatMoney(data.cod)) end
  if data.arrivingIn then flags[#flags + 1] = string.format("|cff%sarrives in %s|r", ToHex(COL_SUBTLE), FormatDuration(data.arrivingIn)) end
  if not data.observed then flags[#flags + 1] = string.format("|cff%sunconfirmed|r", ToHex(COL_ORANGE)) end
  if data.unpriced > 0 then flags[#flags + 1] = string.format("|cff%s%d unpriced|r", ToHex(COL_ORANGE), data.unpriced) end
  local route = string.format("|cff%s%s|r  |cff%s<-|r  %s",
    ToHex(COL_GOLD), data.holder or "?", ToHex(COL_DIMMER), data.origin or "?")
  if #flags > 0 then route = route .. "   " .. table.concat(flags, " · ") end
  row.route:SetText(route)

  row.value:SetText(data.value > 0 and SL:FormatMoney(data.value) or "|cff9c9c9c—|r")

  -- Clock line leads with whichever deadline hits first.
  local clock
  if data.daysToReturn then
    clock = string.format("returns %s |cff%s· gone %s|r",
      FormatDuration(data.daysToReturn), ToHex(COL_DIMMER), FormatDuration(data.daysToDeletion))
  else
    clock = string.format("deleted in %s", FormatDuration(data.daysToDeletion))
  end
  row.clock:SetText(clock)
  row.clock:SetTextColor(accent[1], accent[2], accent[3])

  -- Bar geometry. Track spans from x=41 to width-10.
  local trackWidth = math.max(20, (width or 700) - 51)
  local lifetime = data.totalLifetime or (SL.MAIL_RETURN_DAYS + SL.MAIL_GRACE_DAYS)
  local returnFrac = math.max(0, math.min(1, (data.daysToReturn or 0) / lifetime))
  local totalFrac = math.max(0, math.min(1, (data.daysToDeletion or 0) / lifetime))
  local graceFrac = math.max(0, totalFrac - returnFrac)

  row.fillReturn:ClearAllPoints()
  row.fillReturn:SetPoint("BOTTOMLEFT", 41, 6)
  if returnFrac > 0 then
    row.fillReturn:SetWidth(math.max(1, trackWidth * returnFrac))
    SetColor(function(...) row.fillReturn:SetVertexColor(...) end, accent, 1)
    row.fillReturn:Show()
  else
    row.fillReturn:Hide()
  end

  row.fillGrace:ClearAllPoints()
  row.fillGrace:SetPoint("BOTTOMLEFT", 41 + trackWidth * returnFrac, 6)
  if graceFrac > 0 then
    row.fillGrace:SetWidth(math.max(1, trackWidth * graceFrac))
    SetColor(function(...) row.fillGrace:SetVertexColor(...) end, returnFrac > 0 and COL_DIMMER or accent, 1)
    row.fillGrace:Show()
  else
    row.fillGrace:Hide()
  end
end

local function BuildInboxHeader(parent, inbox)
  local header = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  header:SetHeight(24)
  Backdrop(header, 1, COL_PANEL, COL_EDGE)

  local name = Text(header, "LEFT", 12, true, inbox.transit and COL_ORANGE or COL_TEXT)
  name:SetPoint("LEFT", 10, 0); name:SetPoint("RIGHT", -260, 0); name:SetHeight(14); name:SetWordWrap(false)
  local label
  if inbox.transit then
    label = string.format("IN TRANSIT  |cff9c9c9c%d unconfirmed shipment%s|r", #inbox.rows, #inbox.rows == 1 and "" or "s")
  else
    local realm = inbox.realm and string.format(" |cff%s— %s|r", ToHex(COL_DIMMER), inbox.realm) or ""
    local freshness
    if inbox.stale then
      freshness = string.format("|cff%sscanned %s — projected|r", ToHex(COL_ORANGE), SL:FormatAge(inbox.age))
    else
      freshness = string.format("|cff%sscanned %s|r", ToHex(COL_SUBTLE), SL:FormatAge(inbox.age))
    end
    label = string.format("%s%s  %s", inbox.name, realm, freshness)
    if inbox.capped then
      label = label .. string.format("  |cff%sinbox at 50-mail cap|r", ToHex(COL_RED))
    end
  end
  name:SetText(label)

  local stats = Text(header, "RIGHT", 11, false, COL_DIM)
  stats:SetPoint("RIGHT", -10, 0); stats:SetWidth(250); stats:SetHeight(14); stats:SetWordWrap(false)
  local urgentStr = inbox.urgent > 0 and string.format(" |cff%s%d urgent|r", ToHex(COL_ORANGE), inbox.urgent) or ""
  stats:SetText(string.format("%d mail · %d stack%s · %d item%s · |cff%s%s|r%s",
    #inbox.rows, inbox.stacks, inbox.stacks == 1 and "" or "s",
    inbox.units, inbox.units == 1 and "" or "s",
    ToHex(COL_GOLD), SL:FormatMoney(inbox.value + inbox.money), urgentStr))
  return header
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

function SL:CreateMailTab()
  if self.mailPanel or not self.frame then return end
  local panel = CreateFrame("Frame", nil, self.frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetPoint("TOPLEFT", 10, -38); panel:SetPoint("BOTTOMRIGHT", -10, 43)
  panel:SetFrameLevel(self.frame:GetFrameLevel() + 5)
  Backdrop(panel, 1, COL_BG, COL_EDGE)
  panel:Hide()
  self.mailPanel = panel
  self.mailRows = {}

  local summary = Text(panel, "LEFT", 12, true, COL_TEXT)
  summary:SetPoint("TOPLEFT", 12, -10); summary:SetWidth(420); summary:SetHeight(14); summary:SetWordWrap(false)
  panel.summary = summary

  local function Check(label, xOffsetFrom, onClick)
    local box = CreateFrame("CheckButton", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
    box:SetSize(14, 14)
    Backdrop(box, 1, COL_ROW, COL_EDGE)
    local mark = box:CreateTexture(nil, "ARTWORK")
    mark:SetPoint("TOPLEFT", 2, -2); mark:SetPoint("BOTTOMRIGHT", -2, 2)
    mark:SetColorTexture(COL_GOLD[1], COL_GOLD[2], COL_GOLD[3], 1)
    box:SetCheckedTexture(mark)
    local text = Text(panel, "LEFT", 11, false, COL_DIM)
    text:SetPoint("LEFT", box, "RIGHT", 6, 0); text:SetText(label)
    box:SetScript("OnClick", onClick)
    box.text = text
    return box
  end

  local urgentBox = Check("Urgent only", nil, function(b)
    panel.urgentOnly = b:GetChecked() and true or false; SL:RefreshMail()
  end)
  urgentBox:SetPoint("TOPLEFT", 12, -32)
  panel.urgentBox = urgentBox

  local ahBox = Check("Hide AH mail", nil, function(b)
    panel.hideAuction = b:GetChecked() and true or false; SL:RefreshMail()
  end)
  ahBox:SetPoint("LEFT", urgentBox.text, "RIGHT", 18, 0)
  panel.ahBox = ahBox

  local emptyBox = Check("Hide empty mail", nil, function(b)
    panel.hideEmpty = b:GetChecked() and true or false; SL:RefreshMail()
  end)
  emptyBox:SetPoint("LEFT", ahBox.text, "RIGHT", 18, 0)
  emptyBox:SetChecked(true)
  panel.hideEmpty = true
  panel.emptyBox = emptyBox

  local hint = Text(panel, "RIGHT", 11, false, COL_SUBTLE)
  hint:SetPoint("TOPRIGHT", -12, -10); hint:SetHeight(14); hint:SetWordWrap(false)
  hint:SetText("bright bar = time before it returns · dim = grace before deletion")
  panel.hint = hint

  local legend = Text(panel, "RIGHT", 11, false, COL_SUBTLE)
  legend:SetPoint("TOPRIGHT", -12, -32); legend:SetHeight(14); legend:SetWordWrap(false)
  legend:SetText(string.format("|cff%s<1d|r · |cff%s<3d|r · |cff%s<%dd|r · |cff%sok|r · hover a row for the full manifest",
    ToHex(COL_RED), ToHex(COL_ORANGE), ToHex(COL_GOLD), self.MAIL_URGENT_DAYS, ToHex(COL_GREEN)))
  panel.legend = legend

  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -54); scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(panel:GetWidth() - 40, 1); scroll:SetScrollChild(content)
  panel.scroll = scroll; panel.content = content

  panel:SetScript("OnSizeChanged", function()
    content:SetWidth(panel:GetWidth() - 40)
    SL:RefreshMail()
  end)
  return panel
end

-- Rebuilds every row, so it must not feed the theme tint registry.
function SL:RefreshMail()
  SL.WithoutTintCollection(function() self:RefreshMailImpl() end)
end

function SL:RefreshMailImpl()
  local panel = self.mailPanel
  if not panel or not panel:IsShown() then return end
  local report = self:BuildMailReport()

  for _, widget in ipairs(self.mailRows) do widget:Hide(); widget:SetParent(nil) end
  self.mailRows = {}

  local totals = report.totals
  local unconfirmed = totals.unconfirmed > 0
    and string.format(" · |cff%s%d unconfirmed|r", ToHex(COL_ORANGE), totals.unconfirmed) or ""
  panel.summary:SetText(string.format("|cff%s%d|r mail · %d stack%s · %d item%s · |cff%s%s|r · |cff%s%d urgent|r%s",
    ToHex(COL_GOLD), totals.messages,
    totals.stacks, totals.stacks == 1 and "" or "s",
    totals.units, totals.units == 1 and "" or "s",
    ToHex(COL_GOLD), self:FormatMoney(totals.value + totals.money),
    ToHex(totals.urgent > 0 and COL_ORANGE or COL_SUBTLE), totals.urgent,
    unconfirmed))

  local content = panel.content
  local width = content:GetWidth() - 8
  local y = -4
  local shown = 0

  for _, inbox in ipairs(report.inboxes) do
    local visible = {}
    for _, row in ipairs(inbox.rows) do
      local keep = true
      if panel.urgentOnly and (row.deadline or 999) > self.MAIL_URGENT_DAYS then keep = false end
      if panel.hideAuction and row.kind == "auction" then keep = false end
      if panel.hideEmpty and row.stacks == 0 and row.money <= 0 then keep = false end
      if keep then visible[#visible + 1] = row end
    end
    if #visible > 0 then
      local header = BuildInboxHeader(content, inbox)
      header:SetPoint("TOPLEFT", 4, y); header:SetPoint("TOPRIGHT", -4, y)
      self.mailRows[#self.mailRows + 1] = header
      y = y - 26

      for _, data in ipairs(visible) do
        local row = BuildMessageRow(content)
        row:SetPoint("TOPLEFT", 4, y); row:SetPoint("TOPRIGHT", -4, y)
        FillMessageRow(row, data, width)
        self.mailRows[#self.mailRows + 1] = row
        y = y - ROW_HEIGHT - 3
        shown = shown + 1
      end
      y = y - 8
    end
  end

  if shown == 0 then
    local empty = Text(content, "LEFT", 12, false, COL_SUBTLE)
    empty:SetPoint("TOPLEFT", 12, y); empty:SetPoint("TOPRIGHT", -12, y)
    empty:SetJustifyH("LEFT"); empty:SetWordWrap(true); empty:SetHeight(48)
    if totals.messages > 0 then
      empty:SetText("Every tracked mail is filtered out. Clear the checkboxes above to see them.")
    else
      empty:SetText("No mail recorded yet. Log into each character and open its mailbox once — Goblin snapshots the inbox on every visit and projects the countdowns forward from there.")
    end
    self.mailRows[#self.mailRows + 1] = empty
    y = y - 52
  end

  content:SetHeight(math.max(1, -y + 8))
end

function SL:ShowMail()
  if not self.mailPanel then self:CreateMailTab() end
  self.uiMode = "mail"
  self:ApplyUIMode()
end

--------------------------------------------------------------------------
-- Chat report
--------------------------------------------------------------------------

function SL:PrintMailReport()
  local report = self:BuildMailReport()
  local t = report.totals
  print(string.format("|cffffd839Goblin mail|r — %d mail, %d stacks, %s, %d urgent (<%dd)",
    t.messages, t.stacks, self:FormatMoney(t.value + t.money), t.urgent, self.MAIL_URGENT_DAYS))
  for _, inbox in ipairs(report.inboxes) do
    local suffix = inbox.transit and " (unconfirmed)" or (inbox.stale and string.format(" (scanned %s)", self:FormatAge(inbox.age)) or "")
    print(string.format("  |cff00fe00%s|r%s — %d mail, %s",
      inbox.name, suffix, #inbox.rows, self:FormatMoney(inbox.value + inbox.money)))
    for _, row in ipairs(inbox.rows) do
      local names = {}
      for index, item in ipairs(row.priced) do
        if index > 3 then names[#names + 1] = string.format("+%d more", #row.priced - 3); break end
        names[#names + 1] = string.format("%sx%d", item.name or item.itemString, item.count)
      end
      local clock = row.daysToReturn
        and string.format("returns %s, deleted %s", FormatDuration(row.daysToReturn), FormatDuration(row.daysToDeletion))
        or string.format("deleted %s", FormatDuration(row.daysToDeletion))
      print(string.format("    |cffababab%s <- %s|r  %s  |cffffd839%s|r",
        row.holder or "?", row.origin or "?",
        #names > 0 and table.concat(names, ", ") or (row.subject ~= "" and row.subject or "(empty)"),
        clock))
    end
  end
end
