-- The game anchors bags under the right stick and wheel. After layout, shift right-edge bags left by
-- just over a wheel width so their slots stay reachable. Bag slots are protected in combat;
-- reposition them after combat ends.

local _, ns = ...

local Bags = ns.Register("Bags", {})
local pending = false
local SHIFT = 0.36  -- fraction of screen width

local function Containers()
    local list = {}
    if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame then list[#list + 1] = frame end
    end
    return list
end

-- Run after each game bag layout, which resets their positions.
function Bags.Shift()
    if InCombatLockdown() then pending = true; return end
    pending = false
    local shift = UIParent:GetWidth() * SHIFT
    for _, frame in ipairs(Containers()) do
        if frame:IsShown() and frame:GetNumPoints() > 0 then
            local point, relative, relativePoint, x, y = frame:GetPoint(1)
            if (relative == nil or relative == UIParent) and relativePoint and relativePoint:find("RIGHT") then
                frame:ClearAllPoints()
                frame:SetPoint(point, UIParent, relativePoint, (x or 0) - shift, y or 0)
            end
        end
    end
end

function Bags:Init()
    if type(UpdateContainerFrameAnchors) == "function" then
        hooksecurefunc("UpdateContainerFrameAnchors", Bags.Shift)
    end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if pending and type(UpdateContainerFrameAnchors) == "function" then UpdateContainerFrameAnchors() end
end)
