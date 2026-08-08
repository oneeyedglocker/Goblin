local ADDON_NAME, SL = ...

SL.VERSION = "0.9.0"

-- Shared palette. Every module pulls its local color table from here so the
-- whole addon retints from one place. Goblin-green chrome, gold accents for
-- anything money-shaped.
local function hex(r, g, b) return { r / 255, g / 255, b / 255 } end
SL.THEME = {
  bgDeep    = hex(0x0d, 0x13, 0x10),  -- panel background
  bgPanel   = hex(0x12, 0x1a, 0x15),  -- inset background
  bgRow     = hex(0x18, 0x23, 0x1c),  -- row fill
  bgRowAlt  = hex(0x1e, 0x2b, 0x22),  -- alternating row fill
  chrome    = hex(0x2c, 0x45, 0x35),  -- title bar / footer
  edge      = hex(0x24, 0x35, 0x2a),  -- hairline borders
  active    = hex(0x3d, 0x63, 0x49),  -- buttons, controls
  activeAlt = hex(0xcf, 0xe3, 0xd4),  -- hover wash, scroll thumb
  text      = { 1, 1, 1 },
  textAlt   = hex(0xdf, 0xe8, 0xe0),
  dim       = hex(0x93, 0xa3, 0x96),
  subtle    = hex(0x6d, 0x7f, 0x72),
  dimmer    = hex(0x4a, 0x57, 0x4d),
  gold      = hex(0xff, 0xd8, 0x39),  -- accent / money / active tab
  green     = hex(0x4e, 0xe0, 0x7f),  -- fresh / healthy
  goblin    = hex(0x00, 0xfe, 0x00),  -- brand green (title, minimap G)
  orange    = hex(0xfd, 0x9e, 0x33),  -- stale / warning
  red       = hex(0xfc, 0x57, 0x57),  -- never / critical
  blue      = hex(0x8f, 0xb6, 0xf0),  -- guild
  purple    = hex(0xa6, 0x66, 0xd4),
}

-- ============================================================================
-- Theming
--
-- Every module aliases SL.THEME's colour tables by reference (COLORS.primary =
-- T.bgDeep and so on), so a preset switch only has to overwrite the *contents*
-- of these tables -- never replace them -- for every future read to pick up the
-- new value. Anything already painted is re-painted from the tint registry
-- below.
-- ============================================================================

