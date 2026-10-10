--[[--------------------------------------------------------------------------
  ForeverProfit - AuctionScan   (v0.3.0)

  Die API-Probe hat gezeigt: Forever hat die KOMPLETTE moderne
  C_AuctionHouse-API. Damit koennen wir einen eigenen Full-Scan fahren und
  sind NICHT auf Auctionator angewiesen.

  Mechanik (moderner "Full Scan"):
    C_AuctionHouse.ReplicateItems()            -> Scan anfordern
    Event ReplicateItemListUpdate              -> Liste liegt vor
    C_AuctionHouse.GetNumReplicateItems()      -> Anzahl
    C_AuctionHouse.GetReplicateItemInfo(i)     -> name, count, buyoutPrice, itemID, ...
  Preise aggregieren wir pro itemID als guenstigsten Buyout pro Stueck.

  WICHTIG:
   * Der Scan darf nur am Auktionshaus laufen (Client-Anforderung).
   * BigUInteger-Werte (buyoutPrice) sind evtl. secret/gesperrt -> durch
     ns.Value/ns.IsSecret abgesichert. Werte werden nie verglichen, wenn sie
     secret sind.
   * Ergebnisse gehen in die SavedVariables (ueberleben /reload).

  Auctionator bleibt als zweite Quelle erhalten (siehe Prices.lua).
----------------------------------------------------------------------------]]

local _, ns = ...
local L = ns.L

local AuctionScan = {}
ns.AuctionScan = AuctionScan

AuctionScan.running   = false
AuctionScan.progress  = { done = 0, total = 0 }
AuctionScan.lastCount = 0

local function Store()
    local db = ns.Config and ns.Config.db
    return db
end

local function itemTable(db, itemID)
    db.auction = db.auction or { items = {}, scannedAt = 0, totalListings = 0 }
    db.auction.items = db.auction.items or {}
    local rec = db.auction.items[itemID]
    if not rec then
        rec = { min = nil, qty = 0, listings = 0 }
        db.auction.items[itemID] = rec
    end
    return rec
end

--- Eine gefundene Auktion in die Preis-DB einrechnen (guenstigster Buyout gewinnt).
local function ingest(itemID, buyout, quantity)
    local db = Store()
    if not db then return end
    itemID   = tonumber(itemID)
    buyout   = tonumber(buyout)
    quantity = tonumber(quantity) or 1
    if not itemID or not buyout or buyout <= 0 then return end

    local perUnit = math.floor(buyout / math.max(quantity, 1) + 0.5)
    if perUnit <= 0 then return end

    local rec = itemTable(db, itemID)
    if not rec.min or perUnit < rec.min then rec.min = perUnit end
    rec.qty      = rec.qty + quantity
    rec.listings = rec.listings + 1
end

--- Komplette Replicate-Liste einlesen.
--- FIX v0.3.0: laeuft CHUNKED ueber einen Frame. Ein AH-Scan kann 10k+
--- Angebote liefern - synchron wuerde das den Client einfrieren.
local ingestDriver = CreateFrame("Frame")
local ingestCursor, ingestTotal, ingestSeen, ingestVerbose

local function ingestTick()
    local spent = 0
    local processed = 0
    while ingestCursor <= ingestTotal and processed < 200 and spent < 0.03 do
        local t0 = (type(debugprofilestop) == "function") and debugprofilestop() or 0
        local ok, _, r = ns.Pack(C_AuctionHouse.GetReplicateItemInfo, ingestCursor)
        if ok and type(r) == "table" then
            -- Rueckgabe ist POSITIONSBASIERT (19 Werte, aus der Referenz):
            --  1 name, 2 texture, 3 count, 4 qualityID, 5 usable, 6 level,
            --  7 levelType, 8 minBid, 9 minIncrement, 10 buyoutPrice,
            --  11 bidAmount, 12 highBidder, 13 bidderFullName, 14 owner,
            --  15 ownerFullName, 16 saleStatus, 17 itemID, 18 hasAllInfo
            local buyout = ns.Value(r[10], nil)
            local count  = ns.Value(r[3], 1)
            local itemID = ns.Value(r[17], nil) or ns.Value(r[18], nil) or ns.Value(r[19], nil)
            if itemID and buyout then
                ingest(itemID, buyout, count)
                ingestSeen = ingestSeen + 1
            end
        end
        ingestCursor = ingestCursor + 1
        processed = processed + 1
        if t0 ~= 0 and type(debugprofilestop) == "function" then
            spent = spent + (debugprofilestop() - t0) / 1000
        end
    end

    AuctionScan.progress = { done = ingestCursor - 1, total = ingestTotal }

    if ingestCursor > ingestTotal then
        ingestDriver:SetScript("OnUpdate", nil)
        local db = Store()
        if db then
            db.auction.scannedAt     = time()
            db.auction.totalListings = ingestSeen
        end
        if ns.Config and ns.Config.MarkPricesRefreshed then ns.Config.MarkPricesRefreshed() end
        AuctionScan.lastCount = ingestSeen
        AuctionScan.running   = false
        if ingestVerbose then
            ns:Print(string.format(L["AH-Scan fertig: %d Angebote uebernommen."], ingestSeen))
        end
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    end
end

