-- Mobile chat sits between the thumbsticks and sends through the game's edit box. The compact feed
-- shows fading messages, conversation and system tabs, and an unread whisper count. Tap to expand
-- the history, scroll, or choose a destination. Tapping a player's name selects a whisper recipient.
-- Return opens the selected conversation via F12 (Say by default); slash commands use the game's
-- slash key. Hide collapses chat beside the keyboard, counts new player messages, and still allows
-- typing.

local _, ns = ...

local Chat = ns.Register("Chat", {})
ns.Chat = Chat
local MAX_MESSAGES = 300
local LINES = 3          -- in the feed
local OPEN_KEY = "F12"
local PAD, GAP, ROW, HINT, ARROW, QUICK_H = 8, 6, 36, 20, 44, 28
local BOTTOM = 0.12      -- fraction of screen height reserved for the app toolbar below chat
local STRIP = 0.36       -- feed width as a fraction of the screen, between the lowest wheel slots
local HIDE_W = 84        -- Hide button
-- Measured on the Duo (2026-11-06): the collapsed toolbar was 96 by 34 points, centered 42 points
-- above the bottom of a 669-point-high screen. Align the 44-by-34 chat button eight points left of
-- its keyboard button. Values below are fractions of screen height.
local BAR_HALF, BAR_BOTTOM, BAR_HEIGHT, BAR_GAP, MINI_WIDTH = 48 / 669, 42 / 669, 34 / 669, 8 / 669, 44 / 669

local messages = {}
local target = { kind = "say" }
local lastWhisper
local unread = 0
local pending = 0        -- player messages since the feed was hidden
local ticker, panel, list, tabButtons, quick, chips, to, hint, badge, opener, close, arrows, holder
local hideButton, mini, miniCount
local hider = CreateFrame("Frame")
hider:Hide()

local TABS = {
    { key = "talk", label = "Chat" }, { key = "whisper", label = "Whispers" },
    { key = "system", label = "System" }, { key = "all", label = "All" },
}
local QUICK = { { key = "talk", label = "Chat" }, { key = "system", label = "System" } }
local KNOWN = { talk = true, whisper = true, system = true, all = true }

-- Map game chat events to display labels and tabs.
local TALK = { all = true, talk = true }
local PRIVATE = { all = true, talk = true, whisper = true }
local NPC = { all = true }
local SYSTEM = { system = true }
local EVENTS = {
    CHAT_MSG_SAY = { label = "Say", tabs = TALK },
    CHAT_MSG_YELL = { label = "Yell", tabs = TALK },
    CHAT_MSG_EMOTE = { emote = true, tabs = TALK },
    CHAT_MSG_TEXT_EMOTE = { raw = true, tabs = TALK },
    CHAT_MSG_PARTY = { label = "Group", tabs = TALK },
    CHAT_MSG_PARTY_LEADER = { label = "Leader", tabs = TALK },
    CHAT_MSG_RAID = { label = "Raid", tabs = TALK },
    CHAT_MSG_RAID_LEADER = { label = "Raid leader", tabs = TALK },
    CHAT_MSG_RAID_WARNING = { label = "Warning", tabs = TALK },
    CHAT_MSG_INSTANCE_CHAT = { label = "Instance", tabs = TALK },
    CHAT_MSG_INSTANCE_CHAT_LEADER = { label = "Instance", tabs = TALK },
    CHAT_MSG_GUILD = { label = "Guild", tabs = TALK },
    CHAT_MSG_OFFICER = { label = "Officer", tabs = TALK },
    CHAT_MSG_WHISPER = { label = "From", tabs = PRIVATE, incoming = true },
    CHAT_MSG_WHISPER_INFORM = { label = "To", tabs = PRIVATE },
    CHAT_MSG_CHANNEL = { channel = true, tabs = TALK },
    CHAT_MSG_MONSTER_SAY = { label = "Says", tabs = NPC },
    CHAT_MSG_MONSTER_YELL = { label = "Yells", tabs = NPC },
    CHAT_MSG_MONSTER_WHISPER = { label = "Whispers", tabs = NPC },
    CHAT_MSG_MONSTER_EMOTE = { emote = true, tabs = NPC },
    CHAT_MSG_SYSTEM = { raw = true, tabs = { all = true, system = true } },
    CHAT_MSG_LOOT = { raw = true, tabs = SYSTEM },
    CHAT_MSG_MONEY = { raw = true, tabs = SYSTEM },
    CHAT_MSG_COMBAT_XP_GAIN = { raw = true, tabs = SYSTEM },
    CHAT_MSG_COMBAT_FACTION_CHANGE = { raw = true, tabs = SYSTEM },
    CHAT_MSG_SKILL = { raw = true, tabs = SYSTEM },
}

