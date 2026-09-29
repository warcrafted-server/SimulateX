'''Prueba de la pestaña Mejoras fuera del juego: carga el addon en lupa con la
API de WoW simulada (personaje sin equipo, UnitStat = 60, nada en caché) y
lista las mejoras por hueco. Uso: probar_mejoras_lupa.py <Clase> <nivel> <Alliance|Horde> [herreria]
Requiere: pip install lupa.'''

import pathlib, sys, time
from lupa import LuaRuntime

ROOT = str(pathlib.Path(__file__).resolve().parent.parent / 'Addon') + '/'
CLASS = sys.argv[1] if len(sys.argv) > 1 else 'Druid'
LEVEL = int(sys.argv[2]) if len(sys.argv) > 2 else 80
FACTION = sys.argv[3] if len(sys.argv) > 3 else 'Alliance'

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
      if k == "Show" then rawset(self, "_shown", true) return end
      if k == "Hide" then rawset(self, "_shown", false) return end
      if k == "SetText" then rawset(self, "_text", (...)) return end
      if k == "GetName" then return "Mock" end
      if k:match("^Create") or k == "GetParent" then return newMock() end
      return nil
    end
    rawset(t, k, f)
    return f
  end,
}
_G.newMock = newMock
CreateFrame = function() return newMock() end
UIParent = newMock(); GameTooltip = newMock()
UISpecialFrames = {}
hooksecurefunc = function() end
UnitClass = function() return CLASSNAME, string.upper(CLASSNAME) end
UnitLevel = function() return PLAYERLEVEL end
UnitFactionGroup = function() return FACTIONNAME end
UnitAura = function() return nil end
UnitStat = function() return 60, 60, 0, 0 end
GetSpellInfo = function(id) return "Prof" .. id end
-- Herrería 300 si PROFESION = "herreria"
GetNumSkillLines = function() return PROFESION and 1 or 0 end
GetSkillLineInfo = function() return "Prof2018", false, false, 300 end
GetTalentTabInfo = function(i) return nil, nil, (i == 2 and 51 or 10) end
GetItemInfo = function() return nil end
GetItemIcon = function(id) return "icon" .. tostring(id) end
GetItemCount = function() return 0 end
GetInventorySlotInfo = function(name) return name end
GetInventoryItemLink = function() return nil end
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
g.CLASSNAME, g.PLAYERLEVEL, g.FACTIONNAME = CLASS, LEVEL, FACTION
g.SimulateX_DB = lua.table()
g.PROFESION = (sys.argv[4] == 'herreria') if len(sys.argv) > 4 else None

def load(path):
    code = open(ROOT + path, encoding='utf-8').read()
    code = code.replace('local ADDON_NAME = ...', 'local ADDON_NAME = "SimulateX"')
    if path.endswith('Mejoras.lua'):
        code = code.replace('local results  --', 'results = nil --').replace('local page, statusText,', 'local page; statusText = nil; local')
        code += '\nSLOT_GROUPS_DEBUG = {} for i, g in ipairs(SLOT_GROUPS) do SLOT_GROUPS_DEBUG[i] = g[1] end OriginTextDebug = OriginText'
    lua.execute(code)

for f in ['SimulateX/Data/SimulateX_Levels.lua', 'SimulateX/Data/SimulateX_ItemTypes.lua',
          'SimulateX/Data/SimulateX_ItemStats.lua', f'SimulateX_{CLASS}/Data/SimulateX_Data_{CLASS}.lua',
          'SimulateX_Origenes/Data/SimulateX_Origenes.lua',
          'SimulateX/SimulateX.lua', 'SimulateX/UI/Mejoras.lua']:
    load(f)
g.SimulateX_DB = lua.table()

parent = lua.eval('newMock()')
content = g.SimulateX_BuildUpgradesPage(parent)
t = time.time()
content.refresh()
step = parent['_script_OnUpdate']
frames = 0
MAXF = 10**9
rg = lua.eval('rawget')
while rg(parent, '_script_OnUpdate') and frames < MAXF:
    t0 = time.time()
    parent['_script_OnUpdate'](parent, 0.016)
    frames += 1
if rg(parent, '_script_OnUpdate'): sys.exit(0)
print(f'{CLASS} {LEVEL} {FACTION}: {frames} frames, {time.time()-t:.2f}s')
res = g.results
names = g.SimulateX_OrigenesNombres.objetos
print('status:', rg(g.statusText, '_text'))
for gi in range(1, 16):
    grp = res[gi]
    if not grp: continue
    print('--', g.SLOT_GROUPS_DEBUG[gi])
    for i in range(1, len(grp) + 1):
        e = grp[i]
        ev = e.evaluation
        o = g.OriginTextDebug(e.origins[1]) if len(e.origins) else 'sin origen'
        print(f'   {e.id} {names[e.id]} {ev.percent:+.1f}% exact={ev.isExact} | {o}')
