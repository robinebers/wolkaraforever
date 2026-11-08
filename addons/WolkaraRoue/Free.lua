-- Keep spells visible around both sticks, using rotating wheels (Turn.lua) or arcs. The picker fills
-- slots; arc slots can be dragged in Customize mode. Empty slots are subdued during play.

local _, ns = ...

local SIZE = 64
-- Stick centers measured on the Duo: 12% from the side and 22% from the bottom.
local STICK_X, STICK_Y = 0.12, 0.222
ns.STICK_X, ns.STICK_Y = STICK_X, STICK_Y
-- Place the first row close to the stick and the second farther out.
local INNER, OUTER = 0.165, 0.275

local Free = ns.Register("Free buttons", {})
local groups = {}

local function Arc(side, index, count, spread)
    return function()
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        local cx = side == "right" and width * (1 - STICK_X) or width * STICK_X
        local cy = height * STICK_Y
        local radius, slot, slots
        if index <= 4 then
            radius, slot, slots = INNER, index, math.min(4, count)
        else
            radius, slot, slots = OUTER, index - 4, count - 4
        end
        -- Measure inward from vertical: 90 to 180 degrees on the right, 90 to 0 on the left.
        local t = slots <= 1 and 0.5 or (slot - 1) / (slots - 1)
        local degrees = side == "right" and (90 + 90 * t) or (90 - 90 * t)
        local distance = height * radius * (spread or 100) / 100
        return { "CENTER", "BOTTOMLEFT", cx + math.cos(math.rad(degrees)) * distance,
            cy + math.sin(math.rad(degrees)) * distance }
    end
end

local function BuildGroup(side, key, prefix)
    local group = { side = side, key = key, buttons = {} }
    local function settings() return ns.db[key] end
    local function store(index)
        local list = settings().buttons
        if type(list[index]) ~= "table" then list[index] = {} end
        return list[index]
    end
    for index = 1, ns.MAX_FREE do
        local button = ns.CreateActionButton(prefix .. index, UIParent, SIZE,
            function() return store(index).entry end,
            function(entry) store(index).entry = entry end)
        -- Let game windows such as bags and the spellbook open above these buttons.
        button:SetFrameStrata("LOW")
        button:RegisterForDrag("LeftButton")
        ns.Movable(button, function() return store(index) end, "pos",
            function() return Arc(side, index, settings().count, settings().spread)() end)
        button:Hide()
        local since = 0
        button:HookScript("OnUpdate", function(self, elapsed)
            since = since + elapsed
            if since < 0.25 then return end
            since = 0
            ns.UpdateState(self)
        end)
        group.buttons[index] = button
    end

    function group:Layout()
        local scale = settings().scale / 100
        -- The rotating wheel positions its own spells, including offscreen slots.
        local turning = ns.Turn and ns.Turn:Enabled(side)
        for index, button in ipairs(self.buttons) do
            if index <= settings().count then
                button:SetScale(scale)
                button:SetClampedToScreen(not turning)
                if not turning then button:PlaceSaved() end
                button:Show()
            else
                button:Hide()
            end
            ns.ApplyButton(button)
        end
    end

    function group:Refresh()
        for index, button in ipairs(self.buttons) do
            if index <= settings().count then
                ns.RefreshButton(button)
                button:SetAlpha((button:GetEntry() or ns.editing) and 1 or 0.35)
            end
        end
    end

    function group:Each(fn)
        for index, button in ipairs(self.buttons) do
            if index <= settings().count then fn(button) end
        end
    end
    return group
end

function Free:Init()
    groups[1] = BuildGroup("right", "free", "WolkaraMobileFree")
    groups[2] = BuildGroup("left", "freeLeft", "WolkaraMobileFreeLeft")
    if ns.Turn then
        ns.Turn:Attach(groups[1].buttons, "right")
        ns.Turn:Attach(groups[2].buttons, "left")
    end
end

function Free:Layout()
    for _, group in ipairs(groups) do ns.Guard("buttons " .. group.side, group.Layout, group) end
    self:Refresh()
end

function Free:Refresh()
    for _, group in ipairs(groups) do group:Refresh() end
end

function Free:SetEditing() self:Refresh() end

function Free:CombatStarts()
    for _, group in ipairs(groups) do
        group:Each(function(button) if button.suppressed then ns.ApplyButton(button) end end)
    end
end

local function UpdateCooldowns()
    if not ns.db then return end
    for _, group in ipairs(groups) do group:Each(ns.UpdateCooldown) end
end
ns.On("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE_COOLDOWN", UpdateCooldowns)
ns.On("BAG_UPDATE", function() if ns.db then Free:Refresh() end end)
ns.On("SPELLS_CHANGED", function()
    if not ns.db then return end
    Free:Refresh()
    if not InCombatLockdown() then
        for _, group in ipairs(groups) do group:Each(ns.ApplyButton) end
    end
end)