-- Chrome sets. Accent colours (gold/green/orange/red/blue/purple) are picked
-- separately so any accent can ride on any chrome.
SL.THEME_PRESETS = {
  { key = "goblin", label = "Goblin Green", swatch = hex(0x2c, 0x45, 0x35), colors = {
      bgDeep = hex(0x0d, 0x13, 0x10), bgPanel = hex(0x12, 0x1a, 0x15), bgRow = hex(0x18, 0x23, 0x1c),
      bgRowAlt = hex(0x1e, 0x2b, 0x22), chrome = hex(0x2c, 0x45, 0x35), edge = hex(0x24, 0x35, 0x2a),
      active = hex(0x3d, 0x63, 0x49), activeAlt = hex(0xcf, 0xe3, 0xd4),
      textAlt = hex(0xdf, 0xe8, 0xe0), dim = hex(0x93, 0xa3, 0x96), subtle = hex(0x6d, 0x7f, 0x72),
      dimmer = hex(0x4a, 0x57, 0x4d), goblin = hex(0x00, 0xfe, 0x00) } },
  { key = "midnight", label = "Midnight", swatch = hex(0x2b, 0x33, 0x45), colors = {
      bgDeep = hex(0x0b, 0x0e, 0x14), bgPanel = hex(0x11, 0x15, 0x1e), bgRow = hex(0x17, 0x1c, 0x27),
      bgRowAlt = hex(0x1d, 0x23, 0x30), chrome = hex(0x2b, 0x33, 0x45), edge = hex(0x23, 0x2a, 0x39),
      active = hex(0x3a, 0x45, 0x5e), activeAlt = hex(0xcd, 0xd6, 0xe6),
      textAlt = hex(0xdd, 0xe3, 0xee), dim = hex(0x93, 0x9c, 0xad), subtle = hex(0x6c, 0x75, 0x86),
      dimmer = hex(0x48, 0x50, 0x5f), goblin = hex(0x6f, 0xc9, 0xff) } },
  { key = "slate", label = "Slate", swatch = hex(0x3a, 0x3d, 0x40), colors = {
      bgDeep = hex(0x0f, 0x10, 0x11), bgPanel = hex(0x16, 0x18, 0x19), bgRow = hex(0x1e, 0x20, 0x22),
      bgRowAlt = hex(0x26, 0x29, 0x2b), chrome = hex(0x3a, 0x3d, 0x40), edge = hex(0x2e, 0x31, 0x33),
      active = hex(0x4c, 0x50, 0x54), activeAlt = hex(0xd8, 0xda, 0xdc),
      textAlt = hex(0xe2, 0xe4, 0xe5), dim = hex(0x9c, 0x9f, 0xa1), subtle = hex(0x74, 0x77, 0x79),
      dimmer = hex(0x4e, 0x51, 0x53), goblin = hex(0xc8, 0xcc, 0xd0) } },
  { key = "obsidian", label = "Obsidian", swatch = hex(0x1c, 0x1c, 0x1e), colors = {
      bgDeep = hex(0x07, 0x07, 0x08), bgPanel = hex(0x0d, 0x0d, 0x0e), bgRow = hex(0x14, 0x14, 0x16),
      bgRowAlt = hex(0x1a, 0x1a, 0x1d), chrome = hex(0x1c, 0x1c, 0x1e), edge = hex(0x27, 0x27, 0x2a),
      active = hex(0x33, 0x33, 0x37), activeAlt = hex(0xd0, 0xd0, 0xd4),
      textAlt = hex(0xe6, 0xe6, 0xe8), dim = hex(0x96, 0x96, 0x9a), subtle = hex(0x6e, 0x6e, 0x72),
      dimmer = hex(0x47, 0x47, 0x4b), goblin = hex(0x00, 0xfe, 0x00) } },
  { key = "copper", label = "Copper", swatch = hex(0x4a, 0x34, 0x24), colors = {
      bgDeep = hex(0x13, 0x0e, 0x0a), bgPanel = hex(0x1b, 0x14, 0x0f), bgRow = hex(0x24, 0x1b, 0x14),
      bgRowAlt = hex(0x2d, 0x22, 0x19), chrome = hex(0x4a, 0x34, 0x24), edge = hex(0x38, 0x28, 0x1c),
      active = hex(0x6a, 0x4a, 0x33), activeAlt = hex(0xe6, 0xd6, 0xc6),
      textAlt = hex(0xef, 0xe3, 0xd8), dim = hex(0xa8, 0x99, 0x8b), subtle = hex(0x80, 0x71, 0x64),
      dimmer = hex(0x57, 0x4a, 0x3f), goblin = hex(0xff, 0xb4, 0x50) } },
}

SL.ACCENTS = {
  { key = "gold",   label = "Gold",   color = hex(0xff, 0xd8, 0x39) },
  { key = "green",  label = "Green",  color = hex(0x4e, 0xe0, 0x7f) },
  { key = "blue",   label = "Blue",   color = hex(0x6f, 0xb2, 0xff) },
  { key = "purple", label = "Purple", color = hex(0xb9, 0x7c, 0xf0) },
  { key = "teal",   label = "Teal",   color = hex(0x3f, 0xd4, 0xc4) },
  { key = "rose",   label = "Rose",   color = hex(0xff, 0x7d, 0x9c) },
  { key = "orange", label = "Orange", color = hex(0xfd, 0x9e, 0x33) },
  { key = "silver", label = "Silver", color = hex(0xd4, 0xd8, 0xdd) },
}

-- Tint registry. Every module's SetColor() helper hands its setter closure here
-- so a preset switch can re-run it against the mutated colour table. Panels
-- that throw their widgets away and rebuild on every refresh (Sources,
-- Coverage, Mail) suspend collection while they rebuild -- otherwise the
-- registry would grow without bound -- and simply get refreshed after a
-- theme change instead.
SL.tints = {}
SL.collectTints = true
local TINT_CAP = 6000

