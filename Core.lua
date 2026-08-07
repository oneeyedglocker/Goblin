local ADDON_NAME, SL = ...

SL.VERSION = "0.6.0"
SL.CATEGORIES = { "bags", "bank", "equipped", "mail", "auctions", "guild" }
SL.CATEGORY_LABELS = {
  bags = "Bags", bank = "Bank", equipped = "Equipped", mail = "Mail",
  auctions = "Auctions", guild = "Guild",
}
-- Per-source stale thresholds. bags/equipped tick constantly at login; bank,
-- mail, auctions and guild only refresh when the player visits them, so their
-- freshness bar is more generous.
SL.STALE_SECONDS = {
  bags = 1 * 86400, equipped = 1 * 86400, gold = 1 * 86400,
  bank = 7 * 86400, mail = 7 * 86400, auctions = 3 * 86400,
  guildTab = 14 * 86400, guildGold = 14 * 86400,
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
  mailTransit = {},
  history = {},
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

local function FormatAge(seconds)
  if not seconds then return "never" end
  if seconds < 60 then return "just now" end
  if seconds < 3600 then return string.format("%dm ago", math.floor(seconds / 60)) end
  if seconds < 86400 then return string.format("%dh ago", math.floor(seconds / 3600)) end
  return string.format("%dd ago", math.floor(seconds / 86400))
end

SL.FormatAge = function(_, seconds) return FormatAge(seconds) end

local function FreshnessStatus(stamp, threshold)
  if not stamp then return "never", nil end
  local age = time() - stamp
  if threshold and age >= threshold then return "stale", age end
  return "fresh", age
end

function SL:GetLocationFreshness(characterKey, location)
  local character = self.db.characters and self.db.characters[characterKey]
  if not character then return { status = "never" } end
  local stamp
  if location == "gold" then stamp = character.moneyUpdated
  else stamp = character.updated and character.updated[location] end
  local status, age = FreshnessStatus(stamp, self.STALE_SECONDS[location] or self.STALE_SECONDS[location == "gold" and "gold" or "bags"])
  return { status = status, age = age, stamp = stamp, label = FormatAge(age) }
end

function SL:GetGuildFreshness(guildKey, tab)
  local guild = self.db.guilds and self.db.guilds[guildKey]
  if not guild then return { status = "never" } end
  local stamp
  if tab == "gold" then stamp = guild.goldUpdated or guild.updated
  elseif tab then stamp = guild.tabUpdated and guild.tabUpdated[tab]
  else stamp = guild.updated end
  local threshold = self.STALE_SECONDS[tab == "gold" and "guildGold" or "guildTab"]
  local status, age = FreshnessStatus(stamp, threshold)
  return { status = status, age = age, stamp = stamp, label = FormatAge(age) }
end

-- Returns { {kind="character"|"guildTab", key=..., location=..., label=...}, ... }
-- for every source that has never been scanned or is stale.
function SL:GetStaleSources()
  local out = {}
  for key, character in pairs(self.db.characters or {}) do
    if self:IsCharacterIncluded(key) then
      for _, location in ipairs(self.CATEGORIES) do
        if location ~= "guild" and self:IsCharacterCategoryIncluded(key, location) then
          local info = self:GetLocationFreshness(key, location)
          if info.status ~= "fresh" then
            out[#out + 1] = { kind = "character", key = key, location = location, status = info.status, label = info.label, name = character.name, realm = character.realm }
          end
        end
      end
      if self:IsCharacterGoldIncluded(key) then
        local info = self:GetLocationFreshness(key, "gold")
        if info.status ~= "fresh" then
          out[#out + 1] = { kind = "character", key = key, location = "gold", status = info.status, label = info.label, name = character.name, realm = character.realm }
        end
      end
    end
  end
  for key, guild in pairs(self.db.guilds or {}) do
    if self:IsGuildIncluded(key) then
      local tabs = {}
      for tab in pairs(guild.tabs or {}) do tabs[#tabs + 1] = tab end
      table.sort(tabs)
      for _, tab in ipairs(tabs) do
        if self:IsGuildTabIncluded(key, tab) then
          local info = self:GetGuildFreshness(key, tab)
          if info.status ~= "fresh" then
            out[#out + 1] = { kind = "guildTab", key = key, location = tab, status = info.status, label = info.label, guildName = guild.name }
          end
        end
      end
      if self:IsGuildGoldIncluded(key) then
        local info = self:GetGuildFreshness(key, "gold")
        if info.status ~= "fresh" then
          out[#out + 1] = { kind = "guildTab", key = key, location = "gold", status = info.status, label = info.label, guildName = guild.name }
        end
      end
    end
  end
  return out
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
  if self.PruneMailTransit then self:PruneMailTransit() end
  local transitByCharacter, transitGold = {}, {}
  if self.CollectMailTransit then transitByCharacter, transitGold = self:CollectMailTransit() end
  for key, character in pairs(self.db.characters) do
    if self:IsCharacterIncluded(key) then
      if self.db.settings.includeGold and self:IsCharacterGoldIncluded(key) then
        totalGold = totalGold + (character.gold or 0)
        totalGold = totalGold + (transitGold[key] or 0)
      end
      for _, location in ipairs(self.CATEGORIES) do
        if location ~= "guild" and self:IsCharacterCategoryIncluded(key, location) then
          Add(location, character.locations and character.locations[location])
        end
      end
      if self:IsCharacterCategoryIncluded(key, "mail") then
        Add("mail", transitByCharacter[key])
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
    SL:InitializeMailLedger()
    local uiOK, uiError = pcall(function() SL:InitializeUI() end)
    if not uiOK then
      print("|cffff5555Goblin UI error:|r " .. tostring(uiError))
    end
    if SL.CreateMinimapButton then pcall(function() SL:CreateMinimapButton() end) end
    SL:ScanBags()
    SL:ScanEquipped()
    SL:UpdateMoney()
  end
end)

local CHARACTER_SOURCES = { "bags", "bank", "equipped", "mail", "auctions" }

-- Structured picture of every character/guild source, what's enabled, when
-- it was last scanned, how many items live there, and how many of those
-- have no TSM price (and therefore contribute 0 to net worth).
function SL:GetCoverageReport()
  local report = { characters = {}, guilds = {}, warnings = {}, totals = { itemsPriced = 0, itemsUnpriced = 0 } }
  local now = time()
  local function scanBucket(items)
    local itemCount, unpricedCount, unpricedTotal = 0, 0, 0
    for itemString, item in pairs(items or {}) do
      local count = item.count or 0
      if count > 0 then
        itemCount = itemCount + 1
        local price = self:GetPrice(itemString) or 0
        if not price or price == 0 then
          unpricedCount = unpricedCount + 1
          unpricedTotal = unpricedTotal + count
          report.totals.itemsUnpriced = report.totals.itemsUnpriced + 1
        else
          report.totals.itemsPriced = report.totals.itemsPriced + 1
        end
      end
    end
    return itemCount, unpricedCount, unpricedTotal
  end
  for key, character in pairs(self.db.characters or {}) do
    local charEnabled = self:IsCharacterIncluded(key)
    local row = {
      key = key, name = character.name, realm = character.realm,
      class = character.class, enabled = charEnabled,
      gold = { enabled = self:IsCharacterGoldIncluded(key), amount = character.gold or 0, updatedAt = character.moneyUpdated },
      sources = {},
    }
    for _, loc in ipairs(CHARACTER_SOURCES) do
      local items = character.locations and character.locations[loc]
      local itemCount, unpricedCount = scanBucket(items)
      local lastScanned = character.updated and character.updated[loc]
      local enabled = self:IsCharacterCategoryIncluded(key, loc)
      local src = { name = loc, enabled = enabled, lastScanned = lastScanned, itemCount = itemCount, unpricedCount = unpricedCount }
      row.sources[#row.sources + 1] = src
      if charEnabled and enabled and not lastScanned then
        report.warnings[#report.warnings + 1] = string.format("%s: %s never scanned — visit the location once", key, loc)
      elseif itemCount > 0 and (not charEnabled or not enabled) then
        report.warnings[#report.warnings + 1] = string.format("%s: %s has %d item(s) but %s — those won't count",
          key, loc, itemCount, charEnabled and "the source pill is off" or "the character is disabled")
      end
    end
    report.characters[#report.characters + 1] = row
  end
  for key, guild in pairs(self.db.guilds or {}) do
    local gEnabled = self:IsGuildIncluded(key)
    local row = { key = key, name = guild.name, realm = guild.realm, enabled = gEnabled,
      gold = { enabled = self:IsGuildGoldIncluded(key), amount = guild.gold or 0, updatedAt = guild.goldUpdated },
      tabs = {}, }
    local tabs = {}
    for tab in pairs(guild.tabs or {}) do tabs[#tabs + 1] = tab end
    table.sort(tabs)
    for _, tab in ipairs(tabs) do
      local itemCount, unpricedCount = scanBucket(guild.tabs[tab])
      local lastScanned = guild.tabUpdated and guild.tabUpdated[tab]
      local enabled = self:IsGuildTabIncluded(key, tab)
      row.tabs[#row.tabs + 1] = { index = tab, name = (guild.tabNames and guild.tabNames[tab]) or ("Tab " .. tab),
        enabled = enabled, lastScanned = lastScanned, itemCount = itemCount, unpricedCount = unpricedCount }
      if gEnabled and enabled and not lastScanned then
        report.warnings[#report.warnings + 1] = string.format("<%s> tab %d never scanned — open the guild bank once", guild.name or key, tab)
      elseif itemCount > 0 and (not gEnabled or not enabled) then
        report.warnings[#report.warnings + 1] = string.format("<%s> tab %d has %d item(s) but %s", guild.name or key, tab, itemCount, gEnabled and "the tab is off" or "the guild is disabled")
      end
    end
    report.guilds[#report.guilds + 1] = row
  end
  return report
end

function SL:PrintCoverageReport(mode)
  local report = self:GetCoverageReport()
  local showAll = mode == "all"
  local function ageStr(t) return t and (self:FormatAge(time() - t) .. " ago") or "|cffff5555never|r" end
  local function fmtCount(itemCount, unpricedCount)
    if itemCount == 0 then return "|cff787878empty|r" end
    if unpricedCount > 0 then return string.format("%d items, |cffff9d33%d unpriced|r", itemCount, unpricedCount) end
    return string.format("%d items", itemCount)
  end
  print(string.format("|cffffd839Goblin coverage report|r  (%d priced / %d unpriced items in DB)",
    report.totals.itemsPriced, report.totals.itemsUnpriced))
  for _, char in ipairs(report.characters) do
    print(string.format("  |cffffffff%s|r%s   gold %s (%s)",
      char.key, char.enabled and "" or " |cff787878DISABLED|r",
      self:FormatMoney(char.gold.amount), ageStr(char.gold.updatedAt)))
    for _, src in ipairs(char.sources) do
      local off = src.enabled and "" or " |cff787878off|r"
      if showAll or (not src.lastScanned) or (src.itemCount == 0) or (src.unpricedCount > 0) or not src.enabled then
        print(string.format("    %-8s  %-18s  %s%s", src.name, fmtCount(src.itemCount, src.unpricedCount), ageStr(src.lastScanned), off))
      end
    end
  end
  for _, guild in ipairs(report.guilds) do
    print(string.format("  |cff8fb6f0<%s>|r%s   guild gold %s (%s)",
      guild.name or guild.key, guild.enabled and "" or " |cff787878DISABLED|r",
      self:FormatMoney(guild.gold.amount), ageStr(guild.gold.updatedAt)))
    for _, tab in ipairs(guild.tabs) do
      local off = tab.enabled and "" or " |cff787878off|r"
      if showAll or (not tab.lastScanned) or (tab.unpricedCount > 0) or not tab.enabled then
        print(string.format("    tab %d %-14s  %-18s  %s%s", tab.index, tab.name, fmtCount(tab.itemCount, tab.unpricedCount), ageStr(tab.lastScanned), off))
      end
    end
  end
  if #report.warnings > 0 then
    print("|cffff9d33Warnings:|r")
    for _, w in ipairs(report.warnings) do print("  " .. w) end
  else
    print("|cff30d97fNo coverage issues detected.|r")
  end
  if not showAll then print("  |cffababab(use /goblin coverage all to also show fresh, priced sources)|r") end
end

-- Item-by-item comparison against TSM's canonical NumInventory count. Returns
-- discrepancies sorted by absolute delta so the biggest gaps float to the top.
function SL:BuildTSMDiff(threshold)
  threshold = tonumber(threshold) or 0
  local result = { matches = 0, discrepancies = {}, tsmOnly = {}, error = nil }
  if not (TSM_API and TSM_API.GetCustomPriceValue) then
    result.error = "TSM_API not available. Ensure TradeSkillMaster is loaded."
    return result
  end
  local goblinTotals, goblinNames, goblinLinks = {}, {}, {}
  local function tally(bucket)
    for itemString, item in pairs(bucket or {}) do
      local count = item.count or 0
      if count > 0 then
        goblinTotals[itemString] = (goblinTotals[itemString] or 0) + count
        goblinNames[itemString] = goblinNames[itemString] or item.name or item.itemString
        goblinLinks[itemString] = goblinLinks[itemString] or item.link
      end
    end
  end
  for _, character in pairs(self.db.characters or {}) do
    for _, items in pairs(character.locations or {}) do tally(items) end
  end
  for _, guild in pairs(self.db.guilds or {}) do
    for _, tab in pairs(guild.tabs or {}) do tally(tab) end
  end
  for _, record in pairs(self.db.mailTransit or {}) do
    if record.status == "pending" then tally(record.items) end
  end
  for itemString, goblinCount in pairs(goblinTotals) do
    local ok, tsmCount = pcall(TSM_API.GetCustomPriceValue, "NumInventory", itemString)
    tsmCount = ok and tonumber(tsmCount) or nil
    if tsmCount then
      local delta = tsmCount - goblinCount
      if math.abs(delta) <= threshold then
        result.matches = result.matches + 1
      else
        result.discrepancies[#result.discrepancies + 1] = {
          itemString = itemString, name = goblinNames[itemString], link = goblinLinks[itemString],
          goblin = goblinCount, tsm = tsmCount, delta = delta,
        }
      end
    end
  end
  table.sort(result.discrepancies, function(a, b) return math.abs(a.delta) > math.abs(b.delta) end)
  return result
end

function SL:PrintTSMDiff(threshold, limit)
  limit = tonumber(limit) or 40
  local diff = self:BuildTSMDiff(threshold)
  if diff.error then print("|cffff5555Goblin:|r " .. diff.error); return end
  print(string.format("|cffffd839Goblin vs TSM diff|r  (%d items match within %d, %d differ)",
    diff.matches, tonumber(threshold) or 0, #diff.discrepancies))
  if #diff.discrepancies == 0 then
    print("|cff30d97fEverything Goblin knows about matches TSM's NumInventory.|r")
    return
  end
  local shown = 0
  for _, row in ipairs(diff.discrepancies) do
    shown = shown + 1
    if shown > limit then
      print(string.format("  |cffababab… %d more|r  (use /goblin diff %s %d to see all)",
        #diff.discrepancies - limit, tostring(threshold or 0), #diff.discrepancies))
      break
    end
    local color = row.delta > 0 and "|cffff9d33" or "|cff8fb6f0"
    print(string.format("  %s%+d|r  Goblin %d ↔ TSM %d   %s",
      color, row.delta, row.goblin, row.tsm, row.link or row.name or row.itemString))
  end
  print("|cffababab  positive delta = TSM sees more than Goblin (Goblin missing items)|r")
end

function SL:TraceItem(term)
  term = strlower(strtrim(term or ""))
  if term == "" then print("|cffffd839Goblin:|r usage: /goblin trace <item name or itemID>"); return end
  local matches = 0
  local function nameOf(item)
    return (item and (item.name or (item.itemID and GetItemInfo(item.itemID)))) or item.itemString or ""
  end
  local function match(item) return item and strfind(strlower(nameOf(item)), term, 1, true) end
  for key, character in pairs(self.db.characters or {}) do
    for location, items in pairs(character.locations or {}) do
      for _, item in pairs(items) do
        if match(item) then
          matches = matches + 1
          print(string.format("  |cffababab%s|r %s: %s x%d (bound %d)", key, location, item.link or nameOf(item), item.count or 0, item.boundCount or 0))
        end
      end
    end
  end
  for key, guild in pairs(self.db.guilds or {}) do
    for tab, items in pairs(guild.tabs or {}) do
      for _, item in pairs(items) do
        if match(item) then
          matches = matches + 1
          local tabName = (guild.tabNames and guild.tabNames[tab]) or ("Tab " .. tab)
          print(string.format("  |cff8fb6f0<%s>|r %s: %s x%d", guild.name or key, tabName, item.link or nameOf(item), item.count or 0))
        end
      end
    end
  end
  for _, record in pairs(self.db.mailTransit or {}) do
    if record.status == "pending" then
      for _, item in pairs(record.items or {}) do
        if match(item) then
          matches = matches + 1
          print(string.format("  |cff9fd39fmail-transit|r %s → %s: %s x%d (sent %ds ago)",
            record.senderName or "?", record.recipientName or "?", item.link or nameOf(item),
            item.count or 0, time() - (record.sentAt or 0)))
        end
      end
    end
  end
  print(string.format("|cffffd839Goblin trace|r for \"%s\": %d source(s)", term, matches))
end

SLASH_GOBLIN1 = "/goblin"
SLASH_GOBLIN2 = "/sl"
SLASH_GOBLIN3 = "/ledger"
SlashCmdList.GOBLIN = function(msg)
  msg = strtrim(msg or "")
  local head, tail = msg:match("^(%S+)%s*(.*)$")
  head = head and strlower(head) or ""
  if head == "mail" or head == "transit" then SL:PrintMailTransitSummary()
  elseif head == "stale" or head == "diag" then
    local stale = SL:GetStaleSources()
    print("|cffffd839Goblin unscanned/stale sources:|r " .. #stale)
    for _, entry in ipairs(stale) do
      if entry.kind == "character" then
        print(string.format("  |cffababab%s|r %s — %s", entry.name or entry.key, entry.location, entry.label or entry.status))
      else
        print(string.format("  |cff8fb6f0<%s>|r tab %s — %s", entry.guildName or entry.key, tostring(entry.location), entry.label or entry.status))
      end
    end
  elseif head == "trace" or head == "find" then SL:TraceItem(tail)
  elseif head == "net" or head == "worth" then
    local _, itemValue, gold = SL:BuildLedger("")
    local itemCount = 0
    for _, character in pairs(SL.db.characters or {}) do
      for _, items in pairs(character.locations or {}) do
        for _, item in pairs(items) do
          if (item.count or 0) > 0 then itemCount = itemCount + (item.count or 0) end
        end
      end
    end
    for _, guild in pairs(SL.db.guilds or {}) do
      for _, tab in pairs(guild.tabs or {}) do
        for _, item in pairs(tab) do
          if (item.count or 0) > 0 then itemCount = itemCount + (item.count or 0) end
        end
      end
    end
    print(string.format("|cffffd839Goblin net worth:|r %s  (items %s + gold %s, %d item(s) counted)",
      SL:FormatMoney(itemValue + gold), SL:FormatMoney(itemValue), SL:FormatMoney(gold), itemCount))
  elseif head == "coverage" or head == "check" then SL:PrintCoverageReport(strlower(tail or ""))
  elseif head == "diff" or head == "tsm" then
    local a, b = tail:match("^(%S*)%s*(%S*)$")
    SL:PrintTSMDiff(a ~= "" and a or nil, b ~= "" and b or nil)
  elseif head == "rescan" then
    if GetGuildInfo and GetGuildInfo("player") then
      print("|cffffd839Goblin:|r wiping stored guild-bank contents and re-querying. Keep the guild bank open.")
      SL:ForceRescanCurrentGuildBank()
    else print("|cffffd839Goblin:|r not in a guild.") end
  elseif head == "help" or head == "?" then
    print("|cffffd839Goblin commands:|r")
    print("  /goblin — toggle the ledger")
    print("  /goblin net — print current net worth")
    print("  /goblin mail — list in-flight mail shipments")
    print("  /goblin stale — list unscanned/stale sources")
    print("  /goblin trace <name> — show every source Goblin has for an item")
    print("  /goblin coverage — per-character/guild source scan status and warnings")
    print("  /goblin coverage all — same but also lists fresh, priced sources")
    print("  /goblin diff [threshold] — per-item Goblin vs TSM NumInventory diff (default threshold 0)")
    print("  /goblin rescan — wipe current guild bank cache and re-query")
  else SL:ToggleUI() end
end
