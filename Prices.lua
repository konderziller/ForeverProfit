--[[--------------------------------------------------------------------------
  ForeverProfit - Prices   (v0.7.0)

  Preis-Adapter. Quellen:
    A) Auctionator ueber die offizielle API:
         Auctionator.API.v1.GetAuctionPriceByItemID(callerID, itemID)
         Auctionator.API.v1.RegisterForDBUpdate(callerID, callback)
    B) Nativer C_AuctionHouse-Scan (siehe AuctionScan.lua)
    C) manuelle Preise aus der Config
    D) TradeSkillMaster (ab TSM 4.15 mit Forever-Support):
         TSM_API.GetCustomPriceValue(preisString, "i:<itemID>")
       preisString aus db.tsmSource (Standard: Realm-Marktwert, sonst Region)

  Fix v0.7.0:
   * v0.6 suchte `_G.AuctionatorAPI` bzw. Atr_*-Funktionen - die gibt es im
     aktuellen Auctionator nicht. Danach lief eine Tiefensuche durch
     Auctionators Tabellen, die mit Zahlen-Schluesseln nie traf (bzw. im
     schlimmsten Fall falsche Werte lieferte). Ersetzt durch die echte API.

  Reihenfolge steuert db.priceSource:
    "tsm"         -> TradeSkillMaster (Standard). Ohne TSM-Addon: Auctionator,
                     sonst nativer Scan.
    "auctionator" -> nur Auctionator
    "native"      -> nur nativer AH-Scan
    "manual"      -> nur Handeingabe
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...
local L = ns.L

local Prices = {}
ns.Prices = Prices

Prices.source = "none"   -- welcher Adapter zuletzt gegriffen hat

local CALLER_ID = ADDON_NAME

-- Hilfsfunktionen -----------------------------------------------------------

local function toNumber(v)
    if ns.IsSecret(v) then return nil end
    if type(v) == "number" and v > 0 then return v end
    return nil
end

local function auctionatorAPI()
    local A = _G.Auctionator
    local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
    if type(api) == "table" and type(api.GetAuctionPriceByItemID) == "function" then
        return api
    end
    return nil
end

-- 1) Auctionator ------------------------------------------------------------
local function tryAuctionator(itemID)
    local api = auctionatorAPI()
    itemID = tonumber(itemID)
    if not api or not itemID then return nil end
    local p = toNumber(ns.Try(api.GetAuctionPriceByItemID, CALLER_ID, itemID))
    if p then Prices.source = "auctionator" end
    return p
end

-- 1b) TradeSkillMaster ---------------------------------------------------------
-- Alle Forever-Datensaetze der TSM-App: Realm-/Regions-Marktwert, Historie,
-- zuletzt der Mindestpreis aus eigenen Scans.
local TSM_DEFAULT = "first(dbmarket, dbregionmarketavg, dbhistorical, dbregionhistorical, dbminbuyout)"
local TSM_OLD_DEFAULT = "first(dbmarket, dbregionmarketavg)"

local function tsmAPI()
    local api = _G.TSM_API
    if type(api) == "table" and type(api.GetCustomPriceValue) == "function" then return api end
    return nil
end

local tsmWarned = false
local function tryTSM(itemID)
    local api = tsmAPI()
    itemID = tonumber(itemID)
    if not api or not itemID then return nil end
    local db = ns.Config and ns.Config.db
    local src = (db and db.tsmSource) or TSM_DEFAULT
    local ok, value, err = pcall(api.GetCustomPriceValue, src, "i:" .. itemID)
    if (not ok or err) and src ~= "dbmarket" then
        -- ungueltiger Preis-String (z.B. Quelle im Forever-Client unbekannt)
        if not tsmWarned then
            tsmWarned = true
            ns:Print(L["|cffffcc00TSM-Preisquelle ungueltig, nutze dbmarket:|r "] .. tostring(ok and err or value))
        end
        ok, value = pcall(api.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
    end
    local p = ok and toNumber(value) or nil
    if p then Prices.source = "tsm" end
    return p
end

-- 2) Manuell ----------------------------------------------------------------
local function tryManual(item)
    local db = ns.Config and ns.Config.db
    if not (db and db.manualPrices) or item == nil then return nil end
    local p = toNumber(db.manualPrices[item])
    if p then Prices.source = "manual" end
    return p
end

-- Oeffentliche API ----------------------------------------------------------

