// view.v — pure-V ui2 layout for Fluxget-ui2 (custom renderer).
//
// Fixed frames, no VML: the queue is dynamic (one select button per row, the
// event id carries the gid). Every row has a stable id `sel_<gid>` and the
// event handler parses it. Built for the custom renderer
// (-d ui2_custom_rendering): buttons are drawn by the app, so hundreds of
// rows do not cost native windows.
module app

import ui2

// max_rows_shown caps one frame: the tick already windows the queue
// server-side, this only protects the frame itself.
pub const max_rows_shown = 60

// fa_font names the face for Persian text on the custom renderer. The bundled
// Roboto has no Arabic coverage, so fa labels resolve against the system
// Segoe UI instead; Latin text keeps the default face.
pub const fa_font = 'Segoe UI'

fn tfont(fa bool, size f64) ui2.TextStyle {
	return ui2.TextStyle{
		size:        size
		font_family: if fa { fa_font } else { '' }
	}
}

fn btn_box(selected bool) ui2.BoxStyle {
	return ui2.BoxStyle{
		bg:            if selected { u32(0xDBEAFE) } else { u32(0xFFFFFF) }
		radius:        7
		border_color:  u32(0xCBD5E1)
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}
}

fn action_box() ui2.BoxStyle {
	return ui2.BoxStyle{ bg: u32(0x3478D4), radius: 7 }
}

fn chip_box(on bool) ui2.BoxStyle {
	return ui2.BoxStyle{
		bg:     if on { u32(0x0F172A) } else { u32(0xE2E8F0) }
		radius: 14
	}
}

fn small_label(text string, x f64, y f64, w f64, h f64, color u32, size f64, fa bool) ui2.Element {
	return ui2.label('', text, ui2.rect(x, y, w, h), ui2.TextStyle{
		color:       color
		size:        size
		font_family: if fa { fa_font } else { '' }
	})
}

fn field(id string, placeholder string, text string, x f64, y f64, w f64) ui2.Element {
	return ui2.text_field(id, placeholder, text, ui2.rect(x, y, w, 34), ui2.BoxStyle{
		bg:            u32(0xFFFFFF)
		radius:        7
		border_color:  u32(0xCBD5E1)
		border_left:   1
		border_top:    1
		border_right:  1
		border_bottom: 1
	}, ui2.TextStyle{ size: 13 }, 0)
}

// speed_chart renders the down/up history. Falls back to a label when the
// frame is too small or the chart rejects the data (empty history).
fn speed_chart(s Snapshot, x f64, y f64, w f64, h f64) ui2.Element {
	if w < 130 || h < 110 || s.hist_down.len == 0 {
		return small_label(if s.fa { 'هنوز داده‌ای نیست' } else { 'no data yet' }, x, y, w,
			24, u32(0x64748B), 12, s.fa)
	}
	return ui2.chart(ui2.ChartConfig{
		id:      'speed'
		frame:   ui2.rect(x, y, w, h)
		type:    .line
		data:    ui2.ChartData{
			labels:   s.hist_labels
			datasets: [
				ui2.ChartDataset{
					label: 'down'
					data:  s.hist_down
					color: u32(0x2563EB)
				},
				ui2.ChartDataset{
					label: 'up'
					data:  s.hist_up
					color: u32(0x16A34A)
				},
			]
		}
		options: ui2.ChartOptions{
			title:      tr(s.fa, 'speed')
			legend:     true
			grid:       true
			text_color: u32(0x334155)
			grid_color: u32(0xE2E8F0)
		}
	}) or {
		return small_label('chart: ' + err.msg(), x, y, w, 24, u32(0xB42318), 11, false)
	}
}

