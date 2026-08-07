local _, SL = ...

-- Mail-transit ledger.
-- Goblin can only observe mail when a character opens their inbox, so a raw
-- inbox scan under-counts everything an alt has mailed to a sibling toon and
-- not yet retrieved. This module intercepts outgoing SendMail calls, stages
-- the attachments before the API clears them, commits on MAIL_SUCCESS, and
-- attributes the shipment to the recipient (days 0-30) or back to the sender
-- (days 30-60) until a live inbox scan reconciles it away.

local DAY_SECONDS = 86400
local RECIPIENT_WINDOW = 30 * DAY_SECONDS
local RETURN_WINDOW   = 60 * DAY_SECONDS

local function NowSeconds() return time() end

local function EmptyTable(t)
  if not t then return true end
  for _ in pairs(t) do return false end
  return true
end

function SL:ResolveMailRecipient(rawName)
  if not rawName or rawName == "" then return nil end
  local realm = GetRealmName()
  local best
  for key, record in pairs(self.db.characters or {}) do
    if record.name == rawName then
      if record.realm == realm then return key, record end
      best = best or key
    end
  end
  return best
end

local function CopyItem(entry)
  return {
    itemString = entry.itemString,
    itemID = entry.itemID,
    link = entry.link,
    name = entry.name,
    count = entry.count,
    boundCount = entry.boundCount or 0,
  }
end

function SL:StageOutgoingMail(target, subject, body)
  self.mailStaging = nil
  if not target or target == "" then return end
  local recipientKey = self:ResolveMailRecipient(target)
  if not recipientKey then return end
  local maxAttachments = ATTACHMENTS_MAX_SEND or 12
  local items, itemCount = {}, 0
  for slot = 1, maxAttachments do
    local link = GetSendMailItemLink and GetSendMailItemLink(slot)
    local _, _, _, quantity = GetSendMailItem(slot)
    if link and quantity and quantity > 0 then
      local itemString, itemID = self:NormalizeItem(link)
      if itemString then
        local existing = items[itemString]
        if existing then
          existing.count = existing.count + quantity
        else
          items[itemString] = { itemString = itemString, itemID = itemID, link = link, name = GetItemInfo(link), count = quantity, boundCount = 0 }
          itemCount = itemCount + 1
        end
      end
    end
  end
  local money = (GetSendMailMoney and GetSendMailMoney()) or 0
  if itemCount == 0 and (not money or money <= 0) then return end
  local senderRecord, senderKey = self:GetCharacter()
  self.mailStaging = {
    senderKey = senderKey,
    senderName = senderRecord.name,
    senderRealm = senderRecord.realm,
    recipientName = target,
    recipientKey = recipientKey,
    subject = subject,
    items = items,
    money = money or 0,
    stagedAt = NowSeconds(),
  }
end

function SL:CommitStagedMail()
  local staged = self.mailStaging
  self.mailStaging = nil
  if not staged then return end
  self.db.mailTransit = self.db.mailTransit or {}
  self.db.mailTransitSeq = (self.db.mailTransitSeq or 0) + 1
  local id = string.format("%d-%d-%s", staged.stagedAt, self.db.mailTransitSeq, staged.senderKey or "?")
  self.db.mailTransit[id] = {
    id = id,
    senderKey = staged.senderKey,
    senderName = staged.senderName,
    senderRealm = staged.senderRealm,
    recipientKey = staged.recipientKey,
    recipientName = staged.recipientName,
    subject = staged.subject,
    items = staged.items,
    money = staged.money or 0,
    sentAt = NowSeconds(),
    status = "pending",
  }
  if self.RefreshUI then self:RefreshUI() end
end

function SL:DiscardStagedMail() self.mailStaging = nil end

function SL:StageReturnedMail(inboxIndex)
  local sender = GetInboxHeaderInfo and GetInboxHeaderInfo(inboxIndex)
  local recipientRecord, recipientKey = self:GetCharacter()
  local resolvedSenderKey = sender and self:ResolveMailRecipient(sender)
  local items, itemCount = {}, 0
  local maxAttachments = ATTACHMENTS_MAX_RECEIVE or 16
  for slot = 1, maxAttachments do
    local link = GetInboxItemLink(inboxIndex, slot)
    local _, _, _, quantity = GetInboxItem(inboxIndex, slot)
    if link and quantity and quantity > 0 then
      local itemString, itemID = self:NormalizeItem(link)
      if itemString then
        local existing = items[itemString]
        if existing then existing.count = existing.count + quantity
        else
          items[itemString] = { itemString = itemString, itemID = itemID, link = link, name = GetItemInfo(link), count = quantity, boundCount = 0 }
          itemCount = itemCount + 1
        end
      end
    end
  end
  if itemCount == 0 then return end
  self.db.mailTransit = self.db.mailTransit or {}
  self.db.mailTransitSeq = (self.db.mailTransitSeq or 0) + 1
  local now = NowSeconds()
  local id = string.format("%d-%d-return-%s", now, self.db.mailTransitSeq, recipientKey)
  self.db.mailTransit[id] = {
    id = id,
    senderKey = recipientKey,                 -- the char returning it becomes the "sender" of the return trip
    senderName = recipientRecord.name,
    senderRealm = recipientRecord.realm,
    recipientKey = resolvedSenderKey,
    recipientName = sender,
    subject = "Returned",
    items = items,
    money = 0,
    sentAt = now,
    status = "pending",
    returned = true,
  }
  if self.RefreshUI then self:RefreshUI() end