--- Preis in Kupfer fuer eine ItemID. nil wenn unbekannt.
function Prices.Get(itemID)
    if itemID == nil then return nil end
    local mode = (ns.Config and ns.Config.db and ns.Config.db.priceSource) or "tsm"

    local function native()
        if not (ns.AuctionScan and ns.AuctionScan.Get) then return nil end
        local p = ns.AuctionScan.Get(itemID)
        if p then Prices.source = "native" end
        return p
    end

    -- Eigene Preise (/fp price) haben immer Vorrang.
    local manual = tryManual(tonumber(itemID) or itemID)
    if manual or mode == "manual" then
        return manual
    elseif mode == "native" then
        return native()
    elseif mode == "auctionator" then
        return tryAuctionator(itemID)
    end
    -- Standard "tsm": fest TradeSkillMaster. Nur wenn das TSM-Addon fehlt,
    -- Auctionator bzw. eigener Scan, damit die Liste nicht leer bleibt.
    if tsmAPI() then return tryTSM(itemID) end
    return tryAuctionator(itemID) or native()
end

--- Eigenen Preis setzen (Kupfer) oder mit nil entfernen.
function Prices.SetManual(itemID, copper)
    local db = ns.Config and ns.Config.db
    itemID = tonumber(itemID)
    if not (db and itemID) then return end
    db.manualPrices = db.manualPrices or {}
    db.manualPrices[itemID] = copper
end

function Prices.GetManual(itemID)
    return tryManual(tonumber(itemID))
end

--- true, wenn fuer das Item ein eigener Preis (/fp price) gesetzt ist.
function Prices.HasManual(itemID, name)
    local db = ns.Config and ns.Config.db
    local m = db and db.manualPrices
    if not m then return false end
    return toNumber(m[tonumber(itemID)]) ~= nil or (name ~= nil and toNumber(m[name]) ~= nil)
end

--- Verkaufspreis (AH) fuer ein Item: ItemID, ersatzweise manueller Preis per Name.
function Prices.GetForID(itemID, name)
    return Prices.Get(itemID) or (name and tryManual(name)) or nil
end

--- Kaufpreis beim Haendler pro Stueck. Auctionator fuellt den Cache beim
--- Oeffnen eines Haendlers (nur unbegrenzt vorraetige Waren).
function Prices.GetVendor(itemID)
    local A = _G.Auctionator
    local api = type(A) == "table" and type(A.API) == "table" and A.API.v1
    itemID = tonumber(itemID)
    if not itemID or type(api) ~= "table" or type(api.GetVendorPriceByItemID) ~= "function" then
        return nil
    end
    return toNumber(ns.Try(api.GetVendorPriceByItemID, CALLER_ID, itemID))
end

--- Einkaufspreis fuer ein Reagenz: das Guenstigere aus AH und Haendler.
--- Rueckgabe: preis, quelle ("vendor" | "ah") oder nil.
function Prices.GetReagent(itemID, name)
    local manual = Prices.GetManual(itemID)
    if manual then return manual, "manual" end
    local ah = Prices.GetForID(itemID, name)
    local vendor = Prices.GetVendor(itemID)
    if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
    if ah then return ah, "ah" end
    return nil
end

-- Marktdaten (Auctionator-Preishistorie) -------------------------------------
-- Auctionator speichert pro Item und Tag: niedrigster/hoechster Mindestpreis
-- und hoechste gesehene Angebotsmenge. Daraus:
--   age       = Tage seit dem letzten Sichten im AH (0 = heute)
--   available = Angebotsmenge am letzten Scan-Tag
--   median    = Median der Tages-Mindestpreise (letzte 14 Tage)
--   days      = Anzahl Tage mit Daten
-- Pro Rechen-Durchlauf gecacht (Prices.BeginPass).

local marketCache = {}

function Prices.BeginPass()
    marketCache = {}
end

