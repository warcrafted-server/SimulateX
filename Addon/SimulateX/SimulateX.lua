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

--[[----------------------------------------------------------------------
    USABILIDAD: tooltip oculto para leer lo que el juego pinta en rojo
    (tipo de armadura/arma incompatible, "Clases:", habilidad no aprendida).
    Independiente del idioma y del nivel: el requisito de nivel mínimo se
    trata aparte (dato sí, flecha no), no cuenta como "no usable".
------------------------------------------------------------------------]]

local scanTooltip = CreateFrame("GameTooltip", "SimulateXScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local RED = RED_FONT_COLOR
local RED_TOLERANCE = 0.05

local function IsRedLine(r, g, b)
    return r and math.abs(r - RED.r) < RED_TOLERANCE
        and math.abs(g - RED.g) < RED_TOLERANCE
        and math.abs(b - RED.b) < RED_TOLERANCE
end

-- Patrón para reconocer la línea de nivel mínimo a partir de la propia
-- constante localizada del cliente (ITEM_MIN_LEVEL = "Requiere nivel %d" en
-- esES): un objeto bloqueado SOLO por esa línea sigue siendo "usable" a
-- efectos de tipo de armadura/arma/clase, solo que aún no se puede llevar a
-- este nivel (eso se trata aparte, ver EsBloqueadoPorNivel).
local ITEM_MIN_LEVEL_PATTERN = ITEM_MIN_LEVEL and ("^" .. ITEM_MIN_LEVEL:gsub("%%d", "%%d+") .. "$")

-- link -> { hasLevelBlock, hasOtherBlock }. Un solo escaneo del tooltip
-- oculto por link cubre tanto IsItemUsable como IsBlockedByLevelOnly: cada
-- evaluación de build (una por spec de la clase, hasta 10+ por tooltip)
-- llamaba a las dos por separado, reescaneando el tooltip cada vez.
local scanCache = {}

local function ScanRedLines(itemLink)
    local cached = scanCache[itemLink]
    if cached then
        return cached[1], cached[2]
    end

    scanTooltip:ClearLines()
    scanTooltip:SetHyperlink(itemLink)

    local hasLevelBlock, hasOtherBlock = false, false
    for i = 1, scanTooltip:NumLines() do
        local leftLine = _G["SimulateXScanTooltipTextLeft" .. i]
        local rightLine = _G["SimulateXScanTooltipTextRight" .. i]
        for _, fontString in ipairs({ leftLine, rightLine }) do
            if fontString then
                local text = fontString:GetText()
                local r, g, b = fontString:GetTextColor()
                if text and IsRedLine(r, g, b) then
                    if ITEM_MIN_LEVEL_PATTERN and text:match(ITEM_MIN_LEVEL_PATTERN) then
                        hasLevelBlock = true
                    else
                        hasOtherBlock = true
                    end
                end
            end
        end
    end

    scanCache[itemLink] = { hasLevelBlock, hasOtherBlock }
    return hasLevelBlock, hasOtherBlock
end

-- true si el tooltip del objeto no tiene ninguna línea roja aparte, como
-- mucho, de la de nivel mínimo. Caché por link: dos objetos con el mismo id
-- pero sufijo aleatorio distinto tienen link distinto, así que no se
-- confunden entre sí.
local function IsItemUsable(itemLink)
    local _, hasOtherBlock = ScanRedLines(itemLink)
    return not hasOtherBlock
end

-- true si la ÚNICA razón de bloqueo es el nivel del personaje (línea roja de
-- ITEM_MIN_LEVEL presente y ninguna otra línea roja): el objeto es un dato
-- válido para mostrar (aparecerá al subir de nivel) pero no debe llevar
-- flecha de mejora todavía.
local function IsBlockedByLevelOnly(itemLink)
    local hasLevelBlock, hasOtherBlock = ScanRedLines(itemLink)
    return hasLevelBlock and not hasOtherBlock
end

local function ClearUsabilityCache()
    scanCache = {}
end

--[[----------------------------------------------------------------------
    PUNTUACIÓN: EP en tiempo real con GetItemStats(link, tabla) (decisión de
    diseño 1). Sustituye a lowLevelScores: cubre cualquier objeto en
    cualquier nivel, incluidos sufijos aleatorios, sin depender de un
    catálogo pre-simulado.

    Escalado por nivel (paso 6 del plan): w(L) = w80 × índicePor1%(80) /
    índicePor1%(L) para los combat ratings; agilidad/intelecto se reescalan
    aparte porque su valor incluye el componente de crítico "de stat", que
    escala distinto del crítico "de rating" (ver critComponent, paso 5).
------------------------------------------------------------------------]]

-- ITEM_MOD_* cuyo valor en GetItemStats ya corresponde 1:1 a un peso de la
-- build (weights de SimulateX_Data_<Clase>.lua): se multiplica directo.
-- Crítico/golpe/celeridad NO están aquí porque su peso en la build ya es la
-- suma combinada (Tools/mapeo_stats.py::combine_rating_weight), y se lee con
-- la misma clave ITEM_MOD_*_RATING_SHORT sin distinguir melee/spell aquí:
-- GetItemStats tampoco distingue, solo hay un rating de crítico por objeto.
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
    local equipLoc = select(9, GetItemInfo(itemLink))
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

-- Puntuación = Σ peso × stat + DPS de arma + huecos × valor de hueco
-- (socketValue/metaSocketValue de la build). Ignora la bonificación de ranura
-- (igual que el paso 1 al simular: Pawn por defecto tampoco la cuenta).
-- hand: mano donde iría el arma; sin ella se deduce del tipo de objeto.
local function ScoreItem(itemLink, weights, build, hand)
    local stats = GetItemStats(itemLink) or {}
    local score = ScoreWeaponDps(stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT, build, hand or GetDefaultHand(itemLink))

    for _, key in ipairs(DIRECT_WEIGHT_KEYS) do
        local weight = weights[key]
        if weight and stats[key] then
            score = score + weight * stats[key]
        end
    end
    for itemModKey in pairs(SCALABLE_BY_LEVEL) do
        local weight = weights[itemModKey]
        if weight and stats[itemModKey] then
            score = score + weight * stats[itemModKey]
        end
    end

    for statKey in pairs(stats) do
        if statKey:match("^EMPTY_SOCKET_") then
            if statKey == "EMPTY_SOCKET_META" then
                score = score + (build.metaSocketValue or 0)
            else
                score = score + (build.socketValue or 0)
            end
        end
    end

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
}

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
    if whichHand == "oh" then
        return metricName == "dps" and data.dpsOH or nil
    end
    return data[metricName]