local TARGETS = {
    { kind = "say", label = "Say" }, { kind = "party", label = "Group" }, { kind = "guild", label = "Guild" },
    { kind = "general", label = "General" }, { kind = "whisper", label = "Reply" },
}

local WRITE = "Tap the keyboard below chat to type. Press Return to send."

-- Message history

local function Tab()
    local tab = ns.db and ns.db.chat.tab
    return KNOWN[tab] and tab or "talk"
end

local function Color(event, channelIndex)
    local key = event:sub(10)
    if key == "CHANNEL" and channelIndex then key = "CHANNEL" .. channelIndex end
    local info = ChatTypeInfo and (ChatTypeInfo[key] or ChatTypeInfo[event:sub(10)])
    if info then return info.r or 1, info.g or 1, info.b or 1 end
    return 1, 1, 1
end

local function PlayerLink(name)
    if not name or name == "" then return "" end
    local short = Ambiguate and Ambiguate(name, "short") or name
    return ("|Hplayer:%s|h%s|h"):format(name, short)
end

local function Short(name) return Ambiguate and Ambiguate(name, "short") or name end

local function Format(info, text, author, channelIndex, channelBase)
    local stamp = date and date("%H:%M ") or ""
    if info.raw then return stamp .. text end
    if info.emote then return stamp .. PlayerLink(author) .. " " .. text end
    local label = info.label
    if info.channel then
        label = (channelIndex and (channelIndex .. ". ") or "") .. (channelBase ~= "" and channelBase or "Channel")
    end
    return ("%s[%s] %s: %s"):format(stamp, label, PlayerLink(author), text)
end

local function Shows(entry) return entry.tabs[Tab()] end

