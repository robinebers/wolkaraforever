-- Shared secure action button for wheels and free buttons. Displays the action icon, cooldown, and
-- range. Outside combat, tap an empty slot (or any slot in Customize mode) to open the picker, or
-- drop a spell into it.

local _, ns = ...

-- The picker offers preset actions using the game's own macro commands.
ns.BUILTIN = {
    { kind = "macrotext", id = "/targetenemy", name = "Target enemy", icon = "Interface\\Icons\\Ability_Hunter_SniperShot" },
    { kind = "macrotext", id = "/startattack", name = "Auto attack", icon = "Interface\\Icons\\INV_Sword_04" },
    { kind = "macrotext", id = "/assist", name = "Assist", icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
    { kind = "macrotext", id = "/targetfriend", name = "Target friendly", icon = "Interface\\Icons\\Spell_Holy_Heal" },
    { kind = "macrotext", id = "/cleartarget", name = "Clear target", icon = "Interface\\Icons\\Spell_Shadow_Teleport" },
    { kind = "macrotext", id = "/follow", name = "Follow", icon = "Interface\\Icons\\Ability_Rogue_Sprint" },
    { kind = "macrotext", id = "/sit", name = "Sit", icon = "Interface\\Icons\\Spell_Nature_Sleep" },
}

function ns.EntryIcon(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return ns.SpellIcon(entry.id) end
    if entry.kind == "item" then return ns.ItemIcon(entry.id) end
    if entry.kind == "macro" then
        local _, icon = GetMacroInfo(entry.id)
        return icon
    end
    if entry.kind == "macrotext" then return entry.icon end
end

function ns.EntryName(entry)
    if not entry then return nil end
    if entry.kind == "spell" then return ns.SpellName(entry.id) end
    if entry.kind == "item" then return ns.ItemName(entry.id) end
    return entry.name or entry.id
end

-- Set the secure attributes for a spell, item, or macro outside combat.
function ns.ApplyButton(button)
    if InCombatLockdown() then return false end
    button.suppressed = nil
    local entry = button:GetEntry()
    button:SetAttribute("spell", nil)
    button:SetAttribute("item", nil)
    button:SetAttribute("macro", nil)
    button:SetAttribute("macrotext", nil)
    if ns.editing or not entry then
        button:SetAttribute("type", nil)
    elseif entry.kind == "spell" then
        button:SetAttribute("type", "spell")
        button:SetAttribute("spell", ns.SpellName(entry.id) or entry.id)
    elseif entry.kind == "item" then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. entry.id)
    elseif entry.kind == "macro" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macro", entry.id)
    elseif entry.kind == "macrotext" then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", entry.id)
    end
    return true
end

-- Show the remaining cooldown over a grayed-out icon so it is readable on a small round button even
-- when the game's cooldown text is disabled. Global cooldowns under two seconds use only the sweep.
local GLOBAL_COOLDOWN = 2
local ticking = {}

function ns.CooldownText(remaining)
    if remaining >= 60 then return math.ceil(remaining / 60) .. "m" end
    if remaining >= 3 then return tostring(math.ceil(remaining)) end
    return string.format("%.1f", remaining)
end

local function StopTimer(button)
    ticking[button] = nil
    if button.timer then button.timer:SetText("") end
    button.icon:SetDesaturated(false)
end

local ticker = CreateFrame("Frame")
local sinceTick = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
    sinceTick = sinceTick + elapsed
    if sinceTick < 0.1 then return end
    sinceTick = 0
    local now = GetTime()
    for button, ends in pairs(ticking) do
        if ends - now <= 0 then StopTimer(button) else button.timer:SetText(ns.CooldownText(ends - now)) end
    end
end)

function ns.UpdateCooldown(button)
    local entry = button:GetEntry()
    local start, duration, enable
    if entry and entry.kind == "spell" then
        start, duration, enable = ns.SpellCooldown(entry.id)
    elseif entry and entry.kind == "item" then
        start, duration, enable = ns.ItemCooldown(entry.id)
    end
    if start and duration and duration > 0 and enable ~= 0 and enable ~= false then
        if CooldownFrame_Set then
            CooldownFrame_Set(button.cooldown, start, duration, 1)
        else
            button.cooldown:SetCooldown(start, duration)
            button.cooldown:Show()
        end
        if duration > GLOBAL_COOLDOWN and button.timer then
            ticking[button] = start + duration
            button.timer:SetText(ns.CooldownText(math.max(0, start + duration - GetTime())))
            button.icon:SetDesaturated(true)
        else
            StopTimer(button)
        end
    else
        if button.cooldown.Clear then button.cooldown:Clear() end
        button.cooldown:Hide()
        StopTimer(button)
    end
end