function AuctionScan.Ingest(verbose)
    if type(C_AuctionHouse) ~= "table" then return 0 end
    if type(C_AuctionHouse.GetNumReplicateItems) ~= "function" or
       type(C_AuctionHouse.GetReplicateItemInfo) ~= "function" then
        return 0
    end

    local okN, _, nRets = ns.Pack(C_AuctionHouse.GetNumReplicateItems)
    local n = (okN and tonumber(nRets[1])) or 0
    if n <= 0 then return 0 end

    local db = Store()
    if not db then return 0 end
    db.auction = db.auction or { items = {}, scannedAt = 0, totalListings = 0 }
    db.auction.items = {}

    ingestCursor, ingestTotal, ingestSeen, ingestVerbose = 1, n, 0, verbose
    AuctionScan.progress = { done = 0, total = n }
    ingestDriver:SetScript("OnUpdate", ingestTick)
    return n
end

--- Auctionators eigenen Vollscan anstossen. Der Frame entsteht erst, wenn
--- das AH einmal offen war. Ergebnis kommt ueber RegisterForDBUpdate
--- (siehe Prices.Init). Rueckgabe: true wenn angestossen.
local function startAuctionatorScan()
    local f = _G.AuctionatorFullScanFrame
    if type(f) ~= "table" or type(f.InitiateScan) ~= "function" then return false end
    -- Auctionator erlaubt nur alle 15 Minuten einen Vollscan und meldet
    -- die Restzeit selbst im Chat.
    if type(f.CanInitiate) == "function" and not ns.Try(f.CanInitiate, f) then
        ns.Try(f.InitiateScan, f)
        return true
    end
    local ok, err = ns.Call(f.InitiateScan, f)
    if not ok then
        ns:Print(L["|cffff5555Auctionator-Scan-Fehler:|r "] .. ns.Str(err, "unbekannt"))
        return false
    end
    AuctionScan.running  = true
    AuctionScan.progress = { done = 0, total = 0 }
    ns:Print(L["Auctionator-Vollscan gestartet - die Liste aktualisiert sich danach automatisch."])
    -- Sicherheitsnetz, falls das Fertig-Signal ausbleibt.
    ns.C_Timer_After(120, function() AuctionScan.running = false end)
    return true
end

