// view.v — FDM-style dark layout for Fluxget-ui2 (custom renderer).
//
// Fixed frames, pure-V: a left sidebar (views + file kinds), a top toolbar, a
// table-like queue with inline progress bars, and a bottom panel with
// Progress/Files/Details tabs. Every row has a stable id `sel_<gid>`; the
// event handler parses the gid out of it.
module app

import fashape
import ui2

// max_rows_shown caps one frame: the tick already windows the queue
// server-side, this only protects the frame itself.
pub const max_rows_shown = 80

// FDM-like dark palette.
pub const c_bg = u32(0x1E222A)
pub const c_side = u32(0x16191F)
pub const c_bar = u32(0x232830)
pub const c_row = u32(0x232830)
pub const c_row_sel = u32(0x2E3B4E)
pub const c_card = u32(0x232830)
pub const c_line = u32(0x2E3440)
pub const c_text = u32(0xE6E9EF)
pub const c_muted = u32(0x8B949E)
pub const c_accent = u32(0x2F81F7)
pub const c_green = u32(0x3FB950)
pub const c_red = u32(0xF85149)
pub const c_amber = u32(0xD29922)

// fa_font names the face for Persian text on the custom renderer. The bundled
// Roboto has no Arabic coverage, so fa labels resolve against the system
// Segoe UI instead; Latin keeps the default face.
pub const fa_font = 'Segoe UI'

// t is tr shaped for the custom renderer (no complex text layout there).
fn t(fa bool, key string) string {
	return fashape.sh_auto(tr(fa, key))
}

fn tfont(fa bool, size f64) ui2.TextStyle {
	return ui2.TextStyle{
		color:       c_text
		size:        size
		font_family: if fa { fa_font } else { '' }
	}
}

fn tmuted(size f64) ui2.TextStyle {
	return ui2.TextStyle{
		color: c_muted
		size:  size
	}
}

fn status_color(status string) u32 {
	return match status {
		'active' { c_accent }
		'paused', 'waiting' { c_amber }
		'complete' { c_green }
		'error', 'removed' { c_red }
		else { c_muted }
	}
}

fn tool_btn(id string, title string, x f64, w f64, bg u32) ui2.Element {
	return ui2.button(id, title, ui2.rect(x, 10, w, 40), ui2.BoxStyle{
		bg:     bg
		radius: 8
	}, ui2.TextStyle{
		color: c_text
		size:  15
		bold:  true
	})
}

fn nav_item(id string, title string, count int, y f64, w f64, on bool, fa bool) ui2.Element {
	return ui2.button(id, title + '  ' + count.str(), ui2.rect(10, y, w - 20, 32),
		ui2.BoxStyle{
			bg:     if on { c_row_sel } else { 0x16191F }
			radius: 7
		}, ui2.TextStyle{
			color:       if on { c_text } else { c_muted }
			size:        13
			font_family: if fa { fa_font } else { '' }
		})
}

// speed_chart renders the down/up history. Falls back to a label when there
// is no data yet or the frame is too small for a chart.
fn speed_chart(s Snapshot, x f64, y f64, w f64, h f64) ui2.Element {
	if w < 130 || h < 110 || s.hist_down.len == 0 {
		return ui2.label('', if s.fa {
			fashape.sh_auto('هنوز داده‌ای نیست')
		} else {
			'no data yet'
		},
			ui2.rect(x, y, w, 24), ui2.TextStyle{
				color:       c_muted
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			})
	}
	return ui2.chart(ui2.ChartConfig{
		id:      'speed'
		frame:   ui2.rect(x, y, w, h)
		type:    .line
		data:    ui2.ChartData{
			labels:   s.hist_labels
			datasets: [
				ui2.ChartDataset{
					label: 'D'
					data:  s.hist_down
					color: c_accent
				},
				ui2.ChartDataset{
					label: 'U'
					data:  s.hist_up
					color: c_green
				},
			]
		}
		options: ui2.ChartOptions{
			title:      'Speed (KiB/s)'
			legend:     true
			grid:       true
			text_color: c_text
			grid_color: c_line
			background: c_card
		}
	}) or {
		return ui2.label('', 'chart: ' + err.msg(), ui2.rect(x, y, w, 24), ui2.TextStyle{
			color: c_red
			size:  11
		})
	}
}

