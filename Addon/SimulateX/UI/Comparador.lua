--[[----------------------------------------------------------------------
    Comparador de equipo (v0.6): dos huecos, A y B. B vacío = A contra lo
    equipado. Usa SimulateX_API (SimulateX.lua) para el cálculo, nunca
    duplica la lógica de puntuación.
------------------------------------------------------------------------]]

local PANEL_WIDTH = 460
local SIDEBAR_WIDTH = 130
local CONTENT_LEFT = 146
local CONTENT_TOP = -86
local BOTTOM_MARGIN = 18
local SLOT_SIZE = 40

local frame, slotA, slotB, resultsFrame
local rowPool = {}
local breakdownPool = {}

--[[----------------------------------------------------------------------
    HUECO DE OBJETO: icono + borde, arrastrar/soltar, mayús+clic, clic
    derecho para vaciar. slot.link/slot.itemId guardan lo que contiene.
------------------------------------------------------------------------]]

local function SetSlotItem(slot, itemLink)
    slot.link = itemLink
    slot.itemId = itemLink and tonumber(itemLink:match("item:(%d+)"))
    if itemLink then
        local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemLink)
        slot.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        slot.icon:Show()
        slot.placeholder:Hide()
    else
        slot.icon:Hide()
        slot.placeholder:Show()
    end
    SimulateX_Comparador_Refresh()
end

local function CreateItemSlot(parent, label)
    local container = CreateFrame("Frame", nil, parent)
    container:SetWidth(SLOT_SIZE + 8)
    container:SetHeight(SLOT_SIZE + 26)

    local labelText = container:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    labelText:SetPoint("TOP", 0, 0)
    labelText:SetText(label)

    local slot = CreateFrame("Button", nil, container)
    slot:SetWidth(SLOT_SIZE)
    slot:SetHeight(SLOT_SIZE)
    slot:SetPoint("TOP", labelText, "BOTTOM", 0, -6)
    slot:SetNormalTexture("Interface\\Buttons\\UI-EmptySlot")
    slot:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")

    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetPoint("TOPLEFT", 3, -3)
    slot.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    slot.icon:Hide()

    slot.placeholder = slot:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    slot.placeholder:SetPoint("CENTER", 0, 0)
    slot.placeholder:SetText("+")

    slot:SetScript("OnReceiveDrag", function(self)
        local cursorType, _, itemLink = GetCursorInfo()
        if cursorType == "item" and itemLink then
            SetSlotItem(self, itemLink)
        end
        ClearCursor()
    end)
    slot:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            SetSlotItem(self, nil)
            return
        end
        local cursorType, _, itemLink = GetCursorInfo()
        if cursorType == "item" and itemLink then
            SetSlotItem(self, itemLink)
            ClearCursor()
        end
    end)
    slot:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    container.slot = slot
    return container, slot
end

--[[----------------------------------------------------------------------
    RESULTADOS: una fila por spec (icono de flecha si aplica + nombre +
    %), y debajo el desglose de la spec activa.
------------------------------------------------------------------------]]

local function GetRow(index)
    local row = rowPool[index]
    if not row then
        row = CreateFrame("Frame", nil, resultsFrame)
        row:SetHeight(16)
        row:SetPoint("LEFT", resultsFrame, "LEFT", 0, 0)
        row:SetPoint("RIGHT", resultsFrame, "RIGHT", 0, 0)
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", 0, 0)
        row.value = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.value:SetPoint("RIGHT", 0, 0)
        rowPool[index] = row
    end
    row:Show()
    return row
end

local function GetBreakdownRow(index)
    local row = breakdownPool[index]
    if not row then
        row = CreateFrame("Frame", nil, resultsFrame)
        row:SetHeight(14)
        row:SetPoint("LEFT", resultsFrame, "LEFT", 12, 0)
        row:SetPoint("RIGHT", resultsFrame, "RIGHT", 0, 0)
        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.label:SetPoint("LEFT", 0, 0)
        row.value = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        row.value:SetPoint("RIGHT", 0, 0)
        breakdownPool[index] = row
    end
    row:Show()
    return row
end

local function HideExtraRows(pool, fromIndex)
    for i = fromIndex, #pool do
        pool[i]:Hide()
    end
end