function ns.UpdateState(button)
    local entry = button:GetEntry()
    if not entry then return end
    local usable, noPower, inRange = true, false, nil
    if entry.kind == "spell" then
        usable, noPower = ns.SpellUsable(entry.id)
        inRange = ns.SpellInRange(entry.id)
    elseif entry.kind == "item" then
        usable = (ns.ItemCount(entry.id) or 0) > 0
    end
    if inRange == false then
        button.icon:SetVertexColor(0.95, 0.3, 0.3)
    elseif noPower then
        button.icon:SetVertexColor(0.4, 0.5, 1)
    elseif usable == false then
        button.icon:SetVertexColor(0.45, 0.45, 0.45)
    else
        button.icon:SetVertexColor(1, 1, 1)
    end
end

function ns.RefreshButton(button)
    local entry = button:GetEntry()
    button.count:SetText("")
    if entry then
        button.icon:SetTexture(ns.EntryIcon(entry) or ns.QUESTION)
        button.icon:Show()
        button.plus:Hide()
        if entry.kind == "item" then
            local count = ns.ItemCount(entry.id) or 0
            if count ~= 1 then button.count:SetText(count) end
        end
    else
        button.icon:Hide()
        button.plus:Show()
    end
    button.icon:SetVertexColor(1, 1, 1)
    button.editGlow:SetShown(ns.editing)
    ns.UpdateCooldown(button)
    ns.UpdateState(button)
end

-- Save and redraw the assigned action; apply it outside combat.
function ns.AssignEntry(button, entry)
    button:SetEntry(entry)
    ns.MarkChanged()
    ns.RefreshButton(button)
    ns.ApplyButton(button)
    if button.OnAssigned then button:OnAssigned() end
end

function ns.AssignFromCursor(button)
    if InCombatLockdown() then
        ns.Print("Assign slots outside combat.")
        return
    end
    local entry = ns.CursorEntry()
    if not entry then return end
    local previous = button:GetEntry()
    ns.AssignEntry(button, entry)
    ClearCursor()
    -- Move the previous slot contents to the cursor, like an action bar.
    if previous and previous.kind ~= "macrotext" then ns.PickupEntry(previous) end
end

-- getEntry and setEntry access the underlying wheel or free-button slot.
function ns.CreateActionButton(name, parent, size, getEntry, setEntry)
    local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    button:SetSize(size, size)
    -- Register both edges. The secure template chooses one according to the game's cast-on-key-down
    -- setting.
    button:RegisterForClicks("AnyUp", "AnyDown")
    button.GetEntry = function() return getEntry() end
    button.SetEntry = function(_, entry) setEntry(entry) end

    ns.Disc(button, "BACKGROUND", 0.05, 0.05, 0.08, 0.85, 4)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local round = ns.Circle(button, button.icon)

    button.plus = ns.Label(button, "GameFontNormalHuge", "+")
    button.plus:SetPoint("CENTER")
    button.plus:SetTextColor(0.55, 0.55, 0.55)

    button.count = ns.Label(button, "NumberFontNormal")
    button.count:SetPoint("BOTTOMRIGHT", -8, 8)

    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    if round and button.cooldown.SetSwipeTexture then button.cooldown:SetSwipeTexture(ns.CIRCLE) end
    if button.cooldown.SetUseCircularEdge then button.cooldown:SetUseCircularEdge(true) end
    if button.cooldown.SetSwipeColor then button.cooldown:SetSwipeColor(0, 0, 0, 0.75) end
    if button.cooldown.SetHideCountdownNumbers then button.cooldown:SetHideCountdownNumbers(true) end
    -- Draw the remaining time above the cooldown sweep.
    local over = CreateFrame("Frame", nil, button)
    over:SetAllPoints()
    over:SetFrameLevel(button.cooldown:GetFrameLevel() + 2)
    button.timer = over:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    button.timer:SetPoint("CENTER")
    button.timer:SetTextColor(1, 1, 1)
    button.timer:SetShadowOffset(1, -1)

    button.editGlow = ns.Disc(button, "OVERLAY", 1, 0.8, 0.2, 0.28, 0)
    button.editGlow:Hide()
    local highlight = ns.Disc(button, "HIGHLIGHT", 1, 1, 1, 0.18, 0)
    highlight:SetBlendMode("ADD")

    -- Treat a tap as assignment when the cursor holds an action, the slot is empty, or Customize
    -- mode is active.
    button:SetScript("PreClick", function(self)
        if InCombatLockdown() or self.swiped then return end
        if ns.editing or GetCursorInfo() or not self:GetEntry() then
            self:SetAttribute("type", nil)
            self.suppressed = true
        end
    end)
    button:SetScript("PostClick", function(self, _, down)
        -- A wheel swipe suppresses both casting and the picker (Turn.lua).
        if self.swiped and not down then self.swiped = nil; return end
        if InCombatLockdown() or down or not self.suppressed then return end
        if GetCursorInfo() then
            ns.AssignFromCursor(self)
        elseif ns.Picker then
            ns.Picker:Open(self)
        end
        ns.ApplyButton(self)
    end)
    button:SetScript("OnReceiveDrag", function(self) ns.AssignFromCursor(self) end)
    return button
end