--- Scan starten. Nur am AH sinnvoll/moeglich.
function AuctionScan.Start()
    if not (AuctionFrame and AuctionFrame:IsShown()) and
       not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        ns:Print(L["|cffffcc00Bitte zuerst das Auktionshaus oeffnen.|r"])
        return false
    end

    local mode = ns.Config and ns.Config.db and ns.Config.db.priceSource or "auto"
    if mode ~= "native" and startAuctionatorScan() then return true end

    if type(C_AuctionHouse) ~= "table" or type(C_AuctionHouse.ReplicateItems) ~= "function" then
        ns:Print(L["|cffff5555C_AuctionHouse.ReplicateItems fehlt|r - nativer Scan nicht moeglich."])
        return false
    end

    AuctionScan.running  = true
    AuctionScan.nativeRequested = true
    AuctionScan.progress = { done = 0, total = 0 }
    ns:Print(L["Auktionshaus-Scan gestartet - dauert ein paar Sekunden..."])

    local ok, err = ns.Call(C_AuctionHouse.ReplicateItems)
    if not ok then
        ns:Print(L["|cffff5555ReplicateItems-Fehler:|r "] .. ns.Str(err, "unbekannt"))
        ns:Print(L["|cffffcc00Hinweis:|r Das kann heissen: AH nicht offen, Funktion geschuetzt,"])
        ns:Print(L["oder auf diesem Client anders. Wir nutzen dann die Auctionator-Preise."])
        AuctionScan.running = false
        return false
    end

    -- FALLBACK: Auf dem Forever-Client feuert `ReplicateItemListUpdate`
    -- offenbar nicht zuverlaessig. Deshalb nach kurzer Wartezeit pruefen, ob
    -- die Liste trotzdem da ist, und dann einlesen.
    ns.C_Timer_After(3, function()
        if not (AuctionScan.running and AuctionScan.nativeRequested) then return end
        local okN, _, nRets = ns.Pack(C_AuctionHouse.GetNumReplicateItems)
        local n = (okN and tonumber(nRets[1])) or 0
        if n > 0 then
            AuctionScan.nativeRequested = false
            AuctionScan.Ingest(true)
        else
            ns.C_Timer_After(5, function()
                if not (AuctionScan.running and AuctionScan.nativeRequested) then return end
                local ok2, _, r2 = ns.Pack(C_AuctionHouse.GetNumReplicateItems)
                local n2 = (ok2 and tonumber(r2[1])) or 0
                AuctionScan.nativeRequested = false
                if n2 > 0 then
                    AuctionScan.Ingest(true)
                else
                    AuctionScan.running = false
                    ns:Print(L["|cffffcc00Kein AH-Ergebnis erhalten.|r Event ReplicateItemListUpdate kam nicht"])
                    ns:Print(L["und GetNumReplicateItems liefert 0. Bitte `/fp probe` schicken."])
                end
            end)
        end
    end)
    return true
end

--- Statistik fuer die GUI.
function AuctionScan.Stats()
    local db = Store()
    local a = db and db.auction
    if not a or not a.items then return { items = 0, listings = 0, age = nil } end
    local count = 0
    for _ in pairs(a.items) do count = count + 1 end
    return {
        items    = count,
        listings = a.totalListings or 0,
        age      = a.scannedAt and a.scannedAt > 0 and (time() - a.scannedAt) or nil,
    }
end

--- Preis aus der nativen Scan-DB.
function AuctionScan.Get(itemID)
    local db = Store()
    local a = db and db.auction
    if not a or not a.items then return nil end
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local rec = a.items[itemID]
    return rec and rec.min or nil
end

function AuctionScan.Age()
    local s = AuctionScan.Stats()
    return s.age
end

function AuctionScan.AgeText()
    local a = AuctionScan.Age()
    if not a then return L["|cffff5555noch kein AH-Scan|r"] end
    if a < 60 then return string.format(L["vor %ds"], a) end
    if a < 3600 then return string.format(L["vor %dmin"], math.floor(a / 60)) end
    if a < 86400 then return string.format(L["vor %dh"], math.floor(a / 3600)) end
    return string.format(L["vor %dd"], math.floor(a / 86400))
end

-- Events --------------------------------------------------------------------

local ev = CreateFrame("Frame")
-- Event-Namen in WoW sind GROSS_MIT_UNTERSTRICH (v0.6 hatte CamelCase ->
-- die Events kamen nie an).
for _, e in ipairs({ "REPLICATE_ITEM_LIST_UPDATE", "AUCTION_HOUSE_SHOW" }) do
    ns.Try(ev.RegisterEvent, ev, e)
end

ev:SetScript("OnEvent", function(self, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" then
        -- Nur einlesen, wenn WIR den nativen Scan angefordert haben
        -- (Auctionators Scan loest dasselbe Event aus).
        if AuctionScan.running and AuctionScan.nativeRequested then
            AuctionScan.nativeRequested = false
            AuctionScan.Ingest(true)
        end
    elseif event == "AUCTION_HOUSE_SHOW" then
        ns:Print(L["Auktionshaus offen - 'AH scannen' im Fenster (/fp show) startet den Preis-Scan."])
    end
end)