end

-- Puntúa candidato y equipado con la MISMA fuente de datos (decisión 5: una
-- comparación nunca mezcla exacto y EP): exacto para ambos solo si los dos
-- tienen entrada en items; si a cualquiera le falta, EP para ambos.
local function ComparePair(candLink, candId, equippedLink, equippedId, build, weights, metricName, hand)
    local candExact = candId and GetExactDelta(build, candId, metricName)
    local equippedExact = equippedId and GetExactDelta(build, equippedId, metricName)

    if candExact and equippedExact then
        return candExact - equippedExact
    end

    local candScore = candLink and ScoreItem(candLink, weights, build, hand) or 0
    local equippedScore = equippedLink and ScoreItem(equippedLink, weights, build, hand) or 0
    return candScore - equippedScore
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

-- Ganancia vs equipado (positiva = mejora). metricName es "dps", "hps",
-- "tps" o "dtps" según el rol de la build (paso 6: tanque usa "Amenaza" =
-- tps y "Supervivencia" = dtps, donde MENOR es mejor: el llamador invierte
-- el signo para esos casos, aquí siempre se devuelve candidato − equipado).
local function CompareAgainstEquipped(itemLink, itemId, equipLoc, build, weights, metricName)
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
            return ComparePair(itemLink, itemId, mhLink, mhId, build, weights, metricName, "mainHand")
        end

        local ohLink, ohId = GetEquippedItemId("SecondaryHandSlot")
        local gainMh = ComparePair(itemLink, itemId, mhLink, mhId, build, weights, metricName, "mainHand")

        -- Mano izquierda: si hay dato exacto de dpsOH para AMBOS lados se usa
        -- (decisión 5), si no EP (que no distingue de mano, mismo score).
        local candOhExact = itemId and GetExactDelta(build, itemId, metricName, "oh")
        local equippedOhExact = ohId and GetExactDelta(build, ohId, metricName, "oh")
        local gainOh
        if candOhExact and equippedOhExact then
            gainOh = candOhExact - equippedOhExact
        else
            gainOh = ComparePair(itemLink, itemId, ohLink, ohId, build, weights, metricName, "offHand")
        end

        return math.max(gainMh, gainOh)
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

            if candExact and (mhExact or not equippedLink) and (ohExact or not ohLink) then
                return candExact - (mhExact or 0) - (ohExact or 0)
            end

            local candScore = ScoreItem(itemLink, weights, build, "mainHand")
            local equippedScore = (equippedLink and ScoreItem(equippedLink, weights, build, "mainHand") or 0)
                + (ohLink and ScoreItem(ohLink, weights, build, "offHand") or 0)
            return candScore - equippedScore
        end

        local hand = SLOT_TO_HAND[slotName]
        if not equippedLink then
            return GetScore(itemLink, itemId, build, weights, metricName, hand)  -- slot vacío: puntuación completa
        end
        return ComparePair(itemLink, itemId, equippedLink, equippedId, build, weights, metricName, hand)
    end

    -- Anillos/abalorios: contra el peor de los dos equipados.
    local worstLink, worstId, worstScore
    for _, slotName in ipairs(slots) do
        local equippedLink, equippedId = GetEquippedItemId(slotName)
        if equippedLink then
            local equippedScore = GetScore(equippedLink, equippedId, build, weights, metricName)
            if not worstScore or equippedScore < worstScore then
                worstScore, worstLink, worstId = equippedScore, equippedLink, equippedId
            end
        end
    end
    if not worstLink then
        return GetScore(itemLink, itemId, build, weights, metricName)  -- ambos slots vacíos: puntuación completa
    end
    return ComparePair(itemLink, itemId, worstLink, worstId, build, weights, metricName)
