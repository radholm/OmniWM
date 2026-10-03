---
title: Keyboard Shortcuts
description: Every default OmniWM hotkey, the layout legend, Hyper setup, and shortcut conflict troubleshooting.
sidebar:
  order: 5
---

## Customization and the Hyper modifier

All global shortcuts are customizable in **Settings > Hotkeys**. `Hyper` is the literal `Control + Option + Shift + Command` chord by default; which modifiers make up `Hyper` is configurable in Settings > Hotkeys (for example, exclude `Shift` to keep `Hyper + Shift + …` free for extra bindings). Changing the combination retargets every shortcut that currently resolves to `Hyper` onto the new one, so the shortcut list updates in place as you toggle the modifiers.

Optionally pick a **System Hyper Trigger** — a single key (Caps Lock, F13–F20, or a left- or right-side modifier) or an extra mouse button that acts as `Hyper` while held (this needs the Input Monitoring permission). Leave the trigger as `None` if you already produce `Hyper` another way, such as a Karabiner Elements remap.

Settings > Hotkeys lists all actions that can be assigned a shortcut, including advanced actions.

## When a shortcut does not fire

Confirm the binding and any registration warning in **Settings > Hotkeys**, then check **Settings > Troubleshooting** for related diagnostics. If skhd, Raycast, or another shortcut utility is still running with the same binding, stop it or reassign the conflicting shortcut before editing `settings.toml`.

