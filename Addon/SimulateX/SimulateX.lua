local ADDON_NAME = ...

local SimulateX = CreateFrame("Frame", "SimulateXFrame")

SimulateX_ClassDataVars = {
    WARRIOR = "SimulateX_Data_Warrior",
    PALADIN = "SimulateX_Data_Paladin",
    HUNTER = "SimulateX_Data_Hunter",
    ROGUE = "SimulateX_Data_Rogue",
    PRIEST = "SimulateX_Data_Priest",
    DEATHKNIGHT = "SimulateX_Data_Deathknight",
    SHAMAN = "SimulateX_Data_Shaman",
    MAGE = "SimulateX_Data_Mage",
    WARLOCK = "SimulateX_Data_Warlock",
    DRUID = "SimulateX_Data_Druid",
}
local CLASS_DATA_VARS = SimulateX_ClassDataVars

local CLASS_RELIC_DATA_VARS = {
    PALADIN = "SimulateX_Reliquias_Paladin",
    DEATHKNIGHT = "SimulateX_Reliquias_Deathknight",
    SHAMAN = "SimulateX_Reliquias_Shaman",
    DRUID = "SimulateX_Reliquias_Druid",
}

local RELIC_TYPE_CLASSES = { [407] = "PALADIN", [408] = "DRUID", [409] = "SHAMAN", [410] = "DEATHKNIGHT" }

local function GetRelicValue(spec, itemId)
    if not itemId or SimulateX_DB.relicValuationDisabled then
        return nil
    end
    local dataVarName = CLASS_RELIC_DATA_VARS[select(2, UnitClass("player"))]
    local classValues = dataVarName and _G[dataVarName]
    local specValues = classValues and classValues[spec]
    return specValues and specValues[itemId]
end

-- v0.7: mismo patrón que SimulateX_ClassDataVars, para la pestaña Talentos
-- (Tools/generar_db_talentos.py). Una clase sin fichero consolidado
-- simplemente no tiene entrada aquí.
SimulateX_TalentDataVars = {
    WARRIOR = "SimulateX_Talentos_Warrior",
    PALADIN = "SimulateX_Talentos_Paladin",
    HUNTER = "SimulateX_Talentos_Hunter",
    ROGUE = "SimulateX_Talentos_Rogue",
    PRIEST = "SimulateX_Talentos_Priest",
    DEATHKNIGHT = "SimulateX_Talentos_Deathknight",
    SHAMAN = "SimulateX_Talentos_Shaman",
    MAGE = "SimulateX_Talentos_Mage",
    WARLOCK = "SimulateX_Talentos_Warlock",
    DRUID = "SimulateX_Talentos_Druid",
}

-- v0.7: estructura fija del árbol (Tools/generar_arbol_talentos.py), para
-- dibujar el árbol real en la pestaña Talentos.
SimulateX_ArbolTalentosVars = {
    WARRIOR = "SimulateX_ArbolTalentos_Warrior",
    PALADIN = "SimulateX_ArbolTalentos_Paladin",
    HUNTER = "SimulateX_ArbolTalentos_Hunter",
    ROGUE = "SimulateX_ArbolTalentos_Rogue",
    PRIEST = "SimulateX_ArbolTalentos_Priest",
    DEATHKNIGHT = "SimulateX_ArbolTalentos_Deathknight",
    SHAMAN = "SimulateX_ArbolTalentos_Shaman",
    MAGE = "SimulateX_ArbolTalentos_Mage",
    WARLOCK = "SimulateX_ArbolTalentos_Warlock",
    DRUID = "SimulateX_ArbolTalentos_Druid",
}

-- Nivel efectivo del jugador: el real, salvo que /simulatex nivel 80 lo haya
-- forzado para esta sesión (solo para probar la lógica de 80 sin tener un
-- personaje de ese nivel; nunca se guarda entre sesiones).
local forcedLevelOverride = nil
local function GetEffectivePlayerLevel()
    return forcedLevelOverride or UnitLevel("player")
end

-- classFileName ("WARRIOR", ...) -> nombre de clase tal como lo usa
-- item_template.AllowableClass / SPEC_TO_GAME_CLASS de Tools/simular_builds.py.
local CLASS_FILE_TO_GAME_CLASS = {
    WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", DEATHKNIGHT = "Deathknight", SHAMAN = "Shaman", MAGE = "Mage",
    WARLOCK = "Warlock", DRUID = "Druid",
}

-- Árbol de talentos dominante del jugador (0/1/2), o nil si no se puede
-- determinar. Es la señal para saber cuál de las sub-specs mostradas es la
-- "activa" (se resalta distinto de las demás en el tooltip).
local function GetActiveTalentTree()
    local bestTree, bestPoints = nil, -1
    for tabIndex = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(tabIndex)
        if pointsSpent and pointsSpent > bestPoints then
            bestTree, bestPoints = tabIndex - 1, pointsSpent
        end
    end
    return bestTree
end

-- Feral y Guardián comparten árbol: decide la forma (oso = tanque, felina =
-- dps). Icono como respaldo por si el cliente no da el id de hechizo.
local BEAR_FORM_SPELLS = { [5487] = true, [9634] = true }
local CAT_FORM_SPELL = 768

local function GetDruidFormRole()
    for i = 1, 40 do
        local name, _, icon, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
        if not name then
            return nil
        end
        local iconLower = icon and icon:lower() or ""
        if BEAR_FORM_SPELLS[spellId] or iconLower:find("bearform") then
            return "tank"
        end
        if spellId == CAT_FORM_SPELL or iconLower:find("catform") then
            return "dps"
        end
    end
    return nil
end

-- Rol que cuenta como "tu spec" si varias specs comparten el árbol activo.
-- Druida: la última forma usada (en humanoide no hay pista). Sacerdote
-- disciplina: Sanación antes que Castigo.
local SHARED_TREE_ROLE = { PRIEST = "healer" }

local function GetSharedTreeRole(classFileName)
    if classFileName == "DRUID" then
        return SimulateX_DB.feralRole or "dps"
    end
    return SHARED_TREE_ROLE[classFileName] or "dps"
end

--[[----------------------------------------------------------------------
    USABILIDAD: se decide con datos de item_template (Data/SimulateX_ItemTypes.lua)
    y GetItemInfo, nunca construyendo un tooltip: hacerlo mientras el cliente
    muestra otro le quita el rojo de "no usable" al tooltip que ve el jugador.
    El requisito de nivel mínimo se trata aparte (dato sí, flecha no), no
    cuenta como "no usable". No cubre armas que la clase puede usar pero aún
    no ha entrenado.
------------------------------------------------------------------------]]

-- Qué tipos puede equiparse cada clase (códigos de SimulateX_ItemTypes:
-- clase × 100 + subclase de item_template). El valor es el nivel mínimo: la
-- malla (cazador, chamán) y las placas (guerrero, paladín) se aprenden a 40.
local ANY_CLASS_WEAPONS = { [214] = 1, [220] = 1 }  -- armas varias, cañas de pescar
local CLASS_PROFICIENCIES = {
    WARRIOR = { [401] = 1, [402] = 1, [403] = 1, [404] = 40, [406] = 1,
        [200] = 1, [201] = 1, [202] = 1, [203] = 1, [204] = 1, [205] = 1, [206] = 1, [207] = 1,
        [208] = 1, [210] = 1, [213] = 1, [215] = 1, [216] = 1, [218] = 1 },
    PALADIN = { [401] = 1, [402] = 1, [403] = 1, [404] = 40, [406] = 1, [407] = 1,
        [200] = 1, [201] = 1, [204] = 1, [205] = 1, [206] = 1, [207] = 1, [208] = 1 },
    HUNTER = { [401] = 1, [402] = 1, [403] = 40,
        [200] = 1, [201] = 1, [202] = 1, [203] = 1, [206] = 1, [207] = 1, [208] = 1, [210] = 1,
        [213] = 1, [215] = 1, [216] = 1, [218] = 1 },
    ROGUE = { [401] = 1, [402] = 1,
        [200] = 1, [202] = 1, [203] = 1, [204] = 1, [207] = 1, [213] = 1, [215] = 1, [216] = 1, [218] = 1 },
    PRIEST = { [401] = 1, [204] = 1, [210] = 1, [215] = 1, [219] = 1 },
    DEATHKNIGHT = { [401] = 1, [402] = 1, [403] = 1, [404] = 1, [410] = 1,
        [200] = 1, [201] = 1, [204] = 1, [205] = 1, [206] = 1, [207] = 1, [208] = 1 },
    SHAMAN = { [401] = 1, [402] = 1, [403] = 40, [406] = 1, [409] = 1,
        [200] = 1, [201] = 1, [204] = 1, [205] = 1, [210] = 1, [213] = 1, [215] = 1 },
    MAGE = { [401] = 1, [207] = 1, [210] = 1, [215] = 1, [219] = 1 },
    WARLOCK = { [401] = 1, [207] = 1, [210] = 1, [215] = 1, [219] = 1 },
    DRUID = { [401] = 1, [402] = 1, [408] = 1, [204] = 1, [205] = 1, [206] = 1, [210] = 1, [213] = 1, [215] = 1 },
}

-- Bit de cada clase en item_template.AllowableClass (2^(id de clase − 1)).
local CLASS_MASK_BITS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local function GetItemIdFromLink(itemLink)
    return tonumber(itemLink:match("item:(%d+)"))
end

-- item_template.InventoryType -> equipLoc de GetItemInfo
local INVTYPE_BY_ID = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [5] = "INVTYPE_CHEST",
    [6] = "INVTYPE_WAIST", [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [9] = "INVTYPE_WRIST",
    [10] = "INVTYPE_HAND", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_TRINKET", [13] = "INVTYPE_WEAPON",
    [14] = "INVTYPE_SHIELD", [15] = "INVTYPE_RANGED", [16] = "INVTYPE_CLOAK", [17] = "INVTYPE_2HWEAPON",
    [20] = "INVTYPE_ROBE", [21] = "INVTYPE_WEAPONMAINHAND", [22] = "INVTYPE_WEAPONOFFHAND",
    [23] = "INVTYPE_HOLDABLE", [25] = "INVTYPE_THROWN", [26] = "INVTYPE_RANGEDRIGHT", [28] = "INVTYPE_RELIC",
}

-- Nivel requerido y equipLoc de un objeto: del cliente si lo tiene en caché,
-- si no de SimulateX_Origenes (la lista de la compra evalúa objetos que el
-- jugador nunca ha visto).
local function GetItemBasics(itemLink)
    local _, _, _, _, minLevel, _, _, _, equipLoc = GetItemInfo(itemLink)
    if equipLoc then
        return minLevel, equipLoc
    end
    local itemId = GetItemIdFromLink(itemLink)
    local data = itemId and SimulateX_Origenes and SimulateX_Origenes[itemId]
    if data then
        local req, inv = data:match("^(%d+),(%d+),")
        return tonumber(req), INVTYPE_BY_ID[tonumber(inv)]
    end
end

-- nil si el objeto no está en la tabla de tipos (anillos, capas, ...).
local function IsProficient(itemLink)
    local itemId = GetItemIdFromLink(itemLink)
    local typeCode = itemId and SimulateX_ItemTypes and SimulateX_ItemTypes[itemId]
    if not typeCode then
        return nil
    end
    if ANY_CLASS_WEAPONS[typeCode] then
        return true
    end
    local proficiencies = CLASS_PROFICIENCIES[select(2, UnitClass("player"))]
    local minLevel = proficiencies and proficiencies[typeCode]
    return minLevel ~= nil and UnitLevel("player") >= minLevel
end

-- Línea "Clases:" del tooltip: false si el objeto está restringido a otras clases.
local function IsAllowedClass(itemLink)
    local itemId = GetItemIdFromLink(itemLink)
    local mask = itemId and SimulateX_ItemClasses and SimulateX_ItemClasses[itemId]
    if not mask then
        return true
    end
    local bit = CLASS_MASK_BITS[select(2, UnitClass("player"))]
    return bit ~= nil and mask % (bit * 2) >= bit
end

local function IsItemUsable(itemLink, equipLoc)
    if not equipLoc then
        _, equipLoc = GetItemBasics(itemLink)
    end
    if equipLoc == "INVTYPE_RELIC" then
        local itemId = GetItemIdFromLink(itemLink)
        local typeCode = itemId and SimulateX_ItemTypes and SimulateX_ItemTypes[itemId]
        if RELIC_TYPE_CLASSES[typeCode] ~= select(2, UnitClass("player")) then
            return false
        end
    end
    return IsProficient(itemLink) ~= false and IsAllowedClass(itemLink)
end

-- true si la clase puede llevarlo pero aún no tiene el nivel: el dato se
-- muestra (aparecerá al subir de nivel), la flecha no.
local function IsBlockedByLevelOnly(itemLink)
    local minLevel = GetItemBasics(itemLink)
    return IsItemUsable(itemLink) and minLevel ~= nil and minLevel > UnitLevel("player")
end

--[[----------------------------------------------------------------------
    PUNTUACIÓN: EP en tiempo real (decisión de diseño 1) con las
    estadísticas de Data/SimulateX_ItemStats.lua (item_template y DBC del
    servidor), incluidos sufijos aleatorios y reliquias. No se usa
    GetItemStats: con el addon activo el cliente deja de pintar en rojo lo
    que no se puede usar.

    Escalado por nivel (paso 6 del plan): w(L) = w80 × índicePor1%(80) /
    índicePor1%(L) para los combat ratings; agilidad/intelecto se reescalan
    aparte porque su valor incluye el componente de crítico "de stat", que
    escala distinto del crítico "de rating" (ver critComponent, paso 5).
------------------------------------------------------------------------]]

