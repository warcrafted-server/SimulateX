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

-- Monta los controles de configuración en parent. Los usan el panel de
-- Interfaz > AddOns y la pestaña Configuración del comparador: prefix separa
-- los nombres globales que piden las plantillas ($parentText...). Devuelve la
-- función que relee SimulateX_DB, a llamar cada vez que se muestre.
function SimulateX_BuildOptions(parent, prefix, textWidth)
    textWidth = textWidth or 380

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

    local function RebuildSpecCheckboxes()
        for _, checkbox in ipairs(specCheckboxes) do
            checkbox:Hide()
        end

        local classFileName = select(2, UnitClass("player"))
        local dataVarName = SimulateX_ClassDataVars and SimulateX_ClassDataVars[classFileName]
        local classData = dataVarName and _G[dataVarName]
        if not classData then
            return
        end

        -- los checkbox se reciclan: los nombres globales no se pueden liberar
        for index, specLabel in ipairs(GetAllSpecLabelsForClass(classData)) do
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

    return function()
        lowLevelCheck:SetChecked(not SimulateX_DB.lowLevelEstimateDisabled)
        otherArrowCheck:SetChecked(not SimulateX_DB.otherSpecArrowDisabled)
        minimapCheck:SetChecked(not SimulateX_DB.minimapHidden)
        opacitySlider:SetValue(SimulateX_DB.comparadorOpacity or DEFAULT_OPACITY)
        RebuildSpecCheckboxes()
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
