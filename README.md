# pfUI FadeController

**Fade your pfUI interface out of the way when nothing is happening — vanilla WoW 1.12.**

A small fade-orchestration layer for [pfUI](https://github.com/shagu/pfUI). Elements ("targets") register their frames with one shared engine, which fades them to a set opacity after a while out of combat and brings them back on mouseover.

- **Per-element control** — each pfUI element can be faded independently.
- **Per-bar control** — every action bar keeps its own timers and alpha, so mousing over one bar reveals only that bar (or link them so they reveal together).
- **Chat windows** — both pfUI chat containers (General, and the optional Loot & Spam) fade on their own, each with a small toggle button in its top-right corner for switching immersive mode on and off mid-game.
- **Three-tier settings** — global defaults, per-element settings, and per-bar / per-window overrides.
- **Active and faded opacity** — set both ends of the fade, not just the faded one.
- **Keep-visible rules** — never fade in combat, in dungeons/raids/battlegrounds, or while grouped.
- **Hands off pfUI's own autohide** — bars that pfUI already autohides are left alone.

## Chat windows

Chat starts out unfaded. Hover a chat window and click the small button in its top-right corner to drop that window into immersive mode; click again to pin it back. Right-click the button to open the options panel.

The window's chat tabs (General, Combat Log, LFG …) fade with it, and each window can optionally take the pfUI info panel underneath it along — exp/armour/friends under the left one, fps/latency/clock/gold under the right one.

A faded chat window comes back on mouseover, while you are typing, and whenever a message you care about arrives — whispers, guild and officer chat are on by default, with party/raid, raid warnings, say/yell, channels and loot available on the Chat tab. The loot trigger has an item-quality threshold, so an epic drop pulls the Loot & Spam window back while vendor trash does not.

Requires pfUI.

## Install

Put the `ImmersivePfUIFadeController` folder into your `Interface\AddOns\` folder (so that
`Interface\AddOns\ImmersivePfUIFadeController\ImmersivePfUIFadeController.toc` exists), then restart the game.

## Using it

- Type **`/ipfc`** (or `/ifade`) to open the options panel.
- `/ipfc preview` previews the faded state so you can dial in the opacity.
- Slash tuning: `delay <s>`, `opacity <0-1>`, `active <0-1>`, `grace <s>`, `fadein <s>`, `fadeout <s>`, `combat|instance|group on|off`, `chat on|off`.

## Part of a series

Minimalist, immersive addons for vanilla WoW 1.12:
[Immersive Decursive](https://github.com/max-bruhn/ImmersiveDecursive) ·
[Immersive PallyPower](https://github.com/max-bruhn/ImmersivePallyPower) ·
[Immersive Button Tray](https://github.com/max-bruhn/ImmersiveButtonTray)
