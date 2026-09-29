--[[----------------------------------------------------------------------
    Economía en el vendedor (v0.8): vender grises con lista blanca por
    Ctrl+clic, reparación automática (propia o de hermandad) y precio de
    venta en el tooltip. Todo desactivado por defecto salvo el precio de
    venta, y configurable en el panel (SimulateXOptions.lua).
------------------------------------------------------------------------]]

--[[----------------------------------------------------------------------
    LISTA BLANCA: Ctrl+clic sobre un objeto gris en la bolsa lo protege (o
    lo desprotege). Por itemId, no por nombre, para no confundir objetos
    con el mismo nombre pero distinto id.
------------------------------------------------------------------------]]

local function ToggleWhitelist(itemId)
    SimulateX_DB.sellWhitelist = SimulateX_DB.sellWhitelist or {}
    if SimulateX_DB.sellWhitelist[itemId] then
        SimulateX_DB.sellWhitelist[itemId] = nil
        print("SimulateX: ya no protege este objeto, se venderá si es gris.")
    else
        SimulateX_DB.sellWhitelist[itemId] = true
        print("SimulateX: objeto protegido, nunca se venderá automáticamente.")
    end
end

local function HandleBagItemClick(self, button)
    if button ~= "LeftButton" or not IsControlKeyDown() then
        return
    end
    local itemId = self.simulateXBagId and GetContainerItemID(self.simulateXBagId, self:GetID())
    if itemId then
        ToggleWhitelist(itemId)
    end
end

--[[----------------------------------------------------------------------
    VENDER GRISES: al abrir un vendedor, recorre las bolsas y vende todo lo
    gris que no esté en la lista blanca.
------------------------------------------------------------------------]]

local function SellGreyItems()
    if not SimulateX_DB.autoSellGreysEnabled then
        return
    end
    local whitelist = SimulateX_DB.sellWhitelist or {}
    local totalCopper, totalCount = 0, 0
    for bagId = 0, NUM_BAG_SLOTS do
        for slot = 1, (GetContainerNumSlots(bagId) or 0) do
            local itemId = GetContainerItemID and GetContainerItemID(bagId, slot)
            if itemId and not whitelist[itemId] then
                local _, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(itemId)
                if quality == 0 then
                    local _, itemCount = GetContainerItemInfo(bagId, slot)
                    UseContainerItem(bagId, slot)
                    totalCopper = totalCopper + (sellPrice or 0) * (itemCount or 1)
                    totalCount = totalCount + 1
                end
            end
        end
    end
    if totalCount > 0 then
        print(string.format("SimulateX: vendidos %d objetos grises por %s.", totalCount, GetCoinTextureString(totalCopper)))
    end
end

--[[----------------------------------------------------------------------
    REPARACIÓN AUTOMÁTICA: "self" (fondos propios) o "guild" (banco de
    hermandad, solo si hay permiso y saldo suficiente; si no, no repara,
    para no gastar oro propio sin que el jugador lo haya pedido).
------------------------------------------------------------------------]]

local function AutoRepair()
    local mode = SimulateX_DB.repairMode or "off"
    if mode == "off" or not CanMerchantRepair() then
        return
    end
    local cost = GetRepairAllCost()
    if not cost or cost <= 0 then
        return
    end

    if mode == "guild" then
        if not IsInGuild() or not CanGuildBankRepair() then
            return
        end
        local guildFunds = GetGuildBankWithdrawMoney()
        if guildFunds ~= -1 and guildFunds < cost then
            return  -- sin saldo de hermandad suficiente: no repara con dinero propio en su lugar
        end
        RepairAllItems(true)
        print(string.format("SimulateX: reparado por %s (banco de hermandad).", GetCoinTextureString(cost)))
    elseif mode == "self" then
        if GetMoney() < cost then
            return
        end
        RepairAllItems()
        print(string.format("SimulateX: reparado por %s (fondos propios).", GetCoinTextureString(cost)))
    end
