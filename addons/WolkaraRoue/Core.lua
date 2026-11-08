-- Shared mobile UI module lifecycle. Run Init once, Layout outside combat when positions change,
-- Refresh for display updates, and SetEditing in Customize mode. Report a module error to chat and
-- continue running the other modules. Each cast requires a player tap through a game action button.

local ADDON_NAME, ns = ...
ns.MAX_WHEELS = 4
ns.MAX_SLOTS = 12
ns.MAX_FREE = 12
ns.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.WHITE = "Interface\\Buttons\\WHITE8X8"
ns.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local modules = {}
local loggedIn = false
local pendingLayout = false
ns.editing = false

function ns.Print(message)
    local line = "|cff66ccffMobile|r: " .. message
    -- Send notices through the mobile chat when it replaces game chat.
    if ns.ChatAdd and ns.ChatAdd(line) then return end
    DEFAULT_CHAT_FRAME:AddMessage(line)
end

local reported = 0
local function Trace(message)
    return tostring(message) .. (debugstack and ("\n" .. debugstack(2, 2, 0)) or "")
end
function ns.Guard(label, fn, ...)
    local ok, problem = xpcall(fn, Trace, ...)
    if not ok then
        ns.lastError = label .. " : " .. problem
        if reported < 5 then
            reported = reported + 1
            if loggedIn then ns.Print("|cffff5555error|r (" .. label .. "): " .. problem) end
        end
    end
    return ok
end

