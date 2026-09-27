local ADDON_NAME = ...

local panel = CreateFrame("Frame", "SimulateXOptionsPanel", UIParent)
panel.name = "SimulateX"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("SimulateX")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
subtitle:SetHeight(28)
subtitle:SetJustifyH("LEFT")
subtitle:SetJustifyV("TOP")
subtitle:SetText("Elige qué sub-especializaciones de tu clase se muestran en el tooltip y si quieres el modo estimado en niveles 1-79.")

local lowLevelCheck = CreateFrame("CheckButton", "SimulateXOptionsLowLevelCheck", panel, "UICheckButtonTemplate")
lowLevelCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -20)
local lowLevelText = _G[lowLevelCheck:GetName() .. "Text"]
lowLevelText:SetText("Mostrar estimación en niveles 1-79 (aproximación, no es una simulación real)")
lowLevelText:SetWidth(380)
lowLevelText:SetJustifyH("LEFT")

lowLevelCheck:SetScript("OnClick", function(self)
    SimulateX_DB.lowLevelEstimateDisabled = not self:GetChecked()
end)

local specsLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
specsLabel:SetPoint("TOPLEFT", lowLevelCheck, "BOTTOMLEFT", 2, -20)
specsLabel:SetText("Sub-especializaciones a mostrar (nivel 80):")

local specCheckboxes = {}

-- Recorre todas las builds de la clase (sin filtrar por spec activa/fase, a
-- diferencia de GetBestBuildPerSpec) solo para listar cada specLabel único
-- una vez, tal como aparecería en el tooltip.
local function GetAllSpecLabelsForClass(classData)
    local seen = {}
    local labels = {}
    for _, build in pairs(classData.builds) do
        if not seen[build.specLabel] then
            seen[build.specLabel] = true
            table.insert(labels, build.specLabel)
        end
    end
    table.sort(labels)
    return labels
end

local function RebuildSpecCheckboxes()
    for _, checkbox in ipairs(specCheckboxes) do
        checkbox:Hide()
        checkbox:SetParent(nil)
    end
    wipe(specCheckboxes)

    local classFileName = select(2, UnitClass("player"))
    local dataVarName = SimulateX_ClassDataVars and SimulateX_ClassDataVars[classFileName]
    local classData = dataVarName and _G[dataVarName]
    if not classData then
        return
    end

    local labels = GetAllSpecLabelsForClass(classData)
    local anchor = specsLabel
    for _, specLabel in ipairs(labels) do
        local checkbox = CreateFrame("CheckButton", "SimulateXOptionsSpecCheck" .. #specCheckboxes, panel, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == specsLabel and 2 or 0, -8)
        _G[checkbox:GetName() .. "Text"]:SetText(specLabel)
        checkbox:SetChecked(not (SimulateX_DB.disabledSpecs and SimulateX_DB.disabledSpecs[specLabel]))
        checkbox:SetScript("OnClick", function(self)
            SimulateX_DB.disabledSpecs = SimulateX_DB.disabledSpecs or {}
            SimulateX_DB.disabledSpecs[specLabel] = not self:GetChecked() or nil
        end)
        table.insert(specCheckboxes, checkbox)
        anchor = checkbox
    end
end

panel.refresh = function()
    lowLevelCheck:SetChecked(not SimulateX_DB.lowLevelEstimateDisabled)
    RebuildSpecCheckboxes()
end

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
