-- Scale the entire UI, including game windows (170% by default), to make quest text readable and
-- buttons large enough for touch. Apply scale before the other modules calculate their proportional
-- positions.

local _, ns = ...

local Scale = ns.Register("UI scale", {})
local base, applied

local function Apply()
    if InCombatLockdown() then return end
    local current = UIParent:GetScale()
    -- Start from the game's scale if a display change caused it to recalculate.
    if not applied or math.abs(current - applied) > 0.001 then base = current end
    applied = base * ns.db.ui.scale / 100
    UIParent:SetScale(applied)
end

function Scale:Layout() Apply() end

local function Recompute()
    if not ns.db then return end
    local function again()
        -- Leave the applied scale in place if the base scale is unchanged to avoid scaling twice.
        if InCombatLockdown() then return end
        ns.Layout()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, again) else again() end
end
ns.On("UI_SCALE_CHANGED", Recompute)
ns.On("DISPLAY_SIZE_CHANGED", Recompute)
