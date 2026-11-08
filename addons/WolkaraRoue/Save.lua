-- WoW writes WolkaraRoueDB when the UI reloads or the game quits cleanly. Swiping the phone app
-- away, background termination, or leaving through the toolbar can skip that save. On 2026-11-05 an
-- entire session's assignments were lost this way. After an edit, wait for a few quiet seconds
-- outside combat, with the picker, settings, menu, and Customize mode closed, before reloading the
-- UI to save.

local _, ns = ...

local AFTER_CHANGE = 4  -- seconds since the last change
local AFTER_IDLE = 1.5  -- seconds with all panels closed
local changedAt, idleSince

function ns.MarkChanged()
    if ns.db then changedAt = GetTime() end
end

function ns.SavePending() return changedAt ~= nil end

local function Busy()
    if InCombatLockdown() or ns.editing then return true end
    for _, module in ipairs({ ns.Picker, ns.Settings, ns.Menu }) do
        if module and module.IsOpen and module:IsOpen() then return true end
    end
    return false
end

-- Return true when this tick triggered a save.
function ns.SaveTick(now)
    if not changedAt or not ns.db then return false end
    if Busy() then idleSince = nil; return false end
    idleSince = idleSince or now
    if now - changedAt < AFTER_CHANGE or now - idleSince < AFTER_IDLE then return false end
    changedAt, idleSince = nil, nil
    ns.db.justSaved = true
    ns.Print("Reloading the UI to save your settings.")
    ReloadUI()
    return true
end

local saver = CreateFrame("Frame")
local since = 0
saver:SetScript("OnUpdate", function(_, elapsed)
    since = since + elapsed
    if since < 0.5 then return end
    since = 0
    ns.SaveTick(GetTime())
end)

ns.On("PLAYER_LOGIN", function()
    if ns.db and ns.db.justSaved then
        ns.db.justSaved = nil
        ns.Print("Settings saved.")
    end
end)