local function FormatPercentText(evaluation)
    if evaluation.isNoise then
        return "≈ igual", 0.6, 0.6, 0.6
    end
    if evaluation.gain > 0 then
        return string.format("%+.1f %%", evaluation.percent), 0.1, 1, 0.1
    end
    return string.format("%+.1f %%", evaluation.percent), 1, 0.3, 0.3
end

function SimulateX_Comparador_Refresh()
    if not frame or not frame:IsShown() then
        return
    end

    local linkA = slotA.link
    if not linkA then
        for _, row in ipairs(rowPool) do row:Hide() end
        for _, row in ipairs(breakdownPool) do row:Hide() end
        resultsFrame.emptyText:Show()
        return
    end

    local evaluations, errorMsg = SimulateX_API.GetComparisonEvaluations(linkA, slotB.link)
    if not evaluations or #evaluations == 0 then
        HideExtraRows(rowPool, 1)
        HideExtraRows(breakdownPool, 1)
        resultsFrame.emptyText:SetText(errorMsg or "Sin datos de simulación para tu clase todavía.")
        resultsFrame.emptyText:Show()
        return
    end
    resultsFrame.emptyText:Hide()

    local rowIndex = 0
    local activeEvaluation
    for _, evaluation in ipairs(evaluations) do
        rowIndex = rowIndex + 1
        local row = GetRow(rowIndex)
        local text, r, g, b = FormatPercentText(evaluation)
        if evaluation.isActive then
            row.label:SetText(evaluation.specLabel .. " (tu spec)")
            row.label:SetTextColor(1, 1, 1)
            activeEvaluation = evaluation
        else
            row.label:SetText(evaluation.specLabel)
            row.label:SetTextColor(0.75, 0.75, 0.75)
        end
        row.value:SetText(text)
        row.value:SetTextColor(r, g, b)
    end
    HideExtraRows(rowPool, rowIndex + 1)

    local breakdownIndex = 0
    if activeEvaluation then
        local rows = SimulateX_API.GetComparisonBreakdown(linkA, slotB.link, activeEvaluation.buildId)
        if rows then
            for _, entry in ipairs(rows) do
                breakdownIndex = breakdownIndex + 1
                local row = GetBreakdownRow(breakdownIndex)
                local sign = entry.diff >= 0 and "+" or ""
                row.label:SetText(entry.label)
                row.value:SetText(string.format("%s%.0f (%s%.1f %%)", sign, entry.diff, sign, entry.percent))
                if entry.diff >= 0 then
                    row.value:SetTextColor(0.4, 0.9, 0.4)
                else
                    row.value:SetTextColor(0.9, 0.4, 0.4)
                end
            end
        end
    end
    HideExtraRows(breakdownPool, breakdownIndex + 1)

    -- reposicionar filas (spec, luego desglose debajo)
    local y = 0
    for i = 1, rowIndex do
        local row = rowPool[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", resultsFrame, "RIGHT", 0, 0)
        y = y + 16
    end
    if breakdownIndex > 0 then
        y = y + 6
        local title = resultsFrame.breakdownTitle
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 0, -y)
        title:Show()
        y = y + 14
    else
        resultsFrame.breakdownTitle:Hide()
    end
    for i = 1, breakdownIndex do
        local row = breakdownPool[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 12, -y)
        row:SetPoint("RIGHT", resultsFrame, "RIGHT", 0, 0)
        y = y + 14
    end
end

--[[----------------------------------------------------------------------
    VENTANA
------------------------------------------------------------------------]]

