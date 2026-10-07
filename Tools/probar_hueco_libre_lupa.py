"""Comprueba el indicador de hueco vacío en evaluaciones de Guerrero y Mago."""

from pathlib import Path

from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent / "Addon" / "SimulateX"


def check_class(class_name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r"""
local mockMeta
local function newMock() return setmetatable({}, mockMeta) end
mockMeta = {
  __index = function(t, k)
    local f = function(self, ...)
      if k == "GetWidth" then return 700 end
      if k == "IsVisible" or k == "IsShown" then return rawget(self, "_shown") end
      if k == "SetScript" then local name, fn = ...; rawset(self, "_script_" .. name, fn); return end
      if k == "Show" then rawset(self, "_shown", true); return end
      if k == "Hide" then rawset(self, "_shown", false); return end
      if k == "SetText" then rawset(self, "_text", (...)); return end
      if k == "GetName" then return rawget(self, "_name") or "Mock" end
      if k:match("^Create") or k == "GetParent" then return newMock() end
      return nil
    end
    rawset(t, k, f)
    return f
  end,
}
CreateFrame = function(_, name)
  local frame = newMock()
  if name then rawset(frame, "_name", name); _G[name] = frame end
  return frame
end
UIParent, GameTooltip = newMock(), newMock()
UISpecialFrames, SlashCmdList = {}, {}
hooksecurefunc = function() end
InterfaceOptions_AddCategory = function() end
UnitClass = function() return CLASSNAME, string.upper(CLASSNAME) end
UnitLevel = function() return 80 end
UnitFactionGroup = function() return "Alliance" end
UnitAura = function() return nil end
UnitStat = function() return 60, 60, 0, 0 end
GetTalentTabInfo = function(i) return nil, nil, i == 1 and 51 or 10 end
GetInventorySlotInfo = function(name) return name end
GetInventoryItemLink = function(_, slot) return EQUIPMENT[slot] end
GetInventoryItemTexture = function() return nil end
GetItemInfo = function(item)
  local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  local data = id and ITEMS[id]
  if not data then return nil end
  local link = type(item) == "string" and item or data.link
  return data.name, link, 4, 100, 1, "Armor", "Cloth", 1, data.equipLoc, "icon", 0
end
GetItemIcon = function() return "icon" end
GetAddOnInfo = function() return true end
GetAddOnMetadata = function() return "0.7" end
ITEM_QUALITY_COLORS = {}
for i = 0, 7 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
INVTYPE_HEAD = "Cabeza"
ITEMS, EQUIPMENT = {}, {}
SimulateX_DB = {}
SimulateX_ItemStats, SimulateX_ItemTypes, SimulateX_ItemClasses = {}, {}, {}
setmetatable(_G, { __index = function(_, key)
  if type(key) == "string" and (key:match("^Get") or key:match("^Unit")) then
    return function() return 0 end
  end
end })
""")
    g = lua.globals()
    g.CLASSNAME = class_name

    head_id = 990101
    neck_id = 990102
    equipped_neck_id = 990103

    def configure(item_id, name, equip_loc, strength):
        link = f"|cff0070dd|Hitem:{item_id}:0:0:0:0:0:0:0:80|h[{name}]|h|r"
        g.ITEMS[item_id] = lua.table_from(
            {"name": name, "link": link, "equipLoc": equip_loc}
        )
        g.SimulateX_ItemStats[item_id] = f"4={strength}"
        return link

    head_link = configure(head_id, "Head upgrade", "INVTYPE_HEAD", 1000)
    neck_link = configure(neck_id, "Neck upgrade", "INVTYPE_NECK", 1000)
    equipped_neck_link = configure(equipped_neck_id, "Equipped neck", "INVTYPE_NECK", 100)
    g.EQUIPMENT["NeckSlot"] = equipped_neck_link

    build = lua.table_from(
        {
            "spec": "fixture",
            "specLabel": "Prueba",
            "talentTree": 0,
            "avgItemLevel": 100,
            "weightsKind": "preset",
            "role": "dps",
            "weights": lua.table_from({"ITEM_MOD_STRENGTH_SHORT": 1}),
        }
    )
    class_data = lua.table()
    class_data["fixture"] = build
    g[f"SimulateX_Data_{class_name}"] = class_data
    g.SimulateX_DB = lua.table()

    source = (ROOT / "SimulateX.lua").read_text(encoding="utf-8")
    lua.execute(source.replace("local ADDON_NAME = ...", 'local ADDON_NAME = "SimulateX"'))

    context = lua.table_from(
        {
            "buildId": "fixture",
            "build": build,
            "playerLevel": 80,
            "gameClassName": class_name,
        }
    )
    api = g.SimulateX_API
    empty_eval = api.EvaluateForContext(context, head_link)
    occupied_eval = api.EvaluateForContext(context, neck_link)
    if empty_eval.againstEmpty is not True:
        raise AssertionError(f"{class_name}: el hueco de cabeza vacío debe marcarse")
    if occupied_eval.againstEmpty is not False:
        raise AssertionError(f"{class_name}: el cuello ocupado no debe marcarse")
    if empty_eval.percent <= 100:
        raise AssertionError(f"{class_name}: la fixture vacía debe superar el 100 %")
    if api.FormatPercent(empty_eval) != "hueco libre":
        raise AssertionError(f"{class_name}: no se ocultó el porcentaje alto")
    expected_occupied = f"{occupied_eval.percent:+.1f} %"
    if api.FormatPercent(occupied_eval) != expected_occupied:
        raise AssertionError(f"{class_name}: cambió el texto con el hueco ocupado")

    empty_comparison = api.GetComparisonEvaluations(head_link, None, False)[1]
    occupied_comparison = api.GetComparisonEvaluations(neck_link, None, False)[1]
    if empty_comparison.againstEmpty is not True or occupied_comparison.againstEmpty is not False:
        raise AssertionError(f"{class_name}: el comparador marcó mal el hueco vacío")

    low = lua.table_from({"percent": 15.5, "gain": 1, "againstEmpty": True, "isNoise": False})
    if api.FormatPercent(low) != "+15.5 % (hueco libre)":
        raise AssertionError(f"{class_name}: el porcentaje bajo no conserva la nota")
    print(f"OK {class_name}: hueco libre, comparación ocupada y formato")


for name in ("Warrior", "Mage"):
    check_class(name)