// build_screen renders one frame from a Snapshot copy. Pure: no locks, no
// engine calls, safe on the ui2 UI thread.
pub fn build_screen(s Snapshot) ui2.Element {
	b := ui2.bounds()
	w := if b.width > 0 { b.width } else { 1100.0 }
	h := if b.height > 0 { b.height } else { 760.0 }

	mut children := []ui2.Element{}

	// Header: brand, live speeds, phase, global ops.
	mut head := []ui2.Element{}
	head << ui2.label('title', 'Fluxget (ui2)', ui2.rect(14, 8, 150, 36), ui2.TextStyle{
		color: u32(0xFFFFFF)
		size:  18
		bold:  true
	})
	head << ui2.label('', 'v' + s.down_speed + '  ^' + s.up_speed, ui2.rect(170, 12, 230,
		28), ui2.TextStyle{
		color:       u32(0x93C5FD)
		size:        13
		font_family: 'Consolas'
	})
	head << ui2.label('', s.phase, ui2.rect(405, 14, 120, 24), ui2.TextStyle{
		color: u32(0xFDE68A)
		size:  13
	})
	gright := [['pause_all', tr(s.fa, 'pause_all')], ['resume_all', tr(s.fa, 'resume_all')],
		['forget_all', tr(s.fa, 'forget_all')], ['open_log', tr(s.fa, 'log')],
		['open_settings', tr(s.fa, 'settings')], ['lang', tr(s.fa, 'lang')]]
	mut gx := w - f64(gright.len) * 100.0 - 12.0
	for g in gright {
		head << ui2.button(g[0], g[1], ui2.rect(gx, 10, 94, 32), ui2.BoxStyle{
			bg:     u32(0x1E293B)
			radius: 7
		}, ui2.TextStyle{
			color:       u32(0xFFFFFF)
			size:        11
			font_family: if s.fa { fa_font } else { '' }
		})
		gx += 100.0
	}
	children << ui2.view('header', ui2.rect(0, 0, w, 52), ui2.BoxStyle{ bg: u32(0x0F172A) },
		head)

	// Add bar (Enter submits via submit_id).
	children << ui2.text_field_with_submit('add_field', 'add', tr(s.fa, 'url_hint'), '',
		ui2.rect(12, 60, w - 130, 36), ui2.BoxStyle{
			bg:            u32(0xFFFFFF)
			radius:        7
			border_color:  u32(0xCBD5E1)
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
		}, ui2.TextStyle{ size: 13 }, 0)
	children << ui2.button('add', tr(s.fa, 'add'), ui2.rect(w - 106, 60, 94, 36), action_box(),
		ui2.TextStyle{
			color:       u32(0xFFFFFF)
			size:        13
			bold:        true
			font_family: if s.fa { fa_font } else { '' }
		})

	// Selected-row ops.
	ops := [['pause_sel', tr(s.fa, 'pause')], ['resume_sel', tr(s.fa, 'resume')],
		['remove_sel', tr(s.fa, 'remove')], ['retry_sel', tr(s.fa, 'retry')],
		['details_sel', tr(s.fa, 'details')], ['copy_sel', tr(s.fa, 'copy')],
		['up_sel', tr(s.fa, 'up')], ['down_sel', tr(s.fa, 'down')]]
	aw := (w - 24.0 - 7.0 * 8.0) / 8.0
	for i, op in ops {
		x := 12.0 + f64(i) * (aw + 8.0)
		children << ui2.button(op[0], op[1], ui2.rect(x, 104, aw, 32), ui2.BoxStyle{
			bg:     u32(0xE2E8F0)
			radius: 7
		}, ui2.TextStyle{
			size:        12
			font_family: if s.fa { fa_font } else { '' }
		})
	}

	// Search + status filter chips.
	sy := 144.0
	sw := w * 0.34
	children << ui2.text_field_with_submit('search_field', 'search_go', tr(s.fa, 'search_hint'),
		s.search, ui2.rect(12, sy, sw, 34), ui2.BoxStyle{
			bg:            u32(0xFFFFFF)
			radius:        7
			border_color:  u32(0xCBD5E1)
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
		}, tfont(s.fa, 13), 0)
	children << ui2.button('search_go', tr(s.fa, 'search'), ui2.rect(20 + sw, sy, 80, 34),
		action_box(), ui2.TextStyle{
			color:       u32(0xFFFFFF)
			size:        12
			font_family: if s.fa { fa_font } else { '' }
		})
	children << ui2.button('search_clear', tr(s.fa, 'clear'), ui2.rect(106 + sw, sy, 70,
		34), ui2.BoxStyle{
		bg:     u32(0xE2E8F0)
		radius: 7
	}, tfont(s.fa, 12))
	filters := ['all', 'active', 'waiting', 'paused', 'done']
	mut fx := 192.0 + sw
	for f in filters {
		on := s.filter == f
		children << ui2.button('filter_' + f, tr(s.fa, f), ui2.rect(fx, sy, 84, 34),
			chip_box(on), ui2.TextStyle{
				color:       if on { u32(0xFFFFFF) } else { u32(0x0F172A) }
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			})
		fx += 90.0
	}

	// Main split: queue left, chart + notices right.
	list_y := 186.0
	mut list_h := h - list_y - 48.0
	if list_h < 160 {
		list_h = 160
	}
	left_w := w * 0.62 - 18.0
	right_x := w * 0.62
	right_w := w - right_x - 12.0
	rows := s.downloads.filter(matches_filter(it, s.filter, s.search))
	if s.phase != 'ready' {
		detail := if s.detail != '' { s.detail } else { tr(s.fa, 'needs_engine') }
		children << ui2.label('', detail, ui2.rect(14, list_y + 10, left_w, 30), ui2.TextStyle{
			color:       u32(0xB42318)
			size:        13
			font_family: if s.fa { fa_font } else { '' }
		})
	} else if rows.len == 0 {
		children << small_label(tr(s.fa, 'empty'), 14, list_y + 10, left_w, 24, u32(0x64748B),
			13, s.fa)
	} else {
		mut items := []ui2.Element{}
		shown := if rows.len > max_rows_shown { max_rows_shown } else { rows.len }
		for i in 0 .. shown {
			d := rows[i]
			y := f64(i) * 60.0
			sel := d.gid == s.selected
			title := d.name + '  [' + d.status + ' ' + int(d.percent).str() + '% ' + d.speed + ']'
			sub := d.done + ' / ' + d.total + (if d.eta != '' { '  ' + d.eta } else { '' }) + (if d.err != '' {
				'  !! ' + d.err
			} else {
				''
			})
			items << ui2.view('row_' + d.gid, ui2.rect(0, y, left_w, 56), ui2.BoxStyle{
				bg:     if sel { u32(0xEFF6FF) } else { u32(0xF8FAFC) }
				radius: 8
			}, [
				ui2.button('sel_' + d.gid, title, ui2.rect(6, 4, left_w - 12, 26), btn_box(sel),
					ui2.TextStyle{ size: 12 }),
				ui2.label('', sub, ui2.rect(12, 32, left_w - 24, 20), ui2.TextStyle{
					color:       u32(0x64748B)
					size:        11
					font_family: 'Consolas'
				}),
			])
		}
		children << ui2.scroll('queue', ui2.rect(12, list_y, left_w, list_h), u32(0xF1F5F9),
			items)
		if rows.len > shown {
			children << small_label('showing ${shown}/${rows.len}', 14, list_y + list_h + 2,
				220, 18, u32(0x64748B), 11, false)
		}
	}
	children << speed_chart(s, right_x, list_y, right_w, 230)
	mut ny := list_y + 238.0
	children << small_label(if s.fa { 'رویدادها' } else { 'Events' }, right_x, ny, right_w,
		20, u32(0x475569), 12, s.fa)
	ny += 22.0
	nshown := if s.notices.len > 6 { 6 } else { s.notices.len }
	for i in 0 .. nshown {
		n := s.notices[s.notices.len - 1 - i]
		children << small_label(n, right_x, ny + f64(i) * 20.0, right_w, 18, u32(0x334155),
			11, s.fa)
	}

	// Status bar.
	st_y := h - 36.0
	status := if s.message != '' {
		s.message
	} else {
		'active ${s.num_active}  waiting ${s.num_waiting}  stopped ${s.num_stopped}  ${rows.len} shown' + (if s.version != '' {
			'  aria2 ' + s.version
		} else {
			''
		})
	}
	children << ui2.view('status', ui2.rect(0, st_y, w, 36), ui2.BoxStyle{ bg: u32(0xF1F5F9) },
		[
			ui2.label('', status, ui2.rect(14, 6, w - 28, 24), ui2.TextStyle{
				color:       u32(0x334155)
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			}),
		])

	if s.show_detail {
		children << detail_overlay(s, w, h)
	}
	if s.show_settings {
		children << settings_overlay(s, w, h)
	}
	if s.show_log {
		children << log_overlay(s, w, h)
	}

	return ui2.screen(u32(0xF1F5F9), children)
}

