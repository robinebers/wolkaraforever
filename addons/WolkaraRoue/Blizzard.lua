-- Move the original action bars, unit frames, and objective tracker into a hidden parent while their
-- mobile replacements are active. This preserves keyboard and controller bindings and allows each
-- settings switch to restore its original frames. Chat manages its own replacement.

local _, ns = ...

local Blizzard = ns.Register("Game UI", {})
local hider = CreateFrame("Frame")
hider:Hide()

-- Frame names vary by client version. Use the ones that exist.
local GROUPS = {
    bars = { "MainMenuBar", "MainActionBar", "MainMenuBarArtFrame", "MainMenuBarArtFrameBackground",
        "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
        "MultiBar5", "MultiBar6", "MultiBar7", "MicroButtonAndBagsBar", "MicroMenuContainer", "BagsBar",
        "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
    units = { "PlayerFrame", "TargetFrame", "TargetFrameToT" },
    tracker = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" },
}

local moved = {}

local function Hide(group)
    for _, name in ipairs(GROUPS[group]) do
        local frame = _G[name]
        if frame and frame.GetParent and frame:GetParent() ~= hider then
            moved[frame] = { parent = frame:GetParent() or UIParent, group = group }
            frame:SetParent(hider)
        end
    end
end

local function Restore(group)
    for frame, info in pairs(moved) do
        if info.group == group then
            frame:SetParent(info.parent)
            moved[frame] = nil
        end
    end
end

local function Set(group, hidden)
    if hidden then Hide(group) else Restore(group) end
end

function Blizzard:Layout()
    local settings = ns.db.blizzard
    Set("bars", settings.hideBars)
    -- Hide the original unit frames only when the mobile health bars are enabled.
    Set("units", settings.hideUnitFrames and ns.db.hud.enabled)
    Set("tracker", ns.db.quests.enabled)
end

-- Some game frames appear later, when their add-ons load.
ns.On("ADDON_LOADED", function()
    if ns.db and not InCombatLockdown() then Blizzard:Layout() end
end)
