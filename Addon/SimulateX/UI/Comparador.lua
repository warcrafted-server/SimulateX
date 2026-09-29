--[[----------------------------------------------------------------------
    Ventana de SimulateX: pestaña Comparador (A contra B, o contra lo
    equipado; anillos y abalorios contra los dos equipados) y pestaña
    Configuración. El cálculo sale siempre de SimulateX_API (SimulateX.lua).
------------------------------------------------------------------------]]

local PANEL_WIDTH = 940
local PANEL_HEIGHT = 600
local SIDEBAR_WIDTH = 150
local HEADER_HEIGHT = 58
local CONTENT_LEFT = SIDEBAR_WIDTH + 14
local CONTENT_RIGHT = 16
local CONTENT_WIDTH = PANEL_WIDTH - CONTENT_LEFT - CONTENT_RIGHT
local CARD_GAP = 10
local CARD_HEIGHT = 224
local ICON_SIZE = 40
local MAX_STAT_LINES = 8
local MAX_BREAKDOWN_ROWS = 8
local DEFAULT_OPACITY = 0.95

local MULTI_SLOT_EQUIP_LOCS = { INVTYPE_FINGER = true, INVTYPE_TRINKET = true }
local CARD_LETTERS = { "A", "B", "C" }

-- orden de las estadísticas en las tarjetas; el resto va detrás por nombre
local STAT_ORDER = {
    "RESISTANCE0_NAME", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "ITEM_MOD_STRENGTH_SHORT",
    "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT",
    "ITEM_MOD_SPIRIT_SHORT",
}
local STAT_RANK = {}
for index, key in ipairs(STAT_ORDER) do STAT_RANK[key] = index end

local frame, comparePage, configPage, configRefresh, talentsPage, talentsContent
local cards = {}
local tabs = {}
local resultsFrame, breakdownFrame, verdictText, verdictBg
local resultRows, breakdownRows, columnHeaders = {}, {}, {}

--[[----------------------------------------------------------------------
    UTILIDADES
------------------------------------------------------------------------]]