-- Tipo de estadística de item_template -> clave ITEM_MOD_* (las mismas que
-- daba GetItemStats, que son las de los pesos de SimulateX_Data_<Clase>.lua).
local STAT_TYPE_KEYS = {
    [0] = "MANA", [1] = "HEALTH", [3] = "AGILITY", [4] = "STRENGTH", [5] = "INTELLECT",
    [6] = "SPIRIT", [7] = "STAMINA", [12] = "DEFENSE_SKILL_RATING", [13] = "DODGE_RATING",
    [14] = "PARRY_RATING", [15] = "BLOCK_RATING", [16] = "HIT_MELEE_RATING",
    [17] = "HIT_RANGED_RATING", [18] = "HIT_SPELL_RATING", [19] = "CRIT_MELEE_RATING",
    [20] = "CRIT_RANGED_RATING", [21] = "CRIT_SPELL_RATING", [28] = "HASTE_MELEE_RATING",
    [29] = "HASTE_RANGED_RATING", [30] = "HASTE_SPELL_RATING", [31] = "HIT_RATING",
    [32] = "CRIT_RATING", [35] = "RESILIENCE_RATING", [36] = "HASTE_RATING",
    [37] = "EXPERTISE_RATING", [38] = "ATTACK_POWER", [39] = "RANGED_ATTACK_POWER",
    [40] = "FERAL_ATTACK_POWER", [41] = "SPELL_HEALING_DONE", [42] = "SPELL_DAMAGE_DONE",
    [43] = "MANA_REGENERATION", [44] = "ARMOR_PENETRATION_RATING", [45] = "SPELL_POWER",
    [46] = "HEALTH_REGEN", [47] = "SPELL_PENETRATION", [48] = "BLOCK_VALUE",
}
local SOCKET_KEYS = { m = "EMPTY_SOCKET_META", r = "EMPTY_SOCKET_RED", y = "EMPTY_SOCKET_YELLOW", u = "EMPTY_SOCKET_BLUE" }

local function AddStat(stats, statKey, value)
    local key
    if statKey == "a" then
        key = "RESISTANCE0_NAME"
    elseif statKey == "b" then
        key = "ITEM_MOD_BLOCK_VALUE_SHORT"
    elseif statKey == "d" then
        key = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
    elseif SOCKET_KEYS[statKey] then
        key = SOCKET_KEYS[statKey]
    else
        local statType = tonumber(statKey)
        key = "ITEM_MOD_" .. (STAT_TYPE_KEYS[statType] or ("STAT" .. statKey)) .. "_SHORT"
    end
    stats[key] = (stats[key] or 0) + value
end

local function ForEachPair(data, callback)
    for key, value in data:gmatch("(%w+)=([%d%.%-]+)") do
        callback(key, tonumber(value))
    end
end

-- flag de un solo bit (el 3.3.5a no trae operadores de bits en Lua)
local function HasFlag(mask, flag)
    return mask % (flag * 2) >= flag
end

local function PickByFlag(mask, choices)
    for _, choice in ipairs(choices) do
        if HasFlag(mask, choice[1]) then
            return choice[2]
        end
    end
    return 0
end

-- Reliquias: estadísticas, armadura, DPS y poder con hechizos según el nivel
-- del jugador (Player::_ApplyItemBonuses del core).
local function AddScalingStats(stats, distId, mask)
    local dist = SimulateX_ScalingDist and SimulateX_ScalingDist[distId]
    if not dist then
        return
    end
    local ssv = SimulateX_ScalingValues[math.min(UnitLevel("player"), dist.maxLevel)]
    if not ssv then
        return
    end
    local multiplier = PickByFlag(mask, { { 1, ssv.ssd[1] }, { 2, ssv.ssd[2] }, { 4, ssv.ssd[3] },
        { 8, ssv.ssd2 }, { 16, ssv.ssd[4] }, { 262144, ssv.ssd3 } })
    for _, stat in ipairs(dist.stats) do
        AddStat(stats, tostring(stat[1]), math.floor(multiplier * stat[2] / 10000))
    end
    local armor = PickByFlag(mask, { { 32, ssv.armor[1] }, { 64, ssv.armor[2] }, { 128, ssv.armor[3] },
        { 256, ssv.armor[4] }, { 524288, ssv.armor2[1] }, { 1048576, ssv.armor2[2] },
        { 2097152, ssv.armor2[3] }, { 4194304, ssv.armor2[4] }, { 8388608, ssv.armor2[5] } })
    if armor > 0 then
        AddStat(stats, "a", armor)
    end
    local dps = PickByFlag(mask, { { 512, ssv.dps[1] }, { 1024, ssv.dps[2] }, { 2048, ssv.dps[3] },
        { 4096, ssv.dps[4] }, { 8192, ssv.dps[5] }, { 16384, ssv.dps[6] } })
    if dps > 0 then
        AddStat(stats, "d", dps)
    end
    if HasFlag(mask, 32768) then
        AddStat(stats, "45", ssv.spellPower)
    end
end

-- link -> estadísticas. Las reliquias no se guardan: dependen del nivel.
local itemStatsCache = {}

-- Link: item:id:encantamiento:gema1:gema2:gema3:gema4:propiedad:factor:nivel.
-- propiedad > 0 = ItemRandomProperties, < 0 = ItemRandomSuffix con el
-- factor del link (o el de item_template si el link no lo trae).
local function GetItemStatsFromData(itemLink)
    local cached = itemStatsCache[itemLink]
    if cached then
        return cached
    end

    local stats = {}
    local itemId = tonumber(itemLink:match("item:(%-?%d+)"))
    local data = itemId and SimulateX_ItemStats and SimulateX_ItemStats[itemId]
    if data then
        local fields = {}
        ForEachPair(data, function(key, value) fields[key] = value end)
        -- con escalado el core ignora las estadísticas, armadura y daño base
        local scales = fields.x and fields.v and fields.v > 0
        for key, value in pairs(fields) do
            local replacedByScaling = scales and (tonumber(key) or key == "a" or key == "d")
            if key ~= "f" and key ~= "x" and key ~= "v" and key ~= "s" and key ~= "t" and not replacedByScaling then
                AddStat(stats, key, value)
            end
        end
        if scales then
            AddScalingStats(stats, fields.x, fields.v)
        end

        local propertyId, linkFactor = itemLink:match("item:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:%-?%d+:(%-?%d+):(%-?%d+)")
        propertyId, linkFactor = tonumber(propertyId), tonumber(linkFactor)
        -- links de inspeccionar: el cliente manda el int16 como uint16
        if propertyId and propertyId > 32767 and propertyId <= 65535 then
            propertyId = propertyId - 65536
        end
        if propertyId and propertyId > 0 and SimulateX_RandomProps[propertyId] then
            ForEachPair(SimulateX_RandomProps[propertyId], function(key, value) AddStat(stats, key, value) end)
        elseif propertyId and propertyId < 0 and SimulateX_RandomSuffixes[-propertyId] then
            local factor = (linkFactor and linkFactor > 0) and linkFactor or fields.f or 0
            ForEachPair(SimulateX_RandomSuffixes[-propertyId], function(key, pct)
                AddStat(stats, key, math.floor(pct * factor / 10000))
            end)
        end
    end

    if not (data and data:find("x=", 1, true)) then
        itemStatsCache[itemLink] = stats
    end
    return stats
end

-- Estadísticas de la bonificación de ranura (item_template.socketBonus), o
-- nil. Aparte de GetItemStatsFromData: solo cuentan con los colores cumplidos.
local socketBonusCache = {}
local function GetSocketBonusStats(itemLink)
    local itemId = tonumber(itemLink:match("item:(%-?%d+)"))
    if not itemId then
        return nil
    end
    local cached = socketBonusCache[itemId]
    if cached ~= nil then
        return cached or nil
    end
    local data = SimulateX_ItemStats and SimulateX_ItemStats[itemId]
    local enchantId = data and tonumber(data:match("s=(%d+)"))
    local bonus = enchantId and SimulateX_SocketBonus and SimulateX_SocketBonus[enchantId]
    local stats = false
    if bonus then
        stats = {}
        ForEachPair(bonus, function(key, value) AddStat(stats, key, value) end)
    end
    socketBonusCache[itemId] = stats
    return stats or nil
end

-- ITEM_MOD_* que corresponden 1:1 a un peso de la build (weights de
-- SimulateX_Data_<Clase>.lua): se multiplica directo. Crítico/golpe/
-- celeridad NO están aquí porque su peso en la build ya es la suma combinada
-- (Tools/mapeo_stats.py::combine_rating_weight): el objeto trae un solo
-- rating de crítico, sin distinguir melee/hechizo.
local SCALABLE_BY_LEVEL = {
    ITEM_MOD_CRIT_RATING_SHORT = "critMelee",       -- índice: mismo para melee/spell (ver paso 4)
    ITEM_MOD_HIT_RATING_SHORT = "hitMelee",
    ITEM_MOD_HASTE_RATING_SHORT = "hasteMelee",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "armorPenetration",
}

-- Pesos que NO escalan por nivel via combat rating (estadísticas primarias:
-- su valor en puntos no cambia con el nivel, solo el crítico/golpe/celeridad/
-- penetración lo hacen porque son ratings con "índice por 1%" variable).
local DIRECT_WEIGHT_KEYS = {
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_SPELL_POWER_SHORT",
    "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT",
    "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT",
    "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_BLOCK_RATING_SHORT",
    "ITEM_MOD_BLOCK_VALUE_SHORT", "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT",
    "ITEM_MOD_RESILIENCE_RATING_SHORT", "RESISTANCE0_NAME",
}

-- Devuelve los pesos de una build ajustados al nivel L: los combat ratings
-- (crítico/golpe/celeridad/penetración) se reescalan por el índice por 1% de
-- SimulateX_Levels.lua; agilidad/intelecto se reescalan además restando el
-- componente de crítico "de stat" a 80 y sumando el de nivel L (fórmula del
-- plan: w_agi(L) = w_agi80 − critPct_melee/agiPor1%(80) + critPct_melee/agiPor1%(L)).
local function GetWeightsAtLevel(build, level, classGameName)
    if level >= 80 then
        return build.weights
    end

    local levels = SimulateX_Levels
    if not levels then
        return build.weights
    end

    local idx = level  -- levels[1] = nivel 1, ..., levels[80] = nivel 80
    local idx80 = 80
    local scaled = {}

    for key, weight in pairs(build.weights) do
        local ratingKey = SCALABLE_BY_LEVEL[key]
        if ratingKey then
            local ref80 = levels.combatRatings[ratingKey][idx80]
            local refL = levels.combatRatings[ratingKey][idx]
            scaled[key] = (ref80 and refL and refL ~= 0) and (weight * ref80 / refL) or weight
        else
            scaled[key] = weight
        end
    end

    local critComponent = build.critComponent or { melee = 0, spell = 0 }
    local agiPor1Pct = levels.agiPor1PctCrit[classGameName]
    local intPor1Pct = levels.intPor1PctCrit[classGameName]

    if scaled.ITEM_MOD_AGILITY_SHORT and agiPor1Pct and agiPor1Pct[idx80] and agiPor1Pct[idx] then
        scaled.ITEM_MOD_AGILITY_SHORT = scaled.ITEM_MOD_AGILITY_SHORT
            - critComponent.melee / agiPor1Pct[idx80] + critComponent.melee / agiPor1Pct[idx]
    end
    if scaled.ITEM_MOD_INTELLECT_SHORT and intPor1Pct and intPor1Pct[idx80] and intPor1Pct[idx] then
        scaled.ITEM_MOD_INTELLECT_SHORT = scaled.ITEM_MOD_INTELLECT_SHORT
            - critComponent.spell / intPor1Pct[idx80] + critComponent.spell / intPor1Pct[idx]
    end

    return scaled
end

-- Hueco de equipo -> mano cuyo peso de DPS de arma se aplica (build.weaponDps).
local SLOT_TO_HAND = { MainHandSlot = "mainHand", SecondaryHandSlot = "offHand", RangedSlot = "ranged" }

local RANGED_EQUIP_LOCS = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

local function GetDefaultHand(itemLink)
    local _, equipLoc = GetItemBasics(itemLink)
    if RANGED_EQUIP_LOCS[equipLoc] then
        return "ranged"
    end
    if equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return "offHand"
    end
    return "mainHand"
end

-- Feral: el DPS del arma solo aporta PA feral, que el core calcula como
-- int(dps × 14) − 767 y nunca negativo, así que por debajo de ~54.8 DPS no
-- vale nada. El peso de wowsims es lineal (no recorta), de ahí el ajuste.
local function ScoreWeaponDps(dps, build, hand)
    local weight = build.weaponDps and build.weaponDps[hand]
    if not weight or not dps then
        return 0
    end
    local feral = build.feralWeaponAp
    if feral then
        local feralAp = math.max(0, math.floor(dps * feral.perDps) - feral.base)
        return weight / feral.perDps * feralAp
    end
    return weight * dps
end

--[[----------------------------------------------------------------------
    GEMAS IDEALES (v0.9, nivel 80): cada hueco de color vale la mejor gema
    de ese color y la bonificación de ranura, o la mejor gema sin mirar el
    color y sin bonificación, lo que valga más (la bonificación solo se
    activa con todos los colores cumplidos). build.gems viene de
    Tools/generar_db_addon.py (gemas de wowsims, sin únicas ni de joyero).
    El meta sigue valiendo la meta del preset (metaSocketValue).
------------------------------------------------------------------------]]

local SOCKET_COLOR = { EMPTY_SOCKET_RED = "red", EMPTY_SOCKET_YELLOW = "yellow", EMPTY_SOCKET_BLUE = "blue" }

local function IdealGemsActive(build)
    return build.gems and not SimulateX_DB.idealGemsDisabled and GetEffectivePlayerLevel() >= 80
end

local function SocketBonusValue(itemLink, weights)
    local bonus = GetSocketBonusStats(itemLink)
    local value = 0
    for key, amount in pairs(bonus or {}) do
        value = value + (weights[key] or 0) * amount
    end
    return value
end

-- Mejor gema por color con los pesos reales (definida tras los topes)
local GemValues

local function IdealColoredSocketsValue(itemLink, stats, weights, build)
    local gems = GemValues(build, weights)
    local count, matched = 0, 0
    for key, color in pairs(SOCKET_COLOR) do
        local n = stats[key] or 0
        count = count + n
        matched = matched + n * (gems[color] or 0)
    end
    if count == 0 then
        return 0
    end
    return math.max(matched + SocketBonusValue(itemLink, weights), count * gems.any)