function ns.Register(name, module)
    module.name = name
    modules[#modules + 1] = module
    return module
end

function ns.Each(method, ...)
    for _, module in ipairs(modules) do
        local fn = module[method]
        if fn then ns.Guard(module.name .. "." .. method, fn, module, ...) end
    end
end

-- Defer protected layout changes until combat ends.
function ns.Layout()
    if InCombatLockdown() then pendingLayout = true; return end
    ns.Each("Layout")
end

function ns.Refresh() ns.Each("Refresh") end

function ns.SetEditing(on)
    if InCombatLockdown() then
        if on then ns.Print("Customize outside combat.") end
        return
    end
    ns.editing = on and true or false
    ns.Each("SetEditing", ns.editing)
    ns.Layout()
    if ns.editing then
        ns.Print("Customize mode: drag to move, tap a slot to choose a spell, then tap Done.")
    end
end

-- Client compatibility: Forever may expose either legacy functions or C_* namespaces.

function ns.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

function ns.SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
end

function ns.SpellCooldown(id)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(id)
        if type(info) == "table" then return info.startTime, info.duration, info.isEnabled end
        return info
    end
    if GetSpellCooldown then return GetSpellCooldown(id) end
end

function ns.SpellUsable(id)
    if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(id) end
    if IsUsableSpell then
        local name = ns.SpellName(id)
        if name then return IsUsableSpell(name) end
    end
    return true, false
end

function ns.SpellInRange(id)
    if not UnitExists("target") then return nil end
    if C_Spell and C_Spell.IsSpellInRange then return C_Spell.IsSpellInRange(id, "target") end
    if IsSpellInRange then
        local name = ns.SpellName(id)
        local result = name and IsSpellInRange(name, "target")
        if result == 1 then return true elseif result == 0 then return false end
    end
    return nil
end

function ns.ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    if GetItemIcon then return GetItemIcon(id) end
end

function ns.ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    if GetItemInfo then return (GetItemInfo(id)) end
end

function ns.ItemCount(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
    if GetItemCount then return GetItemCount(id) end
    return 0
end

function ns.ItemSpell(id)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(id) end
    if GetItemSpell then return GetItemSpell(id) end
end

function ns.ItemCooldown(id)
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
    if GetItemCooldown then return GetItemCooldown(id) end
end

function ns.PickupEntry(entry)
    if entry.kind == "spell" then
        if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(entry.id) elseif PickupSpell then PickupSpell(entry.id) end
    elseif entry.kind == "item" then
        if C_Item and C_Item.PickupItem then C_Item.PickupItem(entry.id) elseif PickupItem then PickupItem(entry.id) end
    elseif entry.kind == "macro" then
        PickupMacro(entry.id)
    end
end

-- Represent the spell, item, or macro on the cursor as a slot entry.
function ns.CursorEntry()
    local kind, a, b, c = GetCursorInfo()
    if kind == "spell" then
        if b == "pet" then
            ns.Print("Pet abilities cannot be assigned to these slots.")
            return nil
        end
        local spellID = c
        if not spellID and a and GetSpellBookItemInfo then
            local _, id = GetSpellBookItemInfo(a, b)
            spellID = id
        end
        if spellID then return { kind = "spell", id = spellID } end
    elseif kind == "item" and a then
        return { kind = "item", id = a }
    elseif kind == "macro" and a then
        local name = GetMacroInfo(a)
        if name then return { kind = "macro", id = name } end
    elseif kind then
        ns.Print("Assign a spell, item, or macro to this slot.")
    end
    return nil
end

-- Clear saved positions to restore the default layout.
function ns.ClearPositions(db)
    for i = 1, ns.MAX_WHEELS do if type(db.wheels[i]) == "table" then db.wheels[i].toggle = nil end end
    for _, group in ipairs({ db.free, db.freeLeft }) do
        if type(group) == "table" and type(group.buttons) == "table" then
            for _, button in pairs(group.buttons) do if type(button) == "table" then button.pos = nil end end
        end
    end
    if type(db.shortcuts) == "table" then db.shortcuts.pos = nil end
    if type(db.hud) == "table" then db.hud.player = nil; db.hud.target = nil end
    if type(db.chat) == "table" then db.chat.pos = nil end
    if type(db.quests) == "table" then db.quests.pos = nil end
end

-- In 0.6, copy gold wheel 1's spells into empty slots on the left rotating wheel, skipping
-- duplicates. Disable the gold wheel but retain its contents for players who turn it back on.
function ns.MigrateGoldenWheel(db)
    local golden, left = db.wheels[1], db.freeLeft
    local function Stored(index) return type(left.buttons[index]) == "table" and left.buttons[index].entry end
    local last = 0
    local function Has(entry)
        for index = 1, ns.MAX_FREE do
            local stored = Stored(index)
            if stored and stored.kind == entry.kind and stored.id == entry.id then return true end
        end
        return false
    end
    for index = 1, ns.MAX_FREE do if Stored(index) then last = index end end
    local slot = 1
    for i = 1, golden.slots do
        local entry = golden.entries[i]
        if type(entry) == "table" and entry.kind and not Has(entry) then
            while slot <= ns.MAX_FREE and Stored(slot) do slot = slot + 1 end
            if slot > ns.MAX_FREE then break end
            if type(left.buttons[slot]) ~= "table" then left.buttons[slot] = {} end
            left.buttons[slot].entry = { kind = entry.kind, id = entry.id }
            last = math.max(last, slot)
        end
    end
    golden.enabled = false
    left.turn = true
    left.count = math.max(tonumber(left.count) or 0, 4, last)
end

-- Default coordinates are fractions of the screen measured from the bottom left. Resolve them at
-- layout time to account for UI scale.
function ns.Spot(fx, fy, dx, dy)
    return function()
        return { "CENTER", "BOTTOMLEFT", UIParent:GetWidth() * fx + (dx or 0), UIParent:GetHeight() * fy + (dy or 0) }
    end
end

function ns.Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Shared appearance

function ns.Circle(frame, texture)
    if frame.CreateMaskTexture and texture.AddMaskTexture then
        local mask = frame:CreateMaskTexture()
        mask:SetTexture(ns.CIRCLE, "CLAMPTOEDGE", "CLAMPTOEDGE")
        mask:SetAllPoints(texture)
        texture:AddMaskTexture(mask)
        return true
    end
    return false
end

function ns.Disc(frame, layer, r, g, b, a, inset)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetTexture(ns.WHITE)
    texture:SetVertexColor(r, g, b, a)
    texture:SetPoint("TOPLEFT", -inset, inset)
    texture:SetPoint("BOTTOMRIGHT", inset, -inset)
    ns.Circle(frame, texture)
    return texture
end

function ns.Box(frame, layer, r, g, b, a)
    local texture = frame:CreateTexture(nil, layer)
    texture:SetTexture(ns.WHITE)
    texture:SetVertexColor(r, g, b, a)
    texture:SetAllPoints()
    return texture
end

function ns.Label(frame, template, text)
    local label = frame:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
    if text then label:SetText(text) end
    return label
end

-- A movable frame persists its position in Customize mode. save stores the position, place restores
-- it, and default applies until the first save.
function ns.Movable(frame, store, key, default)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:HookScript("OnDragStart", function(self)
        if ns.editing and not InCombatLockdown() then self:StartMoving(); self.moving = true end
    end)
    frame:HookScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = nil
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        local target = store()
        target[key] = { point = point, relativePoint = relativePoint, x = x, y = y }
        if ns.MarkChanged then ns.MarkChanged() end
        if frame.OnMoved then frame:OnMoved() end
    end)
    function frame:PlaceSaved()
        if InCombatLockdown() then return end
        local saved = store()[key]
        self:ClearAllPoints()
        if type(saved) == "table" and saved.point then
            self:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, saved.x or 0, saved.y or 0)
        else
            local d = type(default) == "function" and default() or default
            self:SetPoint(d[1], UIParent, d[2] or d[1], d[3] or 0, d[4] or 0)
        end
    end
