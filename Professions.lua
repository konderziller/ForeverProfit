--[[--------------------------------------------------------------------------
  ForeverProfit - Professions   (v0.5.0)

  FIX v0.5.0 (aus dem In-Game-Report):
   * "Skinning: 132 Rezepte" == Leatherworking und Koch-Rezepte unter Skinning
     -> C_TradeSkillUI.GetAllRecipeIDs(skillLineID) liefert offenbar eine
        GEMEINSAME Liste, unabhaengig vom Argument.
     -> Lösung: jedes Rezept mit IsRecipeInSkillLine(recipeID, skillLineID)
        gegen den Beruf pruefen. Nur Treffer werden uebernommen.
   * Kochen / Erste Hilfe fehlten -> GetChildProfessionInfos()/GetBaseProfessionInfo()
     als zusaetzliche Berufsquelle.
   * Dedupe jetzt nach skillLineID (nicht nach Name) - sonst verschmelzen Berufe.

  Belegte Signaturen (Forever-Referenz + Probe):
    GetAllProfessionTradeSkillLines()            -> number[]
    GetBaseProfessionInfo()                      -> ProfessionInfo
    GetChildProfessionInfo()                     -> ProfessionInfo
    GetChildProfessionInfos()                    -> ProfessionInfo[]
    GetProfessionInfoBySkillLineID(skillLineID)  -> ProfessionInfo
    GetAllRecipeIDs([skillLineID])               -> number[]   (Argument unzuverlaessig!)
    IsRecipeInSkillLine(recipeID, skillLineID)   -> bool   <-- der Filter
    IsRecipeInBaseSkillLine(recipeID)            -> bool
    GetRecipeInfo(recipeSpellID)                 -> TradeSkillRecipeInfo
    GetRecipeSchematic(recipeSpellID, isRecraft) -> CraftingRecipeSchematic
    GetRecipeOutputItemData(recipeSpellID)       -> CraftingRecipeOutputInfo
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local Professions = {}
ns.Professions = Professions

Professions.professions = {}
Professions.recipes      = {}
Professions.mode         = "none"
Professions.lastScan     = 0
Professions.lastError    = nil
Professions.running      = false
Professions.progress     = { done = 0, total = 0 }

local CHUNK  = 25
local BUDGET = 0.03

-- Helfer --------------------------------------------------------------------

local function pick(t, keys)
    if type(t) ~= "table" then return nil end
    for _, k in ipairs(keys) do
        local v = t[k]
        if v ~= nil and not ns.IsSecret(v) then return v end
    end
    return nil
end

local function isDNT(name)
    return type(name) == "string" and name:find("%[DNT%]") ~= nil
end

local function ItemNameFromLink(link)
    if type(link) ~= "string" or ns.IsSecret(link) then return nil end
    local ok, name = ns.Call(GetItemInfo, link)
    if ok and type(name) == "string" then return name end
    return link:match("%[(.-)%]")
end

local function parseReagents(sch)
    local out = {}
    if type(sch) ~= "table" or ns.IsSecretTable(sch) then return out end
    local slots = pick(sch, { "reagentSlotSchematics" })
    if type(slots) ~= "table" then return out end
    for _, slot in ipairs(slots) do
        if type(slot) == "table" and not ns.IsSecretTable(slot) then
            local qty    = tonumber(ns.Value(slot.quantityRequired, 1)) or 1
            local req    = ns.Value(slot.required, true)
            local hidden = ns.Value(slot.hiddenInCraftingForm, false)
            local list   = slot.reagents
            if type(list) == "table" and type(list[1]) == "table" then
                local rid = ns.Value(list[1].itemID, nil)
                if rid and req ~= false and hidden ~= true then
                    out[#out + 1] = { id = tonumber(rid), name = nil, count = qty }
                end
            end
        end
    end
    return out
end

local function parseOutput(outData, sch)
    local o = { id = nil, name = nil, count = 1, link = nil }
    if type(outData) == "table" and not ns.IsSecretTable(outData) then
        o.id   = tonumber(ns.Value(outData.itemID, nil))
        o.link = ns.Value(outData.hyperlink, nil)
    end
    if type(sch) == "table" and not ns.IsSecretTable(sch) then
        if not o.id then o.id = tonumber(ns.Value(sch.outputItemID, nil)) end
        local qmin = tonumber(ns.Value(sch.quantityMin, nil))
        if qmin and qmin > 0 then o.count = qmin end
    end
    if type(o.link) == "string" then o.name = ItemNameFromLink(o.link) end
    return o
end

-- Berufe ermitteln ----------------------------------------------------------

--- Sammelt alle Berufe: Primaer (GetAllProfessionTradeSkillLines) +
--- Sekundaer (GetChildProfessionInfos/GetBaseProfessionInfo).
--- Dedupe nach skillLineID, nicht nach Name.
local function collectProfessions()
    local byID  = {}
    local order = {}

    local function add(slID, info)
        if type(slID) ~= "number" then return end
        local name = pick(info, { "professionName", "name" })
        if type(name) ~= "string" or isDNT(name) then return end
        local level  = tonumber(ns.Value(pick(info, { "skillLevel" }), 0)) or 0
        local parent = pick(info, { "parentProfessionID" })
        if not byID[slID] then
            order[#order + 1] = slID
        end
        byID[slID] = {
            id = slID, name = name, skillLevel = level,
            maxSkillLevel = tonumber(ns.Value(pick(info, { "maxSkillLevel" }), 0)) or 0,
            isPrimary = ns.Value(pick(info, { "isPrimaryProfession" }), false),
            parentID = parent, info = info,
        }
    end

    local function infoFor(slID)
        if type(C_TradeSkillUI.GetProfessionInfoBySkillLineID) == "function" then
            local ok, info = ns.Call(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slID)
            if ok and type(info) == "table" then return info end
        end
        return nil
    end

    -- Primaerberufe
    local ok, list = ns.Call(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if ok and type(list) == "table" then
        for _, slID in ipairs(list) do add(slID, infoFor(slID)) end
    end

    -- Basis-/Kind-Berufe (Sekundaerberufe wie Kochen, Erste Hilfe)
    local function addInfo(info)
        if type(info) ~= "table" then return end
        local slID = pick(info, { "skillLineID", "skillID" })
        if not slID and type(C_TradeSkillUI.GetProfessionSkillLineID) == "function" then
            -- Profession-Typ -> skillLineID (falls es ein Enum ist)
            local ok2, id2 = ns.Call(C_TradeSkillUI.GetProfessionSkillLineID, pick(info, { "profession" }))
            if ok2 and type(id2) == "number" then slID = id2 end
        end
        if slID then add(slID, info) end
    end
    if type(C_TradeSkillUI.GetBaseProfessionInfo) == "function" then
        local okB, base = ns.Call(C_TradeSkillUI.GetBaseProfessionInfo)
        if okB then addInfo(base) end
    end
    if type(C_TradeSkillUI.GetChildProfessionInfos) == "function" then
        local okC, kids = ns.Call(C_TradeSkillUI.GetChildProfessionInfos)
        if okC and type(kids) == "table" then
            for _, k in ipairs(kids) do addInfo(k) end
        end
    end

    -- Zauberbuch-Berufe (GetProfessions): hier steht u.a. Kochen, das die
    -- C_TradeSkillUI-Listen auf Forever nicht liefern.
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        local okP, p1, p2, arch, fish, cook, aid = pcall(GetProfessions)
        if okP then
            for _, idx in ipairs({ p1 or false, p2 or false, arch or false, fish or false,
                                   cook or false, aid or false }) do
                if idx then
                    local okI, name, _, rank, maxRank, _, _, skillLine = pcall(GetProfessionInfo, idx)
                    skillLine = okI and tonumber(ns.Value(skillLine, nil))
                    if skillLine and not byID[skillLine] then
                        add(skillLine, { professionName = ns.Value(name, nil),
                                         skillLevel = ns.Value(rank, 0),
                                         maxSkillLevel = ns.Value(maxRank, 0) })
                    end
                end
            end
        end
    end

    local out = {}
    for _, slID in ipairs(order) do
        local p = byID[slID]
        if (p.skillLevel or 0) > 0 then out[#out + 1] = p end
    end
    -- Fallback, falls skillLevel nicht lesbar/secret war.
    if #out == 0 then
        for _, slID in ipairs(order) do out[#out + 1] = byID[slID] end
    end
    return out
end

--- Prueft, ob ein Rezept wirklich zu dieser Skill-Line gehoert.
local function recipeBelongsTo(recipeID, skillLineID)
    if type(C_TradeSkillUI.IsRecipeInSkillLine) == "function" then
        local ok, res = ns.Call(C_TradeSkillUI.IsRecipeInSkillLine, recipeID, skillLineID)
        if ok and res ~= nil then return res == true end
    end
    return nil   -- unbekannt -> nicht filtern (besser als alles verlieren)
end

--- Kandidaten-Rezept-IDs fuer eine Skill-Line.
local function candidateRecipeIDs(skillLineID)
    local ids = {}
    if type(C_TradeSkillUI.GetAllRecipeIDs) == "function" then
        local ok, list = ns.Call(C_TradeSkillUI.GetAllRecipeIDs, skillLineID)
        if ok and type(list) == "table" then
            for _, v in ipairs(list) do if type(v) == "number" then ids[#ids + 1] = v end end
        end
    end
    if #ids == 0 and type(C_TradeSkillUI.GetProfessionSpells) == "function" then
        local ok, info = ns.Call(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        local professionID = (ok and type(info) == "table" and pick(info, { "professionID" })) or skillLineID
        local ok2, list = ns.Call(C_TradeSkillUI.GetProfessionSpells, professionID, skillLineID)
        if ok2 and type(list) == "table" then
            for _, v in ipairs(list) do if type(v) == "number" then ids[#ids + 1] = v end end
        end
    end
    return ids
end

local function readRecipe(recipeID, skillLineID, professionName)
    local okI, info = ns.Call(C_TradeSkillUI.GetRecipeInfo, recipeID)
    if not okI or type(info) ~= "table" then return nil end

    if ns.Value(info.isGatheringRecipe, false) or
       ns.Value(info.isDummyRecipe, false) or
       ns.Value(info.disabled, false) then
        return nil
    end

    local okS, sch = ns.Call(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not okS then sch = nil end
    local okO, outData = ns.Call(C_TradeSkillUI.GetRecipeOutputItemData, recipeID)
    if not okO then outData = nil end

    local r = {
        key        = "r:" .. tostring(recipeID),
        recipeID   = recipeID,
        spellID    = recipeID,
        name       = ns.Str(ns.Value(info.name, nil), L["Rezept "] .. tostring(recipeID)),
        profession = professionName,
        skillLine  = skillLineID,
        learned    = ns.Value(info.learned, nil),
        -- Skill-Farbe: 0 orange, 1 gelb, 2 gruen, 3 grau (nil = unbekannt)
        difficulty = tonumber(ns.Value(info.relativeDifficulty, nil)),
        skillUps   = tonumber(ns.Value(info.numSkillUps, nil)),
        output     = parseOutput(outData, sch),
        reagents   = parseReagents(sch),
    }
    if r.output.id or #r.reagents > 0 then return r end
    return nil
end

-- Asynchroner Scan ----------------------------------------------------------

local driver = CreateFrame("Frame")
local queue, cursor, scanVerbose, lastProgressPrint, progressStep
local addedRecipes = {}

local function progressPrint(force)
    if not scanVerbose then return end
    local p = Professions.progress
    if p.total <= 0 then return end
    local now = time()
    local pct = math.floor(p.done / p.total * 100)
    if force or pct >= progressStep or (now - lastProgressPrint) >= 2 then
        progressStep = pct + 10
        lastProgressPrint = now
        ns:Print(string.format(L["Scan: %d/%d (%d%%) - %d Rezepte uebernommen"],
            p.done, p.total, pct, #Professions.recipes))
    end
end

-- Rezept-Cache pro Charakter ------------------------------------------------
-- Nach einem frischen Client-Start liefert C_TradeSkillUI oft erst Rezepte,
-- wenn das Berufsfenster offen war. Deshalb das letzte gute Ergebnis in den
-- SavedVariables halten und bei leerem Scan wiederherstellen.

local function charCache()
    if type(ForeverProfitDB) ~= "table" then return nil end
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if not name then return nil end
    local key = tostring(name) .. "-" .. tostring(realm or "?")
    ForeverProfitDB.chars = ForeverProfitDB.chars or {}
    ForeverProfitDB.chars[key] = ForeverProfitDB.chars[key] or {}
    return ForeverProfitDB.chars[key]
end

local function saveCache()
    local c = charCache()
    if not c then return end
    c.recipes     = Professions.recipes
    c.professions = {}
    for _, p in ipairs(Professions.professions) do
        c.professions[#c.professions + 1] = { id = p.id, name = p.name, skillLevel = p.skillLevel,
                                              maxSkillLevel = p.maxSkillLevel, parentID = p.parentID }
    end
    c.savedAt = time()
end

--- Gespeicherte Rezepte laden, falls aktuell keine da sind.
--- Rueckgabe: true wenn etwas geladen wurde.
function Professions.RestoreCache()
    if #Professions.recipes > 0 then return false end
    local c = charCache()
    if not (c and type(c.recipes) == "table" and #c.recipes > 0) then return false end
    Professions.recipes     = c.recipes
    Professions.professions = c.professions or {}
    Professions.mode        = "cache"
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    return true
end

--- Gespeicherte Rezepte von Berufen uebernehmen, fuer die dieser Scan
--- nichts geliefert hat. Das Spiel liefert die Rezeptliste teils nur fuer
--- das zuletzt geoeffnete Berufsfenster (z.B. Kochen) - ohne Merge wuerden
--- die anderen Berufe dabei verschwinden.
local function mergeCachedRecipes()
    local c = charCache()
    if not (c and type(c.recipes) == "table") then return end
    local found, owned = {}, {}
    for _, r in ipairs(Professions.recipes) do
        if r.profession then found[r.profession] = true end
        addedRecipes[r.recipeID or 0] = true
    end
    for _, p in ipairs(Professions.professions) do
        if p.name then owned[p.name] = true end
    end
    for _, r in ipairs(c.recipes) do
        local prof = r.profession
        if prof and owned[prof] and not found[prof] and not addedRecipes[r.recipeID or 0] then
            addedRecipes[r.recipeID or 0] = true
            Professions.recipes[#Professions.recipes + 1] = r
        end
    end
end

local function finishScan()
    Professions.running = false
    Professions.lastScan = time()
    driver:SetScript("OnUpdate", nil)
    Professions.mode = (#Professions.recipes > 0) and "modern" or "modern-leer"
    if #Professions.recipes > 0 then
        mergeCachedRecipes()
        saveCache()
    else
        Professions.lastError = L["keine Rezepte nach Filter"]
        if Professions.RestoreCache() and scanVerbose then
            ns:Print(L["Spiel liefert gerade keine Rezepte - nutze die gespeicherten. Berufsfenster oeffnen aktualisiert sie."])
            scanVerbose = false
        end
    end

    if scanVerbose then
        if #Professions.recipes > 0 then
            ns:Print(string.format(L["Fertig: %d Rezepte."], #Professions.recipes))
            for _, p in ipairs(Professions.professions) do
                local cnt = 0
                for _, r in ipairs(Professions.recipes) do
                    if r.skillLine == p.id then cnt = cnt + 1 end
                end
                local mark = (cnt > 0) and "" or L["  |cff888888(keine Rezepte)|r"]
                ns:Print(string.format(L["   %s: %d Rezepte (Skill %s)%s"],
                    p.name, cnt, ns.Str(p.skillLevel, "?"), mark))
            end
        else
            ns:Print(L["|cffffcc00Keine Rezepte uebernommen.|r "] .. ns.Str(Professions.lastError, ""))
        end
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function tick(_, elapsed)
    local spent, processed = 0, 0
    while cursor <= #queue and processed < CHUNK and spent < BUDGET do
        local job = queue[cursor]
        local t0 = (type(debugprofilestop) == "function") and debugprofilestop() or 0

        -- Filter: gehoert das Rezept wirklich zu diesem Beruf?
        -- Doppelte (Haupt- + Unterberuf mit eigener skillLineID) verwerfen.
        local belongs = recipeBelongsTo(job.recipeID, job.skillLine)
        if belongs ~= false and not addedRecipes[job.recipeID] then
            local r = readRecipe(job.recipeID, job.skillLine, job.profession)
            if r then
                addedRecipes[job.recipeID] = true
                Professions.recipes[#Professions.recipes + 1] = r
            end
        end
        Professions.progress.done = cursor

        cursor = cursor + 1
        processed = processed + 1
        if t0 ~= 0 and type(debugprofilestop) == "function" then
            spent = spent + (debugprofilestop() - t0) / 1000
        end
    end
    progressPrint(false)
    if cursor > #queue then finishScan() end
end

function Professions.Stop()
    if not Professions.running then return end
    driver:SetScript("OnUpdate", nil)
    Professions.running = false
    ns:Print(string.format(L["Scan abgebrochen (%d/%d, %d Rezepte)."],
        Professions.progress.done, Professions.progress.total, #Professions.recipes))
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

function Professions.ScanAsync(verbose)
    if Professions.running then
        if verbose then ns:Print(L["Scan laeuft schon - /fp stop bricht ab."]) end
        return
    end
    if type(C_TradeSkillUI) ~= "table" then
        ns:Print("|cffff5555C_TradeSkillUI fehlt|r")
        return
    end

    Professions.recipes     = {}
    Professions.professions = {}
    Professions.lastError   = nil
    queue, cursor, scanVerbose = {}, 1, verbose
    lastProgressPrint, progressStep = 0, 10

    local owned = collectProfessions()
    if #owned == 0 then
        Professions.lastError = L["keine Berufe erkannt"]
        if not Professions.RestoreCache() and verbose then
            ns:Print(L["|cffffcc00Keine Berufe erkannt.|r Berufsfenster einmal oeffnen."])
        end
        return
    end
    Professions.professions = owned

    -- Hier NICHT deduplizieren: GetAllRecipeIDs liefert fuer jeden Beruf
    -- dieselbe gemeinsame Liste, die Zuordnung passiert erst im tick per
    -- IsRecipeInSkillLine. Doppelte werden dort nach der Pruefung verworfen.
    addedRecipes = {}
    for _, p in ipairs(owned) do
        local ids = candidateRecipeIDs(p.id)
        local kept = 0
        for _, rid in ipairs(ids) do
            queue[#queue + 1] = { recipeID = rid, skillLine = p.id, profession = p.name }
            kept = kept + 1
        end
        if verbose then
            ns:Print(string.format(L["   %s: %d Kandidaten (Skill %s)"], p.name, kept, ns.Str(p.skillLevel, "?")))
        end
    end

    Professions.progress = { done = 0, total = #queue }
    if #queue == 0 then
        Professions.lastError = L["keine Rezept-Kandidaten"]
        if not Professions.RestoreCache() and verbose then
            ns:Print(L["|cffffcc00Keine Rezepte vom Spiel.|r Berufsfenster einmal oeffnen."])
        end
        return
    end

    Professions.running = true
    if verbose then
        ns:Print(string.format(L["Scanne %d Kandidaten in %d Beruf(en) - Filter aktiv. Abbruch: /fp stop"],
            #queue, #owned))
    end
    driver:SetScript("OnUpdate", tick)
end

-- PROBE ---------------------------------------------------------------------

local function yn(b) return b and "|cff44ff44ja|r" or "|cffff5555nein|r" end
local function dumpFields(label, tbl)
    ns:Print("   " .. label .. ": { " .. table.concat(ns.Describe(tbl), ", ") .. " }")
end

function Professions.Probe()
    ns:Print("=== ForeverProfit Probe v" .. ns.version .. " ===")
    ns:Print(string.format("Build: %s | TOC: %s", tostring(ns.build), tostring(ns.toc)))

    ns:Print("-- Berufe (skillLevel>0) --")
    local owned = collectProfessions()
    for i, p in ipairs(owned) do
        ns:Print(string.format("   [%d] %s  id=%s Skill=%s primary=%s",
            i, p.name, ns.Str(p.id), ns.Str(p.skillLevel), ns.Str(p.isPrimary)))
    end

    ns:Print("-- Rezept-Zuordnung (Filter-Test) --")
    ns:Print("   IsRecipeInSkillLine: " .. yn(type(C_TradeSkillUI) == "table" and
        type(C_TradeSkillUI.IsRecipeInSkillLine) == "function"))
    if #owned >= 1 then
        local p = owned[1]
        local ids = candidateRecipeIDs(p.id)
        ns:Print(string.format("   %s: %d Kandidaten von GetAllRecipeIDs", p.name, #ids))
        local inLine, other = 0, 0
        for n, rid in ipairs(ids) do
            if n <= 200 then
                local b = recipeBelongsTo(rid, p.id)
                if b == true then inLine = inLine + 1
                elseif b == false then other = other + 1 end
            end
        end
        ns:Print(string.format("   davon IsRecipeInSkillLine=true: %d, false: %d (von max 200 geprueft)",
            inLine, other))
    end

    local first = Professions.recipes and Professions.recipes[1]
    if first and first.recipeID then
        local okI, info = ns.Call(C_TradeSkillUI.GetRecipeInfo, first.recipeID)
        if okI and type(info) == "table" then
            dumpFields("GetRecipeInfo(" .. first.recipeID .. ")", info)
            ns:Print(string.format("   relativeDifficulty=%s numSkillUps=%s",
                ns.Str(info.relativeDifficulty), ns.Str(info.numSkillUps)))
        end
    end

    ns:Print("-- Preisquellen --")
    for _, l in ipairs(ns.Prices.Detect()) do ns:Print("   " .. l) end

    ns:Print("-- Native Auction-House-API --")
    ns:Print("   C_AuctionHouse: " .. yn(type(C_AuctionHouse) == "table"))
    for _, fn in ipairs({ "ReplicateItems", "GetNumReplicateItems", "GetReplicateItemInfo",
        "GetCommoditySearchResultInfo", "HasFullCommoditySearchResults" }) do
        ns:Print(string.format("   C_AuctionHouse.%s: %s", fn,
            yn(type(C_AuctionHouse) == "table" and type(C_AuctionHouse[fn]) == "function")))
    end

    -- ReplicateItems wirklich aufrufen und den Fehlertext zeigen.
    if type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ReplicateItems) == "function" then
        local ok, err = ns.Call(C_AuctionHouse.ReplicateItems)
        ns:Print("   ReplicateItems()-Test: " .. (ok and "|cff44ff44ok|r" or ("|cffff5555" .. ns.Str(err) .. "|r")))
        ns.C_Timer_After(2, function()
            local okN, _, nR = ns.Pack(C_AuctionHouse.GetNumReplicateItems)
            ns:Print("   GetNumReplicateItems nach 2s: " .. ns.Str(okN and nR[1])
                .. " (0 = Liste kam nicht)")
        end)
    end

    ns:Print("-- Auctionator-Spuren (Globals) --")
    local found = ns.ScanGlobals("[Aa]uctionator", 60)
    if #found == 0 then
        ns:Print("   |cffff5555keine Globals mit 'uctionator'|r")
    else
        for _, gg in ipairs(found) do ns:Print("   " .. gg) end
    end

    ns:Print("-- Preis-Test (erstes Reagenz) --")
    local testID
    for _, r in ipairs(Professions.recipes or {}) do
        if r.reagents and r.reagents[1] and r.reagents[1].id then testID = r.reagents[1].id; break end
    end
    if not testID then
        ns:Print("   kein Reagenz zum Testen (erst /fp scan)")
    else
        ns:Print("   Testitem-ID: " .. tostring(testID))
        for _, fn in ipairs({ "Atr_GetAuctionPrice", "Atr_GetAuctionBuyout", "GetAuctionBuyout" }) do
            if type(_G[fn]) == "function" then
                local ok2, v = ns.Call(_G[fn], testID)
                ns:Print(string.format("   %s(%d) -> %s", fn, testID, ok2 and ns.Str(v) or "Fehler"))
            end
        end
        local p1 = ns.Prices.Get(testID)
        ns:Print("   ns.Prices.Get -> " .. (p1 and ns.Money(p1) or "|cffff5555nil|r")
            .. " (Quelle: " .. ns.Str(ns.Prices.source) .. ")")
    end

    ns:Print("=== Ende Probe ===")
end

-- Events --------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED",
                     "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE" }) do
    ns.Try(ev.RegisterEvent, ev, e)
end

local lastAuto = 0
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        Professions.RestoreCache()
        ns.C_Timer_After(3, function() Professions.ScanAsync(false) end)
        return
    end
    local now = time()
    if not Professions.running and (now - lastAuto) > 5 then
        lastAuto = now
        ns.C_Timer_After(1.5, function() Professions.ScanAsync(false) end)
    end
end)