local function GetItemId(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function GetEquipLoc(link)
    return link and select(9, GetItemInfo(link))
end

local function EquippedLink(slotName)
    return GetInventoryItemLink("player", (GetInventorySlotInfo(slotName)))
end

local function SetShown(region, shown)
    if shown then region:Show() else region:Hide() end
end

local function IsSocketKey(key)
    return key:match("^EMPTY_SOCKET_") ~= nil
end

local function FormatStatValue(key, value)
    if key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
        return string.format("%.1f", value)
    end
    return string.format("%d", value)
end

-- Lista ordenada { key, value } de lo que trae el objeto (datos del
-- servidor, no del tooltip: así coincide con lo que se puntúa).
local function GetSortedStats(link)
    local stats = link and SimulateX_API.GetItemStats(link) or {}
    local list = {}
    for key, value in pairs(stats) do
        if value ~= 0 then
            table.insert(list, { key = key, value = value })
        end
    end
    table.sort(list, function(a, b)
        local socketA, socketB = IsSocketKey(a.key), IsSocketKey(b.key)
        if socketA ~= socketB then return socketB end
        local rankA, rankB = STAT_RANK[a.key] or 99, STAT_RANK[b.key] or 99
        if rankA ~= rankB then return rankA < rankB end
        return SimulateX_API.GetStatLabel(a.key) < SimulateX_API.GetStatLabel(b.key)
    end)
    return list, stats
end

-- encantamiento y gemas vienen en el link; el cálculo no los cuenta
local function GetLinkExtras(link)
    local enchant, g1, g2, g3, g4 = link:match("item:%d+:(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+):(%-?%d+)")
    local gems = 0
    for _, gem in ipairs({ g1, g2, g3, g4 }) do
        if tonumber(gem) and tonumber(gem) > 0 then gems = gems + 1 end
    end
    return tonumber(enchant) and tonumber(enchant) > 0, gems
end

local function PercentColor(evaluation)
    if evaluation.isNoise then return 0.65, 0.65, 0.65 end
    if evaluation.gain > 0 then return 0.2, 1, 0.2 end
    return 1, 0.35, 0.35
end

local function FormatPercent(evaluation)
    if evaluation.isNoise then
        return "≈ igual"
    end
    return string.format("%+.1f %%", evaluation.percent)
end

local function CreateSectionHeader(parent, text)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    header.line = line
    return header
end

--[[----------------------------------------------------------------------
    TARJETAS DE OBJETO. card.link = lo que ha puesto el jugador; card.auto =
    lo equipado que ocupa el hueco si lo deja vacío (card.autoEmpty si ese
    hueco del personaje está vacío).
------------------------------------------------------------------------]]

local SetCardItem

local function GetShownLink(card)
    return card.link or card.auto
end

-- Sin el objeto en caché GetItemInfo devuelve nil (3.3.5a no tiene
-- GET_ITEM_INFO_RECEIVED): reintenta cada 0.2 s hasta que llegue.
local function WaitForItemInfo(card)
    if card.waiting then
        return
    end
    card.waiting = true
    card.retryTimer = 0
    card:SetScript("OnUpdate", function(self, elapsed)
        self.retryTimer = self.retryTimer + elapsed
        if self.retryTimer < 0.2 then return end
        self.retryTimer = 0
        local link = GetShownLink(self)
        if not link or GetItemInfo(link) then
            self:SetScript("OnUpdate", nil)
            self.waiting = nil
            SimulateX_Comparador_Refresh()
        end
    end)
end

local function StopWaiting(card)
    card.waiting = nil
    card:SetScript("OnUpdate", nil)
end

local function SetStatLines(card, lines)
    for index, fontString in ipairs(card.statLines) do
        local line = lines[index]
        if line then
            fontString:SetText(line.text)
            fontString:SetTextColor(line.r, line.g, line.b)
            fontString:Show()
        else
            fontString:Hide()
        end
    end
end

-- Estadísticas del objeto, en verde lo que tiene de más frente a refStats y
-- en rojo lo que tiene de menos.
local function BuildStatLines(link, refStats)
    local list = GetSortedStats(link)
    local lines = {}
    for _, entry in ipairs(list) do
        local label = SimulateX_API.GetStatLabel(entry.key)
        local text
        if IsSocketKey(entry.key) then
            text = entry.value > 1 and string.format("%d x %s", entry.value, label) or label
        elseif entry.key == "RESISTANCE0_NAME" or entry.key == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then
            text = FormatStatValue(entry.key, entry.value) .. " " .. label
        else
            text = "+" .. FormatStatValue(entry.key, entry.value) .. " " .. label
        end
        local r, g, b = 0.9, 0.9, 0.9
        if refStats then
            local other = refStats[entry.key] or 0
            if entry.value > other then
                r, g, b = 0.3, 1, 0.3
            elseif entry.value < other then
                r, g, b = 1, 0.45, 0.45
            end
        end
        table.insert(lines, { text = text, r = r, g = g, b = b })
    end
    if #lines > MAX_STAT_LINES then
        local hidden = #lines - MAX_STAT_LINES + 1
        for i = #lines, MAX_STAT_LINES, -1 do lines[i] = nil end
        lines[MAX_STAT_LINES] = { text = string.format("(+%d más, ver tooltip)", hidden), r = 0.6, g = 0.6, b = 0.6 }
    end
    return lines
end

local function ShowEmptyCard(card, message)
    StopWaiting(card)
    card.icon:Hide()
    card.border:Hide()
    card.plus:Show()
    card.nameText:SetText(message)
    card.nameText:SetTextColor(0.55, 0.55, 0.55)
    card.infoText:SetText("")
    card.reqText:SetText("")
    card.noteText:SetText("")
    SetStatLines(card, {})
end

local function UpdateCard(card, refStats)
    local link = GetShownLink(card)

    if card.link then
        card.tag:SetText("")
    elseif card.auto then
        card.tag:SetText("equipado")
    elseif card.autoEmpty then
        card.tag:SetText("hueco libre")
    else
        card.tag:SetText("")
    end

    if not link then
        if card.autoEmpty then
            ShowEmptyCard(card, "No llevas nada en ese hueco: A contaría entero")
        elseif card.index == 1 then
            ShowEmptyCard(card, "Arrastra aquí el objeto que quieres valorar")
        else
            ShowEmptyCard(card, "Vacío: se compara con lo que llevas puesto")
        end
        return
    end

    card.plus:Hide()
    local itemId = GetItemId(link)
    -- GetItemIcon lee el icono de los datos del cliente, sin esperar a la caché
    local texture = itemId and GetItemIcon and GetItemIcon(itemId)
    local name, _, quality, itemLevel, reqLevel, itemType, itemSubType, _, equipLoc, infoTexture = GetItemInfo(link)
    card.icon:SetTexture(texture or infoTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.icon:Show()

    if not name then
        WaitForItemInfo(card)
        card.border:Hide()
        card.nameText:SetText("Cargando...")
        card.nameText:SetTextColor(0.6, 0.6, 0.6)
        card.infoText:SetText("")
        card.reqText:SetText("")
        card.noteText:SetText("")
        SetStatLines(card, {})
        return
    end
    StopWaiting(card)

    local color = ITEM_QUALITY_COLORS[quality or 1] or ITEM_QUALITY_COLORS[1]
    card.nameText:SetText(name)
    card.nameText:SetTextColor(color.r, color.g, color.b)
    if quality and quality >= 2 then
        card.border:SetVertexColor(color.r, color.g, color.b)
        card.border:Show()
    else
        card.border:Hide()
    end

    local parts = { string.format("Nivel %d", itemLevel or 0) }
    local subType = (itemSubType and itemSubType ~= "" and itemSubType) or itemType
    if subType and subType ~= "" and subType ~= _G[equipLoc] then
        table.insert(parts, subType)
    end
    if equipLoc and equipLoc ~= "" and _G[equipLoc] then
        table.insert(parts, _G[equipLoc])
    end
    card.infoText:SetText(table.concat(parts, "  ·  "))

    if not SimulateX_API.IsItemUsable(link) then
        card.reqText:SetText("No puedes usarlo")
        card.reqText:SetTextColor(1, 0.3, 0.3)
    elseif reqLevel and reqLevel > 1 then
        card.reqText:SetText(string.format(ITEM_MIN_LEVEL, reqLevel))
        if reqLevel > UnitLevel("player") then
            card.reqText:SetTextColor(1, 0.3, 0.3)
        else
            card.reqText:SetTextColor(0.65, 0.65, 0.65)
        end
    else
        card.reqText:SetText("")
    end

    local lines = BuildStatLines(link, refStats)
    if #lines == 0 then
        lines = { { text = "Sin estadísticas fijas (mira el tooltip)", r = 0.6, g = 0.6, b = 0.6 } }
    end
    SetStatLines(card, lines)

    local enchanted, gems = GetLinkExtras(link)
    local notes = {}
    if enchanted then table.insert(notes, "encantado") end
    if gems > 0 then table.insert(notes, gems == 1 and "1 gema" or (gems .. " gemas")) end
    if #notes > 0 then
        card.noteText:SetText(table.concat(notes, ", ") .. " (no cuenta en el cálculo)")
    else
        card.noteText:SetText("")
    end
end

local function CreateCard(parent, index)
    local card = CreateFrame("Button", nil, parent)
    card.index = index
    card:SetHeight(CARD_HEIGHT)
    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    card:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    card:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local highlight = card:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(1, 0.82, 0, 0.06)
    highlight:SetPoint("TOPLEFT", 3, -3)
    highlight:SetPoint("BOTTOMRIGHT", -3, 3)

    card.letter = card:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    card.letter:SetPoint("TOPLEFT", 10, -8)
    card.letter:SetText(CARD_LETTERS[index])

    card.tag = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    card.tag:SetPoint("LEFT", card.letter, "RIGHT", 8, 0)

    -- capas fijas: fondo del hueco, icono y borde de calidad no comparten
    -- capa (dentro de una misma capa el orden de dibujo no está garantizado)
    local slotBg = card:CreateTexture(nil, "BACKGROUND", nil)
    slotBg:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    slotBg:SetTexCoord(0.14, 0.86, 0.14, 0.86)
    slotBg:SetWidth(ICON_SIZE)
    slotBg:SetHeight(ICON_SIZE)
    slotBg:SetPoint("TOPLEFT", 10, -32)
    card.slotBg = slotBg

    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetAllPoints(slotBg)
    card.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    card.border = card:CreateTexture(nil, "OVERLAY")
    card.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    card.border:SetBlendMode("ADD")
    card.border:SetWidth(ICON_SIZE * 1.8)
    card.border:SetHeight(ICON_SIZE * 1.8)
    card.border:SetPoint("CENTER", slotBg, "CENTER", 0, 0)

    card.plus = card:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    card.plus:SetPoint("CENTER", slotBg, "CENTER", 0, 0)
    card.plus:SetText("+")

    card.nameText = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    card.nameText:SetPoint("TOPLEFT", slotBg, "TOPRIGHT", 8, 0)
    card.nameText:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.nameText:SetHeight(ICON_SIZE - 12)
    card.nameText:SetJustifyH("LEFT")
    card.nameText:SetJustifyV("TOP")

    card.infoText = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.infoText:SetPoint("BOTTOMLEFT", slotBg, "BOTTOMRIGHT", 8, 0)
    card.infoText:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.infoText:SetJustifyH("LEFT")
    card.infoText:SetTextColor(0.8, 0.8, 0.8)

    card.reqText = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    card.reqText:SetPoint("TOPLEFT", slotBg, "BOTTOMLEFT", 0, -6)
    card.reqText:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.reqText:SetJustifyH("LEFT")

    card.statLines = {}
    for i = 1, MAX_STAT_LINES do
        local line = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", card.reqText, "BOTTOMLEFT", 0, -3 - (i - 1) * 13)
        line:SetPoint("RIGHT", card, "RIGHT", -8, 0)
        line:SetJustifyH("LEFT")
        line:SetHeight(13)
        card.statLines[i] = line
    end

    card.noteText = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    card.noteText:SetPoint("BOTTOMLEFT", 10, 8)
    card.noteText:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.noteText:SetJustifyH("LEFT")

    card:SetScript("OnReceiveDrag", function(self)
        local cursorType, _, itemLink = GetCursorInfo()
        if cursorType == "item" and itemLink then
            SetCardItem(self, itemLink)
        end
        ClearCursor()
    end)
    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            SetCardItem(self, nil)
            return
        end
        local cursorType, _, itemLink = GetCursorInfo()
        if cursorType == "item" and itemLink then
            SetCardItem(self, itemLink)
            ClearCursor()
        end
    end)
    card:SetScript("OnEnter", function(self)
        local link = GetShownLink(self)
        if link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(link)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ShowEmptyCard(card, "")
    return card
end

SetCardItem = function(card, link)
    card.link = link
    if card.index == 1 and not link then
        -- sin A, B y C pierden el sentido
        cards[2].link = nil
        cards[3].link = nil
    end
    SimulateX_Comparador_Refresh()
end

--[[----------------------------------------------------------------------
    CONTRA QUÉ SE COMPARA. Anillos y abalorios: una tarjeta por cada uno de
    los dos equipados (B y C). Resto: una sola tarjeta (B); vacía, el motor
    usa sus reglas de siempre (2M contra MP+MI, mano izquierda con 2M...).
------------------------------------------------------------------------]]

local function RepresentativeEquipped(equipLoc)
    local mainHand = EquippedLink("MainHandSlot")
    local mainIs2H = GetEquipLoc(mainHand) == "INVTYPE_2HWEAPON"
    if equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_2HWEAPON" then
        return mainHand or EquippedLink("SecondaryHandSlot")
    end
    if equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return mainIs2H and mainHand or EquippedLink("SecondaryHandSlot")
    end
    local slots = SimulateX_API.INVTYPE_TO_SLOTS[equipLoc]
    return slots and EquippedLink(slots[1])
end

-- Prepara las tarjetas B/C y devuelve la lista de objetivos:
-- { card, link, empty } (link nil y empty nil = motor contra lo equipado).
local function PrepareTargets(linkA)
    local equipLoc = GetEquipLoc(linkA)
    local multi = equipLoc and MULTI_SLOT_EQUIP_LOCS[equipLoc]
    local cardB, cardC = cards[2], cards[3]

    cardB.auto, cardB.autoEmpty = nil, nil
    cardC.auto, cardC.autoEmpty = nil, nil

    if not linkA or not equipLoc then
        cardC.link = nil
        return {}, false
    end

    if multi then
        local slots = SimulateX_API.INVTYPE_TO_SLOTS[equipLoc]
        local targets = {}
        for i, card in ipairs({ cardB, cardC }) do
            local equipped = EquippedLink(slots[i])
            card.auto = equipped
            card.autoEmpty = not equipped
            local link = card.link or equipped
            table.insert(targets, { card = card, link = link, empty = not link })
        end
        return targets, true
    end

    cardC.link = nil
    cardB.auto = RepresentativeEquipped(equipLoc)
    cardB.autoEmpty = not cardB.auto
    return { { card = cardB, link = cardB.link } }, false
end

--[[----------------------------------------------------------------------
    RESULTADOS: tabla spec × objetivo, veredicto para tu spec y desglose
    por estadística frente al objetivo más relevante.
------------------------------------------------------------------------]]

local function GetResultRow(index)
    local row = resultRows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, resultsFrame)
    row:SetHeight(22)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetPoint("LEFT", 6, 0)
    row.label:SetJustifyH("LEFT")
    row.cells = {}
    for i = 1, 2 do
        local cell = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        cell:SetJustifyH("RIGHT")
        cell:SetWidth(70)
        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetHeight(2)
        cell.bar = bar
        row.cells[i] = cell
    end
    resultRows[index] = row
    return row
end

local function GetBreakdownRow(index)
    local row = breakdownRows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, breakdownFrame)
    row:SetHeight(16)
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", 4, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWidth(150)
    row.diff = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.diff:SetPoint("RIGHT", row, "RIGHT", -60, 0)
    row.diff:SetJustifyH("RIGHT")
    row.diff:SetWidth(50)
    row.percent = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.percent:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.percent:SetJustifyH("RIGHT")
    row.percent:SetWidth(56)
    row.bar = row:CreateTexture(nil, "BACKGROUND")
    row.bar:SetHeight(12)
    breakdownRows[index] = row
    return row