// segments draws an FDM-like pieces map from the overall percent: 56 blocks,
// filled blue, the rest dark. Visual only — aria2's per-piece bitfield is not
// on the polled snapshot.
fn segments(percent f64, x f64, y f64, w f64) ui2.Element {
	n := 56
	filled := int(percent / 100.0 * f64(n) + 0.5)
	bw := (w - f64(n - 1) * 3.0) / f64(n)
	mut blocks := []ui2.Element{}
	for i in 0 .. n {
		bx := x + f64(i) * (bw + 3.0)
		blocks << ui2.view('seg${i}', ui2.rect(bx, y, bw, 14), ui2.BoxStyle{
			bg:     if i < filled { c_accent } else { c_line }
			radius: 2
		}, [])
	}
	return ui2.view('segments', ui2.rect(x, y, w, 14), ui2.BoxStyle{ transparent: true },
		blocks)
}

// build_screen renders one frame from a Snapshot copy. Pure: no locks, no
// engine calls, safe on the ui2 UI thread.
pub fn build_screen(s Snapshot) ui2.Element {
	b := ui2.bounds()
	w := if b.width > 0 { b.width } else { 1240.0 }
	h := if b.height > 0 { b.height } else { 820.0 }

	side_w := 236.0
	main_x := side_w
	main_w := w - side_w

	mut children := []ui2.Element{}

	// ---- sidebar ----
	mut side := []ui2.Element{}
	side << ui2.label('', 'Fluxget', ui2.rect(16, 10, side_w - 32, 30), ui2.TextStyle{
		color: c_text
		size:  19
		bold:  true
	})
	side << ui2.text_field_with_submit('search_field', 'search_go', t(s.fa, 'search_hint'),
		s.search, ui2.rect(12, 48, side_w - 24, 34), ui2.BoxStyle{
			bg:            u32(0x232830)
			radius:        7
			border_color:  c_line
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
		}, ui2.TextStyle{
			color:       c_text
			size:        12
			font_family: if s.fa { fa_font } else { '' }
		}, 0)
	mut ny := 92.0
	mut paused_n := 0
	for r in s.downloads {
		if r.status == 'paused' {
			paused_n++
		}
	}
	nav_counts := [s.count_total, s.num_active + s.num_waiting, paused_n, s.num_stopped]
	nav_ids := ['nav_all', 'nav_downloading', 'nav_paused', 'nav_finished']
	nav_filters := ['all', 'downloading', 'paused', 'done']
	nav_titles := [t(s.fa, 'all'), t(s.fa, 'downloading'), t(s.fa, 'paused'), t(s.fa,
		'finished')]
	for i in 0 .. 4 {
		side << nav_item(nav_ids[i], nav_titles[i], nav_counts[i], ny, side_w, s.filter == nav_filters[i],
			s.fa)
		ny += 36.0
	}
	side << ui2.label('', t(s.fa, 'file_types'), ui2.rect(16, ny + 6, side_w - 32, 20),
		ui2.TextStyle{
			color:       c_muted
			size:        11
			font_family: if s.fa { fa_font } else { '' }
		})
	ny += 30.0
	for k in file_kinds {
		side << nav_item('kind_' + k, t(s.fa, k), count_kind(s.downloads, k), ny, side_w,
			s.filter == 'kind:' + k, s.fa)
		ny += 36.0
	}
	side << ui2.label('', if s.version != '' { 'aria2 ' + s.version } else { '' }, ui2.rect(16,
		h - 62, side_w - 32, 20), tmuted(11))
	side << ui2.button('lang', t(s.fa, 'lang'), ui2.rect(12, h - 38, side_w - 24, 30),
		ui2.BoxStyle{
			bg:     c_bar
			radius: 7
		}, ui2.TextStyle{
			color:       c_text
			size:        12
			font_family: if s.fa { fa_font } else { '' }
		})
	children << ui2.view('sidebar', ui2.rect(0, 0, side_w, h), ui2.BoxStyle{ bg: c_side },
		side)

	// ---- toolbar ----
	mut bar := []ui2.Element{}
	bar << tool_btn('add_top', '+', 12, 56, c_accent)
	bar << tool_btn('resume_sel', '▶', 74, 48, c_bar)
	bar << tool_btn('pause_sel', '❚❚', 128, 48, c_bar)
	bar << tool_btn('remove_sel', '×', 182, 48, c_bar)
	bar << tool_btn('up_sel', '▲', 244, 44, c_bar)
	bar << tool_btn('down_sel', '▼', 294, 44, c_bar)
	bar << ui2.button('details_sel', t(s.fa, 'details'), ui2.rect(352, 10, 96, 40),
		ui2.BoxStyle{
			bg:     c_bar
			radius: 8
		}, ui2.TextStyle{
			color:       c_text
			size:        12
			font_family: if s.fa { fa_font } else { '' }
		})
	right_btns := [['open_settings', t(s.fa, 'settings')], ['open_log', t(s.fa, 'log')]]
	mut rx := main_x + main_w - 12.0
	for i := right_btns.len - 1; i >= 0; i-- {
		rx -= 100.0
		bar << ui2.button(right_btns[i][0], right_btns[i][1], ui2.rect(rx, 10, 94, 40),
			ui2.BoxStyle{
				bg:     c_bar
				radius: 8
			}, ui2.TextStyle{
				color:       c_text
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			})
		rx -= 6.0
	}
	children << ui2.view('toolbar', ui2.rect(main_x, 0, main_w, 60), ui2.BoxStyle{ bg: c_bar },
		bar)

	// ---- add bar ----
	children << ui2.text_field_with_submit('add_field', 'add', t(s.fa, 'url_hint'), '',
		ui2.rect(main_x + 12, 68, main_w - 130, 36), ui2.BoxStyle{
			bg:            u32(0x232830)
			radius:        7
			border_color:  c_line
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
		}, ui2.TextStyle{
			color:       c_text
			size:        13
			font_family: if s.fa { fa_font } else { '' }
		}, 0)
	children << ui2.button('add', t(s.fa, 'add'), ui2.rect(main_x + main_w - 106, 68, 94,
		36), ui2.BoxStyle{
		bg:     c_accent
		radius: 7
	}, ui2.TextStyle{
		color:       u32(0xFFFFFF)
		size:        13
		bold:        true
		font_family: if s.fa { fa_font } else { '' }
	})

	// ---- queue table ----
	rows := s.downloads.filter(matches_filter(it, s.filter, s.search))
	head_y := 112.0
	col_name := main_x + 16.0
	col_size := main_x + main_w * 0.46
	col_status := main_x + main_w * 0.58
	col_speed := main_x + main_w * 0.74
	col_eta := main_x + main_w * 0.88
	head_titles := ['Name', 'Size', 'Status', 'Speed', 'ETA']
	head_xs := [col_name, col_size, col_status, col_speed, col_eta]
	for i in 0 .. head_titles.len {
		children << ui2.label('', head_titles[i], ui2.rect(head_xs[i], head_y, 120, 20),
			tmuted(11))
	}
	list_y := 136.0
	bottom_h := 236.0
	status_h := 32.0
	mut list_h := h - list_y - bottom_h - status_h - 8.0
	if list_h < 140 {
		list_h = 140
	}
	if s.phase != 'ready' {
		detail := if s.detail != '' { s.detail } else { t(s.fa, 'needs_engine') }
		children << ui2.label('', detail, ui2.rect(col_name, list_y + 10, main_w - 32, 30),
			ui2.TextStyle{
				color:       c_red
				size:        13
				font_family: if s.fa { fa_font } else { '' }
			})
	} else if rows.len == 0 {
		children << ui2.label('', t(s.fa, 'empty'), ui2.rect(col_name, list_y + 10, main_w - 32,
			24), ui2.TextStyle{
			color:       c_muted
			size:        13
			font_family: if s.fa { fa_font } else { '' }
		})
	} else {
		mut items := []ui2.Element{}
		shown := if rows.len > max_rows_shown { max_rows_shown } else { rows.len }
		name_w := col_size - col_name - 8.0
		for i in 0 .. shown {
			d := rows[i]
			y := f64(i) * 60.0
			sel := d.gid == s.selected
			fill_w := name_w * d.percent / 100.0
			items << ui2.view('row_' + d.gid, ui2.rect(0, y, main_w - 24, 56), ui2.BoxStyle{
				bg:     if sel { c_row_sel } else { c_row }
				radius: 8
			}, [
				ui2.button('sel_' + d.gid, fashape.sh_auto(d.name), ui2.rect(8, 4, name_w, 22), ui2.BoxStyle{
					transparent: true
				}, ui2.TextStyle{
					color: c_text
					size:  13
				}),
				ui2.view('track_' + d.gid, ui2.rect(8, 30, name_w, 6), ui2.BoxStyle{
					bg:     c_line
					radius: 3
				}, [
					ui2.view('fill_' + d.gid, ui2.rect(0, 0, fill_w, 6), ui2.BoxStyle{
						bg:     if d.status == 'complete' { c_green } else { c_accent }
						radius: 3
					}, []),
				]),
				ui2.label('', int(d.percent).str() + '%', ui2.rect(8 + name_w + 4, 4, 52, 22),
					ui2.TextStyle{
						color:       c_muted
						size:        12
						font_family: 'Consolas'
					}),
				ui2.label('', d.done + ' / ' + d.total, ui2.rect(col_size - main_x - 12, 16,
					110, 22), ui2.TextStyle{
					color:       c_text
					size:        12
					font_family: 'Consolas'
				}),
				ui2.label('', fashape.sh_auto(d.status + (if d.err != '' {
					' !! ' + d.err
				} else {
					''
				})),
					ui2.rect(col_status - main_x - 12, 16, 130, 22), ui2.TextStyle{
						color: status_color(d.status)
						size:  12
					}),
				ui2.label('', d.speed, ui2.rect(col_speed - main_x - 12, 16, 110, 22),
					ui2.TextStyle{
						color:       c_text
						size:        12
						font_family: 'Consolas'
					}),
				ui2.label('', d.eta, ui2.rect(col_eta - main_x - 12, 16, 90, 22), ui2.TextStyle{
					color:       c_muted
					size:        12
					font_family: 'Consolas'
				}),
			])
		}
		children << ui2.scroll('queue', ui2.rect(main_x + 12, list_y, main_w - 24, list_h),
			c_bg, items)
		if rows.len > shown {
			children << ui2.label('', 'showing ${shown}/${rows.len}', ui2.rect(col_name,
				list_y + list_h + 2, 220, 18), tmuted(11))
		}
	}

	// ---- bottom panel ----
	bottom_y := h - bottom_h - status_h
	children << ui2.view('bottombar', ui2.rect(main_x, bottom_y, main_w, bottom_h),
		ui2.BoxStyle{ bg: c_side }, bottom_panel(s, main_w, bottom_h))

	// ---- status bar ----
	st := if s.message != '' {
		fashape.sh_auto(s.message)
	} else {
		'active ${s.num_active}  waiting ${s.num_waiting}  stopped ${s.num_stopped}  ${rows.len} shown  v' + s.down_speed + '  ^' + s.up_speed + (if s.version != '' {
			'  aria2 ' + s.version
		} else {
			''
		})
	}
	children << ui2.view('status', ui2.rect(main_x, h - status_h, main_w, status_h),
		ui2.BoxStyle{ bg: c_side }, [
			ui2.label('', st, ui2.rect(14, 6, main_w - 28, 22), ui2.TextStyle{
				color:       c_muted
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			}),
		])
	// Sidebar covers the status strip on the left.
	children << ui2.view('side_status', ui2.rect(0, h - status_h, side_w, status_h),
		ui2.BoxStyle{ bg: c_side }, [])

	if s.show_settings {
		children << settings_overlay(s, w, h)
	}
	if s.show_log {
		children << log_overlay(s, w, h)
	}

	return ui2.screen(c_bg, children)
}