local function Store(entry)
    messages[#messages + 1] = entry
    if #messages > MAX_MESSAGES then table.remove(messages, 1) end
    if not Shows(entry) then return end
    if panel and panel:IsShown() then list:AddMessage(entry.line, entry.r, entry.g, entry.b) end
    if ticker then ticker:AddMessage(entry.line, entry.r, entry.g, entry.b) end
end

local UpdateChips

local function Add(event, text, author, _, _, _, _, _, channelIndex, channelBase)
    local info = EVENTS[event]
    if not info or type(text) ~= "string" then return end
    local r, g, b = Color(event, channelIndex)
    if info.incoming and author then
        lastWhisper = author
        if not (panel and panel:IsShown() and Tab() == "whisper") then unread = unread + 1 end
    end
    Store({ line = Format(info, text, author, channelIndex, channelBase), r = r, g = g, b = b, tabs = info.tabs })
    if badge then Chat:UpdateBadge() end
    if info.incoming and UpdateChips then UpdateChips() end
    if mini and info.tabs.talk and ns.db and ns.db.chat.hidden then
        pending = pending + 1
        Chat:UpdateMini()
    end
end

-- Display the full tab in the panel and the latest fading messages in the feed.
local function Rebuild()
    if panel:IsShown() then
        list:Clear()
        for _, entry in ipairs(messages) do
            if Shows(entry) then list:AddMessage(entry.line, entry.r, entry.g, entry.b) end
        end
        list:ScrollToBottom()
    end
    ticker:Clear()
    local recent = {}
    for i = #messages, 1, -1 do
        if Shows(messages[i]) then
            recent[#recent + 1] = messages[i]
            if #recent == LINES then break end
        end
    end
    for i = #recent, 1, -1 do ticker:AddMessage(recent[i].line, recent[i].r, recent[i].g, recent[i].b) end
end

-- Sending: prefix the game input with the chosen conversation.

local function Prefix()
    if target.kind == "say" then return "/s " end
    if target.kind == "party" then return (IsInRaid and IsInRaid()) and "/raid " or "/p " end
    if target.kind == "guild" then return "/g " end
    if target.kind == "general" then return "/1 " end
    if target.kind == "whisper" then
        local name = target.name or lastWhisper
        if name then return "/w " .. name .. " " end
    end
    return ""
end
Chat.Prefix = Prefix

local function OpenInput()
    if ChatFrame_OpenChat then ChatFrame_OpenChat(Prefix(), DEFAULT_CHAT_FRAME) end
end

local function Paint(button, selected)
    button.back:SetVertexColor(selected and 0.85 or 0.18, selected and 0.68 or 0.18, selected and 0.3 or 0.22, 0.95)
end

function UpdateChips()
    if not chips then return end
    for _, chip in ipairs(chips) do
        if chip.kind == "whisper" then
            local name = target.name or lastWhisper
            chip.text:SetText(name and ("To " .. Short(name)) or "Reply")
        end
        Paint(chip, chip.kind == target.kind)
    end
end

local function UpdateTabs()
    local tab = Tab()
    for _, button in ipairs(tabButtons) do Paint(button, button.key == tab) end
    for _, button in ipairs(quick) do Paint(button, button.key == tab) end
end

local function SetTab(key)
    ns.db.chat.tab = key
    if key == "whisper" then unread = 0 end
    Chat:UpdateBadge()
    UpdateTabs()
    Rebuild()
end
Chat.SetTab = SetTab

-- Move the original chat out of sight, leaving its edit box over the feed while typing.

local moved = {}
local function GameChat()
    local frames = {}
    local function add(frame) if frame then frames[#frames + 1] = frame end end
    for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
            "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton" }) do
        add(_G[name])
    end
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        add(_G["ChatFrame" .. i])
        add(_G["ChatFrame" .. i .. "Tab"])
        add(_G["ChatFrame" .. i .. "ButtonFrame"])
    end
    return frames
end

local function GameBox() return (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox) or _G.ChatFrame1EditBox end

-- Show the input only while typing. Control the parent opacity because the game's classic chat style
-- sets the edit box's own opacity.
local function ShowBox(on) holder:SetAlpha(on and 1 or 0) end

local boxParent, boxHooked
local function TuckGameChat(on)
    local box = GameBox()
    if on then
        for _, frame in ipairs(GameChat()) do
            if frame:GetParent() ~= hider then
                moved[frame] = frame:GetParent() or UIParent
                frame:SetParent(hider)
            end
        end
        if box then
            if not boxParent then boxParent = box:GetParent() or UIParent end
            if not boxHooked then
                boxHooked = true
                box:HookScript("OnEditFocusGained", function() ShowBox(true) end)
                box:HookScript("OnEditFocusLost", function() ShowBox(false) end)
            end
            box:SetParent(holder)
            box:SetFrameStrata("FULLSCREEN_DIALOG")
            box:EnableMouse(false)
            box:ClearAllPoints()
            box:SetPoint("BOTTOMLEFT", ticker, "BOTTOMLEFT", 0, 0)
            box:SetPoint("BOTTOMRIGHT", ticker, "BOTTOMRIGHT", 0, 0)
            ShowBox(box.HasFocus and box:HasFocus())
        end
    else
        for frame, parent in pairs(moved) do
            frame:SetParent(parent)
            moved[frame] = nil
        end
        if box and boxParent then
            box:SetParent(boxParent)
            box:EnableMouse(true)
            boxParent = nil
            if FCF_DockUpdate then pcall(FCF_DockUpdate) end
        end
    end
end

-- Chat layout

local function SetFont(frame, size)
    local font, _, flags = (ChatFontNormal or GameFontNormal):GetFont()
    if font then frame:SetFont(font, size, flags) end
end

-- Distribute equal-width buttons across the row. Clip long labels before the next button.
local function Row(parent, buttons, anchor, x, y, width, height)
    local each = (width - GAP * (#buttons - 1)) / #buttons
    for i, button in ipairs(buttons) do
        button:SetSize(each, height)
        button:ClearAllPoints()
        button:SetPoint(anchor, parent, anchor, x + (i - 1) * (each + GAP), y)
        button.text:SetWidth(math.max(1, each - 8))
        if button.text.SetWordWrap then button.text:SetWordWrap(false) end
    end
    return each
end
Chat.Row = Row

local function ArrowButton(parent, texture, onClick)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ARROW, ARROW)
    button:SetNormalTexture(texture .. "-Up")
    button:SetPushedTexture(texture .. "-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", onClick)
    return button
end

-- Switch between feed, expanded panel, and the button beside the keyboard. Customize mode always
-- shows the feed so it can be moved.
local function Arrange()
    local settings = ns.db.chat
    if not settings.custom then
        ticker:Hide(); panel:Hide(); mini:Hide()
        return
    end
    if settings.hidden and not ns.editing then
        panel:Hide(); ticker:Hide(); mini:Show()
    else
        mini:Hide()
        if not panel:IsShown() then ticker:Show() end
    end
    Chat:UpdateMini()
end

local function Open()
    if ns.editing then return end
    panel:Show()
    ticker:Hide()
    if Tab() == "whisper" then unread = 0 end
    Chat:UpdateBadge()
    Rebuild()
    UpdateChips()
end

local function Close()
    panel:Hide()
    Arrange()
    Rebuild()
end
Chat.Open, Chat.Close = Open, Close

-- Persist visibility with the next save, like the active tab. Toggling chat alone should not trigger
-- a UI reload.
local function SetHidden(on)
    ns.db.chat.hidden = on and true or false
    pending = 0
    Arrange()
    if not on then Rebuild() end
end
Chat.SetHidden = SetHidden

function Chat:UpdateBadge()
    badge:SetText(unread > 0 and (unread .. (unread == 1 and " new whisper" or " new whispers")) or "")
end

function Chat:UpdateMini()
    if not miniCount then return end
    miniCount:SetText(pending > 99 and "99+" or pending > 0 and tostring(pending) or "")
end

-- Expanded panel: tabs and close button above the history, scrolling controls alongside it, and
-- destinations below.
local function LayoutPanel(width, height)
    panel:SetSize(width, height)
    close:SetSize(ARROW, ROW)
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)
    Row(panel, tabButtons, "TOPLEFT", PAD, -PAD, width - 2 * PAD - ARROW - GAP, ROW)

    to:ClearAllPoints()
    to:SetPoint("LEFT", panel, "BOTTOMLEFT", PAD, PAD + ROW / 2)
    local label = (to:GetStringWidth() or 30) + GAP
    Row(panel, chips, "BOTTOMLEFT", PAD + label, PAD, width - 2 * PAD - label, ROW)
    hint:ClearAllPoints()
    hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD + ROW + 4)
    hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD + ROW + 4)

    local top = PAD + ROW + GAP
    list:ClearAllPoints()
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(PAD + ARROW + GAP), PAD + ROW + 4 + HINT + GAP)
    for i, arrow in ipairs(arrows) do
        arrow:ClearAllPoints()
        arrow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(top + (i - 1) * (ARROW + GAP)))
    end