// detail_overlay is the on-demand record for the selected download.
fn detail_overlay(s Snapshot, w f64, h f64) ui2.Element {
	d := s.info
	bw := if w > 640 { 600.0 } else { w - 40.0 }
	bh := if h > 560 { 520.0 } else { h - 60.0 }
	bx := (w - bw) / 2.0
	by := (h - bh) / 2.0
	mut items := []ui2.Element{}
	mut y := 52.0
	kv := [['gid', d.gid], ['name', d.name], ['status', d.status], ['done', d.done + ' / ' + d.total],
		['speed', d.speed + '  ^' + d.upload], ['uploaded', d.uploaded], ['eta', d.eta],
		['dir', d.dir], ['connections', d.connections], ['info hash', d.info_hash],
		['pieces', if d.num_pieces > 0 { d.num_pieces.str() + ' x ' + d.piece_length } else { '' }],
		['verified', d.verified], ['seeders/leechers', if d.info_hash != '' {
			'${d.seeders}/${d.leechers}'
		} else {
			''
		}], ['error', d.error]]
	for p in kv {
		if p[1] == '' {
			continue
		}
		items << ui2.label('', p[0] + ': ' + p[1], ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{
			size: 12
		})
		y += 22.0
	}
	lists := [d.live, d.idle, d.uris, d.trackers, d.files]
	titles := ['mirrors in use', 'mirrors idle', 'sources', 'trackers', 'files']
	for li in 0 .. lists.len {
		vals := lists[li]
		if vals.len == 0 {
			continue
		}
		items << ui2.label('', titles[li] + ' (${vals.len}):', ui2.rect(16, y, bw - 32, 20),
			ui2.TextStyle{ size: 12, bold: true })
		y += 22.0
		n := if vals.len > 12 { 12 } else { vals.len }
		for i in 0 .. n {
			items << ui2.label('', vals[i], ui2.rect(28, y, bw - 44, 18), ui2.TextStyle{
				size:        11
				font_family: 'Consolas'
			})
			y += 20.0
		}
	}
	return ui2.view('detail_overlay', ui2.rect(bx, by, bw, bh), ui2.BoxStyle{
		bg:            u32(0xFFFFFF)
		radius:        12
		border_color:  u32(0x0F172A)
		border_left:   2
		border_top:    2
		border_right:  2
		border_bottom: 2
	}, [
		ui2.label('', d.name, ui2.rect(16, 10, bw - 120, 30), ui2.TextStyle{ size: 16, bold: true }),
		ui2.button('close_detail', tr(s.fa, 'close'), ui2.rect(bw - 100, 10, 86, 30),
			action_box(), ui2.TextStyle{ color: u32(0xFFFFFF), size: 12 }),
		ui2.scroll('detail_scroll', ui2.rect(0, 46, bw, bh - 56), u32(0xFFFFFF), items),
	])
}

