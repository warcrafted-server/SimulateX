local ADDON_NAME = ...

local DEFAULT_OPACITY = 0.95

-- Recorre todas las builds de la clase (sin filtrar por spec activa/fase, a
-- diferencia de GetBestBuildPerSpec) solo para listar cada specLabel único
-- una vez, tal como aparecería en el tooltip. classData es una tabla plana
-- { ["spec_fase"] = build, ... }, ver Tools/generar_db_addon.py.
local function GetAllSpecLabelsForClass(classData)
    local seen = {}
    local labels = {}
    for _, build in pairs(classData) do
        if not seen[build.specLabel] then
            seen[build.specLabel] = true
            table.insert(labels, build.specLabel)
        end
    end
    table.sort(labels)
    return labels
end

local function CreateCheck(parent, name, text, width)
    local check = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    local label = _G[name .. "Text"]
    label:SetText(text)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    return check
end

local function CreateSectionTitle(parent, text)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetTexture(1, 0.82, 0, 0.3)
    line:SetHeight(1)
    line:SetPoint("LEFT", title, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    return title
end

-- Monta los controles de configuración en parent, dentro de un ScrollFrame
-- (cada vez hay más secciones y no siempre caben en el panel de Interfaz >
-- AddOns ni en la pestaña Configuración del comparador, de alto fijo). Lo
-- usan ambos: prefix separa los nombres globales que piden las plantillas
-- ($parentText...). Devuelve la función que relee SimulateX_DB, a llamar
-- cada vez que se muestre.
function SimulateX_BuildOptions(parent, prefix, textWidth)
    textWidth = textWidth or 380

    local scrollFrame = CreateFrame("ScrollFrame", prefix .. "Scroll", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, -34)  -- deja sitio arriba (p. ej. el botón "Abrir comparador")
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local bar = _G[self:GetName() .. "ScrollBar"]
        bar:SetValue(bar:GetValue() - delta * 40)
    end)

    local content = CreateFrame("Frame", prefix .. "ScrollContent", scrollFrame)
    content:SetWidth(textWidth + 40)
    content:SetHeight(1)  -- se ajusta al final, según el último control
    scrollFrame:SetScrollChild(content)
    local parent = content  -- todo lo de abajo se ancla dentro del scroll

    local generalTitle = CreateSectionTitle(parent, "Tooltip y flechas")
    generalTitle:SetPoint("TOPLEFT", 16, -16)

    local lowLevelCheck = CreateCheck(parent, prefix .. "LowLevelCheck",
        "Mostrar datos estimados en niveles 1-79 (pesos por punto, sin simulación exacta)", textWidth)
    lowLevelCheck:SetPoint("TOPLEFT", generalTitle, "BOTTOMLEFT", -2, -8)
    lowLevelCheck:SetScript("OnClick", function(self)
        SimulateX_DB.lowLevelEstimateDisabled = not self:GetChecked()
    end)

    local otherArrowCheck = CreateCheck(parent, prefix .. "OtherArrowCheck",
        "Flecha naranja si el objeto solo mejora otra especialización", textWidth)
    otherArrowCheck:SetPoint("TOPLEFT", lowLevelCheck, "BOTTOMLEFT", 0, -2)
    otherArrowCheck:SetScript("OnClick", function(self)
        SimulateX_DB.otherSpecArrowDisabled = not self:GetChecked()
        if SimulateX_RefreshIcons then
            SimulateX_RefreshIcons()
        end
    end)

    local windowTitle = CreateSectionTitle(parent, "Ventana y accesos")
    windowTitle:SetPoint("TOPLEFT", otherArrowCheck, "BOTTOMLEFT", 2, -16)

    local minimapCheck = CreateCheck(parent, prefix .. "MinimapCheck",
        "Botón en el minimapa (hace falta /reload)", textWidth)
    minimapCheck:SetPoint("TOPLEFT", windowTitle, "BOTTOMLEFT", -2, -8)
    minimapCheck:SetScript("OnClick", function(self)
        SimulateX_DB.minimapHidden = not self:GetChecked() or nil
    end)

    local opacitySlider = CreateFrame("Slider", prefix .. "OpacitySlider", parent, "OptionsSliderTemplate")
    opacitySlider:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 6, -24)
    opacitySlider:SetWidth(200)
    opacitySlider:SetMinMaxValues(0.3, 1)
    opacitySlider:SetValueStep(0.05)
    _G[opacitySlider:GetName() .. "Text"]:SetText("Opacidad de la ventana")
    _G[opacitySlider:GetName() .. "Low"]:SetText("30%")
    _G[opacitySlider:GetName() .. "High"]:SetText("100%")

    local opacityValueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    opacityValueText:SetPoint("LEFT", opacitySlider, "RIGHT", 10, 0)

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value * 20 + 0.5) / 20
        SimulateX_DB.comparadorOpacity = value
        opacityValueText:SetText(string.format("%d%%", value * 100))
        if SimulateX_Comparador_ApplyOpacity then
            SimulateX_Comparador_ApplyOpacity()
        end
    end)

    local specsTitle = CreateSectionTitle(parent, "Especializaciones que se muestran")
    specsTitle:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", -6, -28)

    local specCheckboxes = {}

    -- número de filas de specs de la última RebuildSpecCheckboxes: lo que
    -- va debajo (economyTitle) se reancla a esto en el refresh, porque
    -- varía con la clase (1-8 specs).
    local specRowCount = 0

    local function RebuildSpecCheckboxes()
        for _, checkbox in ipairs(specCheckboxes) do
            checkbox:Hide()
        end

        local classFileName = select(2, UnitClass("player"))
        local dataVarName = SimulateX_ClassDataVars and SimulateX_ClassDataVars[classFileName]
        local classData = dataVarName and _G[dataVarName]
        if not classData then
            specRowCount = 0
            return
        end

        local labels = GetAllSpecLabelsForClass(classData)
        specRowCount = math.ceil(#labels / 2)

        -- los checkbox se reciclan: los nombres globales no se pueden liberar
        for index, specLabel in ipairs(labels) do
            local checkbox = specCheckboxes[index]
            if not checkbox then
                checkbox = CreateCheck(parent, prefix .. "SpecCheck" .. index, "", 200)
                -- dos columnas para que quepan en la ventana del comparador
                local column = (index - 1) % 2
                local line = math.floor((index - 1) / 2)
                checkbox:SetPoint("TOPLEFT", specsTitle, "BOTTOMLEFT", -2 + column * 200, -8 - line * 26)
                specCheckboxes[index] = checkbox
            end
            _G[checkbox:GetName() .. "Text"]:SetText(specLabel)
            checkbox:SetChecked(not (SimulateX_DB.disabledSpecs and SimulateX_DB.disabledSpecs[specLabel]))
            checkbox:SetScript("OnClick", function(self)
                SimulateX_DB.disabledSpecs = SimulateX_DB.disabledSpecs or {}
                SimulateX_DB.disabledSpecs[specLabel] = not self:GetChecked() or nil
                if SimulateX_Comparador_Refresh then
                    SimulateX_Comparador_Refresh()
                end
            end)
            checkbox:Show()
        end
    end

    local economyTitle = CreateSectionTitle(parent, "Economía en el vendedor")
    economyTitle:SetPoint("TOPLEFT", specsTitle, "BOTTOMLEFT", 6, -28)  -- reancla en refresh según specRowCount

    local sellGreysCheck = CreateCheck(parent, prefix .. "SellGreysCheck",
        "Vender objetos grises automáticamente al abrir un vendedor", textWidth)
    sellGreysCheck:SetPoint("TOPLEFT", economyTitle, "BOTTOMLEFT", -2, -8)
    sellGreysCheck:SetScript("OnClick", function(self)
        SimulateX_DB.autoSellGreysEnabled = self:GetChecked() or nil
    end)

    local whitelistHint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    whitelistHint:SetPoint("TOPLEFT", sellGreysCheck, "BOTTOMLEFT", 24, -4)
    whitelistHint:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
    whitelistHint:SetJustifyH("LEFT")
    whitelistHint:SetWordWrap(true)
    whitelistHint:SetText("Ctrl+clic en un objeto gris de la bolsa lo protege (o lo vuelve a permitir): nunca se vende solo aunque sea gris.")

    local repairTitle = CreateSectionTitle(parent, "Reparación automática")
    repairTitle:SetPoint("TOPLEFT", whitelistHint, "BOTTOMLEFT", -22, -20)

    local repairModes = {
        { value = "off", label = "Desactivada" },
        { value = "self", label = "Con mi dinero" },
        { value = "guild", label = "Con el banco de hermandad (si puedo)" },
    }
    local repairRadios = {}
    for index, mode in ipairs(repairModes) do
        local radio = CreateFrame("CheckButton", prefix .. "RepairRadio" .. index, parent, "UIRadioButtonTemplate")
        local label = _G[radio:GetName() .. "Text"]
        label:SetText(mode.label)
        label:SetWidth(textWidth - 20)
        label:SetJustifyH("LEFT")
        radio:SetPoint("TOPLEFT", repairTitle, "BOTTOMLEFT", -4, -8 - (index - 1) * 22)
        radio:SetScript("OnClick", function()
            SimulateX_DB.repairMode = mode.value
            for _, other in ipairs(repairRadios) do
                other:SetChecked(other == radio)
            end
        end)
        repairRadios[index] = radio
    end

    local sellPriceTitle = CreateSectionTitle(parent, "Tooltip")
    sellPriceTitle:SetPoint("TOPLEFT", repairTitle, "BOTTOMLEFT", 6, -8 - #repairModes * 22 - 16)

    local sellPriceCheck = CreateCheck(parent, prefix .. "SellPriceCheck",
        "Precio de venta al vendedor en el tooltip (útil si no tienes addon de subastas)", textWidth)
    sellPriceCheck:SetPoint("TOPLEFT", sellPriceTitle, "BOTTOMLEFT", -2, -8)
    sellPriceCheck:SetScript("OnClick", function(self)
        SimulateX_DB.sellPriceTooltipDisabled = not self:GetChecked()
    end)

    local questRewardTitle = CreateSectionTitle(parent, "Recompensas de misión")
    questRewardTitle:SetPoint("TOPLEFT", sellPriceCheck, "BOTTOMLEFT", 2, -16)

    local questRewardCheck = CreateCheck(parent, prefix .. "QuestRewardCheck",
        "Marcar la mejor recompensa para tu especialización (o, si ninguna mejora, la de más valor)", textWidth)
    questRewardCheck:SetPoint("TOPLEFT", questRewardTitle, "BOTTOMLEFT", -2, -8)
    questRewardCheck:SetScript("OnClick", function(self)
        SimulateX_DB.questRewardHintDisabled = not self:GetChecked()
    end)

    -- El número de specs (y por tanto la altura de RebuildSpecCheckboxes)
    -- solo se sabe tras rellenar los checkboxes, así que la altura del
    -- contenido se recalcula aquí, no al construir.
    local function UpdateContentHeight()
        content:SetScript("OnUpdate", function(self)
            self:SetScript("OnUpdate", nil)
            local bottom = questRewardCheck:GetBottom()
            local top = self:GetTop()
            if bottom and top then
                self:SetHeight(math.max(1, top - bottom + 20))
            end
        end)
    end

    return function()
        lowLevelCheck:SetChecked(not SimulateX_DB.lowLevelEstimateDisabled)
        otherArrowCheck:SetChecked(not SimulateX_DB.otherSpecArrowDisabled)
        minimapCheck:SetChecked(not SimulateX_DB.minimapHidden)
        opacitySlider:SetValue(SimulateX_DB.comparadorOpacity or DEFAULT_OPACITY)
        RebuildSpecCheckboxes()
        economyTitle:ClearAllPoints()
        economyTitle:SetPoint("TOPLEFT", specsTitle, "BOTTOMLEFT", 6, -8 - specRowCount * 26 - 20)
        sellGreysCheck:SetChecked(SimulateX_DB.autoSellGreysEnabled)
        local currentRepairMode = SimulateX_DB.repairMode or "off"
        for index, mode in ipairs(repairModes) do
            repairRadios[index]:SetChecked(mode.value == currentRepairMode)
        end
        sellPriceCheck:SetChecked(not SimulateX_DB.sellPriceTooltipDisabled)
        questRewardCheck:SetChecked(not SimulateX_DB.questRewardHintDisabled)
        UpdateContentHeight()
    end
end

local panel = CreateFrame("Frame", "SimulateXOptionsPanel", UIParent)
panel.name = "SimulateX"

local openButton = CreateFrame("Button", "SimulateXOptionsOpenButton", panel, "UIPanelButtonTemplate")
openButton:SetWidth(150)
openButton:SetHeight(22)
openButton:SetPoint("TOPRIGHT", -16, -12)
openButton:SetText("Abrir comparador")
openButton:SetScript("OnClick", function()
    if SimulateX_Comparador_Toggle then
        SimulateX_Comparador_Toggle()
    end
end)

panel.refresh = SimulateX_BuildOptions(panel, "SimulateXOptions")

local function OnEvent(self, event, addOnName)
    if event == "ADDON_LOADED" and addOnName == ADDON_NAME then
        InterfaceOptions_AddCategory(panel)
    end
end

panel:RegisterEvent("ADDON_LOADED")
panel:SetScript("OnEvent", OnEvent)

SLASH_SIMULATEXOPTIONS1 = "/simulatexconfig"
SlashCmdList["SIMULATEXOPTIONS"] = function()
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
end