end

-- Lo que supuso wowsims al simular el objeto (dato exacto): la gema
-- principal del preset en cada hueco, con bonificación si su color encaja
local function SimColoredSocketsValue(itemLink, stats, weights, build)
    local count, allMatch = 0, true
    for key, color in pairs(SOCKET_COLOR) do
        local n = stats[key] or 0
        count = count + n
        if n > 0 and not build.gems.mainMatches[color] then
            allMatch = false
        end
    end
    if count == 0 then
        return 0
    end
    return count * (build.socketValue or 0) + (allMatch and SocketBonusValue(itemLink, weights) or 0)
end

-- Igual que ScoreItem, pero además de la puntuación total devuelve cuánto
-- aporta cada estadística (clave = misma clave ITEM_MOD_*/"weaponDps"/
-- "socket", para el desglose del comparador; ver ComparadorBreakdown).
-- hand: mano donde iría el arma; sin ella se deduce del tipo de objeto.
local function ScoreItemBreakdown(itemLink, weights, build, hand)
    local stats = GetItemStatsFromData(itemLink)
    local contributions = {}
    local score = 0

    local weaponContribution = ScoreWeaponDps(stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, build, hand or GetDefaultHand(itemLink))
    if weaponContribution ~= 0 then
        contributions.weaponDps = weaponContribution
        score = score + weaponContribution
    end

    for _, key in ipairs(DIRECT_WEIGHT_KEYS) do
        local weight = weights[key]
        if weight and stats[key] then
            local contribution = weight * stats[key]
            contributions[key] = (contributions[key] or 0) + contribution
            score = score + contribution
        end
    end
    for itemModKey in pairs(SCALABLE_BY_LEVEL) do
        local weight = weights[itemModKey]
        if weight and stats[itemModKey] then
            local contribution = weight * stats[itemModKey]
            contributions[itemModKey] = (contributions[itemModKey] or 0) + contribution
            score = score + contribution
        end
    end

    local socketsValue = (stats.EMPTY_SOCKET_META or 0) * (build.metaSocketValue or 0)
    if IdealGemsActive(build) then
        socketsValue = socketsValue + IdealColoredSocketsValue(itemLink, stats, weights, build)
    else
        for key in pairs(SOCKET_COLOR) do
            socketsValue = socketsValue + (stats[key] or 0) * (build.socketValue or 0)
        end
    end
    if socketsValue ~= 0 then
        contributions.sockets = socketsValue
        score = score + socketsValue
    end

    return score, contributions
end

-- Puntuación = Σ peso × stat + DPS de arma + huecos (gemas ideales y
-- bonificación de ranura a nivel 80; si no, la gema del preset por hueco).
local function ScoreItem(itemLink, weights, build, hand)
    local score = ScoreItemBreakdown(itemLink, weights, build, hand)
    return score
end

--[[----------------------------------------------------------------------
    SELECCIÓN DE BUILD POR SPEC (decisión 9: clave = spec wowsims + árbol,
    no solo árbol — smite_priest y la variante disciplina de healing_priest
    comparten árbol sin esta clave). A nivel 80, la build de avgItemLevel más
    cercana por debajo de la media equipada + 10 (2M cuenta doble, sin
    camisa/tabardo); si ninguna cumple eso, la de fase más baja. Por debajo
    de 80, siempre la de fase más baja (no hay comparación de ilvl posible,
    todo se resuelve con EP).
------------------------------------------------------------------------]]

-- Slots de equipo estándar (sin camisa/tabardo, igual que wowsims: ver
-- Tools/mapeo_slots.py). MainHandSlot cuenta doble si el arma es 2M.
local EQUIPPED_SLOTS = {
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot",
    "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
    "Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot",
}

local function GetEquippedAvgItemLevel()
    local levels = {}
    for _, slotName in ipairs(EQUIPPED_SLOTS) do
        local slotId = GetInventorySlotInfo(slotName)
        local link = GetInventoryItemLink("player", slotId)
        if link then
            local _, _, _, itemLevel, _, _, _, _, equipLoc = GetItemInfo(link)
            if itemLevel then
                table.insert(levels, itemLevel)
                if slotName == "MainHandSlot" and equipLoc == "INVTYPE_2HWEAPON" then
                    table.insert(levels, itemLevel)
                end
            end
        end
    end
    if #levels == 0 then
        return nil
    end
    local sum = 0
    for _, lvl in ipairs(levels) do sum = sum + lvl end
    return sum / #levels
end

-- Agrupa las builds de la clase por (spec wowsims, árbol de talentos) y
-- elige, de cada grupo, según el criterio de arriba.
local function GetBestBuildPerSpec(classData)
    local bySpecTree = {}
    for buildId, build in pairs(classData) do
        local key = build.spec .. "#" .. tostring(build.talentTree)
        local group = bySpecTree[key]
        if not group then
            group = {}
            bySpecTree[key] = group
        end
        table.insert(group, { buildId = buildId, build = build })
    end

    local playerLevel = GetEffectivePlayerLevel()
    local equippedAvg = playerLevel >= 80 and GetEquippedAvgItemLevel()

    local bestBySpec = {}
    for key, candidates in pairs(bySpecTree) do
        table.sort(candidates, function(a, b) return (a.build.avgItemLevel or 0) < (b.build.avgItemLevel or 0) end)

        local chosen
        if playerLevel >= 80 and equippedAvg then
            local threshold = equippedAvg + 10
            for i = #candidates, 1, -1 do
                if (candidates[i].build.avgItemLevel or 0) <= threshold then
                    chosen = candidates[i]
                    break
                end
            end
        end
        chosen = chosen or candidates[1]  -- ninguna por debajo del umbral (o nivel bajo): la de fase/ilvl más baja
        bestBySpec[key] = chosen
    end

    if SimulateX_DB.forcedBuild and classData[SimulateX_DB.forcedBuild] then
        local forced = classData[SimulateX_DB.forcedBuild]
        local key = forced.spec .. "#" .. tostring(forced.talentTree)
        bestBySpec[key] = { buildId = SimulateX_DB.forcedBuild, build = forced }
    end

    return bestBySpec
end

--[[----------------------------------------------------------------------
    COMPARACIÓN VS EQUIPADO (arregla E2/E6): nunca contra un BiS de
    referencia, siempre contra lo que el jugador lleva puesto. Anillos/
    abalorios contra el peor de los dos; 2M contra MP+MI; 1M con 2M equipada
    contra la 2M; doble empuñadura: la mejor de MP/MI. A nivel 80, si tanto
    el candidato como el equipado están en items (dato exacto simulado), se
    usa delta(candidato) − delta(equipado) en vez de la puntuación EP.
------------------------------------------------------------------------]]

local INVTYPE_TO_SLOTS = {
    INVTYPE_HEAD = { "HeadSlot" }, INVTYPE_NECK = { "NeckSlot" }, INVTYPE_SHOULDER = { "ShoulderSlot" },
    INVTYPE_CLOAK = { "BackSlot" }, INVTYPE_CHEST = { "ChestSlot" }, INVTYPE_ROBE = { "ChestSlot" },
    INVTYPE_WRIST = { "WristSlot" }, INVTYPE_HAND = { "HandsSlot" }, INVTYPE_WAIST = { "WaistSlot" },
    INVTYPE_LEGS = { "LegsSlot" }, INVTYPE_FEET = { "FeetSlot" },
    INVTYPE_FINGER = { "Finger0Slot", "Finger1Slot" },
    INVTYPE_TRINKET = { "Trinket0Slot", "Trinket1Slot" },
    INVTYPE_WEAPON = { "MainHandSlot", "SecondaryHandSlot" },
    INVTYPE_2HWEAPON = { "MainHandSlot" },
    INVTYPE_WEAPONMAINHAND = { "MainHandSlot" },
    INVTYPE_WEAPONOFFHAND = { "SecondaryHandSlot" },
    INVTYPE_SHIELD = { "SecondaryHandSlot" }, INVTYPE_HOLDABLE = { "SecondaryHandSlot" },
    INVTYPE_RANGED = { "RangedSlot" }, INVTYPE_RANGEDRIGHT = { "RangedSlot" }, INVTYPE_THROWN = { "RangedSlot" },
    INVTYPE_RELIC = { "RangedSlot" }, -- comparte hueco con distancia, pero no es un arma a distancia
}

local OFFHAND_ONLY_EQUIP_LOCS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }

local function GetEquippedItemId(slotName)
    local slotId = GetInventorySlotInfo(slotName)
    local link = GetInventoryItemLink("player", slotId)
    return link, link and tonumber(link:match("item:(%d+)"))
end

-- Delta exacto (items[id]) si existe para ese id en la build, si no nil. Para
-- doble empuñadura, whichHand = "oh" pide dpsOH: solo existe para metricName
-- "dps" (specs melee dps, únicas con doble empuñadura); para cualquier otra
-- métrica no hay equivalente de mano izquierda, así que no hay dato exacto.
local function GetExactDelta(build, itemId, metricName, whichHand)
    local data = build.items and build.items[itemId]
    if not data then
        return nil
    end
    if metricName == "surv" then
        return data.dtps and -data.dtps  -- menos daño recibido = mejor
    end
    if whichHand == "oh" then
        return metricName == "dps" and data.dpsOH or nil
    end
    return data[metricName]
end

--[[----------------------------------------------------------------------
    TOPES (v0.9): golpe, pericia y penetración de armadura dejan de valer al
    llegar al tope. Los datos exactos y los pesos de wowsims se midieron con
    el equipo del preset (que suele ir ya topado: ahí wowsims da peso 0 al
    golpe), así que se corrigen con lo que le falta al jugador. build.caps
    viene de Tools/modelo_caps.py; solo a nivel 80 y para la métrica del rol.
------------------------------------------------------------------------]]

local CAP_ITEM_MOD = {
    meleeHit = "ITEM_MOD_HIT_RATING_SHORT", spellHit = "ITEM_MOD_HIT_RATING_SHORT",
    expertise = "ITEM_MOD_EXPERTISE_RATING_SHORT", arp = "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
}
local CAPPED_ITEM_MODS = {
    "ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_EXPERTISE_RATING_SHORT", "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT",
}

-- Hueco de equipo -> posición en el equipo de wowsims (proto.ItemSlot)
local SLOT_SIM_INDEX = {
    HeadSlot = 0, NeckSlot = 1, ShoulderSlot = 2, BackSlot = 3, ChestSlot = 4, WristSlot = 5,
    HandsSlot = 6, WaistSlot = 7, LegsSlot = 8, FeetSlot = 9, Finger0Slot = 10, Finger1Slot = 11,
    Trinket0Slot = 12, Trinket1Slot = 13, MainHandSlot = 14, SecondaryHandSlot = 15, RangedSlot = 16,
}

-- {a, b} sin huecos: con un nil delante, ipairs se pararía ahí
local function LinkList(...)
    local list = {}
    for i = 1, select("#", ...) do
        local link = select(i, ...)
        if link then
            table.insert(list, link)
        end
    end
    return list
end

local function SimSlotsFor(equipLoc)
    local slots = {}
    for _, slotName in ipairs(INVTYPE_TO_SLOTS[equipLoc] or {}) do
        table.insert(slots, SLOT_SIM_INDEX[slotName])
    end
    return slots
end

local function CapsActive(build, metricName)
    return build.caps ~= nil and metricName ~= "surv" and not SimulateX_DB.capsDisabled
        and GetEffectivePlayerLevel() >= 80
end

-- Rating que el jugador ya tiene (equipo y auras de rating, lo que da la
-- hoja de personaje); talentos y buffs los suma NonGearRating
local function PlayerRating(stat, build)
    if stat == "meleeHit" then
        return GetCombatRating(build.spec == "hunter" and (CR_HIT_RANGED or 7) or (CR_HIT_MELEE or 6))
    elseif stat == "spellHit" then
        return GetCombatRating(CR_HIT_SPELL or 8)
    elseif stat == "expertise" then
        return GetCombatRating(CR_EXPERTISE or 24)
    end
    return GetCombatRating(CR_ARMOR_PENETRATION or 25)
end

local function PlayerCap(stat, block)
    if stat == "spellHit" and block.debuff and SimulateX_DB.spellHitDebuffIgnored then
        return block.cap + block.debuff
    end
    return block.cap
end

-- Golpe de talentos: el del jugador, no el del preset (Data/SimulateX_GolpeTalentos.lua,
-- Tools/generar_golpe_talentos.py). Caché hasta el próximo cambio de talentos.
local playerTalentHit
local buildIds = setmetatable({}, { __mode = "k" })

local function PlayerTalentHit(stat)
    if not playerTalentHit then
        playerTalentHit = {}
        local talents = SimulateX_GolpeTalentos and SimulateX_GolpeTalentos.talentos[select(2, UnitClass("player"))]
        for _, talent in ipairs(talents or {}) do
            for index = 1, GetNumTalents(talent.tab) do
                local _, _, tier, column, rank = GetTalentInfo(talent.tab, index)
                if tier == talent.tier and column == talent.col then
                    if rank and rank > 0 then
                        playerTalentHit[talent.stat] = (playerTalentHit[talent.stat] or 0) + talent.rating[rank]
                    end
                    break
                end
            end
        end
    end
    return playerTalentHit[stat] or 0
end

local function BuildId(build)
    if buildIds[build] == nil then
        local classData = _G[CLASS_DATA_VARS[select(2, UnitClass("player"))] or ""]
        for id, candidate in pairs(classData or {}) do
            buildIds[candidate] = id
        end
    end
    return buildIds[build]
end

-- Golpe que no es de equipo: lo del preset que no son talentos (buffs,
-- raciales) más los talentos del jugador. wowsims no mete en nonGear los
-- talentos de golpe por escuela (Enfoque de las Sombras...), de ahí el max.
local function NonGearRating(stat, block, build)
    local presets = SimulateX_GolpeTalentos and SimulateX_GolpeTalentos.presets
    local preset = presets and presets[BuildId(build)]
    if not preset then
        return block.nonGear
    end
    return math.max(0, block.nonGear - (preset[stat] or 0)) + PlayerTalentHit(stat)
