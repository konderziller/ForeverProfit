--[[--------------------------------------------------------------------------
  ForeverProfit - Core   (v0.3.0)

  Crafting-Profitschaetzer fuer den WoW-Forever-Beta-Client (TOC 16001).

  Fix v0.3.0:
   * ns.Call nutzte `table.pack` -> gibt es in WoW/Lua 5.1 NICHT. Ersetzt
     durch reines pcall mit Mehrfach-Rueckgabe.
   * Slash-Handler laeuft in pcall: ein Fehler kann das Chatfenster nicht
     mehr blockieren.
   * Scan ist jetzt asynchron (siehe Professions.lua), nie mehr blockierend.
----------------------------------------------------------------------------]]

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME

-- Lokalisierung -------------------------------------------------------------
-- Schluessel = urspruenglicher deutscher Text. Deutscher Client -> L_DE
-- (echte Umlaute, sonst Schluessel), alle anderen Sprachen -> L_EN.
local L_DE = {
    ["AH-Scan fertig: %d Angebote uebernommen."] = "AH-Scan fertig: %d Angebote übernommen.",
    ["|cffffcc00Bitte zuerst das Auktionshaus oeffnen.|r"] = "|cffffcc00Bitte zuerst das Auktionshaus öffnen.|r",
    ["|cffff5555C_AuctionHouse.ReplicateItems fehlt|r - nativer Scan nicht moeglich."] = "|cffff5555C_AuctionHouse.ReplicateItems fehlt|r - nativer Scan nicht möglich.",
    ["|cffffcc00Hinweis:|r Das kann heissen: AH nicht offen, Funktion geschuetzt,"] = "|cffffcc00Hinweis:|r Das kann heißen: AH nicht offen, Funktion geschützt,",
    ["Benutzung: /fp price [Item-Link] 1g20s   (Shift+Klick auf ein Item fuegt den Link ein)"] = "Benutzung: /fp price [Item-Link] 1g20s   (Shift+Klick auf ein Item fügt den Link ein)",
    ["Eigener Preis fuer Item "] = "Eigener Preis für Item ",
    ["Eigener Preis fuer Item %d: %s"] = "Eigener Preis für Item %d: %s",
    ["  /fp show      - Hauptfenster oeffnen"] = "  /fp show      - Hauptfenster öffnen",
    ["  /fp probe     - API-Dump (zur Fehlersuche)"] = "  /fp probe     - API-Dump (zur Fehlersuche)",
    [" (hilfe: /fp help)"] = " (Hilfe: /fp help)",
    ["Mit /reload zuruecksetzen. Bitte den Fehlertext melden."] = "Mit /reload zurücksetzen. Bitte den Fehlertext melden.",
    ["Scan: %d/%d (%d%%) - %d Rezepte uebernommen"] = "Scan: %d/%d (%d%%) - %d Rezepte übernommen",
    ["Spiel liefert gerade keine Rezepte - nutze die gespeicherten. Berufsfenster oeffnen aktualisiert sie."] = "Spiel liefert gerade keine Rezepte - nutze die gespeicherten. Berufsfenster öffnen aktualisiert sie.",
    ["|cffffcc00Keine Rezepte uebernommen.|r "] = "|cffffcc00Keine Rezepte übernommen.|r ",
    ["Scan laeuft schon - /fp stop bricht ab."] = "Scan läuft schon - /fp stop bricht ab.",
    ["|cffffcc00Keine Berufe erkannt.|r Berufsfenster einmal oeffnen."] = "|cffffcc00Keine Berufe erkannt.|r Berufsfenster einmal öffnen.",
    ["|cffffcc00Keine Rezepte vom Spiel.|r Berufsfenster einmal oeffnen."] = "|cffffcc00Keine Rezepte vom Spiel.|r Berufsfenster einmal öffnen.",
    ["|cff88ccffBeim Haendler kaufen:|r"] = "|cff88ccffBeim Händler kaufen:|r",
    ["Im AH musst du nichts kaufen - alles da oder beim Haendler."] = "Im AH musst du nichts kaufen - alles da oder beim Händler.",
    ["|cffffcc00Auctionator-Einkaufslisten nicht verfuegbar. Im AH kaufen:|r"] = "|cffffcc00Auctionator-Einkaufslisten nicht verfügbar. Im AH kaufen:|r",
    ["|cffff5555Material fehlt|r fuer "] = "|cffff5555Material fehlt|r für ",
    ["|cffff5555Herstellen per Addon wird von diesem Client nicht unterstuetzt.|r"] = "|cffff5555Herstellen per Addon wird von diesem Client nicht unterstützt.|r",
    ["|r oeffnen (links in der Berufe-Leiste)."] = "|r öffnen (links in der Berufe-Leiste).",
    ["Offen ist |cffffd100%s|r - fuer %s bitte |cffffd100%s|r oeffnen."] = "Offen ist |cffffd100%s|r - für %s bitte |cffffd100%s|r öffnen.",
    ["|cff88ccffHaendler|r"] = "|cff88ccffHändler|r",
    ["Verkauf %dx (nach 5%% AH-Gebuehr)"] = "Verkauf %dx (nach 5%% AH-Gebühr)",
    ["|cffff5555ueber 3 Wochen|r"] = "|cffff5555über 3 Wochen|r",
    ["! Aktueller Preis deutlich ueber dem Mittel - Gewinn evtl. zu optimistisch"] = "! Aktueller Preis deutlich über dem Mittel - Gewinn evtl. zu optimistisch",
    ["gruen"] = "grün",
    ["Kosten pro Skillpunkt (geschaetzt)"] = "Kosten pro Skillpunkt (geschätzt)",
    ["Linksklick: Berufsfenster oeffnen"] = "Linksklick: Berufsfenster öffnen",
    ["Beruf: Links oeffnen, Rechts filtern"] = "Beruf: Links öffnen, Rechts filtern",
    ["Nur Rezepte, die noch Skill geben (orange/gelb/gruen),\nsortiert nach Kosten pro Skillpunkt.\nVerkaufserloes wird gegengerechnet."] = "Nur Rezepte, die noch Skill geben (orange/gelb/grün),
sortiert nach Kosten pro Skillpunkt.
Verkaufserlös wird gegengerechnet.",
    ["Zwischenschritt - wird fuer die Queue gebraucht"] = "Zwischenschritt - wird für die Queue gebraucht",
    ["Naechstes herstellen"] = "Nächstes herstellen",
    ["|cffffcc00%d von %d moeglich|r"] = "|cffffcc00%d von %d möglich|r",
    ["Liest deine Rezepte neu ein.\nPassiert auch automatisch beim Oeffnen des Berufsfensters."] = "Liest deine Rezepte neu ein.
Passiert auch automatisch beim Öffnen des Berufsfensters.",
    ["Nur Rezepte mit vollstaendigen Preisen und Gewinn anzeigen."] = "Nur Rezepte mit vollständigen Preisen und Gewinn anzeigen.",
    ["\nVerfuegbar: "] = "
Verfügbar: ",
    ["Alle Zutaten der Queue minus Taschen und Bank.\nAH-Items gehen als Liste 'ForeverProfit' an Auctionator,\nHaendler-Items und Zwischenschritte stehen im Chat."] = "Alle Zutaten der Queue minus Taschen und Bank.
AH-Items gehen als Liste 'ForeverProfit' an Auctionator,
Händler-Items und Zwischenschritte stehen im Chat.",
    ["Noch keine Rezepte eingelesen.\n\n|cffaaaaaaBerufsfenster einmal oeffnen.|r"] = "Noch keine Rezepte eingelesen.

|cffaaaaaaBerufsfenster einmal öffnen.|r",
    ["Keine Rezepte gefunden, die noch Skill geben.\n\n|cffaaaaaaBerufsfenster oeffnen, damit die Skill-Farben\naktuell sind. Hilft das nicht: /fp probe schicken.|r"] = "Keine Rezepte gefunden, die noch Skill geben.

|cffaaaaaaBerufsfenster öffnen, damit die Skill-Farben
aktuell sind. Hilft das nicht: /fp probe schicken.|r",
    ["Im Kampf nicht moeglich - danach nochmal."] = "Im Kampf nicht möglich - danach nochmal.",
}

