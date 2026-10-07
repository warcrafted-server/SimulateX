'''Comprueba el comando de mejoras en las bolsas y su aviso de inicio con la API
de WoW simulada. Uso: probar_bolsas_lupa.py [Warrior|Mage].'''

import sys
from pathlib import Path

from lupa import LuaRuntime

CLASSES = sys.argv[1:] or ['Warrior', 'Mage']
ROOT = Path(__file__).resolve().parent.parent / 'Addon' / 'SimulateX'
GEAR_ID = 987001
BEST_ID = 987002
NEXT_ID = 987003
WORSE_ID = 987004
UNUSABLE_ID = 987005
NOISE_ID = 987006
TOO_HIGH_ID = 987007
THIRD_ID = 987008
FOURTH_ID = 987009


def create_runtime(class_name, bag_ids):
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
FRAMES = {}
CreateFrame = function(_, name)
  local frame = newMock()
  table.insert(FRAMES, frame)
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
GetTalentTabInfo = function(i)
  return nil, nil, (i == 2 and 51 or 10)
end
GetNumSkillLines = function() return 0 end
GetItemInfo = function(item)
  local itemId = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  local data = itemId and ITEMS[itemId]
  if not data then return nil end
  local link = type(item) == "string" and item or data.link
  return data.name, link, 4, data.itemLevel, data.minLevel, "Armor", data.subType, 1,
    data.equipLoc, "icon" .. itemId, 0
end
GetContainerNumSlots = function(bag) return #(BAGS[bag] or {}) end
GetContainerItemLink = function(bag, slot)
  local itemId = BAGS[bag] and BAGS[bag][slot]
  return itemId and ITEMS[itemId] and ITEMS[itemId].link
end
GetInventorySlotInfo = function(name) return name end
GetInventoryItemLink = function(_, slot) return EQUIPMENT[slot] end
GetAddOnInfo = function() return true end
GetAddOnMetadata = function() return "0.7" end
GetCoinTextureString = function(c) return tostring(c) .. "c" end
LoadAddOn = function() return true end
ITEM_QUALITY_COLORS = {}
for i = 0, 7 do ITEM_QUALITY_COLORS[i] = { r = 1, g = 1, b = 1, hex = "|cffffffff" } end
INVTYPE_HEAD = "Cabeza"
string.trim = function(value) return (value:gsub("^%s*(.-)%s*$", "%1")) end
SlashCmdList = {}
InterfaceOptions_AddCategory = function() end
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  table.insert(OUTPUT, table.concat(parts, "\t"))
end
ITEMS, EQUIPMENT, BAGS = {}, {}, {}
SimulateX_ItemStats, SimulateX_ItemTypes, SimulateX_ItemClasses = {}, {}, {}
OUTPUT = {}
function ConfigureItem(id, name, strength, minLevel, classMask)
  local link = "|cff0070dd|Hitem:" .. id .. ":0:0:0:0:0:0:0:80|h[" .. name .. "]|h|r"
  ITEMS[id] = { name = name, link = link, itemLevel = 100, minLevel = minLevel,
    subType = CLASSNAME == "Warrior" and "Plate" or "Cloth", equipLoc = "INVTYPE_HEAD" }
  SimulateX_ItemStats[id] = "4=" .. tostring(strength)
  if classMask then SimulateX_ItemClasses[id] = classMask end
