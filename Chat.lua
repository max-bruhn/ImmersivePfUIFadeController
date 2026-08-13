--[[
 pfUI FadeController - chat windows

 pfUI has two chat containers: the left one (General) and the optional right one
 (Loot & Spam). Each is faded on its own, exactly like the action bars, and each
 gets a small toggle button in its top-right corner so immersive mode can be
 switched on or off without opening the options panel.

 On top of the shared fade rules, chat windows can be brought back automatically
 when a message arrives: whispers, guild and officer chat are on by default. The
 loot trigger has an item-quality threshold, so a rare/epic drop pulls the Loot &
 Spam window back while vendor trash does not.

 A message reveals the window that actually displays that message type (matched
 against each ChatFrame's messageTypeList), so a whisper does not light up the
 loot window.

 Two things sit outside a container's alpha and are handled by hand: the chat
 tabs (Blizzard's dock code re-parents them away from pfUI's panelTop, leaving
 them bright over a faded window) and the pfUI info panel underneath each chat
 window, which each window can opt into fading along with itself.

 Chat fading starts switched OFF per window - the toggle button (or the Chat tab)
 turns it on.
--]]

IPFC = IPFC or {}

-- panelField is the pfUI info panel sitting under that chat window
-- (pfPanelLeft: exp / armour / friends, pfPanelRight: fps / latency / clock / gold)
IPFC.chatWindows = {
    { key = "left",  name = "Left Chat (General)",      field = "left",  panelField = "left",  panelLabel = "exp / armour / friends" },
    { key = "right", name = "Right Chat (Loot & Spam)", field = "right", panelField = "right", panelLabel = "fps / clock / gold" },
}

-- target-wide chat settings (not part of the per-window cascade)
local CHAT_DEFAULTS = {
    buttons           = true,  -- show the corner toggle buttons
    msgSeconds        = 15,    -- how long a triggering message keeps a window up
    revealWhisper     = true,
    revealGuild       = true,
    revealOfficer     = true,
    revealRaidWarning = true,
    revealGroup       = false, -- party / raid chat
    revealSay         = false, -- say / yell / emotes
    revealChannel     = false,
    revealLoot        = false,
    lootQuality       = 4,     -- minimum quality for the loot trigger (4 = epic)
}

IPFC.LOOT_QUALITIES = {
    { value = 0, name = "Anything" },
    { value = 2, name = "Uncommon or better" },
    { value = 3, name = "Rare or better" },
    { value = 4, name = "Epic or better" },
    { value = 5, name = "Legendary" },
}

local function CDB()
    local db = ImmersivePfUIFadeControllerDB
    return db and db.targets and db.targets.chat
end

local function ChatOption(key)
    local t = CDB()
    if t and t[key] ~= nil then return t[key] end
    return CHAT_DEFAULTS[key]
end
IPFC.ChatOption = ChatOption

-- ---------------------------------------------------------------------------
-- saved data
-- ---------------------------------------------------------------------------
local function InitChatDB(t)
    for k, v in pairs(CHAT_DEFAULTS) do
        if t[k] == nil then t[k] = v end
    end

    -- chat wants a gentler fade than a hotbar: a shorter idle delay but a much
    -- longer reveal, so a window stays up long enough to read. Seeded once; the
    -- Chat tab's "Apply global fade settings" hands control back to the globals.
    if t.useOwn == nil then
        t.useOwn = true
        if not t.settings then
            local s = IPFC.CopyFadeSettings(nil)
            s.oocDelay = 60
            s.fadeAlpha = 0.1
            s.hoverSeconds = 20
            s.fadeOutDuration = 4
            s.alwaysInCombat = false
            t.settings = s
        end
    end
    if not t.windows then t.windows = {} end
    local i
    for i = 1, table.getn(IPFC.chatWindows) do
        local wkey = IPFC.chatWindows[i].key
        if not t.windows[wkey] then t.windows[wkey] = { enabled = false } end
    end
end

-- "Also fade the pfUI panel below it"; starts off
function IPFC.ChatPanelIncluded(wkey)
    local t = CDB()
    local w = t and t.windows and t.windows[wkey]
    return w and w.includePanel and true or false
end

-- per-window on/off ("Fade this window"); starts off
function IPFC.ChatWindowEnabled(wkey)
    local t = CDB()
    local w = t and t.windows and t.windows[wkey]
    if not w or w.enabled == nil then return false end
    return w.enabled and true or false
end

function IPFC.SetChatWindowEnabled(wkey, state)
    local t = CDB()
    if not t then return end
    if not t.windows then t.windows = {} end
    if not t.windows[wkey] then t.windows[wkey] = {} end
    t.windows[wkey].enabled = state and true or false
    if state then IPFC.PrimeChatWindow(wkey) else IPFC.ResetChatWindow(wkey) end
    IPFC.UpdateChatButtons()
end

function IPFC.SetChatFading(state)
    local i
    for i = 1, table.getn(IPFC.chatWindows) do
        IPFC.SetChatWindowEnabled(IPFC.chatWindows[i].key, state)
    end
end

-- ---------------------------------------------------------------------------
-- reveal-on-message
-- ---------------------------------------------------------------------------
local revealUntil = { left = 0, right = 0 }

-- event -> { option that must be on, chat message type it lands in }
local TRIGGERS = {
    CHAT_MSG_WHISPER      = { opt = "revealWhisper",     mtype = "WHISPER" },
    CHAT_MSG_GUILD        = { opt = "revealGuild",       mtype = "GUILD" },
    CHAT_MSG_OFFICER      = { opt = "revealOfficer",     mtype = "OFFICER" },
    CHAT_MSG_RAID_WARNING = { opt = "revealRaidWarning", mtype = "RAID_WARNING" },
    CHAT_MSG_PARTY        = { opt = "revealGroup",       mtype = "PARTY" },
    CHAT_MSG_RAID         = { opt = "revealGroup",       mtype = "RAID" },
    CHAT_MSG_SAY          = { opt = "revealSay",         mtype = "SAY" },
    CHAT_MSG_YELL         = { opt = "revealSay",         mtype = "YELL" },
    CHAT_MSG_EMOTE        = { opt = "revealSay",         mtype = "EMOTE" },
    CHAT_MSG_TEXT_EMOTE   = { opt = "revealSay",         mtype = "EMOTE" },
    CHAT_MSG_CHANNEL      = { opt = "revealChannel",     mtype = "CHANNEL" },
    CHAT_MSG_LOOT         = { opt = "revealLoot",        mtype = "LOOT",  loot = true },
    CHAT_MSG_MONEY        = { opt = "revealLoot",        mtype = "MONEY", loot = true },
}

-- item link colours, so the loot trigger can read a drop's quality
local LINK_QUALITY = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2,
    ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5,
}