// settings_overlay edits limits + files, like the web Settings dialog.
fn settings_overlay(s Snapshot, w f64, h f64) ui2.Element {
	bw := if w > 620 { 580.0 } else { w - 40.0 }
	bh := if h > 620 { 580.0 } else { h - 60.0 }
	bx := (w - bw) / 2.0
	by := (h - bh) / 2.0
	rows := [['set_max_concurrent', 'max_concurrent', s.set_max_concurrent],
		['set_max_per_server', 'max connections/server', s.set_max_per_server],
		['set_split', 'split', s.set_split],
		['set_download_limit', 'download limit (B/s, 0=unlimited)', s.set_download_limit],
		['set_upload_limit', 'upload limit (B/s, 0=unlimited)', s.set_upload_limit],
		['set_dir', 'download folder', s.set_dir], ['set_seed_ratio', 'seed ratio', s.set_seed_ratio],
		['set_seed_time', 'seed time (min)', s.set_seed_time]]
	mut items := []ui2.Element{}
	mut y := 52.0
	for r in rows {
		items << ui2.label('', r[1], ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{ size: 12 })
		y += 22.0
		fw := bw - 32.0
		if r[0] == 'set_dir' {
			items << ui2.text_field(r[0], '', r[2], ui2.rect(16, y, fw - 110, 34), ui2.BoxStyle{
				bg:     u32(0xF8FAFC)
				radius: 7
			}, ui2.TextStyle{ size: 12 }, 0)
			items << ui2.button('pick_dir', tr(s.fa, 'pick'), ui2.rect(16 + fw - 100, y,
				100, 34), ui2.BoxStyle{ bg: u32(0xE2E8F0), radius: 7 }, ui2.TextStyle{ size: 12 })
		} else {
			items << ui2.text_field(r[0], '', r[2], ui2.rect(16, y, fw, 34), ui2.BoxStyle{
				bg:     u32(0xF8FAFC)
				radius: 7
			}, ui2.TextStyle{ size: 12 }, 0)
		}
		y += 40.0
	}
	bt := if s.set_bt { '[x] BitTorrent (dht/pex)' } else { '[ ] BitTorrent (dht/pex)' }
	ss := if s.set_save_session {
		'[x] remember queue across restarts'
	} else {
		'[ ] remember queue across restarts'
	}
	items << ui2.button('toggle_bt', bt, ui2.rect(16, y, bw - 32, 32), btn_box(s.set_bt),
		ui2.TextStyle{ size: 12 })
	y += 38.0
	items << ui2.button('toggle_save_session', ss, ui2.rect(16, y, bw - 32, 32), btn_box(s.set_save_session),
		ui2.TextStyle{ size: 12 })
	y += 38.0
	items << ui2.label('', s.set_path, ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{
		color:       u32(0x64748B)
		size:        11
		font_family: 'Consolas'
	})
	return ui2.view('settings_overlay', ui2.rect(bx, by, bw, bh), ui2.BoxStyle{
		bg:            u32(0xFFFFFF)
		radius:        12
		border_color:  u32(0x0F172A)
		border_left:   2
		border_top:    2
		border_right:  2
		border_bottom: 2
	}, [
		ui2.label('', tr(s.fa, 'settings'), ui2.rect(16, 10, bw - 220, 30), ui2.TextStyle{
			size:        16
			bold:        true
			font_family: if s.fa { fa_font } else { '' }
		}),
		ui2.button('close_settings', tr(s.fa, 'close'), ui2.rect(bw - 204, 10, 90, 30),
			ui2.BoxStyle{ bg: u32(0xE2E8F0), radius: 7 }, ui2.TextStyle{ size: 12 }),
		ui2.button('save_settings', tr(s.fa, 'save'), ui2.rect(bw - 104, 10, 90, 30),
			action_box(), ui2.TextStyle{ color: u32(0xFFFFFF), size: 12 }),
		ui2.scroll('settings_scroll', ui2.rect(0, 46, bw, bh - 56), u32(0xFFFFFF), items),
	])
}

