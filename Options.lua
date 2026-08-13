--[[
 pfUI FadeController - options panel

 Wide, two-column, pfUI-skinned, Blizzard-style. One tab per pfUI element
 (General, Action Bars, Chat). Settings cascade in three tiers:
   Global fade settings  ->  element settings (when "Apply global" is OFF)
                         ->  per-bar / per-window settings (when "Override" is ON)
 A reusable settings block (the fade controls) is re-bound to whichever tier a
 given column edits; a dark overlay marks a block whose tier is not in use.
--]]

IPFC = IPFC or {}

local FONT = STANDARD_TEXT_FONT
local FONT_SIZE = 11
if pfUI then
    if pfUI.font_default then FONT = pfUI.font_default end
    if pfUI_config and pfUI_config.global and pfUI_config.global.font_size then
        FONT_SIZE = tonumber(pfUI_config.global.font_size) or 11
    end
end

local function SetF(fs, size, flag)
    if fs and fs.SetFont then fs:SetFont(FONT, size or FONT_SIZE, flag) end
end
local function round(v, step) return math.floor(v / step + 0.5) * step end
local function fmtDelay(s)
    if s >= 60 then local m = math.floor(s / 60); return m .. "m " .. (s - m * 60) .. "s" end
    return s .. "s"
end
-- sub-second precision below a minute, m/s above it
local function fmtSecs(s)
    if s >= 60 then return fmtDelay(round(s, 1)) end
    return string.format("%.1f", s) .. "s"
end

local function D() return ImmersivePfUIFadeControllerDB.defaults end
local function TAB() return ImmersivePfUIFadeControllerDB.targets.actionbars end

