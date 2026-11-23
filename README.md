# fluxget-ui2

Native desktop version of [Fluxget](../fluxget) built on [ui2](../ui2)'s
**custom renderer** — no webview, no vails, no native Win32 controls, no
frontend bundler. Same window on every backend from one codebase.

- Same pure engine as the web UI: `rpc/`, `aria2ctl/`, `core/`, `engine/`,
  `store/` are copied verbatim from `../fluxget`. Behaviour, limits, session
  format and the RPC wire stay identical.
- `app/` is the only new code: `App` (state + UI cache + actions) and
  `view.v` (pure-V ui2 layout + event routing).
- `main.v` owns the lifetime: menu bar, resolve root, start engine, ticker,
  `run_window_with_options(refresh: .on_demand)`, stop engine on close.

## Build & run (custom renderer)

```powershell
cd D:\MyProjects\fluxget-ui2
v -enable-globals -d ui2_custom_rendering -cc gcc `
  -cflags "-Wno-incompatible-pointer-types" -ldflags "-lws2_32" run .
```

- `-d ui2_custom_rendering` — the custom `gg` renderer on Windows too
  (D3D11), instead of retained Win32 controls. Required: the layout (chart,
  overlays, per-row buttons) is drawn by the app.
- `-enable-globals` — one `__global` for the shared App, like ui2's own
  `g_animation_runtime`.
- The `-cc`/`-cflags`/`-ldflags` trio is the same one fluxget documents:
  GCC 16 vs V's vendored `vschannel.c`, plus winsock for `net`.

Persian text uses the system Segoe UI face (`fa_font`); Latin keeps the
default face with `Consolas` for numbers/paths. No font shipping needed —
override with `UI2_FONT`/`UI2_FONT_BOLD` for comparison.

## What it does (parity with the web UI)

- Queue: add (URL/magnet, Enter submits), select row, pause/resume/remove/
  retry per row, move up/down, copy GID, pause-all/resume-all, clear history
- Search over name/gid/dir/error + status chips (all/active/waiting/paused/done)
- Speed chart (ui2 line chart, ~3 min of down/up in KiB/s)
- Details overlay per row: files, trackers, mirrors (live/idle), torrent fields
- Settings overlay: limits, folder (+ OS picker), seed ratio/time, BitTorrent,
  session memory — clamp → push → read-back → save, exactly like the web UI
- Log overlay: notices + engine stderr tail; menu bar (File: Add/Settings/Quit)
- fa/en toggle, aria2 version + counts in the status bar

Out on purpose: tray icon (unsupported on the custom renderer), per-user
category tagging of rows, scheduler UI.

## Layout

```
fluxget-ui2/
  main.v            bootstrap: menu, root, App, ticker, run_window_with_options
  app/app.v         App + tick cache + actions + detail + settings push
  app/view.v        pure-V layout: header/add/ops/search/chart/overlays + events
  app/app_test.v    pure tests: locale, filter, history cap, events, layout
  rpc/ aria2ctl/ engine/ core/ store/   verbatim copies from ../fluxget
```

## Sync rule

`rpc/`, `aria2ctl/`, `engine/`, `core/`, `store/` must stay identical to
`../fluxget`. Copy, do not fork: any fix lands upstream first, then re-copy.
`grep -r vails` must stay empty (same isolation rule as the original).