local function LootQuality(msg)
    if not msg then return 1 end
    local _, _, hex = string.find(msg, "|c%x%x(%x%x%x%x%x%x)|Hitem:")
    if not hex then return 1 end     -- unlinked loot text: treat as common
    local q = LINK_QUALITY[string.lower(hex)]
    if q == nil then return 1 end
    return q
end

-- which pfUI chat container(s) show this message type
local function RevealType(mtype, seconds)
    local left, right = false, false
    local i
    for i = 1, NUM_CHAT_WINDOWS do
        local f = getglobal("ChatFrame" .. i)
        local parent = f and f.GetParent and f:GetParent()
        local wkey
        if parent and pfUI and pfUI.chat then
            if parent == pfUI.chat.left then wkey = "left"
            elseif parent == pfUI.chat.right then wkey = "right" end
        end
        if wkey and f.messageTypeList then
            for _, m in pairs(f.messageTypeList) do
                if m == mtype then
                    if wkey == "left" then left = true else right = true end
                    break
                end
            end
        end
    end

    -- channels live in channelList, and an unmatched type still deserves a
    -- reveal rather than being silently swallowed
    if not left and not right then left = true; right = true end

    local now = GetTime()
    if left  then revealUntil.left  = now + seconds end
    if right then revealUntil.right = now + seconds end
end