// bottom_panel is the FDM-like inspector for the selected download.
fn bottom_panel(s Snapshot, w f64, h f64) []ui2.Element {
	tabs := [['tab_progress', t(s.fa, 'progress')], ['tab_files', t(s.fa, 'files')],
		['tab_details', t(s.fa, 'details_tab')]]
	mut out := []ui2.Element{}
	mut tx := 12.0
	for t in tabs {
		on := s.bottom_tab == t[0][4..]
		out << ui2.button(t[0], t[1], ui2.rect(tx, 8, 110, 30), ui2.BoxStyle{
			bg:     if on { c_bar } else { c_side }
			radius: 7
		}, ui2.TextStyle{
			color:       if on { c_text } else { c_muted }
			size:        12
			bold:        on
			font_family: if s.fa { fa_font } else { '' }
		})
		tx += 118.0
	}
	body_y := 46.0
	body_h := h - body_y - 8.0
	if s.bottom_tab == 'progress' {
		out << speed_chart(s, 12, body_y, w * 0.58, body_h)
		sx := 12.0 + w * 0.58 + 16.0
		sw := w - sx - 12.0
		sel := if s.selected == '' {
			t(s.fa, 'select_hint')
		} else {
			name := s.selected
			mut found := s.selected
			for r in s.downloads {
				if r.gid == s.selected {
					found = fashape.sh_auto(r.name)
					break
				}
			}
			_ = name
			found
		}
		out << ui2.label('', sel, ui2.rect(sx, body_y, sw, 22), ui2.TextStyle{
			color:       c_text
			size:        13
			font_family: if s.fa { fa_font } else { '' }
		})
		pct := if s.info_fresh { s.info.percent } else { 0.0 }
		out << segments(pct, sx, body_y + 28, sw)
		out << ui2.label('', if s.info_fresh {
			'${int(s.info.percent)}%  ' + s.info.done + ' / ' + s.info.total + '  ' + s.info.speed + (if s.info.connections != '' {
				'  ' + s.info.connections
			} else {
				''
			})
		} else {
			''
		}, ui2.rect(sx, body_y + 48, sw, 22), ui2.TextStyle{
			color:       c_muted
			size:        12
			font_family: 'Consolas'
		})
		out << ui2.label('', t(s.fa, 'segments'), ui2.rect(sx, body_y + 74, sw, 20), ui2.TextStyle{
			color:       c_muted
			size:        11
			font_family: if s.fa { fa_font } else { '' }
		})
	} else if s.bottom_tab == 'files' {
		if !s.info_fresh {
			out << ui2.label('', if s.selected == '' {
				t(s.fa, 'select_hint')
			} else {
				t(s.fa, 'loading')
			}, ui2.rect(12, body_y + 8, w - 24, 24), tmuted(12))
		} else if s.info.files_prog.len == 0 {
			out << ui2.label('', s.info.name, ui2.rect(12, body_y + 8, w - 24, 24),
				tfont(s.fa, 12))
		} else {
			mut items := []ui2.Element{}
			n := if s.info.files_prog.len > 14 { 14 } else { s.info.files_prog.len }
			for i in 0 .. n {
				f := s.info.files_prog[i]
				y := f64(i) * 30.0
				fw := (w - 48.0) * f.percent / 100.0
				items << ui2.view('filerow${i}', ui2.rect(0, y, w - 24, 26), ui2.BoxStyle{
					transparent: true
				}, [
					ui2.label('', fashape.sh_auto(f.path), ui2.rect(0, 0, w * 0.55, 18), ui2.TextStyle{
						color:       c_text
						size:        12
						font_family: if s.fa { fa_font } else { '' }
					}),
					ui2.view('ftrack${i}', ui2.rect(w * 0.57, 5, w * 0.25, 8), ui2.BoxStyle{
						bg:     c_line
						radius: 4
					}, [
						ui2.view('ffill${i}', ui2.rect(0, 0, fw, 8), ui2.BoxStyle{
							bg:     c_accent
							radius: 4
						}, []),
					]),
					ui2.label('', f.done + '/' + f.total, ui2.rect(w * 0.84, 0, w * 0.14,
						18), ui2.TextStyle{
						color:       c_muted
						size:        11
						font_family: 'Consolas'
					}),
				])
			}
			out << ui2.scroll('files_scroll', ui2.rect(12, body_y, w - 24, body_h), c_side,
				items)
			if s.info.files_prog.len > n {
				out << ui2.label('', '+${s.info.files_prog.len - n} more', ui2.rect(12,
					body_y + body_h - 18, 160, 18), tmuted(11))
			}
		}
	} else {
		if !s.info_fresh {
			out << ui2.label('', if s.selected == '' {
				t(s.fa, 'select_hint')
			} else {
				t(s.fa, 'loading')
			}, ui2.rect(12, body_y + 8, w - 24, 24), tmuted(12))
		} else {
			d := s.info
			mut col := []ui2.Element{}
			mut y := 0.0
			kv := [['gid', d.gid], ['status', d.status], ['dir', d.dir],
				['connections', d.connections], ['info hash', d.info_hash], ['pieces',
					if d.num_pieces > 0 { d.num_pieces.str() + ' x ' + d.piece_length } else { '' }],
				['verified', d.verified], ['seeders/leechers', if d.info_hash != '' {
					'${d.seeders}/${d.leechers}'
				} else {
					''
				}], ['mirrors live', d.live.join(', ')], ['mirrors idle', d.idle.join(', ')],
				['error', d.error]]
			for p in kv {
				if p[1] == '' {
					continue
				}
				col << ui2.label('', p[0] + ':  ' + fashape.sh_auto(p[1]), ui2.rect(0, y, w - 24, 20),
					ui2.TextStyle{
						color:       c_text
						size:        12
						font_family: if s.fa { fa_font } else { 'Consolas' }
					})
				y += 22.0
			}
			out << ui2.scroll('details_scroll', ui2.rect(12, body_y, w - 24, body_h), c_side,
				col)
		}
	}
	return out
}