local function median(list)
    if #list == 0 then return nil end
    table.sort(list)
    local mid = math.floor(#list / 2)
    if #list % 2 == 1 then return list[mid + 1] end
    return (list[mid] + list[mid + 1]) / 2
end

function Prices.Market(itemID)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local cached = marketCache[itemID]
    if cached ~= nil then return cached or nil end

    local result = false
    local A = _G.Auctionator
    local db = type(A) == "table" and A.Database
    if type(db) == "table" and type(db.GetPriceHistory) == "function" then
        local ok, hist = pcall(db.GetPriceHistory, db, tostring(itemID))
        if ok and type(hist) == "table" and #hist > 0 then
            -- hist ist nach Tag absteigend sortiert (neuester zuerst).
            local prices = {}
            for i = 1, math.min(#hist, 14) do
                local p = tonumber(hist[i].minSeen)
                if p and p > 0 then prices[#prices + 1] = p end
            end
            local api = A.API and A.API.v1
            local age
            if api and type(api.GetAuctionAgeByItemID) == "function" then
                age = tonumber(ns.Try(api.GetAuctionAgeByItemID, CALLER_ID, itemID))
            end
            result = {
                age       = age,
                available = tonumber(hist[1].available),
                median    = median(prices),
                days      = #prices,
            }
        end
    end
    marketCache[itemID] = result
    return result or nil
end

--- Alter des letzten Preis-Updates in Sekunden, oder nil.
function Prices.Age()
    local newest
    local db = ns.Config and ns.Config.db
    if db and db.lastPriceRefresh and db.lastPriceRefresh > 0 then
        newest = db.lastPriceRefresh
    end
    if ns.AuctionScan and ns.AuctionScan.Stats then
        local s = ns.AuctionScan.Stats()
        if s.age then
            local t = time() - s.age
            if not newest or t > newest then newest = t end
        end
    end
    if not newest then return nil end
    return time() - newest
end

function Prices.AgeText()
    local a = Prices.Age()
    if not a then return L["|cffff5555noch kein Scan|r"] end
    if a < 60 then return string.format(L["vor %ds"], a) end
    if a < 3600 then return string.format(L["vor %dmin"], math.floor(a / 60)) end
    if a < 86400 then return string.format(L["vor %dh"], math.floor(a / 3600)) end
    return string.format(L["vor %dd"], math.floor(a / 86400))
end

--- Erkennen, welche Preis-Backends da sind (fuer GUI/Probe).
function Prices.Detect()
    local list = {}
    if auctionatorAPI() then list[#list + 1] = "Auctionator" end
    if tsmAPI() then list[#list + 1] = "TradeSkillMaster" end
    if type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ReplicateItems) == "function" then
        list[#list + 1] = L["C_AuctionHouse (nativ)"]
    end
    Prices.available = list
    return list
end

function Prices.HasAuctionator()
    return auctionatorAPI() ~= nil
end

function Prices.HasTSM()
    return tsmAPI() ~= nil
end

Prices.TSM_DEFAULT = TSM_DEFAULT

-- Preisquellen-Modi zum Umschalten (Knopf + /fp source). Nicht geladene
-- Quellen werden uebersprungen; der aktuelle Modus bleibt immer waehlbar.
local MODE_LABEL = {
    auctionator = "Auctionator", tsm = "TSM", native = "AH-Scan", manual = "Manuell",
}

function Prices.ModeLabel(mode)
    return L[MODE_LABEL[mode] or tostring(mode)]
end

function Prices.Modes()
    local db = ns.Config and ns.Config.db
    local cur = db and db.priceSource or "tsm"
    local list = { "tsm" }
    if auctionatorAPI() or cur == "auctionator" then list[#list + 1] = "auctionator" end
    if (type(C_AuctionHouse) == "table" and type(C_AuctionHouse.ReplicateItems) == "function") or cur == "native" then
        list[#list + 1] = "native"
    end
    list[#list + 1] = "manual"
    return list
end

--- Naechste (dir = 1) oder vorige (dir = -1) Preisquelle waehlen.
function Prices.Cycle(dir)
    local db = ns.Config and ns.Config.db
    if not db then return end
    local list = Prices.Modes()
    local cur = 1
    for i, v in ipairs(list) do if v == db.priceSource then cur = i end end
    db.priceSource = list[((cur - 1 + (dir or 1)) % #list) + 1]
    return db.priceSource
end

function Prices.Init()
    Prices.Detect()
    -- alte Standard-Formel (v1.7.0) auf die neue umstellen, eigene Formeln bleiben
    local db = ns.Config and ns.Config.db
    if db and (db.tsmSource == nil or db.tsmSource == TSM_OLD_DEFAULT) then db.tsmSource = TSM_DEFAULT end
    -- "auto" gibt es nicht mehr: TSM ist die feste Standard-Preisquelle
    if db and (db.priceSource == nil or db.priceSource == "auto") then db.priceSource = "tsm" end
    -- Feuert nach Auctionator-Vollscans UND nach jeder normalen Suche /
    -- Verkaufen-Abfrage in Auctionator. Chat-Meldung nur fuer unseren
    -- eigenen Scan, sonst wuerde jede Suche spammen.
    local api = auctionatorAPI()
    if api and type(api.RegisterForDBUpdate) == "function" then
        ns.Try(api.RegisterForDBUpdate, CALLER_ID, function()
            if ns.Config and ns.Config.MarkPricesRefreshed then ns.Config.MarkPricesRefreshed() end
            if ns.AuctionScan and ns.AuctionScan.running then
                ns.AuctionScan.running = false
                ns:Print(L["Auctionator-Scan fertig - Profitliste aktualisiert."])
            end
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        end)
    end
end