end

--[[----------------------------------------------------------------------
    PORCENTAJE Y RUIDO: a 80 con weightsKind = "sim" el % es sobre base
    (dps/hps/tps/dtps de la build); en cualquier otro caso (preset, o nivel
    < 80) no hay "base" de referencia con sentido con pesos reescalados, así
    que el % es sobre la suma de puntuación EP de todo el equipo actual con
    esos mismos pesos. |ganancia| < 0.3 % del denominador → "≈ igual".
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

-- Devuelve (percent, isNoise). base80 es build.base[metricName] (solo válido
-- si weightsKind == "sim" y el jugador está a nivel 80).
local function ComputePercent(gain, weightsKind, playerLevel, base80, weights, build)
    local denominator
    if weightsKind == "sim" and playerLevel >= 80 and base80 and base80 ~= 0 then
        denominator = base80
    else
        denominator = GetEquippedTotalScore(weights, build)
    end

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

-- role de la build -> lista de métricas a mostrar (nombre, etiqueta,
-- menorEsMejor). Tanque muestra las DOS (Supervivencia y Amenaza): arregla
-- E8, antes mostraba "DPS" para tanque, un dato que no le sirve al jugador.
local ROLE_METRICS = {
    dps = { { metric = "dps", label = "DPS", lowerIsBetter = false } },
    healer = { { metric = "hps", label = "HPS", lowerIsBetter = false } },
    tank = {
        { metric = "dtps", label = "Supervivencia", lowerIsBetter = true },
        { metric = "tps", label = "Amenaza", lowerIsBetter = false },
    },
}

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
        if link then
            local score = GetScore(link, id, build, weights, metricName)
            if not worstScore or score < worstScore then
                worstScore, worstLink = score, link
            end
        end
    end
    return worstLink and GetItemInfo(worstLink)
end

-- Devuelve una lista de evaluaciones (una para dps/healer, dos para tank:
-- Supervivencia y Amenaza). "gain"/"percent" siempre positivo = mejora, ya
-- invertido para las métricas donde menor es mejor (dtps).
local function EvaluateBuild(itemLink, itemId, equipLoc, buildId, build, playerLevel, classGameName)
    local roleMetrics = ROLE_METRICS[build.role] or ROLE_METRICS.dps
    if not IsItemUsable(itemLink) then
        return nil
    end

    local weights = GetWeightsAtLevel(build, playerLevel, classGameName)
    local blockedByLevel = IsBlockedByLevelOnly(itemLink)
    local isExact = (build.weightsKind == "sim" and playerLevel >= 80)

    local evaluations = {}
    for _, roleInfo in ipairs(roleMetrics) do
        local rawGain = CompareAgainstEquipped(itemLink, itemId, equipLoc, build, weights, roleInfo.metric)
        if rawGain ~= nil then
            local gain = roleInfo.lowerIsBetter and -rawGain or rawGain
            local percent, isNoise = ComputePercent(gain, build.weightsKind, playerLevel,
                build.base and build.base[roleInfo.metric] and (roleInfo.lowerIsBetter and -build.base[roleInfo.metric] or build.base[roleInfo.metric]),
                weights, build)
            local comparisonLabel = GetComparisonLabel(equipLoc, build, weights, roleInfo.metric)

            table.insert(evaluations, {
                buildId = buildId,
                specLabel = build.specLabel or build.spec,
                role = build.role,
                metricLabel = roleInfo.label,
                comparisonLabel = comparisonLabel,
                gain = gain,
                percent = percent,
                isNoise = isNoise,
                isExact = isExact,
                blockedByLevel = blockedByLevel,
                talentTree = build.talentTree,
            })
        end
    end

    if #evaluations == 0 then
        return nil  -- slot no comparable (camisa, tabardo, munición, ...)
    end
    return evaluations
end

-- Evalúa el objeto contra todas las builds relevantes de la clase del
-- jugador (una por spec real, decisión 9), ordenadas: la activa primero.
local function GetItemEvaluations(itemLink)
    local classFileName = select(2, UnitClass("player"))
    local gameClassName = CLASS_FILE_TO_GAME_CLASS[classFileName]
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData or not gameClassName then
        return nil
    end

    local itemId = tonumber(itemLink:match("item:(%d+)"))
    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    if not equipLoc or equipLoc == "" then
        return nil
    end

    local activeTree = GetActiveTalentTree()
    local bestBySpec = GetBestBuildPerSpec(classData)
    local playerLevel = GetEffectivePlayerLevel()

    local results = {}
    for _, entry in pairs(bestBySpec) do
        local specEnabled = SimulateX_DB.disabledSpecs == nil
            or not SimulateX_DB.disabledSpecs[entry.build.specLabel or entry.build.spec]
        if specEnabled then
            local evaluations = EvaluateBuild(itemLink, itemId, equipLoc, entry.buildId, entry.build, playerLevel, gameClassName)
            if evaluations then
                local isActive = (entry.build.talentTree == activeTree)
                for _, evaluation in ipairs(evaluations) do
                    evaluation.isActive = isActive
                    table.insert(results, evaluation)
                end
            end
        end
    end

    table.sort(results, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        return a.specLabel < b.specLabel
    end)
    return results
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
    if hasOtherUpgrade then return "other" end
    return nil
end

-- mode: "header" (línea principal, spec activa, primera métrica: "SimulateX
-- · Spec (tu spec)  ..."), "secondary" (misma spec activa, métrica extra de
-- tanque: solo el valor, indentado bajo la línea principal), "compact"
-- (otras specs, una línea corta cada una).
local function FormatEvaluationLine(evaluation, mode)
    local sign = evaluation.gain >= 0 and "+" or ""
    local sourceLabel = evaluation.isExact and "simulado" or "estimado"
    local valueText
    if evaluation.isNoise then
        valueText = "≈ igual"
    else
        local unit = evaluation.isExact and evaluation.metricLabel or "pts"
        valueText = string.format("%s%.1f %%  (%s%.0f %s)", sign, evaluation.percent, sign, evaluation.gain, unit)
    end

    if mode == "header" then
        return string.format("SimulateX · %s (%s)       %s   %s",
            evaluation.specLabel, evaluation.isActive and "tu spec" or "otra spec", valueText, sourceLabel)
    end
    if mode == "secondary" then
        return string.format("%s: %s", evaluation.metricLabel, valueText)
    end
    return string.format("%s: %s%s", evaluation.specLabel,
        evaluation.isNoise and "≈ igual" or string.format("%s%.1f %%", sign, evaluation.percent),
        evaluation.isNoise and "" or (evaluation.isExact and (" " .. evaluation.metricLabel) or ""))
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

    -- La spec activa va primero (orden de GetItemEvaluations) y puede traer
    -- 1 o 2 evaluaciones (tanque: Supervivencia + Amenaza); el resto son de
    -- otras specs de la misma clase, una línea compacta cada una.
    local activeEvaluations, otherEvaluations = {}, {}
    for _, evaluation in ipairs(evaluations) do
        if evaluation.isActive then
            table.insert(activeEvaluations, evaluation)
        else
            table.insert(otherEvaluations, evaluation)
        end
    end

    if #activeEvaluations == 0 then
        return  -- la spec activa no tiene dato para este slot (ej. munición para un caster)
    end
    if activeEvaluations[1].blockedByLevel then
        return  -- bloqueado solo por nivel: dato sí existe, pero no se muestra flecha ni comparación todavía
    end

    tooltip:AddLine(FormatEvaluationLine(activeEvaluations[1], "header"), 0.6, 0.8, 1)
    if activeEvaluations[1].comparisonLabel then
        tooltip:AddLine("  vs. " .. activeEvaluations[1].comparisonLabel, 0.7, 0.7, 0.7)
    end
    for i = 2, #activeEvaluations do
        tooltip:AddLine("  " .. FormatEvaluationLine(activeEvaluations[i], "secondary"), 0.6, 0.8, 1)
    end

    if #otherEvaluations > 0 then
        local otherParts = {}
        for _, evaluation in ipairs(otherEvaluations) do
            table.insert(otherParts, FormatEvaluationLine(evaluation, "compact"))
        end
        tooltip:AddLine("  Otras: " .. table.concat(otherParts, ", "), 0.6, 0.6, 0.6)
    end

    tooltip:Show()
end

--[[----------------------------------------------------------------------
    ICONO OVERLAY (hooks ya verificados, conservados de v0.2.1): superpone
    la flecha de mejora sobre bolsas/botín/recompensa de misión.
------------------------------------------------------------------------]]

-- Flecha del botón de subir planta del mapa del mundo: 3.3.5a no tiene flecha
-- de mejora nativa (eso es de retail).
local UPGRADE_ARROW_TEXTURE = "Interface\\Buttons\\Arrow-Up-Up"

-- Marco hijo con nivel superior al botón para que la flecha quede por encima
-- de su borde (NormalTexture); la silueta negra algo mayor hace de contorno.
local function CreateUpgradeIcon(button)
    local holder = CreateFrame("Frame", nil, button)
    holder:SetFrameLevel(button:GetFrameLevel() + 2)
    holder:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)

    local shadow = holder:CreateTexture(nil, "ARTWORK")
    shadow:SetTexture(UPGRADE_ARROW_TEXTURE)
    shadow:SetVertexColor(0, 0, 0, 0.9)
    shadow:SetPoint("TOPLEFT", holder, "TOPLEFT", -2, 2)
    shadow:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 2, -2)

    local arrow = holder:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(UPGRADE_ARROW_TEXTURE)
    arrow:SetDesaturated(true)  -- sin soporte de shader queda dorada teñida, sigue viéndose
    arrow:SetAllPoints(holder)
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

    if marker == "active" then
        icon.arrow:SetVertexColor(0.1, 1, 0.1)
        icon:SetSize(20, 20)
        icon:Show()
    elseif marker == "other" then
        icon.arrow:SetVertexColor(1, 0.55, 0)
        icon:SetSize(15, 15)
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