// settings_overlay edits limits + files, like the web Settings dialog.
fn settings_overlay(s Snapshot, w f64, h f64) ui2.Element {
	bw := if w > 620 { 580.0 } else { w - 40.0 }
	bh := if h > 620 { 580.0 } else { h - 60.0 }
	bx := (w - bw) / 2.0
	by := (h - bh) / 2.0
	rows := [['set_max_concurrent', 'max concurrent', s.set_max_concurrent],
		['set_max_per_server', 'connections/server', s.set_max_per_server],
		['set_split', 'split', s.set_split],
		['set_download_limit', 'download limit (B/s, 0=unlimited)', s.set_download_limit],
		['set_upload_limit', 'upload limit (B/s, 0=unlimited)', s.set_upload_limit],
		['set_dir', 'download folder', s.set_dir], ['set_seed_ratio', 'seed ratio', s.set_seed_ratio],
		['set_seed_time', 'seed time (min)', s.set_seed_time]]
	mut items := []ui2.Element{}
	mut y := 52.0
	for r in rows {
		items << ui2.label('', r[1], ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{
			color: c_text
			size:  12
		})
		y += 22.0
		fw := bw - 32.0
		if r[0] == 'set_dir' {
			items << ui2.text_field(r[0], '', r[2], ui2.rect(16, y, fw - 110, 34), ui2.BoxStyle{
				bg:     c_card
				radius: 7
			}, ui2.TextStyle{
				color:       c_text
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			}, 0)
			items << ui2.button('pick_dir', t(s.fa, 'pick'), ui2.rect(16 + fw - 100, y,
				100, 34), ui2.BoxStyle{
				bg:     c_bar
				radius: 7
			}, ui2.TextStyle{
				color:       c_text
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			})
		} else {
			items << ui2.text_field(r[0], '', r[2], ui2.rect(16, y, fw, 34), ui2.BoxStyle{
				bg:     c_card
				radius: 7
			}, ui2.TextStyle{
				color:       c_text
				size:        12
				font_family: if s.fa { fa_font } else { '' }
			}, 0)
		}
		y += 40.0
	}
	bt := if s.set_bt { '[x] BitTorrent (dht/pex)' } else { '[ ] BitTorrent (dht/pex)' }
	ss := if s.set_save_session {
		'[x] remember queue across restarts'
	} else {
		'[ ] remember queue across restarts'
	}
	items << ui2.button('toggle_bt', bt, ui2.rect(16, y, bw - 32, 32), ui2.BoxStyle{
		bg:     c_card
		radius: 7
	}, ui2.TextStyle{
		color: c_text
		size:  12
	})
	y += 38.0
	items << ui2.button('toggle_save_session', ss, ui2.rect(16, y, bw - 32, 32), ui2.BoxStyle{
		bg:     c_card
		radius: 7
	}, ui2.TextStyle{
		color: c_text
		size:  12
	})
	y += 38.0
	items << ui2.label('', s.set_path, ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{
		color:       c_muted
		size:        11
		font_family: 'Consolas'
	})
	return ui2.view('settings_overlay', ui2.rect(bx, by, bw, bh), ui2.BoxStyle{
		bg:            u32(0x232830)
		radius:        12
		border_color:  c_accent
		border_left:   2
		border_top:    2
		border_right:  2
		border_bottom: 2
	}, [
		ui2.label('', t(s.fa, 'settings'), ui2.rect(16, 10, bw - 220, 30), ui2.TextStyle{
			color:       c_text
			size:        16
			bold:        true
			font_family: if s.fa { fa_font } else { '' }
		}),
		ui2.button('close_settings', t(s.fa, 'close'), ui2.rect(bw - 204, 10, 90, 30),
			ui2.BoxStyle{
				bg:     c_bar
				radius: 7
			}, ui2.TextStyle{
				color: c_text
				size:  12
			}),
		ui2.button('save_settings', t(s.fa, 'save'), ui2.rect(bw - 104, 10, 90, 30),
			ui2.BoxStyle{
				bg:     c_accent
				radius: 7
			}, ui2.TextStyle{ color: u32(0xFFFFFF), size: 12 }),
		ui2.scroll('settings_scroll', ui2.rect(0, 46, bw, bh - 56), u32(0x232830), items),
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
		items << ui2.label('', fashape.sh_auto(n), ui2.rect(16, y, bw - 32, 20), ui2.TextStyle{
			color:       c_text
			size:        12
			font_family: if s.fa { fa_font } else { '' }
		})
		y += 22.0
	}
	if s.logs_dropped > 0 {
		items << ui2.label('', '... ${s.logs_dropped} lines dropped ...', ui2.rect(16, y,
			bw - 32, 20), tmuted(11))
		y += 22.0
	}
	for l in s.logs {
		items << ui2.label('', l, ui2.rect(16, y, bw - 32, 18), ui2.TextStyle{
			color:       c_muted
			size:        11
			font_family: 'Consolas'
		})
		y += 20.0
	}
	return ui2.view('log_overlay', ui2.rect(bx, by, bw, bh), ui2.BoxStyle{
		bg:            u32(0x0B1220)
		radius:        12
		border_color:  c_accent
		border_left:   2
		border_top:    2
		border_right:  2
		border_bottom: 2
	}, [
		ui2.label('', t(s.fa, 'log'), ui2.rect(16, 10, bw - 320, 30), ui2.TextStyle{
			color: c_text
			size:  16
			bold:  true
		}),
		ui2.button('clear_notices', t(s.fa, 'clear'), ui2.rect(bw - 204, 10, 90, 30),
			ui2.BoxStyle{
				bg:     c_bar
				radius: 7
			}, ui2.TextStyle{
				color: c_text
				size:  12
			}),
		ui2.button('close_log', t(s.fa, 'close'), ui2.rect(bw - 104, 10, 90, 30),
			ui2.BoxStyle{
				bg:     c_accent
				radius: 7
			}, ui2.TextStyle{ color: u32(0xFFFFFF), size: 12 }),
		ui2.scroll('log_scroll', ui2.rect(0, 46, bw, bh - 56), u32(0x0B1220), items),
	])
}

// handle_event routes one ui2 action id to an App action. Returns true when
// the view should rebuild (almost always).
pub fn handle_event(mut a &App, event string) bool {
	match event {
		'add', 'add_top' {
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
			a.set_bottom_tab('details')
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
		'tab_progress' {
			a.set_bottom_tab('progress')
			return true
		}
		'tab_files' {
			a.set_bottom_tab('files')
			a.open_detail()
			return true
		}
		'tab_details' {
			a.set_bottom_tab('details')
			a.open_detail()
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
			if event == 'nav_all' {
				a.set_filter('all')
				return true
			}
			if event == 'nav_downloading' {
				a.set_filter('downloading')
				return true
			}
			if event == 'nav_paused' {
				a.set_filter('paused')
				return true
			}
			if event == 'nav_finished' {
				a.set_filter('done')
				return true
			}
			if event.starts_with('kind_') {
				a.set_filter('kind:' + event[5..])
				return true
			}
			return false
		}
	}
}
