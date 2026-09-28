--[[----------------------------------------------------------------------
    Pestaña Talentos (v0.7, primera maqueta): compara el dps/hps/tps base de
    cada distribución de talentos simulada para tu spec, con el mismo gear.
    Datos en SimulateX_Talentos_<Clase> (Tools/simular_talentos.py); si no
    existen para la clase, se enseña un aviso en vez de la tabla.
------------------------------------------------------------------------]]

local ROW_HEIGHT = 26
local rows = {}

-- mismo umbral que el comparador de equipo (SimulateX.lua::NOISE_THRESHOLD_PCT)
local NOISE_THRESHOLD_PCT = 0.3

local function GetTalentDataForClass()
    local classFileName = select(2, UnitClass("player"))
    local varName = SimulateX_TalentDataVars and SimulateX_TalentDataVars[classFileName]
    return varName and _G[varName]
end

local function GetRow(parent, index)
    local row = rows[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetJustifyH("LEFT")
    row.value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.value:SetPoint("RIGHT", -70, 0)
    row.value:SetJustifyH("RIGHT")
    row.percent = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.percent:SetPoint("RIGHT", -8, 0)
    row.percent:SetWidth(56)
    row.percent:SetJustifyH("RIGHT")
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetHeight(3)
    rows[index] = row
    return row
end

local function HideFrom(index)
    for i = index, #rows do rows[i]:Hide() end
end

-- Refresca la tabla de la spec cuyo talentTree coincida con specKey (el
-- selector de spec arriba de la tabla la cambia).
local function RenderVariants(page, spec)
    local data = GetTalentDataForClass()
    local specData = data and data[spec]
    if not specData or not specData.variants or #specData.variants == 0 then
        page.emptyText:SetText(specData and "Sin variantes simuladas todavía para esta especialización."
            or "SimulateX no tiene datos de talentos para tu clase todavía.")
        page.emptyText:Show()
        HideFrom(1)
        return
    end
    page.emptyText:Hide()

    local metric = specData.metric or "dps"
    local best = 0
    for _, variant in ipairs(specData.variants) do
        best = math.max(best, variant[metric] or 0)
    end

    local allTied = #specData.variants > 1
    if allTied then
        for _, variant in ipairs(specData.variants) do
            local diff = best > 0 and ((variant[metric] or 0) / best - 1) * 100 or 0
            if math.abs(diff) >= NOISE_THRESHOLD_PCT then
                allTied = false
                break
            end
        end
    end
    if allTied then page.tiedText:Show() else page.tiedText:Hide() end

    local width = page.list:GetWidth()
    for index, variant in ipairs(specData.variants) do
        local row = GetRow(page.list, index)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", page.list, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
        row:SetWidth(width)
        row.bg:SetTexture(1, 1, 1, index % 2 == 0 and 0.03 or 0)
        row.label:SetText(variant.label or ("Variante " .. index))
        row.value:SetText(string.format("%.0f", variant[metric] or 0))

        local fraction = best > 0 and (variant[metric] or 0) / best or 0
        row.bar:ClearAllPoints()
        row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 8, 2)
        row.bar:SetWidth(math.max(1, (width - 90) * fraction))

        local diff = best > 0 and ((variant[metric] or 0) / best - 1) * 100 or 0
        local isBest = (variant[metric] or 0) >= best
        local isNoise = math.abs(diff) < NOISE_THRESHOLD_PCT

        if isNoise then
            row.bar:SetTexture(0.65, 0.65, 0.65, 0.6)
            row.percent:SetText(isBest and "referencia" or "≈ igual")
            row.percent:SetTextColor(0.65, 0.65, 0.65)
        elseif isBest then
            row.bar:SetTexture(0.3, 1, 0.3, 0.7)
            row.percent:SetText("mejor")
            row.percent:SetTextColor(0.3, 1, 0.3)
        else
            row.bar:SetTexture(0.6, 0.6, 0.6, 0.7)
            row.percent:SetText(string.format("%.1f %%", diff))
            row.percent:SetTextColor(1, 0.6, 0.3)
        end
        row:Show()
    end
    HideFrom(#specData.variants + 1)
end

-- Construye la pestaña dentro de parent (mismo hueco de contenido que las
-- otras pestañas del comparador). Devuelve la función refresh a llamar cada
-- vez que se seleccione la pestaña.
function SimulateX_BuildTalentsPage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()

    local header = page:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetText("Comparación de talentos (mismo equipo, distinta distribución)")
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

    page.tiedText = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    page.tiedText:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -10)
    page.tiedText:SetPoint("RIGHT", 0, 0)
    page.tiedText:SetJustifyH("LEFT")
    page.tiedText:SetText("Todas rinden igual: los puntos libres de esta build no tienen ningún talento ofensivo mejor donde ponerlos.")
    page.tiedText:SetTextColor(0.7, 0.7, 0.5)
    page.tiedText:Hide()

    local note = page:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("BOTTOM", page, "BOTTOM", 0, 0)
    note:SetPoint("LEFT", 0, 0)
    note:SetPoint("RIGHT", 0, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Compara distribuciones ya simuladas, no puntos de talento sueltos: cada fila es un árbol completo.")

    page.list = CreateFrame("Frame", nil, page)
    page.list:SetPoint("TOPLEFT", page.tiedText, "BOTTOMLEFT", 0, -8)
    page.list:SetPoint("RIGHT", 0, 0)
    page.list:SetPoint("BOTTOM", note, "TOP", 0, 4)

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
        RenderVariants(page, spec)
    end

    return page
end
