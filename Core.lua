--[[
 ImmersivePfUI FadeController - core
 A small fade-orchestration layer for pfUI. Elements ("targets") register a set
 of frames plus optional rule overrides; one shared engine (Engine.lua) fades
 them all. Ships with the action bars target (Targets.lua); more can be added
 later as ~10-line target definitions.

 Config model: one set of global default rules, with optional per-target
 overrides. Each target can be toggled on/off independently.
--]]

IPFC = IPFC or {}
IPFC.version = "0.2.0"

-- global default fade rules (per-target overrides live in db.targets[key].overrides)
local DEFAULTS = {
    oocDelay      = 120,   -- seconds out of combat before a target fades
    activeAlpha   = 1.0,   -- opacity a revealed target sits at (1 = fully opaque)
    fadeAlpha     = 0.15,  -- opacity a faded target settles at (0 = invisible, 1 = full)
    hoverSeconds  = 2.5,   -- how long a target stays revealed after the mouse leaves it
    fadeInDuration  = 0.2, -- seconds to fade a target back in (fast)
    fadeOutDuration = 3.0, -- seconds to fade a target out (slow)
    alwaysInCombat   = true, -- never fade while in combat
    alwaysInInstance = true, -- never fade in dungeons / raids / battlegrounds / arenas
    alwaysInGroup    = false,-- never fade while in any party or raid
}

IPFC.registry = IPFC.registry or {}  -- key -> target definition
IPFC.state    = IPFC.state or {}     -- key -> runtime state { alpha, frames, idleStart, hoverUntil }

function IPFC.Msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffpfUI|r Fade " .. tostring(text))
end

-- ---------------------------------------------------------------------------
-- saved variables
-- ---------------------------------------------------------------------------
-- the fade-rule keys that make up one "settings" set (global, per-element or per-bar)
IPFC.FADE_KEYS = {
    "oocDelay", "activeAlpha", "fadeAlpha", "hoverSeconds", "fadeInDuration", "fadeOutDuration",
    "alwaysInCombat", "alwaysInInstance", "alwaysInGroup",
}

-- flat copy of a fade-settings set, filling any gaps from the global defaults
function IPFC.CopyFadeSettings(src)
    local db = ImmersivePfUIFadeControllerDB
    local out = {}
    local i
    for i = 1, table.getn(IPFC.FADE_KEYS) do
        local k = IPFC.FADE_KEYS[i]
        if src and src[k] ~= nil then out[k] = src[k] else out[k] = db.defaults[k] end
    end
    return out
end

function IPFC.InitDB()
    if not ImmersivePfUIFadeControllerDB then ImmersivePfUIFadeControllerDB = {} end
    local db = ImmersivePfUIFadeControllerDB
    if not db.defaults then db.defaults = {} end
    for k, v in pairs(DEFAULTS) do
        if db.defaults[k] == nil then db.defaults[k] = v end
    end
    if not db.targets then db.targets = {} end
    -- migrate older per-bar entries (bars[key] used to be a plain on/off boolean)
    local t = db.targets.actionbars
    if t and t.bars then
        local key, val
        for key, val in pairs(t.bars) do
            if type(val) ~= "table" then t.bars[key] = { enabled = val and true or false } end
        end
    end
end

