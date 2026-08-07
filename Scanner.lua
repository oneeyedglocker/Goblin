local _, SL = ...

local Scanner = CreateFrame("Frame")
local attachmentMax = ATTACHMENTS_MAX_RECEIVE or 16

local function NewItemTable() return {} end

local function AddItem(target, link, count, isBound)
  local itemString, itemID = SL:NormalizeItem(link)
  count = tonumber(count) or 0
  if not itemString or count <= 0 then return end
  local item = target[itemString]
  if not item then
    item = { itemID = itemID, link = link, name = GetItemInfo(link), count = 0, boundCount = 0 }
    target[itemString] = item
  end
  item.count = item.count + count
  if isBound then item.boundCount = (item.boundCount or 0) + count end
  if not item.link then item.link = link end
  if not item.name then item.name = GetItemInfo(link) end
end

local function GetContainerSlots(bag)
  local n
  if C_Container and C_Container.GetContainerNumSlots then
    n = C_Container.GetContainerNumSlots(bag)
  else
    n = GetContainerNumSlots(bag)
  end
  -- Some TBC Classic builds return nil for bank containers before the bank
  -- data has streamed in; treat that as zero slots so the outer for loop
  -- doesn't error and the caller commits an empty bucket instead of aborting.
  return tonumber(n) or 0
end

local function GetContainerItem(bag, slot)
  if C_Container then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.hyperlink, info and info.stackCount, info and info.isBound
  end
  local _, count, _, _, _, _, link, _, _, _, isBound = GetContainerItemInfo(bag, slot)
  return link, count, isBound
end

local function ScanContainers(bags)
  local items = NewItemTable()
  for _, bag in ipairs(bags) do
    for slot = 1, GetContainerSlots(bag) do
      local link, count, isBound = GetContainerItem(bag, slot)
      AddItem(items, link, count, isBound)
    end
  end
  return items
end

function SL:CommitCharacterLocation(location, items)
  local character = self:GetCharacter()
  character.locations[location] = items
  character.updated = character.updated or {}
  character.updated[location] = time()
  character.lastScan = time()
  if self.RefreshUI then self:RefreshUI() end
end

function SL:ScanBags()
  self:CommitCharacterLocation("bags", ScanContainers({ 0, 1, 2, 3, 4 }))
end

function SL:ScanBank()
  self:CommitCharacterLocation("bank", ScanContainers({ BANK_CONTAINER or -1, 5, 6, 7, 8, 9, 10, 11 }))
end

function SL:ScanEquipped()
  local items = NewItemTable()
  for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
    local link = GetInventoryItemLink("player", slot)
    AddItem(items, link, link and 1 or 0, true)
  end
  self:CommitCharacterLocation("equipped", items)
end

function SL:ScanMail()
  local items = NewItemTable()
  for index = 1, GetInboxNumItems() do
    for attachment = 1, attachmentMax do
      local link = GetInboxItemLink(index, attachment)
      local _, _, _, count = GetInboxItem(index, attachment)
      AddItem(items, link, count)
    end
  end
  self:CommitCharacterLocation("mail", items)
  if self.ReconcileMailTransit then self:ReconcileMailTransit() end
  if self.ReconcileAuctionsAgainstMail then self:ReconcileAuctionsAgainstMail() end
end

function SL:ScanAuctions()
  local items = NewItemTable()
  local count = GetNumAuctionItems and GetNumAuctionItems("owner") or 0
  for index = 1, count do
    local link = GetAuctionItemLink("owner", index)
    local _, _, stackCount = GetAuctionItemInfo("owner", index)
    AddItem(items, link, stackCount)
  end
  self:CommitCharacterLocation("auctions", items)
  -- Persist the raw AH scan separately so ReconcileAuctionsAgainstMail can
  -- derive an accurate visible-auctions count without losing the baseline.
  local character = self:GetCharacter()
  local raw = NewItemTable()
  for k, v in pairs(items) do
    raw[k] = { itemID = v.itemID, link = v.link, name = v.name, count = v.count, boundCount = v.boundCount }
  end
  character.auctionsScanRaw = raw
end

