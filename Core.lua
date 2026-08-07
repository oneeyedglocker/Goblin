local ADDON_NAME, SL = ...

SL.VERSION = "0.5.0"
SL.CATEGORIES = { "bags", "bank", "equipped", "mail", "auctions", "guild" }
SL.CATEGORY_LABELS = {
  bags = "Bags", bank = "Bank", equipped = "Equipped", mail = "Mail",
  auctions = "Auctions", guild = "Guild",
}

local DEFAULTS = {
  settings = {
    priceSource = "dbmarket",
    includeGold = true,
    includeGuildGold = false,
    includeSoulbound = false,
    categories = { bags = true, bank = true, equipped = false, mail = true, auctions = true, guild = true },
    characters = {},
    characterCategories = {},
    characterGold = {},
    guilds = {},
    guildTabs = {},
    guildGold = {},
    sort = "value",
    descending = true,
  },
  characters = {},
  guilds = {},
  window = {},
}

local function CopyDefaults(source, target)
  for key, value in pairs(source) do
    if type(value) == "table" then
      if type(target[key]) ~= "table" then target[key] = {} end
      CopyDefaults(value, target[key])
    elseif target[key] == nil then
      target[key] = value
    end
  end
end

function SL:GetCharacterKey()
  return UnitName("player") .. " - " .. GetRealmName()
end

function SL:GetGuildKey()
  local guild = GetGuildInfo("player")
  return guild and (guild .. " - " .. GetRealmName()) or nil
end

function SL:GetCharacter()
  local key = self:GetCharacterKey()
  local record = self.db.characters[key]
  if not record then
    local _, class = UnitClass("player")
    record = { name = UnitName("player"), realm = GetRealmName(), class = class, locations = {} }
    self.db.characters[key] = record
  end
  local guildName = GetGuildInfo("player")
  if guildName then
    record.guildName = guildName
    record.guildKey = guildName .. " - " .. GetRealmName()
  elseif IsInGuild and not IsInGuild() then
    record.guildName, record.guildKey = nil, nil
  end
  if self.db.settings.characters[key] == nil then self.db.settings.characters[key] = true end
  return record, key
end

function SL:IsCharacterIncluded(key)
  return self.db.settings.characters[key] ~= false
end

function SL:IsGuildIncluded(key)
  return self.db.settings.guilds[key] ~= false
end

function SL:IsCharacterCategoryIncluded(characterKey, category)
  local settings = self.db.settings.characterCategories[characterKey]
  return not settings or settings[category] ~= false
end

function SL:IsCharacterGoldIncluded(characterKey)
  return self.db.settings.characterGold[characterKey] ~= false
end

function SL:IsGuildTabIncluded(guildKey, tab)
  local settings = self.db.settings.guildTabs[guildKey]
  return not settings or settings[tab] ~= false
end

function SL:IsGuildGoldIncluded(guildKey)
  return self.db.settings.guildGold[guildKey] ~= false
end

function SL:NormalizeItem(link)
  if not link then return nil end
  local itemID = GetItemInfoInstant(link)
  if not itemID then itemID = tonumber(link:match("item:(%d+)")) end
  if not itemID then return nil end
  return "i:" .. itemID, itemID
end

function SL:GetPrice(itemString)
  if not TSM_API or not TSM_API.GetCustomPriceValue then return nil, "TSM is not ready" end
  local ok, value, err = pcall(TSM_API.GetCustomPriceValue, self.db.settings.priceSource, itemString)
  if not ok then return nil, value end
  return value, err
end

function SL:ValidatePriceSource(source)
  if not TSM_API or not TSM_API.IsCustomPriceValid then return false, "TSM is not ready" end
  local ok, valid, err = pcall(TSM_API.IsCustomPriceValid, source)
  if not ok then return false, valid end
  return valid, err
end

function SL:FormatMoney(copper)
  copper = math.floor(tonumber(copper) or 0)
  if TSM_API and TSM_API.FormatMoneyString then
    local ok, result = pcall(TSM_API.FormatMoneyString, copper)
    if ok then return result end
  end
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  local coins = copper % 100
  return string.format("%dg %02ds %02dc", gold, silver, coins)
end

function SL:GetPriceSources()
  local result = {}
  if TSM_API and TSM_API.GetPriceSourceKeys then pcall(TSM_API.GetPriceSourceKeys, result) end
  table.sort(result)
  return result
end

function SL:BuildLedger(filter)
  local result, totalValue, totalGold = {}, 0, 0
  filter = strlower(strtrim(filter or ""))
  local function Add(location, items)
    if not self.db.settings.categories[location] then return end
    for itemString, item in pairs(items or {}) do
      local count = item.count or 0
      if not self.db.settings.includeSoulbound then
        count = math.max(0, count - (item.boundCount or 0))
      end
      if count > 0 then
        local row = result[itemString]
        if not row then
          row = { itemString = itemString, itemID = item.itemID, link = item.link, name = item.name, total = 0, value = 0 }
          result[itemString] = row
        end
        row[location] = (row[location] or 0) + count
        row.total = row.total + count
      end
    end
  end
  for key, character in pairs(self.db.characters) do
    if self:IsCharacterIncluded(key) then
      if self.db.settings.includeGold and self:IsCharacterGoldIncluded(key) then
        totalGold = totalGold + (character.gold or 0)
      end
      for _, location in ipairs(self.CATEGORIES) do
        if location ~= "guild" and self:IsCharacterCategoryIncluded(key, location) then
          Add(location, character.locations and character.locations[location])
        end
      end
    end
  end
  if self.db.settings.categories.guild then
    for key, guild in pairs(self.db.guilds) do
      if self:IsGuildIncluded(key) then
        if self.db.settings.includeGuildGold and self:IsGuildGoldIncluded(key) then
          totalGold = totalGold + (guild.gold or 0)
        end
        for tab, items in pairs(guild.tabs or {}) do
          if self:IsGuildTabIncluded(key, tab) then Add("guild", items) end
        end
      end
    end
  end
  local rows = {}
  for _, row in pairs(result) do
    row.name = row.name or (row.itemID and GetItemInfo(row.itemID)) or row.itemString
    if filter == "" or strfind(strlower(row.name or ""), filter, 1, true) then
      row.unitPrice = self:GetPrice(row.itemString) or 0
      row.value = row.unitPrice * row.total
      totalValue = totalValue + row.value
      rows[#rows + 1] = row
    end
  end
  local sortKey, descending = self.db.settings.sort, self.db.settings.descending
  table.sort(rows, function(a, b)
    local av, bv = a[sortKey] or 0, b[sortKey] or 0
    if sortKey == "name" then av, bv = strlower(a.name or ""), strlower(b.name or "") end
    if av == bv then return (a.name or "") < (b.name or "") end
    if descending then return av > bv else return av < bv end
  end)
  return rows, totalValue, totalGold
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    GoblinDB = GoblinDB or {}
    CopyDefaults(DEFAULTS, GoblinDB)
    SL.db = GoblinDB
  elseif event == "PLAYER_LOGIN" then
    SL:GetCharacter()
    SL:InitializeScanner()
    local uiOK, uiError = pcall(function() SL:InitializeUI() end)
    if not uiOK then
      print("|cffff5555Goblin UI error:|r " .. tostring(uiError))
    end
    SL:ScanBags()
    SL:ScanEquipped()
    SL:UpdateMoney()
  end
end)

SLASH_GOBLIN1 = "/goblin"
SLASH_GOBLIN2 = "/sl"
SLASH_GOBLIN3 = "/ledger"
SlashCmdList.GOBLIN = function() SL:ToggleUI() end
