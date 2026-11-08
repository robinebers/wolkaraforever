-- Rotating spell wheels are centered on the bottom corners, mirrored left to right. Only the inner
-- quarter above each stick is visible; rotating brings the remaining spells onscreen. Keep the area
-- below the stick free for jumping. Drag from a spell to rotate or tap and release to cast. Swipes
-- outside spells stay available for camera movement. Outside combat, spells follow the finger.
-- During combat secure code uses the press and release positions and precomputed geometry to snap
-- the wheel on release. Only spells are drawn. Disable drag-and-drop on rotating buttons so releases
-- reach them; a missed release previously made both wheels follow the cursor. Outside combat, check
-- for release and stop any previous drag before starting another wheel.

local _, ns = ...

local Turn = ns.Register("Rotating wheels", {})
ns.Turn = Turn

local SIZE = 64         -- spell button size, shared with free buttons
local FIRST = 95        -- first slot angle in degrees from the edge, viewed from the right
local SWIPE = 0.35      -- threshold in wheel steps between a tap and a swipe

local SIDES = {
    right = { key = "free", name = "WolkaraMobileTurn", corner = "BOTTOMRIGHT", mirror = false },
    left = { key = "freeLeft", name = "WolkaraMobileTurnLeft", corner = "BOTTOMLEFT", mirror = true },
}
local ORDER = { "right", "left" }
local wheels, attached = {}, {}

local function Settings(wheel) return ns.db[wheel.key] end

function Turn:Enabled(side)
    local settings = ns.db and ns.db[SIDES[side or "right"].key]
    return settings ~= nil and settings.turn == true
end

-- The radius clears the stick. At 100% spacing, consecutive spells are 1.25 button widths apart; the
-- range is 1.11 at 60% to 1.53 at 180%.
function Turn.Geometry(width, height, count, spread)
    local stick = math.sqrt((width * ns.STICK_X) ^ 2 + (height * ns.STICK_Y) ^ 2)
    local radius = stick + height * 0.15
    local apart = SIZE * (0.9 + 0.35 * (spread or 100) / 100)
    local step = math.deg(2 * math.asin(math.min(1, apart / (2 * radius))))
    return radius, step
end

-- Compute a slot angle for a possibly fractional drag offset. The left wheel mirrors the same
-- angles.
function Turn.Angle(index, offset, count, step)
    return FIRST + ((index - 1 + offset) % count) * step
end

local function Point(wheel, radius, degrees)
    local angle = math.rad(degrees)
    local x, y = radius * math.cos(angle), radius * math.sin(angle)
    if wheel.mirror then x = -x end
    return x, y
end

-- Measure offsets in free-button units because wheel slots use the same size.
local function Place(wheel, offset)
    local band, buttons = wheel.band, attached[wheel.side]
    if not buttons or InCombatLockdown() then return end
    local count = band:GetAttribute("count") or 0
    local radius, step, scale = band.radius, band:GetAttribute("step"), band.buttonScale or 1
    for index = 1, count do
        local x, y = Point(wheel, radius, Turn.Angle(index, offset, count, step))
        buttons[index]:ClearAllPoints()
        buttons[index]:SetPoint("CENTER", band, wheel.corner, x / scale, y / scale)
    end
end

-- Outside secure code, measure the cursor angle from the corner, mirrored on the left.
local function CursorAngle(wheel)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    local inward = wheel.mirror and x or UIParent:GetWidth() - x
    return math.deg(math.atan2(y, -inward))
end

-- Stop an unfinished drag outside combat and restore the saved notch.
local function Drop(wheel)
    wheel.dragging = false
    Place(wheel, wheel.band:GetAttribute("offset") or 0)
end

