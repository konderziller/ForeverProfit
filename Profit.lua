--[[--------------------------------------------------------------------------
  ForeverProfit - Profit   (v0.9.0)

  Rechnung: Reagenzien-Kosten vs. Verkaufspreis des Ergebnisses.
  Es werden KEINE Werte erfunden - fehlt ein Preis, wird das Rezept als
  "unvollstaendig" markiert und nicht als profitabel ausgegeben.

  v0.9.0:
   * Teilrezepte: Kann der Char ein Reagenz selbst herstellen und ist das
     billiger als Kaufen (AH/Haendler), zaehlt der Herstellungspreis.
     Rekursiv bis MAX_DEPTH, mit Zyklus-Schutz.
   * Queue mit Anzahl: db.queue[recipeKey] = Anzahl Crafts.
   * Einkaufsliste: Queue -> benoetigte Items, minus Taschen+Bank, Teil-
     rezepte werden aufgeloest. AH-Items gehen als Shopping-Liste an
     Auctionator, Haendler-Items werden im Chat aufgelistet.
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local L = ns.L

local Profit = {}
ns.Profit = Profit

local MAX_DEPTH = 3
local SHOPPING_LIST_NAME = "ForeverProfit"

-- Pro Durchlauf neu aufgebaut (Preise koennen sich jederzeit aendern).
local memo, producers

local function cutFactor()
    local db = ns.Config and ns.Config.db
    return 1 - ((db and tonumber(db.ahCut)) or 0.05)
end

local function useSubCrafts()
    local db = ns.Config and ns.Config.db
    return not db or db.useSubCrafts ~= false
end

--- Index: itemID -> Liste gelernter Rezepte, die das Item herstellen.
local function buildProducers()
    producers = {}
    for _, r in ipairs(ns.Professions.recipes or {}) do
        local out = r.output
        if out and out.id and r.learned ~= false then
            local list = producers[out.id]
            if not list then list = {}; producers[out.id] = list end
            list[#list + 1] = r
        end
    end
end

--- Neuen Rechen-Durchlauf beginnen (Memo leeren).
function Profit.Begin()
    memo = {}
    buildProducers()
    if ns.Prices.BeginPass then ns.Prices.BeginPass() end
end

-- Skill-Chance je Farbe (Naeherung): orange immer, gelb meistens, gruen selten.
local SKILL_CHANCE = { [0] = 1.0, [1] = 0.6, [2] = 0.25 }
Profit.SKILL_CHANCE = SKILL_CHANCE

local STALE_DAYS = 3      -- Preis aelter -> "veraltet"
local SPIKE_FACTOR = 1.5  -- aktueller Preis > 1.5x Median -> "auffaellig hoch"

local function ensurePass()
    if not memo then Profit.Begin() end
end

local unitCost

--- Herstellungskosten pro Stueck fuer ein Rezept, oder nil wenn ein
--- Reagenz keinen Preis hat.
local function craftCostPerUnit(recipe, depth, visiting)
    local total = 0
    for _, rg in ipairs(recipe.reagents or {}) do
        local p = unitCost(rg.id, rg.name, depth + 1, visiting)
        if not p then return nil end
        total = total + p * (rg.count or 1)
    end
    local outCount = (recipe.output and recipe.output.count) or 1
    return total / math.max(outCount, 1)
end

--- Guenstigster Stueckpreis fuer ein Reagenz.
--- Rueckgabe: preis, quelle ("vendor" | "ah" | "craft"), rezept (bei craft)
unitCost = function(itemID, name, depth, visiting)
    depth = depth or 0
    local key = itemID or name
    if key == nil then return nil end
    if depth == 0 and memo[key] then
        local m = memo[key]
        return m.price, m.src, m.recipe
    end

    local best, src, viaRecipe = ns.Prices.GetReagent(itemID, name)

    if useSubCrafts() and itemID and depth < MAX_DEPTH and producers[itemID]
       and not visiting[itemID] then
        visiting[itemID] = true
        for _, r in ipairs(producers[itemID]) do
            local c = craftCostPerUnit(r, depth, visiting)
            if c and (not best or c < best) then
                best, src, viaRecipe = c, "craft", r
            end
        end
        visiting[itemID] = nil
    end

    if depth == 0 then
        memo[key] = { price = best, src = src, recipe = viaRecipe }
    end
    return best, src, viaRecipe
end

--- Oeffentlich fuer Tooltip/Einkaufsliste.
function Profit.ReagentCost(itemID, name)
    ensurePass()
    return unitCost(itemID, name, 0, {})
end

--- Bewertet ein Rezept.
function Profit.Evaluate(recipe)
    ensurePass()
    local cost, unknown = 0, 0
    local details = {}
    -- Das Rezept selbst als "besucht" markieren: ein Rezept darf seine
    -- eigene Ausgabe nicht als Teilrezept nutzen.
    local visiting = {}
    if recipe.output and recipe.output.id then visiting[recipe.output.id] = true end

    for _, rg in ipairs(recipe.reagents or {}) do
        local p, src, via = unitCost(rg.id, rg.name, 0, visiting)
        details[#details + 1] = { id = rg.id, name = rg.name, count = rg.count or 1,
                                  unit = p, src = src, via = via }
        if p then
            cost = cost + p * (rg.count or 1)
        else
            unknown = unknown + 1
        end
    end
    cost = math.floor(cost + 0.5)

    local out = recipe.output or {}
    local outPrice = ns.Prices.GetForID(out.id, out.name)
    local revenue = math.floor((outPrice or 0) * (out.count or 1) * cutFactor())

    local profit = revenue - cost

    -- Marktlage des Ergebnisses
    local market = out.id and ns.Prices.Market(out.id)
    local stale, spike = false, false
    if outPrice and market then
        stale = (market.age == nil) or (market.age >= STALE_DAYS)
        spike = market.median ~= nil and market.days >= 3 and outPrice > market.median * SPIKE_FACTOR
    end

    -- Skill-Kosten: was kostet ein erwarteter Skillpunkt (Kosten minus Verkauf)?
    local skillCost
    local chance = recipe.difficulty and SKILL_CHANCE[recipe.difficulty]
    if chance and unknown == 0 then
        local net = cost - (outPrice and revenue or 0)
        skillCost = net / chance
    end

    return {
        recipe    = recipe,
        cost      = cost,
        revenue   = revenue,
        profit    = profit,
        margin    = revenue > 0 and (profit / revenue) or 0,
        unknown   = unknown,
        details   = details,
        hasOutput = outPrice ~= nil,
        complete  = (unknown == 0 and outPrice ~= nil),
        market    = market,
        stale     = stale,
        spike     = spike,
        skillCost = skillCost,
    }
end

--- Alle Rezepte bewerten, nach Gewinn sortiert.
--- Mit db.onlyProfit nur vollstaendig bepreiste Rezepte mit Gewinn > 0.
--- Zweiter Rueckgabewert: Anzahl ausgeblendeter Rezepte.
function Profit.All()
    Profit.Begin()
    local db = ns.Config and ns.Config.db
    local onlyProfit = db and db.onlyProfit
    local onlyLearned = db and db.onlyLearned
    local queue = db and db.queue or {}
    local rows, hidden = {}, 0

    -- Skill-Modus: gelernte Rezepte, die noch Skill geben, billigste zuerst.
    if db and db.mode == "skill" then
        for _, r in ipairs(ns.Professions.recipes or {}) do
            local d = r.difficulty
            if r.learned ~= false and d and SKILL_CHANCE[d] then
                rows[#rows + 1] = Profit.Evaluate(r)
            else
                hidden = hidden + 1
            end
        end
        table.sort(rows, function(a, b)
            if (a.skillCost ~= nil) ~= (b.skillCost ~= nil) then return a.skillCost ~= nil end
            if a.skillCost and b.skillCost and a.skillCost ~= b.skillCost then
                return a.skillCost < b.skillCost
            end
            return (a.recipe.difficulty or 9) < (b.recipe.difficulty or 9)
        end)
        return rows, hidden
    end

    for _, r in ipairs(ns.Professions.recipes or {}) do
        local e = Profit.Evaluate(r)
        -- In der Queue = immer sichtbar, sonst verschwindet die Auswahl.
        local queued = queue[r.key]
        -- learned == nil (unlesbar) zaehlt als gelernt, damit nichts verschwindet.
        if not queued and onlyLearned and r.learned == false then
            hidden = hidden + 1
        elseif queued or not onlyProfit or (e.complete and e.profit > 0) then
            rows[#rows + 1] = e
        else
            hidden = hidden + 1
        end
    end
    table.sort(rows, function(a, b)
        if a.complete ~= b.complete then return a.complete end
        return (a.profit or 0) > (b.profit or 0)
    end)
    return rows, hidden
end

-- Queue ---------------------------------------------------------------------

--- Anzahl in der Queue (alte Saves hatten `true` statt Zahl).
function Profit.QueueCount(key)
    local db = ns.Config and ns.Config.db
    local v = db and db.queue and db.queue[key]
    if v == true then return 1 end
    return tonumber(v) or 0
end

function Profit.QueueAdd(key, delta)
    local db = ns.Config and ns.Config.db
    if not (db and key) then return end
    local n = Profit.QueueCount(key) + delta
    db.queue[key] = (n > 0) and n or nil
end

function Profit.QueueClear()
    local db = ns.Config and ns.Config.db
    if db then db.queue = {} end
end

--- Zusammenfassung fuer die Queue.
function Profit.QueueSummary()
    Profit.Begin()
    local crafts, cost, revenue, recipes = 0, 0, 0, 0
    for _, r in ipairs(ns.Professions.recipes or {}) do
        local n = Profit.QueueCount(r.key)
        if n > 0 then
            local e = Profit.Evaluate(r)
            recipes = recipes + 1
            crafts  = crafts + n
            cost    = cost + e.cost * n
            revenue = revenue + e.revenue * n
        end
    end
    return { recipes = recipes, crafts = crafts, cost = cost, revenue = revenue,
             profit = revenue - cost }
end

-- Einkaufsliste -------------------------------------------------------------

local function itemName(id)
    if not id or type(GetItemInfo) ~= "function" then return nil end
    local name = ns.Try(GetItemInfo, id)
    if type(name) == "string" then return name end
    -- Item-Info anfordern, beim naechsten Klick ist der Name da.
    if type(C_Item) == "table" and type(C_Item.RequestLoadItemDataByID) == "function" then
        ns.Try(C_Item.RequestLoadItemDataByID, id)
    end
    return nil
end

--- Berechnet, was gekauft werden muss.
--- Rueckgabe: { ah = {[id]=n}, vendor = {[id]=n}, unknown = {[id]=n}, crafts = {[id]=n} }
function Profit.BuildShopping()
    Profit.Begin()
    local avail = {}
    local result = { ah = {}, vendor = {}, unknown = {}, crafts = {}, craftRecipes = {} }

    local function have(id)
        if avail[id] == nil then
            local n = 0
            if type(GetItemCount) == "function" then
                n = tonumber(ns.Try(GetItemCount, id, true)) or 0
            end
            avail[id] = n
        end
        return avail[id]
    end

    local function need(id, name, n, depth, visiting)
        if not id or n <= 0 then return end
        local take = math.min(have(id), n)
        avail[id] = avail[id] - take
        n = n - take
        if n <= 0 then return end

        local p, src, via = unitCost(id, name, 0, visiting)
        if src == "craft" and via and depth < MAX_DEPTH and not visiting[id] then
            local outCount = (via.output and via.output.count) or 1
            local times = math.ceil(n / math.max(outCount, 1))
            result.crafts[id] = (result.crafts[id] or 0) + times
            result.craftRecipes[id] = via
            visiting[id] = true
            for _, rg in ipairs(via.reagents or {}) do
                need(rg.id, rg.name, (rg.count or 1) * times, depth + 1, visiting)
            end
            visiting[id] = nil
        elseif src == "vendor" then
            result.vendor[id] = (result.vendor[id] or 0) + n
        elseif src == "ah" or src == "manual" then
            result.ah[id] = (result.ah[id] or 0) + n
        else
            result.unknown[id] = (result.unknown[id] or 0) + n
        end
    end

    for _, r in ipairs(ns.Professions.recipes or {}) do
        local times = Profit.QueueCount(r.key)
        if times > 0 then
            local visiting = {}
            if r.output and r.output.id then visiting[r.output.id] = true end
            for _, rg in ipairs(r.reagents or {}) do
                need(rg.id, rg.name, (rg.count or 1) * times, 0, visiting)
            end
        end
    end
    return result
end

local function listLines(tbl)
    local lines, missing = {}, 0
    for id, n in pairs(tbl) do
        local name = itemName(id)
        if not name then missing = missing + 1 end
        lines[#lines + 1] = { id = id, n = n, name = name or ("Item " .. id) }
    end
    table.sort(lines, function(a, b) return a.name < b.name end)
    return lines, missing
end

--- Einkaufsliste erstellen und an Auctionator geben.
function Profit.SendShoppingList()
    if Profit.QueueSummary().crafts == 0 then
        ns:Print(L["Queue ist leer - erst Rezepte anklicken."])
        return
    end
    local s = Profit.BuildShopping()

    local ah, missingAH = listLines(s.ah)
    local vendor = listLines(s.vendor)
    local unknown = listLines(s.unknown)
    local crafts = listLines(s.crafts)

    if missingAH > 0 then
        ns:Print(L["|cffffcc00Einige Item-Namen werden noch geladen - bitte in 1-2 Sekunden nochmal klicken.|r"])
        return
    end

    if #crafts > 0 then
        ns:Print(L["|cff88ff88Vorher selbst herstellen:|r"])
        for _, l in ipairs(crafts) do ns:Print(string.format("   %dx %s", l.n, l.name)) end
    end
    if #vendor > 0 then
        ns:Print(L["|cff88ccffBeim Haendler kaufen:|r"])
        for _, l in ipairs(vendor) do ns:Print(string.format("   %dx %s", l.n, l.name)) end
    end
    if #unknown > 0 then
        ns:Print(L["|cffff5555Ohne Preis (selbst besorgen):|r"])
        for _, l in ipairs(unknown) do ns:Print(string.format("   %dx %s", l.n, l.name)) end
    end

    if #ah == 0 then
        ns:Print(L["Im AH musst du nichts kaufen - alles da oder beim Haendler."])
        return
    end

    local A = _G.Auctionator
    local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
    if type(api) ~= "table" or type(api.CreateShoppingList) ~= "function"
       or type(api.ConvertToSearchString) ~= "function" then
        ns:Print(L["|cffffcc00Auctionator-Einkaufslisten nicht verfuegbar. Im AH kaufen:|r"])
        for _, l in ipairs(ah) do ns:Print(string.format("   %dx %s", l.n, l.name)) end
        return
    end

    local terms = {}
    for _, l in ipairs(ah) do
        local ok, str = ns.Call(api.ConvertToSearchString, ADDON_NAME,
            { searchString = l.name, isExact = true, quantity = l.n })
        if ok and type(str) == "string" then terms[#terms + 1] = str end
    end
    local ok, err = ns.Call(api.CreateShoppingList, ADDON_NAME, SHOPPING_LIST_NAME, terms)
    if not ok then
        ns:Print(L["|cffff5555Einkaufsliste fehlgeschlagen:|r "] .. ns.Str(err, "unbekannt"))
        return
    end
    ns:Print(string.format(L["|cff44ff44Auctionator-Einkaufsliste '%s' erstellt (%d Items).|r"],
        SHOPPING_LIST_NAME, #terms))
    ns:Print(L["Am AH: Auctionator -> Tab 'Einkaufen' -> Liste '"] .. SHOPPING_LIST_NAME .. "'.")
end

-- Herstellliste -------------------------------------------------------------

--- Wie oft kann das Rezept mit dem Material in den TASCHEN hergestellt werden?
--- (Bank zaehlt hier nicht - zum Herstellen muss es in der Tasche sein.)
function Profit.CraftableNow(recipe)
    local n
    for _, rg in ipairs(recipe.reagents or {}) do
        local have = 0
        if type(GetItemCount) == "function" then
            have = tonumber(ns.Try(GetItemCount, rg.id, false)) or 0
        end
        local possible = math.floor(have / math.max(rg.count or 1, 1))
        if not n or possible < n then n = possible end
    end
    return n or 0
end

--- Eintraege der Herstellliste: zuerst Zwischenschritte (Teilrezepte),
--- dann die Queue. Jeder Eintrag: { recipe, times, possible, intermediate }
function Profit.CraftEntries()
    local entries = {}
    local s = Profit.BuildShopping()
    local inter = {}
    for id, times in pairs(s.crafts) do
        local r = s.craftRecipes[id]
        if r then inter[#inter + 1] = { recipe = r, times = times, intermediate = true } end
    end
    table.sort(inter, function(a, b) return ns.Str(a.recipe.name) < ns.Str(b.recipe.name) end)
    for _, e in ipairs(inter) do entries[#entries + 1] = e end

    local main = {}
    for _, r in ipairs(ns.Professions.recipes or {}) do
        local n = Profit.QueueCount(r.key)
        if n > 0 then main[#main + 1] = { recipe = r, times = n } end
    end
    table.sort(main, function(a, b) return ns.Str(a.recipe.name) < ns.Str(b.recipe.name) end)
    for _, e in ipairs(main) do entries[#entries + 1] = e end

    for _, e in ipairs(entries) do
        e.possible = math.min(e.times, Profit.CraftableNow(e.recipe))
    end
    return entries
end

--- Name des aktuell offenen Berufsfensters, oder nil.
local function openProfession()
    if type(C_TradeSkillUI) ~= "table" then return nil end
    if type(C_TradeSkillUI.IsTradeSkillReady) == "function" then
        local ok, ready = ns.Call(C_TradeSkillUI.IsTradeSkillReady)
        if ok and ready == false then return nil end
    end
    for _, fn in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
        if type(C_TradeSkillUI[fn]) == "function" then
            local ok, info = ns.Call(C_TradeSkillUI[fn])
            if ok and type(info) == "table" then
                local name = ns.Value(info.professionName, nil)
                if type(name) == "string" and name ~= "" then return name end
            end
        end
    end
    return nil
end

Profit.OpenProfession = openProfession

--- Einen Eintrag herstellen (so oft wie Queue und Material erlauben).
--- Muss aus einem Klick heraus aufgerufen werden.
function Profit.Craft(entry)
    if not entry then return end
    local r = entry.recipe
    local n = math.min(entry.times or 0, entry.possible or 0)
    if n <= 0 then
        ns:Print(L["|cffff5555Material fehlt|r fuer "] .. ns.Str(r.name) .. L[" - siehe Einkaufsliste."])
        return
    end
    if type(C_TradeSkillUI) ~= "table" or type(C_TradeSkillUI.CraftRecipe) ~= "function" then
        ns:Print(L["|cffff5555Herstellen per Addon wird von diesem Client nicht unterstuetzt.|r"])
        return
    end
    local open = openProfession()
    if not open then
        ns:Print(L["Bitte zuerst das Berufsfenster |cffffd100"] .. ns.Str(r.profession) ..
                 L["|r oeffnen (links in der Berufe-Leiste)."])
        return
    end
    -- Locker vergleichen: Basis- und Unterberuf koennen leicht anders heissen
    -- (z.B. "Leatherworking" vs. "Classic Leatherworking").
    local a, b = open:lower(), ns.Str(r.profession, ""):lower()
    if b ~= "" and not (a:find(b, 1, true) or b:find(a, 1, true)) then
        ns:Print(string.format(L["Offen ist |cffffd100%s|r - fuer %s bitte |cffffd100%s|r oeffnen."],
            open, ns.Str(r.name), ns.Str(r.profession)))
        return
    end
    local ok, err = ns.Call(C_TradeSkillUI.CraftRecipe, r.recipeID, n)
    if not ok then
        ns:Print(L["|cffff5555Herstellen fehlgeschlagen:|r "] .. ns.Str(err, "unbekannt"))
        return
    end
    ns:Print(string.format(L["Stelle her: %dx %s"], n, ns.Str(r.name)))
end

--- Ersten herstellbaren Eintrag herstellen.
function Profit.CraftNext()
    for _, e in ipairs(Profit.CraftEntries()) do
        if e.possible > 0 then
            Profit.Craft(e)
            return
        end
    end
    ns:Print(L["Nichts herstellbar - Material fehlt oder Queue ist leer."])
end

--- Nach jedem erfolgreichen Craft die Queue herunterzaehlen.
--- (Rezept-Spell-ID == recipeID, Queue-Key ist "r:<recipeID>")
local castEv = CreateFrame("Frame")
castEv:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
castEv:SetScript("OnEvent", function(_, _, unit, _, spellID)
    if unit ~= "player" or not spellID or ns.IsSecret(spellID) then return end
    local key = "r:" .. tostring(spellID)
    if Profit.QueueCount(key) > 0 then
        Profit.QueueAdd(key, -1)
        if ns.UI and ns.UI.ScheduleRefresh then ns.UI.ScheduleRefresh() end
    end
end)