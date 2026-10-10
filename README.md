# ForeverProfit

Crafting profit helper for the **WoW Forever** client (Interface 16001), using **Auctionator** prices.

*Deutsch weiter unten.*

## Features

- **Profit list** – every recipe of your character with reagent cost, sale price (after the 5% AH cut) and profit, sorted by profit.
- **Prices from Auctionator** – full scans, normal searches and the selling tab all feed the list. Vendor prices for reagents (thread, salt, flux …) are used when cheaper.
- **Sub-recipes** – reagents you can craft cheaper yourself (e.g. Cured Light Hide) are calculated at their crafting cost, recursively.
- **Market check** – number of listings at the AH, median price, warnings for old prices (`~`) and price spikes (`!`).
- **Queue & shopping list** – queue recipes with quantities; the shopping list subtracts bags and bank and is sent to Auctionator as list `ForeverProfit`.
- **Craft list** – craft the queue step by step (“Craft next”), intermediate steps first. The queue counts down automatically.
- **Professions bar** – left-click opens a profession, right-click filters the list.
- **Leveling mode** – recipes that still give skill, sorted by estimated cost per skill point.
- **Custom prices** – `/fp price [item] 1g20s`.
- German and English (follows the client language).

## Requirements

- WoW Forever client (`_classic_beta_`, Interface 16001)
- [Auctionator](https://www.curseforge.com/wow/addons/auctionator)

## Installation

Copy the `ForeverProfit` folder to `World of Warcraft\_classic_beta_\Interface\AddOns\` and restart the game.

## Usage

| | |
|---|---|
| `/fp show` or minimap button | open the window |
| Left-click recipe | +1 to queue (Shift: +5) |
| Right-click recipe | −1 from queue |
| `/fp shop` | send shopping list to Auctionator |
| `/fp price [item] 1g20s` | set a custom price (`clear` removes it) |
| `/fp help` | all commands |

Crafting requires the matching profession window to be open (Blizzard restriction).

---

## Deutsch

Profit-Rechner für Berufe im **WoW-Forever**-Client mit Preisen aus **Auctionator**: Profit-Liste, Händlerpreise, Teilrezepte, Marktlage, Queue mit Einkaufsliste für Auctionator, Herstellliste, Berufe-Leiste und Skill-Modus. Die Sprache folgt automatisch dem Spiel-Client.

Installation: Ordner `ForeverProfit` nach `World of Warcraft\_classic_beta_\Interface\AddOns\` kopieren, Spiel neu starten, `/fp show`.

## License

MIT – see [LICENSE](LICENSE).
