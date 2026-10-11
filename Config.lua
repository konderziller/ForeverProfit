--[[--------------------------------------------------------------------------
  ForeverProfit - Config
  Profile + SavedVariables. Beta-Clients verlieren teils Einstellungen ->
  Profil-Export zum Sichern ausserhalb des Spiels.
----------------------------------------------------------------------------]]

local _, ns = ...

local Config = {}
ns.Config = Config

local DEFAULT_PROFILE = "Default"

local DEFAULTS = {
    debug = false,
    priceSource = "auto",        -- "auto" | "native" | "auctionator" | "manual"
    includeUnprofitable = true,  -- (alt, ungenutzt)
    onlyProfit = true,           -- nur Rezepte mit Gewinn > 0 anzeigen
    onlyLearned = true,          -- nur Rezepte, die der Char kann
    autoOpen = true,             -- mit dem Berufsfenster oeffnen
    useSubCrafts = true,         -- Zwischenprodukte selbst herstellen, wenn billiger
    mode = "profit",             -- "profit" | "skill"
    ahCut = 0.05,                -- AH-Gebuehr auf den Verkaufserloes
    lastPriceRefresh = 0,        -- Zeitstempel des letzten Preis-Updates
    manualPrices = {},           -- [itemID or name] = copper
    queue = {},                  -- [recipeKey] = true  (Auswahl "soll herstellen")
    auction = {                  -- nativer C_AuctionHouse-Scan
        items = {},              -- [itemID] = { min = kupferProStueck, qty, listings }
        scannedAt = 0,
        totalListings = 0,
    },
}

local function copyPlain(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = type(v) == "table" and copyPlain(v) or v
    end
    return out
end

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            fillDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function Config.Init()
    ForeverProfitDB = ForeverProfitDB or {}
    ForeverProfitDB.profiles = ForeverProfitDB.profiles or {}
    ForeverProfitDB.profile  = ForeverProfitDB.profile or DEFAULT_PROFILE

    local name = ForeverProfitDB.profile
    local p = ForeverProfitDB.profiles[name]
    if type(p) ~= "table" then
        p = copyPlain(DEFAULTS)
        ForeverProfitDB.profiles[name] = p
    else
        fillDefaults(p, DEFAULTS)
    end

    Config.db = p
    ns.debug = p.debug or false
end

--- Zeitstempel des letzten Preis-Updates setzen (nach Scan / Refresh).
function Config.MarkPricesRefreshed()
    if Config.db then Config.db.lastPriceRefresh = time() end
end

function Config.Reset()
    local name = ForeverProfitDB and ForeverProfitDB.profile or DEFAULT_PROFILE
    if ForeverProfitDB then
        ForeverProfitDB.profiles[name] = copyPlain(DEFAULTS)
    end
    Config.Init()
end