local L_EN = {
    ["AH-Scan fertig: %d Angebote uebernommen."] = "AH scan finished: %d listings imported.",
    ["|cffff5555Auctionator-Scan-Fehler:|r "] = "|cffff5555Auctionator scan error:|r ",
    ["Auctionator-Vollscan gestartet - die Liste aktualisiert sich danach automatisch."] = "Auctionator full scan started - the list updates automatically afterwards.",
    ["|cffffcc00Bitte zuerst das Auktionshaus oeffnen.|r"] = "|cffffcc00Please open the auction house first.|r",
    ["|cffff5555C_AuctionHouse.ReplicateItems fehlt|r - nativer Scan nicht moeglich."] = "|cffff5555C_AuctionHouse.ReplicateItems missing|r - native scan not possible.",
    ["Auktionshaus-Scan gestartet - dauert ein paar Sekunden..."] = "Auction house scan started - takes a few seconds...",
    ["|cffff5555ReplicateItems-Fehler:|r "] = "|cffff5555ReplicateItems error:|r ",
    ["|cffffcc00Hinweis:|r Das kann heissen: AH nicht offen, Funktion geschuetzt,"] = "|cffffcc00Note:|r This can mean: AH not open, function protected,",
    ["oder auf diesem Client anders. Wir nutzen dann die Auctionator-Preise."] = "or different on this client. Auctionator prices will be used instead.",
    ["|cffffcc00Kein AH-Ergebnis erhalten.|r Event ReplicateItemListUpdate kam nicht"] = "|cffffcc00No AH result received.|r Event ReplicateItemListUpdate did not fire",
    ["und GetNumReplicateItems liefert 0. Bitte `/fp probe` schicken."] = "and GetNumReplicateItems returns 0. Please send `/fp probe`.",
    ["|cffff5555noch kein AH-Scan|r"] = "|cffff5555no AH scan yet|r",
    ["Auktionshaus offen - 'AH scannen' im Fenster (/fp show) startet den Preis-Scan."] = "Auction house open - 'Scan AH' in the window (/fp show) starts the price scan.",
    ["vor %ds"] = "%ds ago",
    ["vor %dmin"] = "%dmin ago",
    ["vor %dh"] = "%dh ago",
    ["vor %dd"] = "%dd ago",
    ["Benutzung: /fp price [Item-Link] 1g20s   (Shift+Klick auf ein Item fuegt den Link ein)"] = "Usage: /fp price [item link] 1g20s   (shift-click an item to insert its link)",
    ["           /fp price [Item-Link] clear   - eigenen Preis entfernen"] = "           /fp price [item link] clear   - remove custom price",
    ["Eigener Preis fuer Item "] = "Custom price for item ",
    [" entfernt."] = " removed.",
    ["Preis nicht verstanden: '"] = "Price not understood: '",
    ["' (Beispiele: 1g20s, 35s, 0.5)"] = "' (examples: 1g20s, 35s, 0.5)",
    ["Eigener Preis fuer Item %d: %s"] = "Custom price for item %d: %s",
    ["Queue geleert."] = "Queue cleared.",
    ["Befehle:"] = "Commands:",
    ["  /fp show      - Hauptfenster oeffnen"] = "  /fp show      - open main window",
    ["  /fp shop      - Einkaufsliste der Queue an Auctionator"] = "  /fp shop      - send queue shopping list to Auctionator",
    ["  /fp clear     - Queue leeren"] = "  /fp clear     - clear queue",
    ["  /fp price [Item] 1g20s - eigenen Preis setzen ('clear' = entfernen)"] = "  /fp price [item] 1g20s - set custom price ('clear' = remove)",
    ["  /fp scan      - Berufe/Rezepte einlesen (asynchron)"] = "  /fp scan      - read professions/recipes",
    ["  /fp stop      - laufenden Scan abbrechen"] = "  /fp stop      - stop running scan",
    ["  /fp ahscan    - Auktionshaus-Preisscan (am AH)"] = "  /fp ahscan    - auction house price scan (at the AH)",
    ["  /fp source    - Preisquelle umschalten"] = "  /fp source    - switch price source",
    ["  /fp learned   - nur gelernte Rezepte an/aus"] = "  /fp learned   - learned recipes only on/off",
    ["  /fp minimap   - Minimap-Button an/aus"] = "  /fp minimap   - minimap button on/off",
    ["  /fp probe     - API-Dump (zur Fehlersuche)"] = "  /fp probe     - API dump (for troubleshooting)",
    ["  /fp debug     - Debug an/aus"] = "  /fp debug     - debug on/off",
    ["Preisquelle: "] = "Price source: ",
    ["Nur gelernte Rezepte: "] = "Learned recipes only: ",
    ["an"] = "on",
    ["aus"] = "off",
    ["Unbekannt: "] = "Unknown: ",
    [" (hilfe: /fp help)"] = " (help: /fp help)",
    ["|cffff5555Fehler im Befehl:|r "] = "|cffff5555Command error:|r ",
    ["Mit /reload zuruecksetzen. Bitte den Fehlertext melden."] = "Reset with /reload. Please report the error text.",
    ["v%s geladen %s"] = "v%s loaded %s",
    ["|cffff5555(kein Forever-Client)|r"] = "|cffff5555(not a Forever client)|r",
    ["Start: /fp show - API-Check: /fp probe"] = "Start: /fp show - API check: /fp probe",
    ["Linksklick: Fenster an/aus"] = "Left-click: toggle window",
    ["Rechtsklick: AH scannen (am Auktionshaus)"] = "Right-click: scan AH (at the auction house)",
    ["Ziehen: Button verschieben"] = "Drag: move button",
    ["Minimap-Button: "] = "Minimap button: ",
    ["|cffff5555noch kein Scan|r"] = "|cffff5555no scan yet|r",
    ["C_AuctionHouse (nativ)"] = "C_AuctionHouse (native)",
    ["Auctionator-Scan fertig - Profitliste aktualisiert."] = "Auctionator scan finished - profit list updated.",
    ["Rezept "] = "Recipe ",
    ["Scan: %d/%d (%d%%) - %d Rezepte uebernommen"] = "Scan: %d/%d (%d%%) - %d recipes imported",
    ["keine Rezepte nach Filter"] = "no recipes after filter",
    ["Spiel liefert gerade keine Rezepte - nutze die gespeicherten. Berufsfenster oeffnen aktualisiert sie."] = "The game currently returns no recipes - using the saved ones. Opening the profession window updates them.",
    ["Fertig: %d Rezepte."] = "Done: %d recipes.",
    ["  |cff888888(keine Rezepte)|r"] = "  |cff888888(no recipes)|r",
    ["   %s: %d Rezepte (Skill %s)%s"] = "   %s: %d recipes (skill %s)%s",
    ["|cffffcc00Keine Rezepte uebernommen.|r "] = "|cffffcc00No recipes imported.|r ",
    ["Scan abgebrochen (%d/%d, %d Rezepte)."] = "Scan stopped (%d/%d, %d recipes).",
    ["Scan laeuft schon - /fp stop bricht ab."] = "Scan already running - /fp stop cancels it.",
    ["keine Berufe erkannt"] = "no professions found",
    ["|cffffcc00Keine Berufe erkannt.|r Berufsfenster einmal oeffnen."] = "|cffffcc00No professions found.|r Open a profession window once.",
    ["   %s: %d Kandidaten (Skill %s)"] = "   %s: %d candidates (skill %s)",
    ["keine Rezept-Kandidaten"] = "no recipe candidates",
    ["|cffffcc00Keine Rezepte vom Spiel.|r Berufsfenster einmal oeffnen."] = "|cffffcc00No recipes from the game.|r Open a profession window once.",
    ["Scanne %d Kandidaten in %d Beruf(en) - Filter aktiv. Abbruch: /fp stop"] = "Scanning %d candidates in %d profession(s) - filter active. Cancel: /fp stop",
    ["Queue ist leer - erst Rezepte anklicken."] = "Queue is empty - click recipes first.",
    ["|cffffcc00Einige Item-Namen werden noch geladen - bitte in 1-2 Sekunden nochmal klicken.|r"] = "|cffffcc00Some item names are still loading - please click again in 1-2 seconds.|r",
    ["|cff88ff88Vorher selbst herstellen:|r"] = "|cff88ff88Craft first:|r",
    ["|cff88ccffBeim Haendler kaufen:|r"] = "|cff88ccffBuy from vendor:|r",
    ["|cffff5555Ohne Preis (selbst besorgen):|r"] = "|cffff5555No price (get these yourself):|r",
    ["Im AH musst du nichts kaufen - alles da oder beim Haendler."] = "Nothing to buy at the AH - everything is in stock or at a vendor.",
    ["|cffffcc00Auctionator-Einkaufslisten nicht verfuegbar. Im AH kaufen:|r"] = "|cffffcc00Auctionator shopping lists not available. Buy at the AH:|r",
    ["|cffff5555Einkaufsliste fehlgeschlagen:|r "] = "|cffff5555Shopping list failed:|r ",
    ["|cff44ff44Auctionator-Einkaufsliste '%s' erstellt (%d Items).|r"] = "|cff44ff44Auctionator shopping list '%s' created (%d items).|r",
    ["Am AH: Auctionator -> Tab 'Einkaufen' -> Liste '"] = "At the AH: Auctionator -> 'Shopping' tab -> list '",
    ["|cffff5555Material fehlt|r fuer "] = "|cffff5555Missing materials|r for ",
    [" - siehe Einkaufsliste."] = " - see shopping list.",
    ["|cffff5555Herstellen per Addon wird von diesem Client nicht unterstuetzt.|r"] = "|cffff5555This client does not support crafting via addon.|r",
    ["Bitte zuerst das Berufsfenster |cffffd100"] = "Please open the profession window |cffffd100",
    ["|r oeffnen (links in der Berufe-Leiste)."] = "|r first (left in the professions bar).",
    ["Offen ist |cffffd100%s|r - fuer %s bitte |cffffd100%s|r oeffnen."] = "|cffffd100%s|r is open - for %s please open |cffffd100%s|r.",
    ["|cffff5555Herstellen fehlgeschlagen:|r "] = "|cffff5555Crafting failed:|r ",
    ["Stelle her: %dx %s"] = "Crafting: %dx %s",
    ["Nichts herstellbar - Material fehlt oder Queue ist leer."] = "Nothing craftable - missing materials or queue is empty.",
    ["|cff88ccffHaendler|r"] = "|cff88ccffvendor|r",
    ["|cff88ff88selbst herstellen|r"] = "|cff88ff88craft yourself|r",
    ["|cffffcc00eigener Preis|r"] = "|cffffcc00custom price|r",
    [" |cff888888(hast %d)|r"] = " |cff888888(have %d)|r",
    ["|cffff5555kein Preis|r"] = "|cffff5555no price|r",
    ["Kosten"] = "Cost",
    ["Verkauf %dx (nach 5%% AH-Gebuehr)"] = "Sale %dx (after 5%% AH cut)",
    ["Gewinn"] = "Profit",
    ["Ergebnis hat keinen AH-Preis"] = "Result has no AH price",
    ["Markt"] = "Market",
    ["|cffff5555ueber 3 Wochen|r"] = "|cffff5555over 3 weeks|r",
    ["heute"] = "today",
    ["gestern"] = "yesterday",
    ["vor %d Tagen"] = "%d days ago",
    ["Zuletzt im AH gesehen"] = "Last seen at the AH",
    ["Angebote (letzter Scan)"] = "Listings (last scan)",
    ["Mittlerer Preis (%d Tage)"] = "Median price (%d days)",
    ["! Aktueller Preis deutlich ueber dem Mittel - Gewinn evtl. zu optimistisch"] = "! Current price well above median - profit may be optimistic",
    ["~ Preis ist alt - vor dem Craften neu scannen"] = "~ Price is old - rescan before crafting",
    ["Viel Konkurrenz im AH"] = "Lots of competition at the AH",
    ["Skill-Farbe"] = "Skill color",
    ["orange"] = "orange",
    ["gelb"] = "yellow",
    ["gruen"] = "green",
    ["grau"] = "grey",
    ["Kosten pro Skillpunkt (geschaetzt)"] = "Cost per skill point (estimated)",
    ["In der Queue: %dx"] = "In queue: %dx",
    ["Links +1   Shift+Links +5   Rechts -1"] = "Left +1   Shift+Left +5   Right -1",
    ["Linksklick: Berufsfenster oeffnen"] = "Left-click: open profession window",
    ["Kein eigenes Berufsfenster"] = "No profession window",
    ["Rechtsklick: Liste auf diesen Beruf filtern"] = "Right-click: filter list to this profession",
    ["Berufe"] = "Professions",
    ["Alle Berufe"] = "All professions",
    ["Beruf: Links oeffnen, Rechts filtern"] = "Profession: left open, right filter",
    ["Profit-Modus"] = "Profit mode",
    ["Rezepte nach Gewinn sortiert."] = "Recipes sorted by profit.",
    ["Skillen"] = "Leveling",
    ["Skill-Modus"] = "Leveling mode",
    ["Nur Rezepte, die noch Skill geben (orange/gelb/gruen),\nsortiert nach Kosten pro Skillpunkt.\nVerkaufserloes wird gegengerechnet."] = "Only recipes that still give skill (orange/yellow/green),
sorted by cost per skill point.
Sale value is deducted.",
    ["Ungelernte zeigen"] = "Show unlearned",
    ["Ungelernte Rezepte"] = "Unlearned recipes",
    ["Zeigt auch Rezepte, die du noch nicht kannst -\npraktisch um zu sehen, ob sich ein Rezept-Kauf lohnt."] = "Also shows recipes you don't know yet -
handy to see whether buying a recipe pays off.",
    ["%d Rezepte"] = "%d recipes",
    ["%s%s%d Rezepte"] = "%s%s%d recipes",
    ["Herstellen"] = "Craft",
    ["Zwischenschritt - wird fuer die Queue gebraucht"] = "Intermediate step - needed for the queue",
    ["Herstellliste"] = "Craft list",
    ["Naechstes herstellen"] = "Craft next",
    ["|cff44ff44bereit|r"] = "|cff44ff44ready|r",
    ["|cffffcc00%d von %d moeglich|r"] = "|cffffcc00%d of %d possible|r",
    ["|cffff5555Material fehlt|r"] = "|cffff5555Missing materials|r",
    ["|cff88ff88Zwischenschritt|r  "] = "|cff88ff88Intermediate|r  ",
    ["|cff888888Leer - Rezepte in der Liste\nanklicken, um sie einzuplanen.|r"] = "|cff888888Empty - click recipes in the list
to queue them.|r",
    ["\n|cff888888... und %d weitere|r"] = "
|cff888888... and %d more|r",
    ["%d Schritte, %d Crafts  \194\183  %d bereit%s"] = "%d steps, %d crafts  9483  %d ready%s",
    ["Berufe einlesen"] = "Read professions",
    ["Liest deine Rezepte neu ein.\nPassiert auch automatisch beim Oeffnen des Berufsfensters."] = "Re-reads your recipes.
Also happens automatically when opening the profession window.",
    ["AH scannen"] = "Scan AH",
    ["Startet Auctionators Vollscan (am offenen Auktionshaus, max. alle 15 Min)."] = "Starts Auctionator's full scan (at the open auction house, max. every 15 min).",
    ["Nur Profit"] = "Profit only",
    ["Nur Rezepte mit vollstaendigen Preisen und Gewinn anzeigen."] = "Only show recipes with complete prices and profit.",
    ["Teilrezepte"] = "Sub-recipes",
    ["Zutaten, die du selbst billiger herstellen kannst,\nwerden mit dem Herstellungspreis gerechnet."] = "Reagents you can craft cheaper yourself
are calculated at their crafting cost.",
    ["Preisquellen"] = "Price sources",
    ["Modus: "] = "Mode: ",
    ["\nVerfuegbar: "] = "
Available: ",
    ["\n\nUmschalten: /fp source"] = "

Switch: /fp source",
    ["Anz."] = "Qty",
    ["Rezept"] = "Recipe",
    ["Im AH"] = "At AH",
    ["Verkauf"] = "Sale",
    ["Queue leeren"] = "Clear queue",
    ["Einkaufsliste"] = "Shopping list",
    ["Alle Zutaten der Queue minus Taschen und Bank.\nAH-Items gehen als Liste 'ForeverProfit' an Auctionator,\nHaendler-Items und Zwischenschritte stehen im Chat."] = "All reagents of the queue minus bags and bank.
AH items go to Auctionator as list 'ForeverProfit',
vendor items and intermediate steps are listed in chat.",
    ["Links +1   |   Shift+Links +5   |   Rechts -1"] = "Left +1   |   Shift+Left +5   |   Right -1",
    ["Pro Skill"] = "Per skill",
    ["|cffffcc00Lese Berufe ein... %d / %d|r"] = "|cffffcc00Reading professions... %d / %d|r",
    ["|cffffcc00Auktionshaus wird gescannt...|r"] = "|cffffcc00Scanning auction house...|r",
    ["|cffffd100Skill-Modus|r   \194\183   %d Rezepte geben noch Skill   \194\183   billigste zuerst"] = "|cffffd100Leveling mode|r   9483   %d recipes still give skill   9483   cheapest first",
    ["Preise %s   \194\183   %d Rezepte angezeigt   \194\183   %d ausgeblendet"] = "Prices %s   9483   %d recipes shown   9483   %d hidden",
    ["Noch keine Rezepte eingelesen.\n\n|cffaaaaaaBerufsfenster einmal oeffnen.|r"] = "No recipes read yet.

|cffaaaaaaOpen a profession window once.|r",
    ["Kein Rezept passt zur Suche."] = "No recipe matches the search.",
    ["Keine Rezepte gefunden, die noch Skill geben.\n\n|cffaaaaaaBerufsfenster oeffnen, damit die Skill-Farben\naktuell sind. Hilft das nicht: /fp probe schicken.|r"] = "No recipes found that still give skill.

|cffaaaaaaOpen the profession window so the skill colors
are up to date. If that doesn't help: send /fp probe.|r",
    ["Kein Rezept mit Gewinn gefunden.\n\n|cffaaaaaaAm Auktionshaus 'AH scannen' klicken\noder 'Nur Profit' ausschalten.|r"] = "No profitable recipe found.

|cffaaaaaaClick 'Scan AH' at the auction house
or turn off 'Profit only'.|r",
    [" (nicht gelernt)|r"] = " (not learned)|r",
    ["|cffffaa33Preis fehlt|r"] = "|cffffaa33price missing|r",
    ["|cffffaa33%d Preis fehlt|r"] = "|cffffaa33%d price missing|r",
    ["|cffffaa33%d Preise fehlen|r"] = "|cffffaa33%d prices missing|r",
    ["|cff888888Queue leer - Rezepte anklicken, um sie einzuplanen.|r"] = "|cff888888Queue empty - click recipes to queue them.|r",
    ["|cffffd100Queue|r %d Crafts   |cff888888Kosten|r %s   |cff888888Verkauf|r %s   |cffffd100Gewinn|r %s%s|r"] = "|cffffd100Queue|r %d crafts   |cff888888Cost|r %s   |cff888888Sale|r %s   |cffffd100Profit|r %s%s|r",
    ["Im Kampf nicht moeglich - danach nochmal."] = "Not possible in combat - try again afterwards.",
}