end

-- Dragging this handle in Customize mode moves its parent block.
function ns.DragHandle(handle, frame)
    handle:RegisterForDrag("LeftButton")
    handle:HookScript("OnDragStart", function()
        local start = frame:GetScript("OnDragStart")
        if start then start(frame) end
    end)
    handle:HookScript("OnDragStop", function()
        local stop = frame:GetScript("OnDragStop")
        if stop then stop(frame) end
    end)
end

-- Yellow outline for Customize mode.
function ns.EditFrame(frame)
    local glow = frame:CreateTexture(nil, "OVERLAY")
    glow:SetTexture(ns.WHITE)
    glow:SetVertexColor(1, 0.82, 0.2, 0.22)
    glow:SetPoint("TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", 3, -3)
    glow:Hide()
    return glow
end

-- Settings

-- Keep the optional gold pop-up wheels in settings. The left rotating wheel replaces them in the
-- default 0.6 layout.
local function Wheel()
    return {
        enabled = false,
        slots = 8,
        scale = 100,
        radius = 110,
        open = "bouton", -- around the button or at screen center
        entries = {},
    }
end

local function Defaults()
    local wheels = {}
    for i = 1, ns.MAX_WHEELS do wheels[i] = Wheel(i) end
    return {
        version = 2,
        wheels = wheels,
        ui = { scale = 170 },
        free = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 0, buttons = {} },
        freeLeft = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 0, buttons = {} },
        shortcuts = { enabled = true, scale = 100 },
        hud = { enabled = true, scale = 100 },
        chat = { custom = true, fontSize = 16, tab = "talk", hidden = false },
        minimap = { shown = true, scale = 60 },
        blizzard = { hideBars = true, hideUnitFrames = true },
        quests = { enabled = true, collapsed = false, shown = 3 },
        welcomed = false,
    }
end