-- ---------------------------------------------------------------------------
-- skinned widgets
-- ---------------------------------------------------------------------------
local function Header(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetF(fs, FONT_SIZE + 1)
    fs:SetTextColor(1, 0.82, 0)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Label(parent, text, x, y, r, g, b, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SetF(fs, size or FONT_SIZE)
    fs:SetTextColor(r or 0.8, g or 0.8, b or 0.8)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Slider(parent, name, x, y, w, minv, maxv, step, getf, setf, fmt)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetWidth(w)
    s:SetHeight(16)
    s:SetMinMaxValues(minv, maxv)
    s:SetValueStep(step)
    getglobal(name .. "Low"):SetText("")
    getglobal(name .. "High"):SetText("")
    local cap = getglobal(name .. "Text")
    SetF(cap, FONT_SIZE)
    s.caption = cap
    s.fmt = fmt
    s.setf = setf
    s:SetScript("OnValueChanged", function()
        local v = round(this:GetValue(), step)
        if not this.loading then this.setf(v) end
        this.caption:SetText(this.fmt(v))
    end)
    s.Load = function()
        s.loading = true
        s:SetValue(getf())
        s.caption:SetText(s.fmt(round(getf(), step)))
        s.loading = false
    end
    if pfUI and pfUI.api and pfUI.api.SkinSlider then pfUI.api.SkinSlider(s) end
    return s
end

local function Check(parent, name, x, y, label, getf, setf)
    local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c:SetWidth(18)
    c:SetHeight(18)
    local fs = c:CreateFontString(nil, "OVERLAY")
    SetF(fs, FONT_SIZE)
    fs:SetPoint("LEFT", c, "RIGHT", 6, 0)
    fs:SetText(label)
    c.textfs = fs
    c.baseLabel = label
    c.setf = setf
    c:SetScript("OnClick", function() this.setf(this:GetChecked() and true or false) end)
    c.Load = function() c:SetChecked(getf()) end
    if pfUI and pfUI.api and pfUI.api.SkinCheckbox then pfUI.api.SkinCheckbox(c, 16) end
    return c
end

-- ---------------------------------------------------------------------------
-- reusable settings block (fade controls bound to a dynamic table)
-- ---------------------------------------------------------------------------
local BLOCK_W = 250
local BLOCK_H = 296
-- opts.graceMax / opts.graceStep widen the mouseover-reveal slider for elements
-- that want a long grace (chat windows: minutes rather than seconds)
local function SettingsBlock(parent, prefix, x, y, opts)
    if not opts then opts = {} end
    local graceMax = opts.graceMax or 10
    local graceStep = opts.graceStep or 0.5
    local block = { controls = {}, tbl = nil, active = true }
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    f:SetWidth(BLOCK_W)
    f:SetHeight(BLOCK_H)
    block.frame = f
    local sw = BLOCK_W - 20

    -- an inactive block shows what its unit actually inherits: its own table if
    -- it has one, else the tier above it (element settings), else the globals
    local function get(key)
        if block.tbl and block.tbl[key] ~= nil then return block.tbl[key] end
        if block.fallback and block.fallback[key] ~= nil then return block.fallback[key] end
        return D()[key]
    end
    local function set(key, v) if block.active and block.tbl then block.tbl[key] = v end end
    local function add(c) tinsert(block.controls, c) end

    add(Slider(f, prefix .. "Delay", 4, -16, sw, 5, 600, 5,
        function() return get("oocDelay") end, function(v) set("oocDelay", v) end,
        function(v) return "Out-of-combat delay:  " .. fmtDelay(v) end))
    add(Slider(f, prefix .. "Active", 4, -50, sw, 0.1, 1, 0.05,
        function() return get("activeAlpha") end, function(v) set("activeAlpha", v) end,
        function(v) return "Active opacity:  " .. string.format("%.2f", v) end))
    add(Slider(f, prefix .. "Alpha", 4, -84, sw, 0, 1, 0.05,
        function() return get("fadeAlpha") end, function(v) set("fadeAlpha", v) end,
        function(v) return "Faded opacity:  " .. string.format("%.2f", v) end))
    add(Slider(f, prefix .. "Grace", 4, -118, sw, 0, graceMax, graceStep,
        function() return get("hoverSeconds") end, function(v) set("hoverSeconds", v) end,
        function(v) return "Mouseover reveal:  " .. fmtSecs(v) end))
    add(Slider(f, prefix .. "FadeIn", 4, -152, sw, 0.05, 2, 0.05,
        function() return get("fadeInDuration") end, function(v) set("fadeInDuration", v) end,
        function(v) return "Fade-in speed:  " .. string.format("%.2f", v) .. "s" end))
    add(Slider(f, prefix .. "FadeOut", 4, -186, sw, 0.2, 10, 0.1,
        function() return get("fadeOutDuration") end, function(v) set("fadeOutDuration", v) end,
        function(v) return "Fade-out speed:  " .. string.format("%.1f", v) .. "s" end))

    Label(f, "Keep visible while:", 4, -214, 1, 0.82, 0)
    add(Check(f, prefix .. "Combat", 2, -232, "In combat",
        function() return get("alwaysInCombat") end, function(v) set("alwaysInCombat", v) end))
    add(Check(f, prefix .. "Instance", 2, -253, "In dungeons / raids / BGs",
        function() return get("alwaysInInstance") end, function(v) set("alwaysInInstance", v) end))
    add(Check(f, prefix .. "Group", 2, -274, "In a party or raid",
        function() return get("alwaysInGroup") end, function(v) set("alwaysInGroup", v) end))

    -- dark overlay shown when this block's tier is not the one in use
    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints(f)
    ov:SetFrameLevel(f:GetFrameLevel() + 20)
    ov:EnableMouse(true)
    local ovt = ov:CreateTexture(nil, "OVERLAY")
    ovt:SetAllPoints(ov)
    ovt:SetTexture(0, 0, 0)
    ovt:SetAlpha(0.3)
    block.overlay = ov

    function block.Bind(tbl, active, fallback)
        block.tbl = tbl
        block.fallback = fallback
        block.active = active and true or false
        local i
        for i = 1, table.getn(block.controls) do
            if block.controls[i].Load then block.controls[i].Load() end
        end
        if block.active then ov:Hide() else ov:Show() end
    end
    return block
end

-- ---------------------------------------------------------------------------
-- cascade table helpers (create-on-demand)
-- ---------------------------------------------------------------------------
local function EnsureElementSettings()
    local t = TAB(); if not t then return nil end
    if not t.settings then t.settings = IPFC.CopyFadeSettings(D()) end
    return t.settings
end
local function EnsureBarEntry(cfgkey)
    local t = TAB(); if not t then return nil end
    if not t.bars then t.bars = {} end
    if not t.bars[cfgkey] then t.bars[cfgkey] = { enabled = true } end
    return t.bars[cfgkey]
end
local function EnsureBarSettings(cfgkey)
    local b = EnsureBarEntry(cfgkey); if not b then return nil end
    if not b.settings then
        local t = TAB()
        local base = (t and t.useOwn and t.settings) or D()
        b.settings = IPFC.CopyFadeSettings(base)
    end
    return b.settings
end

local function TCHAT() return ImmersivePfUIFadeControllerDB.targets.chat end
local function EnsureChatSettings()
    local t = TCHAT(); if not t then return nil end
    if not t.settings then t.settings = IPFC.CopyFadeSettings(D()) end
    return t.settings
end
local function EnsureChatWindow(wkey)
    local t = TCHAT(); if not t then return nil end
    if not t.windows then t.windows = {} end
    if not t.windows[wkey] then t.windows[wkey] = { enabled = false } end
    return t.windows[wkey]
end
local function EnsureChatWindowSettings(wkey)
    local w = EnsureChatWindow(wkey); if not w then return nil end
    if not w.settings then
        local t = TCHAT()
        local base = (t and t.useOwn and t.settings) or D()
        w.settings = IPFC.CopyFadeSettings(base)
    end
    return w.settings
end

-- ---------------------------------------------------------------------------
-- panel state
-- ---------------------------------------------------------------------------
local panel, tabButtons, tabContents, currentTab
local globalBlock, elementBlock, barBlock
local ddScope, abScope, captionBar
local abEnableCheck, linkAllCheck, applyGlobalCheck, fadeThisCheck, overrideCheck
-- the chat tab's widgets live in one table: as separate locals they are one
-- upvalue each, and BuildChatTab would sit on Lua 5.0's 32-upvalue ceiling
local chatUI = {}

-- the panel grows for the taller Chat tab
local TAB_HEIGHT = { 520, 520, 660 }

-- chat windows come back on their own when one of these arrives
local CHAT_TRIGGERS = {
    { key = "revealWhisper",     label = "Whispers" },
    { key = "revealGuild",       label = "Guild" },
    { key = "revealOfficer",     label = "Officer" },
    { key = "revealGroup",       label = "Party & raid" },
    { key = "revealRaidWarning", label = "Raid warnings" },
    { key = "revealSay",         label = "Say & yell" },
    { key = "revealChannel",     label = "Channels" },
    { key = "revealLoot",        label = "Loot & money" },
}

local function BarName(cfgkey)
    local i
    for i = 1, table.getn(IPFC.actionBars) do
        if IPFC.actionBars[i].cfgkey == cfgkey then return IPFC.actionBars[i].name end
    end
    return cfgkey
end

local function RefreshElement()
    local t = TAB()
    applyGlobalCheck.Load()
    elementBlock.Bind(t and t.settings or nil, t and t.useOwn and true or false)
end

local function RefreshBar()
    local t = TAB()
    fadeThisCheck.Load()
    overrideCheck.Load()
    local b = t and t.bars and t.bars[abScope]
    local override = b and b.override and true or false
    if IPFC.BarPfUIAutohide(abScope) then
        captionBar:SetText("pfUI autohide controls this bar - left untouched.")
    elseif override then
        captionBar:SetText("Using this bar's own settings.")
    elseif t and t.useOwn then
        captionBar:SetText("Using the All Action Bars settings.")
    else
        captionBar:SetText("Using the Global settings.")
    end
    barBlock.Bind((b and b.settings) or nil, override, (t and t.useOwn and t.settings) or nil)
end

local function ScopeDropdownInit()
    local i
    for i = 1, table.getn(IPFC.actionBars) do
        local bar = IPFC.actionBars[i]
        local info = {}
        info.text = bar.name
        info.checked = (abScope == bar.cfgkey)
        info.func = function() abScope = bar.cfgkey; UIDropDownMenu_SetText(bar.name, ddScope); RefreshBar() end
        UIDropDownMenu_AddButton(info)
    end
end

local function ShowTab(idx)
    currentTab = idx
    panel:SetHeight(TAB_HEIGHT[idx] or 520)
    local i
    for i = 1, table.getn(tabContents) do
        local on = (i == idx)
        if on then tabContents[i]:Show() else tabContents[i]:Hide() end
        local bb = tabButtons[i]
        if bb.textfs then
            if on then bb.textfs:SetTextColor(1, 0.82, 0) else bb.textfs:SetTextColor(0.7, 0.7, 0.7) end
        end
        if bb.backdrop and bb.backdrop.SetBackdropBorderColor then
            if on then bb.backdrop:SetBackdropBorderColor(1, 0.82, 0, 1)
            else bb.backdrop:SetBackdropBorderColor(0.3, 0.3, 0.3, 1) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- tab content
-- ---------------------------------------------------------------------------
local function BuildGeneralTab(c)
    Header(c, "Global Fade Settings", 20, -64)
    globalBlock = SettingsBlock(c, "IPFCG_", 20, -88)

    Label(c, "How fading works", 300, -64, 1, 0.82, 0)
    local info = c:CreateFontString(nil, "OVERLAY")
    SetF(info, FONT_SIZE)
    info:SetTextColor(0.75, 0.75, 0.75)
    info:SetPoint("TOPLEFT", c, "TOPLEFT", 300, -88)
    info:SetWidth(238)
    info:SetJustifyH("LEFT")
    info:SetText("These settings apply to every fadeable element by default.\n\n"
        .. "On the Action Bars and Chat tabs you can give all bars (or all chat windows) "
        .. "their own settings, and then override any single one on top of that.\n\n"
        .. "Elements stay fully visible while your mouse is over them, and while any "
        .. "\"Keep visible\" condition is met.\n\n"
        .. "Chat windows start out unfaded: hover a window and click the small button "
        .. "in its top-right corner to drop it into immersive mode.")
end

local function BuildActionBarsTab(c)
    local div = c:CreateTexture(nil, "ARTWORK")
    div:SetTexture(1, 1, 1, 0.08)
    div:SetWidth(1)
    div:SetHeight(392)
    div:SetPoint("TOP", c, "TOPLEFT", 286, -86)

    linkAllCheck = Check(c, "IPFClink", 20, -58, "Apply to all bars together (reveal them as one)",
        function() local t = TAB(); return t and t.linkAll and true or false end,
        function(v) local t = TAB(); if t then t.linkAll = v end end)

    -- left column: all action bars
    Header(c, "All Action Bars", 20, -86)
    abEnableCheck = Check(c, "IPFCabEnable", 20, -110, "Fade action bars",
        function() return IPFC.TargetEnabled("actionbars") end,
        function(v)
            local t = TAB(); if t then t.enabled = v end
            if v then IPFC.RefreshAll() else IPFC.ResetTarget("actionbars") end
        end)
    applyGlobalCheck = Check(c, "IPFCapplyGlobal", 20, -136, "Apply global fade settings",
        function() local t = TAB(); return not (t and t.useOwn) end,
        function(v)
            local t = TAB()
            if t then
                t.useOwn = not v
                if t.useOwn then EnsureElementSettings() end
            end
            RefreshElement()
            RefreshBar()      -- a non-overriding bar now inherits from a different tier
        end)
    elementBlock = SettingsBlock(c, "IPFCE_", 20, -190)

    -- right column: individual bar
    Header(c, "Individual Bar", 300, -86)
    ddScope = CreateFrame("Frame", "IPFCScopeDD", c, "UIDropDownMenuTemplate")
    ddScope:SetPoint("TOPLEFT", c, "TOPLEFT", 284, -100)
    UIDropDownMenu_Initialize(ddScope, ScopeDropdownInit)
    UIDropDownMenu_SetWidth(150, ddScope)
    if pfUI and pfUI.api and pfUI.api.SkinDropDown then pfUI.api.SkinDropDown(ddScope, nil, nil, nil, true) end

    fadeThisCheck = Check(c, "IPFCfadeThis", 300, -136, "Fade this bar",
        function()
            local t = TAB(); local b = t and t.bars and t.bars[abScope]
            if b and b.enabled ~= nil then return b.enabled end
            return true
        end,
        function(v)
            local b = EnsureBarEntry(abScope); if b then b.enabled = v end
            if not v then IPFC.ResetTarget("actionbars") end
        end)
    overrideCheck = Check(c, "IPFCoverride", 300, -158, "Override fade settings for this bar",
        function()
            local t = TAB(); local b = t and t.bars and t.bars[abScope]
            return b and b.override and true or false
        end,
        function(v)
            local b = EnsureBarEntry(abScope)
            if b then b.override = v; if v then EnsureBarSettings(abScope) end end
            RefreshBar()
        end)
    captionBar = c:CreateFontString(nil, "OVERLAY")
    SetF(captionBar, FONT_SIZE - 1)
    captionBar:SetTextColor(0.7, 0.7, 0.7)
    captionBar:SetPoint("TOPLEFT", c, "TOPLEFT", 300, -180)
    barBlock = SettingsBlock(c, "IPFCB_", 300, -190)
end

-- ---------------------------------------------------------------------------
-- chat tab
-- ---------------------------------------------------------------------------
local function ChatWindowName(wkey)
    local i
    for i = 1, table.getn(IPFC.chatWindows) do
        if IPFC.chatWindows[i].key == wkey then return IPFC.chatWindows[i].name end
    end
    return wkey
end

local function LootQualityName(v)
    local i
    for i = 1, table.getn(IPFC.LOOT_QUALITIES) do
        if IPFC.LOOT_QUALITIES[i].value == v then return IPFC.LOOT_QUALITIES[i].name end
    end
    return IPFC.LOOT_QUALITIES[1].name
end

local function RefreshChatElement()
    local t = TCHAT()
    chatUI.applyGlobal.Load()
    chatUI.elementBlock.Bind(t and t.settings or nil, t and t.useOwn and true or false)
end

local function ChatPanelLabel(wkey)
    local i
    for i = 1, table.getn(IPFC.chatWindows) do
        local w = IPFC.chatWindows[i]
        if w.key == wkey then
            return "Also fade the panel below it (" .. (w.panelLabel or "info panel") .. ")"
        end
    end
    return "Also fade the panel below it"
end

local function RefreshChatWindow()
    local t = TCHAT()
    chatUI.fadeThis.Load()
    chatUI.includePanel.Load()
    chatUI.includePanel.textfs:SetText(ChatPanelLabel(chatUI.scope))
    chatUI.override.Load()
    local w = t and t.windows and t.windows[chatUI.scope]
    local override = w and w.override and true or false
    if override then
        chatUI.caption:SetText("Using this window's own settings.")
    elseif t and t.useOwn then
        chatUI.caption:SetText("Using the All Chat Windows settings.")
    else
        chatUI.caption:SetText("Using the Global settings.")
    end
    chatUI.winBlock.Bind((w and w.settings) or nil, override, (t and t.useOwn and t.settings) or nil)
end

local function ChatScopeDropdownInit()
    local i
    for i = 1, table.getn(IPFC.chatWindows) do
        local win = IPFC.chatWindows[i]
        local info = {}
        info.text = win.name
        info.checked = (chatUI.scope == win.key)
        info.func = function()
            chatUI.scope = win.key
            UIDropDownMenu_SetText(win.name, chatUI.ddWin)
            RefreshChatWindow()
        end
        UIDropDownMenu_AddButton(info)
    end
end

local function LootQualityDropdownInit()
    local t = TCHAT()
    local cur = (t and t.lootQuality) or 0
    local i
    for i = 1, table.getn(IPFC.LOOT_QUALITIES) do
        local q = IPFC.LOOT_QUALITIES[i]
        local info = {}
        info.text = q.name
        info.checked = (cur == q.value)
        info.func = function()
            local tc = TCHAT(); if tc then tc.lootQuality = q.value end
            UIDropDownMenu_SetText(q.name, chatUI.ddLootQ)
        end
        UIDropDownMenu_AddButton(info)
    end
end

local function BuildChatTab(c)
    local div = c:CreateTexture(nil, "ARTWORK")
    div:SetTexture(1, 1, 1, 0.08)
    div:SetWidth(1)
    div:SetHeight(416)
    div:SetPoint("TOP", c, "TOPLEFT", 286, -86)

    -- left column: all chat windows
    Header(c, "All Chat Windows", 20, -86)
    chatUI.enable = Check(c, "IPFCchatEnable", 20, -110, "Fade chat windows",
        function() return IPFC.TargetEnabled("chat") end,
        function(v)
            local t = TCHAT(); if t then t.enabled = v end
            if v then IPFC.RefreshAll() else IPFC.ResetTarget("chat") end
        end)
    chatUI.applyGlobal = Check(c, "IPFCchatApplyGlobal", 20, -136, "Apply global fade settings",
        function() local t = TCHAT(); return not (t and t.useOwn) end,
        function(v)
            local t = TCHAT()
            if t then
                t.useOwn = not v
                if t.useOwn then EnsureChatSettings() end
            end
            RefreshChatElement()
            RefreshChatWindow()
        end)
    chatUI.buttons = Check(c, "IPFCchatButtons", 20, -158, "Show fade toggle buttons on mouseover",
        function() local t = TCHAT(); return t and t.buttons and true or false end,
        function(v) local t = TCHAT(); if t then t.buttons = v end end)
    chatUI.elementBlock = SettingsBlock(c, "IPFCC_", 20, -206, { graceMax = 300, graceStep = 2.5 })

    -- right column: one window
    Header(c, "Individual Window", 300, -86)
    chatUI.ddWin = CreateFrame("Frame", "IPFCChatScopeDD", c, "UIDropDownMenuTemplate")
    chatUI.ddWin:SetPoint("TOPLEFT", c, "TOPLEFT", 284, -100)
    UIDropDownMenu_Initialize(chatUI.ddWin, ChatScopeDropdownInit)
    UIDropDownMenu_SetWidth(150, chatUI.ddWin)
    if pfUI and pfUI.api and pfUI.api.SkinDropDown then pfUI.api.SkinDropDown(chatUI.ddWin, nil, nil, nil, true) end

    chatUI.fadeThis = Check(c, "IPFCchatFadeThis", 300, -132, "Fade this window",
        function() return IPFC.ChatWindowEnabled(chatUI.scope) end,
        function(v) IPFC.SetChatWindowEnabled(chatUI.scope, v) end)
    -- label is re-set per window (each names the panel that sits under it)
    chatUI.includePanel = Check(c, "IPFCchatPanel", 300, -153, "Also fade the panel below it",
        function() return IPFC.ChatPanelIncluded(chatUI.scope) end,
        function(v)
            local w = EnsureChatWindow(chatUI.scope)
            if w then w.includePanel = v end
        end)
    chatUI.override = Check(c, "IPFCchatOverride", 300, -174, "Override fade settings for this window",
        function()
            local t = TCHAT(); local w = t and t.windows and t.windows[chatUI.scope]
            return w and w.override and true or false
        end,
        function(v)
            local w = EnsureChatWindow(chatUI.scope)
            if w then w.override = v; if v then EnsureChatWindowSettings(chatUI.scope) end end
            RefreshChatWindow()
        end)
    chatUI.caption = c:CreateFontString(nil, "OVERLAY")
    SetF(chatUI.caption, FONT_SIZE - 1)
    chatUI.caption:SetTextColor(0.7, 0.7, 0.7)
    chatUI.caption:SetPoint("TOPLEFT", c, "TOPLEFT", 300, -196)
    chatUI.winBlock = SettingsBlock(c, "IPFCW_", 300, -206, { graceMax = 300, graceStep = 2.5 })

    -- full width: reveal-on-message triggers
    Header(c, "Bring a window back when a message arrives", 20, -514)
    chatUI.msgSlider = Slider(c, "IPFCchatMsgSecs", 24, -548, BLOCK_W - 20, 0, 300, 5,
        function() local t = TCHAT(); return (t and t.msgSeconds) or 15 end,
        function(v) local t = TCHAT(); if t then t.msgSeconds = v end end,
        function(v) return "Stay visible for:  " .. fmtDelay(v) end)

    Label(c, "Loot trigger needs at least:", 300, -532)
    chatUI.ddLootQ = CreateFrame("Frame", "IPFCLootQualityDD", c, "UIDropDownMenuTemplate")
    chatUI.ddLootQ:SetPoint("TOPLEFT", c, "TOPLEFT", 284, -546)
    UIDropDownMenu_Initialize(chatUI.ddLootQ, LootQualityDropdownInit)
    UIDropDownMenu_SetWidth(150, chatUI.ddLootQ)
    if pfUI and pfUI.api and pfUI.api.SkinDropDown then pfUI.api.SkinDropDown(chatUI.ddLootQ, nil, nil, nil, true) end

    chatUI.trigChecks = {}
    local i
    for i = 1, table.getn(CHAT_TRIGGERS) do
        local trig = CHAT_TRIGGERS[i]
        local col = math.floor((i - 1) / 2)
        local row = math.mod(i - 1, 2)
        chatUI.trigChecks[i] = Check(c, "IPFCtrig" .. trig.key, 20 + col * 135, -586 - row * 21, trig.label,
            function() local t = TCHAT(); return t and t[trig.key] and true or false end,
            function(v) local t = TCHAT(); if t then t[trig.key] = v end end)
    end
end

-- ---------------------------------------------------------------------------
-- build
-- ---------------------------------------------------------------------------
local function Build()
    panel = CreateFrame("Frame", "ImmersivePfUIFadeOptions", UIParent)
    panel:SetWidth(560)
    panel:SetHeight(520)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function() this:StartMoving() end)
    panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    panel:Hide()

    if pfUI and pfUI.api and pfUI.api.CreateBackdrop then
        pfUI.api.CreateBackdrop(panel)
        if pfUI.api.CreateBackdropShadow then pfUI.api.CreateBackdropShadow(panel) end
        if panel.backdrop then
            local r, g, b = 0.05, 0.05, 0.05
            if pfUI.api.GetStringColor and pfUI_config then
                local cr, cg, cb = pfUI.api.GetStringColor(pfUI_config.appearance.border.background)
                if cr then r, g, b = cr, cg, cb end
            end
            panel.backdrop:SetBackdropColor(r, g, b, 0.9)
        end
    else
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
        panel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    end

    local title = panel:CreateFontString(nil, "OVERLAY")
    SetF(title, FONT_SIZE + 3)
    title:SetPoint("TOP", panel, "TOP", 0, -12)
    title:SetText("|cff33bbffpfUI|r FadeController")

    local close = CreateFrame("Button", "ImmersivePfUIFadeOptionsClose", panel)
    close:SetWidth(16); close:SetHeight(16)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -6)
    if pfUI and pfUI.api and pfUI.api.CreateBackdrop then pfUI.api.CreateBackdrop(close) end
    local cx = close:CreateFontString(nil, "OVERLAY")
    SetF(cx, FONT_SIZE)
    cx:SetPoint("CENTER", close, "CENTER", 0, 0)
    cx:SetTextColor(1, 0.4, 0.4)
    cx:SetText("x")
    close:SetScript("OnClick", function() panel:Hide() end)

    -- vertical divider between the two Action Bars columns
    tabButtons, tabContents = {}, {}
    local names = { "General", "Action Bars", "Chat" }
    local i
    for i = 1, table.getn(names) do
        local content = CreateFrame("Frame", nil, panel)
        content:SetAllPoints(panel)
        content:Hide()
        tabContents[i] = content

        local b = CreateFrame("Button", "IPFCTab" .. i, panel)
        b:SetWidth(110); b:SetHeight(20)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 16 + (i - 1) * 116, -34)
        if pfUI and pfUI.api and pfUI.api.CreateBackdrop then pfUI.api.CreateBackdrop(b) end
        local bt = b:CreateFontString(nil, "OVERLAY")
        SetF(bt, FONT_SIZE)
        bt:SetPoint("CENTER", b, "CENTER", 0, 0)
        bt:SetText(names[i])
        b.textfs = bt
        local idx = i
        b:SetScript("OnClick", function() ShowTab(idx) end)
        tabButtons[i] = b
    end

    BuildGeneralTab(tabContents[1])
    BuildActionBarsTab(tabContents[2])
    BuildChatTab(tabContents[3])

    local foot = panel:CreateFontString(nil, "OVERLAY")
    SetF(foot, FONT_SIZE - 1)
    foot:SetTextColor(0.6, 0.6, 0.6)
    foot:SetPoint("BOTTOM", panel, "BOTTOM", 0, 12)
    foot:SetText("/ipfc  -  v" .. (IPFC.version or "?") .. "   (/ipfc preview to test)")
end

local function LoadAll()
    globalBlock.Bind(D(), true)
    abEnableCheck.Load()
    linkAllCheck.Load()
    if not abScope then abScope = IPFC.actionBars[1].cfgkey end
    UIDropDownMenu_SetText(BarName(abScope), ddScope)
    RefreshElement()
    RefreshBar()

    chatUI.enable.Load()
    chatUI.buttons.Load()
    chatUI.msgSlider.Load()
    local t = TCHAT()
    UIDropDownMenu_SetText(LootQualityName((t and t.lootQuality) or 0), chatUI.ddLootQ)
    local i
    for i = 1, table.getn(chatUI.trigChecks) do chatUI.trigChecks[i].Load() end
    if not chatUI.scope then chatUI.scope = IPFC.chatWindows[1].key end
    UIDropDownMenu_SetText(ChatWindowName(chatUI.scope), chatUI.ddWin)
    RefreshChatElement()
    RefreshChatWindow()
end

function IPFC.ToggleOptions()
    if not panel then Build(); ShowTab(2) end
    if panel:IsShown() then
        panel:Hide()
    else
        LoadAll()
        panel:Show()
    end
end