end

local function HideFrom(pool, index)
    for i = index, #pool do pool[i]:Hide() end
end

local function TargetName(target)
    local link = target.link or target.card.auto
    local name = link and GetItemInfo(link)
    return name or "lo que llevas"
end

local function SetVerdict(text, r, g, b)
    verdictText:SetText(text)
    verdictText:SetTextColor(r, g, b)
    verdictBg:SetVertexColor(r, g, b)
end

-- Une las evaluaciones de cada objetivo por spec: filas { specLabel,
-- isActive, buildId, byTarget = { evaluation, ... } }
local function MergeEvaluations(perTarget)
    local rows, byLabel = {}, {}
    for targetIndex, evaluations in ipairs(perTarget) do
        for _, evaluation in ipairs(evaluations) do
            local row = byLabel[evaluation.specLabel]
            if not row then
                row = { specLabel = evaluation.specLabel, isActive = evaluation.isActive,
                    buildId = evaluation.buildId, byTarget = {} }
                byLabel[evaluation.specLabel] = row
                table.insert(rows, row)
            end
            row.byTarget[targetIndex] = evaluation
        end
    end
    table.sort(rows, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        return a.specLabel < b.specLabel
    end)
    return rows
end

local function CellOffset(i, targetCount)
    return -6 - (targetCount - i) * 78
