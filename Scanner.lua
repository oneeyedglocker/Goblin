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
  return C_Container and C_Container.GetContainerNumSlots(bag) or GetContainerNumSlots(bag)
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
end

function SL:ScanGuildBank()
  local guildKey = self:GetGuildKey()
  if not guildKey then return end
  local guild = self.db.guilds[guildKey] or { name = GetGuildInfo("player"), realm = GetRealmName(), tabs = {}, tabNames = {} }
  self.db.guilds[guildKey] = guild
  if self.db.settings.guilds[guildKey] == nil then self.db.settings.guilds[guildKey] = true end
  local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab() or 1
  guild.tabNames = guild.tabNames or {}
  local tabName = GetGuildBankTabInfo and GetGuildBankTabInfo(tab)
  guild.tabNames[tab] = tabName or ("Tab " .. tab)
  local tabItems = NewItemTable()
  for slot = 1, MAX_GUILDBANK_SLOTS_PER_TAB or 98 do
    local link = GetGuildBankItemLink(tab, slot)
    local _, count = GetGuildBankItemInfo(tab, slot)
    AddItem(tabItems, link, count)
  end
  guild.tabs[tab] = tabItems
  guild.items = NewItemTable()
  for _, savedTab in pairs(guild.tabs) do
    for _, item in pairs(savedTab) do AddItem(guild.items, item.link, item.count) end
  end
  guild.gold = GetGuildBankMoney and GetGuildBankMoney() or guild.gold
  guild.updated = time()
  if self.RefreshUI then self:RefreshUI() end
end

function SL:UpdateMoney()
  local character = self:GetCharacter()
  character.gold = GetMoney()
  character.moneyUpdated = time()
  if self.RefreshUI then self:RefreshUI() end
end

function SL:InitializeScanner()
  local eventNames = {
    "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_MONEY", "BANKFRAME_OPENED",
    "MAIL_SHOW", "MAIL_INBOX_UPDATE", "AUCTION_HOUSE_SHOW", "AUCTION_OWNED_LIST_UPDATE",
    "GUILDBANKFRAME_OPENED", "GUILDBANKBAGSLOTS_CHANGED", "PLAYER_GUILD_UPDATE",
  }
  for _, event in ipairs(eventNames) do pcall(Scanner.RegisterEvent, Scanner, event) end
  Scanner:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" then self:ScanBags()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then self:ScanEquipped()
    elseif event == "PLAYER_MONEY" then self:UpdateMoney()
    elseif event == "BANKFRAME_OPENED" then self:ScanBank()
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then self:ScanMail()
    elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_OWNED_LIST_UPDATE" then self:ScanAuctions()
    elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANKBAGSLOTS_CHANGED" then self:ScanGuildBank()
    elseif event == "PLAYER_GUILD_UPDATE" then self:GetCharacter(); if self.RefreshUI then self:RefreshUI() end end
  end)
end
