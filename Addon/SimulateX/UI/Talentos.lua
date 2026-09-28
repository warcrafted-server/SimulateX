--[[----------------------------------------------------------------------
    Pestaña Talentos (v0.7): dibuja los 3 árboles reales de tu clase (datos
    de Tools/generar_arbol_talentos.py, extraídos de Talent.dbc/TalentTab.dbc
    del servidor) y marca qué puntos pone cada distribución ya simulada
    (Tools/simular_talentos.py). Un selector arriba cambia de variante.
------------------------------------------------------------------------]]

local ICON_SIZE = 26
local CELL_SIZE = 31
local TREE_COLUMNS = 4
local TREE_ROWS = 11
local NOISE_THRESHOLD_PCT = 0.3  -- mismo umbral que SimulateX.lua

local treeFrames = {}   -- 3 frames (uno por árbol), cada uno con .cells[talentIndex]
local variantTabs = {}
local currentVariantIndex = 1

local function GetTalentDataForClass()
    local classFileName = select(2, UnitClass("player"))
    local varName = SimulateX_TalentDataVars and SimulateX_TalentDataVars[classFileName]
    return varName and _G[varName]
end

local function GetTreeDataForClass()
    local classFileName = select(2, UnitClass("player"))
    local varName = SimulateX_ArbolTalentosVars and SimulateX_ArbolTalentosVars[classFileName]
    return varName and _G[varName]
end

-- "-503202132322010053120230310511-205503012" -> { [0]="", [1]="5032...", [2]="2055..." }
local function SplitTalentBlocks(talentsString)
    local blocks = { [0] = "", [1] = "", [2] = "" }
    local i = 0
    for block in (talentsString .. "-"):gmatch("([^-]*)-") do
        blocks[i] = block
        i = i + 1
        if i > 2 then break end
    end
    return blocks
end

--[[----------------------------------------------------------------------
    UN TALENTO: icono + marco + texto "n/max". Los huecos sin talento real
    (fila/columna sin entrada en la DBC) se quedan vacíos e invisibles.
------------------------------------------------------------------------]]