// log_overlay shows recent notices + the engine's stderr tail.
fn log_overlay(s Snapshot, w f64, h f64) ui2.Element {
	bw := if w > 680 { 640.0 } else { w - 40.0 }
	bh := if h > 560 { 520.0 } else { h - 60.0 }
	bx := (w - bw) / 2.0
	by := (h - bh) / 2.0
	mut items := []ui2.Element{}
	mut y := 10.0
	for n in s.notices {
		items << ui2.label('', n, ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{ size: 12 })
		y += 22.0
	}
	if s.logs_dropped > 0 {
		items << ui2.label('', '... ${s.logs_dropped} lines dropped ...', ui2.rect(16, y,
			bw - 32, 20), ui2.TextStyle{ color: u32(0x64748B), size: 11 })
		y += 22.0
	}
	for l in s.logs {
		items << ui2.label('', l, ui2.rect(16, y, bw - 32, 18), ui2.TextStyle{
			size:        11
			font_family: 'Consolas'
		})
		y += 20.0
	}
	return ui2.view('log_overlay', ui2.rect(bx, by, bw, bh), ui2.BoxStyle{
		bg:            u32(0x0B1220)
		radius:        12
		border_color:  u32(0x0F172A)
		border_left:   2
		border_top:    2
		border_right:  2
		border_bottom: 2
	}, [
		ui2.label('', tr(s.fa, 'log'), ui2.rect(16, 10, bw - 320, 30), ui2.TextStyle{
			color: u32(0xFFFFFF)
			size:  16
			bold:  true
		}),
		ui2.button('clear_notices', tr(s.fa, 'clear'), ui2.rect(bw - 204, 10, 90, 30),
			ui2.BoxStyle{ bg: u32(0x1E293B), radius: 7 }, ui2.TextStyle{
				color: u32(0xFFFFFF)
				size:  12
			}),
		ui2.button('close_log', tr(s.fa, 'close'), ui2.rect(bw - 104, 10, 90, 30),
			action_box(), ui2.TextStyle{ color: u32(0xFFFFFF), size: 12 }),
		ui2.scroll('log_scroll', ui2.rect(0, 46, bw, bh - 56), u32(0x0B1220), items),
	])
}