end
setmetatable(_G, { __index = function(t, k)
  if type(k) == "string" and (k:match("^Get") or k:match("^Unit")) then return function() return 0 end end
end })
''')
    g = lua.globals()
    g.CLASSNAME = class_name
    g.PLAYERLEVEL = 80
    g.SimulateX_DB = lua.table()

    wrong_class_mask = 128 if class_name == 'Warrior' else 1
    g.ConfigureItem(GEAR_ID, 'Equipped helm', 10, 1, None)
    g.ConfigureItem(BEST_ID, 'Best helm', 30, 1, None)
    g.ConfigureItem(NEXT_ID, 'Runner-up helm', 25, 1, None)
    g.ConfigureItem(WORSE_ID, 'Worse helm', 5, 1, None)
    g.ConfigureItem(UNUSABLE_ID, 'Wrong-class helm', 100, 1, wrong_class_mask)
    g.ConfigureItem(NOISE_ID, 'Noise helm', 10.1, 1, None)
    g.ConfigureItem(TOO_HIGH_ID, 'Future helm', 100, 81, None)
    g.ConfigureItem(THIRD_ID, 'Third helm', 20, 1, None)
    g.ConfigureItem(FOURTH_ID, 'Fourth helm', 18, 1, None)
    g.EQUIPMENT['HeadSlot'] = g.ITEMS[GEAR_ID]['link']

    class_data = lua.table()
    class_data['fixture'] = lua.table_from({
        'spec': 'fixture_spec',
        'specLabel': 'Prueba',
        'talentTree': 1,
        'avgItemLevel': 100,
        'weightsKind': 'preset',
        'role': 'dps',
        'weights': lua.table_from({'ITEM_MOD_STRENGTH_SHORT': 1}),
    })
    g[f'SimulateX_Data_{class_name}'] = class_data

    def load(path):
        code = (ROOT / path).read_text(encoding='utf-8')
        code = code.replace('local ADDON_NAME = ...', 'local ADDON_NAME = "SimulateX"')
        lua.execute(code)

    load('SimulateX.lua')
    g.BAG_ALERT_TIMER = g.FRAMES[2]
    load('SimulateXOptions.lua')
    g.SimulateXOptionsPanel['refresh']()

    for bag in range(5):
        g.BAGS[bag] = lua.table()
    for index, item_id in enumerate(bag_ids):
        bag = index % 5
        slot = index // 5 + 1
        g.BAGS[bag][slot] = item_id

    return lua, g


def outputs(g):
    values = g.OUTPUT
    return [values[i] for i in range(1, len(values) + 1)]


def reset_output(g):
    for i in range(len(g.OUTPUT), 0, -1):
        g.OUTPUT[i] = None


def invoke_bags(g):
    g.SlashCmdList['SIMULATEX']('bolsas')
    return outputs(g)


def entering_world(g):
    frame = g.SimulateXFrame
    frame['_script_OnEvent'](frame, 'PLAYER_ENTERING_WORLD')


def advance_alert(g):
    timer = g.BAG_ALERT_TIMER
    update = g.rawget(timer, '_script_OnUpdate')
    if not update:
        raise AssertionError('No se programó el aviso de inicio')
    update(timer, 4.9)
    if outputs(g):
        raise AssertionError('El aviso salió antes de cinco segundos')
    update(timer, 0.1)


def check_class(class_name):
    _, g = create_runtime(class_name, [BEST_ID, NEXT_ID, THIRD_ID, FOURTH_ID, WORSE_ID, UNUSABLE_ID, NOISE_ID, TOO_HIGH_ID])
    option = g[f'SimulateXOptionsBagAlertCheck']
    if not option['GetChecked'](option):
        raise AssertionError(f'{class_name}: el aviso debe estar activado por defecto')

    lines = invoke_bags(g)
    expected_ids = [BEST_ID, NEXT_ID, THIRD_ID]
    if len(lines) != 4 or any(f'item:{item_id}:' not in lines[index + 1] for index, item_id in enumerate(expected_ids)):
        raise AssertionError(f'{class_name}: se esperaban las tres mejores mejoras, en orden: {lines}')
    if f'item:{FOURTH_ID}:' in '\n'.join(lines):
        raise AssertionError(f'{class_name}: se superó el máximo de tres objetos por hueco: {lines}')
    if not lines[0].startswith('SimulateX: 3 mejora(s) en tus bolsas'):
        raise AssertionError(f'{class_name}: falta el resumen del comando: {lines[0]}')
    if '+28.6%' not in lines[1] or 'Cabeza' not in lines[1] or '+21.4%' not in lines[2] or '+14.3%' not in lines[3]:
        raise AssertionError(f'{class_name}: faltan porcentaje o hueco: {lines}')

    reset_output(g)
    entering_world(g)
    entering_world(g)
    advance_alert(g)
    if len(outputs(g)) != 1 or not outputs(g)[0].startswith(
        'SimulateX: tienes 3 objeto(s) en las bolsas que mejoran tu equipo (/simulatex bolsas).'
    ):
        raise AssertionError(f'{class_name}: el aviso de inicio no salió una sola vez: {outputs(g)}')
    entering_world(g)
    if len(outputs(g)) != 1:
        raise AssertionError(f'{class_name}: se repitió el aviso durante la sesión')

    empty_bags = [WORSE_ID, UNUSABLE_ID, NOISE_ID, TOO_HIGH_ID]
    _, empty = create_runtime(class_name, empty_bags)
    no_upgrades = invoke_bags(empty)
    if no_upgrades != ['SimulateX: no hay mejoras en tus bolsas.']:
        raise AssertionError(f'{class_name}: mensaje incorrecto sin mejoras: {no_upgrades}')
    reset_output(empty)
    entering_world(empty)
    advance_alert(empty)
    entering_world(empty)
    if outputs(empty):
        raise AssertionError(f'{class_name}: hubo aviso de inicio sin mejoras')

    _, disabled = create_runtime(class_name, [BEST_ID, NEXT_ID])
    disabled_option = disabled['SimulateXOptionsBagAlertCheck']
    disabled_option['SetChecked'](disabled_option, False)
    disabled_option['_script_OnClick'](disabled_option)
    if not disabled.SimulateX_DB['bagAlertDisabled']:
        raise AssertionError(f'{class_name}: no se guardó la opción desactivada')
    entering_world(disabled)
    advance_alert(disabled)
    if outputs(disabled):
        raise AssertionError(f'{class_name}: salió el aviso con la opción desactivada')

    print(f'OK {class_name}: lista ordenada, filtros, mensaje vacío, aviso único y opción')


for name in CLASSES:
    if name not in ('Warrior', 'Mage'):
        raise SystemExit(f'Clase no admitida por esta prueba: {name}')
    check_class(name)
