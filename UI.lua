--[[--------------------------------------------------------------------------
  ForeverProfit - UI   (v1.0.0)
  Hauptfenster: Rezepte mit Kosten / Verkauf / Gewinn.
  Linksklick = +1 in die Queue, Shift+Linksklick = +5, Rechtsklick = -1.
  Unten: Queue-Summe, Einkaufsliste an Auctionator, Queue leeren.
  Keine geschuetzten Aktionen, kein Auto-Craft.
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 620, 500
local ROWS = 13
local ROW_H = 26
local ROW_W = 560

-- Spalten (x relativ zur Zeile)
local COL_QTY, COL_ICON, COL_NAME = 8, 38, 64
local COL_AVAIL = 236
local COL_COST, COL_REV, COL_PROFIT = 300, 390, 470
local W_NAME, W_AVAIL, W_MONEY, W_PROFIT = 170, 52, 86, 86

-- Skill-Farben: 0 orange, 1 gelb, 2 gruen, 3 grau
local DIFF_COLOR = {
    [0] = { 1, 0.5, 0.25 }, [1] = { 1, 1, 0 }, [2] = { 0.25, 0.75, 0.25 }, [3] = { 0.5, 0.5, 0.5 },
}
local DIFF_NAME = { [0] = L["orange"], [1] = L["gelb"], [2] = L["gruen"], [3] = L["grau"] }
local profitHead

local frame, scroll, scrollChild, rows
local statusText, footerText, emptyText, searchBox, profitCheck, subCheck
local searchText = ""
local autoOpened = false    -- Fenster wurde vom Berufsfenster geoeffnet
local userMoved = false     -- Spieler hat das Fenster selbst verschoben
local profFilter            -- Berufsname oder nil (= alle)
local sidebar, allBtn, sidebarSig
local profButtons = {}
local SIDE_W, PROF_H = 176, 38

local SRC_LABEL = {
    vendor = L["|cff88ccffHaendler|r"],
    craft  = L["|cff88ff88selbst herstellen|r"],
    manual = L["|cffffcc00eigener Preis|r"],
    ah     = "|cffaaaaaaAH|r",
}

-- Helfer --------------------------------------------------------------------

local function coins(copper)
    copper = math.floor((tonumber(copper) or 0) + 0.5)
    local neg = copper < 0
    if neg then copper = -copper end
    local txt
    if type(GetCoinTextureString) == "function" then
        txt = ns.Try(GetCoinTextureString, copper, 12)
    end
    if type(txt) ~= "string" or txt == "" then txt = ns.Money(copper) end
    return (neg and "-" or "") .. txt
end

local function itemInfo(id)
    if not id or type(GetItemInfo) ~= "function" then return nil end
    local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
    if not icon and type(GetItemIcon) == "function" then icon = GetItemIcon(id) end
    return name, quality, icon
end

local function qualityHex(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if not c then return "ffffffff" end
    if c.hex then return (c.hex:gsub("^|c", "")) end
    return string.format("ff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
end

local function owned(id)
    if not id or type(GetItemCount) ~= "function" then return 0 end
    return tonumber(ns.Try(GetItemCount, id, true)) or 0
end

local function setBackdrop(f, bgAlpha)
    if not f.SetBackdrop then return end
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, bgAlpha or 0.95)
    f:SetBackdropBorderColor(0.45, 0.40, 0.30, 1)
end

local function hline(parent, y, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(0.8, 0.7, 0.4, alpha or 0.25)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", 12, y)
    t:SetPoint("TOPRIGHT", -12, y)
    return t
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function tooltip(owner, title, body)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(title)
        local text = type(body) == "function" and body() or body
        if text then GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function checkbox(parent, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 0, 1)
    fs:SetText(label)
    cb.label = fs
    cb:SetScript("OnClick", onClick)
    return cb
end

-- Zeilen-Tooltip ------------------------------------------------------------

local function showRowTooltip(self)
    local e = self.entry
    if not e then return end
    local out = e.recipe.output or {}
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if out.id and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(out.id)
        GameTooltip:AddLine(" ")
    else
        GameTooltip:AddLine(ns.Str(e.recipe.name), 1, 1, 1)
    end
    GameTooltip:AddLine("ForeverProfit", 0.2, 0.67, 1)
    for _, d in ipairs(e.details or {}) do
        local name, q = itemInfo(d.id)
        local have = owned(d.id)
        local left = string.format("%dx |c%s%s|r%s", d.count, qualityHex(q),
            name or d.name or ("Item " .. ns.Str(d.id)),
            have > 0 and string.format(L[" |cff888888(hast %d)|r"], have) or "")
        local right = d.unit and (coins(d.unit * d.count) .. "  " .. (SRC_LABEL[d.src] or ""))
                      or L["|cffff5555kein Preis|r"]
        GameTooltip:AddDoubleLine(left, right, 0.9, 0.9, 0.9, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L["Kosten"], coins(e.cost), 0.7, 0.7, 0.7, 1, 1, 1)
    if e.hasOutput then
        GameTooltip:AddDoubleLine(string.format(L["Verkauf %dx (nach 5%% AH-Gebuehr)"], out.count or 1),
            coins(e.revenue), 0.7, 0.7, 0.7, 1, 1, 1)
        local pc = e.profit >= 0 and "|cff44ff44" or "|cffff5555"
        GameTooltip:AddDoubleLine(L["Gewinn"], pc .. coins(e.profit) .. "|r", 1, 0.82, 0, 1, 1, 1)
    else
        GameTooltip:AddLine(L["Ergebnis hat keinen AH-Preis"], 1, 0.4, 0.4)
    end
    -- Marktlage
    local m = e.market
    if m then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Markt"], 1, 0.82, 0)
        local ageText = (m.age == nil) and L["|cffff5555ueber 3 Wochen|r"]
            or (m.age == 0 and L["heute"] or (m.age == 1 and L["gestern"] or string.format(L["vor %d Tagen"], m.age)))
        GameTooltip:AddDoubleLine(L["Zuletzt im AH gesehen"], ageText, 0.7, 0.7, 0.7, 1, 1, 1)
        if m.available then
            GameTooltip:AddDoubleLine(L["Angebote (letzter Scan)"], tostring(m.available), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        if m.median then
            GameTooltip:AddDoubleLine(string.format(L["Mittlerer Preis (%d Tage)"], m.days), coins(m.median),
                0.7, 0.7, 0.7, 1, 1, 1)
        end
        if e.spike then
            GameTooltip:AddLine(L["! Aktueller Preis deutlich ueber dem Mittel - Gewinn evtl. zu optimistisch"],
                1, 0.67, 0.2, true)
        end
        if e.stale then
            GameTooltip:AddLine(L["~ Preis ist alt - vor dem Craften neu scannen"], 0.6, 0.6, 0.6, true)
        end
        if m.available and m.available >= 20 then
            GameTooltip:AddLine(L["Viel Konkurrenz im AH"], 1, 0.53, 0.4)
        end
    end

    -- Skill
    local d = e.recipe.difficulty
    if d and DIFF_NAME[d] then
        GameTooltip:AddLine(" ")
        local c = DIFF_COLOR[d]
        GameTooltip:AddDoubleLine(L["Skill-Farbe"], DIFF_NAME[d], 0.7, 0.7, 0.7, c[1], c[2], c[3])
        if e.skillCost then
            GameTooltip:AddDoubleLine(L["Kosten pro Skillpunkt (geschaetzt)"], coins(e.skillCost),
                0.7, 0.7, 0.7, 1, 1, 1)
        end
    end

    local q = ns.Profit.QueueCount(e.recipe.key)
    if q > 0 then GameTooltip:AddLine(string.format(L["In der Queue: %dx"], q), 0.27, 1, 0.27) end
    GameTooltip:AddLine(L["Links +1   Shift+Links +5   Rechts -1"], 0.5, 0.7, 1)
    GameTooltip:Show()
end

-- Zeilen --------------------------------------------------------------------

local function makeRow(i)
    local r = CreateFrame("Button", nil, scrollChild)
    r:SetSize(ROW_W, ROW_H)
    r:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.035 or 0)

    r.queued = r:CreateTexture(nil, "BACKGROUND", nil, 1)
    r.queued:SetAllPoints()
    r.queued:SetColorTexture(0.2, 0.8, 0.2, 0.10)

    r.accent = r:CreateTexture(nil, "ARTWORK")
    r.accent:SetPoint("TOPLEFT", 0, -2)
    r.accent:SetPoint("BOTTOMLEFT", 0, 2)
    r.accent:SetWidth(3)
    r.accent:SetColorTexture(0.3, 0.95, 0.3, 0.9)

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0, 0.08)

    r.qty = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.qty:SetPoint("LEFT", COL_QTY, 0)
    r.qty:SetWidth(28)
    r.qty:SetJustifyH("CENTER")

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", COL_ICON, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.diff = r:CreateTexture(nil, "OVERLAY")
    r.diff:SetSize(7, 7)
    r.diff:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 2, -2)
    r.diff:SetColorTexture(1, 1, 1, 1)

    r.avail = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.avail:SetPoint("LEFT", COL_AVAIL, 0)
    r.avail:SetWidth(W_AVAIL)
    r.avail:SetJustifyH("RIGHT")

    r.name:SetPoint("LEFT", COL_NAME, 0)
    r.name:SetWidth(W_NAME)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.cost = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.cost:SetPoint("LEFT", COL_COST, 0)
    r.cost:SetWidth(W_MONEY)
    r.cost:SetJustifyH("RIGHT")

    r.rev = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.rev:SetPoint("LEFT", COL_REV, 0)
    r.rev:SetWidth(W_MONEY)
    r.rev:SetJustifyH("RIGHT")

    r.profit = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.profit:SetPoint("LEFT", COL_PROFIT, 0)
    r.profit:SetWidth(W_PROFIT)
    r.profit:SetJustifyH("RIGHT")

    r:SetScript("OnClick", function(self, btn)
        local e = self.entry
        if not e or not e.recipe.key then return end
        local delta = 1
        if btn == "RightButton" then
            delta = -1
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            delta = 5
        end
        ns.Profit.QueueAdd(e.recipe.key, delta)
        UI.Refresh()
        if GameTooltip:IsOwned(self) then showRowTooltip(self) end
    end)
    r:SetScript("OnEnter", showRowTooltip)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

-- Seitenleiste: Berufe ------------------------------------------------------
-- Linksklick = Berufsfenster oeffnen (SecureActionButton, castet den
-- Berufs-Zauber), Rechtsklick = Liste auf den Beruf filtern.
-- Secure-Buttons duerfen im Kampf nicht veraendert/gezeigt werden ->
-- Fenster schliesst bei Kampfbeginn, Aenderungen nur ausserhalb.

local SMELTING_SPELL = 2656   -- Bergbau oeffnet das "Verhuetten"-Fenster

local function spellInfo(spell)
    if type(GetSpellInfo) == "function" then
        local name, _, icon = GetSpellInfo(spell)
        if name then return name, icon end
    end
    if type(C_Spell) == "table" and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(spell)
        if type(info) == "table" and info.name then return info.name, info.iconID end
    end
    return nil
end

--- Zauber, der das Berufsfenster oeffnet (Name + Icon), oder nil.
local function professionSpell(profName)
    local name, icon = spellInfo(profName)
    if name then return name, icon end
    -- Bergbau: Fenster heisst "Verhuetten" / "Smelting"
    name, icon = spellInfo(SMELTING_SPELL)
    if name and profName and profName:lower():find("^min") then return name, icon end
    if name and profName and profName:lower():find("^berg") then return name, icon end
    return nil
end

--- Berufe mit mindestens einem Rezept, nach Name zusammengefasst.
-- Basis-Skill-Lines der Herstellungsberufe (Sammelberufe fehlen bewusst):
-- Schmiedekunst, Lederverarbeitung, Alchemie, Kochen, Bergbau (Verhuetten),
-- Schneiderei, Ingenieurskunst, Verzauberkunst, Juwelier, Inschriften, Erste Hilfe
local CRAFTING_LINES = {
    [164] = true, [165] = true, [171] = true, [185] = true, [186] = true, [197] = true,
    [202] = true, [333] = true, [755] = true, [773] = true, [129] = true,
}

--- Berufe fuer die Leiste: alle mit eingelesenen Rezepten, plus
--- Herstellungsberufe ohne Rezepte (z.B. Kochen, bevor das Fenster offen war).
local function professionList()
    local counts = {}
    for _, r in ipairs(ns.Professions.recipes or {}) do
        if r.profession then counts[r.profession] = (counts[r.profession] or 0) + 1 end
    end
    local byName, list = {}, {}
    for _, p in ipairs(ns.Professions.professions or {}) do
        local n = p.name
        local crafting = CRAFTING_LINES[tonumber(p.id) or 0] or CRAFTING_LINES[tonumber(p.parentID) or 0]
        if n and (counts[n] or crafting) then
            local cur = byName[n]
            if not cur then
                cur = { name = n, skill = 0, max = 0, recipes = counts[n] or 0 }
                byName[n] = cur
                list[#list + 1] = cur
            end
            cur.skill = math.max(cur.skill, tonumber(p.skillLevel) or 0)
            cur.max   = math.max(cur.max, tonumber(p.maxSkillLevel) or 0)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function sideButtonVisual(b)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints()
    b.sel:SetColorTexture(1, 0.82, 0, 0.15)
    b.sel:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(26, 26)
    b.icon:SetPoint("LEFT", 6, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.title:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, 1)
    b.title:SetPoint("RIGHT", -4, 0)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)

    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sub:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 8, 0)
    b.sub:SetJustifyH("LEFT")
end

local function setFilter(name)
    profFilter = name
    if scroll then scroll:SetVerticalScroll(0) end
    UI.Refresh()
end

local function makeProfButton(i)
    local b = CreateFrame("Button", "ForeverProfitProf" .. i, sidebar, "SecureActionButtonTemplate")
    b:SetSize(SIDE_W - 16, PROF_H)
    b:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonUp")
    b:SetAttribute("useOnKeyDown", false)
    b:SetAttribute("type1", "spell")
    sideButtonVisual(b)
    b:HookScript("PostClick", function(self, btn)
        if btn == "RightButton" then
            setFilter(profFilter ~= self.profName and self.profName or nil)
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(self.profName or "?")
        if self.hasSpell then
            GameTooltip:AddLine(L["Linksklick: Berufsfenster oeffnen"], 0.8, 0.8, 0.8)
        else
            GameTooltip:AddLine(L["Kein eigenes Berufsfenster"], 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine(L["Rechtsklick: Liste auf diesen Beruf filtern"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function buildSidebar()
    sidebar = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    sidebar:SetWidth(SIDE_W)
    sidebar:SetPoint("TOPRIGHT", frame, "TOPLEFT", 2, 0)
    sidebar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 2, 0)
    setBackdrop(sidebar)

    local t = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 14, -12)
    t:SetText(L["Berufe"])

    allBtn = CreateFrame("Button", nil, sidebar)
    allBtn:SetSize(SIDE_W - 16, PROF_H)
    allBtn:SetPoint("TOPLEFT", 8, -40)
    sideButtonVisual(allBtn)
    allBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    allBtn.title:SetText(L["Alle Berufe"])
    allBtn:SetScript("OnClick", function() setFilter(nil) end)

    local hint = sidebar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 12, 14)
    hint:SetPoint("BOTTOMRIGHT", -12, 14)
    hint:SetJustifyH("LEFT")
    hint:SetText(L["Beruf: Links oeffnen, Rechts filtern"])

    -- Modus: Profit / Skillen
    local function setMode(mode)
        ns.Config.db.mode = mode
        if scroll then scroll:SetVerticalScroll(0) end
        UI.Refresh()
    end
    sidebar.profitBtn = button(sidebar, "Profit", 76)
    sidebar.profitBtn:SetPoint("BOTTOMLEFT", 10, 36)
    sidebar.profitBtn:SetScript("OnClick", function() setMode("profit") end)
    tooltip(sidebar.profitBtn, L["Profit-Modus"], L["Rezepte nach Gewinn sortiert."])

    sidebar.skillBtn = button(sidebar, L["Skillen"], 76)
    sidebar.skillBtn:SetPoint("LEFT", sidebar.profitBtn, "RIGHT", 4, 0)
    sidebar.skillBtn:SetScript("OnClick", function() setMode("skill") end)
    tooltip(sidebar.skillBtn, L["Skill-Modus"],
        L["Nur Rezepte, die noch Skill geben (orange/gelb/gruen),\nsortiert nach Kosten pro Skillpunkt.\nVerkaufserloes wird gegengerechnet."])

    sidebar.unlearned = checkbox(sidebar, L["Ungelernte zeigen"], function(self)
        ns.Config.db.onlyLearned = not self:GetChecked()
        UI.Refresh()
    end)
    sidebar.unlearned:SetPoint("BOTTOMLEFT", 8, 62)

    sidebar.autoOpen = checkbox(sidebar, L["Mit Beruf oeffnen"], function(self)
        ns.Config.db.autoOpen = self:GetChecked() and true or false
    end)
    sidebar.autoOpen:SetPoint("BOTTOMLEFT", 8, 86)
    tooltip(sidebar.autoOpen, L["Mit Beruf oeffnen"],
        L["ForeverProfit oeffnet sich automatisch mit dem Berufsfenster\nund zeigt die Rezepte dieses Berufs."])
    tooltip(sidebar.unlearned, L["Ungelernte Rezepte"],
        L["Zeigt auch Rezepte, die du noch nicht kannst -\npraktisch um zu sehen, ob sich ein Rezept-Kauf lohnt."])
end

local function updateSidebar()
    if not sidebar then return end
    local list = professionList()

    -- Filter auf einen Beruf, der nicht mehr existiert -> zuruecksetzen.
    if profFilter then
        local found = false
        for _, p in ipairs(list) do if p.name == profFilter then found = true end end
        if not found then profFilter = nil end
    end

    local db = ns.Config.db
    if db.mode == "skill" then
        sidebar.skillBtn:LockHighlight(); sidebar.profitBtn:UnlockHighlight()
    else
        sidebar.profitBtn:LockHighlight(); sidebar.skillBtn:UnlockHighlight()
    end
    sidebar.unlearned:SetChecked(not db.onlyLearned)
    sidebar.autoOpen:SetChecked(db.autoOpen ~= false)

    allBtn.sub:SetText(string.format(L["%d Rezepte"], #(ns.Professions.recipes or {})))
    if profFilter then allBtn.sel:Hide() else allBtn.sel:Show() end

    -- Texte/Markierung duerfen immer aktualisiert werden ...
    local sig = {}
    for i, p in ipairs(list) do sig[i] = p.name end
    sig = table.concat(sig, "|")

    -- ... Secure-Attribute und Show/Hide nur ausserhalb des Kampfes.
    local canChange = not (InCombatLockdown and InCombatLockdown())
    if canChange and sig ~= sidebarSig then
        sidebarSig = sig
        for i, p in ipairs(list) do
            local b = profButtons[i] or makeProfButton(i)
            profButtons[i] = b
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 8, -40 - i * (PROF_H + 2))
            local spell, icon = professionSpell(p.name)
            b.profName = p.name
            b.hasSpell = spell ~= nil
            b:SetAttribute("spell1", spell)
            b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:Show()
        end
        for i = #list + 1, #profButtons do profButtons[i]:Hide() end
    end

    for i, p in ipairs(list) do
        local b = profButtons[i]
        if b then
            b.title:SetText(p.name)
            local skill = (p.max > 0) and string.format("%d/%d", p.skill, p.max)
                          or (p.skill > 0 and tostring(p.skill) or "")
            if p.recipes > 0 then
                b.sub:SetText(string.format(L["%s%s%d Rezepte"], skill, skill ~= "" and "  \194\183  " or "", p.recipes))
            else
                b.sub:SetText(skill .. (skill ~= "" and "  \194\183  " or "") .. L["Fenster oeffnen zum Einlesen"])
            end
            if profFilter == p.name then b.sel:Show() else b.sel:Hide() end
        end
    end
end

-- Herstellliste (rechts) ----------------------------------------------------

local CRAFT_W, CRAFT_ROW_H, CRAFT_ROWS = 260, 42, 9
local craftPanel, craftRows, craftSummary, craftNextBtn
local craftEntries = {}

local function makeCraftRow(i)
    local r = CreateFrame("Frame", nil, craftPanel)
    r:SetSize(CRAFT_W - 16, CRAFT_ROW_H)
    r:SetPoint("TOPLEFT", 8, -40 - (i - 1) * (CRAFT_ROW_H + 2))
    r:EnableMouse(true)

    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, 0.035)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(28, 28)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn:SetSize(74, 22)
    r.btn:SetPoint("RIGHT", -4, 0)
    r.btn:SetText(L["Herstellen"])
    r.btn:SetScript("OnClick", function(self)
        ns.Profit.Craft(self:GetParent().entry)
    end)

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, -1)
    r.title:SetPoint("RIGHT", r.btn, "LEFT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)

    r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.sub:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 1)
    r.sub:SetPoint("RIGHT", r.btn, "LEFT", -4, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)

    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.Str(e.recipe.name), 1, 1, 1)
        if e.intermediate then
            GameTooltip:AddLine(L["Zwischenschritt - wird fuer die Queue gebraucht"], 0.53, 1, 0.53)
        end
        GameTooltip:AddLine(" ")
        for _, rg in ipairs(e.recipe.reagents or {}) do
            local name, q = itemInfo(rg.id)
            local bag = tonumber(ns.Try(GetItemCount, rg.id, false)) or 0
            local need = (rg.count or 1) * e.times
            local col = bag >= need and "|cff44ff44" or "|cffff5555"
            GameTooltip:AddDoubleLine(string.format("|c%s%s|r", qualityHex(q), name or ("Item " .. ns.Str(rg.id))),
                string.format("%s%d|r / %d", col, bag, need), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return r
end

local function buildCraftPanel()
    craftPanel = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
    craftPanel:SetWidth(CRAFT_W)
    craftPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", -2, 0)
    craftPanel:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", -2, 0)
    setBackdrop(craftPanel)

    local t = craftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 14, -12)
    t:SetText(L["Herstellliste"])

    craftRows = {}
    for i = 1, CRAFT_ROWS do craftRows[i] = makeCraftRow(i) end

    craftNextBtn = CreateFrame("Button", nil, craftPanel, "UIPanelButtonTemplate")
    craftNextBtn:SetSize(CRAFT_W - 24, 30)
    craftNextBtn:SetPoint("BOTTOM", 0, 14)
    craftNextBtn:SetText(L["Naechstes herstellen"])
    craftNextBtn:SetScript("OnClick", function() ns.Profit.CraftNext() end)

    craftSummary = craftPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    craftSummary:SetPoint("BOTTOMLEFT", craftNextBtn, "TOPLEFT", 2, 8)
    craftSummary:SetPoint("BOTTOMRIGHT", craftNextBtn, "TOPRIGHT", -2, 8)
    craftSummary:SetJustifyH("LEFT")
