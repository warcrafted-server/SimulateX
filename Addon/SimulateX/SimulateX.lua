local ADDON_NAME = ...

local SimulateX = CreateFrame("Frame", "SimulateXFrame")

local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        SimulateX_DB = SimulateX_DB or {}
    end
end

SimulateX:RegisterEvent("ADDON_LOADED")
SimulateX:SetScript("OnEvent", OnEvent)
