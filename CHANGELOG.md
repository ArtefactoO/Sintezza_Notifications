# Changelog

## 0.1.1

- Hide the duplicate Blizzard achievement toast while Sintezza achievement notifications are active.
- Use the shared solid preview background and thin border for all notification and signal samples.

## 0.1.0

First public release for WoW Forever 1.60.1.

- Shift the quest progress fill from amber through gold to the selected accent and back it with a dark rail for readability in bright areas.
- Use a transparent background for the in-game bell icon so it matches the other Sintezza shortcuts.
- Fit the full Move and Reset labels in the compact position row and match the button heights.
- Put short X and Y sliders and placement buttons on one row, and let players drag the alert itself.
- Place settings on the left and move the preview to the right on notification and signal pages.
- Route new area discoveries through zone notifications, including exploration XP when the client supplies it.
- Show XP and money on quest turn-in and pulse the accent when a quest objective is completed.
- Keep the quest title and detail sizes independent in compact progress and keep the preview scale stable while editing them.
- Give each notification page its own enable switch and remove the world notification master switch.
- Group settings by notification type, with separate colors, opacity, and animation settings for each group.
- Give quest and zone notifications independent fonts, sizes, positions and playback.
- Move the onboard arrival countdown from Sintezza UI and import its saved position and enabled state.
- Improve default notification contrast with light text and a dark backing that stays solid behind wide quest counters.
- Add animated notifications for quests, world quests, areas, achievements, boss emotes, rare deaths, and scenarios.
- Add live-data preview, drag placement, position sliders, and separate title and detail font controls.
- Add a Sintezza Theme settings window, themed placement controls, and a minimap button with original artwork.
- Port combat, stealth, health, and aggro signals with a shared active profile during the Sintezza UI transition.
- Inherit the Theme fonts by default and offer the active combat font as a title or detail override.
- Use X and Y positions and add notification colors, overall opacity, and independent background opacity.
- Separate world notifications from player signals and add an opt-in low-mana signal with configurable thresholds and an instance-only option for both mana and health.
- Detect initial mana loss below the alert threshold and add an outlined mana icon matching the health signal.
- Use a grouped settings sidebar and a static appearance sample with separate in-game animation playback.
- Take ownership of player signals from compatible Sintezza UI builds and import the active alert profile on the first handoff.
- Announce the handoff in chat once at login or reload when both profiles enable a shared signal.
- Recheck mana after casts and repeat the warning only after a readable refill and another drop.
- Post the shared-signal handoff message from Sintezza UI after the player enters the world.
- Hide the duplicate yellow quest progress text and use a compact quest progress layout by default.
- Detect zone changes from the same title WoW displays, prioritize them over quest progress, and hide the duplicate Blizzard zone text when the custom notification is available.