-- Auction-return-mail reconciliation: when items come back from the AH via
-- mail (expired, cancelled, or sold-invoice), the seller's mail bucket picks
-- them up on the next mail scan while the auctions bucket still holds the
-- stale pre-return quantity. This function derives locations.auctions from
-- the last raw AH scan minus the quantities currently sitting in AH-return
-- mails, so a mail-only visit deduplicates the count automatically.
function SL:ReconcileAuctionsAgainstMail()
  local character = self:GetCharacter()
  local raw = character.auctionsScanRaw
  if not raw then return end
  local result = {}
  for k, v in pairs(raw) do
    result[k] = { itemID = v.itemID, link = v.link, name = v.name, count = v.count, boundCount = v.boundCount }
  end

  local function subjectPrefix(tmpl)
    if not tmpl then return nil end
    return (tmpl:gsub("%%s", ""))
  end
  local prefixes = {
    { p = subjectPrefix(AUCTION_EXPIRED_MAIL_SUBJECT),   kind = "expired" },
    { p = subjectPrefix(AUCTION_REMOVED_MAIL_SUBJECT),   kind = "cancelled" },
    { p = subjectPrefix(AUCTION_SOLD_MAIL_SUBJECT),      kind = "sold" },
  }

  local function classify(subject)
    if not subject then return nil end
    for _, entry in ipairs(prefixes) do
      if entry.p and subject:sub(1, #entry.p) == entry.p then
        return entry.kind, subject:sub(#entry.p + 1)
      end
    end
  end

  local function deduct(name, qty)
    if not name or not qty or qty <= 0 then return end
    for k, v in pairs(result) do
      if v.name == name or (v.link and GetItemInfo(v.link) == name) then
        v.count = math.max(0, (v.count or 0) - qty)
        if v.count == 0 then result[k] = nil end
        return
      end
    end
  end

  for index = 1, GetInboxNumItems() do
    local _, _, _, subject = GetInboxHeaderInfo(index)
    local kind, subjectItemName = classify(subject)
    if kind == "sold" and GetInboxInvoiceInfo then
      local invType, itemName, _, _, _, _, _, _, itemCount = GetInboxInvoiceInfo(index)
      if invType == "seller" and itemCount and itemCount > 0 then
        deduct(itemName or subjectItemName, itemCount)
      end
    elseif kind == "expired" or kind == "cancelled" then
      local link = GetInboxItemLink(index, 1)
      local _, _, _, quantity = GetInboxItem(index, 1)
      local name = link and GetItemInfo(link) or subjectItemName
      deduct(name, quantity)
    end
  end
  character.locations.auctions = result
end

-- ScanSingleGuildTab has two modes:
--   force=true  -- we just queried this tab or the user is viewing it, so any
--                  empty result is authoritative. Always overwrite.
--   force=false -- opportunistic scan (e.g. on GUILDBANKFRAME_OPENED before
--                  queries respond). Empty may just mean "data hasn't arrived
--                  yet", so preserve any previously-known contents.
local function ScanSingleGuildTab(guild, tab, force)
  guild.tabNames = guild.tabNames or {}
  local tabName = GetGuildBankTabInfo and GetGuildBankTabInfo(tab)
  guild.tabNames[tab] = tabName or guild.tabNames[tab] or ("Tab " .. tab)
  local tabItems = NewItemTable()
  local slotCount = MAX_GUILDBANK_SLOTS_PER_TAB or 98
  local seenAny = false
  for slot = 1, slotCount do
    local link = GetGuildBankItemLink(tab, slot)
    local _, count = GetGuildBankItemInfo(tab, slot)
    if link then seenAny = true end
    AddItem(tabItems, link, count)
  end
  if force or seenAny or not guild.tabs[tab] then
    guild.tabs[tab] = tabItems
    guild.tabUpdated = guild.tabUpdated or {}
    guild.tabUpdated[tab] = time()
    return true
  end
  return false
end

local function RebuildGuildAggregate(guild)
  guild.items = NewItemTable()
  for _, savedTab in pairs(guild.tabs) do
    for _, item in pairs(savedTab) do AddItem(guild.items, item.link, item.count) end
  end
end

function SL:ScanGuildBank(forceCurrentTab)
  local guildKey = self:GetGuildKey()
  if not guildKey then return end
  local guild = self.db.guilds[guildKey] or { name = GetGuildInfo("player"), realm = GetRealmName(), tabs = {}, tabNames = {} }
  self.db.guilds[guildKey] = guild
  guild.tabs = guild.tabs or {}
  if self.db.settings.guilds[guildKey] == nil then self.db.settings.guilds[guildKey] = true end
  local tabCount = GetNumGuildBankTabs and GetNumGuildBankTabs() or 1
  local changed = false
  local currentTab = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or nil
  for tab = 1, tabCount do
    local force = forceCurrentTab and tab == currentTab
    if ScanSingleGuildTab(guild, tab, force) then changed = true end
  end
  RebuildGuildAggregate(guild)
  guild.gold = GetGuildBankMoney and GetGuildBankMoney() or guild.gold
  guild.goldUpdated = time()
  guild.updated = time()
  if changed and self.RefreshUI then self:RefreshUI() end
end

-- After a QueryGuildBankTab response has had time to land, scan that specific
-- tab authoritatively so genuine emptying overwrites stale contents.
local function DeferredForceScan(tab)
  local guildKey = SL:GetGuildKey()
  if not guildKey then return end
  local guild = SL.db.guilds[guildKey]
  if not guild then return end
  local changed = ScanSingleGuildTab(guild, tab, true)
  if changed then
    RebuildGuildAggregate(guild)
    if SL.RefreshUI then SL:RefreshUI() end
  end
end

function SL:ForceRescanCurrentGuildBank()
  local guildKey = self:GetGuildKey()
  if not guildKey then return end
  local guild = self.db.guilds[guildKey]
  if not guild then return end
  guild.tabs = {}
  guild.tabUpdated = {}
  self:RequestAllGuildBankTabs()
end

function SL:UpdateMoney()
  local character = self:GetCharacter()
  character.gold = GetMoney()
  character.moneyUpdated = time()
  if self.RefreshUI then self:RefreshUI() end
end

-- Ask the server for every viewable tab so users don't have to click each
-- tab manually. QueryGuildBankTab does not spend withdrawal charges; tabs
-- the current rank can't view silently no-op. Staggered by frame to avoid
-- flooding the client on guild banks with many tabs.
function SL:RequestAllGuildBankTabs()
  if not QueryGuildBankTab then return end
  local tabCount = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
  if tabCount == 0 then return end
  for tab = 1, tabCount do
    local t = tab
    if C_Timer and C_Timer.After then
      C_Timer.After(t * 0.15, function() pcall(QueryGuildBankTab, t) end)
      -- Wait past the query round-trip, then scan authoritatively so an
      -- emptied tab actually clears its stored contents.
      C_Timer.After(t * 0.15 + 0.30, function() DeferredForceScan(t) end)
    else
      pcall(QueryGuildBankTab, t)
    end
  end
end

local bankOpen = false

function SL:InitializeScanner()
  local eventNames = {
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY",
    "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "PLAYERBANKBAGSLOTS_CHANGED",
    "MAIL_SHOW", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_OWNED_LIST_UPDATE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKBAGSLOTS_CHANGED", "PLAYER_GUILD_UPDATE",
  }
  for _, event in ipairs(eventNames) do pcall(Scanner.RegisterEvent, Scanner, event) end
  Scanner:SetScript("OnEvent", function(_, event)
    -- pcall the dispatch so a scan error can't silently freeze future scans
    -- for the session (previously any error in one scan aborted its
    -- CommitCharacterLocation call, leaving buckets nil forever).
    local ok, err = pcall(function()
      if event == "BAG_UPDATE_DELAYED" then
        self:ScanBags()
        if bankOpen then self:ScanBank() end
      elseif event == "PLAYER_EQUIPMENT_CHANGED" then self:ScanEquipped()
      elseif event == "PLAYER_MONEY" then self:UpdateMoney()
      elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        -- Initial best-effort scan; PLAYERBANKSLOTS_CHANGED will re-scan
        -- as the server streams the real bag data.
        self:ScanBank()
      elseif event == "BANKFRAME_CLOSED" then
        -- Final authoritative scan on close so anything the user changed
        -- while browsing is captured before they walk away.
        if bankOpen then self:ScanBank() end
        bankOpen = false
      elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERBANKBAGSLOTS_CHANGED" then
        if bankOpen then self:ScanBank() end
      elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then self:ScanMail()
      elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_OWNED_LIST_UPDATE" then self:ScanAuctions()
      elseif event == "GUILDBANKFRAME_OPENED" then self:ScanGuildBank(); self:RequestAllGuildBankTabs()
      elseif event == "GUILDBANKBAGSLOTS_CHANGED" then self:ScanGuildBank(true)
      elseif event == "PLAYER_GUILD_UPDATE" then self:GetCharacter(); if self.RefreshUI then self:RefreshUI() end
      end
    end)
    if not ok then
      print("|cffff5555Goblin scan error (" .. tostring(event) .. "):|r " .. tostring(err))
    end
  end)
end
