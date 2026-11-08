-- At the default 170% scale, game windows could extend beyond the screen or put quest buttons under
-- the left stick. Shrink windows only enough to fit, up to their original scale. Use the full-height
-- space between sticks when possible, or the wider space above them. The world map uses the full
-- screen with its close button in reach. Keep the game's placement and adjust its clamping margins.
-- Defer protected window changes until combat ends.

local _, ns = ...

local Windows = ns.Register("Game windows", {})
ns.Windows = Windows

local MARGIN = 10
-- Reserve room around each stick center for the app's ring and a margin, expressed as fractions of
-- screen height.
local STICK_ZONE = 0.10
local WHOLE_SCREEN = { WorldMapFrame = true }
-- Handle known windows and other panels as ShowUIPanel opens them. Some frames vary by client or
-- load with their module.
local NAMES = {
    "WorldMapFrame", "QuestFrame", "GossipFrame", "QuestLogFrame", "MerchantFrame", "LootFrame",
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "TaxiFrame", "FriendsFrame", "MailFrame",
    "BankFrame", "TradeFrame", "ClassTrainerFrame", "TalentFrame", "ItemTextFrame", "GameMenuFrame",
    "SettingsPanel", "InterfaceOptionsFrame", "VideoOptionsFrame", "PVEFrame", "LFGParentFrame",
    "PVPFrame", "CollectionsJournal", "EncounterJournal", "AchievementFrame", "AuctionFrame",
    "AuctionHouseFrame", "ProfessionsFrame", "TradeSkillFrame", "CraftFrame", "GuildFrame",
    "CommunitiesFrame", "MacroFrame", "KeyBindingFrame", "HelpFrame",
}

local natural, pending, watched = {}, {}, {}
local busy = false

-- Calculate scale and the required side and bottom clearances in UI units. Cap scale at the original
-- value, largest.
function Windows.Placement(W, H, width, height, largest, whole)
    if whole then
        return math.min(largest, (W - 2 * MARGIN) / width, (H - 2 * MARGIN) / height), MARGIN, MARGIN
    end
    local side = W * ns.STICK_X + H * STICK_ZONE + MARGIN
    local low = H * ns.STICK_Y + H * STICK_ZONE + MARGIN
    local between = math.min(largest, (W - 2 * side) / width, (H - 2 * MARGIN) / height)
    local above = math.min(largest, (W - 2 * MARGIN) / width, (H - low - MARGIN) / height)
    if between >= above then return between, side, MARGIN end
    return above, MARGIN, low
end

-- Allow for the close button extending above and right of its frame so the button stays onscreen.
local function Overhang(frame)
    local close = frame.CloseButton or (type(frame.BorderFrame) == "table" and frame.BorderFrame.CloseButton)
        or _G[(frame:GetName() or "") .. "CloseButton"]
    if type(close) ~= "table" or not close.GetRight or not close:IsShown() then return 0, 0 end
    local frameRight, frameTop, closeRight, closeTop = frame:GetRight(), frame:GetTop(), close:GetRight(), close:GetTop()
    if not (frameRight and frameTop and closeRight and closeTop) then return 0, 0 end
    local f, c = frame:GetEffectiveScale(), close:GetEffectiveScale()
    return math.max(0, (closeRight * c - frameRight * f) / f), math.max(0, (closeTop * c - frameTop * f) / f)
end

function Windows.Fit(frame)
    if busy or type(frame) ~= "table" or not frame.IsShown or not frame:IsShown() then return end
    if InCombatLockdown() and frame:IsProtected() then pending[frame] = true; return end
    -- Leave anchor-sized frames alone because their dimensions would change with scale.
    if frame:GetNumPoints() > 1 then return end
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not width or not height or width < 1 or height < 1 then return end
    if natural[frame] == nil then natural[frame] = frame:GetScale() or 1 end
    local ui = UIParent:GetEffectiveScale()
    local parent = frame:GetParent()
    local parentScale = parent and parent:GetEffectiveScale() / ui or 1
    local right, top = Overhang(frame)
    local scale, side, low = Windows.Placement(UIParent:GetWidth(), UIParent:GetHeight(), width + right,
        height + top, natural[frame] * parentScale, WHOLE_SCREEN[frame:GetName() or ""])
    busy = true
    if math.abs(frame:GetScale() - scale / parentScale) > 0.001 then frame:SetScale(scale / parentScale) end
    frame:SetClampedToScreen(true)
    -- Clamping margins use frame units, each worth scale UI units.
    frame:SetClampRectInsets(-side / scale, side / scale + right, MARGIN / scale + top, -low / scale)
    busy = false
end

-- Revisit panels such as the map one frame later, once their opening layout has resolved.
local function Again(frame)
    if C_Timer and C_Timer.After then C_Timer.After(0, function() Windows.Fit(frame) end) end
end

function Windows.Watch(frame)
    if type(frame) ~= "table" or watched[frame] or not frame.HookScript then return end
    watched[frame] = true
    frame:HookScript("OnShow", function(self) Windows.Fit(self); Again(self) end)
    frame:HookScript("OnSizeChanged", function(self) Windows.Fit(self) end)
end

local function WatchKnown()
    for _, name in ipairs(NAMES) do Windows.Watch(_G[name]) end
end

function Windows:Init()
    WatchKnown()
    if type(ShowUIPanel) == "function" and hooksecurefunc then
        hooksecurefunc("ShowUIPanel", function(frame)
            if type(frame) == "table" and frame.IsShown then Windows.Watch(frame); Windows.Fit(frame) end
        end)
    end
end

-- Refit open windows when UI scale changes.
function Windows:Layout()
    for frame in pairs(watched) do
        if frame:IsShown() then Windows.Fit(frame) end
    end
end

ns.On("ADDON_LOADED", function() if ns.db then WatchKnown() end end)
ns.On("PLAYER_REGEN_ENABLED", function()
    for frame in pairs(pending) do
        pending[frame] = nil
        Windows.Fit(frame)
    end
end)
