'''Comprueba el recuerdo de recetas de Mejoras con la API de WoW simulada.'''

import pathlib
from lupa import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent / 'Addon'


def create_runtime():
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
      if k == "RegisterEvent" then
        local event = ...; local events = rawget(self, "_events") or {}; events[event] = true
        rawset(self, "_events", events); return
      end
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
UIParent = newMock(); GameTooltip = newMock(); UISpecialFrames = {}
SlashCmdList = {}
InterfaceOptions_AddCategory = function() end
InterfaceOptionsFrame_OpenToCategory = function() end
UnitName = function() return "Recetario" end
GetRealmName = function() return "Reino de prueba" end
UnitClass = function() return "Guerrero", "WARRIOR" end
GetNumSkillLines = function() return #SKILL_LINES end
GetSkillLineInfo = function(i)
  local line = SKILL_LINES[i]
  if line then return line.name, false, false, line.rank end
end
GetSpellInfo = function(id) return PROFESSION_NAMES[id] or ("Hechizo " .. tostring(id)) end
IsTradeSkillLinked = function() return false end
GetTradeSkillLine = function() return TRADE_LINE, 450, 450 end
GetNumTradeSkills = function() return #TRADE_ROWS end
GetTradeSkillInfo = function(i)
  local row = TRADE_ROWS[i]
  if row then return row.name, row.type end
end
GetTradeSkillRecipeLink = function(i) return TRADE_ROWS[i] and TRADE_ROWS[i].recipeLink end
GetTradeSkillItemLink = function(i) return TRADE_ROWS[i] and TRADE_ROWS[i].itemLink end
GetCraftDisplaySkillLine = function() return CRAFT_LINE end
GetNumCrafts = function() return #CRAFT_ROWS end
GetCraftInfo = function(i)
  local row = CRAFT_ROWS[i]
  if row then return row.name, nil, row.type end
end
GetCraftRecipeLink = function(i) return CRAFT_ROWS[i] and CRAFT_ROWS[i].recipeLink end
GetItemIcon = function(id) return "icon" .. tostring(id) end
GetItemInfo = function(item)
  local id = type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  local data = id and ITEMS[id]
  if data then return data.name, "item:" .. id .. ":0:0:0:0:0:0:0", data.quality or 2 end
