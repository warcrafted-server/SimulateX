--[[----------------------------------------------------------------------
    Pestaña Mejoras (v0.10, lista de la compra): por hueco, las mejores
    mejoras para la spec activa y dónde conseguirlas. Orígenes en el
    sub-addon SimulateX_Origenes (Tools/generar_origenes.py), que se carga
    al abrir la pestaña. El cálculo es el del tooltip (SimulateX_API).
------------------------------------------------------------------------]]

local ORIGINS_ADDON = "SimulateX_Origenes"
local LEVELS_BEHIND = 10
local ITEMS_PER_FRAME = 120
local ROW_HEIGHT = 34
local HEADER_ROW_HEIGHT = 22
local ICON_SIZE = 28
local MAX_ORIGINS_IN_ROW = 2

-- Grupos de huecos en el orden de la hoja de personaje; el nombre sale de
-- las cadenas del cliente (INVTYPE_*), ya traducidas.
local SLOT_GROUPS = {
    { "INVTYPE_HEAD" }, { "INVTYPE_NECK" }, { "INVTYPE_SHOULDER" }, { "INVTYPE_CLOAK" },
    { "INVTYPE_CHEST", "INVTYPE_ROBE" }, { "INVTYPE_WRIST" }, { "INVTYPE_HAND" }, { "INVTYPE_WAIST" },
    { "INVTYPE_LEGS" }, { "INVTYPE_FEET" }, { "INVTYPE_FINGER" }, { "INVTYPE_TRINKET" },
    { "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON" },
    { "INVTYPE_WEAPONOFFHAND", "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" },
    { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" },
}
local GROUP_OF_EQUIPLOC = {}
for index, group in ipairs(SLOT_GROUPS) do
    for _, equipLoc in ipairs(group) do
        GROUP_OF_EQUIPLOC[equipLoc] = index
    end
end

-- INVTYPE_WEAPONOFFHAND solo se lleva con doble empuñadura
local DUAL_WIELD_CLASSES = { WARRIOR = true, ROGUE = true, HUNTER = true, DEATHKNIGHT = true, SHAMAN = true }

-- Tipo de armadura principal (códigos de SimulateX_ItemTypes: 401 tela, 402
-- cuero, 403 malla, 404 placas): { antes de 40, desde 40 }
local MAIN_ARMOR = {
    WARRIOR = { 403, 404 }, PALADIN = { 403, 404 }, DEATHKNIGHT = { 404, 404 },
    HUNTER = { 402, 403 }, SHAMAN = { 402, 403 }, ROGUE = { 402, 402 }, DRUID = { 402, 402 },
    PRIEST = { 401, 401 }, MAGE = { 401, 401 }, WARLOCK = { 401, 401 },
}
local ARMOR_TYPE_CODES = { [401] = true, [402] = true, [403] = true, [404] = true }

local DIFFICULTY_TEXT = {
    N = "normal", H = "heroico",
    ["10"] = "10 jug.", ["25"] = "25 jug.", ["10H"] = "10 jug. heroico", ["25H"] = "25 jug. heroico",
}
local HEROIC_LABELS = { H = true, ["10H"] = true, ["25H"] = true }
local RAID25_LABELS = { ["25"] = true, ["25H"] = true }

local page, statusText, scrollFrame, content
local playerProfessions = {}  -- línea de habilidad -> rango, al empezar cada cálculo
local headerRows, itemRows = {}, {}
local job  -- cálculo en curso
local results  -- [grupo] = { {id, evaluation, origins}, ... }
local dirty = true

--[[----------------------------------------------------------------------
    ORÍGENES: "tipo+campos" separados por ";" (formato en el generador).
------------------------------------------------------------------------]]

local function Split(text, separator)
    local parts = {}
    for part in (text .. separator):gmatch("(.-)" .. separator:gsub("%p", "%%%0")) do
        table.insert(parts, part)
    end
    return parts
end

local function ParseOrigin(token)
    local kind, rest = token:sub(1, 1), token:sub(2)
    local f = Split(rest, ":")
    if kind == "j" or kind == "c" then
        return { kind = kind, id = tonumber(f[1]), map = tonumber(f[2]), label = f[3], chance = tonumber(f[4]),
            zone = tonumber(f[5]) }
    elseif kind == "m" then
        return { kind = kind, id = tonumber(f[1]), map = tonumber(f[2]), label = f[3], chance = tonumber(f[4]),
            count = tonumber(f[5]), zone = tonumber(f[6]) }
    elseif kind == "r" then
        return { kind = kind, id = tonumber(f[1]), map = tonumber(f[2]), label = "", chance = tonumber(f[3]),
            zone = tonumber(f[4]) }
    elseif kind == "v" then
        local currencies = {}
        for _, pair in ipairs(f[7] ~= "" and Split(f[7], "+") or {}) do
            local itemId, count = pair:match("(%d+)x(%d+)")
            table.insert(currencies, { tonumber(itemId), tonumber(count) })
        end
        return { kind = kind, id = tonumber(f[1]), faction = tonumber(f[2]), copper = tonumber(f[3]),
            honor = tonumber(f[4]), arena = tonumber(f[5]), rating = tonumber(f[6]), currencies = currencies,
            zone = tonumber(f[8]) }
    elseif kind == "q" then
        return { kind = kind, id = tonumber(f[1]), level = tonumber(f[2]), faction = tonumber(f[3]),
            zone = tonumber(f[4]) }
    elseif kind == "p" then
        return { kind = kind, skill = tonumber(f[1]), rank = tonumber(f[2]), recipe = tonumber(f[3]) }
    elseif kind == "b" then
        return { kind = kind, id = tonumber(f[1]), chance = tonumber(f[2]) }
    elseif kind == "w" then
        return { kind = kind }
    end
end

-- Orígenes de una receta o bolsa (SimulateX_OrigenesIntermedios)
local intermediateCache = {}
local function IntermediateOrigins(itemId)
    local cached = intermediateCache[itemId]
    if not cached then
        cached = {}
        local data = SimulateX_OrigenesIntermedios and SimulateX_OrigenesIntermedios[itemId]
        for _, token in ipairs(data and Split(data, ";") or {}) do
            table.insert(cached, ParseOrigin(token))
        end
        intermediateCache[itemId] = cached
    end
    return cached
end

-- Profesiones del personaje: nombre del cliente (GetSkillLineInfo) casado
-- con el del hechizo de cada profesión, que el cliente da ya traducido.
local function ReadPlayerProfessions()
    local skillByName = {}
    for skill, spell in pairs(SimulateX_OrigenesProfesiones or {}) do
        local name = GetSpellInfo(spell)
        if name then
            skillByName[name] = skill
        end
    end
    local result = {}
    for index = 1, GetNumSkillLines() do
        local name, isHeader, _, rank = GetSkillLineInfo(index)
        if not isHeader and skillByName[name] then
            result[skillByName[name]] = rank
        end
    end
    return result
end

local function ProfessionName(skill)
    local spell = SimulateX_OrigenesProfesiones and SimulateX_OrigenesProfesiones[skill]
    return spell and GetSpellInfo(spell) or "Profesión"
end

local function PlayerFaction()
    local group = UnitFactionGroup("player")
    return group == "Alliance" and 1 or group == "Horde" and 2 or 0
end

local function OriginAllowed(origin, playerFaction)
    local db = SimulateX_DB
    if origin.faction and origin.faction ~= 0 and origin.faction ~= playerFaction and not db.upgradesOtherFaction then
        return false
    end
    if origin.kind == "w" then
        return true
    end
    if origin.kind == "p" then
        if db.upgradesNoProfessions or (db.upgradesOnlyMyProfessions and not playerProfessions[origin.skill]) then
            return false
        end
        if not origin.recipe then
            return true  -- instructor
        end
        for _, recipeOrigin in ipairs(IntermediateOrigins(origin.recipe)) do
            if OriginAllowed(recipeOrigin, playerFaction) then
                return true
            end
        end
        return false
    end
    if origin.kind == "b" then
        if (origin.chance or 0) < (db.upgradesMinChance or 1) then
            return false
        end
        for _, bagOrigin in ipairs(IntermediateOrigins(origin.id)) do
            if OriginAllowed(bagOrigin, playerFaction) then
                return true
            end
        end
        return false
    end
    if origin.kind == "v" then
        return not db.upgradesNoVendors
    end
    if origin.kind == "q" then
        return not db.upgradesNoQuests
    end
    if db.upgradesNoHeroic and HEROIC_LABELS[origin.label] then
        return false
    end
    if db.upgradesNo25 and RAID25_LABELS[origin.label] then
        return false
    end
    return (origin.chance or 0) >= (db.upgradesMinChance or 1)
end

local function Name(kind, id)
    local names = SimulateX_OrigenesNombres
    local list = names and names[kind]
    return list and list[id] or "?"
end

-- Instancia (por el mapa) o zona del mundo, en esES del cliente; nil si no se sabe
local function PlaceName(origin)
    local names = SimulateX_OrigenesNombres
    if not names then return nil end
    return (origin.map and names.mapas and names.mapas[origin.map])
        or (origin.zone and origin.zone > 0 and names.zonas and names.zonas[origin.zone]) or nil
end

local function WithDetails(text, origin)
    local parts = { text }
    local place = PlaceName(origin)
    if place then
        table.insert(parts, place)
    end
    if origin.label and DIFFICULTY_TEXT[origin.label] then
        table.insert(parts, DIFFICULTY_TEXT[origin.label])
    end
    if origin.chance then
        table.insert(parts, string.format("%s %%", origin.chance))
    end
    return table.concat(parts, " · ")
end

local function CostText(origin)
    local parts = {}
    if origin.copper and origin.copper > 0 then
        table.insert(parts, GetCoinTextureString(origin.copper))
    end
    for _, currency in ipairs(origin.currencies) do
        local icon = GetItemIcon(currency[1])
        local name = GetItemInfo(currency[1]) or Name("objetos", currency[1])
        table.insert(parts, icon and string.format("%d |T%s:0|t", currency[2], icon) or string.format("%d %s", currency[2], name))
    end
    if origin.honor > 0 then
        table.insert(parts, string.format("%d honor", origin.honor))
    end
    if origin.arena > 0 then
        table.insert(parts, string.format("%d arena", origin.arena))
    end
    if origin.rating > 0 then
        table.insert(parts, string.format("índice %d", origin.rating))
    end
    return table.concat(parts, " + ")
end

-- Nombre de las monedas para el tooltip, donde el icono solo no basta
local function CurrencyNames(origin)
    local names = {}
    for _, currency in ipairs(origin.currencies) do
        table.insert(names, GetItemInfo(currency[1]) or Name("objetos", currency[1]))
    end
    return table.concat(names, ", ")
end

local function OriginText(origin)
    local kind = origin.kind
    if kind == "j" then
        return WithDetails("Jefe: " .. Name("criaturas", origin.id), origin)
    elseif kind == "m" then
        if origin.id == 0 then
            return WithDetails(string.format("Varias criaturas (%d)", origin.count or 0), origin)
        end
        return WithDetails(Name("criaturas", origin.id), origin)
    elseif kind == "r" then
        return WithDetails("Raro: " .. Name("criaturas", origin.id), origin)
    elseif kind == "c" then
        return WithDetails("Cofre: " .. Name("cofres", origin.id), origin)
    elseif kind == "v" then
        local place = PlaceName(origin)
        return "Vendedor: " .. Name("criaturas", origin.id) .. (place and (" (" .. place .. ")") or "")
            .. " · " .. CostText(origin)
    elseif kind == "q" then
        local place = PlaceName(origin)
        return string.format("Misión: %s (nivel %d)", Name("misiones", origin.id), origin.level)
            .. (place and (" · " .. place) or "")
    elseif kind == "p" then
        local text = string.format("%s (%d)", ProfessionName(origin.skill), origin.rank)
        local have = playerProfessions[origin.skill]
        if have and have < origin.rank then
            text = text .. string.format(" |cffff6060tienes %d|r", have)
        end
        if origin.recipe then
            return text .. " · receta: " .. Name("objetos", origin.recipe)
        end
        return text .. " · instructor"
    elseif kind == "b" then
        return WithDetails("Dentro de: " .. Name("objetos", origin.id), origin)
    elseif kind == "w" then
        return "botín de mundo (subasta)"
    end
    return "?"
end

-- Líneas extra del tooltip: de dónde sale la receta o la bolsa
local function IntermediateLines(origin)
    local itemId = origin.kind == "p" and origin.recipe or origin.kind == "b" and origin.id
    local lines = {}
    if itemId then
        for _, sub in ipairs(IntermediateOrigins(itemId)) do
            table.insert(lines, OriginText(sub))
        end
    end
    return lines
end

--[[----------------------------------------------------------------------
    CÁLCULO: candidatos (nivel, facción, orígenes permitidos) y evaluación
    por tandas en OnUpdate, para no congelar el cliente.
------------------------------------------------------------------------]]

local function CollectCandidates(context)
    local db = SimulateX_DB
    local level = context.playerLevel
    local maxLevel = level + (db.upgradesLevelsAhead or 2)
    local playerFaction = PlayerFaction()
    local candidates = {}

    for itemId, data in pairs(SimulateX_Origenes) do
        local req, _, _, faction, skill, sources = data:match("^(%d+),(%d+),(%d+),(%d+),(%d+)|(.*)$")
        req, faction, skill = tonumber(req), tonumber(faction), tonumber(skill)
        -- skill: profesión sin la que no se puede llevar (gafas de ingeniero...)
        if req and req > 0 and req <= maxLevel and req >= level - LEVELS_BEHIND
            and (faction == 0 or faction == playerFaction or db.upgradesOtherFaction)
            and (skill == 0 or playerProfessions[skill]) then
            local origins = {}
            for _, token in ipairs(Split(sources, ";")) do
                local origin = ParseOrigin(token)
                if origin and OriginAllowed(origin, playerFaction) then
                    table.insert(origins, origin)
                end
            end
            if #origins > 0 then
                table.insert(candidates, { id = itemId, origins = origins })
            end
        end
    end

    -- Objetos simulados de nivel 80 que no salen de ningún sitio registrado
    -- (profesiones, subasta...): también cuentan si la opción lo permite
    if level >= 80 and context.build.items and not db.upgradesNoUnknownOrigin then
        for itemId in pairs(context.build.items) do
            if not SimulateX_Origenes[itemId] then
                table.insert(candidates, { id = itemId, origins = {} })
            end
        end
    end
    return candidates
end

local function InsertTop(list, entry, limit)
    local position = #list + 1
    for index, other in ipairs(list) do
        if entry.evaluation.percent > other.evaluation.percent then
            position = index
            break
        end
    end
    if position <= limit then
        table.insert(list, position, entry)
        list[limit + 1] = nil
    end
end

local Render, StartJob

local function StepJob(self)
    local finish = math.min(job.next + ITEMS_PER_FRAME - 1, #job.candidates)
    for index = job.next, finish do
        local candidate = job.candidates[index]
        local link = "item:" .. candidate.id .. ":0:0:0:0:0:0:0"
        local _, equipLoc = SimulateX_API.GetItemBasics(link)
        local group = equipLoc and GROUP_OF_EQUIPLOC[equipLoc]
        local typeCode = SimulateX_ItemTypes and SimulateX_ItemTypes[candidate.id]
        local wrongArmor = job.mainArmor and equipLoc ~= "INVTYPE_CLOAK"
            and ARMOR_TYPE_CODES[typeCode] and typeCode ~= job.mainArmor
        if group and not wrongArmor and (equipLoc ~= "INVTYPE_WEAPONOFFHAND" or job.dualWield) then
            local evaluation = SimulateX_API.EvaluateForContext(job.context, link)
            if evaluation and evaluation.gain > 0 and not evaluation.isNoise then
                job.results[group] = job.results[group] or {}
                candidate.evaluation = evaluation
                InsertTop(job.results[group], candidate, job.limit)
            end
        end
    end
    job.next = finish + 1
    if job.next > #job.candidates then
        self:SetScript("OnUpdate", nil)
        results, job = job.results, nil
        if dirty then
            StartJob()  -- algo cambió mientras se calculaba
        else
            Render()
        end
    else
        statusText:SetText(string.format("Calculando... %d %%", math.floor((job.next - 1) * 100 / #job.candidates)))
    end
end

function StartJob()
    if not SimulateX_Origenes then
        local loaded, reason = LoadAddOn(ORIGINS_ADDON)
        if not loaded then
            statusText:SetText("No se ha podido cargar " .. ORIGINS_ADDON .. " (" .. tostring(reason) .. ").")
            return
        end
    end
    local context = SimulateX_API.GetActiveSpecContext()
    if not context then
        statusText:SetText("No hay datos de simulación para tu clase.")
        return
    end
    playerProfessions = ReadPlayerProfessions()
    job = {
        context = context,
        candidates = CollectCandidates(context),
        next = 1,
        results = {},
        limit = SimulateX_DB.upgradesPerSlot or 3,
        dualWield = DUAL_WIELD_CLASSES[select(2, UnitClass("player"))],
    }
    local armor = MAIN_ARMOR[select(2, UnitClass("player"))]
    if armor and not SimulateX_DB.upgradesAnyArmor then
        job.mainArmor = context.playerLevel >= 40 and armor[2] or armor[1]
    end
    results = nil
    dirty = false
    Render()
    page:SetScript("OnUpdate", StepJob)
end

--[[----------------------------------------------------------------------
    FILAS
------------------------------------------------------------------------]]

local function ItemLink(itemId)
    local _, link = GetItemInfo(itemId)
    return link
end

local function ShowRowTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. row.itemId .. ":0:0:0:0:0:0:0")
    if #row.origins > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Dónde conseguirlo:", 1, 0.82, 0)
        for _, origin in ipairs(row.origins) do
            GameTooltip:AddLine(OriginText(origin), 0.9, 0.9, 0.9, true)
            if origin.kind == "v" and #origin.currencies > 0 then
                GameTooltip:AddLine("   " .. CurrencyNames(origin), 0.6, 0.6, 0.6, true)
            end
            for _, line in ipairs(IntermediateLines(origin)) do
                GameTooltip:AddLine("   ← " .. line, 0.6, 0.6, 0.6, true)
            end
        end
    end
    GameTooltip:Show()
end

local function CreateItemRow()
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(1, 1, 1, 0.06)
    highlight:SetAllPoints()

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ICON_SIZE)
    row.icon:SetHeight(ICON_SIZE)
    row.icon:SetPoint("LEFT", 8, 0)

    row.percent = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.percent:SetPoint("TOPRIGHT", -6, -3)
    row.percent:SetWidth(70)
    row.percent:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.percent, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")

    row.origin = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    row.origin:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
    row.origin:SetPoint("RIGHT", -6, 0)
    row.origin:SetJustifyH("LEFT")

    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Mayús+clic al chat y Ctrl+clic al probador, como en el juego; solo con
    -- el link real del cliente (nunca uno montado a mano)
    row:SetScript("OnClick", function(self)
        local link = ItemLink(self.itemId)
        if link then
            HandleModifiedItemClick(link)
        end
    end)
    return row
end

local function CreateHeaderRow()
    local header = CreateFrame("Frame", nil, content)
    header:SetHeight(HEADER_ROW_HEIGHT)
    header.text = header:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header.text:SetPoint("BOTTOMLEFT", 2, 3)
    header.line = header:CreateTexture(nil, "ARTWORK")
    header.line:SetTexture(1, 0.82, 0, 0.3)
    header.line:SetHeight(1)
    header.line:SetPoint("BOTTOMLEFT", 0, 0)
    header.line:SetPoint("BOTTOMRIGHT", 0, 0)
    return header
end

local function FillItemRow(row, entry, level)
    row.itemId = entry.id
    row.origins = entry.origins
    row.icon:SetTexture(GetItemIcon(entry.id) or "Interface\\Icons\\INV_Misc_QuestionMark")

    local cachedName, _, cachedQuality = GetItemInfo(entry.id)
    local data = SimulateX_Origenes[entry.id]
    local quality = cachedQuality or (data and tonumber(data:match("^%d+,%d+,(%d+),"))) or 1
    local color = ITEM_QUALITY_COLORS[quality] or ITEM_QUALITY_COLORS[1]
    local name = cachedName or Name("objetos", entry.id)
    local notes = {}
    local req = data and tonumber(data:match("^(%d+),"))
    if req and req > level then
        table.insert(notes, "nivel " .. req)
    end
    if GetItemCount(entry.id, true) > 0 then
        table.insert(notes, "ya lo tienes")
    end
    if #notes > 0 then
        name = name .. "|cff999999  (" .. table.concat(notes, ", ") .. ")|r"
    end
    row.name:SetText(color.hex .. name .. "|r")

    row.percent:SetText(string.format("%+.1f %%", entry.evaluation.percent))
    row.percent:SetTextColor(0.2, 1, 0.2)

    local texts = {}
    for index = 1, math.min(#entry.origins, MAX_ORIGINS_IN_ROW) do
        table.insert(texts, OriginText(entry.origins[index]))
    end
    if #entry.origins > MAX_ORIGINS_IN_ROW then
        table.insert(texts, string.format("y %d más", #entry.origins - MAX_ORIGINS_IN_ROW))
    end
    row.origin:SetText(#texts > 0 and table.concat(texts, "  ·  ") or "Origen no registrado (profesiones, subasta...)")
end

function Render()
    for _, row in ipairs(headerRows) do row:Hide() end
    for _, row in ipairs(itemRows) do row:Hide() end
    if job then
        statusText:SetText("Calculando...")
        return
    end
    if not results then
        return
    end

    local context = SimulateX_API.GetActiveSpecContext()
    local level = context and context.playerLevel or UnitLevel("player")
    local width = scrollFrame:GetWidth()
    local y, headerIndex, itemIndex, total = 0, 0, 0, 0
    for groupIndex, group in ipairs(SLOT_GROUPS) do
        local entries = results[groupIndex]
        if entries and #entries > 0 then
            headerIndex = headerIndex + 1
            local header = headerRows[headerIndex] or CreateHeaderRow()
            headerRows[headerIndex] = header
            header:SetWidth(width)
            header:SetPoint("TOPLEFT", 0, -y)
            header.text:SetText(_G[group[1]] or group[1])
            header:Show()
            y = y + HEADER_ROW_HEIGHT + 2
            for _, entry in ipairs(entries) do
                itemIndex = itemIndex + 1
                local row = itemRows[itemIndex] or CreateItemRow()
                itemRows[itemIndex] = row
                row:SetWidth(width)
                row:SetPoint("TOPLEFT", 0, -y)
                FillItemRow(row, entry, level)
                row:Show()
                y = y + ROW_HEIGHT
                total = total + 1
            end
            y = y + 8
        end
    end
    content:SetHeight(math.max(1, y))

    if total == 0 then
        statusText:SetText("No hay mejoras con los filtros actuales (pestaña Configuración, sección Mejoras).")
    else
        statusText:SetText(string.format("Mejoras para %s (nivel %d). Pasa el ratón por un objeto para ver todos sus orígenes.",
            context and context.specLabel or "?", level))
    end
end

--[[----------------------------------------------------------------------
    PÁGINA
------------------------------------------------------------------------]]

-- Lo llaman el equipo nuevo, los talentos y las opciones: se recalcula la
-- próxima vez que se muestre la pestaña (o ya, si está a la vista).
function SimulateX_Mejoras_MarkDirty()
    dirty = true
    if page and page:IsVisible() and not job then
        StartJob()
    end
end

function SimulateX_BuildUpgradesPage(parent)
    page = parent

    statusText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", 2, -4)
    statusText:SetPoint("RIGHT", -110, 0)
    statusText:SetJustifyH("LEFT")

    local refreshButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    refreshButton:SetWidth(100)
    refreshButton:SetHeight(22)
    refreshButton:SetPoint("TOPRIGHT", 0, 0)
    refreshButton:SetText("Recalcular")
    refreshButton:SetScript("OnClick", function()
        if not job then StartJob() end
    end)

    scrollFrame = CreateFrame("ScrollFrame", "SimulateXMejorasScroll", page, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local bar = _G[self:GetName() .. "ScrollBar"]
        bar:SetValue(bar:GetValue() - delta * ROW_HEIGHT * 2)
    end)
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(1)
    content:SetHeight(1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnSizeChanged", function(self, width)
        content:SetWidth(width)
    end)

    return {
        refresh = function()
            content:SetWidth(scrollFrame:GetWidth())
            if dirty and not job then
                StartJob()
            end
        end,
    }
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
watcher:RegisterEvent("PLAYER_LEVEL_UP")
watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
watcher:SetScript("OnEvent", function()
    SimulateX_Mejoras_MarkDirty()
end)