end

--[[----------------------------------------------------------------------
    PRECIO DE VENTA EN EL TOOLTIP: activado por defecto, para quien no
    tenga addon de subastas con esa info.
------------------------------------------------------------------------]]

local function AddSellPriceToTooltip(tooltip)
    if SimulateX_DB.sellPriceTooltipDisabled then
        return
    end
    local _, itemLink = tooltip:GetItem()
    if not itemLink then
        return
    end
    local sellPrice = select(11, GetItemInfo(itemLink))
    if sellPrice and sellPrice > 0 then
        tooltip:AddLine("Venta: " .. GetCoinTextureString(sellPrice), 1, 1, 1)
        tooltip:Show()
    end
end

--[[----------------------------------------------------------------------
    MEJOR RECOMPENSA DE MISIÓN: si ninguna recompensa a elegir mejora el
    equipo, marca la de mayor precio de venta con un texto (no reutiliza el
    overlay de flecha de SimulateX.lua, reservado a "mejora tu equipo").
------------------------------------------------------------------------]]

local function MarkBestSellValueReward()
    if SimulateX_DB.questRewardHintDisabled or not QuestInfoRewardsFrame then
        return
    end
    local bestButton, bestPrice
    for _, button in ipairs({ QuestInfoRewardsFrame:GetChildren() }) do
        if button.rewardType == "item" and button.type == "choice" then
            local link = (QuestInfoFrame and QuestInfoFrame.questLog)
                and GetQuestLogItemLink(button.type, button:GetID())
                or GetQuestItemLink(button.type, button:GetID())
            local sellPrice = link and select(11, GetItemInfo(link))
            if sellPrice and (not bestPrice or sellPrice > bestPrice) then
                bestPrice, bestButton = sellPrice, button
            end
        end
        if button.simulateXSellHint then
            button.simulateXSellHint:Hide()
        end
    end
    -- solo si esta elección no lleva ya la flecha de mejora (SimulateX.lua)
    local alreadyMarked = bestButton and bestButton.simulateXIcon and bestButton.simulateXIcon:IsShown()
    if bestButton and not alreadyMarked then
        if not bestButton.simulateXSellHint then
            local hint = bestButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            hint:SetPoint("BOTTOM", bestButton, "TOP", 0, 2)
            hint:SetTextColor(1, 0.82, 0)
            bestButton.simulateXSellHint = hint
        end
        bestButton.simulateXSellHint:SetText("$")
        bestButton.simulateXSellHint:Show()
    end
end

-- ContainerFrame_Update repuebla los botones cada vez que se abre una bolsa
-- o cambia su contenido (mismo hook que UpdateContainerFrameIcons en
-- SimulateX.lua): es donde hay que reenganchar el Ctrl+clic, no solo en el
-- login, porque a esa hora ninguna bolsa está todavía abierta en pantalla.
local function HookBagButtons(frame)
    if not frame or not frame.GetID then
        return
    end
    local bagId = frame:GetID()
    for i = 1, (frame.size or 0) do
        local button = _G[frame:GetName() .. "Item" .. i]
        if button and not button.simulateXWhitelistHooked then
            button.simulateXBagId = bagId
            button:HookScript("OnClick", HandleBagItemClick)
            button.simulateXWhitelistHooked = true
        end
    end
end

function SimulateX_Economia_Init()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:SetScript("OnEvent", function()
        SellGreyItems()
        AutoRepair()
    end)

    GameTooltip:HookScript("OnTooltipSetItem", AddSellPriceToTooltip)
    ItemRefTooltip:HookScript("OnTooltipSetItem", AddSellPriceToTooltip)

    if QuestInfo_ShowRewards then
        hooksecurefunc("QuestInfo_ShowRewards", MarkBestSellValueReward)
    end

    if ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", HookBagButtons)
    end
end
