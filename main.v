// main.v — fluxget-ui2 entry point (custom renderer).
//
// Native ui2 window on the custom gg renderer (-d ui2_custom_rendering), no
// webview, no vails. The engine is the same pure code the web UI drives
// (rpc, aria2ctl, core, engine, store, copied verbatim), so behaviour and
// limits stay identical; only the presentation changes.
//
// Build:
//
//   v -enable-globals -d ui2_custom_rendering -cc gcc `
//     -cflags "-Wno-incompatible-pointer-types" -ldflags "-lws2_32" .
module main

import app
import os
import time
import ui2

__global g_flux &app.App

fn build_ui() ui2.Element {
	g := g_flux
	if g == unsafe { nil } {
		return ui2.screen(u32(0xF1F5F9), [
			ui2.label('', 'starting…', ui2.rect(20, 20, 300, 30), ui2.TextStyle{ size: 14 }),
		])
	}
	return app.build_screen(g.snapshot())
}

fn handle_ui(event string) {
	mut g := g_flux
	if g == unsafe { nil } {
		return
	}
	if app.handle_event(mut g, event) {
		ui2.refresh()
	}
}

fn ticker() {
	for {
		time.sleep(1200 * time.millisecond)
		mut g := g_flux
		if g == unsafe { nil } {
			continue
		}
		g.tick_once()
		// Detail for the bottom panel refreshes outside the state lock.
		changed := g.refresh_detail_if_needed()
		_ = changed
		ui2.request_refresh()
	}
}

// resolve_root finds the project root: where runtime/aria2c.exe and downloads/
// live. Probes the cwd, the executable dir and two levels up, like the web
// version, so a shortcut or double-click still finds the engine.
fn resolve_root() string {
	roots := [
		os.getwd(),
		os.dir(os.executable()),
		os.join_path(os.dir(os.executable()), '..'),
		os.join_path(os.dir(os.executable()), '..', '..'),
	]
	for r in roots {
		if os.exists(os.join_path(r, 'runtime', 'aria2c.exe'))
			|| os.exists(os.join_path(r, 'runtime')) || os.exists(os.join_path(r, 'v.mod')) {
			return r
		}
	}
	return os.getwd()
}

fn main() {
	// The custom renderer draws its own menu bar across the top of the
	// window; declare it before the window exists so it is installed with it.
	ui2.set_menu_bar([
		ui2.Menu{
			title: 'File'
			items: [
				ui2.menu_item_with_shortcut('menu_add', 'Add download…', 'cmd+n'),
				ui2.menu_item('menu_settings', 'Settings…'),
				ui2.menu_item_with_shortcut('menu_quit', 'Quit', 'cmd+q'),
			]
		},
	])
	root := resolve_root()
	g_flux = app.new_app(root)
	mut g := g_flux
	g.start_engine()
	// First poll synchronously so the first frame already shows the phase
	// instead of "starting…".
	g.tick_once()
	spawn ticker()
	ui2.run_window_with_options(ui2.WindowOptions{
		title:   'Fluxget (ui2)'
		width:   1240
		height:  820
		refresh: .on_demand
	}, build_ui, handle_ui)
	g.stop_engine()
}