local function Fill(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Fill(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function LoadSettings()
    local saved = type(WolkaraRoueDB) == "table" and WolkaraRoueDB or {}
    -- Migrate the original flat wheel settings to wheel 1.
    if not saved.version then
        local first = Wheel(1)
        if type(saved.entries) == "table" then first.entries = saved.entries end
        if tonumber(saved.slots) then first.slots = saved.slots end
        if tonumber(saved.scale) then first.scale = saved.scale end
        if tonumber(saved.radius) then first.radius = saved.radius end
        if saved.position == "centre" then first.open = "centre" end
        local welcomed = saved.welcomed
        saved = { wheels = { first }, welcomed = welcomed }
    end
    Fill(saved, Defaults())
    for i = 1, ns.MAX_WHEELS do
        local wheel = saved.wheels[i]
        wheel.slots = ns.Clamp(tonumber(wheel.slots) or 8, 4, ns.MAX_SLOTS)
        wheel.scale = ns.Clamp(tonumber(wheel.scale) or 100, 50, 200)
        wheel.radius = ns.Clamp(tonumber(wheel.radius) or 140, 80, 320)
    end
    saved.free.count = ns.Clamp(tonumber(saved.free.count) or 4, 0, ns.MAX_FREE)
    saved.freeLeft.count = ns.Clamp(tonumber(saved.freeLeft.count) or 4, 0, ns.MAX_FREE)
    saved.minimap.scale = ns.Clamp(tonumber(saved.minimap.scale) or 60, 30, 150)
    saved.free.spread = ns.Clamp(tonumber(saved.free.spread) or 100, 60, 180)
    saved.freeLeft.spread = ns.Clamp(tonumber(saved.freeLeft.spread) or 100, 60, 180)
    saved.ui.scale = ns.Clamp(tonumber(saved.ui.scale) or 170, 100, 220)
    -- Layout 3 restores default positions once because positions saved for the original UI no longer
    -- match the enlarged, proportional layout.
    if (tonumber(saved.layoutVersion) or 0) < 3 then
        ns.ClearPositions(saved)
        for i = 1, ns.MAX_WHEELS do
            if saved.wheels[i].radius == 140 then saved.wheels[i].radius = 110 end
        end
        if saved.chat.fontSize == 15 then saved.chat.fontSize = 16 end
        saved.layoutVersion = 3
    end
    -- Layout 4 (0.6) mirrors the right rotating wheel on the left, fills free slots from the gold
    -- wheel, and returns chat to the bottom.
    if (tonumber(saved.layoutVersion) or 0) < 4 then
        ns.MigrateGoldenWheel(saved)
        saved.chat.pos = nil
        saved.layoutVersion = 4
    end
    WolkaraRoueDB = saved
    ns.db = saved
end

-- Events

local events = CreateFrame("Frame")
local handlers = {}

-- Register module event handlers, ignoring events this client does not support.
function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if not pcall(events.RegisterEvent, events, event) then
            handlers[event] = nil
            return
        end
    end
    table.insert(handlers[event], fn)
end

events:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do ns.Guard(event, fn, ...) end
end)

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    LoadSettings()
    ns.Each("Init")
end)

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    if not ns.db then LoadSettings(); ns.Each("Init") end
    ns.Layout()
    ns.Refresh()
    if ns.lastError then ns.Print("|cffff5555load error|r: " .. ns.lastError) end
    if not ns.db.welcomed then
        ns.db.welcomed = true
        ns.Print("Tap an empty wheel slot to assign a spell. Drag from a spell to rotate the wheel. Tap the shortcut gear for settings.")
    end
end)

ns.On("PLAYER_REGEN_DISABLED", function()
    -- Last opportunity to update protected buttons before combat.
    if ns.editing then ns.SetEditing(false) end
    ns.Each("CombatStarts")
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    if pendingLayout then
        pendingLayout = false
        ns.Each("Layout")
    end
end)

-- /mobile and /wheel share a handler; keep /roue for existing users.

SLASH_WOLKARAMOBILE1 = "/mobile"
SLASH_WOLKARAMOBILE2 = "/roue"
SLASH_WOLKARAMOBILE3 = "/wheel"
SlashCmdList.WOLKARAMOBILE = function(message)
    if not ns.db then
        ns.Print("not ready yet" .. (ns.lastError and (": " .. ns.lastError) or "."))
        return
    end
    local command = ((message or ""):match("^%s*(%S*)") or ""):lower()
    if command == "error" or command == "erreur" then
        ns.Print(ns.lastError or "No errors.")
    elseif command == "customize" or command == "edit" or command == "personnaliser" or command == "modifier" then
        ns.SetEditing(not ns.editing)
    elseif command == "reset" then
        if InCombatLockdown() then ns.Print("Unavailable during combat."); return end
        local old = ns.db
        WolkaraRoueDB = nil
        LoadSettings()
        for i = 1, ns.MAX_WHEELS do ns.db.wheels[i].entries = old.wheels[i] and old.wheels[i].entries or {} end
        -- Preserve the rotating wheels' spell assignments and slot order as well.
        for _, key in ipairs({ "free", "freeLeft" }) do
            for index, button in pairs(old[key].buttons) do
                if type(button) == "table" and button.entry and ns.db[key].buttons then
                    ns.db[key].buttons[index] = { entry = button.entry }
                    ns.db[key].count = math.max(ns.db[key].count, math.min(index, ns.MAX_FREE))
                end
            end
        end
        ns.db.welcomed = true
        ns.MarkChanged()
        ns.Layout(); ns.Refresh()
        ns.Print("Default settings and positions restored. Your wheel spells are preserved.")
    elseif ns.Settings then
        ns.Settings:Toggle()
    end
end
