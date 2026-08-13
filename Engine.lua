--[[
 pfUI FadeController - fade engine

 One OnUpdate driver ticks every registered target. A simple target uses the
 default per-target behaviour below; a target may instead supply its own
 def.tick (the action bars do, for independent per-bar fading).

 Timer model (per fading unit - a whole target, or a single bar):
   - idleStart : anchored when the unit last left an "always-on" state (combat /
                 instance / group) or at login. It fades once
                 now - idleStart >= oocDelay. Mouseover does NOT move this
                 anchor - the long OOC timer keeps running underneath.
   - hoverUntil: mouseover sets this to now + hoverSeconds. While now < hoverUntil
                 the unit is revealed at full alpha - a short, separate grace.
   - always-on : combat / instance / group pin full alpha and keep idleStart at
                 now, so the OOC countdown restarts when the condition ends.

 Alpha eases toward its goal with separate fade-in (fast) and fade-out (slow)
 speeds.
--]]

IPFC = IPFC or {}

-- shared world conditions, evaluated once per tick
local function WorldConds()
    local inCombat = UnitAffectingCombat("player") and true or false

    local inInstance = false
    if IsInInstance then
        local isin, itype = IsInInstance()
        if isin and itype and itype ~= "none" then inInstance = true end
    end

    local inGroup = (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0)
    return inCombat, inInstance, inGroup
end

-- ease `cur` toward `target`; brightening uses fadeInDuration, dimming uses
-- fadeOutDuration
function IPFC.StepAlpha(cur, target, dt, cfg)
    if cur == target then return cur end
    local dur
    if target > cur then dur = cfg.fadeInDuration else dur = cfg.fadeOutDuration end
    if not dur or dur < 0.01 then dur = 0.01 end
    local step = dt / dur
    if target > cur then
        cur = cur + step
        if cur > target then cur = target end
    else
        cur = cur - step
        if cur < target then cur = target end
    end
    return cur
end

-- default behaviour: one alpha shared across a target's frames, mouseover any
-- frame reveals the whole target. Suits single-frame elements (minimap, chat...).
local function DefaultTick(key, st, ctx)
    local frames = st.frames
    if not frames or table.getn(frames) == 0 then return end
    local cfg = IPFC.CachedTargetConfig(key)
    local now = ctx.now

    local target
    if (cfg.alwaysInCombat and ctx.inCombat)
        or (cfg.alwaysInInstance and ctx.inInstance)
        or (cfg.alwaysInGroup and ctx.inGroup) then
        st.idleStart = now
        target = 1
    else
        local hover = false
        local i
        for i = 1, table.getn(frames) do
            local f = frames[i]
            if f and f.IsShown and f:IsShown() and MouseIsOver(f, 8, -8, -8, 8) then hover = true; break end
        end
        if hover then st.hoverUntil = now + cfg.hoverSeconds end
        if now < (st.hoverUntil or 0) then
            target = 1
        elseif (now - (st.idleStart or now)) >= cfg.oocDelay then
            target = cfg.fadeAlpha
        else
            target = 1
        end
    end

    local cur = st.alpha or 1
    if cur ~= target then
        cur = IPFC.StepAlpha(cur, target, ctx.dt, cfg)
        st.alpha = cur
        local i
        for i = 1, table.getn(frames) do
            local f = frames[i]
            if f and f.SetAlpha then f:SetAlpha(cur) end
        end
    end
end

-- reused every tick so the OnUpdate path allocates nothing
local ctx = {}

local function Tick()
    local dt = arg1
    if not dt then dt = 0.03 end
    if not ImmersivePfUIFadeControllerDB then return end

    local now = GetTime()
    IPFC.EnsureConfigCache(now)
    local inCombat, inInstance, inGroup = WorldConds()
    ctx.dt = dt; ctx.now = now
    ctx.inCombat = inCombat; ctx.inInstance = inInstance; ctx.inGroup = inGroup

    local key
    for key in pairs(IPFC.registry) do
        local def = IPFC.registry[key]
        local st = IPFC.state[key]
        if def and st and IPFC.TargetEnabled(key) then
            if def.tick then def.tick(key, st, ctx) else DefaultTick(key, st, ctx) end
        end
    end
end

-- restore a target to full opacity (used when it is disabled)
function IPFC.ResetTarget(key)
    local def = IPFC.registry[key]
    local st = IPFC.state[key]
    if not def or not st then return end
    if def.reset then def.reset(st); return end
    st.alpha = 1
    if st.frames then
        local i
        for i = 1, table.getn(st.frames) do
            if st.frames[i] and st.frames[i].SetAlpha then st.frames[i]:SetAlpha(1) end
        end
    end
end

function IPFC.StartEngine()
    if IPFC.driver then return end
    IPFC.driver = CreateFrame("Frame", "ImmersivePfUIFadeDriver", UIParent)
    IPFC.driver:SetScript("OnUpdate", Tick)
end