end

local function RenderResults(rows, targets)
    local tableWidth = resultsFrame:GetWidth()
    for i, header in ipairs(columnHeaders) do
        if targets[i] then
            header:SetText("contra " .. CARD_LETTERS[i + 1])
            header:ClearAllPoints()
            header:SetPoint("TOPRIGHT", resultsFrame, "TOPRIGHT", CellOffset(i, #targets), -4)
            header:Show()
        else
            header:Hide()
        end
    end

    for index, data in ipairs(rows) do
        local row = GetResultRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 0, -18 - (index - 1) * 24)
        row:SetWidth(tableWidth)
        if data.isActive then
            row.bg:SetTexture(1, 0.82, 0, 0.12)
            row.label:SetText(data.specLabel .. "  |cffffd100(tu spec)|r")
            row.label:SetTextColor(1, 1, 1)
        else
            row.bg:SetTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
            row.label:SetText(data.specLabel)
            row.label:SetTextColor(0.8, 0.8, 0.8)
        end
        for i, cell in ipairs(row.cells) do
            local evaluation = data.byTarget[i]
            cell:ClearAllPoints()
            cell:SetPoint("RIGHT", row, "RIGHT", CellOffset(i, #targets), 1)
            if targets[i] and evaluation then
                cell:SetText(FormatPercent(evaluation))
                local r, g, b = PercentColor(evaluation)
                cell:SetTextColor(r, g, b)
                cell:Show()
                -- barra bajo la cifra: llena a partir de un 10 %
                local fill = math.min(math.abs(evaluation.percent) / 10, 1)
                cell.bar:ClearAllPoints()
                cell.bar:SetPoint("TOPRIGHT", cell, "BOTTOMRIGHT", 0, -1)
                cell.bar:SetWidth(math.max(1, 70 * fill))
                cell.bar:SetTexture(r, g, b, evaluation.isNoise and 0.2 or 0.6)
                cell.bar:Show()
            elseif targets[i] then
                cell:SetText("-")
                cell:SetTextColor(0.5, 0.5, 0.5)
                cell:Show()
                cell.bar:Hide()
            else
                cell:Hide()
                cell.bar:Hide()
            end
        end
        row:Show()
    end
    HideFrom(resultRows, #rows + 1)
end

-- Veredicto para tu spec; devuelve el índice del objetivo para el desglose
-- (el que A sustituiría: el de mayor ganancia).
local function RenderVerdict(rows, targets, linkA, multi)
    local active = rows[1] and rows[1].isActive and rows[1]
    if not SimulateX_API.IsItemUsable(linkA) then
        SetVerdict("No puedes usar A con este personaje.", 1, 0.35, 0.35)
        return nil
    end
    if not active then
        SetVerdict("Sin datos para tu especialización (¿desactivada en Configuración?).", 0.7, 0.7, 0.7)
        return nil
    end

    local bestIndex, best
    for i in ipairs(targets) do
        local evaluation = active.byTarget[i]
        if evaluation and (not best or evaluation.percent > best.percent) then
            bestIndex, best = i, evaluation
        end
    end
    if not best then
        SetVerdict("B no se puede usar o no va en el mismo hueco que A.", 1, 0.35, 0.35)
        return nil
    end

    local spec = active.specLabel
    local target = targets[bestIndex]
    local againstName = target.empty and "el hueco libre" or TargetName(target)

    if multi then
        if best.isNoise then
            SetVerdict(string.format("Para %s, A rinde casi igual que %s.", spec, againstName), 0.8, 0.8, 0.8)
        elseif best.gain > 0 then
            local verb = target.empty and "Póntelo en" or "Cámbialo por"
            SetVerdict(string.format("%s %s: %+.1f %% para %s.", verb, againstName, best.percent, spec), 0.2, 1, 0.2)
        else
            SetVerdict(string.format("A no mejora ninguno de los dos para %s (en el mejor caso %+.1f %%).",
                spec, best.percent), 1, 0.35, 0.35)
        end
    else
        if best.isNoise then
            SetVerdict(string.format("Para %s, A y %s rinden casi igual.", spec, againstName), 0.8, 0.8, 0.8)
        elseif best.gain > 0 then
            SetVerdict(string.format("A es mejor que %s para %s: %+.1f %%.", againstName, spec, best.percent), 0.2, 1, 0.2)
        else
            SetVerdict(string.format("A es peor que %s para %s: %+.1f %%.", againstName, spec, best.percent), 1, 0.35, 0.35)
        end
    end
    return bestIndex, active
end

local BREAKDOWN_STAT_KEY = { weaponDps = "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" }

local function SocketCount(stats)
    local count = 0
    for key, value in pairs(stats) do
        if IsSocketKey(key) then count = count + value end
    end
    return count
end

-- Cambio de la estadística en sí (no de su valor), para la columna central
local function StatAmountDiff(key, statsA, statsB)
    if key == "sockets" then
        return SocketCount(statsA) - SocketCount(statsB), "%+d"
    end
    local statKey = BREAKDOWN_STAT_KEY[key] or key
    local format = statKey == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" and "%+.1f" or "%+d"
    return (statsA[statKey] or 0) - (statsB[statKey] or 0), format
end

local function RenderBreakdown(linkA, target, active)
    local title = breakdownFrame.title
    local rows = active and target
        and SimulateX_API.GetComparisonBreakdown(linkA, target.link, active.buildId, target.empty)

    if not rows then
        HideFrom(breakdownRows, 1)
        breakdownFrame.emptyText:SetText(active and target
            and "Para este hueco solo hay % total: A se compara con más de un objeto equipado a la vez."
            or "")
        breakdownFrame.emptyText:Show()
        title:SetText("Por qué")
        return
    end
    breakdownFrame.emptyText:Hide()
    title:SetText(string.format("Por qué, en %s (A contra %s)", active.specLabel, CARD_LETTERS[target.card.index]))

    local statsA = SimulateX_API.GetItemStats(linkA)
    local linkB = target.link or target.card.auto
    local statsB = (not target.empty and linkB) and SimulateX_API.GetItemStats(linkB) or {}

    -- estadísticas que cambian pero no valen nada para esta spec, al final
    local listed = {}
    for _, entry in ipairs(rows) do
        listed[BREAKDOWN_STAT_KEY[entry.key] or entry.key] = true
    end
    local keys = {}
    for key in pairs(statsA) do keys[key] = true end
    for key in pairs(statsB) do keys[key] = true end
    local useless = {}
    for key in pairs(keys) do
        if not listed[key] and not IsSocketKey(key) and key ~= "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"
            and (statsA[key] or 0) ~= (statsB[key] or 0) then
            table.insert(useless, { key = key, label = SimulateX_API.GetStatLabel(key), percent = 0, useless = true })
        end
    end
    table.sort(useless, function(a, b) return a.label < b.label end)
    for _, entry in ipairs(useless) do table.insert(rows, entry) end

    local maxAbs = 0
    for _, entry in ipairs(rows) do maxAbs = math.max(maxAbs, math.abs(entry.percent)) end

    local width = breakdownFrame:GetWidth()
    local shown = math.min(#rows, MAX_BREAKDOWN_ROWS)
    for index = 1, shown do
        local entry = rows[index]
        local row = GetBreakdownRow(index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", breakdownFrame, "TOPLEFT", 0, -22 - (index - 1) * 17)
        row:SetWidth(width)
        row.label:SetText(entry.label)

        local amount, format = StatAmountDiff(entry.key, statsA, statsB)
        row.diff:SetText(amount ~= 0 and string.format(format, amount) or "")

        if entry.useless then
            row.label:SetTextColor(0.5, 0.5, 0.5)
            row.diff:SetTextColor(0.5, 0.5, 0.5)
            row.percent:SetText("no te sirve")
            row.percent:SetTextColor(0.5, 0.5, 0.5)
            row.bar:Hide()
        else
            local positive = entry.percent >= 0
            local r, g, b = positive and 0.3 or 1, positive and 1 or 0.4, positive and 0.3 or 0.4
            row.label:SetTextColor(0.9, 0.9, 0.9)
            row.diff:SetTextColor(r, g, b)
            row.percent:SetText(string.format("%+.2f %%", entry.percent))
            row.percent:SetTextColor(r, g, b)
            local fill = maxAbs > 0 and math.abs(entry.percent) / maxAbs or 0
            row.bar:ClearAllPoints()
            row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.bar:SetWidth(math.max(1, (width - 2) * fill))
            row.bar:SetTexture(r, g, b, 0.12)
            row.bar:Show()
        end
        row:Show()
    end
    HideFrom(breakdownRows, shown + 1)
end

local function LayoutCards(count)
    local width = (CONTENT_WIDTH - CARD_GAP * (count - 1)) / count
    for index, card in ipairs(cards) do
        if index <= count then
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", comparePage, "TOPLEFT", (index - 1) * (width + CARD_GAP), 0)
            card:SetWidth(width)
            card:Show()
        else
            card:Hide()
        end
    end
end

function SimulateX_Comparador_Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    if talentsContent and talentsContent.refresh then
        talentsContent.refresh()
    end

    local linkA = cards[1].link
    local targets, multi = PrepareTargets(linkA)
    LayoutCards(multi and 3 or 2)

    -- colores de las estadísticas: A frente a B, y B/C frente a A
    local firstTarget = targets[1]
    local refLink = firstTarget and not firstTarget.empty and (firstTarget.link or firstTarget.card.auto)
    local refForA = refLink and SimulateX_API.GetItemStats(refLink) or nil
    local statsA = linkA and SimulateX_API.GetItemStats(linkA)
    UpdateCard(cards[1], refForA)
    UpdateCard(cards[2], statsA)
    if multi then
        UpdateCard(cards[3], statsA)
    end

    if not linkA then
        HideFrom(resultRows, 1)
        HideFrom(breakdownRows, 1)
        for _, header in ipairs(columnHeaders) do header:Hide() end
        resultsFrame.emptyText:SetText("Pon en A el objeto que quieres valorar: arrástralo o haz Mayús+clic en él.")
        resultsFrame.emptyText:Show()
        breakdownFrame.emptyText:SetText("")
        breakdownFrame.title:SetText("Por qué")
        SetVerdict("Anillos y abalorios se comparan con los dos que llevas.", 0.7, 0.7, 0.7)
        return
    end

    local perTarget = {}
    for i, target in ipairs(targets) do
        local evaluations, errorMsg = SimulateX_API.GetComparisonEvaluations(linkA, target.link, target.empty)
        if not evaluations then
            HideFrom(resultRows, 1)
            HideFrom(breakdownRows, 1)
            for _, header in ipairs(columnHeaders) do header:Hide() end
            resultsFrame.emptyText:SetText(errorMsg and ("A y " .. CARD_LETTERS[i + 1] .. " " .. errorMsg .. ".")
                or "Todavía no hay datos de simulación para tu clase.")
            resultsFrame.emptyText:Show()
            breakdownFrame.emptyText:SetText("")
            breakdownFrame.title:SetText("Por qué")
            SetVerdict(errorMsg and "Cambia uno de los dos objetos." or "Sin datos.", 1, 0.35, 0.35)
            return
        end
        perTarget[i] = evaluations
    end
    resultsFrame.emptyText:Hide()

    local rows = MergeEvaluations(perTarget)
    RenderResults(rows, targets)
    local bestIndex, active = RenderVerdict(rows, targets, linkA, multi)
    RenderBreakdown(linkA, bestIndex and targets[bestIndex], active)
end

--[[----------------------------------------------------------------------
    VENTANA
------------------------------------------------------------------------]]

function SimulateX_Comparador_ApplyOpacity()
    if frame then
        frame:SetBackdropColor(0, 0, 0, SimulateX_DB.comparadorOpacity or DEFAULT_OPACITY)
    end
end

local function SelectTab(index)
    for i, tab in ipairs(tabs) do
        local selected = (i == index)
        SetShown(tab.bg, selected)
        SetShown(tab.bar, selected)
        tab.label:SetTextColor(selected and 1 or 0.7, selected and 1 or 0.7, selected and 1 or 0.7)
        SetShown(tab.page, selected)
    end
    if index == 2 and talentsContent and talentsContent.refresh then
        talentsContent.refresh()
    end
    if index == 3 and configRefresh then
        configRefresh()
    end
end

local function CreateTab(index, text, icon, page)
    local tab = CreateFrame("Button", nil, frame)
    tab:SetWidth(SIDEBAR_WIDTH - 16)
    tab:SetHeight(30)
    tab:SetPoint("TOPLEFT", 12, -HEADER_HEIGHT - 8 - (index - 1) * 34)
    tab.page = page

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetTexture(1, 0.82, 0, 0.14)
    tab.bg:SetAllPoints()
    tab.bar = tab:CreateTexture(nil, "ARTWORK")
    tab.bar:SetTexture(1, 0.82, 0, 0.9)
    tab.bar:SetWidth(3)
    tab.bar:SetPoint("TOPLEFT")
    tab.bar:SetPoint("BOTTOMLEFT")

    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetTexture(1, 1, 1, 0.06)
    highlight:SetAllPoints()

    local iconTexture = tab:CreateTexture(nil, "ARTWORK")
    iconTexture:SetWidth(20)
    iconTexture:SetHeight(20)
    iconTexture:SetPoint("LEFT", 9, 0)
    iconTexture:SetTexture(icon)

    tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tab.label:SetPoint("LEFT", iconTexture, "RIGHT", 7, 0)
    tab.label:SetText(text)

    tab:SetScript("OnClick", function() SelectTab(index) end)
    tabs[index] = tab
end

local function BuildComparePage()
    comparePage = CreateFrame("Frame", nil, frame)
    comparePage:SetPoint("TOPLEFT", CONTENT_LEFT, -HEADER_HEIGHT - 8)
    comparePage:SetPoint("BOTTOMRIGHT", -CONTENT_RIGHT, 14)

    for index = 1, 3 do
        cards[index] = CreateCard(comparePage, index)
    end

    local hint = comparePage:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", comparePage, "TOPLEFT", 2, -CARD_HEIGHT - 5)
    hint:SetText("Arrastra un objeto o Mayús+clic en él. Clic derecho en una tarjeta la vacía.")

    verdictBg = comparePage:CreateTexture(nil, "BACKGROUND")
    verdictBg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    verdictBg:SetAlpha(0.12)
    verdictBg:SetPoint("TOPLEFT", comparePage, "TOPLEFT", 0, -CARD_HEIGHT - 22)
    verdictBg:SetPoint("RIGHT", comparePage, "RIGHT", 0, 0)
    verdictBg:SetHeight(28)
    verdictText = comparePage:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    verdictText:SetPoint("LEFT", verdictBg, "LEFT", 10, 0)
    verdictText:SetPoint("RIGHT", verdictBg, "RIGHT", -10, 0)
    verdictText:SetJustifyH("LEFT")

    local columnWidth = (CONTENT_WIDTH - 16) / 2
    local sectionTop = -CARD_HEIGHT - 80

    resultsFrame = CreateFrame("Frame", nil, comparePage)
    resultsFrame:SetPoint("TOPLEFT", comparePage, "TOPLEFT", 0, sectionTop)
    resultsFrame:SetPoint("BOTTOM", comparePage, "BOTTOM", 0, 0)
    resultsFrame:SetWidth(columnWidth)
    local resultsTitle = CreateSectionHeader(resultsFrame, "Por especialización")
    resultsTitle:SetPoint("BOTTOMLEFT", resultsFrame, "TOPLEFT", 0, 4)
    for i = 1, 2 do
        local header = resultsFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        header:SetJustifyH("RIGHT")
        header:SetWidth(70)
        columnHeaders[i] = header
    end
    resultsFrame.emptyText = resultsFrame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    resultsFrame.emptyText:SetPoint("TOPLEFT", 4, -8)
    resultsFrame.emptyText:SetPoint("RIGHT", -4, 0)
    resultsFrame.emptyText:SetJustifyH("LEFT")
    resultsFrame.emptyText:SetWordWrap(true)

    breakdownFrame = CreateFrame("Frame", nil, comparePage)
    breakdownFrame:SetPoint("TOPRIGHT", comparePage, "TOPRIGHT", 0, sectionTop)
    breakdownFrame:SetPoint("BOTTOM", comparePage, "BOTTOM", 0, 0)
    breakdownFrame:SetWidth(columnWidth)
    breakdownFrame.title = CreateSectionHeader(breakdownFrame, "Por qué")
    breakdownFrame.title:SetPoint("BOTTOMLEFT", breakdownFrame, "TOPLEFT", 0, 4)
    local legendStat = breakdownFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    legendStat:SetPoint("TOPLEFT", 4, -6)
    legendStat:SetText("Estadística")
    local legendDiff = breakdownFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    legendDiff:SetPoint("TOPRIGHT", -60, -6)
    legendDiff:SetText("A - B")
    local legendPercent = breakdownFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    legendPercent:SetPoint("TOPRIGHT", -2, -6)
    legendPercent:SetText("aporte")
    breakdownFrame.emptyText = breakdownFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    breakdownFrame.emptyText:SetPoint("TOPLEFT", 4, -22)
    breakdownFrame.emptyText:SetPoint("RIGHT", -4, 0)
    breakdownFrame.emptyText:SetJustifyH("LEFT")
    breakdownFrame.emptyText:SetWordWrap(true)
end

local function BuildConfigPage()
    configPage = CreateFrame("Frame", "SimulateXComparadorConfig", frame)
    configPage:SetPoint("TOPLEFT", CONTENT_LEFT - 12, -HEADER_HEIGHT + 4)
    configPage:SetPoint("BOTTOMRIGHT", -CONTENT_RIGHT, 14)
    configRefresh = SimulateX_BuildOptions(configPage, "SimulateXComparadorConfig", 440)
end

local function BuildTalentsPage()
    talentsPage = CreateFrame("Frame", nil, frame)
    talentsPage:SetPoint("TOPLEFT", CONTENT_LEFT, -HEADER_HEIGHT - 8)
    talentsPage:SetPoint("BOTTOMRIGHT", -CONTENT_RIGHT, 14)
    talentsContent = SimulateX_BuildTalentsPage(talentsPage)
end

local function BuildFrame()
    frame = CreateFrame("Frame", "SimulateXComparadorFrame", UIParent)
    frame:SetWidth(PANEL_WIDTH)
    frame:SetHeight(PANEL_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 16, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    SimulateX_Comparador_ApplyOpacity()
    frame:Hide()
    -- Esc la cierra, como las ventanas del juego
    table.insert(UISpecialFrames, "SimulateXComparadorFrame")

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -6, -6)

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetWidth(34)
    logo:SetHeight(34)
    logo:SetPoint("TOPLEFT", 18, -14)
    logo:SetTexture("Interface\\Addons\\SimulateX\\Media\\SimulateX")

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -2)
    title:SetText("SimulateX")

    local version = GetAddOnMetadata("SimulateX", "Version")
    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetText("Comparador de equipo" .. (version and ("  ·  v" .. version) or ""))

    local headerLine = frame:CreateTexture(nil, "ARTWORK")
    headerLine:SetTexture(1, 0.82, 0, 0.3)
    headerLine:SetHeight(1)
    headerLine:SetPoint("TOPLEFT", 12, -HEADER_HEIGHT)
    headerLine:SetPoint("TOPRIGHT", -12, -HEADER_HEIGHT)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(1, 0.82, 0, 0.25)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDEBAR_WIDTH, -HEADER_HEIGHT)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDEBAR_WIDTH, 12)

    BuildComparePage()
    BuildTalentsPage()
    BuildConfigPage()
    CreateTab(1, "Comparador", "Interface\\Addons\\SimulateX\\Media\\SimulateX", comparePage)
    CreateTab(2, "Talentos", "Interface\\Icons\\Spell_Nature_ProtectionformNature", talentsPage)
    CreateTab(3, "Configuración", "Interface\\Icons\\INV_Misc_Gear_01", configPage)
    SelectTab(1)

    frame:SetScript("OnHide", function()
        for _, card in ipairs(cards) do
            card.link = nil
            StopWaiting(card)
        end
    end)
    frame:SetScript("OnShow", function()
        SelectTab(1)
        SimulateX_Comparador_Refresh()
    end)
end

function SimulateX_Comparador_Toggle()
    if not frame then
        BuildFrame()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Cambiar de equipo con la ventana abierta cambia lo que se compara
local equipWatcher = CreateFrame("Frame")
equipWatcher:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
equipWatcher:SetScript("OnEvent", function()
    SimulateX_Comparador_Refresh()
end)

-- Mayús+clic con la ventana abierta y sin caja de chat activa: va a A si
-- está vacía, si no a la primera de B/C que el jugador no haya rellenado
-- (mismo mecanismo que la Casa de Subastas, ver HandleModifiedItemClick).
hooksecurefunc("ChatEdit_InsertLink", function(text)
    if not frame or not frame:IsShown() or not text then
        return
    end
    if ChatEdit_GetActiveWindow() or not text:match("item:%d+") then
        return
    end
    if not cards[1].link then
        SetCardItem(cards[1], text)
    elseif not cards[2].link then
        SetCardItem(cards[2], text)
    elseif cards[3]:IsShown() and not cards[3].link then
        SetCardItem(cards[3], text)
    end
end)