end
GetItemCount = function() return 0 end
SimulateX_API = { FormatPercent = function() return "+5.0 %" end }
ITEM_QUALITY_COLORS = { [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" } }
SKILL_LINES, PROFESSION_NAMES, TRADE_ROWS, CRAFT_ROWS, ITEMS = {}, {}, {}, {}, {}
TRADE_LINE, CRAFT_LINE = nil, nil
MARK_DIRTY_COUNT = 0
SimulateX_Mejoras_MarkDirty = function() MARK_DIRTY_COUNT = MARK_DIRTY_COUNT + 1 end

function makeRow()
  local function textObject()
    return { SetText = function(self, value) self.value = value end,
      SetTextColor = function(self, ...) end, SetTexture = function(self, ...) end }
  end
  return { icon = textObject(), name = textObject(), percent = textObject(), origin = textObject() }
end
function findEventFrame(event)
  for _, frame in ipairs(FRAMES) do
    if frame._events and frame._events[event] then return frame end
  end
end
function setRows(rows)
  TRADE_ROWS = rows
end
''')

    def load(path):
        code = (ROOT / path).read_text(encoding='utf-8')
        if path.endswith('Mejoras.lua'):
            code += '\nMejorasTest = { ParseOrigin = ParseOrigin, FillItemRow = FillItemRow }'
        lua.execute(code)

    load('SimulateX/UI/Mejoras.lua')
    load('SimulateX/SimulateXOptions.lua')
    g = lua.globals()
    g.SimulateX_DB = lua.table()
    g.SimulateX_OrigenesProfesiones = lua.table_from({164: 1001, 171: 1002, 333: 1003})
    g.PROFESSION_NAMES = lua.table_from({1001: 'Herrería', 1002: 'Alquimia', 1003: 'Encantamiento'})
    g.SKILL_LINES = lua.table_from([
        lua.table_from({'name': 'Herrería', 'rank': 450}),
        lua.table_from({'name': 'Alquimia', 'rank': 450}),
        lua.table_from({'name': 'Encantamiento', 'rank': 450}),
    ])
    g.SimulateX_Origenes = lua.table_from({
        2001: '80,1,4,0,0|p164:75:t',
        2002: '80,1,4,0,0|p502:164:80:0',
        2003: '80,1,4,0,0|p164:90:2599',
        3001: '80,1,4,0,0|p171:100:t',
    })
    g.SimulateX_OrigenesNombres = lua.table_from({'objetos': lua.table_from({2599: 'Receta desconocida'})})
    g.ITEMS = lua.table_from({
        2001: lua.table_from({'name': 'Objeto conocido 1', 'quality': 4}),
        2002: lua.table_from({'name': 'Objeto conocido 2', 'quality': 4}),
        2003: lua.table_from({'name': 'Objeto no conocido', 'quality': 4}),
        3001: lua.table_from({'name': 'Objeto de alquimia', 'quality': 4}),
    })
    g.SimulateXOptionsPanel['refresh']()
    return lua, g


def row_origin(lua, g, item_id):
    row = g.makeRow()
    source = g.SimulateX_Origenes[item_id].split('|')[1]
    origin = g.MejorasTest['ParseOrigin'](source)
    # Construir la fila mediante Lua para mantener las tablas con metatabla.
    g.MejorasTest['FillItemRow'](row, lua.table_from({
        'id': item_id,
        'origins': lua.table_from([origin]),
        'evaluation': lua.table_from({'percent': 5}),
    }), 80)
    return row['origin']['value']


def check():
    lua, g = create_runtime()
    # Simula TRADE_SKILL_SHOW: dos recetas aprendidas y una cabecera.
    g.TRADE_LINE = 'Herrería'
    g.setRows(lua.table_from([
        lua.table_from({'name': 'Receta uno', 'type': 'optimal', 'recipeLink': '|Henchant:501|h',
                        'itemLink': 'item:2001:0:0:0:0:0:0:0'}),
        lua.table_from({'name': 'Receta dos', 'type': 'trivial', 'recipeLink': '|Hspell:502|h',
                        'itemLink': 'item:2002:0:0:0:0:0:0:0'}),
        lua.table_from({'name': 'Armaduras', 'type': 'header', 'recipeLink': '|Hspell:999|h',
                        'itemLink': 'item:9999:0:0:0:0:0:0:0'}),
    ]))
    event_frame = g.findEventFrame('TRADE_SKILL_SHOW')
    event_frame['_script_OnEvent'](event_frame, 'TRADE_SKILL_SHOW')
    character = g.SimulateX_DB['knownRecipes']['Recetario-Reino de prueba']
    if not character[164][501] or not character[164][502] or character[164][999]:
        raise AssertionError('El escaneo no guardó solo las recetas y omitió la cabecera')
    if row_origin(lua, g, 2001) != '|cff00ff00Ya sabes fabricarlo|r':
        raise AssertionError('La fila no marcó la primera receta conocida en verde')
    if row_origin(lua, g, 2002) != '|cff00ff00Ya sabes fabricarlo|r':
        raise AssertionError('La fila no marcó la segunda receta conocida en verde')
    unknown = row_origin(lua, g, 2003)
    if 'Ya sabes fabricarlo' in unknown or 'receta: Receta desconocida' not in unknown:
        raise AssertionError(f'La receta no conocida cambió el texto anterior: {unknown}')

    # Una actualización inicial sin filas no debe borrar lo ya recordado.
    g.setRows(lua.table_from([]))
    event_frame['_script_OnEvent'](event_frame, 'TRADE_SKILL_UPDATE')
    character = g.SimulateX_DB['knownRecipes']['Recetario-Reino de prueba']
    if not character[164][501] or not character[164][502]:
        raise AssertionError('Un escaneo vacío borró las recetas guardadas')

    # La lista completa recibida después del evento vacío sí reemplaza los datos.
    g.setRows(lua.table_from([
        lua.table_from({'name': 'Receta uno', 'type': 'optimal', 'recipeLink': '|Henchant:501|h'}),
        lua.table_from({'name': 'Receta dos', 'type': 'trivial', 'recipeLink': '|Hspell:502|h'}),
        lua.table_from({'name': 'Receta tres', 'type': 'optimal', 'recipeLink': '|Hspell:503|h'}),
        lua.table_from({'name': 'Armaduras', 'type': 'header', 'recipeLink': '|Hspell:999|h'}),
    ]))
    event_frame['_script_OnEvent'](event_frame, 'TRADE_SKILL_UPDATE')
    character = g.SimulateX_DB['knownRecipes']['Recetario-Reino de prueba']
    if not character[164][501] or not character[164][502] or not character[164][503]:
        raise AssertionError('El escaneo completo posterior al vacío no actualizó las recetas')

    # El escaneo de otra profesión conserva la primera.
    g.TRADE_LINE = 'Alquimia'
    g.setRows(lua.table_from([
        lua.table_from({'name': 'Poción', 'type': 'easy', 'recipeLink': '|Hspell:601|h',
                        'itemLink': 'item:3001:0:0:0:0:0:0:0'}),
    ]))
    event_frame['_script_OnEvent'](event_frame, 'TRADE_SKILL_UPDATE')
    character = g.SimulateX_DB['knownRecipes']['Recetario-Reino de prueba']
    if not character[164][501] or not character[171][601]:
        raise AssertionError('El escaneo de la segunda profesión borró la primera')

    # Reabrir la primera profesión sin la receta desaprendida la elimina.
    g.TRADE_LINE = 'Herrería'
    g.setRows(lua.table_from([
        lua.table_from({'name': 'Receta dos', 'type': 'trivial', 'recipeLink': '|Hspell:502|h',
                        'itemLink': 'item:2002:0:0:0:0:0:0:0'}),
        lua.table_from({'name': 'Armaduras', 'type': 'header'}),
    ]))
    event_frame['_script_OnEvent'](event_frame, 'TRADE_SKILL_SHOW')
    character = g.SimulateX_DB['knownRecipes']['Recetario-Reino de prueba']
    if character[164][501] or row_origin(lua, g, 2001) == '|cff00ff00Ya sabes fabricarlo|r':
        raise AssertionError('La receta desaprendida siguió marcada tras reabrir la profesión')
    if not character[171][601]:
        raise AssertionError('Al reemplazar la profesión se perdió otra profesión guardada')

    # Encantamiento usa la API Craft y su tipo de receta está en el tercer resultado.
    g.CRAFT_LINE = 'Encantamiento'
    g.CRAFT_ROWS = lua.table_from([
        lua.table_from({'name': 'Encantar anillo', 'type': 'optimal', 'recipeLink': '|Henchant:701|h'}),
        lua.table_from({'name': 'Armas', 'type': 'header', 'recipeLink': '|Hspell:999|h'}),
    ])
    craft_frame = g.findEventFrame('CRAFT_SHOW')
    craft_frame['_script_OnEvent'](craft_frame, 'CRAFT_SHOW')
    character = g.SimulateX_DB['knownRecipes']['Recetario-Reino de prueba']
    if not character[333][701] or character[333][999]:
        raise AssertionError('La API Craft no guardó hechizos o no omitió la cabecera')

    # La casilla nueva está activa por defecto y, al desactivarla, no escanea ni marca.
    lua_disabled, disabled = create_runtime()
    option = disabled.SimulateXOptionsKnownRecipesCheck
    if not option['GetChecked'](option):
        raise AssertionError('La opción de recordar recetas no está activada por defecto')
    option['SetChecked'](option, False)
    option['_script_OnClick'](option)
    if not disabled.SimulateX_DB['knownRecipesDisabled']:
        raise AssertionError('La casilla no desactivó el recuerdo de recetas')
    disabled.TRADE_LINE = 'Herrería'
    disabled.setRows(lua_disabled.table_from([
        lua_disabled.table_from({'name': 'Receta uno', 'type': 'optimal', 'recipeLink': '|Henchant:501|h',
                                 'itemLink': 'item:2001:0:0:0:0:0:0:0'}),
    ]))
    before = disabled.MARK_DIRTY_COUNT
    disabled.findEventFrame('TRADE_SKILL_SHOW')['_script_OnEvent'](
        disabled.findEventFrame('TRADE_SKILL_SHOW'), 'TRADE_SKILL_SHOW')
    if disabled.SimulateX_DB['knownRecipes'] or disabled.MARK_DIRTY_COUNT != before:
        raise AssertionError('La opción desactivada guardó recetas o marcó Mejoras como sucia')
    if row_origin(lua_disabled, disabled, 2001) == '|cff00ff00Ya sabes fabricarlo|r':
        raise AssertionError('La fila marcó una receta con la opción desactivada')

    print('OK recetas: escaneo, cabeceras, marcado, opción, varias profesiones y desaprendidas')


if __name__ == '__main__':
    check()
