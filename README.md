# pfUI FadeController

**Fade your pfUI interface out of the way when nothing is happening — vanilla WoW 1.12.**

A small fade-orchestration layer for [pfUI](https://github.com/shagu/pfUI). Elements ("targets") register their frames with one shared engine, which fades them to a set opacity after a while out of combat and brings them back on mouseover.

- **Per-element control** — each pfUI element can be faded independently.
- **Per-bar control** — every action bar keeps its own timers and alpha, so mousing over one bar reveals only that bar (or link them so they reveal together).
- **Three-tier settings** — global defaults, per-element settings, and per-bar overrides.
- **Keep-visible rules** — never fade in combat, in dungeons/raids/battlegrounds, or while grouped.
- **Hands off pfUI's own autohide** — bars that pfUI already autohides are left alone.

Requires pfUI.

## Install

Put the `ImmersivePfUIFadeController` folder into your `Interface\AddOns\` folder (so that
`Interface\AddOns\ImmersivePfUIFadeController\ImmersivePfUIFadeController.toc` exists), then restart the game.

## Using it

- Type **`/ipfc`** (or `/ifade`) to open the options panel.
- `/ipfc preview` previews the faded state so you can dial in the opacity.
- Slash tuning: `delay <s>`, `opacity <0-1>`, `grace <s>`, `fadein <s>`, `fadeout <s>`, `combat|instance|group on|off`.

## Part of a series

Minimalist, immersive addons for vanilla WoW 1.12:
[Immersive Decursive](https://github.com/max-bruhn/ImmersiveDecursive) ·
[Immersive PallyPower](https://github.com/max-bruhn/ImmersivePallyPower) ·
[Immersive Button Tray](https://github.com/max-bruhn/ImmersiveButtonTray)