end


-- Lo que hay que sumar a la puntuación (exacta o por pesos) de `link` para
-- que sus stats con tope valgan lo que le faltan al jugador. removed: lo que
-- el cambio se quita de encima; simSlots: huecos del preset donde wowsims lo
-- probó (anillos/abalorios: media de los dos, se quedó con el mejor).
local function CapAdjustment(build, link, isExact, removed, simSlots, onlyItemMod)
    if not link then
        return 0
    end
    local stats = GetItemStatsFromData(link)
    local adjust = 0
    for stat, block in pairs(build.caps) do
        local key = CAP_ITEM_MOD[stat]
        local amount = (onlyItemMod == nil or onlyItemMod == key) and stats[key] or 0
        if amount > 0 then
            local current = PlayerRating(stat, build) + NonGearRating(stat, block, build)
            for _, removedLink in ipairs(removed) do
                current = current - (GetItemStatsFromData(removedLink)[key] or 0)
            end
            local valued = block.weight * math.min(amount, math.max(0, PlayerCap(stat, block) - current))
            if isExact then
                local slotContribution = 0
                for _, simSlot in ipairs(simSlots or {}) do
                    slotContribution = slotContribution + (block.slots[simSlot] or 0) / #simSlots
                end
                local presetRoom = math.max(0, block.cap - (block.preset - slotContribution))
                adjust = adjust + valued - block.weight * math.min(amount, presetRoom)
            else
                adjust = adjust + valued - block.presetWeight * amount
            end
        end
    end
    return adjust
end

-- Gemas ideales (Data/SimulateX_Gemas.lua) valoradas con los pesos que se
-- pasan, salvo golpe/pericia/penetración: su peso real por debajo del tope si
-- al jugador le falta, 0 si ya lo tiene. build.gems (pesos del preset) queda
-- de respaldo. Caché de un segundo: Mejoras evalúa cientos de objetos seguidos.
local gemValuesCache = setmetatable({}, { __mode = "k" })

GemValues = function(build, weights)
    if not SimulateX_Gemas then
        return build.gems
    end
    local cached = gemValuesCache[build]
    if cached and cached.weights == weights and GetTime() - cached.time < 1 then
        return cached.values
    end

    local capWeights = {}
    if build.caps and not SimulateX_DB.capsDisabled and GetEffectivePlayerLevel() >= 80 then
        for stat, block in pairs(build.caps) do
            local room = PlayerCap(stat, block) - PlayerRating(stat, build) - NonGearRating(stat, block, build)
            local key = CAP_ITEM_MOD[stat]
            -- golpe cuerpo a cuerpo y de hechizo comparten clave (Mejora)
            capWeights[key] = (capWeights[key] or 0) + (room > 0 and block.weight or 0)
        end
    end

    local values = { red = 0, yellow = 0, blue = 0, any = 0, mainMatches = build.gems.mainMatches }
    local maskBits = { red = 1, yellow = 2, blue = 4 }
    for _, gem in ipairs(SimulateX_Gemas) do
        local value = 0
        for key, amount in pairs(gem.s) do
            value = value + (capWeights[key] or weights[key] or 0) * amount
        end
        for color, bit in pairs(maskBits) do
            if gem.m % (bit * 2) >= bit and value > values[color] then
                values[color] = value
            end
        end
        if value > values.any then
            values.any = value
        end
    end
    gemValuesCache[build] = { weights = weights, time = GetTime(), values = values }
    return values
end

-- Corrección total de un objeto: topes, y en datos exactos además las gemas
-- ideales frente a la gema del preset que usó wowsims (la puntuación por
-- pesos ya valora las gemas ideales en ScoreItemBreakdown).
local function Adjustment(build, metricName, link, isExact, removed, simSlots)
    if not link then
        return 0
    end
    local adjust = 0
    if CapsActive(build, metricName) then
        adjust = CapAdjustment(build, link, isExact, removed, simSlots)
    end
    if isExact and metricName ~= "surv" and IdealGemsActive(build) then
        local stats = GetItemStatsFromData(link)
        adjust = adjust + IdealColoredSocketsValue(link, stats, build.weights, build)
            - SimColoredSocketsValue(link, stats, build.weights, build)
    end
    return adjust
end

-- Puntúa candidato y equipado con la MISMA fuente de datos (decisión 5: una
-- comparación nunca mezcla exacto y EP): exacto para ambos solo si los dos
-- tienen entrada en items; si a cualquiera le falta, EP para ambos.
-- removed: lo que el jugador se quitaría (por defecto, el propio equipado).
local function ComparePair(candLink, candId, equippedLink, equippedId, build, weights, metricName, hand, simSlots, removed)
    local candExact = candId and GetExactDelta(build, candId, metricName)
    local equippedExact = equippedId and GetExactDelta(build, equippedId, metricName)
    local isExact = candExact ~= nil and equippedExact ~= nil

    local gain
    if isExact then
        gain = candExact - equippedExact
    else
        local candScore = candLink and ScoreItem(candLink, weights, build, hand) or 0
        local equippedScore = equippedLink and ScoreItem(equippedLink, weights, build, hand) or 0
        gain = candScore - equippedScore
    end

    removed = removed or LinkList(equippedLink)
    local adjustedGain = gain + Adjustment(build, metricName, candLink, isExact, removed, simSlots)
        - Adjustment(build, metricName, equippedLink, isExact, removed, simSlots)
    return adjustedGain, equippedLink == nil and #removed == 0
end

-- Puntuación de un solo objeto (slot vacío, o suma de dos slots ya
-- equipados): sin comparación, así que no aplica la regla de "no mezclar".
local function GetScore(itemLink, itemId, build, weights, metricName, hand)
    if itemId then
        local exact = GetExactDelta(build, itemId, metricName)
        if exact then
            return exact
        end
    end
    return ScoreItem(itemLink, weights, build, hand)
end

-- GetScore para un hueco vacío: el objeto entra sin quitar nada
local function GetScoreAdjusted(itemLink, itemId, build, weights, metricName, hand, simSlots)
    local score = GetScore(itemLink, itemId, build, weights, metricName, hand)
    local isExact = itemId ~= nil and GetExactDelta(build, itemId, metricName) ~= nil
    return score + Adjustment(build, metricName, itemLink, isExact, {}, simSlots)
end

-- Ganancia vs equipado (positiva = mejora). metricName es "dps", "hps",
-- "tps" o "dtps" según el rol de la build (paso 6: tanque usa "Amenaza" =
-- tps y "Supervivencia" = dtps, donde MENOR es mejor: el llamador invierte
-- el signo para esos casos, aquí siempre se devuelve candidato − equipado).
local function CompareAgainstEquipped(itemLink, itemId, equipLoc, build, weights, metricName)
    if equipLoc == "INVTYPE_RELIC" then
        local candidateValue = GetRelicValue(build.spec, itemId)
        if candidateValue == nil then
            return nil
        end
        local _, equippedId = GetEquippedItemId("RangedSlot")
        return candidateValue - (GetRelicValue(build.spec, equippedId) or 0)
    end

    local slots = INVTYPE_TO_SLOTS[equipLoc]
    if not slots then
        return nil  -- slot no comparable (camisa, tabardo, ...)
    end

    -- Candidato de una mano (1M): si el jugador lleva una 2M, sustituiría
    -- toda la mano, así que se compara contra la 2M completa, no como doble
    -- empuñadura. Si lleva 1M+MI (o MP vacía), es doble empuñadura: se
    -- compara en MP y en MI por separado (con el dato de esa mano concreta,
    -- dps o dpsOH), la mejor de las dos ganancias.
    if equipLoc == "INVTYPE_WEAPON" then
        local mhLink, mhId = GetEquippedItemId("MainHandSlot")
        local mhEquipLoc = mhLink and select(9, GetItemInfo(mhLink))

        if mhEquipLoc == "INVTYPE_2HWEAPON" then
            return ComparePair(itemLink, itemId, mhLink, mhId, build, weights, metricName, "mainHand", { 14 })
        end

        local ohLink, ohId = GetEquippedItemId("SecondaryHandSlot")
        local gainMh, emptyMh = ComparePair(itemLink, itemId, mhLink, mhId, build, weights, metricName, "mainHand", { 14 })

        -- Mano izquierda: si hay dato exacto de dpsOH para AMBOS lados se usa
        -- (decisión 5), si no EP (que no distingue de mano, mismo score).
        local candOhExact = itemId and GetExactDelta(build, itemId, metricName, "oh")
        local equippedOhExact = ohId and GetExactDelta(build, ohId, metricName, "oh")
        local gainOh
        local emptyOh = ohLink == nil
        if candOhExact and equippedOhExact then
            local removed = LinkList(ohLink)
            gainOh = candOhExact - equippedOhExact
                + Adjustment(build, metricName, itemLink, true, removed, { 15 })
                - Adjustment(build, metricName, ohLink, true, removed, { 15 })
        else
            gainOh, emptyOh = ComparePair(itemLink, itemId, ohLink, ohId, build, weights, metricName, "offHand", { 15 })
        end

        local selectedEmpty = emptyMh
        if gainOh > gainMh then
            selectedEmpty = emptyOh
        end
        return math.max(gainMh, gainOh), selectedEmpty
    end

    -- Mano izquierda con una 2M puesta: para llevarla hay que quitarse la 2M,
    -- así que se compara contra ella y no como hueco vacío.
    if OFFHAND_ONLY_EQUIP_LOCS[equipLoc] then
        local mhLink, mhId = GetEquippedItemId("MainHandSlot")
        if mhLink and select(9, GetItemInfo(mhLink)) == "INVTYPE_2HWEAPON" then
            local candExact = itemId and GetExactDelta(build, itemId, metricName)
            local mhExact = mhId and GetExactDelta(build, mhId, metricName)
            local isExact = candExact ~= nil and mhExact ~= nil
            local gain
            if isExact then
                gain = candExact - mhExact
            else
                gain = ScoreItem(itemLink, weights, build, "offHand") - ScoreItem(mhLink, weights, build, "mainHand")
            end
            local removed = LinkList(mhLink)
            return gain + Adjustment(build, metricName, itemLink, isExact, removed, { 15 })
                - Adjustment(build, metricName, mhLink, isExact, removed, { 14 }), false
        end
    end

    if #slots == 1 then
        local slotName = slots[1]
        local equippedLink, equippedId = GetEquippedItemId(slotName)

        if equipLoc == "INVTYPE_2HWEAPON" then
            -- 2M candidata: comparar contra MP + MI juntas (mismo criterio de
            -- fuente para las tres puntuaciones a la vez: si alguna de las
            -- tres no tiene dato exacto, las tres se puntúan en EP).
            local ohLink, ohId = GetEquippedItemId("SecondaryHandSlot")
            local candExact = itemId and GetExactDelta(build, itemId, metricName)
            local mhExact = equippedId and GetExactDelta(build, equippedId, metricName)
            local ohExact = ohId and GetExactDelta(build, ohId, metricName)

            local isExact = candExact ~= nil and (mhExact or not equippedLink) and (ohExact or not ohLink) and true or false
            local gain
            if isExact then
                gain = candExact - (mhExact or 0) - (ohExact or 0)
            else
                local candScore = ScoreItem(itemLink, weights, build, "mainHand")
                local equippedScore = (equippedLink and ScoreItem(equippedLink, weights, build, "mainHand") or 0)
                    + (ohLink and ScoreItem(ohLink, weights, build, "offHand") or 0)
                gain = candScore - equippedScore
            end
            local removed = LinkList(equippedLink, ohLink)
            return gain + Adjustment(build, metricName, itemLink, isExact, removed, { 14 })
                - Adjustment(build, metricName, equippedLink, isExact, removed, { 14 })
                - Adjustment(build, metricName, ohLink, isExact, removed, { 15 }),
                not equippedLink and not ohLink and #removed == 0
        end

        local hand = SLOT_TO_HAND[slotName]
        local simSlots = { SLOT_SIM_INDEX[slotName] }
        if not equippedLink then
            return GetScoreAdjusted(itemLink, itemId, build, weights, metricName, hand, simSlots), true  -- slot vacío: puntuación completa
        end
        return ComparePair(itemLink, itemId, equippedLink, equippedId, build, weights, metricName, hand, simSlots)
    end

    -- Anillos/abalorios: contra el peor de los dos equipados; con un hueco
    -- vacío iría ahí sin quitar nada, así que cuenta entero.
    local simSlots = SimSlotsFor(equipLoc)
    local worstLink, worstId, worstScore
    for _, slotName in ipairs(slots) do
        local equippedLink, equippedId = GetEquippedItemId(slotName)
        if not equippedLink then
            return GetScoreAdjusted(itemLink, itemId, build, weights, metricName, nil, simSlots), true
        end
        local equippedScore = GetScore(equippedLink, equippedId, build, weights, metricName)
        if not worstScore or equippedScore < worstScore then
            worstScore, worstLink, worstId = equippedScore, equippedLink, equippedId
        end
    end
    return ComparePair(itemLink, itemId, worstLink, worstId, build, weights, metricName, nil, simSlots)
end

--[[----------------------------------------------------------------------
    PORCENTAJE Y RUIDO: a 80 con weightsKind = "sim" el % es sobre base
    (dps/hps/tps de la build); en cualquier otro caso (preset, o nivel < 80)
    es sobre la puntuación EP del personaje entero con esos mismos pesos:
    equipo puesto + estadísticas base. |ganancia| < 0.3 % → "≈ igual".
------------------------------------------------------------------------]]

local NOISE_THRESHOLD_PCT = 0.3

local function GetEquippedTotalScore(weights, build)
    local total = 0
    for _, slotName in ipairs(EQUIPPED_SLOTS) do
        local link = select(1, GetEquippedItemId(slotName))
        if link then
            total = total + ScoreItem(link, weights, build, SLOT_TO_HAND[slotName])
        end
    end
    return total
end