[HotkeyClash](https://github.com/Wunderlandmedia/HotkeyClash) can inspect shortcuts across supported apps, config files, and macOS. It does not parse Raycast settings.

## Layout legend

- `Shared` works in any active layout.
- `Dwindle` works only when the active workspace uses the Dwindle layout.

## Workspace

| Action | Default Shortcut | Layout |
|--------|------------------|--------|
| Switch to Workspace 1-9 | `Option + 1-9` | `Shared` |
| Move to Workspace 1-9 | `Option + Shift + 1-9` | `Shared` |
| Switch to Workspace Slot 1-9 (position on the current monitor) | `Unassigned` | `Shared` |
| Move to Workspace Slot 1-9 (position on the current monitor) | `Unassigned` | `Shared` |
| Switch to Last Active Workspace (Back and Forth) | `Control + Option + Tab` | `Shared` |
| Switch to Next Workspace | `Unassigned` | `Shared` |
| Switch to Previous Workspace (Sequential) | `Unassigned` | `Shared` |
| Move Window to Workspace Up | `Control + Option + Shift + Up Arrow` | `Shared` |
| Move Window to Workspace Down | `Control + Option + Shift + Down Arrow` | `Shared` |

Creating workspace 10 or higher adds its Switch and Move actions to **Settings > Hotkeys** as `Unassigned`. The rows disappear when the workspace is removed.

## Focus

| Action | Default Shortcut | Layout |
|--------|------------------|--------|
| Focus Left / Right / Up / Down | `Option + Arrow Keys` | `Shared` |
| Focus Down or Top / Up or Bottom | `Unassigned` | `Shared` |
| Focus Previous Window | `Option + Tab` | `Shared` |
| Toggle Command Palette | `Control + Option + Space` | `Shared` |
| Open Menu Anywhere | `Control + Option + M` | `Shared` |
| Set Mark on Focused Window | `Unassigned` | `Shared` |
| Remove Mark from Focused Window | `Unassigned` | `Shared` |
| Close Focused Window | `Unassigned` | `Shared` |
| Toggle Workspace Bar | `Unassigned` | `Shared` |
| Toggle Hidden Icons Bar | `Unassigned` | `Shared` |
| Toggle Quake Terminal | `` Option + ` `` | `Shared` |
| Toggle Overview | `Option + Shift + O` | `Shared` |
| Toggle System Stats | `Unassigned` | `Shared` |

The Set Mark and Remove Mark global actions and the Command Palette mark shortcuts below are available.

### Window marks in the Command Palette

These shortcuts are available while the Command Palette is open in **Windows** mode. They act on the selected window row and are shown beside the matching Palette actions.

| Action | Shortcut |
|--------|----------|
| Mark selected window | `Control + Option + Shift + M` |
| Remove a mark from the selected window | `Control + Option + Shift + R` |

These shortcuts are local to the open Palette and yield to conflicting enabled global shortcuts; the affected Palette action remains available as a button. **Set Mark on Focused Window** and **Remove Mark from Focused Window** are also available as separate, unassigned actions in **Settings > Hotkeys** for configurable global shortcuts. Outside the Palette, key combinations retain their configured global behavior.

## Move Window

| Action | Default Shortcut | Layout |
|--------|------------------|--------|
| Move Left / Right / Up / Down | `Option + Shift + Arrow Keys` | `Shared` |
| Reorder Window Up / Down | `Unassigned` | `Shared` |

## Monitor

| Action | Default Shortcut | Layout |
|--------|------------------|--------|
| Focus Next Monitor | `Control + Command + Tab` | `Shared` |
| Focus Previous Monitor | `Unassigned` | `Shared` |
| Focus Last Monitor | `` Control + Command + ` `` | `Shared` |
| Move Workspace to Left / Right / Up / Down Monitor | `Unassigned` | `Shared` |
| Move Window to Left / Right / Up / Down Monitor | `Unassigned` | `Shared` |

The workspace-to-monitor actions target the active workspace and intentionally use the same temporary runtime override as `omniwmctl workspace move-to-monitor --force`. They do not rewrite the workspace's Home Monitor or swap workspaces, and unsafe fullscreen, hidden-app, scratchpad, or focus states still block the move.

The window-to-monitor actions send the focused window directly to the current workspace on the adjacent routed display, independently of **Move Window Across Monitor at Edge**. They do not wrap when no monitor exists in that direction. **Follow Window to Monitor** controls whether focus follows the window; when it is off, you remain in the source workspace.

## Layout

| Action | Default Shortcut | Layout |
|--------|------------------|--------|
| Toggle Fullscreen | `Option + Return` | `Shared` |
| Toggle Native Fullscreen | `Unassigned` | `Shared` |
| Balance Sizes | `Option + Shift + B` | `Shared` |
| Cycle Size Forward | `Option + .` | `Shared` |
| Cycle Size Backward | `Option + ,` | `Shared` |
| Move to Root | `Unassigned` | `Dwindle` |
| Toggle Split | `Unassigned` | `Dwindle` |
| Swap Split | `Unassigned` | `Dwindle` |
| Grow Horizontally / Vertically | `Unassigned` | `Dwindle` |
| Shrink Horizontally / Vertically | `Unassigned` | `Dwindle` |
| Grow / Shrink Focused Window | `Unassigned` | `Dwindle` |
| Preselect Left / Right / Up / Down | `Unassigned` | `Dwindle` |
| Clear Preselection | `Unassigned` | `Dwindle` |
| Raise All Floating Windows | `Option + Shift + R` | `Shared` |
| Rescue Off-Screen Floating Windows | `Unassigned` | `Shared` |
| Toggle Focused Window Floating | `Unassigned` | `Shared` |
| Assign Focused Window to Scratchpad 1-10 | `Unassigned` | `Shared` |
| Toggle Scratchpad 1-10 | `Unassigned` | `Shared` |

## Dwindle Groups

Dwindle groups use the existing Focus and Move bindings, so there are no separate group shortcuts to memorize. Only the active member occupies the tile; the other members stay hidden and the clickable tab rail shows their order.

| Goal | Default Shortcut | Behavior |
|------|------------------|----------|
| Focus another tile | `Option + Arrow Keys` | Left / Right are always spatial. Up / Down are spatial for a singleton tile. |
| Select the next / previous tab | `Option + Down / Up Arrow` | Within a group, Down advances and Up goes back. At the group edge OmniWM tries a spatial tile, then the configured monitor transition, and wraps locally only when neither exit succeeds. |
| Join a singleton into a tile or group | `Option + Shift + Arrow Keys` | Joins the focused singleton with the touching tile in that direction. |
| Extract the active tab | `Option + Shift + Arrow Keys` | When the focused tile is grouped, extracts only its active tab onto the requested side. |
| Move the complete tile or group | `Control + Option + Shift + Left / Right Arrow` | `Move Container` swaps the whole structure. Up / Down are advanced, unassigned Dwindle actions. |
| Select an exact tab | Click its tab rail item | Reveals and focuses that member without changing the group order. |

Moving a tab directly from one existing group into another is intentionally a two-step operation: extract it first, then move the resulting singleton toward the destination group. A singleton at a genuine workspace edge can still use the normal cross-monitor Move behavior; a rejected group mutation does not fall through to tile swapping or monitor movement.

The unassigned advanced actions are available in Settings > Hotkeys. `Focus Down or Top / Up or Bottom` always wraps within the active Dwindle group. `Reorder Window Up / Down` changes the active member's position by one without wrapping. `Move Container` is the whole-structure escape hatch and never transfers to another monitor at a workspace edge. Dwindle join/extract and Move Container operations are intentionally unavailable while Overview is open; leave Overview before changing a Dwindle tree.

## Quake Terminal (Inside Terminal)

These shortcuts work inside the [Quake Terminal](/features/quake-terminal/) itself:

| Action | Shortcut |
|--------|----------|
| New Tab | `Cmd + T` |
| Close Tab | `Cmd + W` |
| Next Tab | `Cmd + Shift + ]` |
| Previous Tab | `Cmd + Shift + [` |
| Next Tab (Alt) | `Ctrl + Tab` |
| Previous Tab (Alt) | `Ctrl + Shift + Tab` |
| Select Tab 1-9 | `Cmd + 1-9` |
| Split Pane (Horizontal) | `Cmd + D` |
| Split Pane (Vertical) | `Cmd + Shift + D` |
| Close Pane | `Cmd + Shift + W` |
| Equalize Splits | `Cmd + Shift + =` |
| Navigate Pane | `Cmd + Option + Arrow Keys` |
