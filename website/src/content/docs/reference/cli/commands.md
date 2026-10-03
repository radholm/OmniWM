---
title: Command Reference
description: omniwmctl top-level commands, global flags, exit codes, the full command action surface, and capture control.
sidebar:
  order: 2
---

## CLI Reference

```
omniwmctl <command> [arguments...] [--format json|ndjson|table|tsv|text] [--json]
```

### Top-Level Commands

| Command | Type | Description |
|---------|------|-------------|
| `ping` | remote | Verify IPC reachability and return `pong` |
| `version` | remote | Return app and IPC protocol versions plus available build fingerprint fields |
| `command` | remote | Execute window manager commands through the IPC command surface |
| `capture` | remote | Start, stop, or inspect a diagnostics trace or performance capture |
| `query` | remote | Query OmniWM state, registries, and protocol capabilities |
| `rule` | remote | Manage persisted window rules and reapply them to windows |
| `workspace` | remote | Perform workspace actions such as focusing, moving, or renaming by workspace name |
| `window` | remote | Perform window actions using session-scoped opaque IDs; it also supports [window marks](/reference/cli/actions/#window-marks) |
| `subscribe` | remote | Stream the subscribe handshake plus live event envelopes as JSON |
| `watch` | remote | Consume subscription events and run a child command once per event |
| `help`, `--help`, `-h` | local | Print CLI usage text without connecting to IPC |
| `completion <zsh\|bash\|fish\|nu>` | local | Emit a shell completion script without connecting to IPC |

Remote commands require IPC to be enabled. Local commands work even when the IPC server is disabled.

For Nushell 0.108 or newer, `omniwmctl completion nu` emits a module that adds Tab suggestions for commands, options, and fixed argument values. Save it as `omniwmctl-completions.nu` and import its `omniwmctl` definition from `config.nu`; see [shell completion setup](/reference/cli/overview/#nushell) for the commands. Regenerate the file after upgrading OmniWM.

`omniwmctl version --json` returns `protocolVersion` and the available `appVersion`, `gitHash`, `buildConfiguration`, and `executableSHA256` fields in `result.payload`. Optional fields are omitted when unavailable; the fingerprint identifies the running app build and executable.

### Global Flags

| Flag | Description |
|------|-------------|
| `--format <format>` | Output format: `json`, `ndjson` (one compact JSON envelope per line), `table`, `tsv`, `text` |
| `--json` | Alias for `--format json` |

Global flags must appear before `--exec` in watch commands.

### Exit Codes

| Code | Name | Meaning |
|------|------|---------|
| 0 | success | Command completed successfully |
| 1 | rejected | Server rejected the request |
| 2 | transportFailure | Could not connect to the IPC socket, or a `subscribe`/`watch` stream ended because OmniWM closed the connection (use `--reconnect` to keep streaming) |
| 3 | invalidArguments | CLI argument parsing failed |
| 4 | internalError | Unexpected internal error |

---

## Commands

Execute window manager commands. While Overview is closed, these use the same semantic command path as hotkey-bound commands, without `PhysicalHotkeyTrigger` metadata.

```
omniwmctl command <command-path> [arguments...]
```

### Focus

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command focus` | `<left\|right\|up\|down>` | shared | Focus spatially; Dwindle Up/Down traverse grouped tabs before edge fallback |
| `command focus-window down-or-top` | — | shared | Focus the next window in the active Dwindle group, wrapping locally |
| `command focus-window up-or-bottom` | — | shared | Focus the previous window in the active Dwindle group, wrapping locally |
| `command focus previous` | — | shared | Focus the previously focused window |

### Move

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command move` | `<left\|right\|up\|down>` | shared | Move with layout-aware consume/expel or Dwindle join/extract behavior |
| `command move-window-down` | — | shared | Reorder the focused window down by one without wrapping within its Dwindle group |
| `command move-window-up` | — | shared | Reorder the focused window up by one without wrapping within its Dwindle group |


In Dwindle, `focus left/right` remains spatial. `focus up/down` traverses a group's eligible tabs; at the group edge it tries a spatial neighbor, then the configured monitor transition, and wraps locally only when neither exit succeeds. `move <direction>` joins a singleton with the touching tile or extracts only the active member from a group onto that side. Moving between two existing groups is a two-step extract-then-join operation. Use `move-group <direction>` when the complete tile or group should move instead.

### Workspace Switching

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command switch-workspace` | `<number>` | shared | Switch to a workspace by numeric workspace ID on its assigned monitor |
| `command switch-workspace next` | — | shared | Switch to the next workspace |
| `command switch-workspace prev` | — | shared | Switch to the previous workspace |
| `command switch-workspace back-and-forth` | — | shared | Switch to the previously active workspace |
| `command switch-workspace anywhere` | `<number>` | shared | Focus a workspace by numeric workspace ID across all monitors |
| `command switch-workspace slot` | `<number>` | shared | Switch to the workspace at a one-based position in the interaction monitor's ordered workspace list |

### Move to Workspace

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command move-to-workspace` | `<number>` | shared | Move focused window to a workspace by numeric workspace ID |
| `command move-to-workspace up` | — | shared | Move focused window to the adjacent workspace above |
| `command move-to-workspace down` | — | shared | Move focused window to the adjacent workspace below |
| `command move-to-workspace on-monitor` | `<number> <left\|right\|up\|down>` | shared | Move focused window to a workspace already assigned to the requested adjacent monitor |
| `command move-to-workspace slot` | `<number>` | shared | Move focused window to the workspace at a one-based position in the interaction monitor's ordered workspace list |

Workspace IDs are positive numeric strings. Direct hotkeys for `1-9` have default bindings. Creating workspace `10+` adds unassigned direct hotkey actions. The workspace UI and IPC/CLI both support `10+`.

Workspace IDs are global, so `switch-workspace 3` targets workspace `3` wherever it lives. The `slot` variants address a position in the interaction monitor's ordered workspace list instead, the same order the workspace bar shows, so `switch-workspace slot 2` opens whichever workspace comes second on the monitor you are using. A slot beyond that monitor's list reports `not_found`; the native actions `Switch to Workspace Slot 1-9` and `Move to Workspace Slot 1-9` are unassigned by default.

### Monitor Focus

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command focus-monitor prev` | — | shared | Move focus to the previous monitor |
| `command focus-monitor next` | — | shared | Move focus to the next monitor |
| `command focus-monitor last` | — | shared | Move focus back to the previous monitor |
| `command move-to-monitor` | `<left\|right\|up\|down>` | shared | Move the focused window to the active workspace on an adjacent monitor |
| `command swap-workspace-with-monitor` | `<left\|right\|up\|down>` | shared | Swap active workspace with the workspace on an adjacent monitor |

`command move-to-monitor` does not wrap when no monitor exists in the requested direction. It honors **Follow Window to Monitor** and operates independently of **Move Window Across Monitor at Edge**.

### Dwindle Operations

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command move-to-root` | — | dwindle | Move the selected window to the root split |
| `command move-group` | `left` \| `right` \| `up` \| `down` | dwindle | Move the complete tile or group |
| `command toggle-split` | — | dwindle | Toggle the active split orientation |
| `command swap-split` | — | dwindle | Swap the active split |
| `command resize` | `<horizontal\|vertical> <grow\|shrink>` | dwindle | Grow or shrink the selected window along an axis |
| `command resize-focused` | `<grow\|shrink>` | dwindle | Grow or shrink the focused window |
| `command preselect` | `<left\|right\|up\|down>` | dwindle | Set the preselection direction |
| `command preselect clear` | — | dwindle | Clear the preselection |

### Layout & Sizing

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command balance-sizes` | — | shared | Balance layout sizes in the active workspace |
| `command cycle-size forward` | — | shared | Cycle layout sizing presets forward (in Dwindle the focused window takes 30, 50, or 70 % of its split) |
| `command cycle-size backward` | — | shared | Cycle layout sizing presets backward (in Dwindle the focused window takes 70, 50, or 30 % of its split) |
| `command set-workspace-layout` | `<default\|dwindle>` | shared | Set the workspace layout explicitly |
| `command toggle-fullscreen` | — | shared | Toggle OmniWM-managed fullscreen |
| `command toggle-native-fullscreen` | — | shared | Toggle native macOS fullscreen |

### Window Management

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command toggle-focused-window-floating` | — | shared | Toggle focused window between tiled and floating |
| `command close-focused-window` | — | shared | Close the focused managed window through its close button; returns `window_action_failed` when the window has no close button or refuses the press |
| `command raise-all-floating-windows` | — | shared | Raise all visible floating windows |
| `command rescue-offscreen-windows` | — | shared | Clamp tracked floating windows back onto their visible monitors |
| `command scratchpad assign <number>` | — | shared | Assign the focused window to scratchpad 1-10, or remove it when already there |
| `command scratchpad toggle <number>` | — | shared | Show or hide the windows in scratchpad 1-10 |

### UI Toggles

| Command | Arguments | Layout | Description |
|---------|-----------|--------|-------------|
| `command open-command-palette` | — | shared | Toggle the command palette |
| `command open-menu-anywhere` | — | shared | Open the menu surface |
| `command toggle-workspace-bar` | — | shared | Toggle workspace bar visibility |
| `command hidden-bar panel` | — | shared | Toggle the panel containing configured hidden menu-bar items |
| `command toggle-quake-terminal` | — | shared | Toggle the configured Quake terminal |
| `command toggle-overview` | — | shared | Open Overview when it is closed, or dismiss it onto the current selection when it is open |
| `command toggle-system-stats` | — | shared | Toggle the system stats popup when a workspace-bar System Stats button is available |

For example, run `omniwmctl command hidden-bar panel` to show or dismiss the Hidden Bar panel.

Overview is modal with respect to external commands. While it is open every IPC/external command except `toggle-overview` returns `ignored_overview`; `omniwmctl command toggle-overview` closes it onto the current selection, exactly like Escape, Enter, backdrop dismissal, or the configured physical Overview toggle.

**Layout compatibility:**
- `shared` — works with any active layout
- `dwindle` — only works when the active workspace uses the Dwindle layout

Commands sent to an incompatible layout return `layout_mismatch`.

---

## Capture

Capture control is independent of the window-manager enabled state, active layout, and Overview. IPC must still be enabled and the request must be authenticated.

```bash
omniwmctl capture start trace
omniwmctl capture start performance
omniwmctl capture stop
omniwmctl capture status
```

Only one capture can be active. `capture stop` stops whichever profile is recording and waits for finalization before returning. Starting while a capture is active, or stopping while the coordinator is idle, starting, or finalizing, returns `capture_state_conflict` with the current capture snapshot.

A trace capture writes an atomic partial immediately, refreshes it periodically, and replaces it with the final trace on stop or automatic finalization. A performance capture writes only its final artifact. Both profiles automatically finalize after 10 minutes and keep their existing size and retention limits.

`capture status` always returns `phase`. The active `profile`, `startedAt`, coordinator's `lastArtifact`, and `failureReason` are optional and omitted when unavailable; absent values are not encoded as `null`. Timestamps are RFC 3339 strings. Artifact paths are absolute. A write failure returns `internal_error` with a UTF-8-safe, 4 KiB-bounded `failureReason`.

```json
{
  "phase": "idle",
  "lastArtifact": {
    "profile": "trace",
    "path": "/Users/example/.local/state/omniwm/diagnostics/omniwm-trace-....log",
    "startedAt": "2026-08-25T21:00:00Z",
    "endedAt": "2026-08-25T21:01:00Z"
  }
}
```

`lastArtifact` is one process-local, best-effort slot rather than per-profile history. Its profile can differ from the active profile. A successful new trace start clears a prior trace artifact after the replacement partial is safely written; a performance start does not clear the slot. Successful finalization replaces it, while finalization failure leaves the prior value unchanged. During `finalizing`, it can still refer to the preceding capture.

If a successful stop response is lost, status can discover the result before another successful finalization or successful new trace start clears or replaces it. Wait for `phase` to become `idle` and compare the artifact metadata before starting another capture. Status does not recover failed responses, persist across app restarts, or provide capture history.

Disconnecting the client or disabling and restarting IPC while OmniWM remains alive does not stop an armed capture or roll back an accepted finalization, although the response can be lost. App termination does not finalize an active capture: a trace retains its latest completed partial, while an unfinished performance capture produces no artifact.