-- merged (defaults + this target's overrides) rule set - used by simple targets.
-- The Into variants fill a caller-owned table so per-frame code can reuse one.
function IPFC.EffectiveConfigInto(eff, key)
    local db = ImmersivePfUIFadeControllerDB
    for k, v in pairs(db.defaults) do eff[k] = v end
    local t = db.targets[key]
    if t and t.overrides then
        for k, v in pairs(t.overrides) do eff[k] = v end
    end
    return eff
end

function IPFC.EffectiveConfig(key)
    return IPFC.EffectiveConfigInto({}, key)
end

-- 3-tier cascade for one sub-unit of a target (an action bar, a chat window):
--   global defaults  ->  (element settings, if "use own settings")  ->
--   (per-unit settings, if that unit's "override" is on)
-- listfield is the target's sub-unit table ("bars", "windows").
function IPFC.SubConfigInto(eff, tkey, listfield, subkey)
    local db = ImmersivePfUIFadeControllerDB
    for k, v in pairs(db.defaults) do eff[k] = v end
    local t = db.targets[tkey]
    if t then
        if t.useOwn and t.settings then
            for k, v in pairs(t.settings) do eff[k] = v end
        end
        local list = t[listfield]
        local s = list and list[subkey]
        if s and s.override and s.settings then
            for k, v in pairs(s.settings) do eff[k] = v end
        end
    end
    return eff
end

function IPFC.ActionBarConfigInto(eff, cfgkey)
    return IPFC.SubConfigInto(eff, "actionbars", "bars", cfgkey)
end

function IPFC.ActionBarConfig(cfgkey)
    return IPFC.ActionBarConfigInto({}, cfgkey)
end

-- ---------------------------------------------------------------------------
-- per-frame config cache
-- ---------------------------------------------------------------------------
-- The OnUpdate ticks read configs every frame for every target/bar. Building
-- those tables fresh each time churned ~700 tables/sec through the Lua 5.0
-- stop-the-world GC (visible stutter). Instead the tick path reads from these
-- cached tables, which are reused and re-filled at most every CACHE_TTL
-- seconds - so steady-state frames allocate nothing.
local CACHE_TTL = 0.5
local targetCache = {}
local subCache = {}    -- "targetkey/subkey" -> cascaded config
local cacheTime = -1

-- force a refresh on the next tick (settings just changed)
function IPFC.InvalidateConfigCache()
    cacheTime = -1
end

function IPFC.EnsureConfigCache(now)
    if cacheTime >= 0 and (now - cacheTime) < CACHE_TTL then return end
    cacheTime = now
    for key, def in pairs(IPFC.registry) do
        local t = targetCache[key]
        if not t then t = {}; targetCache[key] = t end
        IPFC.EffectiveConfigInto(t, key)
        -- targets with sub-units (bars, chat windows) cache one config each
        if def.sublist and def.listfield then
            local subs = def.sublist()
            local i
            for i = 1, table.getn(subs) do
                local ck = key .. "/" .. subs[i]
                local c = subCache[ck]
                if not c then c = {}; subCache[ck] = c end
                IPFC.SubConfigInto(c, key, def.listfield, subs[i])
            end
        end
    end
end

function IPFC.CachedTargetConfig(key)
    return targetCache[key] or IPFC.EffectiveConfig(key)
end

function IPFC.CachedSubConfig(tkey, listfield, subkey)
    return subCache[tkey .. "/" .. subkey]
        or IPFC.SubConfigInto({}, tkey, listfield, subkey)
end

function IPFC.CachedBarConfig(cfgkey)
    return IPFC.CachedSubConfig("actionbars", "bars", cfgkey)
end

function IPFC.TargetEnabled(key)
    local db = ImmersivePfUIFadeControllerDB
    local t = db.targets[key]
    if not t then return true end
    if t.enabled == nil then return true end
    return t.enabled and true or false
end

-- ---------------------------------------------------------------------------
-- target registry
-- ---------------------------------------------------------------------------
-- def = {
--   label   = "Action Bars",
--   resolve = function() return { frame1, frame2, ... } end,   -- current frames
--   onEnable = function(frames) ... end,                       -- optional (e.g. stop pfUI autohide)
--   defaultEnabled = true|false,                               -- optional (default true)
--   listfield = "bars"|"windows",                              -- optional: sub-unit table name
--   sublist  = function() return { subkey, ... } end,           -- optional: sub-units to cache
--   initdb   = function(saved) ... end,                        -- optional: fill target-wide saved keys
-- }
function IPFC.RegisterTarget(key, def)
    def.key = key
    IPFC.registry[key] = def
    IPFC.state[key] = IPFC.state[key] or { alpha = 1 }
end

-- ensure a saved entry exists for every registered target
function IPFC.SyncTargets()
    local db = ImmersivePfUIFadeControllerDB
    for key, def in pairs(IPFC.registry) do
        if not db.targets[key] then
            db.targets[key] = { enabled = (def.defaultEnabled ~= false), overrides = {} }
        end
        -- runs on every login so new target-wide keys get filled on upgrade
        if def.initdb then def.initdb(db.targets[key]) end
    end
end

-- (re)resolve a target's frames and (re)assert its takeover
function IPFC.RefreshTarget(key)
    local def = IPFC.registry[key]
    local st = IPFC.state[key]
    if not def or not st then return end
    st.frames = def.resolve() or {}
    st.idleStart = GetTime()
    st.hoverUntil = 0
    if def.onEnable then def.onEnable(st.frames) end
end

function IPFC.RefreshAll()
    for key in pairs(IPFC.registry) do IPFC.RefreshTarget(key) end
end

-- ---------------------------------------------------------------------------
-- slash tuning (a full options panel comes once the fade feel is dialled in)
-- ---------------------------------------------------------------------------
local function OnOff(v) if v then return "|cff44ff44on|r" else return "|cffff4444off|r" end end

local function PrintStatus()
    local d = ImmersivePfUIFadeControllerDB.defaults
    IPFC.Msg("|cffffd100FadeController|r settings:")
    IPFC.Msg(string.format("  delay %ds   opacity %.2f (active %.2f)   grace %.1fs",
        d.oocDelay, d.fadeAlpha, d.activeAlpha, d.hoverSeconds))
    IPFC.Msg(string.format("  fade-in %.2fs   fade-out %.2fs", d.fadeInDuration, d.fadeOutDuration))
    IPFC.Msg("  always-on:  combat " .. OnOff(d.alwaysInCombat)
        .. "  instance " .. OnOff(d.alwaysInInstance)
        .. "  group " .. OnOff(d.alwaysInGroup))
    IPFC.Msg("Commands: delay <s>, opacity <0-1>, active <0-1>, grace <s>, fadein <s>, fadeout <s>, combat/instance/group on|off, chat on|off, preview, on|off")
end

function IPFC.Slash(msg)
    msg = string.lower(msg or "")
    local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.*)$")
    local db = ImmersivePfUIFadeControllerDB
    if not db then IPFC.InitDB(); db = ImmersivePfUIFadeControllerDB end
    local d = db.defaults
    local n = tonumber(rest)

    if cmd == "delay" and n then
        d.oocDelay = n; IPFC.Msg("OOC fade delay = " .. n .. "s")
    elseif (cmd == "opacity" or cmd == "alpha") and n then
        if n > 1 then n = n / 100 end
        if n < 0 then n = 0 elseif n > 1 then n = 1 end
        d.fadeAlpha = n; IPFC.Msg("Faded opacity = " .. n)
    elseif (cmd == "active" or cmd == "activeopacity") and n then
        if n > 1 then n = n / 100 end
        if n < 0 then n = 0 elseif n > 1 then n = 1 end
        d.activeAlpha = n; IPFC.Msg("Active opacity = " .. n)
    elseif cmd == "grace" and n then
        d.hoverSeconds = n; IPFC.Msg("Mouseover grace = " .. n .. "s")
    elseif cmd == "fadein" and n then
        d.fadeInDuration = n; IPFC.Msg("Fade-in speed = " .. n .. "s")
    elseif cmd == "fadeout" and n then
        d.fadeOutDuration = n; IPFC.Msg("Fade-out speed = " .. n .. "s")
    elseif cmd == "combat" then
        d.alwaysInCombat = (rest == "on"); IPFC.Msg("Always-on in combat: " .. OnOff(d.alwaysInCombat))
    elseif cmd == "instance" then
        d.alwaysInInstance = (rest == "on"); IPFC.Msg("Always-on in instances: " .. OnOff(d.alwaysInInstance))
    elseif cmd == "group" then
        d.alwaysInGroup = (rest == "on"); IPFC.Msg("Always-on in groups: " .. OnOff(d.alwaysInGroup))
    elseif cmd == "chatinfo" then
        if IPFC.ChatDebug then IPFC.ChatDebug() end
    elseif cmd == "chat" then
        local want = (rest == "on")
        if IPFC.SetChatFading then
            IPFC.SetChatFading(want)
            IPFC.Msg("Chat window fading: " .. OnOff(want))
        end
    elseif cmd == "on" then
        if db.targets.actionbars then db.targets.actionbars.enabled = true end
        IPFC.RefreshAll(); IPFC.Msg("Action bar fading enabled.")
    elseif cmd == "off" then
        if db.targets.actionbars then db.targets.actionbars.enabled = false end
        if IPFC.ResetTarget then IPFC.ResetTarget("actionbars") end
        IPFC.Msg("Action bar fading disabled.")
    elseif cmd == "preview" then
        local key; for key in pairs(IPFC.registry) do
            local st = IPFC.state[key]
            if st then
                st.idleStart = GetTime() - 100000; st.hoverUntil = 0
                if st.frames then
                    local i; for i = 1, table.getn(st.frames) do
                        local e = st.frames[i]
                        if type(e) == "table" and e.idleStart ~= nil then
                            e.idleStart = GetTime() - 100000; e.hoverUntil = 0
                        end
                    end
                end
            end
        end
        IPFC.Msg("Previewing the faded state (mouse away from the bars).")
    elseif cmd == "help" or cmd == "status" or cmd == "cli" then
        PrintStatus()
    elseif cmd == "" or cmd == nil then
        if IPFC.ToggleOptions then IPFC.ToggleOptions() else PrintStatus() end
    else
        PrintStatus()
    end
    IPFC.InvalidateConfigCache()
end

SLASH_IPFC1 = "/ipfc"
SLASH_IPFC2 = "/ifade"
SlashCmdList["IPFC"] = function(msg) IPFC.Slash(msg) end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        IPFC.InitDB()
        IPFC.SyncTargets()
        IPFC.RefreshAll()
        if IPFC.StartEngine then IPFC.StartEngine() end
        IPFC.Msg("loaded. Type |cffffd100/ipfc|r to tune the fade.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- pfUI may rebuild its bars on zone/reload; re-resolve and re-assert
        if ImmersivePfUIFadeControllerDB then IPFC.RefreshAll() end
    end
end)
