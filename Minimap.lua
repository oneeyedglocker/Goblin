local _, SL = ...

-- Custom minimap button. Standard circular-track math with click-and-drag
-- repositioning; no LibDBIcon dep so Goblin stays a single-folder addon.
--
-- Every layer for every style is created once and then shown or hidden by
-- PaintMinimapStyle, so switching styles from the Appearance panel is
-- instantaneous and never leaks textures. The same paint routine drives the
-- style previews in that panel, which is why a preview is guaranteed to look
-- exactly like what you end up with.

-- Circular alpha mask shipped with the client; used to round off the flat
-- WHITE8X8 fills that make up the drawn styles.
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

SL.MINIMAP_STYLES = {
  { key = "coin",    label = "Gold coin",  note = "Struck coin, Goblin G" },
  { key = "minimal", label = "Minimal",    note = "Dark disc, accent ring" },
  { key = "badge",   label = "Badge",      note = "Solid accent disc" },
  { key = "pouch",   label = "Coin pouch", note = "Game artwork" },
  { key = "gem",     label = "Emerald",    note = "Game artwork" },
  { key = "classic", label = "Coin",       note = "Game artwork" },
}

local STYLE_ICONS = {
  pouch   = "Interface\\Icons\\INV_Misc_Coinbag_special",
  gem     = "Interface\\Icons\\INV_Misc_Gem_Emerald_02",
  classic = "Interface\\Icons\\INV_Misc_Coin_01",
}

local function Settings()
  local appearance = SL:GetAppearance()
  appearance.minimap = appearance.minimap
    or { shown = true, style = "coin", size = 30, radius = 5, locked = false, angle = -75 }
  return appearance.minimap
end

local function ComputePosition(angleDeg, radiusOffset)
  local Minimap = _G.Minimap
  if not Minimap then return 0, 0 end
  local radius = Minimap:GetWidth() / 2 + (radiusOffset or 5)
  local a = math.rad(angleDeg or -75)
  return math.cos(a) * radius, math.sin(a) * radius
end

local function UpdatePosition(button)
  local settings = Settings()
  local x, y = ComputePosition(settings.angle, settings.radius)
  button:ClearAllPoints()
  button:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