function SL.RegisterTint(setter, color, alpha)
  if not SL.collectTints then return end
  local list = SL.tints
  if #list >= TINT_CAP then return end
  list[#list + 1] = { setter = setter, color = color, alpha = alpha }
end

-- Run fn with tint collection suspended. Used by the rebuild-on-refresh panels.
function SL.WithoutTintCollection(fn, ...)
  local previous = SL.collectTints
  SL.collectTints = false
  local ok, err = pcall(fn, ...)
  SL.collectTints = previous
  if not ok then error(err, 0) end
end

local function WriteColor(target, source)
  if not target or not source then return end
  target[1], target[2], target[3] = source[1], source[2], source[3]
end

-- "ffd839" for a THEME colour table, for inline |cff.. escapes in text that
-- can't be re-tinted through the registry.
function SL.Hex(color)
  if not color then return "ffffff" end
  return string.format("%02x%02x%02x",
    math.floor(math.min(1, math.max(0, color[1])) * 255 + 0.5),
    math.floor(math.min(1, math.max(0, color[2])) * 255 + 0.5),
    math.floor(math.min(1, math.max(0, color[3])) * 255 + 0.5))
end

function SL:GetAppearance()
  local settings = self.db and self.db.settings
  return settings and settings.appearance or {}
end

function SL:GetPresetByKey(key)
  for _, preset in ipairs(self.THEME_PRESETS) do
    if preset.key == key then return preset end
  end
  return self.THEME_PRESETS[1]
end

function SL:GetAccentColor()
  local appearance = self:GetAppearance()
  if appearance.accent == "custom" and appearance.accentCustom then
    return appearance.accentCustom
  end
  for _, accent in ipairs(self.ACCENTS) do
    if accent.key == appearance.accent then return accent.color end
  end
  return self.ACCENTS[1].color
end

-- Opacity and scale don't touch the palette, so they get their own cheap path
-- rather than re-running the whole tint registry on every tick of a slider drag.
function SL:ApplyWindowSettings()
  local appearance = self:GetAppearance()
  local opacity, scale = appearance.opacity or 1, appearance.scale or 1
  if self.frame then self.frame:SetAlpha(opacity); self.frame:SetScale(scale) end
  if self.options then self.options:SetAlpha(opacity); self.options:SetScale(scale) end
  if self.appearanceFrame then self.appearanceFrame:SetScale(scale) end
end

-- Rewrite SL.THEME in place from the stored appearance settings, then re-paint
-- everything the tint registry knows about. Never replaces a colour table.
function SL:ApplyTheme(skipRefresh)
  local appearance = self:GetAppearance()
  local preset = self:GetPresetByKey(appearance.theme)
  for key, color in pairs(preset.colors) do WriteColor(self.THEME[key], color) end
  WriteColor(self.THEME.gold, self:GetAccentColor())

  for _, entry in ipairs(self.tints) do
    pcall(entry.setter, entry.color[1], entry.color[2], entry.color[3], entry.alpha or 1)
  end

  self:ApplyWindowSettings()
  if self.RefreshMinimapButton then self:RefreshMinimapButton() end
  if not skipRefresh and self.RefreshUI then self:RefreshUI() end
end

-- Mail lifetimes. Player-to-player mail sits in the recipient's inbox for
-- MAIL_RETURN_DAYS, bounces back to the sender for MAIL_GRACE_DAYS more, then
-- is destroyed. Auction-house and already-returned mail has no return leg --
-- its countdown runs straight to deletion.
SL.MAIL_RETURN_DAYS = 30
SL.MAIL_GRACE_DAYS = 30
SL.MAIL_URGENT_DAYS = 7

SL.CATEGORIES = { "bags", "bank", "equipped", "mail", "auctions", "guild" }
-- What a character's sources default to before the user has touched the
-- Sources matrix. Equipped is off because most worn gear is soulbound and
-- can't be sold, so counting it inflates a "what am I worth" number.
--
-- This used to be enforced by a second, invisible switch (settings.categories)
-- that BuildLedger checked in addition to the matrix. Nothing ever wrote to
-- it, so ticking "Equip" could never actually turn equipped on -- and because
-- the Summary tab only ever checked the matrix, the two tabs disagreed. The
-- matrix is now the only switch for character sources, and this table is
-- merely its starting position.
SL.DEFAULT_SOURCES = { bags = true, bank = true, equipped = false, mail = true, auctions = true }
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
    -- Only `guild` is still read -- it's the master switch for guild banks.
    -- The per-character entries are vestigial; character sources are governed
    -- by the Sources matrix (characterCategories) and seeded from
    -- SL.DEFAULT_SOURCES. Kept so old SavedVariables load unchanged.
    categories = { bags = true, bank = true, equipped = false, mail = true, auctions = true, guild = true },
    characters = {},
    characterCategories = {},
    characterGold = {},
    guilds = {},
    guildTabs = {},
    guildGold = {},
    sort = "value",
    descending = true,
    appearance = {
      theme = "goblin",
      accent = "gold",
      accentCustom = nil,
      opacity = 1,
      scale = 1,
      stripes = true,
      minimap = { shown = true, style = "coin", size = 30, radius = 5, locked = false, angle = -75, letter = true },
    },
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
  local value = settings and settings[category]
  if value == nil then return self.DEFAULT_SOURCES[category] ~= false end
  return value ~= false
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
            out[#out + 1] = { kind = "character", key = key, location = location, status = info.status, label = info.label, age = info.age, name = character.name, realm = character.realm }
          end
        end
      end
      if self:IsCharacterGoldIncluded(key) then
        local info = self:GetLocationFreshness(key, "gold")
        if info.status ~= "fresh" then
          out[#out + 1] = { kind = "character", key = key, location = "gold", status = info.status, label = info.label, age = info.age, name = character.name, realm = character.realm }
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
  -- Never-scanned first, then oldest, so the summary widget's short list is
  -- the list that actually needs attention.
  table.sort(out, function(a, b)
    local aNever, bNever = a.status == "never", b.status == "never"
    if aNever ~= bNever then return aNever end
    return (a.age or math.huge) > (b.age or math.huge)
  end)
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

-- 43865 -> "43,865". Big raw counts are unreadable without separators.
function SL.CommaNumber(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
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

-- Fingerprint of every setting that changes the net-worth total. History
-- snapshots record this so the trend widgets only ever compare two totals that
-- were computed from the same source selection -- toggling a guild bank off
-- used to look like an overnight crash.
-- How much is being held back by the soulbound switch. Reported in the Sources
-- footer so "why is my net worth lower than TSM's" has a visible answer.
function SL:GetSoulboundExcluded()
  local stacks, units = 0, 0
  local function scan(items)
    for _, item in pairs(items or {}) do
      local bound = item.boundCount or 0
      if bound > 0 then stacks = stacks + 1; units = units + bound end
    end
  end
  for key, character in pairs(self.db.characters or {}) do
    if self:IsCharacterIncluded(key) then
      for _, location in ipairs({ "bags", "bank", "equipped", "mail", "auctions" }) do
        if self:IsCharacterCategoryIncluded(key, location) then
          scan((character.locations or {})[location])
        end
      end
    end
  end
  if self.db.settings.categories.guild then
    for gkey, guild in pairs(self.db.guilds or {}) do
      if self:IsGuildIncluded(gkey) then
        for tab, items in pairs(guild.tabs or {}) do
          if self:IsGuildTabIncluded(gkey, tab) then scan(items) end
        end
      end
    end
  end
  return stacks, units
end

function SL:GetConfigFingerprint()
  local settings = self.db.settings
  local parts = {
    settings.priceSource or "?",
    settings.includeGold and "G1" or "G0",
    settings.includeGuildGold and "GG1" or "GG0",
    settings.includeSoulbound and "SB1" or "SB0",
  }
  -- Only guild is still a real switch here; the per-character locations are
  -- fingerprinted from the Sources matrix further down. Hashing the vestigial
  -- entries would just be hashing constants.
  parts[#parts + 1] = "guild" .. (settings.categories.guild and "1" or "0")
  local characterKeys = {}
  for key in pairs(self.db.characters or {}) do characterKeys[#characterKeys + 1] = key end
  table.sort(characterKeys)
  for _, key in ipairs(characterKeys) do
    local bits = { self:IsCharacterIncluded(key) and "1" or "0", self:IsCharacterGoldIncluded(key) and "1" or "0" }
    for _, location in ipairs({ "bags", "bank", "equipped", "mail", "auctions" }) do
      bits[#bits + 1] = self:IsCharacterCategoryIncluded(key, location) and "1" or "0"
    end
    parts[#parts + 1] = key .. ":" .. table.concat(bits)
  end
  local guildKeys = {}
  for key in pairs(self.db.guilds or {}) do guildKeys[#guildKeys + 1] = key end
  table.sort(guildKeys)
  for _, key in ipairs(guildKeys) do
    local bits = { self:IsGuildIncluded(key) and "1" or "0", self:IsGuildGoldIncluded(key) and "1" or "0" }
    local tabs = {}
    for tab in pairs((self.db.guilds[key] or {}).tabs or {}) do tabs[#tabs + 1] = tab end
    table.sort(tabs)
    for _, tab in ipairs(tabs) do bits[#bits + 1] = self:IsGuildTabIncluded(key, tab) and "1" or "0" end
    parts[#parts + 1] = key .. ":" .. table.concat(bits)
  end
  -- djb2. Only used for change detection, so collision resistance is a
  -- non-issue and a 32-bit rolling hash stays well inside double precision.
  local joined = table.concat(parts, "|")
  local hash = 5381
  for i = 1, #joined do hash = (hash * 33 + joined:byte(i)) % 4294967296 end
  return hash
end

-- True once TSM has answered at least one price query. Snapshots taken before
-- this would record a near-zero net worth and poison the trend line.
function SL:IsPricingReady()
  if not TSM_API or not TSM_API.GetCustomPriceValue then return false end
  local valid = self:ValidatePriceSource(self.db.settings.priceSource)
  return valid and true or false
end

-- Returns rows, filteredValue, gold, unfilteredValue.
--
-- filteredValue only counts rows matching the search box; unfilteredValue is
-- the true item value of every included source. History snapshots MUST use the
-- unfiltered figure -- recording the filtered one meant that leaving a word in
-- the search box while the ledger refreshed wrote a near-zero net worth into
-- the trend line.
function SL:BuildLedger(filter)
  local result, totalValue, totalGold, grandValue = {}, 0, 0, 0
  filter = strlower(strtrim(filter or ""))
  -- Gating is the caller's job: character locations are gated by the Sources
  -- matrix, guild tabs by the guild switches. There is deliberately no second
  -- global check here any more.
  local function Add(location, items)
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
    row.unitPrice = self:GetPrice(row.itemString) or 0
    row.value = row.unitPrice * row.total
    grandValue = grandValue + row.value
    if filter == "" or strfind(strlower(row.name or ""), filter, 1, true) then
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
  return rows, totalValue, totalGold, grandValue
end

-- Every distinct item TSM has no price for, with where it lives and how many
-- there are. The Summary tile says "1 with no price" and used to leave you no
-- way to find out which item that was.
function SL:GetUnpricedItems()
  local out, index = {}, {}
  local function note(itemString, item, where, count)
    if count <= 0 then return end
    local row = index[itemString]
    if not row then
      row = { itemString = itemString, itemID = item.itemID, link = item.link,
              name = item.name, count = 0, places = {} }
      index[itemString] = row
      out[#out + 1] = row
    end
    row.count = row.count + count
    row.name = row.name or item.name
    row.link = row.link or item.link
    row.places[#row.places + 1] = string.format("%s (%d)", where, count)
  end
  local function scan(items, where)
    for itemString, item in pairs(items or {}) do
      local count = item.count or 0
      if not self.db.settings.includeSoulbound then
        count = math.max(0, count - (item.boundCount or 0))
      end
      if count > 0 and (self:GetPrice(itemString) or 0) == 0 then
        note(itemString, item, where, count)
      end
    end
  end
  for key, character in pairs(self.db.characters or {}) do
    if self:IsCharacterIncluded(key) then
      for _, location in ipairs({ "bags", "bank", "equipped", "mail", "auctions" }) do
        if self:IsCharacterCategoryIncluded(key, location) then
          scan((character.locations or {})[location], string.format("%s %s", character.name or key, location))
        end
      end
    end
  end
  if self.db.settings.categories.guild then
    for gkey, guild in pairs(self.db.guilds or {}) do
      if self:IsGuildIncluded(gkey) then
        for tab, items in pairs(guild.tabs or {}) do
          if self:IsGuildTabIncluded(gkey, tab) then
            scan(items, string.format("<%s> tab %s", guild.name or gkey, tostring(tab)))
          end
        end
      end
    end
  end
  for _, row in ipairs(out) do
    row.name = row.name or (row.itemID and GetItemInfo(row.itemID)) or row.itemString
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
end

function SL:PrintUnpricedItems()
  local rows = self:GetUnpricedItems()
  if #rows == 0 then
    print("|cffffd839Goblin:|r every counted item has a price under |cffffffff" .. tostring(self.db.settings.priceSource) .. "|r.")
    return
  end
  print(string.format("|cffffd839Goblin — %d item type%s with no %s price:|r",
    #rows, #rows == 1 and "" or "s", tostring(self.db.settings.priceSource)))
  for _, row in ipairs(rows) do
    print(string.format("  %s |cff9c9c9cx%d|r — %s", row.link or row.name or row.itemString,
      row.count, table.concat(row.places, ", ")))
  end
  print("|cffababab  usually vendor trash, quest/conjured items, or something the AH has never seen.|r")
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    GoblinDB = GoblinDB or {}
    CopyDefaults(DEFAULTS, GoblinDB)
    SL.db = GoblinDB
    -- Minimap settings used to live under db.window.minimap. Fold anything
    -- found there into settings.appearance.minimap once, then leave the old
    -- table alone so downgrading doesn't lose the icon position.
    local legacy = GoblinDB.window and GoblinDB.window.minimap
    if legacy and not GoblinDB.settings.appearance.minimapMigrated then
      local target = GoblinDB.settings.appearance.minimap
      if legacy.angle then target.angle = legacy.angle end
      if legacy.hidden ~= nil then target.shown = not legacy.hidden end
      GoblinDB.settings.appearance.minimapMigrated = true
    end
    SL:ApplyTheme(true)
  elseif event == "PLAYER_LOGIN" then
    SL:GetCharacter()
    SL:InitializeScanner()
    SL:InitializeMailLedger()
    local uiOK, uiError = pcall(function() SL:InitializeUI() end)
    if not uiOK then
      print("|cffff5555Goblin UI error:|r " .. tostring(uiError))
    end
    if SL.CreateMinimapButton then pcall(function() SL:CreateMinimapButton() end) end
    pcall(function() SL:ApplyTheme(true) end)
    SL:ScanBags()
    SL:ScanEquipped()
    SL:UpdateMoney()
    -- Item data may not be cached the instant we log in, and bind state is
    -- read from it. Re-scan once the client has had a moment to fill in.
    if C_Timer and C_Timer.After then
      C_Timer.After(5, function() pcall(function() SL:ScanEquipped() end) end)
    end
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
      -- Only warn about never-scanned for locations that reliably have
      -- content on any active character. Auctions/mail/bank stay silent
      -- when never-scanned because most alts genuinely have none of those
      -- and the warning was pure noise.
      local warnOnNever = (loc == "bags" or loc == "equipped")
      if charEnabled and enabled and not lastScanned and warnOnNever then
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
  local function ageStr(t) return t and self:FormatAge(time() - t) or "|cffff5555never|r" end
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
  if head == "mail" then
    if strlower(tail or "") == "transit" then SL:PrintMailTransitSummary() else SL:PrintMailReport() end
  elseif head == "transit" then SL:PrintMailTransitSummary()
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
  elseif head == "unpriced" or head == "noprice" then SL:PrintUnpricedItems()
  elseif head == "appearance" or head == "config" or head == "options" then
    if SL.ToggleAppearance then SL:ToggleAppearance() end
  elseif head == "history" then
    local sub = strlower(tail or "")
    if sub == "reset" then SL:ResetHistory()
    elseif sub == "prune" then SL:PruneHistory()
    elseif sub == "why" then SL:ExplainTrend()
    else print("|cffffd839Goblin:|r history reset | prune | why") end
  elseif head == "rescan" then
    if GetGuildInfo and GetGuildInfo("player") then
      print("|cffffd839Goblin:|r wiping stored guild-bank contents and re-querying. Keep the guild bank open.")
      SL:ForceRescanCurrentGuildBank()
    else print("|cffffd839Goblin:|r not in a guild.") end
  elseif head == "help" or head == "?" then
    print("|cffffd839Goblin commands:|r")
    print("  /goblin — toggle the ledger")
    print("  /goblin net — print current net worth")
    print("  /goblin mail — every tracked mail, where it sits, and its expiry clocks")
    print("  /goblin mail transit — only shipments Goblin hooked but hasn't confirmed")
    print("  /goblin stale — list unscanned/stale sources")
    print("  /goblin trace <name> — show every source Goblin has for an item")
    print("  /goblin coverage — per-character/guild source scan status and warnings")
    print("  /goblin coverage all — same but also lists fresh, priced sources")
    print("  /goblin diff [threshold] — per-item Goblin vs TSM NumInventory diff (default threshold 0)")
    print("  /goblin unpriced — every item TSM has no price for, and where it lives")
    print("  /goblin appearance — theme, accent, minimap icon and window options")
    print("  /goblin history why — explain exactly what the 7-day trend is comparing")
    print("  /goblin history prune — drop snapshots taken under a different source selection")
    print("  /goblin history reset — clear the net-worth trend line and start fresh")
    print("  /goblin rescan — wipe current guild bank cache and re-query")
  else SL:ToggleUI() end
end