// handle_event routes one ui2 action id to an App action. Returns true when
// the view should rebuild (almost always).
pub fn handle_event(mut a &App, event string) bool {
	match event {
		'add' {
			url := ui2.text('add_field')
			a.add(url)
			if url.trim_space() != '' {
				ui2.set_text('add_field', '')
			}
			return true
		}
		'search_go' {
			a.set_search(ui2.text('search_field'))
			return true
		}
		'search_clear' {
			ui2.set_text('search_field', '')
			a.set_search('')
			return true
		}
		'lang' {
			a.toggle_lang()
			return true
		}
		'pause_sel' {
			a.pause_selected()
			return true
		}
		'resume_sel' {
			a.resume_selected()
			return true
		}
		'remove_sel' {
			a.remove_selected()
			return true
		}
		'retry_sel' {
			a.retry_selected()
			return true
		}
		'details_sel' {
			a.open_detail()
			return true
		}
		'copy_sel' {
			a.copy_selected()
			return true
		}
		'up_sel' {
			a.move_selected(-1)
			return true
		}
		'down_sel' {
			a.move_selected(1)
			return true
		}
		'pause_all' {
			a.pause_all()
			return true
		}
		'resume_all' {
			a.resume_all()
			return true
		}
		'forget_all' {
			a.forget_all()
			return true
		}
		'open_settings' {
			a.open_settings()
			return true
		}
		'close_settings' {
			a.close_settings()
			return true
		}
		'toggle_bt' {
			a.toggle_bt()
			return true
		}
		'toggle_save_session' {
			a.toggle_save_session()
			return true
		}
		'pick_dir' {
			a.pick_dir()
			return true
		}
		'save_settings' {
			a.save_settings_from(ui2.text('set_max_concurrent'), ui2.text('set_max_per_server'),
				ui2.text('set_split'), ui2.text('set_download_limit'), ui2.text('set_upload_limit'),
				ui2.text('set_dir'), ui2.text('set_seed_ratio'), ui2.text('set_seed_time'))
			return true
		}
		'close_detail' {
			a.close_detail()
			return true
		}
		'open_log' {
			a.open_log()
			return true
		}
		'close_log' {
			a.close_log()
			return true
		}
		'clear_notices' {
			a.clear_notices()
			return true
		}
		'menu_add' {
			ui2.focus('add_field')
			return false
		}
		'menu_settings' {
			a.open_settings()
			return true
		}
		'menu_quit' {
			ui2.quit()
			return false
		}
		else {
			if event.starts_with('sel_') {
				a.select(event[4..])
				return true
			}
			if event.starts_with('filter_') {
				a.set_filter(event[7..])
				return true
			}
			return false
		}
	}
}
