'''Comprueba las recomendaciones de encantamientos en Mejoras con la API de
WoW simulada. Uso: probar_encantamientos_lupa.py [<Clase> <Clase> ...]'''

import pathlib
import sys
import time

from lupa import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'Addon'
CLASSES = sys.argv[1:] or ['Warrior', 'Mage']
GEAR_IDS = {'Warrior': 50712, 'Mage': 51281}


def create_runtime(class_name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
local mockMeta
local function newMock() return setmetatable({}, mockMeta) end
mockMeta = {
  __index = function(t, k)
    local f = function(self, ...)
      if k == "GetWidth" then return 700 end
      if k == "IsVisible" or k == "IsShown" then return rawget(self, "_shown") end
      if k == "SetScript" then local name, fn = ...; rawset(self, "_script_" .. name, fn); return end
      if k == "SetChecked" then rawset(self, "_checked", (...)); return end
      if k == "GetChecked" then return rawget(self, "_checked") end
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
_G.newMock = newMock
CreateFrame = function(_, name)
  local frame = newMock()
  if name then
    rawset(frame, "_name", name)
    _G[name] = frame
    _G[name .. "Text"] = newMock()
    _G[name .. "Low"] = newMock()
    _G[name .. "High"] = newMock()
  end
  return frame
end
UIParent = newMock(); GameTooltip = newMock()
UISpecialFrames = {}
hooksecurefunc = function() end
UnitClass = function() return CLASSNAME, string.upper(CLASSNAME) end
UnitLevel = function() return PLAYERLEVEL end
UnitFactionGroup = function() return "Horde" end
UnitAura = function() return nil end
UnitStat = function() return 60, 60, 0, 0 end
GetSpellInfo = function(id) return "Prof" .. tostring(id) end
GetNumSkillLines = function() return 0 end
GetSkillLineInfo = function() return nil end
GetTalentTabInfo = function(i)
  local activeTalentTab = CLASSNAME == "Druid" and 1 or CLASSNAME == "Paladin" and 3 or 2
  return nil, nil, (i == activeTalentTab and 51 or 10)
end
ITEMS = {}
EQUIPMENT = {}
GetItemInfo = function(item)
  local itemId = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  local data = itemId and ITEMS[itemId]
  if not data then return nil end
  local link = type(item) == "string" and item or ("item:" .. itemId .. ":0:0:0:0:0:0:0")
  return data.name, link, data.quality or 4, data.itemLevel or 264, data.minLevel or 1,
    data.itemType or "Armor", data.itemSubType or "Plate", 1, data.equipLoc, "icon" .. itemId, 0
end
GetItemIcon = function(id) return "icon" .. tostring(id) end
GetInventoryItemTexture = function(_, slot)
  local link = EQUIPMENT[slot]
  local id = link and tonumber(link:match("item:(%d+)"))
  return id and ("equippedicon" .. id)
end
GetItemCount = function() return 0 end
GetInventorySlotInfo = function(name) return name end
GetInventoryItemLink = function(_, slot) return EQUIPMENT[slot] end
GetAddOnInfo = function() return true end
GetAddOnMetadata = function() return "0.7" end
GetCoinTextureString = function(c) return tostring(c) .. "c" end
LoadAddOn = function() return true end
ITEM_QUALITY_COLORS = {}
for i = 0, 7 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
INVTYPE_HEAD = "Cabeza"
SlashCmdList = {}
InterfaceOptions_AddCategory = function() end
setmetatable(_G, { __index = function(t, k)
  if type(k) == "string" and (k:match("^Get") or k:match("^Unit")) then
    return function() return 0 end
  end
end })
''')
    g = lua.globals()
    g.CLASSNAME = class_name
    g.PLAYERLEVEL = 80
    g.SimulateX_DB = lua.table()
    g.ITEMS = lua.table()
    gear_id = GEAR_IDS[class_name]
    g.ITEMS[gear_id] = lua.table_from({
        'name': f'{class_name} helmet',
        'equipLoc': 'INVTYPE_HEAD',
        'itemLevel': 264,
    })

    def load(path):
        code = (ROOT / path).read_text(encoding='utf-8')
        code = code.replace('local ADDON_NAME = ...', 'local ADDON_NAME = "SimulateX"')
        if path.endswith('Mejoras.lua'):
            code = code.replace('local results  --', 'results = nil --')
            code = code.replace('local page, statusText,', 'local page; statusText = nil; local')
            code += '\nSLOT_GROUPS_DEBUG = {} for i, g in ipairs(SLOT_GROUPS) do SLOT_GROUPS_DEBUG[i] = g[1] end'
        lua.execute(code)

    files = [
        'SimulateX/Data/SimulateX_Levels.lua',
        'SimulateX/Data/SimulateX_ItemTypes.lua',
        'SimulateX/Data/SimulateX_ItemStats.lua',
        'SimulateX/Data/SimulateX_GolpeTalentos.lua',
        'SimulateX/Data/SimulateX_Gemas.lua',
        'SimulateX/Data/SimulateX_Encantamientos.lua',
        f'SimulateX_{class_name}/Data/SimulateX_Data_{class_name}.lua',
        'SimulateX_Origenes/Data/SimulateX_Origenes.lua',
        'SimulateX/SimulateX.lua',
        'SimulateX/UI/Mejoras.lua',
        'SimulateX/SimulateXOptions.lua',
    ]
    for path in files:
        load(path)
    g.SimulateX_DB = lua.table()

    parent = lua.eval('newMock()')
    page_content = g.SimulateX_BuildUpgradesPage(parent)
    options_panel = g.SimulateXOptionsPanel
    options_panel['refresh']()
    option = g.SimulateXOptionsEnchantAdviceCheck
    if not option['GetChecked'](option):
        raise AssertionError('La casilla Recomendar encantamientos debe estar activada por defecto')
    return lua, g, parent, page_content, option, gear_id


def recommendations(g):
    values = g.results['enchantments']
    return [values[i] for i in range(1, len(values) + 1)] if values else []


def run_recommendations(g, parent, page_content, gear_id, effect):
    g.EQUIPMENT['HeadSlot'] = f'item:{gear_id}:{effect}:0:0:0:0:0:0:0'
    g.SimulateX_Mejoras_MarkDirty()
    page_content['refresh']()
    rawget = g.rawget
    start = time.time()
    frames = 0
    while rawget(parent, '_script_OnUpdate'):
        parent['_script_OnUpdate'](parent, 0.016)
        frames += 1
        if frames > 10000:
            raise AssertionError('El cálculo de Mejoras no terminó')
    if rawget(g.statusText, '_text') is None:
        raise AssertionError(f'No hay estado de Mejoras tras {time.time() - start:.2f}s')
    return recommendations(g)


def check_class(class_name):
    lua, g, parent, page_content, option, gear_id = create_runtime(class_name)
    no_enchant = run_recommendations(g, parent, page_content, gear_id, 0)
    if len(no_enchant) != 1:
        raise AssertionError(f'{class_name}: sin encantar debía proponer una mejora, obtuvo {len(no_enchant)}')
    best_effect = no_enchant[0]['enchantment']['effect']
    if not no_enchant[0]['name'] or no_enchant[0]['itemId'] != gear_id:
        raise AssertionError(f'{class_name}: faltan el nombre localizado o el objeto equipado')

    known_bad = run_recommendations(g, parent, page_content, gear_id, 3329)
    if len(known_bad) != 1:
        raise AssertionError(f'{class_name}: el encantamiento conocido 3329 debía mejorar')

    unknown = run_recommendations(g, parent, page_content, gear_id, 999999)
    if unknown:
        raise AssertionError(f'{class_name}: se recomendó cambiar un encantamiento desconocido')

    already_best = run_recommendations(g, parent, page_content, gear_id, best_effect)
    if already_best:
        raise AssertionError(f'{class_name}: se propuso un cambio teniendo ya el mejor encantamiento')

    option['SetChecked'](option, False)
    option['_script_OnClick'](option)
    if not g.SimulateX_DB['enchantAdviceDisabled']:
        raise AssertionError(f'{class_name}: la casilla no desactivó las recomendaciones')
    disabled = run_recommendations(g, parent, page_content, gear_id, 0)
    if disabled:
        raise AssertionError(f'{class_name}: la casilla desactivada dejó recomendaciones visibles')

    option['SetChecked'](option, True)
    option['_script_OnClick'](option)
    if g.SimulateX_DB['enchantAdviceDisabled']:
        raise AssertionError(f'{class_name}: no se pudo volver a activar la casilla')
    g.PLAYERLEVEL = 79
    low_level = run_recommendations(g, parent, page_content, gear_id, 0)
    if low_level:
        raise AssertionError(f'{class_name}: se recomendaron encantamientos por debajo de nivel 80')
    print(f'OK {class_name}: sin encantar, encantamiento conocido, desconocido, mejor, casilla y nivel 79')


for class_name in CLASSES:
    if class_name not in GEAR_IDS:
        raise SystemExit(f'Clase no admitida por esta prueba: {class_name}')
    check_class(class_name)