local ev = CreateFrame("Frame")
for e in pairs(TRIGGERS) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function()
    if not ImmersivePfUIFadeControllerDB or not CDB() then return end
    if not IPFC.TargetEnabled("chat") then return end
    local trig = TRIGGERS[event]
    if not trig or not ChatOption(trig.opt) then return end
    if trig.loot then
        local q = 0
        if event == "CHAT_MSG_LOOT" then q = LootQuality(arg1) end
        if q < (ChatOption("lootQuality") or 0) then return end
    end
    RevealType(trig.mtype, ChatOption("msgSeconds") or 15)
end)

-- ---------------------------------------------------------------------------
-- corner toggle buttons
-- ---------------------------------------------------------------------------
local buttons = {}

local function ButtonColor(b)
    local on = IPFC.ChatWindowEnabled(b.wkey)
    if on then b.dot:SetTexture(1, 0.82, 0) else b.dot:SetTexture(0.45, 0.45, 0.45) end
end

local function ButtonTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    GameTooltip:AddLine("Immersive fade")
    if IPFC.ChatWindowEnabled(b.wkey) then
        GameTooltip:AddLine("This window fades out when idle.", 0.4, 1, 0.4)
    else
        GameTooltip:AddLine("This window always stays visible.", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("Left-click: toggle", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

local function CreateToggle(wkey, frame)
    if buttons[wkey] then return buttons[wkey] end
    local b = CreateFrame("Button", "IPFCChatToggle" .. wkey, UIParent)
    b.wkey = wkey
    b:SetWidth(13)
    b:SetHeight(13)
    b:SetFrameStrata("MEDIUM")
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    if pfUI and pfUI.api and pfUI.api.CreateBackdrop then
        pfUI.api.CreateBackdrop(b)
    else
        b:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        b:SetBackdropColor(0, 0, 0, 0.8)
        b:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end
    local dot = b:CreateTexture(nil, "OVERLAY")
    dot:SetWidth(5)
    dot:SetHeight(5)
    dot:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.dot = dot
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            if IPFC.ToggleOptions then IPFC.ToggleOptions() end
        else
            IPFC.SetChatWindowEnabled(this.wkey, not IPFC.ChatWindowEnabled(this.wkey))
            if this:IsShown() then ButtonTooltip(this) end
        end
    end)
    b:SetScript("OnEnter", function() ButtonTooltip(this) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    ButtonColor(b)
    buttons[wkey] = b
    return b
end

-- repaint every button (called when a toggle flips)
function IPFC.UpdateChatButtons()
    for _, b in pairs(buttons) do ButtonColor(b) end
end

-- ---------------------------------------------------------------------------
-- target
-- ---------------------------------------------------------------------------
-- is `frame` the container itself or one of its descendants? A frame's alpha
-- carries down to its children, so anything inside fades on its own.
local function IsInside(frame, container)
    local p = frame
    local guard = 0
    while p and guard < 8 do
        if p == container then return true end
        if not p.GetParent then return false end
        p = p:GetParent()
        guard = guard + 1
    end
    return false
end

-- ...but pfUI positions the chat frames and their tabs by anchor, and Blizzard's
-- dock code re-parents tabs, so a piece of a chat window can sit visually inside
-- the container while hanging off UIParent - alpha never reaches it and it stays
-- bright over a faded window. Treat anything anchored into the container as part
-- of it as well.
local function BelongsTo(obj, container)
    if IsInside(obj, container) then return true end
    if not obj.GetNumPoints then return false end
    local n = obj:GetNumPoints()
    local i
    for i = 1, n do
        local _, rel = obj:GetPoint(i)
        if rel and IsInside(rel, container) then return true end
    end
    return false
end

-- Split the chat frames and tabs that make up this window into the ones the
-- container's alpha reaches on its own, and the ones the tick has to fade by
-- hand. Rescanned periodically: docking moves both around at runtime.
local function ScanParts(e)
    local extras, inside = {}, {}
    local i
    for i = 1, NUM_CHAT_WINDOWS do
        local f = getglobal("ChatFrame" .. i)
        local tab = getglobal("ChatFrame" .. i .. "Tab")
        if f and BelongsTo(f, e.frame) then
            if IsInside(f, e.frame) then tinsert(inside, f) else tinsert(extras, f) end
            if tab then
                if IsInside(tab, e.frame) then tinsert(inside, tab) else tinsert(extras, tab) end
            end
        end
    end
    return extras, inside
end

-- alpha for one window: the container, any escaped tab, and (optionally) the
-- pfUI info panel underneath it
local function ApplyWindowAlpha(e, alpha)
    if e.frame.SetAlpha then e.frame:SetAlpha(alpha) end

    local i
    if e.extras then
        for i = 1, table.getn(e.extras) do
            local o = e.extras[i]
            if o and o.SetAlpha then o:SetAlpha(alpha) end
        end
    end
    -- parts the container already fades: keep their own alpha neutral, or the
    -- two would multiply into near-invisibility
    if e.inside then
        for i = 1, table.getn(e.inside) do
            local o = e.inside[i]
            if o and o.SetAlpha and o:GetAlpha() ~= 1 then o:SetAlpha(1) end
        end
    end

    if e.panel and e.panel.SetAlpha then
        if IPFC.ChatPanelIncluded(e.key) then
            e.panel:SetAlpha(alpha)
            e.panelFaded = (alpha ~= 1) and true or false
        elseif e.panelFaded then
            e.panel:SetAlpha(1)
            e.panelFaded = false
        end
    end
end

local function ResolveChat()
    local list = {}
    if not (pfUI and pfUI.chat) then return list end
    local i
    for i = 1, table.getn(IPFC.chatWindows) do
        local def = IPFC.chatWindows[i]
        local f = pfUI.chat[def.field]
        if f and f.SetAlpha then
            local e = {
                frame = f, key = def.key, name = def.name,
                panel = pfUI.panel and pfUI.panel[def.panelField],
                alpha = 1, idleStart = GetTime(), hoverUntil = 0, nextScan = 0,
                button = CreateToggle(def.key, f),
            }
            e.extras, e.inside = ScanParts(e)
            tinsert(list, e)
        end
    end
    return list
end

local function ChatKeys()
    local keys = {}
    local i
    for i = 1, table.getn(IPFC.chatWindows) do tinsert(keys, IPFC.chatWindows[i].key) end
    return keys
end

-- the edit box lives outside the chat containers, so typing keeps them up
local function Typing()
    return ChatFrameEditBox and ChatFrameEditBox:IsShown() and true or false
end

local function ChatTick(key, st, ctx)
    local wins = st.frames
    if not wins or table.getn(wins) == 0 then return end
    local now = ctx.now
    local showButtons = ChatOption("buttons") and true or false
    local typing = Typing()

    local i
    for i = 1, table.getn(wins) do
        local e = wins[i]
        local shown = e.frame and e.frame.IsShown and e.frame:IsShown()
        local hover = shown and MouseIsOver(e.frame, 10, -10, -10, 10) and true or false

        -- an included panel counts as part of the window for mouseover
        if not hover and shown and e.panel and IPFC.ChatPanelIncluded(e.key)
            and e.panel:IsShown() and MouseIsOver(e.panel, 10, -10, -10, 10) then
            hover = true
        end

        -- docking moves frames and tabs around at runtime; recheck once a second
        if now >= (e.nextScan or 0) then
            e.extras, e.inside = ScanParts(e)
            e.nextScan = now + 1
        end

        -- the button only appears while the mouse is on that chat window
        if e.button then
            if showButtons and shown and hover then
                if not e.button:IsShown() then e.button:Show() end
            elseif e.button:IsShown() then
                e.button:Hide()
            end
        end

        if not shown or not IPFC.ChatWindowEnabled(e.key) then
            -- not fading: sit at full alpha and keep the idle timer parked
            e.idleStart = now
            e.hoverUntil = 0
            if e.alpha ~= 1 or e.panelFaded then
                e.alpha = 1
                ApplyWindowAlpha(e, 1)
            end
        else
            local cfg = IPFC.CachedSubConfig("chat", "windows", e.key)
            local active = IPFC.ActiveAlpha(cfg)
            local always = (cfg.alwaysInCombat and ctx.inCombat)
                or (cfg.alwaysInInstance and ctx.inInstance)
                or (cfg.alwaysInGroup and ctx.inGroup)
            local target
            if always then
                e.idleStart = now
                target = active
            else
                if hover or typing then e.hoverUntil = now + cfg.hoverSeconds end
                if now < (e.hoverUntil or 0) or now < (revealUntil[e.key] or 0) then
                    target = active
                elseif (now - (e.idleStart or now)) >= cfg.oocDelay then
                    target = cfg.fadeAlpha
                else
                    target = active
                end
            end
            local cur = e.alpha or 1
            if cur ~= target then
                cur = IPFC.StepAlpha(cur, target, ctx.dt, cfg)
                e.alpha = cur
            end
            -- applied every tick, not only on change: tabs re-parent and the
            -- panel can be included mid-fade, and both must catch up
            ApplyWindowAlpha(e, cur)
        end
    end
end

-- switching a window on starts the fade right away instead of waiting out the
-- idle delay; the mouseover grace keeps it up until the cursor leaves
function IPFC.PrimeChatWindow(wkey)
    local st = IPFC.state.chat
    if not st or not st.frames then return end
    local i
    for i = 1, table.getn(st.frames) do
        local e = st.frames[i]
        if e.key == wkey then e.idleStart = GetTime() - 100000 end
    end
end

-- back to full opacity (a window was switched off, or the whole target was)
function IPFC.ResetChatWindow(wkey)
    local st = IPFC.state.chat
    if not st or not st.frames then return end
    local i
    for i = 1, table.getn(st.frames) do
        local e = st.frames[i]
        if e.key == wkey then
            e.alpha = 1
            e.hoverUntil = 0
            revealUntil[wkey] = 0
            ApplyWindowAlpha(e, 1)
            if e.panel and e.panel.SetAlpha then e.panel:SetAlpha(1); e.panelFaded = false end
        end
    end
end

local function ChatReset(st)
    if not st.frames then return end
    local i
    for i = 1, table.getn(st.frames) do
        local e = st.frames[i]
        e.alpha = 1
        e.hoverUntil = 0
        revealUntil[e.key] = 0
        ApplyWindowAlpha(e, 1)
        if e.panel and e.panel.SetAlpha then e.panel:SetAlpha(1); e.panelFaded = false end
        if e.button then e.button:Hide() end
    end
end

-- /ipfc chatinfo - what the fade actually reaches, when a piece of a chat
-- window refuses to dim
function IPFC.ChatDebug()
    local st = IPFC.state.chat
    if not st or not st.frames then IPFC.Msg("chat: no windows resolved."); return end
    local function name(o)
        if not o then return "nil" end
        if o.GetName and o:GetName() then return o:GetName() end
        return "(unnamed)"
    end
    local i
    for i = 1, table.getn(st.frames) do
        local e = st.frames[i]
        IPFC.Msg(string.format("%s [%s]  shown=%s  alpha=%.2f  fading=%s",
            e.name, name(e.frame), tostring(e.frame:IsShown()), e.frame:GetAlpha(),
            tostring(IPFC.ChatWindowEnabled(e.key))))
        local j
        for j = 1, NUM_CHAT_WINDOWS do
            local f = getglobal("ChatFrame" .. j)
            local tab = getglobal("ChatFrame" .. j .. "Tab")
            if f and BelongsTo(f, e.frame) then
                IPFC.Msg(string.format("   ChatFrame%d parent=%s %s | tab parent=%s %s",
                    j, name(f:GetParent()), (IsInside(f, e.frame) and "inherits" or "|cffffaa00faded by hand|r"),
                    name(tab and tab:GetParent()),
                    (tab and IsInside(tab, e.frame) and "inherits" or "|cffffaa00faded by hand|r")))
            end
        end
        IPFC.Msg(string.format("   handled by hand: %d   inherited: %d   panel=%s",
            table.getn(e.extras or {}), table.getn(e.inside or {}), tostring(IPFC.ChatPanelIncluded(e.key))))
    end
end

IPFC.RegisterTarget("chat", {
    label = "Chat Windows",
    resolve = ResolveChat,
    tick = ChatTick,
    reset = ChatReset,
    initdb = InitChatDB,
    defaultEnabled = true,
    listfield = "windows",
    sublist = ChatKeys,
})
