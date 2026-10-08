--[[----------------------------------------------------------------------
    Pestaña Talentos (v0.7): dibuja los 3 árboles reales de tu clase (datos
    de Tools/generar_arbol_talentos.py, extraídos de Talent.dbc/TalentTab.dbc
    del servidor) y marca qué puntos pone cada distribución ya simulada
    (Tools/simular_talentos.py). Un selector arriba cambia de variante.
    Icono, tamaño de casilla y líneas de conexión calcados de la interfaz
    nativa del juego (Interface\TalentFrame\UI-TalentBranches/UI-TalentArrows,
    ver FrameXML TalentFrameBase.lua) para que se lea igual que la calculadora
    del juego, no una tabla aparte.
------------------------------------------------------------------------]]

local unpack = unpack or table.unpack  -- Lua 5.1 (WoW 3.3.5a) trae unpack global

local ICON_SIZE = 32  -- el del juego (TALENT_BUTTON_SIZE): sin reescalar el icono
local CELL_SIZE = 38
local TREE_GAP = 20
local TREE_COLUMNS = 4
local TREE_ROWS = 11
local NOISE_THRESHOLD_PCT = 0.3  -- mismo umbral que SimulateX.lua

local STANDARD_BUILD_IS_OPTIMAL = {
    DEATHKNIGHT = { deathknight = true },
    MAGE = { mage = true },
    PALADIN = { retribution_paladin = true },
    SHAMAN = { elemental_shaman = true },
}

-- Coordenadas reales de Interface\TalentFrame\UI-TalentBranches (líneas
-- rectas entre celdas adyacentes): [1] = requisito cumplido (dorado en la
-- textura), [-1] = no cumplido (gris). Solo "down" (prerrequisito en la fila
-- de encima, misma columna) y "right"/"left" (misma fila, columna
-- adyacente) cubren la inmensa mayoría de dependencias reales del árbol.
local BRANCH_TEXTURE = "Interface\\TalentFrame\\UI-TalentBranches"
local BRANCH_COORDS = {
    down = { [1] = { 0, 0.125, 0, 0.484375 }, [-1] = { 0, 0.125, 0.515625, 1.0 } },
    right = { [1] = { 0.2578125, 0.3828125, 0, 0.5 }, [-1] = { 0.2578125, 0.3828125, 0.5, 1.0 } },
}

local treeFrames = {}   -- 3 frames (uno por árbol)
local currentVariantIndex = 1
local RenderPage  -- forward-declaration: InitializeVariantDropdown la llama

-- traduce el label interno de la variante a algo que lea un jugador. Si no
-- hay traducción conocida, usa el label tal cual (mejor que nada, pero
-- Tools/simular_talentos.py debería darle uno legible de entrada).
local VARIANT_LABELS = {
    estandar = "Estándar (wowsims)",
    mas_potp = "Protector de la manada al máximo",
    nivel3 = "Óptima (búsqueda)",
}

local function DisplayLabel(variant)
    return VARIANT_LABELS[variant.label] or variant.label or "Variante"
end

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
    UN TALENTO: icono + marco dorado si tiene puntos + contador grande.
------------------------------------------------------------------------]]

local function CreateTalentCell(parent)
    local cell = CreateFrame("Button", nil, parent)
    cell:SetWidth(ICON_SIZE)
    cell:SetHeight(ICON_SIZE)
    cell:EnableMouse(true)

    cell.slotBg = cell:CreateTexture(nil, "BACKGROUND")
    cell.slotBg:SetTexture(0.06, 0.06, 0.06, 0.9)
    cell.slotBg:SetAllPoints()

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", 2, -2)
    cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- borde sólido y grueso (dorado con puntos, gris apagado sin ellos):
    -- más contraste que la textura difusa UI-Quickslot2 de antes. 3.3.5a
    -- tiene SetBackdrop nativo en cualquier Frame, sin plantilla.
    cell.border = CreateFrame("Frame", nil, cell)
    cell.border:SetAllPoints()
    cell.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })

    cell.count = cell:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    cell.count:SetPoint("BOTTOMRIGHT", 1, 1)
    cell.count:SetText("")

    cell:SetScript("OnEnter", function(self)
        if not self.talent then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.talent.name, 1, 1, 1)
        GameTooltip:AddLine(string.format("Rango %d / %d", self.rank or 0, self.talent.maxRank),
            self.rank and self.rank > 0 and 0.1 or 0.6, self.rank and self.rank > 0 and 1 or 0.6, 0.1)
        if self.talent.reqTalent then
            GameTooltip:AddLine("Requiere el talento de encima/al lado a rango mínimo", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)

    cell:Hide()
    return cell
