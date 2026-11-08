-- The enlarged minimap could cover the Menu shortcut and occupy nearly a third of the screen height.
-- Mobile settings scale it (60% by default) or move the minimap and its zone, clock, and tracking
-- controls into a hidden parent.

local _, ns = ...

local Mini = ns.Register("Minimap", {})
ns.Minimap = Mini
local hider = CreateFrame("Frame")
hider:Hide()
local home

function Mini:Layout()
    local cluster = _G.MinimapCluster
    if not cluster then return end
    local settings = ns.db.minimap
    if settings.shown then
        if cluster:GetParent() == hider then cluster:SetParent(home or UIParent) end
        cluster:SetScale(settings.scale / 100)
    elseif cluster:GetParent() ~= hider then
        home = cluster:GetParent() or UIParent
        cluster:SetParent(hider)
    end
end

-- Reapply after the game's Edit Mode resets minimap scale.
local function Again()
    if ns.db and not InCombatLockdown() then ns.Guard("minimap", Mini.Layout, Mini) end
end
ns.On("EDIT_MODE_LAYOUTS_UPDATED", Again)
ns.On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then C_Timer.After(1, Again) else Again() end
end)