end

-- Place quick tabs above the feed on the left, Hide on the right, and the unread whisper count above
-- Hide.
local function LayoutStrip(width)
    Row(ticker, quick, "TOPLEFT", 0, QUICK_H + 4, width * 0.6 - GAP, QUICK_H)
    local hideWidth = math.min(HIDE_W, width * 0.4 - GAP)
    hideButton:SetSize(hideWidth, QUICK_H)
    hideButton.text:SetWidth(math.max(1, hideWidth - 8))
    hideButton:ClearAllPoints()
    hideButton:SetPoint("TOPRIGHT", ticker, "TOPRIGHT", 0, QUICK_H + 4)
    badge:ClearAllPoints()
    badge:SetPoint("BOTTOMRIGHT", hideButton, "TOPRIGHT", 0, 4)
end

-- Align the collapsed chat button just left of the toolbar keyboard.
local function LayoutMini(height)
    local size = height * BAR_HEIGHT
    mini:SetSize(height * MINI_WIDTH, size)
    mini:ClearAllPoints()
    mini:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -height * (BAR_HALF + BAR_GAP), height * BAR_BOTTOM)
    mini.icon:SetSize(size * 0.8, size * 0.8)
end

function Chat:Init()
    holder = CreateFrame("Frame", nil, UIParent)
    holder:SetFrameStrata("FULLSCREEN_DIALOG")
    holder:SetAllPoints(UIParent)
    holder:EnableMouse(false)
    holder:SetAlpha(0)

    -- Show the active tab's newest messages, then let them fade.
    ticker = CreateFrame("ScrollingMessageFrame", "WolkaraMobileChatTicker", UIParent)
    ticker:SetFrameStrata("LOW")
    ticker:SetJustifyH("LEFT")
    ticker:SetMaxLines(40)
    ticker:SetFading(true)
    ticker:SetTimeVisible(20)
    if ticker.SetHyperlinksEnabled then ticker:SetHyperlinksEnabled(false) end
    ticker:EnableMouse(true)
    ticker:SetScript("OnMouseUp", function() Open() end)
    ticker.back = ns.Box(ticker, "BACKGROUND", 0, 0, 0, 0.25)
    ticker.glow = ns.EditFrame(ticker)
    quick = {}
    for i, info in ipairs(QUICK) do
        local button = ns.UIButton(ticker, info.label, 100, QUICK_H, function() SetTab(info.key) end)
        button.text:SetFontObject("GameFontHighlight")
        button.key = info.key
        quick[i] = button
    end
    hideButton = ns.UIButton(ticker, "Hide", HIDE_W, QUICK_H, function() SetHidden(true) end)
    hideButton.text:SetFontObject("GameFontHighlight")
    if hideButton.text.SetWordWrap then hideButton.text:SetWordWrap(false) end
    badge = ns.Label(ticker, "GameFontNormal")
    badge:SetTextColor(1, 0.5, 1)
    ns.Movable(ticker, function() return ns.db.chat end, "pos",
        function() return { "BOTTOM", "BOTTOM", 0, UIParent:GetHeight() * BOTTOM } end)

    -- The collapsed feed shows a bubble and the new message count in pink.
    mini = ns.UIButton(UIParent, "", 44, 34, function() SetHidden(false) end)
    mini:SetFrameStrata("LOW")
    mini.back:SetVertexColor(0.05, 0.05, 0.08, 0.7)
    mini.icon = mini:CreateTexture(nil, "ARTWORK")
    mini.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
    mini.icon:SetPoint("CENTER")
    miniCount = ns.Label(mini, "GameFontNormal")
    miniCount:SetTextColor(1, 0.5, 1)
    miniCount:SetPoint("TOPRIGHT", mini, "TOPRIGHT", -2, -2)
    mini:Hide()
    Chat.mini = mini

    -- The expanded panel occupies the feed's position.
    panel = CreateFrame("Frame", "WolkaraMobileChat", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetPoint("BOTTOM", ticker, "BOTTOM", 0, 0)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    ns.Box(panel, "BACKGROUND", 0.03, 0.04, 0.07, 0.92)

    tabButtons = {}
    for i, info in ipairs(TABS) do
        local button = ns.UIButton(panel, info.label, 90, ROW, function() SetTab(info.key) end)
        button.key = info.key
        tabButtons[i] = button
    end
    close = ns.UIButton(panel, "X", ARROW, ROW, Close)

    list = CreateFrame("ScrollingMessageFrame", "WolkaraMobileChatList", panel)
    list:SetJustifyH("LEFT")
    list:SetMaxLines(MAX_MESSAGES)
    list:SetFading(false)
    list:EnableMouse(true)
    if list.SetHyperlinksEnabled then list:SetHyperlinksEnabled(true) end
    list:SetScript("OnHyperlinkClick", function(self, link, text, button)
        local name = link:match("^player:([^:]+)")
        if name then
            target = { kind = "whisper", name = name }
            UpdateChips()
            hint:SetText("Whisper to " .. Short(name) .. ": tap the keyboard below chat.")
        elseif SetItemRef then
            SetItemRef(link, text, button, self)
        end
    end)

    arrows = {
        ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", function()
            for _ = 1, 3 do list:ScrollUp() end
        end),
        ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", function()
            for _ = 1, 3 do list:ScrollDown() end
        end),
        ArrowButton(panel, "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd", function() list:ScrollToBottom() end),
    }

    to = ns.Label(panel, "GameFontNormal", "To:")
    chips = {}
    for i, info in ipairs(TARGETS) do
        local chip = ns.UIButton(panel, info.label, 100, ROW, function()
            target = { kind = info.kind }
            if info.kind == "whisper" then target.name = lastWhisper end
            UpdateChips()
            hint:SetText(WRITE)
        end)
        chip.kind = info.kind
        chips[i] = chip
    end
    hint = ns.Label(panel, "GameFontHighlightSmall", WRITE)
    hint:SetJustifyH("LEFT")
    if hint.SetWordWrap then hint:SetWordWrap(false) end

    -- The app sends F12 before a message.
    opener = CreateFrame("Button", "WolkaraMobileChatOpener", UIParent)
    opener:SetScript("OnClick", function() ns.Guard("open chat input", OpenInput) end)

    -- Route add-on notices to both quick tabs when mobile chat replaces game chat.
    ns.ChatAdd = function(line)
        if not ns.db or not ns.db.chat.custom then return false end
        Store({ line = line, r = 1, g = 1, b = 1, tabs = { all = true, system = true, talk = true } })
        return true
    end
