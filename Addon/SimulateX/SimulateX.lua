local ADDON_NAME = ...

local SimulateX = CreateFrame("Frame", "SimulateXFrame")

local CLASS_DATA_VARS = {
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

-- Agrupa las builds de la clase por árbol de talentos (sub-spec) y devuelve,
-- de cada grupo, la de fase de contenido más alta disponible: una entrada por
-- sub-spec real de la clase (ej. Beast Mastery/Marksman/Survival en Cazador),
-- no solo la detectada como activa. Si el usuario forzó una build manual
-- (SimulateX_DB.forcedBuild), esa sustituye a la de su mismo árbol.
local function GetBestBuildPerSpec(classData)
    local bestBySpec = {}
    for buildId, build in pairs(classData.builds) do
        local key = build.talentTree or build.specLabel
        local current = bestBySpec[key]
        if not current or (build.phase or -1) > (current.build.phase or -1) then
            bestBySpec[key] = { buildId = buildId, build = build }
        end
    end

    if SimulateX_DB.forcedBuild and classData.builds[SimulateX_DB.forcedBuild] then
        local forced = classData.builds[SimulateX_DB.forcedBuild]
        local key = forced.talentTree or forced.specLabel
        bestBySpec[key] = { buildId = SimulateX_DB.forcedBuild, build = forced }
    end

    return bestBySpec
end

local function GetItemDeltasBySpec(itemId)
    local classFileName = select(2, UnitClass("player"))
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData then
        return nil
    end

    local activeTree = GetActiveTalentTree()
    local bestBySpec = GetBestBuildPerSpec(classData)

    local results = {}
    for _, entry in pairs(bestBySpec) do
        local itemData = entry.build.items[itemId]
        if itemData and (itemData.dps ~= 0 or itemData.hps ~= 0) then
            table.insert(results, {
                specLabel = entry.build.specLabel,
                role = entry.build.role,
                isActive = (entry.build.talentTree == activeTree),
                dps = itemData.dps,
                hps = itemData.hps,
                baseDps = entry.build.baseDps,
                baseHps = entry.build.baseHps,
            })
        end
    end

    table.sort(results, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        return a.specLabel < b.specLabel
    end)
    return results
end

local EQUIP_LOC_TO_SLOT = {
    INVTYPE_HEAD = "HeadSlot", INVTYPE_NECK = "NeckSlot", INVTYPE_SHOULDER = "ShoulderSlot",
    INVTYPE_CLOAK = "BackSlot", INVTYPE_CHEST = "ChestSlot", INVTYPE_ROBE = "ChestSlot",
    INVTYPE_WRIST = "WristSlot", INVTYPE_HAND = "HandsSlot", INVTYPE_WAIST = "WaistSlot",
    INVTYPE_LEGS = "LegsSlot", INVTYPE_FEET = "FeetSlot", INVTYPE_FINGER = "Finger0Slot",
    INVTYPE_TRINKET = "Trinket0Slot", INVTYPE_WEAPON = "MainHandSlot",
    INVTYPE_2HWEAPON = "MainHandSlot", INVTYPE_WEAPONMAINHAND = "MainHandSlot",
    INVTYPE_WEAPONOFFHAND = "SecondaryHandSlot", INVTYPE_SHIELD = "SecondaryHandSlot",
    INVTYPE_HOLDABLE = "SecondaryHandSlot", INVTYPE_RANGED = "RangedSlot",
    INVTYPE_RANGEDRIGHT = "RangedSlot", INVTYPE_THROWN = "RangedSlot",
}

-- Compara el score de un objeto de nivel bajo contra el que ya lleva puesto
-- el jugador en su slot equivalente. Es una estimación por prioridad de
-- estadísticas (ver Tools/calcular_score_bajo_nivel.py), no una simulación de
-- combate: para nivel 80 sí hay dato preciso, para 1-79 no existe forma de
-- simular con esta precisión, así que se avisa explícitamente en el tooltip.
local function GetLowLevelComparison(itemId, itemLink)
    local classFileName = select(2, UnitClass("player"))
    local dataVarName = CLASS_DATA_VARS[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData or not classData.lowLevelScores then
        return nil
    end

    local itemScore = classData.lowLevelScores[itemId]
    if not itemScore then
        return nil
    end

    local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemLink)
    local slot = equipLoc and EQUIP_LOC_TO_SLOT[equipLoc]
    if not slot then
        return itemScore.score, nil
    end

    local equippedLink = GetInventoryItemLink("player", GetInventorySlotInfo(slot))
    if not equippedLink then
        return itemScore.score, nil
    end
    local equippedId = tonumber(equippedLink:match("item:(%d+)"))
    local equippedScore = equippedId and classData.lowLevelScores[equippedId]

    return itemScore.score, equippedScore and equippedScore.score or nil
end

local function OnTooltipSetItem(tooltip)
    local _, link = tooltip:GetItem()
    if not link then
        return
    end
    local itemId = tonumber(link:match("item:(%d+)"))
    if not itemId then
        return
    end

    if UnitLevel("player") < 80 then
        local score, equippedScore = GetLowLevelComparison(itemId, link)
        if score then
            if equippedScore then
                tooltip:AddLine(string.format("SimulateX (estimado): %+.0f frente a equipado", score - equippedScore), 0.6, 0.8, 1)
            else
                tooltip:AddLine(string.format("SimulateX (estimado): %.0f puntos", score), 0.6, 0.8, 1)
            end
        end
        return
    end

    local deltasBySpec = GetItemDeltasBySpec(itemId)
    if not deltasBySpec or #deltasBySpec == 0 then
        return
    end

    for _, entry in ipairs(deltasBySpec) do
        local value, base, unit
        if entry.role == "heal" then
            value, base, unit = entry.hps, entry.baseHps, "HPS"
        else
            value, base, unit = entry.dps, entry.baseDps, "DPS"
        end

        local percent = (base and base ~= 0) and (value / base * 100) or 0
        local marker = entry.isActive and "*" or ""
        local r, g, b = 0.2, 1, 0.2
        if value < 0 then r, g, b = 1, 0.3, 0.3 end

        tooltip:AddLine(string.format("%s%s: %+.0f %s (%+.1f%%)", marker, entry.specLabel, value, unit, percent), r, g, b)
    end
end

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        SimulateX_DB = SimulateX_DB or {}
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
end

SimulateX:RegisterEvent("ADDON_LOADED")
SimulateX:SetScript("OnEvent", OnEvent)

SLASH_SIMULATEX1 = "/simulatex"
SlashCmdList["SIMULATEX"] = function(msg)
    msg = msg and msg:trim() or ""
    if msg == "" then
        SimulateX_DB.forcedBuild = nil
        print("SimulateX: detección automática de build activada.")
    else
        SimulateX_DB.forcedBuild = msg
        print("SimulateX: build forzada a '" .. msg .. "'.")
    end
end
