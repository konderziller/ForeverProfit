"""Profit test for ForeverProfit: spike prices must not inflate the profit.

Run from the addon folder:  python -I tools/test_profit.py
Needs lupa (Lua 5.1) in tools/pylib, see test_prices.py.
"""
import os, sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
sys.path.insert(0, os.path.join(TOOLS, "pylib"))
import lupa.lua51 as lupa
from test_prices import STUBS, ADDON, toc_files

# 2589 Linen Cloth (reagent), 2580 Linen Bag (output)
HISTORY = r'''
AUC_PRICES = { [2589] = 100, [2580] = 1000 }
HIST = {}
Auctionator.Database = { GetPriceHistory = function(_, id) return HIST[tonumber(id)] end }
Auctionator.API.v1.GetAuctionAgeByItemID = function() return 0 end
'''


def load():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    lua.execute(HISTORY)
    lua.globals().LOCALE = "enUS"
    ns = lua.eval("{}")
    loader = lua.eval("function(src, name, ns) local f = assert(loadstring(src, name)); f('ForeverProfit', ns) end")
    for f in toc_files():
        loader(open(os.path.join(ADDON, f.replace("\\", os.sep)), encoding="utf-8").read(), f, ns)
    lua.eval('''function(ns)
      for _, f in ipairs(FRAMES) do
        if f.events.ADDON_LOADED and f.scripts.OnEvent then f.scripts.OnEvent(f, "ADDON_LOADED", "ForeverProfit") end
      end
      ns.Config.db.priceSource = "auctionator"
      ns.Professions.recipes = { {
        key = "bag", name = "Linen Bag", learned = true,
        output = { id = 2580, name = "Linen Bag", count = 1 },
        reagents = { { id = 2589, name = "Linen Cloth", count = 3 } },
      } }
    end''')(ns)
    return lua, ns


def evaluate(lua, ns, history):
    lua.execute("HIST = { [2580] = %s }" % history)
    return lua.eval("function(ns) ns.Profit.Begin(); return ns.Profit.Evaluate(ns.Professions.recipes[1]) end")(ns)


def check(name, got, want):
    ok = got == want
    print("%s %s: got %s, want %s" % ("ok  " if ok else "FAIL", name, got, want))
    return ok


lua, ns = load()
results = []

# Normal market: price 1000 close to median 950, so the profit uses the listing.
e = evaluate(lua, ns, "{ {minSeen=1000}, {minSeen=950}, {minSeen=900} }")
results += [check("normal spike", e.spike, False),
            check("normal revenue", e.revenue, 950),      # 1000 * 0.95
            check("normal profit", e.profit, 650)]        # 950 - 3*100

# Spike: price 1000 vs median 500, so revenue must use the median.
e = evaluate(lua, ns, "{ {minSeen=1000}, {minSeen=500}, {minSeen=500}, {minSeen=450} }")
results += [check("spike flag", e.spike, True),
            check("spike revenue", e.revenue, 475),       # median 500 * 0.95
            check("spike profit", e.profit, 175),
            check("spike listing price kept", e.listPrice, 1000)]

# Too little history (2 days): no spike check, listing price is used.
e = evaluate(lua, ns, "{ {minSeen=1000}, {minSeen=400} }")
results += [check("short history spike", e.spike, False),
            check("short history revenue", e.revenue, 950)]

# Own price set with /fp price: never replaced by the median.
lua.eval("function(ns) ns.Config.db.manualPrices = { [2580] = 1000 } end")(ns)
e = evaluate(lua, ns, "{ {minSeen=1000}, {minSeen=500}, {minSeen=500}, {minSeen=450} }")
results += [check("manual price spike", e.spike, False),
            check("manual price revenue", e.revenue, 950)]
lua.eval("function(ns) ns.Config.db.manualPrices = { [\"Linen Bag\"] = 1000 }; AUC_PRICES[2580] = nil end")(ns)
e = evaluate(lua, ns, "{ {minSeen=1000}, {minSeen=500}, {minSeen=500}, {minSeen=450} }")
results += [check("manual price by name revenue", e.revenue, 950)]

ok = all(results)
print("OK" if ok else "FAILED")
sys.exit(0 if ok else 1)