end

local function ReconcileAgainstInbox(self, currentKey)
  local transit = self.db.mailTransit
  if not transit then return end
  local visible = {}
  for index = 1, GetInboxNumItems() do
    local sender = GetInboxHeaderInfo and GetInboxHeaderInfo(index)
    if sender then
      visible[sender] = visible[sender] or {}
      for slot = 1, (ATTACHMENTS_MAX_RECEIVE or 16) do
        local link = GetInboxItemLink(index, slot)
        local _, _, _, quantity = GetInboxItem(index, slot)
        if link and quantity and quantity > 0 then
          local itemString = self:NormalizeItem(link)
          if itemString then
            local senderBucket = visible[sender]
            senderBucket[itemString] = (senderBucket[itemString] or 0) + quantity
          end
        end
      end
    end
  end
  local now = NowSeconds()
  local mailCapReached = GetInboxNumItems() >= 50
  for id, record in pairs(transit) do
    if record.status == "pending" and record.recipientKey == currentKey then
      local age = now - (record.sentAt or now)
      if age < RECIPIENT_WINDOW then
        local senderBucket = visible[record.senderName or ""]
        local matches = false
        if senderBucket then
          matches = true
          for itemString, item in pairs(record.items or {}) do
            if (senderBucket[itemString] or 0) < item.count then matches = false; break end
          end
        end
        -- If we can see a matching mail from the sender OR the inbox is
        -- authoritative (not at the visible cap), consider the shipment
        -- reconciled: either it's still sitting there and the inbox scan
        -- already counts it, or the recipient already took it into bags.
        if matches or not mailCapReached then
          record.status = "delivered"
          record.deliveredAt = now
        end
      end
    end
  end
end

function SL:ReconcileMailTransit()
  local _, key = self:GetCharacter()
  ReconcileAgainstInbox(self, key)
end

function SL:PruneMailTransit()
  local transit = self.db.mailTransit
  if not transit then return end
  local now = NowSeconds()
  for id, record in pairs(transit) do
    local age = now - (record.sentAt or now)
    if age >= RETURN_WINDOW then record.status = "expired" end
    if record.status == "expired" or record.status == "delivered" or record.status == "reclaimed" then
      transit[id] = nil
    end
  end
  if EmptyTable(transit) then self.db.mailTransitSeq = 0 end
end

-- Iterates pending shipments and returns per-character mail contributions
-- keyed by character key. Each contribution is a plain items table shaped
-- like the normal `mail` location so BuildLedger's Add() can consume it.
function SL:CollectMailTransit()
  local transit = self.db.mailTransit
  local perCharacter, transitGold = {}, {}
  if not transit then return perCharacter, transitGold end
  local now = NowSeconds()
  for _, record in pairs(transit) do
    if record.status == "pending" then
      local age = now - (record.sentAt or now)
      local attributeTo
      if age < RECIPIENT_WINDOW then attributeTo = record.recipientKey
      elseif age < RETURN_WINDOW then attributeTo = record.senderKey end
      if attributeTo then
        perCharacter[attributeTo] = perCharacter[attributeTo] or {}
        local bucket = perCharacter[attributeTo]
        for itemString, entry in pairs(record.items or {}) do
          local target = bucket[itemString]
          if not target then
            target = CopyItem(entry); target.count = 0; bucket[itemString] = target
          end
          target.count = target.count + entry.count
        end
        if (record.money or 0) > 0 and age < RECIPIENT_WINDOW then
          -- Attached gold rides with the shipment during the delivery window.
          transitGold[attributeTo] = (transitGold[attributeTo] or 0) + record.money
        end
      end
    end
  end
  return perCharacter, transitGold
end

function SL:InitializeMailLedger()
  self.db.mailTransit = self.db.mailTransit or {}
  self:PruneMailTransit()
  if self.mailLedgerInstalled then return end
  self.mailLedgerInstalled = true
  hooksecurefunc("SendMail", function(target, subject, body)
    SL:StageOutgoingMail(target, subject, body)
  end)
  if type(_G.ReturnInboxItem) == "function" then
    hooksecurefunc("ReturnInboxItem", function(index) SL:StageReturnedMail(index) end)
  end
  local events = CreateFrame("Frame")
  events:RegisterEvent("MAIL_SUCCESS")
  events:RegisterEvent("MAIL_FAILED")
  events:SetScript("OnEvent", function(_, event)
    if event == "MAIL_SUCCESS" then SL:CommitStagedMail()
    elseif event == "MAIL_FAILED" then SL:DiscardStagedMail() end
  end)
end