end

local function updateCraftPanel()
    if not craftPanel then return end
    craftEntries = ns.Profit.CraftEntries()
    local ready, total = 0, 0
    for i = 1, CRAFT_ROWS do
        local row = craftRows[i]
        local e = craftEntries[i]
        row.entry = e
        if not e then
            row:Hide()
        else
            row:Show()
            local out = e.recipe.output or {}
            local _, q, icon = itemInfo(out.id)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.title:SetText(string.format("%dx |c%s%s|r", e.times, qualityHex(q), ns.Str(e.recipe.name)))
            local status
            if e.possible >= e.times then
                status = L["|cff44ff44bereit|r"]
            elseif e.possible > 0 then
                status = string.format(L["|cffffcc00%d von %d moeglich|r"], e.possible, e.times)
            else
                status = L["|cffff5555Material fehlt|r"]
            end
            if e.intermediate then status = L["|cff88ff88Zwischenschritt|r  "] .. status end
            row.sub:SetText(status)
            if e.possible > 0 then row.btn:Enable() else row.btn:Disable() end
        end
    end
    for _, e in ipairs(craftEntries) do
        total = total + e.times
        if e.possible > 0 then ready = ready + 1 end
    end
    if #craftEntries == 0 then
        craftSummary:SetText(L["|cff888888Leer - Rezepte in der Liste\nanklicken, um sie einzuplanen.|r"])
        craftNextBtn:Disable()
    else
        local more = #craftEntries > CRAFT_ROWS and
            string.format(L["\n|cff888888... und %d weitere|r"], #craftEntries - CRAFT_ROWS) or ""
        craftSummary:SetText(string.format(L["%d Schritte, %d Crafts  \194\183  %d bereit%s"],
            #craftEntries, total, ready, more))
        if ready > 0 then craftNextBtn:Enable() else craftNextBtn:Disable() end
    end
end

-- Aufbau --------------------------------------------------------------------

local function build()
    if frame then return end

    frame = CreateFrame("Frame", "ForeverProfitFrame", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        userMoved = true
    end)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    setBackdrop(frame)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "ForeverProfitFrame")
    end

    -- Titelleiste
    local titleBg = frame:CreateTexture(nil, "BORDER")
    titleBg:SetPoint("TOPLEFT", 4, -4)
    titleBg:SetPoint("TOPRIGHT", -4, -4)
    titleBg:SetHeight(30)
    titleBg:SetColorTexture(0.35, 0.28, 0.12, 0.35)

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetSize(22, 22)
    logo:SetPoint("TOPLEFT", 12, -8)
    logo:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    logo:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("ForeverProfit")

    local ver = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 6, -1)
    ver:SetText("v" .. ns.version)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    -- Werkzeugleiste
    local okSB, sb = pcall(CreateFrame, "EditBox", "ForeverProfitSearch", frame, "SearchBoxTemplate")
    if not okSB then
        sb = CreateFrame("EditBox", "ForeverProfitSearch", frame, "InputBoxTemplate")
    end
    searchBox = sb
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("TOPLEFT", 20, -44)
    searchBox:SetAutoFocus(false)
    searchBox:HookScript("OnTextChanged", function(self)
        searchText = (self:GetText() or ""):lower()
        if scroll then scroll:SetVerticalScroll(0) end
        UI.Refresh()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local scanBtn = button(frame, L["Berufe"], 74)
    scanBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
    scanBtn:SetScript("OnClick", function() ns.Professions.ScanAsync(true) end)
    tooltip(scanBtn, L["Berufe einlesen"], L["Liest deine Rezepte neu ein.\nPassiert auch automatisch beim Oeffnen des Berufsfensters."])

    local ahBtn = button(frame, L["AH scannen"], 96)
    ahBtn:SetPoint("LEFT", scanBtn, "RIGHT", 4, 0)
    ahBtn:SetScript("OnClick", function() ns.AuctionScan.Start() end)
    tooltip(ahBtn, L["AH scannen"], L["Startet Auctionators Vollscan (am offenen Auktionshaus, max. alle 15 Min)."])

    profitCheck = checkbox(frame, L["Nur Profit"], function(self)
        ns.Config.db.onlyProfit = self:GetChecked() and true or false
        scroll:SetVerticalScroll(0)
        UI.Refresh()
    end)
    profitCheck:SetPoint("LEFT", ahBtn, "RIGHT", 14, 0)
    tooltip(profitCheck, L["Nur Profit"], L["Nur Rezepte mit vollstaendigen Preisen und Gewinn anzeigen."])

    subCheck = checkbox(frame, L["Teilrezepte"], function(self)
        ns.Config.db.useSubCrafts = self:GetChecked() and true or false
        UI.Refresh()
    end)
    subCheck:SetPoint("LEFT", profitCheck.label, "RIGHT", 10, -1)
    tooltip(subCheck, L["Teilrezepte"], L["Zutaten, die du selbst billiger herstellen kannst,\nwerden mit dem Herstellungspreis gerechnet."])

    -- Statuszeile
    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    statusText:SetPoint("TOPLEFT", 20, -74)
    statusText:SetPoint("TOPRIGHT", -20, -74)
    statusText:SetJustifyH("LEFT")
    local statusHit = CreateFrame("Frame", nil, frame)
    statusHit:SetAllPoints(statusText)
    statusHit:EnableMouse(true)
    tooltip(statusHit, L["Preisquellen"], function()
        local list = ns.Prices.available or ns.Prices.Detect()
        return L["Modus: "] .. ns.Str(ns.Config.db.priceSource) .. L["\nVerfuegbar: "] ..
            ((#list > 0) and table.concat(list, ", ") or "keine") ..
            L["\n\nUmschalten: /fp source"]
    end)

    -- Spaltenkoepfe
    local headY = -94
    local function head(text, x, w, justify)
        local f = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", 14 + x, headY)
        f:SetWidth(w)
        f:SetJustifyH(justify or "RIGHT")
        f:SetText(text)
        return f
    end
    head(L["Anz."], COL_QTY, 28, "CENTER")
    head(L["Rezept"], COL_ICON, W_NAME, "LEFT")
    head(L["Im AH"], COL_AVAIL, W_AVAIL)
    head(L["Kosten"], COL_COST, W_MONEY)
    head(L["Verkauf"], COL_REV, W_MONEY)
    profitHead = head(L["Gewinn"], COL_PROFIT, W_PROFIT)
    hline(frame, headY - 16, 0.35)

    -- Liste
    scroll = CreateFrame("ScrollFrame", "ForeverProfitScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, headY - 20)
    scroll:SetPoint("BOTTOMRIGHT", -34, 78)

    scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(ROW_W, ROWS * ROW_H)
    scroll:SetScrollChild(scrollChild)

    rows = {}
    for i = 1, ROWS do rows[i] = makeRow(i) end

    emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("TOPLEFT", scroll, "TOPLEFT", 10, -40)
    emptyText:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -10, -40)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetTextColor(0.75, 0.75, 0.75)

    -- Fussbereich
    local footBg = frame:CreateTexture(nil, "BORDER")
    footBg:SetPoint("BOTTOMLEFT", 4, 4)
    footBg:SetPoint("BOTTOMRIGHT", -4, 4)
    footBg:SetHeight(70)
    footBg:SetColorTexture(0, 0, 0, 0.35)
    local footLine = frame:CreateTexture(nil, "ARTWORK")
    footLine:SetColorTexture(0.8, 0.7, 0.4, 0.35)
    footLine:SetHeight(1)
    footLine:SetPoint("BOTTOMLEFT", footBg, "TOPLEFT", 8, 0)
    footLine:SetPoint("BOTTOMRIGHT", footBg, "TOPRIGHT", -8, 0)

    footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    footerText:SetPoint("BOTTOMLEFT", 20, 46)
    footerText:SetPoint("BOTTOMRIGHT", -20, 46)
    footerText:SetJustifyH("LEFT")

    local clearBtn = button(frame, L["Queue leeren"], 104)
    clearBtn:SetPoint("BOTTOMRIGHT", -16, 14)
    clearBtn:SetScript("OnClick", function()
        ns.Profit.QueueClear()
        UI.Refresh()
    end)

    local shopBtn = button(frame, L["Einkaufsliste"], 116)
    shopBtn:SetPoint("RIGHT", clearBtn, "LEFT", -6, 0)
    shopBtn:SetScript("OnClick", function() ns.Profit.SendShoppingList() end)
    tooltip(shopBtn, L["Einkaufsliste"],
        L["Alle Zutaten der Queue minus Taschen und Bank.\nAH-Items gehen als Liste 'ForeverProfit' an Auctionator,\nHaendler-Items und Zwischenschritte stehen im Chat."])

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 20)
    hint:SetText(L["Links +1   |   Shift+Links +5   |   Rechts -1"])

    -- Mausrad
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local v = scroll:GetVerticalScroll() + (delta > 0 and -ROW_H or ROW_H)
        local maxScroll = math.max(0, scrollChild:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.min(math.max(v, 0), maxScroll))
        UI.Refresh()
    end)

    buildSidebar()
    buildCraftPanel()

    -- Fortschritt sichtbar halten, solange ein Scan laeuft.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 0.5 then return end
        acc = 0
        if (ns.Professions and ns.Professions.running) or
           (ns.AuctionScan and ns.AuctionScan.running) then
            UI.Refresh()
        end
    end)
end

-- Aktualisieren -------------------------------------------------------------

local function matchesSearch(e)
    if profFilter and e.recipe.profession ~= profFilter then return false end
    if searchText == "" then return true end
    return (ns.Str(e.recipe.name, "")):lower():find(searchText, 1, true) ~= nil
end

function UI.Refresh()
    -- Geschlossenes Fenster nicht neu rechnen (Auctionator meldet bei jeder Suche).
    if not frame or not frame:IsShown() then return end
    updateSidebar()
    local all, hidden = ns.Profit.All()
    local db = ns.Config.db
    profitCheck:SetChecked(db.onlyProfit and true or false)
    subCheck:SetChecked(db.useSubCrafts ~= false)

    local evaluated = {}
    for _, e in ipairs(all) do
        if matchesSearch(e) then evaluated[#evaluated + 1] = e end
    end

    -- Mehrere Berufe? Dann Beruf hinter dem Namen anzeigen.
    local skillMode = db.mode == "skill"
    local profs, multi = {}, false
    for _, e in ipairs(evaluated) do
        local p = e.recipe.profession or "?"
        profs[p] = true
        if next(profs, next(profs)) then multi = true; break end
    end

    profitHead:SetText(skillMode and L["Pro Skill"] or L["Gewinn"])

    if ns.Professions.running then
        local p = ns.Professions.progress
        statusText:SetText(string.format(L["|cffffcc00Lese Berufe ein... %d / %d|r"], p.done, p.total))
    elseif ns.AuctionScan.running then
        statusText:SetText(L["|cffffcc00Auktionshaus wird gescannt...|r"])
    elseif skillMode then
        statusText:SetText(string.format(
            L["|cffffd100Skill-Modus|r   \194\183   %d Rezepte geben noch Skill   \194\183   billigste zuerst"],
            #evaluated))
    else
        statusText:SetText(string.format(
            L["Preise %s   \194\183   %d Rezepte angezeigt   \194\183   %d ausgeblendet"],
            ns.Prices.AgeText(), #evaluated, hidden or 0))
    end

    if #evaluated > 0 then
        emptyText:SetText("")
    elseif #(ns.Professions.recipes or {}) == 0 then
        emptyText:SetText(L["Noch keine Rezepte eingelesen.\n\n|cffaaaaaaBerufsfenster einmal oeffnen.|r"])
    elseif searchText ~= "" then
        emptyText:SetText(L["Kein Rezept passt zur Suche."])
    elseif skillMode then
        emptyText:SetText(L["Keine Rezepte gefunden, die noch Skill geben.\n\n|cffaaaaaaBerufsfenster oeffnen, damit die Skill-Farben\naktuell sind. Hilft das nicht: /fp probe schicken.|r"])
    elseif db.onlyProfit then
        emptyText:SetText(L["Kein Rezept mit Gewinn gefunden.\n\n|cffaaaaaaAm Auktionshaus 'AH scannen' klicken\noder 'Nur Profit' ausschalten.|r"])
    else
        emptyText:SetText("")
    end

    local offset = math.max(0, math.floor(scroll:GetVerticalScroll() / ROW_H + 0.5))

    for i = 1, ROWS do
        local row = rows[i]
        local e = evaluated[offset + i]
        row.entry = e
        if not e then
            row:Hide()
        else
            row:Show()
            local r = e.recipe
            local out = r.output or {}
            local q = ns.Profit.QueueCount(r.key)

            row.qty:SetText(q > 0 and string.format("|cff44ff44%dx|r", q) or "")
            if q > 0 then row.queued:Show(); row.accent:Show() else row.queued:Hide(); row.accent:Hide() end

            local _, quality, icon = itemInfo(out.id)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            local name = string.format("|c%s%s|r", qualityHex(quality), ns.Str(r.name))
            if (out.count or 1) > 1 then
                name = name .. string.format(" |cffaaaaaax%d|r", out.count)
            end
            if multi and r.profession then
                name = name .. "  |cff777777" .. r.profession .. "|r"
            end
            if r.learned == false then
                name = "|cff777777" .. ns.Str(r.name) .. L[" (nicht gelernt)|r"]
            end
            row.name:SetText(name)

            -- Punkt nur, wenn das Rezept noch Skill gibt (grau = kein Punkt).
            local dc = r.difficulty and r.difficulty < 3 and DIFF_COLOR[r.difficulty]
            if dc then
                row.diff:SetColorTexture(dc[1], dc[2], dc[3], 1)
                row.diff:Show()
            else
                row.diff:Hide()
            end

            -- Angebotsmenge im AH (letzter Scan-Tag)
            local m = e.market
            if m and m.available then
                local col = m.available >= 20 and "|cffff8866" or (m.available <= 3 and "|cff66ff66" or "|cffdddddd")
                row.avail:SetText(col .. m.available .. "|r")
            else
                row.avail:SetText("|cff555555-|r")
            end

            if skillMode then
                row.cost:SetText(e.unknown == 0 and coins(e.cost) or "|cff777777?|r")
                row.rev:SetText(e.hasOutput and coins(e.revenue) or "|cff777777-|r")
                if e.skillCost then
                    local col = e.skillCost <= 0 and "|cff44ff44" or "|cffffffff"
                    row.profit:SetText(col .. coins(e.skillCost) .. "|r")
                else
                    row.profit:SetText(L["|cffffaa33Preis fehlt|r"])
                end
            elseif e.complete then
                row.cost:SetText(coins(e.cost))
                row.rev:SetText(coins(e.revenue))
                local col = e.profit >= 0 and "|cff44ff44" or "|cffff5555"
                -- Veralteter Preis -> grau, auffaellig hoher Preis -> "!"
                if e.stale then col = "|cff888888" end
                local mark = e.spike and " |cffffaa33!|r" or (e.stale and " |cff888888~|r" or "")
                row.profit:SetText(col .. coins(e.profit) .. "|r" .. mark)
            else
                row.cost:SetText(e.unknown == 0 and coins(e.cost) or "|cff777777?|r")
                row.rev:SetText(e.hasOutput and coins(e.revenue) or "|cff777777?|r")
                local missing = e.unknown + (e.hasOutput and 0 or 1)
                row.profit:SetText(string.format(missing == 1 and L["|cffffaa33%d Preis fehlt|r"]
                    or L["|cffffaa33%d Preise fehlen|r"], missing))
            end
        end
    end

    scrollChild:SetSize(ROW_W, math.max(ROWS * ROW_H, #evaluated * ROW_H))
    local maxScroll = math.max(0, scrollChild:GetHeight() - scroll:GetHeight())
    if scroll:GetVerticalScroll() > maxScroll then scroll:SetVerticalScroll(maxScroll) end

    local s = ns.Profit.QueueSummary()
    if s.crafts == 0 then
        footerText:SetText(L["|cff888888Queue leer - Rezepte anklicken, um sie einzuplanen.|r"])
    else
        local pc = s.profit >= 0 and "|cff44ff44" or "|cffff5555"
        footerText:SetText(string.format(
            L["|cffffd100Queue|r %d Crafts   |cff888888Kosten|r %s   |cff888888Verkauf|r %s   |cffffd100Gewinn|r %s%s|r"],
            s.crafts, coins(s.cost), coins(s.revenue), pc, coins(s.profit)))
    end

    updateCraftPanel()
end

--- Mehrere Ausloeser kurz hintereinander (Taschen, Crafts) -> ein Refresh.
local refreshPending = false
function UI.ScheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    ns.C_Timer_After(0.3, function()
        refreshPending = false
        UI.Refresh()
    end)
end

function UI.Toggle()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Im Kampf nicht moeglich - danach nochmal."])
        return
    end
    build()
    autoOpened = false
    if frame:IsShown() then
        frame:Hide()
    else
        if ns.Professions and #(ns.Professions.recipes or {}) == 0 then
            ns.Professions.ScanAsync(false)
        end
        frame:Show()
        UI.Refresh()
    end
end

-- Kampfbeginn: Fenster schliessen, solange das noch erlaubt ist
-- (PLAYER_REGEN_DISABLED kommt vor dem Combat-Lockdown). Die Berufs-Buttons
-- sind Secure-Buttons und duerfen im Kampf nicht gezeigt/versteckt werden.
-- Mit dem Berufsfenster oeffnen --------------------------------------------
-- TRADE_SKILL_SHOW -> Fenster auf, Liste auf den offenen Beruf filtern,
-- rechts neben das Berufsfenster setzen (solange nicht selbst verschoben).
-- TRADE_SKILL_CLOSE -> wieder zu, aber nur wenn es automatisch aufging.

local function professionFrame()
    for _, name in ipairs({ "ProfessionsFrame", "TradeSkillFrame" }) do
        local f = _G[name]
        if type(f) == "table" and f.IsShown and f:IsShown() then return f end
    end
    return nil
end

--- Offenen Beruf in der Liste waehlen (lockerer Namensvergleich).
local function filterToOpenProfession()
    if not frame or not frame:IsShown() then return end
    local open = ns.Profit.OpenProfession and ns.Profit.OpenProfession()
    if type(open) ~= "string" then return end
    local a = open:lower()
    for _, p in ipairs(professionList()) do
        local b = p.name:lower()
        if a:find(b, 1, true) or b:find(a, 1, true) then
            if profFilter ~= p.name then setFilter(p.name) end
            return
        end
    end
end

local function onProfessionShow()
    local db = ns.Config and ns.Config.db
    if not db or db.autoOpen == false then return end
    if InCombatLockdown and InCombatLockdown() then return end
    build()
    if not frame:IsShown() then
        UI.Toggle()
        autoOpened = true
        local pf = professionFrame()
        if pf and not userMoved then
            frame:ClearAllPoints()
            -- Platz fuer die Berufe-Leiste links am Fenster lassen.
            frame:SetPoint("TOPLEFT", pf, "TOPRIGHT", SIDE_W + 4, 0)
        end
    end
    filterToOpenProfession()
    -- Berufsdaten sind beim Event evtl. noch nicht fertig -> nochmal.
    ns.C_Timer_After(0.5, filterToOpenProfession)
end

local function onProfessionClose()
    if autoOpened and frame and frame:IsShown()
       and not (InCombatLockdown and InCombatLockdown()) then
        frame:Hide()
    end
    autoOpened = false
end

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:RegisterEvent("BAG_UPDATE_DELAYED")
combat:RegisterEvent("TRADE_SKILL_SHOW")
combat:RegisterEvent("TRADE_SKILL_CLOSE")
combat:SetScript("OnEvent", function(_, event)
    if event == "TRADE_SKILL_SHOW" then
        onProfessionShow()
        return
    elseif event == "TRADE_SKILL_CLOSE" then
        onProfessionClose()
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        -- Material gekauft/hergestellt -> Herstellliste aktualisieren.
        if frame and frame:IsShown() then UI.ScheduleRefresh() end
        return
    end
    if frame and frame:IsShown() then frame:Hide() end
end)