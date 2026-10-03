---
title: Tips
description: Mouse, trackpad, and workspace tricks that make OmniWM faster to drive.
sidebar:
  order: 6
---

## Name your workspaces

Create named workspaces in Settings to organize by project or context — emojis work too 🥳.

## Tame problem apps with rules

Use [App Rules](/features/app-rules/) to exclude problematic apps from tiling or assign them to specific workspaces.

## Swap windows by dragging

Hold the configured mouse-move modifier and drag a tiled window onto another to swap them. The drag swaps whole tiles, so a tab group moves with all of its members, the drop target is outlined while you hover it, releasing anywhere else changes nothing, and `Shift` has no effect. The modifier defaults to `Option` and can be changed or disabled in **Settings → Mouse & Trackpad**. In [Overview](/features/overview/), dragging a thumbnail needs no modifier and moves it to another workspace.

## Resize with a right-drag

Hold the configured right-mouse resize modifier (`Option` by default) and right-drag a tiled window to resize it in Dwindle.

## Trackpad gestures

All four gesture assignments appear together in **Trackpad Gestures**. You can select fingers while a gesture is off. If an assignment conflicts, **Set Up…** shows exactly which gestures would turn off and lets you choose before applying.

## Move and resize with the trackpad (opt-in)

Enable **Move windows** or **Resize windows** in **Settings → Mouse & Trackpad → Trackpad Gestures** to drag without clicking. The gesture targets the tiled window under the cursor in Dwindle; lift all fingers to finish. Move swaps with the window under the drop position and stays on the starting monitor. Resize adjusts the nearest movable edges. The pointer itself stays in place.

Choose two, three, or four fingers for each action. Defaults are four fingers to move and three to resize, with both actions disabled. A window gesture needs a finger count unused by other enabled OmniWM gestures, including workspace switching and Overview. **Set Up…** previews which conflicting gestures would turn off and lets you choose before applying the assignment. You can also reassign or disable those gestures yourself. At **1.0x** sensitivity, a full trackpad sweep travels across the starting screen.

Turn off matching macOS gestures in **System Settings → Trackpad → More Gestures** to prevent Mission Control, App Exposé, or full-screen app switching from firing alongside window gestures.

## Workspace swipe (opt-in)


:::caution[Mission Control can intercept vertical swipes]
For vertical swipes with three or four fingers, first turn off Mission Control in System Settings → Trackpad → More Gestures so macOS does not intercept the gesture.
:::