-- Índice de UnitStat: 1 fuerza, 2 agilidad, 3 aguante, 4 intelecto, 5 espíritu.
local PRIMARY_STAT_KEYS = {
    "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
    "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT",
}

-- Primarias sin equipo ni buffs (la cifra entre paréntesis de la hoja de
-- personaje): el equipo ya lo cuenta GetEquippedTotalScore.
local function GetBaseStatsScore(weights)
    local total = 0
    for statIndex, key in ipairs(PRIMARY_STAT_KEYS) do
        local weight = weights[key]
        if weight then
            local stat, _, posBuff, negBuff = UnitStat("player", statIndex)
            total = total + weight * ((stat or 0) - (posBuff or 0) - (negBuff or 0))
        end
    end
    return total
end

-- Mismo denominador que usa ComputePercent, expuesto aparte para el
-- desglose del comparador (GetComparisonBreakdown necesita el número, no
-- solo el % ya dividido).
local function GetPercentDenominator(weightsKind, playerLevel, base80, weights, build)
    if weightsKind == "sim" and playerLevel >= 80 and base80 and base80 ~= 0 then
        return base80
    end
    return GetEquippedTotalScore(weights, build) + GetBaseStatsScore(weights)
end

-- Devuelve (percent, isNoise). base80 es build.base[metricName] (solo válido
-- si weightsKind == "sim" y el jugador está a nivel 80).
local function ComputePercent(gain, weightsKind, playerLevel, base80, weights, build)
    local denominator = GetPercentDenominator(weightsKind, playerLevel, base80, weights, build)

    if not denominator or denominator == 0 then
        return 0, true
    end

    local percent = gain / denominator * 100
    return percent, math.abs(percent) < NOISE_THRESHOLD_PCT
end

--[[----------------------------------------------------------------------
    ORQUESTACIÓN POR OBJETO: para cada build (spec activa + otras de la
    clase), calcula usabilidad, ganancia vs equipado, % y etiqueta, listas
    para el tooltip y para la flecha de mejora.
------------------------------------------------------------------------]]

-- Una sola métrica por rol: el tooltip da un % global por spec. Tanque:
-- amenaza, y si la build trae "survival" se promedia con la supervivencia
-- (EvaluateBuild).
local ROLE_METRIC = { dps = "dps", healer = "hps", tank = "tps" }

-- Vista de la build con los pesos de supervivencia (dtps con el signo
-- cambiado); lo demás (items, base, feralWeaponAp...) es el de la build.
local survivalBuilds = setmetatable({}, { __mode = "k" })

local function GetSurvivalBuild(build)
    local survival = survivalBuilds[build]
    if not survival then
        local data = build.survival
        survival = setmetatable({
            weights = data.weights,
            weaponDps = data.weaponDps,
            critComponent = data.critComponent,
            socketValue = data.socketValue,
            metaSocketValue = data.metaSocketValue,
            gems = false,  -- build.gems se calculó con los pesos de amenaza, no de supervivencia
        }, { __index = build })
        survivalBuilds[build] = survival
    end
    return survival
end

-- Nombre del objeto (u objetos) contra el que se comparó, para la línea
-- "vs. X" del tooltip. Usa el mismo criterio que CompareAgainstEquipped para
-- decidir "el peor de los dos" en anillos/abalorios (mismos pesos/build), así
-- que la etiqueta nunca puede nombrar un objeto distinto del que se usó.
local function GetComparisonLabel(equipLoc, build, weights, metricName)
    local slots = INVTYPE_TO_SLOTS[equipLoc]
    if not slots then
        return nil
    end

    if equipLoc == "INVTYPE_WEAPON" then
        local mhLink = select(1, GetEquippedItemId("MainHandSlot"))
        local mhEquipLoc = mhLink and select(9, GetItemInfo(mhLink))
        if mhEquipLoc == "INVTYPE_2HWEAPON" then
            return mhLink and GetItemInfo(mhLink)
        end
        local ohLink = select(1, GetEquippedItemId("SecondaryHandSlot"))
        if mhLink and ohLink then
            return (GetItemInfo(mhLink)) .. " / " .. (GetItemInfo(ohLink))
        end
        return mhLink and GetItemInfo(mhLink) or (ohLink and GetItemInfo(ohLink))
    end

    if OFFHAND_ONLY_EQUIP_LOCS[equipLoc] then
        local mhLink = select(1, GetEquippedItemId("MainHandSlot"))
        if mhLink and select(9, GetItemInfo(mhLink)) == "INVTYPE_2HWEAPON" then
            return GetItemInfo(mhLink)
        end
    end

    if equipLoc == "INVTYPE_2HWEAPON" then
        local mhLink = select(1, GetEquippedItemId("MainHandSlot"))
        local ohLink = select(1, GetEquippedItemId("SecondaryHandSlot"))
        if mhLink and ohLink then
            return (GetItemInfo(mhLink)) .. " + " .. (GetItemInfo(ohLink))
        end
        return mhLink and GetItemInfo(mhLink) or (ohLink and GetItemInfo(ohLink))
    end

    if #slots == 1 then
        local link = select(1, GetEquippedItemId(slots[1]))
        return link and GetItemInfo(link)
    end

    local worstLink, worstScore
    for _, slotName in ipairs(slots) do
        local link, id = GetEquippedItemId(slotName)
        if not link then
            return nil  -- hueco libre: no sustituye a nada
        end
        local score = GetScore(link, id, build, weights, metricName)
        if not worstScore or score < worstScore then
            worstScore, worstLink = score, link
        end
    end
    return worstLink and GetItemInfo(worstLink)
end

-- Una evaluación por build, o nil si no es usable o el slot no es comparable
-- (camisa, tabardo, munición...). gain > 0 = mejora.
local function EvaluateBuild(itemLink, itemId, equipLoc, buildId, build, playerLevel, classGameName)
    if not IsItemUsable(itemLink, equipLoc) then
        return nil
    end

    local metric = ROLE_METRIC[build.role] or "dps"
    local weights = GetWeightsAtLevel(build, playerLevel, classGameName)
    local gain, againstEmpty = CompareAgainstEquipped(itemLink, itemId, equipLoc, build, weights, metric)
    if gain == nil then
        return nil
    end

    local percent, isNoise
    if equipLoc == "INVTYPE_RELIC" then
        percent = gain
        isNoise = math.abs(percent) < NOISE_THRESHOLD_PCT
    else
        percent, isNoise = ComputePercent(gain, build.weightsKind, playerLevel,
            build.base and build.base[metric], weights, build)
    end

    -- tanque: media 1:1 de amenaza y supervivencia, como los pesos de tanque
    -- por defecto de wowsims
    if build.role == "tank" and build.survival then
        local survival = GetSurvivalBuild(build)
        local survivalWeights = GetWeightsAtLevel(survival, playerLevel, classGameName)
        local survivalGain = CompareAgainstEquipped(itemLink, itemId, equipLoc, survival, survivalWeights, "surv")
        if survivalGain then
            local survivalPercent = ComputePercent(survivalGain, build.weightsKind, playerLevel,
                build.base and build.base.dtps, survivalWeights, survival)
            percent = (percent + survivalPercent) / 2
            gain = percent
            isNoise = math.abs(percent) < NOISE_THRESHOLD_PCT
        end
    end

    return {
        buildId = buildId,
        spec = build.spec,
        specLabel = build.specLabel or build.spec,
        role = build.role,
        metric = metric,
        comparisonLabel = GetComparisonLabel(equipLoc, build, weights, metric),
        gain = gain,
        percent = percent,
        isNoise = isNoise,
        isExact = equipLoc == "INVTYPE_RELIC" or (build.weightsKind == "sim" and playerLevel >= 80),
        againstEmpty = equipLoc ~= "INVTYPE_RELIC" and not not againstEmpty,
        blockedByLevel = IsBlockedByLevelOnly(itemLink),
        talentTree = build.talentTree,
    }
end

