--[[
 pfUI FadeController - target definitions

 The action bars are handled per-bar: each pfUI bar keeps its own timers and
 alpha, so mousing over one bar reveals only that bar. Bars that have pfUI's own
 autohide switched on are left entirely to pfUI (its behaviour takes priority and
 our faded opacity does not apply to them).

 The "Apply to all action bars" option (db.targets.actionbars.linkAll) links the
 bars so a mouseover on any one reveals them all together.

 Future single-frame elements (minimap, chat, ...) can just register with a
 resolve() and use the engine's default tick - no custom logic needed.
--]]

IPFC = IPFC or {}

-- every action bar pfUI lists in its own config menu, in pfUI's order and with
-- pfUI's labels (pfUI gui.lua). cfgkey indexes pfUI_config.bars[cfgkey]; index
-- indexes pfUI.bars.
IPFC.actionBars = {
    { cfgkey = "bar1",  index = 1,  name = "Main Actionbar" },
    { cfgkey = "bar6",  index = 6,  name = "Top Actionbar" },
    { cfgkey = "bar5",  index = 5,  name = "Left Actionbar" },
    { cfgkey = "bar3",  index = 3,  name = "Right Actionbar" },
    { cfgkey = "bar4",  index = 4,  name = "Vertical Actionbar" },
    { cfgkey = "bar2",  index = 2,  name = "Paging Actionbar" },
    { cfgkey = "bar7",  index = 7,  name = "Stance Bar 1" },
    { cfgkey = "bar8",  index = 8,  name = "Stance Bar 2" },
    { cfgkey = "bar9",  index = 9,  name = "Stance Bar 3" },
    { cfgkey = "bar10", index = 10, name = "Stance Bar 4" },
    { cfgkey = "bar11", index = 11, name = "Shapeshift Bar" },
    { cfgkey = "bar12", index = 12, name = "Pet Actionbar" },
}

-- true when pfUI's own autohide owns this bar (we then leave it entirely alone)
function IPFC.BarPfUIAutohide(cfgkey)
    return pfUI_config and pfUI_config.bars and pfUI_config.bars[cfgkey]
        and pfUI_config.bars[cfgkey].autohide == "1" and true or false
end

-- false only when pfUI has explicitly disabled the bar
function IPFC.BarPfUIEnabled(cfgkey)
    if not (pfUI_config and pfUI_config.bars and pfUI_config.bars[cfgkey]) then return true end
    return pfUI_config.bars[cfgkey].enable ~= "0"
end

-- our own per-bar toggle ("Fade this bar"); defaults to on
function IPFC.BarEnabled(tcfg, cfgkey)
    if not tcfg or not tcfg.bars then return true end
    local b = tcfg.bars[cfgkey]
    if not b then return true end
    if b.enabled == nil then return true end
    return b.enabled and true or false
end

local function ResolveBars()
    local list = {}
    if not (pfUI and pfUI.bars) then return list end
    local i
    for i = 1, table.getn(IPFC.actionBars) do
        local def = IPFC.actionBars[i]
        local f = pfUI.bars[def.index]
        if f and f.SetAlpha then
            tinsert(list, {
                frame = f, cfgkey = def.cfgkey, name = def.name, index = def.index,
                alpha = 1, idleStart = GetTime(), hoverUntil = 0,
            })
        end
    end
    return list
end

local function MouseOverBar(e)
    return e.frame and e.frame.IsShown and e.frame:IsShown()
        and MouseIsOver(e.frame, 8, -8, -8, 8) and true or false
end

-- a managed bar: exists, our toggle on, and pfUI autohide NOT claiming it
local function Managed(tcfg, e)
    if IPFC.BarPfUIAutohide(e.cfgkey) then return false end
    if not IPFC.BarEnabled(tcfg, e.cfgkey) then return false end
    return true
end

local function ActionBarsTick(key, st, ctx)
    local bars = st.frames
    if not bars or table.getn(bars) == 0 then return end
    local tcfg = ImmersivePfUIFadeControllerDB.targets[key]
    local linkAll = tcfg and tcfg.linkAll and true or false
    local now = ctx.now

    -- when linked, a mouseover on any managed bar reveals them all
    local groupHover = false
    if linkAll then
        local i
        for i = 1, table.getn(bars) do
            local e = bars[i]
            if Managed(tcfg, e) and MouseOverBar(e) then groupHover = true; break end
        end
    end

    local i
    for i = 1, table.getn(bars) do
        local e = bars[i]
        if not Managed(tcfg, e) then
            -- pfUI autohide bar, or a bar we've been told to leave alone:
            -- make sure our toggle-off bars sit at full alpha, then hands off
            if not IPFC.BarPfUIAutohide(e.cfgkey) and e.alpha ~= 1 then
                e.alpha = 1
                if e.frame.SetAlpha then e.frame:SetAlpha(1) end
            end
        else
            -- each bar resolves its own cascaded settings (global / element / per-bar)
            local cfg = IPFC.CachedBarConfig(e.cfgkey)
            local always = (cfg.alwaysInCombat and ctx.inCombat)
                or (cfg.alwaysInInstance and ctx.inInstance)
                or (cfg.alwaysInGroup and ctx.inGroup)
            local target
            if always then
                e.idleStart = now
                target = 1
            else
                local hover
                if linkAll then hover = groupHover else hover = MouseOverBar(e) end
                if hover then e.hoverUntil = now + cfg.hoverSeconds end
                if now < (e.hoverUntil or 0) then
                    target = 1
                elseif (now - (e.idleStart or now)) >= cfg.oocDelay then
                    target = cfg.fadeAlpha
                else
                    target = 1
                end
            end
            local cur = e.alpha or 1
            if cur ~= target then
                cur = IPFC.StepAlpha(cur, target, ctx.dt, cfg)
                e.alpha = cur
                if e.frame.SetAlpha then e.frame:SetAlpha(cur) end
            end
        end
    end
end

local function ActionBarsReset(st)
    if not st.frames then return end
    local i
    for i = 1, table.getn(st.frames) do
        local e = st.frames[i]
        if not IPFC.BarPfUIAutohide(e.cfgkey) then
            e.alpha = 1
            if e.frame and e.frame.SetAlpha then e.frame:SetAlpha(1) end
        end
    end
end

IPFC.RegisterTarget("actionbars", {
    label = "Action Bars",
    resolve = ResolveBars,
    tick = ActionBarsTick,
    reset = ActionBarsReset,
    defaultEnabled = true,
})
