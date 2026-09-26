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

-- Determina, de entre las builds disponibles para la clase del jugador, cuál
-- coincide con su árbol de talentos dominante (más puntos invertidos). Si el
-- usuario ha forzado una build manualmente (SimulateX_DB.forcedBuild), esa
-- tiene prioridad sobre la detección automática.
local function GetActiveBuildId(classData)
    if SimulateX_DB.forcedBuild and classData.builds[SimulateX_DB.forcedBuild] then
        return SimulateX_DB.forcedBuild
    end

    local bestTree, bestPoints = nil, -1
    for tabIndex = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(tabIndex)
        if pointsSpent and pointsSpent > bestPoints then
            bestTree, bestPoints = tabIndex - 1, pointsSpent
        end
    end
    if not bestTree then
        return nil
    end

    local chosenBuildId, chosenPhase = nil, -1
    for buildId, build in pairs(classData.builds) do
        if build.talentTree == bestTree and (build.phase or -1) > chosenPhase then
            chosenBuildId, chosenPhase = buildId, build.phase or -1
        end
    end
    return chosenBuildId
end

local function GetItemDelta(itemId)
    local classFileName = select(2, UnitClass("player"))
    local dataVarName = CLASS_DATA_VARS[classFileName]
    if not dataVarName then
        return nil
    end

    local classData = _G[dataVarName]
    if not classData then
        return nil
    end

    local buildId = GetActiveBuildId(classData)
    if not buildId then
        return nil
    end

    local build = classData.builds[buildId]
    local itemData = build.items[itemId]
    if not itemData then
        return nil
    end

    return itemData, build.role
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

    local itemData, role = GetItemDelta(itemId)
    if not itemData then
        return
    end

    if role == "heal" and itemData.hps ~= 0 then
        tooltip:AddLine(string.format("SimulateX: %+.0f HPS", itemData.hps), 0.2, 1, 0.2)
    elseif itemData.dps ~= 0 then
        tooltip:AddLine(string.format("SimulateX: %+.0f DPS", itemData.dps), 0.2, 1, 0.2)
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