local function CreateTalentCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetWidth(ICON_SIZE)
    cell:SetHeight(ICON_SIZE)
    cell:EnableMouse(true)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    cell.border:SetBlendMode("ADD")
    cell.border:SetPoint("CENTER")
    cell.border:SetWidth(ICON_SIZE * 1.6)
    cell.border:SetHeight(ICON_SIZE * 1.6)
    cell.border:Hide()

    cell.count = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cell.count:SetPoint("BOTTOMRIGHT", 2, -2)
    cell.count:SetText("")

    cell:SetScript("OnEnter", function(self)
        if not self.talent then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.talent.name, 1, 1, 1)
        GameTooltip:AddLine(string.format("Rango %d / %d", self.rank or 0, self.talent.maxRank), 0.8, 0.8, 0.8)
        if self.talent.reqTalent then
            GameTooltip:AddLine("Requiere otro talento a un rango mínimo", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cell:Hide()
    return cell
end

--[[----------------------------------------------------------------------
    UN ÁRBOL: cuadrícula de TREE_ROWS x TREE_COLUMNS. Cada talento de la DBC
    ocupa su fila/columna real; sin GetSpellInfo (icono) hasta que el
    cliente lo tenga en caché, se reintenta con OnUpdate como en el resto
    del addon (3.3.5a no tiene evento GET_SPELL_INFO_RECEIVED).
------------------------------------------------------------------------]]

local function RefreshCellIcon(cell)
    local spellId = cell.talent.ranks[1]
    local name, _, icon = GetSpellInfo(spellId)
    if not name then
        if not cell.pendingIcon then
            cell.pendingIcon = true
            cell:SetScript("OnUpdate", function(self, elapsed)
                self.retryTimer = (self.retryTimer or 0) + elapsed
                if self.retryTimer < 0.3 then return end
                self.retryTimer = 0
                if GetSpellInfo(spellId) then
                    self:SetScript("OnUpdate", nil)
                    self.pendingIcon = nil
                    RefreshCellIcon(self)
                end
            end)
        end
        cell.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        return
    end
    cell.pendingIcon = nil
    cell:SetScript("OnUpdate", nil)
    cell.icon:SetTexture(icon)
end

local function CreateTreeFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetWidth(TREE_COLUMNS * CELL_SIZE)
    frame:SetHeight(TREE_ROWS * CELL_SIZE + 18)

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.title:SetPoint("TOP", 0, 0)
    frame.title:SetTextColor(1, 0.82, 0)

    frame.grid = CreateFrame("Frame", nil, frame)
    frame.grid:SetPoint("TOPLEFT", 0, -18)
    frame.grid:SetWidth(TREE_COLUMNS * CELL_SIZE)
    frame.grid:SetHeight(TREE_ROWS * CELL_SIZE)

    frame.cells = {}
    for row = 0, TREE_ROWS - 1 do
        for col = 0, TREE_COLUMNS - 1 do
            local cell = CreateTalentCell(frame.grid)
            cell:SetPoint("TOPLEFT", frame.grid, "TOPLEFT", col * CELL_SIZE + 3, -(row * CELL_SIZE) - 3)
            frame.cells[row .. "_" .. col] = cell
        end
    end
    return frame
end

-- Coloca los talentos reales de la DBC en su celda y marca los que trae
-- digits (cadena de un solo árbol, sin guiones).
local function RenderTree(frame, treeData, digits)
    frame.title:SetText(treeData.name or "")
    for _, cell in pairs(frame.cells) do
        cell.talent = nil
        cell:Hide()
    end

    for index, talent in ipairs(treeData.talents) do
        local cell = frame.cells[talent.row .. "_" .. talent.col]
        if cell then
            cell.talent = talent
            local rank = tonumber(digits and digits:sub(index, index)) or 0
            cell.rank = rank
            RefreshCellIcon(cell)
            if rank > 0 then
                cell.icon:SetDesaturated(false)
                cell.icon:SetAlpha(1)
                cell.border:Show()
                cell.count:SetText(rank .. "/" .. talent.maxRank)
                cell.count:SetTextColor(1, 0.82, 0)
            else
                cell.icon:SetDesaturated(true)
                cell.icon:SetAlpha(0.55)
                cell.border:Hide()
                cell.count:SetText("")
            end
            cell:Show()
        end
    end
end

--[[----------------------------------------------------------------------
    RESUMEN Y SELECTOR DE VARIANTE
------------------------------------------------------------------------]]

local function GetVariantTab(index)
    local tab = variantTabs[index]
    if tab then return tab end
    local parent = variantTabs.parent
    tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(20)
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    tab.label:SetPoint("CENTER")
    variantTabs[index] = tab
    return tab
end

local function HideVariantTabsFrom(index)
    for i = index, #variantTabs do variantTabs[i]:Hide() end
end

local function RenderSummary(page, specData)
    local metric = specData.metric or "dps"
    local best = 0
    for _, variant in ipairs(specData.variants) do
        best = math.max(best, variant[metric] or 0)
    end
    local current = specData.variants[currentVariantIndex]
    if not current then return end
    local value = current[metric] or 0
    local diff = best > 0 and (value / best - 1) * 100 or 0
    local isNoise = math.abs(diff) < NOISE_THRESHOLD_PCT

    page.summaryValue:SetText(string.format("%.0f", value))
    if isNoise then
        page.summaryDiff:SetText(value >= best and "referencia" or "≈ igual")
        page.summaryDiff:SetTextColor(0.65, 0.65, 0.65)
    elseif value >= best then
        page.summaryDiff:SetText("mejor")
        page.summaryDiff:SetTextColor(0.3, 1, 0.3)
    else
        page.summaryDiff:SetText(string.format("%.1f %%", diff))
        page.summaryDiff:SetTextColor(1, 0.6, 0.3)
    end

    local allTied = #specData.variants > 1
    if allTied then
        for _, variant in ipairs(specData.variants) do
            local d = best > 0 and ((variant[metric] or 0) / best - 1) * 100 or 0
            if math.abs(d) >= NOISE_THRESHOLD_PCT then allTied = false; break end
        end
    end
    if allTied then page.tiedText:Show() else page.tiedText:Hide() end
end

local function RenderPage(page, spec)
    local data = GetTalentDataForClass()
    local specData = data and data[spec]
    local treeData = GetTreeDataForClass()

    if not treeData then
        page.emptyText:SetText("SimulateX no tiene el árbol de talentos de tu clase todavía.")
        page.emptyText:Show()
        page.treesFrame:Hide()
        page.summaryFrame:Hide()
        HideVariantTabsFrom(1)
        return
    end

    if not specData or not specData.variants or #specData.variants == 0 then
        page.emptyText:SetText("Sin variantes simuladas todavía para esta especialización.")
        page.emptyText:Show()
        page.summaryFrame:Hide()
        -- sin datos de variante, el árbol se ve igualmente pero sin marcar nada
        for treeIndex = 1, 3 do
            RenderTree(treeFrames[treeIndex], treeData.trees[treeIndex], "")
        end
        page.treesFrame:Show()
        HideVariantTabsFrom(1)
        return
    end
    page.emptyText:Hide()
    page.summaryFrame:Show()
    page.treesFrame:Show()

    if currentVariantIndex > #specData.variants then
        currentVariantIndex = 1
    end

    local tabWidth = page.treesFrame:GetWidth() / #specData.variants
    for index, variant in ipairs(specData.variants) do
        local tab = GetVariantTab(index)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", page.variantBar, "TOPLEFT", (index - 1) * tabWidth, 0)
        tab:SetWidth(tabWidth - 2)
        tab.label:SetText(variant.label or ("Variante " .. index))
        local selected = (index == currentVariantIndex)
        tab.bg:SetTexture(1, 0.82, 0, selected and 0.25 or 0.06)
        tab.label:SetTextColor(selected and 1 or 0.75, selected and 1 or 0.75, selected and 0.6 or 0.75)
        tab:SetScript("OnClick", function()
            currentVariantIndex = index
            RenderPage(page, spec)
        end)
        tab:Show()
    end
    HideVariantTabsFrom(#specData.variants + 1)

    RenderSummary(page, specData)

    local current = specData.variants[currentVariantIndex]
    local blocks = SplitTalentBlocks(current.talents or "")
    for treeIndex = 1, 3 do
        RenderTree(treeFrames[treeIndex], treeData.trees[treeIndex], blocks[treeIndex - 1])
    end
end

--[[----------------------------------------------------------------------
    CONSTRUCCIÓN DE LA PÁGINA
------------------------------------------------------------------------]]

function SimulateX_BuildTalentsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetText("Árbol de talentos (mismo equipo, distinta distribución)")
    header:SetTextColor(1, 0.82, 0)

    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", page, "RIGHT", 0, 0)

    page.emptyText = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    page.emptyText:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -12)
    page.emptyText:SetPoint("RIGHT", 0, 0)
    page.emptyText:SetJustifyH("LEFT")

    -- resumen: valor de la variante actual + selector de variantes
    page.summaryFrame = CreateFrame("Frame", nil, page)
    page.summaryFrame:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
    page.summaryFrame:SetPoint("RIGHT", 0, 0)
    page.summaryFrame:SetHeight(20)

    page.summaryValue = page.summaryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    page.summaryValue:SetPoint("LEFT", 0, 0)
    page.summaryDiff = page.summaryFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    page.summaryDiff:SetPoint("LEFT", page.summaryValue, "RIGHT", 8, 0)

    page.tiedText = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    page.tiedText:SetPoint("TOPLEFT", page.summaryFrame, "BOTTOMLEFT", 0, -2)
    page.tiedText:SetPoint("RIGHT", 0, 0)
    page.tiedText:SetJustifyH("LEFT")
    page.tiedText:SetText("Todas rinden igual: los puntos libres de esta build no tienen ningún talento mejor donde ponerlos.")
    page.tiedText:SetTextColor(0.7, 0.7, 0.5)
    page.tiedText:Hide()

    -- pestañitas de variante, justo encima de los árboles
    page.variantBar = CreateFrame("Frame", nil, page)
    page.variantBar:SetPoint("TOPLEFT", page.tiedText, "BOTTOMLEFT", 0, -6)
    page.variantBar:SetPoint("RIGHT", 0, 0)
    page.variantBar:SetHeight(20)
    variantTabs.parent = page.variantBar

    -- los 3 árboles lado a lado
    page.treesFrame = CreateFrame("Frame", nil, page)
    page.treesFrame:SetPoint("TOPLEFT", page.variantBar, "BOTTOMLEFT", 0, -6)
    page.treesFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    local treeWidth = TREE_COLUMNS * CELL_SIZE
    for treeIndex = 1, 3 do
        local frame = CreateTreeFrame(page.treesFrame)
        frame:SetPoint("TOPLEFT", page.treesFrame, "TOPLEFT", (treeIndex - 1) * (treeWidth + 14), 0)
        treeFrames[treeIndex] = frame
    end

    page.refresh = function()
        local classFileName = select(2, UnitClass("player"))
        local dataVarName = SimulateX_ClassDataVars and SimulateX_ClassDataVars[classFileName]
        local classData = dataVarName and _G[dataVarName]
        local spec
        if classData and SimulateX_API then
            local bestBySpec = SimulateX_API.GetBestBuildPerSpec(classData)
            local activeKey = SimulateX_API.GetActiveSpecKey(bestBySpec, classFileName)
            spec = activeKey and bestBySpec[activeKey] and bestBySpec[activeKey].build.spec
        end
        RenderPage(page, spec)
    end

    return page
end