ns.locale = (type(GetLocale) == "function" and GetLocale()) or "enUS"
local activeLocale = (ns.locale == "deDE") and L_DE or L_EN
ns.L = setmetatable({}, { __index = function(_, k) return activeLocale[k] or k end })
local L = ns.L

ns.version    = "1.4.0"
ns.debug      = false
ns.FOREVER_TOC = 16001

do
    local _, build, _, toc = GetBuildInfo()
    ns.build     = build
    ns.toc       = tonumber(toc) or 0
    ns.isForever = (ns.toc == ns.FOREVER_TOC)
end

-- Secret-Guards -------------------------------------------------------------
function ns.IsSecret(v)
    return type(issecretvalue) == "function" and issecretvalue(v) == true
end

--- Auch Tabellen koennen secret sein (Forever hat `issecrettable`).
function ns.IsSecretTable(t)
    return type(issecrettable) == "function" and issecrettable(t) == true
end

--- pcall-Kapsel, die die Rueckgabewerte DURCHREICHT (Lua 5.1-tauglich).
--- Rueckgabe: ok, <weitere Werte...>
--- Bewusst KEIN table.pack - das existiert in WoW nicht.
function ns.Call(fn, ...)
    if type(fn) ~= "function" then return false end
    return pcall(fn, ...)