local function BuildFrame()
    frame = CreateFrame("Frame", "SimulateXComparadorFrame", UIParent)
    frame:SetWidth(PANEL_WIDTH)
    frame:SetHeight(360)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:Hide()

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -4, -4)
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("SimulateX")

    -- Pestaña lateral (una sola por ahora; hub para Talentos en v0.7)
    local tabButton = CreateFrame("Button", nil, frame)
    tabButton:SetWidth(SIDEBAR_WIDTH - 12)
    tabButton:SetHeight(28)
    tabButton:SetPoint("TOPLEFT", 12, CONTENT_TOP)
    local tabBg = tabButton:CreateTexture(nil, "BACKGROUND")
    tabBg:SetTexture(1, 0.82, 0, 0.14)
    tabBg:SetAllPoints()
    local tabBar = tabButton:CreateTexture(nil, "ARTWORK")
    tabBar:SetTexture(1, 0.82, 0, 0.9)
    tabBar:SetWidth(3)
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetPoint("BOTTOMLEFT", 0, 0)
    local tabIcon = tabButton:CreateTexture(nil, "ARTWORK")
    tabIcon:SetWidth(20)
    tabIcon:SetHeight(20)
    tabIcon:SetPoint("LEFT", 8, 0)
    tabIcon:SetTexture("Interface\\Addons\\SimulateX\\Media\\SimulateX")
    local tabLabel = tabButton:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tabLabel:SetPoint("LEFT", tabIcon, "RIGHT", 6, 0)
    tabLabel:SetText("Comparador")
    tabLabel:SetTextColor(1, 1, 1)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(1, 0.82, 0, 0.25)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_LEFT - 1, CONTENT_TOP)
    divider:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", CONTENT_LEFT - 1, BOTTOM_MARGIN)

    -- Tarjeta de huecos
    local card = CreateFrame("Frame", nil, frame)
    card:SetPoint("TOPLEFT", frame, "TOPLEFT", CONTENT_LEFT, CONTENT_TOP)
    card:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
    card:SetHeight(90)
    card:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
    })
    card:SetBackdropColor(0, 0, 0, 0.5)
    card:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)

    local slotAContainer
    slotAContainer, slotA = CreateItemSlot(card, "A")
    slotAContainer:SetPoint("LEFT", card, "LEFT", 30, 0)

    local vsText = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    vsText:SetPoint("CENTER", card, "CENTER", 0, 4)
    vsText:SetText("vs.")

    local slotBContainer
    slotBContainer, slotB = CreateItemSlot(card, "B (o equipado)")
    slotBContainer:SetPoint("RIGHT", card, "RIGHT", -30, 0)

    local hint = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", card, "BOTTOM", 0, 6)
    hint:SetText("Arrastra un objeto, o Mayús+clic con esta ventana abierta")

    -- Cabecera de la sección de resultados
    local resultsHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    resultsHeader:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 2, -14)
    resultsHeader:SetText("Comparación por especialización")
    resultsHeader:SetTextColor(1, 0.82, 0)

    local headerLine = frame:CreateTexture(nil, "ARTWORK")
    headerLine:SetTexture(1, 0.82, 0, 0.4)
    headerLine:SetHeight(1)
    headerLine:SetPoint("TOPLEFT", resultsHeader, "BOTTOMLEFT", 0, -3)
    headerLine:SetPoint("RIGHT", card, "RIGHT", 0, 0)

    resultsFrame = CreateFrame("Frame", nil, frame)
    resultsFrame:SetPoint("TOPLEFT", headerLine, "BOTTOMLEFT", 0, -8)
    resultsFrame:SetPoint("RIGHT", card, "RIGHT", 0, 0)
    resultsFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, BOTTOM_MARGIN)

    resultsFrame.emptyText = resultsFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    resultsFrame.emptyText:SetPoint("TOPLEFT", 0, 0)
    resultsFrame.emptyText:SetPoint("RIGHT", 0, 0)
    resultsFrame.emptyText:SetJustifyH("LEFT")
    resultsFrame.emptyText:SetText("Pon un objeto en el hueco A para comparar.")

    resultsFrame.breakdownTitle = resultsFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    resultsFrame.breakdownTitle:SetJustifyH("LEFT")
    resultsFrame.breakdownTitle:SetText("Diferencia de estadísticas (tu spec):")
    resultsFrame.breakdownTitle:SetTextColor(0.8, 0.8, 0.8)
    resultsFrame.breakdownTitle:Hide()

    frame:SetScript("OnHide", function()
        SetSlotItem(slotA, nil)
        SetSlotItem(slotB, nil)
    end)
    frame:SetScript("OnShow", SimulateX_Comparador_Refresh)
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

-- Mayús+clic con la ventana abierta y sin caja de chat activa: mete el link
-- en A si está vacío, si no en B (mismo mecanismo que la Casa de Subastas
-- para "buscar por objeto", ver HandleModifiedItemClick en FrameXML 3.3.5a).
hooksecurefunc("ChatEdit_InsertLink", function(text)
    if not frame or not frame:IsShown() or not text then
        return
    end
    if ChatEdit_GetActiveWindow() then
        return
    end
    local itemId = tonumber(text:match("item:(%d+)"))
    if not itemId then
        return
    end
    if not slotA.link then
        SetSlotItem(slotA, text)
    elseif not slotB.link then
        SetSlotItem(slotB, text)
    end
end)