local function ShowTooltip(button)
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:AddLine("|cff" .. SL.Hex(SL.THEME.goblin) .. "Goblin|r")
  local _, itemValue, gold = SL:BuildLedger("")
  local netWorth = (itemValue or 0) + (gold or 0)
  GameTooltip:AddDoubleLine("Net worth", SL:FormatMoney(netWorth), 1, 1, 1, 1, 0.85, 0.22)
  GameTooltip:AddDoubleLine("Gold", SL:FormatMoney(gold or 0), 0.9, 0.9, 0.9, 1, 0.85, 0.22)
  GameTooltip:AddDoubleLine("Items", SL:FormatMoney(itemValue or 0), 0.9, 0.9, 0.9, 1, 0.85, 0.22)
  local urgent, soonest = 0, nil
  if SL.GetMailUrgency then urgent, soonest = SL:GetMailUrgency() end
  if urgent > 0 then
    local when = soonest and soonest < 1 and "under a day" or string.format("%dd", math.floor(soonest or 0))
    GameTooltip:AddDoubleLine(string.format("|cffff9933%d mail expiring|r", urgent), "soonest " .. when, 1, 1, 1, 0.99, 0.62, 0.20)
  end
  local stale = SL.GetStaleSources and SL:GetStaleSources() or {}
  if #stale > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("|cffff9933%d source%s stale|r", #stale, #stale == 1 and "" or "s"))
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("|cffababab Left-click:|r Toggle ledger", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("|cffababab Right-click:|r Sources", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("|cffababab Shift-right-click:|r Appearance", 0.7, 0.7, 0.7)
  if not Settings().locked then
    GameTooltip:AddLine("|cffababab Drag:|r Reposition", 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end

-- One masked WHITE8X8 disc. Also reports whether masking worked -- on clients
-- without Texture:SetMask a square fill would show as a box, so the drawn
-- styles fall back to game artwork instead.
local function CreateDisc(target, layer, level)
  local tex = target:CreateTexture(nil, layer, nil, level)
  tex:SetTexture("Interface\\Buttons\\WHITE8X8")
  local masked = tex.SetMask and pcall(tex.SetMask, tex, CIRCLE_MASK) or false
  return tex, masked
end

local function InsetDisc(tex, inset)
  tex:ClearAllPoints()
  tex:SetPoint("TOPLEFT", inset, -inset)
  tex:SetPoint("BOTTOMRIGHT", -inset, inset)
end

-- Build the full layer set for one icon. Shared by the real minimap button and
-- the Appearance panel's style previews.
local function BuildParts(target)
  local parts = {}
  target.parts = parts
  parts.ring = target:CreateTexture(nil, "BORDER")
  local discA, masked = CreateDisc(target, "BACKGROUND", 1)
  target.masked = masked
  parts.discA = discA
  parts.discB = CreateDisc(target, "BACKGROUND", 2)
  parts.discC = CreateDisc(target, "BORDER", 1)
  parts.sheen = CreateDisc(target, "ARTWORK", 1)
  parts.icon = target:CreateTexture(nil, "BACKGROUND", nil, 3)

  local shadow = target:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  shadow:SetPoint("CENTER", 1, -1); shadow:SetText("G")
  local letter = target:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  letter:SetPoint("CENTER", 0, 0); letter:SetText("G")
  local fontPath = letter:GetFont()
  letter.fontPath, shadow.fontPath = fontPath, fontPath
  parts.shadow, parts.letter = shadow, letter
  return parts
end

function SL:ResolveMinimapStyle(target, style)
  style = style or "coin"
  local known = STYLE_ICONS[style] or style == "coin" or style == "minimal" or style == "badge"
  if not known then style = "coin" end
  if target and not target.masked and (style == "coin" or style == "minimal" or style == "badge") then
    style = "classic"
  end
  return style
end

-- Pure paint: draws `style` at `size` into a target set up by BuildParts.
-- Knows nothing about saved settings or positioning. Returns the ring size so
-- callers can match their hover art to it.
--
-- `showLetter` only applies to the game-artwork styles -- the three drawn
-- styles always carry the G because it *is* the icon. Over artwork the letter
-- is set slightly smaller with a heavier outline, so it reads against a busy
-- 30px icon without burying it.
function SL:PaintMinimapStyle(target, style, size, showLetter)
  local parts = target.parts
  if not parts then return 0 end
  style = self:ResolveMinimapStyle(target, style)
  size = math.max(18, math.min(48, tonumber(size) or 30))
  target:SetSize(size, size)
  for _, part in pairs(parts) do part:Hide() end

  local accent = self.THEME.gold
  local brand = self.THEME.goblin
  local ringScale = size * 1.74

  local function showGameRing()
    parts.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    parts.ring:ClearAllPoints()
    parts.ring:SetSize(ringScale, ringScale)
    parts.ring:SetPoint("TOPLEFT", -size * 0.27, size * 0.27)
    parts.ring:Show()
  end

  if style == "coin" then
    showGameRing()
    parts.discA:SetVertexColor(0.44, 0.31, 0.05, 1); InsetDisc(parts.discA, size * 0.07); parts.discA:Show()
    parts.discB:SetVertexColor(0.86, 0.66, 0.14, 1); InsetDisc(parts.discB, size * 0.13); parts.discB:Show()
    parts.discC:SetVertexColor(1.00, 0.84, 0.28, 1); InsetDisc(parts.discC, size * 0.20); parts.discC:Show()
    parts.sheen:SetVertexColor(1.00, 0.96, 0.72, 0.45)
    parts.sheen:ClearAllPoints(); parts.sheen:SetSize(size * 0.37, size * 0.37)
    parts.sheen:SetPoint("CENTER", -size * 0.13, size * 0.13); parts.sheen:Show()
    parts.shadow:SetTextColor(0.10, 0.16, 0.04, 0.85); parts.shadow:Show()
    parts.letter:SetTextColor(brand[1], brand[2], brand[3], 1); parts.letter:Show()
  elseif style == "minimal" then
    parts.discA:SetVertexColor(accent[1], accent[2], accent[3], 1); InsetDisc(parts.discA, 0); parts.discA:Show()
    parts.discB:SetVertexColor(0.05, 0.07, 0.06, 1); InsetDisc(parts.discB, math.max(2, size * 0.09)); parts.discB:Show()
    parts.letter:SetTextColor(accent[1], accent[2], accent[3], 1); parts.letter:Show()
  elseif style == "badge" then
    parts.discA:SetVertexColor(0.05, 0.07, 0.06, 1); InsetDisc(parts.discA, 0); parts.discA:Show()
    parts.discB:SetVertexColor(accent[1], accent[2], accent[3], 1); InsetDisc(parts.discB, math.max(1.5, size * 0.06)); parts.discB:Show()
    parts.letter:SetTextColor(0.06, 0.09, 0.07, 1); parts.letter:Show()
  else
    showGameRing()
    parts.icon:SetTexture(STYLE_ICONS[style] or STYLE_ICONS.classic)
    parts.icon:ClearAllPoints()
    parts.icon:SetPoint("TOPLEFT", size * 0.10, -size * 0.10)
    parts.icon:SetPoint("BOTTOMRIGHT", -size * 0.10, size * 0.10)
    parts.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if target.masked then pcall(parts.icon.SetMask, parts.icon, CIRCLE_MASK) end
    parts.icon:Show()
    if showLetter then
      parts.shadow:SetTextColor(0, 0, 0, 0.9); parts.shadow:Show()
      parts.letter:SetTextColor(brand[1], brand[2], brand[3], 1); parts.letter:Show()
    end
  end

  local artwork = not (style == "coin" or style == "minimal" or style == "badge")
  local fontSize = math.max(9, size * (artwork and 0.48 or 0.53))
  local outline = artwork and "THICKOUTLINE" or "OUTLINE"
  parts.letter:SetFont(parts.letter.fontPath or "Fonts\\FRIZQT__.TTF", fontSize, outline)
  parts.shadow:SetFont(parts.shadow.fontPath or "Fonts\\FRIZQT__.TTF", fontSize, outline)
  return ringScale
end

-- A non-interactive rendering of one style, for the Appearance panel.
function SL:CreateMinimapPreview(parent, size)
  local preview = CreateFrame("Frame", nil, parent)
  BuildParts(preview)
  self:PaintMinimapStyle(preview, "coin", size or 30)
  return preview
end

function SL:ApplyMinimapStyle()
  local button = self.minimapButton
  if not button then return end
  local settings = Settings()
  local ringScale = self:PaintMinimapStyle(button, settings.style, settings.size, settings.letter ~= false)
  local size = button:GetWidth()

  button.highlight:ClearAllPoints()
  button.highlight:SetSize(ringScale, ringScale)
  button.highlight:SetPoint("TOPLEFT", -size * 0.27, size * 0.27)

  if settings.locked then button:RegisterForDrag() else button:RegisterForDrag("LeftButton") end
  UpdatePosition(button)
end

function SL:CreateMinimapButton()
  if self.minimapButton or not _G.Minimap then return end
  local settings = Settings()
  local button = CreateFrame("Button", "GoblinMinimapButton", _G.Minimap, BackdropTemplateMixin and "BackdropTemplate" or nil)
  self.minimapButton = button
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:SetMovable(true)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  BuildParts(button)

  -- The highlight art is a glow drawn on black. Without ADD blending the black
  -- is composited straight over the icon, which is why hovering used to turn
  -- the button into a black square.
  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetBlendMode("ADD")
  button.highlight = highlight

  button:SetScript("OnEnter", ShowTooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
      SL:ToggleUI()
    elseif IsShiftKeyDown() and SL.ToggleAppearance then
      SL:ToggleAppearance()
    else
      if not SL.frame or not SL.frame:IsShown() then SL:ToggleUI() end
      if SL.options then SL.options:Show(); SL:RefreshOptions() end
    end
  end)

  button:SetScript("OnDragStart", function() button.dragging = true end)
  button:SetScript("OnDragStop", function() button.dragging = false end)
  button:SetScript("OnUpdate", function()
    if not button.dragging then return end
    local mx, my = GetCursorPosition()
    local scale = _G.Minimap:GetEffectiveScale()
    mx, my = mx / scale, my / scale
    local cx, cy = _G.Minimap:GetCenter()
    if not cx then return end
    Settings().angle = math.deg(math.atan2(my - cy, mx - cx))
    UpdatePosition(button)
  end)

  self:ApplyMinimapStyle()
  button:SetShown(settings.shown ~= false)
  return button
end

-- Re-reads every minimap setting: visibility, style, size, distance, lock.
function SL:RefreshMinimapButton()
  local settings = Settings()
  if settings.shown == false then
    if self.minimapButton then self.minimapButton:Hide() end
    return
  end
  if not self.minimapButton then
    self:CreateMinimapButton()
    return
  end
  self:ApplyMinimapStyle()
  self.minimapButton:Show()
end

function SL:SetMinimapHidden(hidden)
  Settings().shown = not hidden
  self:RefreshMinimapButton()
end
