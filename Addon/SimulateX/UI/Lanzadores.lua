--[[----------------------------------------------------------------------
    Formas de abrir el comparador (v0.6): botón en la hoja de personaje,
    botón de minimapa propio, objeto LibDataBroker para wcdpanel.
------------------------------------------------------------------------]]

local ICON_PATH = "Interface\\Addons\\SimulateX\\Media\\SimulateX"

--[[----------------------------------------------------------------------
    BOTÓN EN LA HOJA DE PERSONAJE
------------------------------------------------------------------------]]

local function CreateCharacterButton()
    if not CharacterFrame then
        return
    end
    local button = CreateFrame("Button", "SimulateXCharacterButton", CharacterFrame)
    button:SetWidth(24)
    button:SetHeight(24)
    button:SetPoint("TOPLEFT", CharacterFrame, "TOPLEFT", 34, -6)
    button:SetFrameLevel(CharacterFrame:GetFrameLevel() + 5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ICON_PATH)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(46)
    border:SetHeight(46)
    border:SetPoint("TOPLEFT", -9, 9)

    button:SetScript("OnClick", function() SimulateX_Comparador_Toggle() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SimulateX")
        GameTooltip:AddLine("Abrir el comparador de equipo", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

--[[----------------------------------------------------------------------
    BOTÓN DE MINIMAPA: no se crea si wcdpanel está cargado (su plugin
    MinimapButtons recogería el objeto LDB de abajo y saldría duplicado).
------------------------------------------------------------------------]]

local MINIMAP_RADIUS = 80

local function ApplyMinimapPosition(button)
    local angle = math.rad(SimulateX_DB.minimapAngle or 220)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * MINIMAP_RADIUS, math.sin(angle) * MINIMAP_RADIUS)
end

local function CreateMinimapButton()
    if WCDPanel then
        return  -- wcdpanel enseña el objeto LDB de abajo, no duplicar el icono
    end
    if SimulateX_DB.minimapHidden then
        return
    end

    local button = CreateFrame("Button", "SimulateXMinimapButton", Minimap)
    button:SetWidth(31)
    button:SetHeight(31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ICON_PATH)
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", 0, 1)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetWidth(54)
    border:SetHeight(54)
    border:SetPoint("TOPLEFT", 0, 0)

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            SimulateX_Comparador_Toggle()
        else
            InterfaceOptionsFrame_OpenToCategory(SimulateXOptionsPanel)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("SimulateX")
        GameTooltip:AddLine("Clic izquierdo: comparador de equipo", 1, 1, 1)
        GameTooltip:AddLine("Clic derecho: opciones", 1, 1, 1)
        GameTooltip:AddLine("Arrastrar: mover el icono", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            SimulateX_DB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
            ApplyMinimapPosition(self)
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    ApplyMinimapPosition(button)
end

--[[----------------------------------------------------------------------
    LibDataBroker: para la barra de wcdpanel (u otro launcher LDB). Sin
    librerías propias: solo se registra si LibStub y LibDataBroker-1.1 ya
    están disponibles (aportados por wcdpanel u otro addon).
------------------------------------------------------------------------]]

local function CreateDataBrokerObject()
    if not LibStub then
        return
    end
    local ok, ldb = pcall(LibStub, "LibDataBroker-1.1", true)
    if not ok or not ldb then
        return
    end
    ldb:NewDataObject("SimulateX", {
        type = "launcher",
        icon = ICON_PATH,
        OnClick = function(self, mouseButton)
            if mouseButton == "RightButton" then
                InterfaceOptionsFrame_OpenToCategory(SimulateXOptionsPanel)
            else
                SimulateX_Comparador_Toggle()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("SimulateX")
            tooltip:AddLine("Clic izquierdo: comparador de equipo", 1, 1, 1)
            tooltip:AddLine("Clic derecho: opciones", 1, 1, 1)
        end,
    })
end

function SimulateX_Lanzadores_Init()
    CreateCharacterButton()
    CreateMinimapButton()
    CreateDataBrokerObject()
end