end

--[[----------------------------------------------------------------------
    UN ÁRBOL: cuadrícula de TREE_ROWS x TREE_COLUMNS, con líneas de
    conexión reales del juego (texturas Blizzard) hacia el prerrequisito de
    cada talento que lo tenga.
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
    frame:SetHeight(TREE_ROWS * CELL_SIZE + 20)

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.title:SetPoint("TOP", 0, 0)
    frame.title:SetTextColor(1, 0.82, 0)

    frame.grid = CreateFrame("Frame", nil, frame)
    frame.grid:SetPoint("TOPLEFT", 0, -20)
    frame.grid:SetWidth(TREE_COLUMNS * CELL_SIZE)
    frame.grid:SetHeight(TREE_ROWS * CELL_SIZE)

    frame.cells = {}
    frame.branches = {}
    for row = 0, TREE_ROWS - 1 do
        for col = 0, TREE_COLUMNS - 1 do
            local cell = CreateTalentCell(frame.grid)
            cell:SetPoint("CENTER", frame.grid, "TOPLEFT",
                col * CELL_SIZE + CELL_SIZE / 2, -(row * CELL_SIZE) - CELL_SIZE / 2)
            frame.cells[row .. "_" .. col] = cell
        end
    end
    return frame
end

local function GetBranch(frame, index)
    local branch = frame.branches[index]
    if branch then return branch end
    branch = frame.grid:CreateTexture(nil, "ARTWORK")
    branch:SetTexture(BRANCH_TEXTURE)
    frame.branches[index] = branch
    return branch
end

-- Dibuja la línea entre el talento y su prerrequisito, si ambos existen en
-- la cuadrícula y están alineados en vertical u horizontal (el caso normal;
-- un puñado de talentos del juego real tiene desplazamientos en diagonal,
-- ver limitación documentada arriba).
local function DrawBranch(frame, branchIndex, fromCell, toCell, met)
    if not fromCell or not toCell then return branchIndex end
    local sameCol = fromCell.talent.col == toCell.talent.col
    local sameRow = fromCell.talent.row == toCell.talent.row
    if not sameCol and not sameRow then
        return branchIndex  -- desplazamiento diagonal, no cubierto
    end

    branchIndex = branchIndex + 1
    local branch = GetBranch(frame, branchIndex)
    local rowDiff = toCell.talent.row - fromCell.talent.row

    if sameCol and rowDiff == 1 then
        branch:SetTexCoord(unpack(BRANCH_COORDS.down[met and 1 or -1]))
        branch:SetWidth(CELL_SIZE)
        branch:SetHeight(CELL_SIZE)
        branch:SetPoint("TOP", fromCell, "BOTTOM", 0, 0)
    elseif sameRow then
        branch:SetTexCoord(unpack(BRANCH_COORDS.right[met and 1 or -1]))
        branch:SetWidth(CELL_SIZE)
        branch:SetHeight(CELL_SIZE)
        local leftCell = fromCell.talent.col < toCell.talent.col and fromCell or toCell
        branch:SetPoint("LEFT", leftCell, "RIGHT", 0, 0)
    else
        return branchIndex - 1  -- salto de más de una fila, no cubierto
    end
    branch:Show()
    return branchIndex
end

-- Coloca los talentos reales de la DBC en su celda, marca los que trae
-- digits (cadena de un solo árbol, sin guiones) y dibuja sus líneas.
local function RenderTree(frame, treeData, digits)
    frame.title:SetText(treeData.name or "")
    for _, cell in pairs(frame.cells) do
        cell.talent = nil
        cell:Hide()
    end
    for _, branch in pairs(frame.branches) do branch:Hide() end

    local rankByIndex = {}
    local cellByTalentId = {}
    for index, talent in ipairs(treeData.talents) do
        local cell = frame.cells[talent.row .. "_" .. talent.col]
        if cell then
            cell.talent = talent
            local rank = tonumber(digits and digits:sub(index, index)) or 0
            cell.rank = rank
            rankByIndex[index] = rank
            cellByTalentId[talent.id] = cell
            RefreshCellIcon(cell)

            if rank > 0 then
                cell.icon:SetDesaturated(false)
                cell.icon:SetAlpha(1)
                cell.border:SetBackdropBorderColor(1, 0.82, 0, 0.55)
                cell.count:SetText(rank)
                cell.count:SetTextColor(1, 0.82, 0)
            else
                cell.icon:SetDesaturated(true)
                cell.icon:SetAlpha(0.35)
                cell.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
                cell.count:SetText("")
            end
            cell:Show()
        end
    end

    local branchIndex = 0
    for index, talent in ipairs(treeData.talents) do
        if talent.reqTalent then
            local fromCell = cellByTalentId[talent.reqTalent]
            local toCell = frame.cells[talent.row .. "_" .. talent.col]
            local met = (rankByIndex[index] or 0) > 0
            branchIndex = DrawBranch(frame, branchIndex, fromCell, toCell, met)
        end
    end
    for i = branchIndex + 1, #frame.branches do frame.branches[i]:Hide() end
end

--[[----------------------------------------------------------------------
    RESUMEN Y SELECTOR DE VARIANTE
------------------------------------------------------------------------]]

-- Desplegable nativo (UIDropDownMenuTemplate) en vez de una fila de
-- pestañas: no escala cuando el Nivel 3 traiga muchas más variantes por
-- spec, y así queda consistente con el resto de la UI del juego.
local METRIC_NAMES = { dps = "DPS", hps = "HPS", tps = "amenaza" }

-- "Estándar (wowsims) · 15962 DPS", con la pérdida frente a la mejor
-- variante si la diferencia supera el umbral de ruido.
local function VariantLabel(specData, variant)
    local metric = specData.metric or "dps"
    local best = 0
    for _, other in ipairs(specData.variants) do
        best = math.max(best, other[metric] or 0)
    end
    local value = variant[metric] or 0
    local text = string.format("%s · %.0f %s", DisplayLabel(variant), value, METRIC_NAMES[metric] or metric)
    local diff = best > 0 and (value / best - 1) * 100 or 0
    if math.abs(diff) >= NOISE_THRESHOLD_PCT then
        text = text .. string.format(" (%.1f %%)", diff)
    end
    return text
end

-- El callback de UIDropDownMenu_Initialize solo se registra UNA vez (en
-- SimulateX_BuildTalentsPage): la propia función de inicialización, no
-- llamarla de nuevo, es lo que hay que repetir en cada refresco. Llamar a
-- UIDropDownMenu_Initialize entero en cada RenderPage reinicializa de golpe
-- los DropDownList1/2 globales y compartidos de todo el juego (ver
-- UIDropDownMenu_InitializeHelper en FrameXML) cada vez que se dibuja la
-- pestaña, no solo al abrir el menú: eso puede fallar de forma silenciosa.
-- El callback lee page.currentSpec/page.currentSpecData, que RenderPage
-- mantiene actualizados.
local function BuildVariantDropdownInitializer(page)
    return function()
        local specData = page.currentSpecData
        if not specData then return end
        for index, variant in ipairs(specData.variants) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = VariantLabel(specData, variant)
            info.checked = (index == currentVariantIndex)
            info.func = function()
                currentVariantIndex = index
                RenderPage(page, page.currentSpec)
            end
            UIDropDownMenu_AddButton(info)
        end
    end
end

--[[----------------------------------------------------------------------
    PANEL DE GLIFOS, a la derecha de los árboles: Sublime / Menor, 3 huecos
    cada uno, como la ventana de glifos del juego. Nombre e icono vienen ya
    resueltos en los datos (item_template_locale + ItemDisplayInfo.dbc del
    servidor, ver Tools/generar_db_talentos.py): son ids de OBJETO glifo,
    no de hechizo. Son los de la petición simulada (iguales para todas las
    distribuciones de la spec), no los de presets.ts.
------------------------------------------------------------------------]]

local GLYPH_PANEL_WIDTH = 240
local GLYPH_SLOT_SIZE = 30
local GLYPH_ROW_HEIGHT = 40
local GLYPH_KINDS = { { key = "major", label = "Sublime" }, { key = "minor", label = "Menor" } }
local EMPTY_SLOT_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

-- "Glifo de Triturar" -> "Triturar": la cabecera ya dice Glifos, y la
-- columna es estrecha. Solo si lo que queda empieza en mayúscula ("Glifo de
-- lo Salvaje" se queda entero). El tooltip enseña el nombre completo.
local function ShortGlyphName(name)
    return name:match("^Glifo del? (.+)$") or name
end

local function CreateGlyphSlot(parent)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetHeight(GLYPH_ROW_HEIGHT)

    slot.background = slot:CreateTexture(nil, "BACKGROUND")
    slot.background:SetTexture(EMPTY_SLOT_TEXTURE)
    slot.background:SetWidth(GLYPH_SLOT_SIZE + 8)
    slot.background:SetHeight(GLYPH_SLOT_SIZE + 8)
    slot.background:SetPoint("LEFT", -4, 0)

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetWidth(GLYPH_SLOT_SIZE)
    slot.icon:SetHeight(GLYPH_SLOT_SIZE)
    slot.icon:SetPoint("LEFT", 0, 0)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    slot.label = slot:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    slot.label:SetPoint("LEFT", slot.icon, "RIGHT", 6, 0)
    slot.label:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
    slot.label:SetJustifyH("LEFT")
    slot.label:SetWordWrap(true)

    slot:SetScript("OnEnter", function(self)
        if not self.itemId then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetHyperlink("item:" .. self.itemId)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return slot
end

local function CreateGlyphPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(GLYPH_PANEL_WIDTH)
    panel:SetHeight(28 + 18 + 3 * GLYPH_ROW_HEIGHT + 60)  -- la nota puede ocupar 4 líneas

    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0, 0, 0, 0.45)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Glifos")

    local columnWidth = (GLYPH_PANEL_WIDTH - 20 - 10) / 2
    panel.slots = {}
    for column, kind in ipairs(GLYPH_KINDS) do
        local x = 10 + (column - 1) * (columnWidth + 10)
        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", x, -30)
        header:SetText(kind.label)
        header:SetTextColor(0.35, 0.75, 1)

        panel.slots[kind.key] = {}
        for row = 1, 3 do
            local slot = CreateGlyphSlot(panel)
            slot:SetWidth(columnWidth)
            slot:SetPoint("TOPLEFT", x + 4, -46 - (row - 1) * GLYPH_ROW_HEIGHT)
            panel.slots[kind.key][row] = slot
        end
    end

    -- con solo un ancla abajo el cliente la deja en una línea y la corta
    panel.note = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.note:SetPoint("TOPLEFT", 10, -46 - 3 * GLYPH_ROW_HEIGHT - 4)
    panel.note:SetPoint("BOTTOMRIGHT", -10, 6)
    panel.note:SetJustifyH("LEFT")
    panel.note:SetJustifyV("TOP")
    panel.note:SetWordWrap(true)
    return panel
end

local function RenderGlyphPanel(panel, glyphs, missing)
    -- los glifos de wowsims que no existen en el servidor (p. ej. los de
    -- WotLK Classic) dejan huecos sublimes; no se sabe cuál, así que se marcan
    -- los primeros vacíos
    local unavailable = missing or 0
    for _, kind in ipairs(GLYPH_KINDS) do
        local entries = glyphs and glyphs[kind.key] or {}
        for row, slot in ipairs(panel.slots[kind.key]) do
            local glyph = entries[row]
            if glyph then
                slot.itemId = glyph.id
                slot.icon:SetTexture(glyph.icon ~= "" and ("Interface\\Icons\\" .. glyph.icon)
                    or "Interface\\Icons\\INV_Misc_QuestionMark")
                slot.icon:Show()
                slot.label:SetText(ShortGlyphName(glyph.name))
                slot.label:SetTextColor(1, 1, 1)
            else
                slot.itemId = nil
                slot.icon:Hide()
                if kind.key == "major" and unavailable > 0 then
                    unavailable = unavailable - 1
                    slot.label:SetText("No existe en 3.3.5")
                else
                    slot.label:SetText("Sin glifo")
                end
                slot.label:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
    local note = glyphs and "Glifos del preset de wowsims. Los menores casi no cuentan y no siempre los pone."
        or "Sin datos de glifos para esta especialización."
    if missing then
        note = note .. string.format(" %d no existe en 3.3.5.", missing)
    end
    panel.note:SetText(note)
    panel:Show()
end

RenderPage = function(page, spec)
    local data = GetTalentDataForClass()
    local specData = data and data[spec]
    local treeData = GetTreeDataForClass()

    if not treeData then
        page.emptyText:SetText("SimulateX no tiene el árbol de talentos de tu clase todavía.")
        page.emptyText:Show()
        page.treesFrame:Hide()
        page.variantBar:Hide()
        page.glyphPanel:Hide()
        return
    end

    if not specData or not specData.variants or #specData.variants == 0 then
        local classFileName = select(2, UnitClass("player"))
        local optimalSpecs = STANDARD_BUILD_IS_OPTIMAL[classFileName]
        if optimalSpecs and optimalSpecs[spec] then
            page.emptyText:SetText("Sin variantes: la búsqueda de SimulateX no halló nada mejor que la distribución estándar de wowsims.")
        else
            page.emptyText:SetText("Sin distribuciones simuladas todavía para esta especialización")
        end
        page.emptyText:Show()
        page.variantBar:Hide()
        page.glyphPanel:Hide()
        -- el árbol se ve igual (nombres/iconos reales), pero sin marcar puntos
        for treeIndex = 1, 3 do
            RenderTree(treeFrames[treeIndex], treeData.trees[treeIndex], "")
        end
        page.treesFrame:Show()
        return
    end
    page.emptyText:Hide()
    page.treesFrame:Show()

    if currentVariantIndex > #specData.variants then
        currentVariantIndex = 1
    end

    local current = specData.variants[currentVariantIndex]
    local blocks = SplitTalentBlocks(current.talents or "")
    for treeIndex = 1, 3 do
        RenderTree(treeFrames[treeIndex], treeData.trees[treeIndex], blocks[treeIndex - 1])
    end
    RenderGlyphPanel(page.glyphPanel, specData.glyphs, specData.glyphsMissing)

    -- el desplegable va al final: el árbol ya dibujado no depende de que
    -- esto salga bien. page.currentSpec/currentSpecData son lo que lee el
    -- callback del dropdown, registrado una sola vez (ver SimulateX_BuildTalentsPage).
    page.currentSpec = spec
    page.currentSpecData = specData
    -- visible también con una sola variante: es donde se ve su valor
    page.variantBar:Show()
    UIDropDownMenu_SetText(page.variantDropdown, VariantLabel(specData, specData.variants[currentVariantIndex]))
end

--[[----------------------------------------------------------------------
    CONSTRUCCIÓN DE LA PÁGINA
------------------------------------------------------------------------]]

function SimulateX_BuildTalentsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetText("Árbol de talentos")
    header:SetTextColor(1, 0.82, 0)

    local line = page:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    line:SetPoint("RIGHT", page, "RIGHT", 0, 0)

    page.emptyText = page:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    page.emptyText:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", 0, 4)
    page.emptyText:SetJustifyH("RIGHT")

    -- desplegable en la misma línea que el título, a la derecha. La barra
    -- necesita ancho explícito: con ancho 0 el juego no la dibuja.
    page.variantBar = CreateFrame("Frame", nil, page)
    page.variantBar:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", 14, -2)
    page.variantBar:SetWidth(340)
    page.variantBar:SetHeight(26)

    page.variantDropdown = CreateFrame("Frame", "SimulateXTalentVariantDropdown", page.variantBar, "UIDropDownMenuTemplate")
    page.variantDropdown:SetPoint("RIGHT", 0, 0)
    UIDropDownMenu_SetWidth(page.variantDropdown, 230)
    UIDropDownMenu_Initialize(page.variantDropdown, BuildVariantDropdownInitializer(page))

    local variantLabel = page.variantBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    variantLabel:SetPoint("RIGHT", page.variantDropdown, "LEFT", 14, 2)
    variantLabel:SetText("Distribución:")
    variantLabel:SetTextColor(0.8, 0.8, 0.8)

    -- los 3 árboles a la izquierda y el panel de glifos a la derecha: con
    -- 760 px de ancho útil caben los dos (496 + 240), no uno debajo de otro
    local treeWidth = TREE_COLUMNS * CELL_SIZE
    page.treesFrame = CreateFrame("Frame", nil, page)
    page.treesFrame:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
    page.treesFrame:SetWidth(3 * treeWidth + 2 * TREE_GAP)
    page.treesFrame:SetHeight(TREE_ROWS * CELL_SIZE + 20)

    for treeIndex = 1, 3 do
        local frame = CreateTreeFrame(page.treesFrame)
        frame:SetPoint("TOPLEFT", page.treesFrame, "TOPLEFT", (treeIndex - 1) * (treeWidth + TREE_GAP), 0)
        treeFrames[treeIndex] = frame
    end

    page.glyphPanel = CreateGlyphPanel(page)
    page.glyphPanel:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, -8)
    page.glyphPanel:Hide()

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
