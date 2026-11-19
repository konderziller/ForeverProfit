"""Ladetest fuer ForeverProfit + Preisquellen (Auctionator / TSM / manuell).

Aufruf aus dem Addon-Ordner:  python -I tools/test_prices.py
Benoetigt lupa (Lua 5.1) in tools/pylib:  python -m pip install --target tools/pylib lupa
"""
import os, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(TOOLS)
sys.path.insert(0, os.path.join(TOOLS, "pylib"))
import lupa.lua51 as lupa

STUBS = r'''
local function obj()
  local o = { scripts = {}, events = {} }
  return setmetatable(o, { __index = function(t, k)
    if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
    if k == "RegisterEvent" then return function(self, e) self.events[e] = true end end
    if k == "GetWidth" or k == "GetHeight" then return function() return 100 end end
    if k == "CreateTexture" or k == "CreateFontString" then return function() return obj() end end
    return function() end
  end })
end
FRAMES = {}
CreateFrame = function() local f = obj(); FRAMES[#FRAMES+1] = f; return f end
UIParent, Minimap, GameTooltip = obj(), obj(), obj()
UISpecialFrames = {}
tinsert = table.insert
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
SlashCmdList = {}
OUT = {}
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring((select(i, ...))) end OUT[#OUT+1] = table.concat(t, " ") end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) OUT[#OUT+1] = m end }
GetLocale = function() return LOCALE end
GetTime = function() return 0 end
time = os.time
date = os.date
C_Timer = { After = function(_, f) f() end, NewTicker = function() return obj() end }
C_AddOns = { GetAddOnMetadata = function() return "@project-version@" end }
GetBuildInfo = function() return "1.60.1", "70790", "x", 16001 end
issecretvalue = function() return false end
hooksecurefunc = function() end
InCombatLockdown = function() return false end
C_TradeSkillUI = {}
C_Item = { GetItemCount = function() return 0 end }
-- Preisquellen
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) return AUC_PRICES[id] end,
  GetVendorPriceByItemID = function() return nil end,
  RegisterForDBUpdate = function() end,
} } }
TSM_API = {
  GetCustomPriceValue = function(str, itemString)
    TSM_CALLS[#TSM_CALLS+1] = str
    if str ~= "dbmarket" and not str:match("^first%(db") then return nil, "Invalid source" end
    local id = tonumber(itemString:match("^i:(%d+)$"))
    return TSM_PRICES[id]
  end,
}
AUC_PRICES = { [2318] = 150, [2320] = 50 }
TSM_PRICES = { [2318] = 140, [2319] = 900 }
TSM_CALLS = {}
'''

def toc_files():
    toc = [f for f in os.listdir(ADDON) if f.endswith(".toc")][0]
    out = []
    for line in open(os.path.join(ADDON, toc), encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def run(locale):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.globals().LOCALE = locale
    ns = lua.eval("{}")
    loader = lua.eval("function(src, name, ns) local f = assert(loadstring(src, name)); f('ForeverProfit', ns) end")
    for f in toc_files():
        loader(open(os.path.join(ADDON, f.replace("\\", os.sep)), encoding="utf-8").read(), f, ns)
    res = lua.eval('''function(ns)
      for _, f in ipairs(FRAMES) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "ForeverProfit") end
      end
      local db = ns.Config.db
      local r = {}
      local function get(mode, id) db.priceSource = mode; return tostring(ns.Prices.Get(id)) .. "/" .. tostring(ns.Prices.source) end
      r[#r+1] = "default=" .. tostring(db.priceSource)    -- tsm
      db.priceSource = "auto"; ns.Prices.Init()
      r[#r+1] = "migriert=" .. tostring(db.priceSource)   -- auto -> tsm
      r[#r+1] = "modes=" .. table.concat(ns.Prices.Modes(), ",")
      r[#r+1] = "tsm 2320=" .. get("tsm", 2320)           -- fest TSM: kein Auctionator-Fallback (nil)
      local saved = TSM_API; TSM_API = nil
      r[#r+1] = "ohneTSM 2318=" .. get("tsm", 2318)       -- ohne TSM-Addon -> Auctionator (150)
      TSM_API = saved
      r[#r+1] = "formel=" .. tostring(db.tsmSource)
      r[#r+1] = "tsm 2318=" .. get("tsm", 2318)
      r[#r+1] = "auctionator 2319=" .. get("auctionator", 2319)
      db.tsmSource = "dbbogus"
      r[#r+1] = "tsm-invalid 2319=" .. get("tsm", 2319)   -- faellt auf dbmarket zurueck
      db.tsmSource = nil
      for k, fn in pairs(SlashCmdList) do
        if k:find("FOREVERPROFIT") then fn("tsm dbmarket"); fn("tsm"); fn("tsm reset"); fn("source"); fn("help") end
      end
      r[#r+1] = "detect=" .. table.concat(ns.Prices.Detect(), ",")
      return table.concat(r, " | ")
    end''')(ns)
    out = list(lua.globals().OUT.values())
    errs = [l for l in out if "Fehler:" in l or "Fehler im" in l or "error" in l.lower() and "fehlersuche" not in l.lower()]
    print("--- %s: %s" % (locale, res))
    for l in out:
        if "TSM" in l or "tsm" in l:
            print("    ", l)
    for l in errs:
        print("ERR", l)
    return not errs


if __name__ == "__main__":
    ok = all(run(loc) for loc in ("deDE", "enUS"))
    print("OK" if ok else "FAILED")
    sys.exit(0 if ok else 1)
