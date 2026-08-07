local _, SL = ...

-- Custom minimap button. Standard circular-track math with click-and-drag
-- repositioning; no LibDBIcon dep so Goblin stays a single-folder addon.

local BUTTON_RADIUS = 80
local BUTTON_SIZE = 30

local function ComputePosition(angleDeg)
  local Minimap = _G.Minimap
  if not Minimap then return 0, 0 end
  local radius = Minimap:GetWidth() / 2 + 5
  local a = math.rad(angleDeg or -75)
  return math.cos(a) * radius, math.sin(a) * radius
end

local function UpdatePosition(button)
  local angle = SL.db.window.minimap and SL.db.window.minimap.angle or -75
  local x, y = ComputePosition(angle)
  button:ClearAllPoints()
  button:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

local function ShowTooltip(button)
  GameTooltip:SetOwner(button, "ANCHOR_LEFT")
  GameTooltip:AddLine("|cff00fe00Goblin|r")
  local rows, itemValue, gold = SL:BuildLedger("")
  local netWorth = (itemValue or 0) + (gold or 0)
  GameTooltip:AddDoubleLine("Net worth", SL:FormatMoney(netWorth), 1, 1, 1, 1, 0.85, 0.22)
  GameTooltip:AddDoubleLine("Gold", SL:FormatMoney(gold or 0), 0.9, 0.9, 0.9, 1, 0.85, 0.22)
  GameTooltip:AddDoubleLine("Items", SL:FormatMoney(itemValue or 0), 0.9, 0.9, 0.9, 1, 0.85, 0.22)
  local stale = SL.GetStaleSources and SL:GetStaleSources() or {}
  if #stale > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(string.format("|cffff9933%d source%s stale|r", #stale, #stale == 1 and "" or "s"))
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("|cffababab Left-click:|r Toggle ledger", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("|cffababab Right-click:|r Sources", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("|cffababab Drag:|r Reposition", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end

function SL:CreateMinimapButton()
  if self.minimapButton or not _G.Minimap then return end
  self.db.window.minimap = self.db.window.minimap or { angle = -75, hidden = false }
  if self.db.window.minimap.hidden then return end
  local button = CreateFrame("Button", "GoblinMinimapButton", _G.Minimap, BackdropTemplateMixin and "BackdropTemplate" or nil)
  self.minimapButton = button
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:SetMovable(true)
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  local ring = button:CreateTexture(nil, "BORDER")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(52, 52); ring:SetPoint("TOPLEFT", -8, 8)

  local disc = button:CreateTexture(nil, "BACKGROUND")
  disc:SetTexture("Interface\\Buttons\\WHITE8X8")
  disc:SetVertexColor(0.06, 0.10, 0.06, 1)
  disc:SetPoint("TOPLEFT", 2, -2); disc:SetPoint("BOTTOMRIGHT", -2, 2)

  local letter = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  letter:SetPoint("CENTER", 0, 1)
  letter:SetText("G")
  letter:SetTextColor(0.0, 0.90, 0.20, 1)

  local highlight = button:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  highlight:SetPoint("TOPLEFT", -8, 8); highlight:SetSize(52, 52)

  button:SetScript("OnEnter", ShowTooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then SL:ToggleUI()
    elseif mouseButton == "RightButton" then
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
    SL.db.window.minimap.angle = math.deg(math.atan2(my - cy, mx - cx))
    UpdatePosition(button)
  end)

  UpdatePosition(button)
end

function SL:SetMinimapHidden(hidden)
  self.db.window.minimap = self.db.window.minimap or { angle = -75 }
  self.db.window.minimap.hidden = hidden and true or false
  if hidden then
    if self.minimapButton then self.minimapButton:Hide() end
  else
    if self.minimapButton then self.minimapButton:Show()
    else self:CreateMinimapButton() end
  end
end