-- Redibuja los overlays de todas las bolsas/banco/vendedor abiertos: usado
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
end

--[[----------------------------------------------------------------------
    REFRESCO: PLAYER_EQUIPMENT_CHANGED, PLAYER_LEVEL_UP, PLAYER_TALENT_UPDATE
    vacían la caché de usabilidad y redibujan las ventanas abiertas (el
    equipo/nivel/talentos cambiados invalidan las comparaciones ya hechas).
------------------------------------------------------------------------]]

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        SimulateX_DB = SimulateX_DB or {}
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
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_LEVEL_UP" or event == "PLAYER_TALENT_UPDATE" then
        ClearUsabilityCache()
        RefreshOpenContainers()
    elseif event == "SKILL_LINES_CHANGED" then
        ClearUsabilityCache()
    end
end

SimulateX:RegisterEvent("ADDON_LOADED")
SimulateX:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
SimulateX:RegisterEvent("PLAYER_LEVEL_UP")
SimulateX:RegisterEvent("PLAYER_TALENT_UPDATE")
SimulateX:RegisterEvent("SKILL_LINES_CHANGED")
SimulateX:SetScript("OnEvent", OnEvent)

--[[----------------------------------------------------------------------
    DEPURACIÓN: /simulatex debug + link muestra las claves de GetItemStats,
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
    print("  Bloqueado solo por nivel: " .. tostring(IsBlockedByLevelOnly(itemLink)))

    local stats = GetItemStats(itemLink) or {}
    local statKeys = {}
    for key in pairs(stats) do table.insert(statKeys, key) end
    table.sort(statKeys)
    print("  GetItemStats: " .. (#statKeys > 0 and table.concat(statKeys, ", ") or "(sin estadísticas)"))
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
    for _, evaluation in ipairs(evaluations) do
        print(string.format("  %s%s [%s]: ganancia %.2f, %.1f%% %s%s%s",
            evaluation.isActive and "*" or "", evaluation.specLabel, evaluation.metricLabel,
            evaluation.gain, evaluation.percent, evaluation.isExact and "(simulado)" or "(estimado)",
            evaluation.isNoise and " ≈igual" or "", evaluation.blockedByLevel and " [bloqueado por nivel]" or ""))
    end
end

SLASH_SIMULATEX1 = "/simulatex"
SlashCmdList["SIMULATEX"] = function(msg)
    msg = msg and msg:trim() or ""
    local command, rest = msg:match("^(%S*)%s*(.-)$")
    command = command:lower()

    if command == "debug" then
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
        ClearUsabilityCache()
        RefreshOpenContainers()
    elseif msg == "" then
        SimulateX_DB.forcedBuild = nil
        print("SimulateX: detección automática de build activada.")
    else
        SimulateX_DB.forcedBuild = msg
        print("SimulateX: build forzada a '" .. msg .. "'.")
    end
end