-- If the game missed the release outside combat, snap to the nearest notch and remember it for next
-- launch.
local function Release(wheel)
    local band = wheel.band
    wheel.dragging = false
    local count = band:GetAttribute("count") or 0
    local turns = (CursorAngle(wheel) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
    local offset = wheel.dragOffset or 0
    if count > 0 and (turns >= SWIPE or turns <= -SWIPE) then
        offset = (offset + math.floor(turns + 0.5)) % count
    end
    band:SetAttribute("offset", offset)
    Place(wheel, offset)
    Settings(wheel).turnOffset = offset
end

-- Secure code uses arithmetic on relative band coordinates to approximate angles from 90 to 180
-- degrees within a third of a degree. In these snippets self is the spell button and owner is its
-- band.
local ANGLE = [=[
    local x, y = owner:GetMousePosition()
    local angle
    if x then
        local size = owner:GetAttribute("size")
        local dx, dy = x * size, y * size
        if not owner:GetAttribute("mirror") then dx = size - dx end
        if dx <= 0 then angle = 90
        else
            local t = dy / dx
            local inverse = t > 1
            if inverse then t = 1 / t end
            local a = 45 * t + 15.64 * t * (1 - t)
            if inverse then a = 90 - a end
            angle = 180 - a
        end
    end
]=]

local DOWN = [=[
    if not owner:GetAttribute("turning") then return end
    owner:SetAttribute("swiped", nil)
]=] .. ANGLE .. [=[
    owner:SetAttribute("downangle", angle)
]=]

local UP = [=[
    if not owner:GetAttribute("turning") then return end
]=] .. ANGLE .. [=[
    local from = owner:GetAttribute("downangle")
    owner:SetAttribute("downangle", nil)
    local count = owner:GetAttribute("count")
    if not angle or not from or not count or count < 1 then return end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns < ]=] .. SWIPE .. [=[ and turns > -]=] .. SWIPE .. [=[ then return end
    owner:SetAttribute("swiped", true)
    turns = turns + 0.5
    turns = turns - turns % 1
    local offset = (owner:GetAttribute("offset") + turns) % count
    owner:SetAttribute("offset", offset)
    local corner = owner:GetAttribute("corner")
    for index = 1, count do
        local slot = (index - 1 + offset) % count
        local button = owner:GetFrameRef("b" .. index)
        button:ClearAllPoints()
        button:SetPoint("CENTER", owner, corner, owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
    end
]=]

-- Suppress casting when the gesture rotated the wheel. Measure here too in case the game dispatches
-- the click before release.
local CLICK = [=[
    if owner:GetAttribute("swiped") then
        owner:SetAttribute("swiped", nil)
        return false
    end
    local from = owner:GetAttribute("downangle")
    if down or not from or not owner:GetAttribute("turning") then return end
]=] .. ANGLE .. [=[
    if not angle then return end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns >= ]=] .. SWIPE .. [=[ or turns <= -]=] .. SWIPE .. [=[ then return false end
]=]

function Turn:Init()
    for _, side in ipairs(ORDER) do
        local info = SIDES[side]
        local band = CreateFrame("Frame", info.name, UIParent, "SecureHandlerBaseTemplate")
        band:SetFrameStrata("BACKGROUND")  -- below spell buttons, which sit below game windows
        band:SetPoint(info.corner, UIParent, info.corner)
        band:EnableMouse(false)
        band:Hide()
        local wheel = { side = side, key = info.key, corner = info.corner, mirror = info.mirror, band = band }
        band:SetScript("OnUpdate", function()
            if not wheel.dragging or InCombatLockdown() then return end
            -- Trust a reported mouse-up only if the game first reported mouse-down during this
            -- swipe; the app translates the button state.
            if IsMouseButtonDown then
                if IsMouseButtonDown("LeftButton") then
                    wheel.held = true
                elseif wheel.held then
                    Release(wheel)
                    return
                end
            end
            local turns = (CursorAngle(wheel) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
            if turns < SWIPE and turns > -SWIPE then turns = 0 end
            Place(wheel, wheel.dragOffset + turns)
        end)
        wheels[side] = wheel
    end
end

-- Free creates the buttons before Turn initializes and hands them over here.
function Turn:Attach(list, side) attached[side or "right"] = list end

-- Attach secure handlers and finger tracking once outside combat. They act only when the band's
-- turning attribute is enabled.
local function Wrap(wheel)
    local buttons, band = attached[wheel.side], wheel.band
    if wheel.wrapped or not buttons or InCombatLockdown() then return end
    wheel.wrapped = true
    for _, button in ipairs(buttons) do
        SecureHandlerWrapScript(button, "OnMouseDown", band, DOWN)
        SecureHandlerWrapScript(button, "OnMouseUp", band, UP)
        SecureHandlerWrapScript(button, "OnClick", band, CLICK)
        button:HookScript("OnMouseDown", function()
            button.swiped = nil
            if InCombatLockdown() or not Turn:Enabled(wheel.side) then return end
            -- Only one wheel can follow a finger at a time.
            for _, other in pairs(wheels) do
                if other ~= wheel and other.dragging then Drop(other) end
            end
            wheel.dragging, wheel.dragFrom, wheel.dragOffset = true, CursorAngle(wheel), band:GetAttribute("offset") or 0
            wheel.held = false
        end)
        button:HookScript("OnMouseUp", function()
            if not wheel.dragging then return end
            wheel.dragging = false
            if InCombatLockdown() then return end
            -- A swipe on an empty slot must also suppress its PostClick picker.
            local turns = (CursorAngle(wheel) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
            if turns >= SWIPE or turns <= -SWIPE then button.swiped = true end
            -- Use the secure handler's snapped offset, or its unchanged offset for a tap, and
            -- persist it.
            local offset = band:GetAttribute("offset") or 0
            Place(wheel, offset)
            Settings(wheel).turnOffset = offset
        end)
    end
end

-- Outside combat, compute geometry and cache slot positions for secure code before placing spells.
local function LayoutWheel(wheel)
    local buttons, band = attached[wheel.side], wheel.band
    if not buttons or InCombatLockdown() then return end
    Wrap(wheel)
    local turning = Turn:Enabled(wheel.side)
    band:SetAttribute("turning", turning)
    -- Cast on release so a swipe can cancel the cast. Disable drag-and-drop so the button receives
    -- that release.
    for _, button in ipairs(buttons) do
        if turning then
            button:SetAttribute("useOnKeyDown", false)
            pcall(button.RegisterForDrag, button)
        else
            button:SetAttribute("useOnKeyDown", nil)
            pcall(button.RegisterForDrag, button, "LeftButton")
        end
    end
    if not turning then band:Hide(); return end
    local settings = Settings(wheel)
    local count = math.max(0, math.min(settings.count, #buttons))
    local radius, step = Turn.Geometry(UIParent:GetWidth(), UIParent:GetHeight(), count, settings.spread)
    local size = radius + SIZE
    band.radius = radius
    band.buttonScale = (settings.scale or 100) / 100
    band:SetSize(size, size)
    band:SetAttribute("size", size)
    band:SetAttribute("mirror", wheel.mirror)
    band:SetAttribute("corner", wheel.corner)
    band:SetAttribute("count", count)
    band:SetAttribute("step", step)
    local offset = count > 0 and math.floor(tonumber(settings.turnOffset) or 0) % count or 0
    band:SetAttribute("offset", offset)
    for slot = 0, math.max(0, count - 1) do
        local x, y = Point(wheel, radius, FIRST + slot * step)
        band:SetAttribute("x" .. slot, x / band.buttonScale)
        band:SetAttribute("y" .. slot, y / band.buttonScale)
    end
    for index = 1, count do band:SetFrameRef("b" .. index, buttons[index]) end
    band:Show()
    Place(wheel, offset)
end

function Turn:Layout()
    for _, side in ipairs(ORDER) do
        if wheels[side] then LayoutWheel(wheels[side]) end
    end
end

-- Save the notch reached by each wheel when combat ends.
ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for _, side in ipairs(ORDER) do
        local wheel = wheels[side]
        if wheel and attached[side] and Turn:Enabled(side) then
            Settings(wheel).turnOffset = wheel.band:GetAttribute("offset") or 0
        end
    end
end)