end

--- Wie ns.Call, aber sammelt ALLE Rueckgabewerte in eine Liste.
--- Fuer Funktionen mit vielen Werten (z.B. GetReplicateItemInfo: 19).
--- Rueckgabe: ok, count, {werte...}
function ns.Pack(fn, ...)
    if type(fn) ~= "function" then return false, 0, {} end
    local packed = { pcall(fn, ...) }
    local ok = packed[1]
    local out = {}
    for i = 2, #packed do out[i - 1] = packed[i] end
    return ok, #packed - 1, out
end

--- Alle globalen Namen finden, die zu einem Muster passen (fuer die Probe).
function ns.ScanGlobals(luaPattern, limit)
    local out, n = {}, 0
    local base = _G
    for k, v in pairs(base) do
        if type(k) == "string" and k:find(luaPattern) then
            out[#out + 1] = k .. " (" .. type(v) .. ")"
            n = n + 1
            if limit and n >= limit then break end
        end
    end
    table.sort(out)
    return out
end

--- Groesse einer Tabelle (Anzahl Schluessel), defensiv.
function ns.Count(tbl)
    if type(tbl) ~= "table" or ns.IsSecretTable(tbl) then return 0 end
    local n = 0
    pcall(function() for _ in pairs(tbl) do n = n + 1 end end)
    return n
end

--- Struktur einer Tabelle beschreiben: "key:typ" je Feld, sortiert.
--- Liest NIEMALS Werte - damit koennen secret-Werte nicht werfen.
function ns.Describe(tbl)
    local out = {}
    if type(tbl) ~= "table" then return { "<" .. type(tbl) .. ">" } end
    if ns.IsSecretTable(tbl) then return { "<secret table>" } end
    local ok = pcall(function()
        for k, v in pairs(tbl) do
            out[#out + 1] = tostring(k) .. ":" .. type(v)
        end
    end)
    if not ok then return { "<unlesbar>" } end
    table.sort(out)
    return out
end

function ns.Value(v, fallback)
    if ns.IsSecret(v) then return fallback end
    return v
end

function ns.Try(fn, ...)
    if ns.IsSecret(fn) then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        if ns.debug then ns:Print("|cffff5555err:|r " .. tostring(a)) end
        return nil
    end
    return a, b, c, d
end

function ns.Str(v, fallback)
    if v == nil or ns.IsSecret(v) then return fallback or "?" end
    return tostring(v)
end

--- Timer-Helfer (C_Timer modern, Frame-Fallback).
function ns.C_Timer_After(sec, fn)
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(sec, fn)
        return
    end
    local t = CreateFrame("Frame")
    local left = tonumber(sec) or 0
    t:SetScript("OnUpdate", function(self, dt)
        left = left - (dt or 0)
        if left <= 0 then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

function ns.HasFn(path)
    local cur = _G
    for part in tostring(path):gmatch("[^.]+") do
        if type(cur) ~= "table" then return false end
        cur = cur[part]
    end
    return type(cur) == "function"
end

--- Gold-Formatierung: 1234567 -> "123g 45s 67k"
function ns.Money(copper)
    copper = tonumber(copper) or 0
    local neg = copper < 0
    copper = math.abs(math.floor(copper))
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local str
    if g > 0 then str = string.format("%dg %ds %dc", g, s, c)
    elseif s > 0 then str = string.format("%ds %dc", s, c)
    else str = string.format("%dc", c) end
    return (neg and "-" or "") .. str
end

-- Ausgabe -------------------------------------------------------------------
local PREFIX = "|cff33aaffForeverProfit|r "
function ns:Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(msg))
    end
end

-- Slash ---------------------------------------------------------------------

--- "1g20s5c" | "20s" | "1.5" (= Gold) -> Kupfer, oder nil.
local function parseMoney(str)
    str = (str or ""):gsub("%s+", "")
    if str == "" then return nil end
    local g = tonumber(str:match("(%d+)g")) or 0
    local s = tonumber(str:match("(%d+)s")) or 0
    local c = tonumber(str:match("(%d+)c")) or 0
    if g + s + c > 0 then return g * 10000 + s * 100 + c end
    local gold = tonumber(str)
    if gold and gold > 0 then return math.floor(gold * 10000 + 0.5) end
    return nil
end

--- /fp price <Itemlink oder ItemID> <Preis | clear>
local function priceCommand(input)
    local id = tonumber(input:match("item:(%d+)") or input:match("^price%s+(%d+)"))
    local rest = input:match("|h|r%s*(.-)$") or input:match("^price%s+%d+%s*(.-)$") or ""
    if not id then
        ns:Print(L["Benutzung: /fp price [Item-Link] 1g20s   (Shift+Klick auf ein Item fuegt den Link ein)"])
        ns:Print(L["           /fp price [Item-Link] clear   - eigenen Preis entfernen"])
        return
    end
    if rest == "clear" or rest == "" then
        ns.Prices.SetManual(id, nil)
        ns:Print(L["Eigener Preis fuer Item "] .. id .. L[" entfernt."])
    else
        local copper = parseMoney(rest)
        if not copper then
            ns:Print(L["Preis nicht verstanden: '"] .. rest .. L["' (Beispiele: 1g20s, 35s, 0.5)"])
            return
        end
        ns.Prices.SetManual(id, copper)
        ns:Print(string.format(L["Eigener Preis fuer Item %d: %s"], id, ns.Money(copper)))
    end
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

--- Alle Befehle laufen in pcall: ein Fehler darf das Chatfenster NIE
--- blockieren (genau der Bug aus v0.1/0.2).
local function handle(input)
    input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if input:find("^price") then
        priceCommand(input)
    elseif input == "shop" then
        if ns.Profit then ns.Profit.SendShoppingList() end
    elseif input == "clear" then
        if ns.Profit then ns.Profit.QueueClear() end
        if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        ns:Print(L["Queue geleert."])
    elseif input == "" or input == "help" then
        ns:Print(L["Befehle:"])
        ns:Print(L["  /fp show      - Hauptfenster oeffnen"])
        ns:Print(L["  /fp shop      - Einkaufsliste der Queue an Auctionator"])
        ns:Print(L["  /fp clear     - Queue leeren"])
        ns:Print(L["  /fp price [Item] 1g20s - eigenen Preis setzen ('clear' = entfernen)"])
        ns:Print(L["  /fp scan      - Berufe/Rezepte einlesen (asynchron)"])
        ns:Print(L["  /fp stop      - laufenden Scan abbrechen"])
        ns:Print(L["  /fp ahscan    - Auktionshaus-Preisscan (am AH)"])
        ns:Print(L["  /fp source    - Preisquelle umschalten"])
        ns:Print(L["  /fp learned   - nur gelernte Rezepte an/aus"])
        ns:Print(L["  /fp minimap   - Minimap-Button an/aus"])
        ns:Print(L["  /fp probe     - API-Dump (zur Fehlersuche)"])
        ns:Print(L["  /fp debug     - Debug an/aus"])
    elseif input == "show" then
        if ns.UI then ns.UI.Toggle() end
    elseif input == "scan" then
        if ns.Professions then ns.Professions.ScanAsync(true) end
    elseif input == "stop" then
        if ns.Professions then ns.Professions.Stop() end
    elseif input == "ahscan" then
        if ns.AuctionScan then ns.AuctionScan.Start() end
    elseif input == "source" then
        local db = ns.Config and ns.Config.db
        if db then
            local order = { "auto", "native", "auctionator", "manual" }
            local cur = 1
            for i, v in ipairs(order) do if v == db.priceSource then cur = i end end
            db.priceSource = order[(cur % #order) + 1]
            ns:Print(L["Preisquelle: "] .. db.priceSource)
        end
    elseif input == "minimap" then
        if ns.Minimap then ns.Minimap.Toggle() end
    elseif input == "learned" then
        local db = ns.Config and ns.Config.db
        if db then
            db.onlyLearned = not db.onlyLearned
            ns:Print(L["Nur gelernte Rezepte: "] .. (db.onlyLearned and L["an"] or L["aus"]))
            if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
        end
    elseif input == "probe" then
        if ns.Professions then ns.Professions.Probe() end
    elseif input == "debug" then
        ns.debug = not ns.debug
        if ns.Config and ns.Config.db then ns.Config.db.debug = ns.debug end
        ns:Print("Debug: " .. (ns.debug and L["an"] or L["aus"]))
    else
        ns:Print(L["Unbekannt: "] .. input .. L[" (hilfe: /fp help)"])
    end
end

local function slash(input)
    local ok, err = pcall(handle, input)
    if not ok then
        ns:Print(L["|cffff5555Fehler im Befehl:|r "] .. tostring(err))
        ns:Print(L["Mit /reload zuruecksetzen. Bitte den Fehlertext melden."])
    end
end

SLASH_FOREVERPROFIT1 = "/fp"
SLASH_FOREVERPROFIT2 = "/foreverprofit"
SlashCmdList["FOREVERPROFIT"] = slash

-- Boot ----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")

    if ns.Config and ns.Config.Init then ns.Config.Init() end
    if ns.Prices and ns.Prices.Init then ns.Prices.Init() end
    if ns.Minimap and ns.Minimap.Init then ns.Minimap.Init() end

    ns:Print(string.format(L["v%s geladen %s"], ns.version,
        ns.isForever and ("(Forever TOC " .. tostring(ns.toc) .. ")")
                     or L["|cffff5555(kein Forever-Client)|r"]))
    ns:Print(L["Start: /fp show - API-Check: /fp probe"])
end)