-- Clave (spec#árbol) de la build que cuenta como "tu spec": la del árbol con
-- más puntos y, si ese árbol lo comparten varias specs, la del rol de
-- GetSharedTreeRole.
local function GetActiveSpecKey(bestBySpec, classFileName)
    local activeTree = GetActiveTalentTree()
    local candidates = {}
    for key, entry in pairs(bestBySpec) do
        if entry.build.talentTree == activeTree then
            table.insert(candidates, key)
        end
    end
    if #candidates <= 1 then
        return candidates[1]
    end

    table.sort(candidates)  -- pairs() no tiene orden fijo
    local wantedRole = GetSharedTreeRole(classFileName)
    for _, key in ipairs(candidates) do
        if bestBySpec[key].build.role == wantedRole then
            return key
        end
    end
    return candidates[1]
end

-- Evalúa el objeto contra todas las builds relevantes de la clase del
-- jugador (una línea por spec, decisión 9), la activa primero.
local function GetItemEvaluations(itemLink)
    local classFileName = select(2, UnitClass("player"))
    local gameClassName = CLASS_FILE_TO_GAME_CLASS[classFileName]
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData or not gameClassName then
        return nil
    end

    local itemId = tonumber(itemLink:match("item:(%d+)"))
    local _, equipLoc = GetItemBasics(itemLink)
    if not equipLoc or equipLoc == "" then
        return nil
    end

    local bestBySpec = GetBestBuildPerSpec(classData)
    local activeKey = GetActiveSpecKey(bestBySpec, classFileName)
    local playerLevel = GetEffectivePlayerLevel()

    -- Por etiqueta: Sanación tiene build de disciplina y de sagrado, pero en
    -- el tooltip es una sola línea (la del árbol activo si la hay).
    local byLabel = {}
    for key, entry in pairs(bestBySpec) do
        local specLabel = entry.build.specLabel or entry.build.spec
        local specEnabled = SimulateX_DB.disabledSpecs == nil or not SimulateX_DB.disabledSpecs[specLabel]
        if specEnabled then
            local evaluation = EvaluateBuild(itemLink, itemId, equipLoc, entry.buildId, entry.build, playerLevel, gameClassName)
            if evaluation then
                evaluation.isActive = (key == activeKey)
                local current = byLabel[specLabel]
                if not current or (evaluation.isActive and not current.isActive)
                    or (not current.isActive and evaluation.talentTree < current.talentTree) then
                    byLabel[specLabel] = evaluation
                end
            end
        end
    end

    local results = {}
    for _, evaluation in pairs(byLabel) do
        table.insert(results, evaluation)
    end

    table.sort(results, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        return a.specLabel < b.specLabel
    end)
    return results
end

-- Lista de la compra (v0.10): la build de la spec activa se elige una vez y
-- se evalúan contra ella miles de objetos, sin repetir GetBestBuildPerSpec.
local function GetActiveSpecContext()
    local classFileName = select(2, UnitClass("player"))
    local gameClassName = CLASS_FILE_TO_GAME_CLASS[classFileName]
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData or not gameClassName then
        return nil
    end
    local bestBySpec = GetBestBuildPerSpec(classData)
    local entry = bestBySpec[GetActiveSpecKey(bestBySpec, classFileName)]
    if not entry then
        return nil
    end
    return {
        buildId = entry.buildId,
        build = entry.build,
        specLabel = entry.build.specLabel or entry.build.spec,
        playerLevel = GetEffectivePlayerLevel(),
        gameClassName = gameClassName,
    }
end

local function EvaluateForContext(context, itemLink)
    local _, equipLoc = GetItemBasics(itemLink)
    if not equipLoc or equipLoc == "" then
        return nil
    end
    return EvaluateBuild(itemLink, GetItemIdFromLink(itemLink), equipLoc, context.buildId, context.build,
        context.playerLevel, context.gameClassName)
end

local function EvaluateStatDeltaForContext(context, stats)
    local build = context.build
    local metric = ROLE_METRIC[build.role] or "dps"
    local weights = GetWeightsAtLevel(build, context.playerLevel, context.gameClassName)
    local gain = 0
    -- CapAdjustment necesita un enlace de objeto; aquí se aplican los pesos directos a la tabla.
    for key, amount in pairs(stats) do
        gain = gain + (weights[key] or 0) * amount
    end
    local percent, isNoise = ComputePercent(gain, build.weightsKind, context.playerLevel,
        build.base and build.base[metric], weights, build)
    return { gain = gain, percent = percent, isNoise = isNoise }
end

--[[----------------------------------------------------------------------
    COMPARADOR (v0.6): A contra B (huecos ya validados como compatibles por
    el llamador, UI/Comparador.lua) o A contra lo equipado si B está vacío.
    Reutiliza el mismo motor que el tooltip: nunca dos cálculos distintos
    para la misma pregunta.
------------------------------------------------------------------------]]

-- Ganancia de A frente a B para una sola métrica, con las mismas reglas de
-- ComparePair (exacto solo si A y B tienen dato en build.items, si no EP
-- para los dos). A y B son del mismo equipLoc (validado por el llamador), así
-- que no hace falta la lógica de doble empuñadura/2M/peor-de-dos de
-- CompareAgainstEquipped: es una comparación directa de dos objetos.
-- Topes: A y B sustituirían a lo que el jugador lleva en ese hueco (si es
-- uno solo; en anillos/abalorios no hay "el" equipado y no se descuenta nada).
local function CompareDirect(linkA, idA, linkB, idB, equipLoc, build, weights, metricName, hand)
    local slots = INVTYPE_TO_SLOTS[equipLoc] or {}
    local removed = {}
    if #slots == 1 then
        removed = LinkList((GetEquippedItemId(slots[1])))
    end
    return ComparePair(linkA, idA, linkB, idB, build, weights, metricName, hand, SimSlotsFor(equipLoc), removed)
end

-- Ganancia de A según contra qué se compara: hueco vacío (A entero), B, o
-- lo equipado.
local function ComparisonGain(linkA, idA, linkB, idB, equipLoc, build, weights, metric, hand, againstEmpty)
    if againstEmpty then
        return GetScoreAdjusted(linkA, idA, build, weights, metric, hand, SimSlotsFor(equipLoc))
    end
    if linkB then
        return CompareDirect(linkA, idA, linkB, idB, equipLoc, build, weights, metric, hand)
    end
    return CompareAgainstEquipped(linkA, idA, equipLoc, build, weights, metric)
end

local function RelicComparisonGain(idA, idB, spec, againstEmpty)
    local candidateValue = GetRelicValue(spec, idA)
    if candidateValue == nil then
        return nil
    end
    local baselineValue = 0
    if not againstEmpty then
        if idB then
            baselineValue = GetRelicValue(spec, idB) or 0
        else
            local _, equippedId = GetEquippedItemId("RangedSlot")
            baselineValue = GetRelicValue(spec, equippedId) or 0
        end
    end
    return candidateValue - baselineValue
end

-- Evaluación de A frente a B para una build (misma forma que EvaluateBuild),
-- para el comparador. linkB nil = contra lo equipado; againstEmpty = contra
-- un hueco vacío.
local function EvaluateBuildComparison(linkA, idA, linkB, idB, equipLoc, buildId, build, playerLevel, classGameName, againstEmpty)
    if not IsItemUsable(linkA, equipLoc) then
        return nil
    end
    if linkB and not IsItemUsable(linkB) then
        return nil
    end

    if equipLoc == "INVTYPE_RELIC" then
        local gain = RelicComparisonGain(idA, idB, build.spec, againstEmpty)
        if gain == nil then
            return nil
        end
        return {
            buildId = buildId,
            spec = build.spec,
            specLabel = build.specLabel or build.spec,
            role = build.role,
            metric = ROLE_METRIC[build.role] or "dps",
            gain = gain,
            percent = gain,
            isNoise = math.abs(gain) < NOISE_THRESHOLD_PCT,
            isExact = true,
            againstEmpty = false,
            talentTree = build.talentTree,
        }
    end

    local metric = ROLE_METRIC[build.role] or "dps"
    local weights = GetWeightsAtLevel(build, playerLevel, classGameName)
    local hand = GetDefaultHand(linkA)

    local gain, comparedAgainstEmpty = ComparisonGain(linkA, idA, linkB, idB, equipLoc, build, weights, metric, hand, againstEmpty)
    if gain == nil then
        return nil
    end

    local percent, isNoise = ComputePercent(gain, build.weightsKind, playerLevel,
        build.base and build.base[metric], weights, build)

    if build.role == "tank" and build.survival then
        local survival = GetSurvivalBuild(build)
        local survivalWeights = GetWeightsAtLevel(survival, playerLevel, classGameName)
        local survivalGain = ComparisonGain(linkA, idA, linkB, idB, equipLoc, survival, survivalWeights, "surv", hand, againstEmpty)
        if survivalGain then
            local survivalPercent = ComputePercent(survivalGain, build.weightsKind, playerLevel,
                build.base and build.base.dtps, survivalWeights, survival)
            percent = (percent + survivalPercent) / 2
            gain = percent
            isNoise = math.abs(percent) < NOISE_THRESHOLD_PCT
        end
    end

    return {
        buildId = buildId,
        spec = build.spec,
        specLabel = build.specLabel or build.spec,
        role = build.role,
        metric = metric,
        comparisonLabel = not linkB and not againstEmpty and GetComparisonLabel(equipLoc, build, weights, metric) or nil,
        gain = gain,
        percent = percent,
        isNoise = isNoise,
        isExact = (build.weightsKind == "sim" and playerLevel >= 80),
        againstEmpty = equipLoc ~= "INVTYPE_RELIC" and not not (againstEmpty or (not linkB and comparedAgainstEmpty)),
        talentTree = build.talentTree,
    }
end

-- Una línea por spec, A contra B (o contra equipado si linkB es nil, o
-- contra un hueco vacío con againstEmpty). Misma selección de build
-- activa/etiquetas que GetItemEvaluations.
local function GetComparisonEvaluations(linkA, linkB, againstEmpty)
    local classFileName = select(2, UnitClass("player"))
    local gameClassName = CLASS_FILE_TO_GAME_CLASS[classFileName]
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData or not gameClassName then
        return nil
    end

    local idA = tonumber(linkA:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(linkA)
    if not equipLoc or equipLoc == "" then
        return nil
    end
    local idB
    if linkB then
        idB = tonumber(linkB:match("item:(%d+)"))
        local _, _, _, _, _, _, _, _, equipLocB = GetItemInfo(linkB)
        if not INVTYPE_TO_SLOTS[equipLoc] or equipLocB ~= equipLoc then
            return nil, "no van en el mismo hueco"
        end
    end

    local bestBySpec = GetBestBuildPerSpec(classData)
    local activeKey = GetActiveSpecKey(bestBySpec, classFileName)
    local playerLevel = GetEffectivePlayerLevel()

    local byLabel = {}
    for key, entry in pairs(bestBySpec) do
        local specLabel = entry.build.specLabel or entry.build.spec
        local specEnabled = SimulateX_DB.disabledSpecs == nil or not SimulateX_DB.disabledSpecs[specLabel]
        if specEnabled then
            local evaluation = EvaluateBuildComparison(linkA, idA, linkB, idB, equipLoc, entry.buildId, entry.build, playerLevel, gameClassName, againstEmpty)
            if evaluation then
                evaluation.isActive = (key == activeKey)
                local current = byLabel[specLabel]
                if not current or (evaluation.isActive and not current.isActive)
                    or (not current.isActive and evaluation.talentTree < current.talentTree) then
                    byLabel[specLabel] = evaluation
                end
            end
        end
    end

    local results = {}
    for _, evaluation in pairs(byLabel) do
        table.insert(results, evaluation)
    end
    table.sort(results, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        return a.specLabel < b.specLabel
    end)
    return results
end

-- Etiquetas legibles en castellano de cada clave del desglose (globales
-- traducidas del cliente para las de item, resto a mano).
local BREAKDOWN_LABELS = setmetatable({
    weaponDps = "DPS de arma", sockets = "Huecos de gema",
    ITEM_MOD_CRIT_RATING_SHORT = ITEM_MOD_CRIT_RATING_SHORT or "Crítico",
    ITEM_MOD_HIT_RATING_SHORT = ITEM_MOD_HIT_RATING_SHORT or "Puntería",
    ITEM_MOD_HASTE_RATING_SHORT = ITEM_MOD_HASTE_RATING_SHORT or "Celeridad",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT or "Penetración de armadura",
}, {
    __index = function(_, key)
        return _G[key] or key
    end,
})

-- Desglose de una spec: diferencia de estadísticas (A − B, o A − equipo si
-- linkB es nil) y cuánto aporta cada una al % de esa spec (mismo denominador
-- que ComputePercent para esa build), ordenado por |aporte| descendente.
-- buildId: clave de classData (ver GetComparisonEvaluations/evaluation.buildId).
local function GetComparisonBreakdown(linkA, linkB, buildId, againstEmpty)
    local classFileName = select(2, UnitClass("player"))
    local gameClassName = CLASS_FILE_TO_GAME_CLASS[classFileName]
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    local build = classData and classData[buildId]
    if not build then
        return nil
    end

    local _, equipLoc = GetItemBasics(linkA)
    if equipLoc == "INVTYPE_RELIC" then
        local idA = GetItemIdFromLink(linkA)
        local idB = linkB and GetItemIdFromLink(linkB)
        local gain = RelicComparisonGain(idA, idB, build.spec, againstEmpty)
        if gain == nil then
            return nil
        end
        return { { key = "relicEffect", label = "Efecto de reliquia simulada", diff = 0, percent = gain } }
    end
    local playerLevel = GetEffectivePlayerLevel()
    local weights = GetWeightsAtLevel(build, playerLevel, gameClassName)
    local hand = GetDefaultHand(linkA)
    local metric = ROLE_METRIC[build.role] or "dps"
    local denominator = GetPercentDenominator(build.weightsKind, playerLevel, build.base and build.base[metric], weights, build)

    local _, contribA = ScoreItemBreakdown(linkA, weights, build, hand)
    local contribB, compareLink
    if againstEmpty then
        contribB = {}
    elseif linkB then
        _, contribB = ScoreItemBreakdown(linkB, weights, build, hand)
        compareLink = linkB
    else
        -- objeto equipado en ese hueco (slot único; anillos/abalorios y armas
        -- con doble empuñadura no tienen un "el equipado" único, se omite el
        -- desglose por estadística para esos huecos y solo se ve el % total)
        local slots = INVTYPE_TO_SLOTS[equipLoc]
        if not slots or #slots ~= 1 or equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" then
            return nil
        end
        local equippedLink = select(1, GetEquippedItemId(slots[1]))
        if equippedLink then
            _, contribB = ScoreItemBreakdown(equippedLink, weights, build, hand)
            compareLink = equippedLink
        else
            contribB = {}
        end
    end

    -- mismo tope que el % total: la puntería por encima del tope aporta 0
    if CapsActive(build, metric) then
        local slots = INVTYPE_TO_SLOTS[equipLoc] or {}
        local removed = #slots == 1 and LinkList((GetEquippedItemId(slots[1]))) or {}
        for _, key in ipairs(CAPPED_ITEM_MODS) do
            contribA[key] = (contribA[key] or 0) + CapAdjustment(build, linkA, false, removed, nil, key)
            contribB[key] = (contribB[key] or 0) + CapAdjustment(build, compareLink, false, removed, nil, key)
        end
    end

    local keys = {}
    local seen = {}
    for key in pairs(contribA) do
        if not seen[key] then seen[key] = true; table.insert(keys, key) end
    end
    for key in pairs(contribB) do
        if not seen[key] then seen[key] = true; table.insert(keys, key) end
    end

    local rows = {}
    for _, key in ipairs(keys) do
        local diff = (contribA[key] or 0) - (contribB[key] or 0)
        if diff ~= 0 then
            local percentContribution = denominator and denominator ~= 0 and (diff / denominator * 100) or 0
            table.insert(rows, { key = key, label = BREAKDOWN_LABELS[key], diff = diff, percent = percentContribution })
        end
    end
    table.sort(rows, function(a, b) return math.abs(a.percent) > math.abs(b.percent) end)
    return rows
end

-- API pública para UI/Comparador.lua: no expone las locales de este archivo.
SimulateX_API = {
    GetComparisonEvaluations = GetComparisonEvaluations,
    GetComparisonBreakdown = GetComparisonBreakdown,
    GetItemStats = GetItemStatsFromData,
    GetStatLabel = function(key) return BREAKDOWN_LABELS[key] end,
    IsItemUsable = IsItemUsable,
    INVTYPE_TO_SLOTS = INVTYPE_TO_SLOTS,
    GetEffectivePlayerLevel = GetEffectivePlayerLevel,
    CLASS_FILE_TO_GAME_CLASS = CLASS_FILE_TO_GAME_CLASS,
    CLASS_DATA_VARS = CLASS_DATA_VARS,
    GetBestBuildPerSpec = GetBestBuildPerSpec,
    GetActiveSpecKey = GetActiveSpecKey,
    GetItemBasics = GetItemBasics,
    GetActiveSpecContext = GetActiveSpecContext,
    EvaluateForContext = EvaluateForContext,
    EvaluateStatDeltaForContext = EvaluateStatDeltaForContext,
    CLASS_MASK_BITS = CLASS_MASK_BITS,
}

local function ScanBagUpgrades()
    local context = SimulateX_API.GetActiveSpecContext()
    if not context then
        return {}
    end

    local playerLevel = SimulateX_API.GetEffectivePlayerLevel()
    local found = {}
    for bagId = 0, 4 do
        for slot = 1, GetContainerNumSlots(bagId) do
            local link = GetContainerItemLink(bagId, slot)
            if link then
                local minLevel, equipLoc = SimulateX_API.GetItemBasics(link)
                if equipLoc and (not minLevel or minLevel <= playerLevel)
                    and SimulateX_API.IsItemUsable(link, equipLoc) then
                    local evaluation = SimulateX_API.EvaluateForContext(context, link)
                    if evaluation and evaluation.gain > 0 and not evaluation.isNoise and evaluation.percent then
                        table.insert(found, { link = link, equipLoc = equipLoc, percent = evaluation.percent })
                    end
                end
            end
        end
    end

    table.sort(found, function(a, b)
        if a.percent ~= b.percent then return a.percent > b.percent end
        return a.link < b.link
    end)

    local upgrades, perSlot = {}, {}
    for _, entry in ipairs(found) do
        local slots = SimulateX_API.INVTYPE_TO_SLOTS[entry.equipLoc]
        local slotKey = slots and #slots == 1 and slots[1] or entry.equipLoc
        local count = perSlot[slotKey] or 0
        if count < 3 then
            table.insert(upgrades, entry)
            perSlot[slotKey] = count + 1
            if #upgrades == 10 then break end
        end
    end
    return upgrades
end

local bagAlertTimer = CreateFrame("Frame")
local bagAlertStarted = false
local function ScheduleBagAlert()
    if bagAlertStarted then return end
    bagAlertStarted = true
    local elapsedTotal = 0
    bagAlertTimer:SetScript("OnUpdate", function(self, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 5 then return end
        self:SetScript("OnUpdate", nil)
        self:Hide()
        if not SimulateX_DB.bagAlertDisabled then
            local upgrades = ScanBagUpgrades()
            if #upgrades > 0 then
                print(string.format("SimulateX: tienes %d objeto(s) en las bolsas que mejoran tu equipo (/simulatex bolsas).", #upgrades))
            end
        end
    end)
    bagAlertTimer:Show()
end

local function PrintBagUpgrades()
    local upgrades = ScanBagUpgrades()
    if #upgrades == 0 then
        print("SimulateX: no hay mejoras en tus bolsas.")
        return
    end

    print(string.format("SimulateX: %d mejora(s) en tus bolsas", #upgrades))
    for _, entry in ipairs(upgrades) do
        print(string.format("  %s %+.1f%% (%s)", entry.link, entry.percent, _G[entry.equipLoc] or entry.equipLoc))
    end
end

--[[----------------------------------------------------------------------
    FLECHA Y TOOLTIP: "active" si mejora la spec activa, "other" si solo
    mejora otra spec de la clase; nunca si no es usable, bloqueado por
    nivel, o "≈ igual" (arregla E3: ya no restringido a nivel 80).
------------------------------------------------------------------------]]

-- En tooltips originados desde la ventana de recompensa de misión (poblados
-- con SetQuestItem/SetQuestLogItem, no SetHyperlink), tooltip:GetItem() es
-- conocido por devolver vacío y por interferir con el coloreado nativo del
-- motor (ej. "Malla" en rojo cuando la clase no puede vestirla se pierde).
-- Se detecta ese origen por el frame dueño del tooltip y se usa la API de
-- misión en vez de GetItem().
local function GetTooltipItemLink(tooltip)
    local owner = tooltip:GetOwner()
    if owner and owner.rewardType == "item" then
        if QuestInfoFrame and QuestInfoFrame.questLog then
            return GetQuestLogItemLink(owner.type, owner:GetID())
        end
        return GetQuestItemLink(owner.type, owner:GetID())
    end
    local _, link = tooltip:GetItem()
    return link
end

local function GetUpgradeMarker(itemLink)
    local evaluations = GetItemEvaluations(itemLink)
    if not evaluations then
        return nil
    end

    local hasActiveUpgrade, hasOtherUpgrade = false, false
    for _, evaluation in ipairs(evaluations) do
        if not evaluation.blockedByLevel and not evaluation.isNoise and evaluation.gain > 0 then
            if evaluation.isActive then
                hasActiveUpgrade = true
            else
                hasOtherUpgrade = true
            end
        end
    end

    if hasActiveUpgrade then return "active" end
    if hasOtherUpgrade and not SimulateX_DB.otherSpecArrowDisabled then return "other" end
    return nil
end

local function FormatPercent(evaluation)
    if evaluation.isNoise then
        return "≈ igual"
    end
    if evaluation.againstEmpty then
        if evaluation.percent > 100 then
            return "hueco libre"
        end
        return string.format("%+.1f %% (hueco libre)", evaluation.percent)
    end
    return string.format("%+.1f %%", evaluation.percent)
end
SimulateX_API.FormatPercent = FormatPercent

local function GetPercentColor(evaluation)
    if evaluation.isNoise then
        return 0.6, 0.6, 0.6
    end
    if evaluation.gain > 0 then
        return 0.1, 1, 0.1
    end
    return 1, 0.3, 0.3
end

--[[----------------------------------------------------------------------
    BiS (v0.9): el objeto está en el set de referencia de wowsims de alguna
    fase (build.bis, Tools/generar_db_addon.py). Solo fases hasta la elegida
    en el panel (SimulateX_DB.maxPhase: 0 = prerraid, 1-5; nil = todas) y
    sets de la propia facción cuando wowsims los separa.
------------------------------------------------------------------------]]

local function BuildPhaseNumber(phase)
    if phase:match("^preraid") then
        return 0
    end
    return tonumber(phase:match("^p(%d)"))
end

local function PhaseLabel(n)
    return n == 0 and "Prerraid" or ("P" .. n)
end

-- {0, 1, 3, 4} -> "Prerraid-P1, P3-P4"
local function FormatPhaseRuns(phases)
    local parts, runStart, previous = {}, nil, nil
    for _, n in ipairs(phases) do
        if runStart and n == previous + 1 then
            previous = n
        else
            if runStart then
                table.insert(parts, runStart == previous and PhaseLabel(runStart)
                    or (PhaseLabel(runStart) .. "-" .. PhaseLabel(previous)))
            end
            runStart, previous = n, n
        end
    end
    if runStart then
        table.insert(parts, runStart == previous and PhaseLabel(runStart)
            or (PhaseLabel(runStart) .. "-" .. PhaseLabel(previous)))
    end
    return table.concat(parts, ", ")
end

-- specLabel -> "P3-P4", la spec activa primero
local function GetBisLines(itemId, classData, activeSpecLabel)
    local faction = (UnitFactionGroup("player") or ""):lower()
    local maxPhase = SimulateX_DB.maxPhase
    local phasesBySpec = {}
    for _, build in pairs(classData) do
        local specLabel = build.specLabel or build.spec
        local phase = build.phase or ""
        local n = BuildPhaseNumber(phase)
        local otherFaction = (phase:find("alliance") and faction ~= "alliance")
            or (phase:find("horde") and faction ~= "horde")
        local specEnabled = not (SimulateX_DB.disabledSpecs and SimulateX_DB.disabledSpecs[specLabel])
        if build.bis and build.bis[itemId] and n and not otherFaction and specEnabled
            and (not maxPhase or n <= maxPhase) then
            phasesBySpec[specLabel] = phasesBySpec[specLabel] or {}
            phasesBySpec[specLabel][n] = true
        end
    end
    local lines = {}
    for specLabel, set in pairs(phasesBySpec) do
        local phases = {}
        for n in pairs(set) do table.insert(phases, n) end
        table.sort(phases)
        table.insert(lines, { spec = specLabel, phases = FormatPhaseRuns(phases), active = specLabel == activeSpecLabel })
    end
    table.sort(lines, function(a, b)
        if a.active ~= b.active then return a.active end
        return a.spec < b.spec
    end)
    return lines
end

local function AddBisLines(tooltip, link, activeSpecLabel)
    if SimulateX_DB.bisTooltipDisabled then
        return
    end
    local classData = _G[CLASS_DATA_VARS[select(2, UnitClass("player"))] or ""]
    local itemId = tonumber(link:match("item:(%d+)"))
    if not classData or not itemId then
        return
    end
    for _, line in ipairs(GetBisLines(itemId, classData, activeSpecLabel)) do
        tooltip:AddDoubleLine("  BiS " .. line.spec, line.phases, 1, 0.82, 0, 1, 0.82, 0)
    end
end

--[[----------------------------------------------------------------------
    BONUS DE CONJUNTO (v0.9): solo aviso, no entra en la puntuación (el
    efecto del bonus no tiene un peso fiable). Conjunto de cada pieza y
    umbrales de ItemSet.dbc (SimulateX_ItemStats "t=", SimulateX_ItemSets).
------------------------------------------------------------------------]]

local function GetItemSetId(link)
    local itemId = link and tonumber(link:match("item:(%d+)"))
    local data = itemId and SimulateX_ItemStats and SimulateX_ItemStats[itemId]
    return data and tonumber(data:match("t=(%d+)"))
end

local function IsSetThreshold(setId, pieces)
    for threshold in ((SimulateX_ItemSets and SimulateX_ItemSets[setId]) or ""):gmatch("%d+") do
        if tonumber(threshold) == pieces then
            return true
        end
    end
    return false
end

local function EquippedSetPieces(setId)
    local count = 0
    for _, slotName in ipairs(EQUIPPED_SLOTS) do
        if GetItemSetId((GetEquippedItemId(slotName))) == setId then
            count = count + 1
        end
    end
    return count
end

-- Notas {texto, bueno} de lo que cambia en bonus de conjunto si el objeto
-- sustituye a lo que llevas en su hueco (solo huecos únicos: los conjuntos
-- no incluyen anillos, abalorios ni armas de una mano)
local function GetSetBonusNotes(link)
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    local slots = equipLoc and INVTYPE_TO_SLOTS[equipLoc]
    if not slots or #slots ~= 1 then
        return {}
    end
    local newSet = GetItemSetId(link)
    local oldSet = GetItemSetId((GetEquippedItemId(slots[1])))
    if newSet == oldSet then
        return {}
    end
    local notes = {}
    if oldSet then
        local pieces = EquippedSetPieces(oldSet)
        if IsSetThreshold(oldSet, pieces) then
            table.insert(notes, { string.format("Pierdes el bonus de %d piezas de tu conjunto", pieces), false })
        end
    end
    if newSet then
        local pieces = EquippedSetPieces(newSet) + 1
        if IsSetThreshold(newSet, pieces) then
            table.insert(notes, { string.format("Activa el bonus de %d piezas de su conjunto", pieces), true })
        end
    end
    return notes
end

SimulateX_API.GetSetBonusNotes = GetSetBonusNotes

local function AddSetBonusLines(tooltip, link)
    if SimulateX_DB.setBonusWarningDisabled then
        return
    end
    for _, note in ipairs(GetSetBonusNotes(link)) do
        if note[2] then
            tooltip:AddLine("  " .. note[1], 0.1, 1, 0.1)
        else
            tooltip:AddLine("  " .. note[1], 1, 0.3, 0.3)
        end
    end
end

local function OnTooltipSetItem(tooltip)
    local link = GetTooltipItemLink(tooltip)
    if not link then
        return
    end

    -- Panel v0.3 (mantenido): la opción de nivel bajo pasa a controlar si se
    -- muestran las comparaciones "estimadas" (EP, sin simulación exacta);
    -- a 80 con weightsKind = "sim" el dato es exacto y siempre se muestra.
    if GetEffectivePlayerLevel() < 80 and SimulateX_DB.lowLevelEstimateDisabled then
        return
    end

    local evaluations = GetItemEvaluations(link)
    if not evaluations or #evaluations == 0 then
        return
    end

    -- bloqueado solo por nivel: el dato existe, pero aún no se enseña
    if evaluations[1].blockedByLevel then
        return
    end

    -- evaluations[1] es la spec activa (si está activada en el panel)
    local header = "SimulateX"
    if evaluations[1].comparisonLabel then
        header = header .. "  vs. " .. evaluations[1].comparisonLabel
    end
    tooltip:AddLine(header, 0.6, 0.8, 1)

    for _, evaluation in ipairs(evaluations) do
        local label, lr, lg, lb
        if evaluation.isActive then
            label, lr, lg, lb = "  " .. evaluation.specLabel .. " (tu spec)", 1, 1, 1
        else
            label, lr, lg, lb = "  " .. evaluation.specLabel, 0.75, 0.75, 0.75
        end
        local pr, pg, pb = GetPercentColor(evaluation)
        tooltip:AddDoubleLine(label, FormatPercent(evaluation), lr, lg, lb, pr, pg, pb)
    end
    AddSetBonusLines(tooltip, link)
    AddBisLines(tooltip, link, evaluations[1].isActive and evaluations[1].specLabel)

    tooltip:Show()
end

--[[----------------------------------------------------------------------
    ICONO OVERLAY (hooks ya verificados, conservados de v0.2.1): superpone
    la flecha de mejora sobre bolsas/botín/recompensa de misión.
------------------------------------------------------------------------]]

-- Flecha del botón de subir planta del mapa del mundo (3.3.5a no tiene flecha
-- de mejora nativa) y brillo de objeto equipado de la barra de acción.
local UPGRADE_ARROW_TEXTURE = "Interface\\Buttons\\Arrow-Up-Up"
local UPGRADE_GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

-- Marco hijo con nivel superior al botón para quedar por encima de su borde
-- (NormalTexture). Se ancla al icono: en recompensas de misión el botón es
-- mucho más ancho que el icono.
local function CreateUpgradeIcon(button)
    local anchor = _G[(button:GetName() or "") .. "IconTexture"] or button
    local holder = CreateFrame("Frame", nil, button)
    holder:SetFrameLevel(button:GetFrameLevel() + 2)
    holder:SetAllPoints(anchor)

    -- el borde ocupa el centro de la textura: 62 px para un icono de 36
    local glow = holder:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture(UPGRADE_GLOW_TEXTURE)
    glow:SetBlendMode("ADD")
    glow:SetPoint("TOPLEFT", holder, "TOPLEFT", -13, 13)
    glow:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 13, -13)
    holder.glow = glow

    local arrowFrame = CreateFrame("Frame", nil, holder)
    arrowFrame:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -3, -3)
    holder.arrowFrame = arrowFrame

    local shadow = arrowFrame:CreateTexture(nil, "ARTWORK")
    shadow:SetTexture(UPGRADE_ARROW_TEXTURE)
    shadow:SetVertexColor(0, 0, 0, 1)
    shadow:SetPoint("TOPLEFT", arrowFrame, "TOPLEFT", -2, 2)
    shadow:SetPoint("BOTTOMRIGHT", arrowFrame, "BOTTOMRIGHT", 2, -2)

    local arrow = arrowFrame:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(UPGRADE_ARROW_TEXTURE)
    arrow:SetAllPoints(arrowFrame)
    holder.arrow = arrow

    return holder
end

-- Superpone (o retira) la flecha de mejora sobre un botón de objeto (bolsa,
-- botín, recompensa de misión, banco, vendedor). Un solo marco por botón,
-- reutilizado en cada actualización.
local function UpdateUpgradeIcon(button, itemLink)
    if not button then
        return
    end
    if not button.simulateXIcon then
        button.simulateXIcon = CreateUpgradeIcon(button)
    end

    local icon = button.simulateXIcon
    local marker = itemLink and GetUpgradeMarker(itemLink)

    -- el brillo lleva el color de calidad del objeto, la flecha el de la spec
    if marker then
        local quality = select(3, GetItemInfo(itemLink))
        local r, g, b = GetItemQualityColor(quality or 1)
        icon.glow:SetVertexColor(r, g, b, marker == "active" and 1 or 0.7)
    end
    if marker == "active" then
        icon.arrow:SetVertexColor(0.3, 1, 0.3)
        icon.arrowFrame:SetSize(22, 22)
        icon:Show()
    elseif marker == "other" then
        icon.arrow:SetVertexColor(1, 0.6, 0.2)
        icon.arrowFrame:SetSize(16, 16)
        icon:Show()
    else
        icon:Hide()
    end
end

-- Bolsas: cada ContainerFrame%dItem%d representa un icono de objeto. Se
-- engancha ContainerFrame_Update (llamada cada vez que se abre una bolsa o
-- cambia su contenido) para actualizar el overlay de todos sus botones.
local function UpdateContainerFrameIcons(frame)
    if not frame or not frame.GetID then
        return
    end
    local bagId = frame:GetID()
    for i = 1, (frame.size or 0) do
        local button = _G[frame:GetName() .. "Item" .. i]
        if button then
            local slot = button:GetID()
            local link = GetContainerItemLink(bagId, slot)
            UpdateUpgradeIcon(button, link)
        end
    end
end

-- Botín: LootFrame_UpdateButton(index) actualiza un botón LootButton%d
-- concreto cada vez que se llama, no todos a la vez (verificado contra el
-- FrameXML fuente de 3.3.5a) — el hook recibe ese mismo índice.
local function UpdateLootFrameIcon(index)
    local button = _G["LootButton" .. index]
    if button and button.slot then
        local link = GetLootSlotLink(button.slot)
        UpdateUpgradeIcon(button, link)
    end
end

-- Recompensa de misión: los botones se llaman QuestInfoItem%d dentro de
-- QuestInfoRewardsFrame. `.type` indica la categoría ("choice"/"reward", no
-- el tipo de objeto) y `.rewardType` si es "item" o "spell" (glifos/talentos
-- también pueden ser recompensa, no solo objetos) — verificado contra el
-- FrameXML fuente, que usa GetQuestLogChoiceInfo/GetQuestItemInfo/
-- GetQuestLogRewardInfo (sin link); el link se obtiene aparte con la API
-- global GetQuestLogItemLink/GetQuestItemLink.
local function UpdateQuestInfoIcons()
    if not QuestInfoRewardsFrame then
        return
    end
    for _, button in ipairs({ QuestInfoRewardsFrame:GetChildren() }) do
        if button.rewardType == "item" and button.type then
            local link
            if QuestInfoFrame and QuestInfoFrame.questLog then
                link = GetQuestLogItemLink(button.type, button:GetID())
            else
                link = GetQuestItemLink(button.type, button:GetID())
            end
            UpdateUpgradeIcon(button, link)
        end
    end
end

-- Banco: BankFrameItemButton_Update(button) actualiza un botón concreto cada
-- vez que se llama (mismo patrón que LootFrame_UpdateButton), tanto para
-- objetos como para los botones de bolsa de banco (button.isBag, sin objeto
-- que evaluar) — verificado contra BankFrame.lua del FrameXML fuente de
-- 3.3.5a. El link se obtiene con el contenedor especial BANK_CONTAINER (-1),
-- misma API que GetContainerItemLink de las bolsas normales.
local function UpdateBankFrameIcon(button)
    if not button or button.isBag then
        return
    end
    local link = GetContainerItemLink(BANK_CONTAINER, button:GetID())
    UpdateUpgradeIcon(button, link)
end

-- Vendedor: MerchantFrame_UpdateMerchantInfo() repuebla TODOS los botones de
-- la página a la vez (sin recibir un botón concreto, a diferencia de bolsas/
-- botín/banco) — verificado contra MerchantFrame.lua del FrameXML fuente.
-- itemButton.link ya lo deja puesto la propia función nativa (incluye
-- objetos con coste en moneda alternativa, vía GetMerchantItemLink).
local function UpdateMerchantFrameIcons()
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
        if itemButton and itemButton.hasItem then
            UpdateUpgradeIcon(itemButton, itemButton.link)
        end
    end
end

-- Casa de subastas: cada pestaña (buscar, mis pujas, mis subastas) repuebla
-- todas sus filas a la vez; la fila i muestra la subasta offset + i del
-- scroll. La flecha va en el botón del icono ("<fila>Item"), no en la fila.
local AUCTION_TABS = {
    { prefix = "BrowseButton", count = 8, query = "list", scroll = "BrowseScrollFrame" },
    { prefix = "BidButton", count = 9, query = "bidder", scroll = "BidScrollFrame" },
    { prefix = "AuctionsButton", count = 9, query = "owner", scroll = "AuctionsScrollFrame" },
}

local function UpdateAuctionFrameIcons()
    for _, tab in ipairs(AUCTION_TABS) do
        local scrollFrame = _G[tab.scroll]
        local offset = scrollFrame and FauxScrollFrame_GetOffset(scrollFrame) or 0
        for i = 1, tab.count do
            local row = _G[tab.prefix .. i]
            local itemButton = _G[tab.prefix .. i .. "Item"]
            if row and itemButton then
                local link = row:IsShown() and GetAuctionItemLink(tab.query, offset + i)
                UpdateUpgradeIcon(itemButton, link)
            end
        end
    end
end

-- Blizzard_AuctionUI se carga al abrir la subasta por primera vez.
local auctionHooked = false
local function HookAuctionFrame()
    if auctionHooked or not AuctionFrameBrowse_Update then
        return
    end
    auctionHooked = true
    hooksecurefunc("AuctionFrameBrowse_Update", UpdateAuctionFrameIcons)
    hooksecurefunc("AuctionFrameBid_Update", UpdateAuctionFrameIcons)
    hooksecurefunc("AuctionFrameAuctions_Update", UpdateAuctionFrameIcons)
end

-- Correo: bandeja (primer adjunto de cada carta; flecha si mejora alguno) y
-- carta abierta (un botón por adjunto).
local function GetMailUpgradeLink(mailIndex, itemCount)
    for attachIndex = 1, math.min(itemCount or 0, ATTACHMENTS_MAX_RECEIVE or 16) do
        local link = GetInboxItemLink(mailIndex, attachIndex)
        if link and GetUpgradeMarker(link) then
            return link
        end
    end
end

local function UpdateInboxIcons()
    for i = 1, INBOXITEMS_TO_DISPLAY or 7 do
        local button = _G["MailItem" .. i .. "Button"]
        if button then
            local link = button:IsShown() and button.index and GetMailUpgradeLink(button.index, button.itemCount)
            UpdateUpgradeIcon(button, link or nil)
        end
    end
end

local function UpdateOpenMailIcons()
    for i = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local button = _G["OpenMailAttachmentButton" .. i]
        if button then
            local link = button:IsShown() and InboxFrame.openMailID and GetInboxItemLink(InboxFrame.openMailID, i)
            UpdateUpgradeIcon(button, link or nil)
        end
    end
end

-- Redibuja los overlays de todas las bolsas/banco/vendedor/subasta abiertos: usado
-- tras vaciar la caché (equipo cambiado, subida de nivel, cambio de
-- talentos) para que el overlay refleje el estado nuevo sin esperar a la
-- próxima actualización nativa de esas ventanas.
local function RefreshOpenContainers()
    for bagId = 0, NUM_BAG_SLOTS do
        local frame = _G["ContainerFrame" .. (bagId + 1)]
        if frame and frame:IsVisible() then
            UpdateContainerFrameIcons(frame)
        end
    end
    if BankFrame and BankFrame:IsVisible() then
        for slot = 1, NUM_BANKGENERIC_SLOTS do
            UpdateBankFrameIcon(_G["BankFrameItem" .. slot])
        end
    end
    if MerchantFrame and MerchantFrame:IsVisible() then
        UpdateMerchantFrameIcons()
    end
    if AuctionFrame and AuctionFrame:IsVisible() then
        UpdateAuctionFrameIcons()
    end
    if InboxFrame and InboxFrame:IsVisible() then
        UpdateInboxIcons()
    end
    if OpenMailFrame and OpenMailFrame:IsVisible() then
        UpdateOpenMailIcons()
    end
end
SimulateX_RefreshIcons = RefreshOpenContainers  -- para el panel de opciones

--[[----------------------------------------------------------------------
    REFRESCO: PLAYER_EQUIPMENT_CHANGED, PLAYER_LEVEL_UP, PLAYER_TALENT_UPDATE
    redibujan las ventanas abiertas (el equipo/nivel/talentos cambiados
    invalidan las comparaciones ya hechas).
------------------------------------------------------------------------]]

-- v0.8: datos de clase repartidos en sub-addons LoadOnDemand
-- (Addon/SimulateX_<Clase>/) para no cargar las 10 clases en cada personaje.
local function LoadClassDataAddon()
    local _, classFileName = UnitClass("player")
    local gameClassName = CLASS_FILE_TO_GAME_CLASS[classFileName]
    if not gameClassName then return end
    local subAddon = "SimulateX_" .. gameClassName
    if GetAddOnInfo(subAddon) then
        LoadAddOn(subAddon)
    end
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        SimulateX_DB = SimulateX_DB or {}
        LoadClassDataAddon()
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)

        if ContainerFrame_Update then
            hooksecurefunc("ContainerFrame_Update", UpdateContainerFrameIcons)
        end
        if LootFrame_UpdateButton then
            hooksecurefunc("LootFrame_UpdateButton", UpdateLootFrameIcon)
        end
        if QuestInfo_ShowRewards then
            hooksecurefunc("QuestInfo_ShowRewards", UpdateQuestInfoIcons)
        end
        if BankFrameItemButton_Update then
            hooksecurefunc("BankFrameItemButton_Update", UpdateBankFrameIcon)
        end
        if MerchantFrame_UpdateMerchantInfo then
            hooksecurefunc("MerchantFrame_UpdateMerchantInfo", UpdateMerchantFrameIcons)
        end
        if InboxFrame_Update then
            hooksecurefunc("InboxFrame_Update", UpdateInboxIcons)
        end
        if OpenMail_Update then
            hooksecurefunc("OpenMail_Update", UpdateOpenMailIcons)
        end
        HookAuctionFrame()  -- por si otro addon ya cargó la subasta
        if SimulateX_Lanzadores_Init then
            SimulateX_Lanzadores_Init()
        end
        if SimulateX_Economia_Init then
            SimulateX_Economia_Init()
        end
    elseif event == "ADDON_LOADED" and ... == "Blizzard_AuctionUI" then
        HookAuctionFrame()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ScheduleBagAlert()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_TALENT_UPDATE" then
        if event == "PLAYER_TALENT_UPDATE" then
            playerTalentHit = nil
        end
        RefreshOpenContainers()
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        -- humanoide (o cualquier otra forma) no cambia nada: vale la última
        local role = GetDruidFormRole()
        if role and role ~= SimulateX_DB.feralRole then
            SimulateX_DB.feralRole = role
            RefreshOpenContainers()
            if SimulateX_Comparador_Refresh then
                SimulateX_Comparador_Refresh()
            end
        end
    end
end

SimulateX:RegisterEvent("ADDON_LOADED")
SimulateX:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
SimulateX:RegisterEvent("PLAYER_LEVEL_UP")
SimulateX:RegisterEvent("PLAYER_TALENT_UPDATE")
SimulateX:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
SimulateX:RegisterEvent("PLAYER_ENTERING_WORLD")
SimulateX:SetScript("OnEvent", OnEvent)

--[[----------------------------------------------------------------------
    DEPURACIÓN: /simulatex debug + link muestra las estadísticas del objeto,
    la usabilidad y la puntuación/comparación por spec para ese objeto.
    /simulatex nivel 80 fuerza la lógica de nivel 80 para probar sin un 80
    (solo dura la sesión, nunca se guarda).
------------------------------------------------------------------------]]

local function PrintDebugInfo(itemLink)
    if not itemLink then
        print("SimulateX debug: pega un link de objeto tras el comando (shift-click al objeto).")
        return
    end

    print("SimulateX debug: " .. itemLink)
    print("  Usable: " .. tostring(IsItemUsable(itemLink)))
    print("  Competencia de clase: " .. (IsProficient(itemLink) == nil and "objeto fuera de la tabla" or tostring(IsProficient(itemLink))))
    print("  Bloqueado solo por nivel: " .. tostring(IsBlockedByLevelOnly(itemLink)))
    print("  Clase permitida: " .. tostring(IsAllowedClass(itemLink)))

    local stats = GetItemStatsFromData(itemLink)
    local statKeys = {}
    for key in pairs(stats) do table.insert(statKeys, key) end
    table.sort(statKeys)
    print("  Estadísticas: " .. (#statKeys > 0 and table.concat(statKeys, ", ") or "(sin estadísticas)"))
    for _, key in ipairs(statKeys) do
        print(string.format("    %s = %s", key, tostring(stats[key])))
    end

    local weaponDps = stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT
    local classData = _G[CLASS_DATA_VARS[select(2, UnitClass("player"))] or ""]
    if weaponDps and classData then
        local hand = GetDefaultHand(itemLink)
        for _, entry in pairs(GetBestBuildPerSpec(classData)) do
            local build = entry.build
            if build.weaponDps and build.weaponDps[hand] then
                print(string.format("  DPS de arma (%s) en %s: %.2f pts", hand, entry.buildId, ScoreWeaponDps(weaponDps, build, hand)))
            end
        end
    end

    local evaluations = GetItemEvaluations(itemLink)
    if not evaluations or #evaluations == 0 then
        print("  Sin evaluación por spec (¿clase sin datos, o slot no comparable?).")
        return
    end
    print("  Rol feral recordado: " .. tostring(SimulateX_DB.feralRole or "dps (por defecto)"))
    for _, evaluation in ipairs(evaluations) do
        print(string.format("  %s%s [%s, %s]: ganancia %.2f, %.1f%% %s%s%s",
            evaluation.isActive and "*" or "", evaluation.specLabel, evaluation.buildId, evaluation.metric,
            evaluation.gain, evaluation.percent, evaluation.isExact and "(simulado)" or "(estimado)",
            evaluation.isNoise and " ≈igual" or "", evaluation.blockedByLevel and " [bloqueado por nivel]" or ""))
    end
end

SLASH_SIMULATEX1 = "/simulatex"
SlashCmdList["SIMULATEX"] = function(msg)
    msg = msg and msg:trim() or ""
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "comparar" then
        if SimulateX_Comparador_Toggle then
            SimulateX_Comparador_Toggle()
        end
    elseif command == "bolsas" then
        PrintBagUpgrades()
    elseif command == "debug" then
        local link = rest ~= "" and rest or nil
        PrintDebugInfo(link)
    elseif command == "nivel" then
        local level = tonumber(rest)
        if level then
            forcedLevelOverride = level
            print(string.format("SimulateX: nivel forzado a %d para esta sesión.", level))
        else
            forcedLevelOverride = nil
            print("SimulateX: nivel forzado desactivado, se usa el nivel real del personaje.")
        end
        RefreshOpenContainers()
    elseif msg == "" then
        SimulateX_DB.forcedBuild = nil
        print("SimulateX: detección automática de build activada.")
    else
        SimulateX_DB.forcedBuild = msg
        print("SimulateX: build forzada a '" .. msg .. "'.")
    end
end