end

function Chat:Layout()
    local settings = ns.db.chat
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local size = settings.fontSize
    if not KNOWN[settings.tab] then settings.tab = "talk" end
    ticker:SetSize(W * STRIP, size * LINES + 14)
    SetFont(ticker, size)
    LayoutStrip(W * STRIP)
    -- Fit the expanded panel between the sticks.
    local side = W * ns.STICK_X + H * 0.10
    LayoutPanel(ns.Clamp(W - 2 * side, W * 0.5, W - 16), H * 0.55)
    SetFont(list, size)
    LayoutMini(H)
    ticker:PlaceSaved()
    UpdateTabs()
    UpdateChips()
    if settings.custom then
        TuckGameChat(true)
    else
        TuckGameChat(false)
        local frame = ChatFrame1
        if frame and FCF_SetChatWindowFontSize then pcall(FCF_SetChatWindowFontSize, nil, frame, size) end
    end
    Arrange()
    -- Bind F12 for both layouts because the app sends it before each message.
    if SetOverrideBindingClick then
        ClearOverrideBindings(opener)
        SetOverrideBindingClick(opener, true, OPEN_KEY, "WolkaraMobileChatOpener", "LeftButton")
    end
end

function Chat:SetEditing(on)
    ticker.glow:SetShown(on)
    ticker.back:SetVertexColor(0, 0, 0, on and 0.45 or 0.25)
    if on then panel:Hide() end
    Arrange()
end

for event in pairs(EVENTS) do
    ns.On(event, function(...) Add(event, ...) end)
end

-- Reapply after the game repositions its chat frames in Edit Mode or on a zone change.
local function Again()
    if ns.db and ns.db.chat.custom and not InCombatLockdown() then TuckGameChat(true) end
end
ns.On("PLAYER_ENTERING_WORLD", function()
    if C_Timer and C_Timer.After then C_Timer.After(2, Again) else Again() end
end)
ns.On("UPDATE_CHAT_WINDOWS", Again)
