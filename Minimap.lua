--[[--------------------------------------------------------------------------
  ForeverProfit - Minimap   (v0.8.0)

  Minimap-Button ohne Libraries.
    Linksklick   = Fenster an/aus
    Rechtsklick  = AH-Scan (am offenen Auktionshaus)
    Ziehen       = um die Minimap verschieben (Winkel wird gespeichert)
  Zusaetzlich: Eintrag im Addon-Compartment (falls der Client es hat,
  siehe ## AddonCompartmentFunc in der TOC).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local MinimapButton = {}
ns.Minimap = MinimapButton

local ICON = "Interface\\Icons\\INV_Misc_Coin_02"
local button

local atan2 = math.atan2 or _G.atan2

local function settings()
    local db = ns.Config and ns.Config.db
    if not db then return { angle = 225, hide = false } end
    db.minimap = db.minimap or {}
    if db.minimap.angle == nil then db.minimap.angle = 225 end
    return db.minimap
end

local function updatePosition()
    if not button then return end
    local rad = math.rad(settings().angle or 225)
    local r = (Minimap:GetWidth() / 2) + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    px, py = px / scale, py / scale
    if atan2 then
        settings().angle = math.deg(atan2(py - my, px - mx))
        updatePosition()
    end
end

local function showTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("ForeverProfit")
    GameTooltip:AddLine(L["Linksklick: Fenster an/aus"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Rechtsklick: AH scannen (am Auktionshaus)"], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L["Ziehen: Button verschieben"], 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function onClick(btn)
    if btn == "RightButton" then
        if ns.AuctionScan then ns.AuctionScan.Start() end
    elseif ns.UI then
        ns.UI.Toggle()
    end
end

local function build()
    if button or not Minimap then return end

    button = CreateFrame("Button", "ForeverProfitMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, btn) onClick(btn) end)
    button:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", showTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    updatePosition()
end

function MinimapButton.Init()
    build()
    if button then if settings().hide then button:Hide() else button:Show() end end
end

function MinimapButton.Toggle()
    local s = settings()
    s.hide = not s.hide
    build()
    if button then if s.hide then button:Hide() else button:Show() end end
    ns:Print(L["Minimap-Button: "] .. (s.hide and L["aus"] or L["an"]))
end

-- Addon-Compartment (Addon-Liste an der Minimap, falls vorhanden).
function ForeverProfit_OnAddonCompartmentClick(_, btn)
    onClick(btn)
end
