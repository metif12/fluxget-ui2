// app.v — Fluxget-ui2 application object (custom-renderer build).
//
// This is the ui2 counterpart of fluxget/platform/{app,control,settings_cmd,
// details}.v, without any vails or webview knowledge. It owns:
//   * core.State (shared engine state, with its own lock)
//   * store.Settings (user preferences, persisted like the original)
//   * a UI cache guarded by mu, so the background ticker and the ui2 UI
//     thread never race.
//
// Threading mirrors the original design: the ticker polls the engine about
// once per second (core.State.poll does the restart policy, the diff and the
// notice queue), copies the result into the UI cache, and calls
// ui2.request_refresh. No handler sleeps, no background thread touches ui2.
module app

import aria2ctl
import core
import engine
import os
import rpc
import store
import sync
import strconv
import ui2

// UiDownload is one row the window shows. Rendered strings come from engine/
// (rate_text/size_text/eta_text) so the native window and the web UI can never
// disagree about what "1.4 MiB/s" means.
pub struct UiDownload {
pub:
	gid     string
	name    string
	status  string
	percent f64
	speed   string
	total   string
	done    string
	eta     string
	dir     string
	err     string
}

// Detail is everything a row is not: the on-demand record for one download.
// Same shape as platform.Detail in the web UI, minus the JSON wire.
pub struct Detail {
pub mut:
	gid          string
	name         string
	status       string
	percent      f64
	total        string
	done         string
	speed        string
	upload       string
	uploaded     string
	eta          string
	dir          string
	connections  string
	error        string
	info_hash    string
	num_pieces   int
	piece_length string
	verified     string
	seeders      int
	leechers     int
	trackers     []string
	files        []string
	uris         []string
	live         []string
	idle         []string
}

// Snapshot is a copy of everything the view needs, taken under the lock so
// the view builds without holding it.
pub struct Snapshot {
pub:
	downloads          []UiDownload
	down_speed         string
	up_speed           string
	num_active         int
	num_waiting        int
	num_stopped        int
	phase              string
	detail             string
	version            string
	message            string
	selected           string
	count_total        int
	fa                 bool
	search             string
	filter             string
	show_settings      bool
	show_detail        bool
	show_log           bool
	info               Detail
	set_max_concurrent string
	set_max_per_server string
	set_split          string
	set_download_limit string
	set_upload_limit   string
	set_dir            string
	set_seed_ratio     string
	set_seed_time      string
	set_bt             bool
	set_save_session   bool
	set_path           string
	set_notes          []string
	notices            []string
	logs               []string
	logs_dropped       int
	hist_labels        []string
	hist_down          []f64
	hist_up            []f64
}

@[heap]
pub struct App {
pub mut:
	state          &core.State
	settings       store.Settings
	settings_path  string
	settings_notes []string
	mu             &sync.Mutex
	downloads      []UiDownload
	down_raw       i64
	up_raw         i64
	down_speed     string
	up_speed       string
	num_active     int
	num_waiting    int
	num_stopped    int
	phase          string = 'never-started'
	detail         string
	version        string
	message        string
	selected       string
	fa             bool = true
	search         string
	filter         string = 'all'
	show_settings  bool
	show_detail    bool
	show_log       bool
	info           Detail
	info_gid       string
	notices        []string
	logs           []string
	logs_dropped   int
	down_hist      []f64
	up_hist        []f64
	hist_n         int
	started        bool
}

// max_hist is how many speed samples the chart keeps (about 3 minutes).
pub const max_hist = 90

// max_notices bounds the in-memory notice list.
pub const max_notices = 20

pub fn new_app(root string) &App {
	mut c := core.Config{
		root: root
		port: aria2ctl.default_rpc_port
	}
	if p := os.getenv_opt('FLUXGET_RPC_PORT') {
		n := strconv.atoi(p) or { 0 }
		if n > 0 && n < 65536 {
			c.port = n
		}
	}
	if p := os.getenv_opt('FLUXGET_ARIA2') {
		if p != '' {
			c.aria2_path = p
		}
	}
	if probe := os.getenv_opt('FLUXGET_PROBE') {
		if probe != '' {
			c.probe_url = probe
		}
	}
	settings_path := store.default_path()
	loaded, notes := store.load(settings_path)
	mut a := &App{
		state:          core.new_state(c)
		settings:       loaded
		settings_path:  settings_path
		settings_notes: notes
		mu:             sync.new_mutex()
		fa:             true
	}
	if notes.len > 0 {
		a.message = notes.join('; ')
	}
	return a
}

// ---- engine lifecycle ----

pub fn (mut a App) start_engine() {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.start_engine() or {
		a.set_cache(phase_from_state(mut a.state), err.msg(), []UiDownload{}, rpc.Snapshot{})
		return
	}
	a.state.seed_probe()
	a.started = true
	// Same code path as a user edit: the running engine must hold what the
	// document says, from the first minute on.
	a.push_settings_locked()
}

pub fn (mut a App) stop_engine() {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.stop_engine()
}

// phase_from_state reads the supervisor phase. Callers must hold the lock.
fn phase_from_state(mut s core.State) string {
	mut sup := s.sup or { return 'never-started' }
	return sup.phase.label()
}

// set_cache writes the UI cache. Callers hold the state lock; this takes mu.
fn (mut a App) set_cache(phase string, detail string, rows []UiDownload, snap rpc.Snapshot) {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.phase = phase
	a.detail = detail
	a.downloads = rows
	if phase == 'ready' {
		a.num_active = snap.stat.num_active
		a.num_waiting = snap.stat.num_waiting
		a.num_stopped = snap.stat.num_stopped
		a.down_speed = engine.rate_text(snap.stat.download_speed)
		a.up_speed = engine.rate_text(snap.stat.upload_speed)
		push_hist(mut a.down_hist, f64(snap.stat.download_speed) / 1024.0)
		push_hist(mut a.up_hist, f64(snap.stat.upload_speed) / 1024.0)
		a.hist_n++
	}
}

fn push_hist(mut h []f64, v f64) {
	h << v
	if h.len > max_hist {
		h = h[h.len - max_hist..].clone()
	}
}

// tick_once is the background heartbeat: poll, diff, publish. It never
// touches ui2; the caller calls ui2.request_refresh.
pub fn (mut a App) tick_once() {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	if !a.started {
		ph := phase_from_state(mut a.state)
		detail := if ph == 'never-started' { 'starting the engine...' } else { '' }
		a.set_cache(ph, detail, []UiDownload{}, rpc.Snapshot{})
		return
	}
	view_phase := phase_from_state(mut a.state)
	res := a.state.poll()
	mut logs := []string{}
	mut dropped := 0
	mut sup := a.state.sup
	if sup != none {
		logs = sup.ring.lines()
		dropped = sup.ring.how_many_dropped()
		if logs.len > 40 {
			logs = logs[logs.len - 40..].clone()
		}
	}
	all := res.snap.all()
	mut rows := []UiDownload{cap: all.len}
	for s in all {
		eta := if s.is_finished() { '' } else { engine.eta_text(s.eta_seconds()) }
		rows << UiDownload{
			gid:     s.gid
			name:    s.display_name('')
			status:  s.status
			percent: s.percent()
			speed:   engine.rate_text(s.download_speed)
			total:   engine.size_text(s.total_length)
			done:    engine.size_text(s.completed_length)
			eta:     eta
			dir:     s.dir
			err:     s.error
		}
	}
	detail := res.detail
	a.set_cache(view_phase, detail, rows, res.snap)
	a.mu.lock()
	if res.notices.len > 0 {
		for n in res.notices {
			a.notices << n.text
		}
		if a.notices.len > max_notices {
			a.notices = a.notices[a.notices.len - max_notices..].clone()
		}
		a.message = res.notices[res.notices.len - 1].text
	}
	a.logs = logs
	a.logs_dropped = dropped
	if a.selected != '' {
		mut found := false
		for r in rows {
			if r.gid == a.selected {
				found = true
				break
			}
		}
		if !found {
			a.selected = ''
			a.show_detail = false
		}
	}
	// Refresh the open detail record live while it is visible.
	if a.show_detail && a.info_gid != '' {
		a.mu.unlock()
		d := a.fetch_detail(a.info_gid)
		a.mu.lock()
		a.info = d
	}
	a.mu.unlock()
	if a.version == '' {
		if ver := a.state.eng.client.version() {
			a.mu.lock()
			a.version = ver.version
			a.mu.unlock()
		}
	}
}

// snapshot copies the UI cache for the view thread.
pub fn (a &App) snapshot() Snapshot {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	mut labels := []string{cap: a.down_hist.len}
	for i in 0 .. a.down_hist.len {
		labels << '${i - a.down_hist.len + 1}'
	}
	return Snapshot{
		downloads:          a.downloads.clone()
		down_speed:         a.down_speed
		up_speed:           a.up_speed
		num_active:         a.num_active
		num_waiting:        a.num_waiting
		num_stopped:        a.num_stopped
		phase:              a.phase
		detail:             a.detail
		version:            a.version
		message:            a.message
		selected:           a.selected
		count_total:        a.num_active + a.num_waiting + a.num_stopped
		fa:                 a.fa
		search:             a.search
		filter:             a.filter
		show_settings:      a.show_settings
		show_detail:        a.show_detail
		show_log:           a.show_log
		info:               a.info
		set_max_concurrent: a.settings.max_concurrent.str()
		set_max_per_server: a.settings.max_per_server.str()
		set_split:          a.settings.split.str()
		set_download_limit: a.settings.download_limit.str()
		set_upload_limit:   a.settings.upload_limit.str()
		set_dir:            a.settings.dir
		set_seed_ratio:     a.settings.seed_ratio
		set_seed_time:      a.settings.seed_time
		set_bt:             a.settings.bt_enabled
		set_save_session:   a.settings.save_session
		set_path:           a.settings_path
		set_notes:          a.settings_notes.clone()
		notices:            a.notices.clone()
		logs:               a.logs.clone()
		logs_dropped:       a.logs_dropped
		hist_labels:        labels
		hist_down:          a.down_hist.clone()
		hist_up:            a.up_hist.clone()
	}
}

// ---- filtering (pure, tested) ----

// matches_filter reports whether a row belongs to a status view and a query.
// The query matches name, gid, dir and aria2's error text, like the web UI.
pub fn matches_filter(d UiDownload, filter string, query string) bool {
	if filter == 'active' && d.status != 'active' {
		return false
	}
	if filter == 'waiting' && d.status != 'waiting' {
		return false
	}
	if filter == 'paused' && d.status != 'paused' {
		return false
	}
	if filter == 'done' && !(d.status == 'complete' || d.status == 'error' || d.status == 'removed') {
		return false
	}
	q := query.trim_space().to_lower()
	if q == '' {
		return true
	}
	return d.name.to_lower().contains(q) || d.gid.to_lower().contains(q)
		|| d.dir.to_lower().contains(q) || d.err.to_lower().contains(q)
}

// visible_rows applies the current filter and search to the cached queue.
pub fn (a &App) visible_rows() []UiDownload {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	return a.downloads.filter(matches_filter(it, a.filter, a.search))
}

// ---- actions (called from the ui2 event handler, on the UI thread) ----

pub fn (mut a App) set_message(s string) {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.message = s
}

pub fn (mut a App) toggle_lang() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.fa = !a.fa
}

pub fn (mut a App) select(gid string) {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.selected = gid
}

pub fn (mut a App) set_search(q string) {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.search = q
}

pub fn (mut a App) set_filter(f string) {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.filter = f
}

fn (mut a App) selected_gid() string {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	return a.selected
}

pub fn (mut a App) add(url string) {
	u := url.trim_space()
	if u == '' {
		a.set_message(if a.fa { 'نشانی خالی است' } else { 'empty URL' })
		return
	}
	a.state.lock()
	defer {
		a.state.unlock()
	}
	gid := a.state.eng.add(engine.AddRequest{
		uris: [u]
	}) or {
		a.mu.lock()
		a.message = 'add: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.state.remember(gid, [u])
	a.mu.lock()
	a.message = if a.fa { 'افزوده شد' } else { 'added' }
	a.selected = gid
	a.mu.unlock()
}

pub fn (mut a App) pause_selected() {
	gid := a.selected_gid()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.pause(gid) or {
		a.mu.lock()
		a.message = 'pause: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.mu.lock()
	a.message = 'pause OK'
	a.mu.unlock()
}

pub fn (mut a App) resume_selected() {
	gid := a.selected_gid()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.resume(gid) or {
		a.mu.lock()
		a.message = 'resume: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.mu.lock()
	a.message = 'resume OK'
	a.mu.unlock()
}

pub fn (mut a App) remove_selected() {
	mut gid := ''
	a.mu.lock()
	gid = a.selected
	a.mu.unlock()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.remove(gid) or {
		a.mu.lock()
		a.message = 'remove: ' + err.msg()
		a.mu.unlock()
		return
	}
	// Best effort: drop the history record too, like the web UI's remove.
	a.state.eng.forget(gid) or {}
	a.mu.lock()
	a.message = if a.fa { 'حذف شد' } else { 'removed' }
	a.selected = ''
	a.show_detail = false
	a.mu.unlock()
}

pub fn (mut a App) retry_selected() {
	mut gid := ''
	a.mu.lock()
	gid = a.selected
	a.mu.unlock()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	a.state.lock()
	defer {
		a.state.unlock()
	}
	remembered := a.state.remembered(gid)
	new_gid := a.state.eng.retry(gid, remembered) or {
		a.mu.lock()
		a.message = 'retry: ' + err.msg()
		a.mu.unlock()
		return
	}
	_ = new_gid
	a.mu.lock()
	a.message = if a.fa { 'تلاش دوباره' } else { 'retrying' }
	a.mu.unlock()
}

pub fn (mut a App) move_selected(delta int) {
	gid := a.selected_gid()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	if delta == 0 {
		return
	}
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.move(gid, delta, engine.pos_cur) or {
		a.mu.lock()
		a.message = 'move: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.mu.lock()
	a.message = if a.fa { 'جابه‌جا شد' } else { 'moved' }
	a.mu.unlock()
}

pub fn (mut a App) copy_selected() {
	gid := a.selected_gid()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	if ui2.set_clipboard_text(gid) {
		a.set_message('copied GID')
	} else {
		a.set_message(if a.fa {
			'کلیپ‌برد در دسترس نیست'
		} else {
			'no clipboard here'
		})
	}
}

pub fn (mut a App) pause_all() {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.pause_all() or {
		a.mu.lock()
		a.message = 'pause all: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.mu.lock()
	a.message = if a.fa { 'همه متوقف شد' } else { 'paused all' }
	a.mu.unlock()
}

pub fn (mut a App) resume_all() {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.resume_all() or {
		a.mu.lock()
		a.message = 'resume all: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.mu.lock()
	a.message = if a.fa { 'همه ادامه یافت' } else { 'resumed all' }
	a.mu.unlock()
}

pub fn (mut a App) forget_all() {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	a.state.eng.client.purge_results() or {
		a.mu.lock()
		a.message = 'forget all: ' + err.msg()
		a.mu.unlock()
		return
	}
	a.mu.lock()
	a.message = if a.fa { 'تاریخچه پاک شد' } else { 'history cleared' }
	a.mu.unlock()
}

// ---- detail (on demand, like fluxget.details) ----

pub fn (mut a App) open_detail() {
	gid := a.selected_gid()
	if gid == '' {
		a.set_message(if a.fa {
			'اول یک دانلود را انتخاب کن'
		} else {
			'select a download first'
		})
		return
	}
	d := a.fetch_detail(gid)
	a.mu.lock()
	a.info = d
	a.info_gid = gid
	a.show_detail = true
	a.mu.unlock()
}

pub fn (mut a App) close_detail() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.show_detail = false
}

// fetch_detail reads tellStatus + files + trackers + mirror state. Each extra
// call may fail independently (HTTP rows have no trackers, magnets may have no
// files yet) and yields emptiness, never a blank dialog.
fn (mut a App) fetch_detail(gid string) Detail {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	s := a.state.eng.client.tell_status(gid, []) or {
		return Detail{
			gid:   gid
			name:  gid
			error: err.msg()
		}
	}
	mut d := Detail{
		gid:         s.gid
		name:        s.display_name('')
		status:      s.status
		percent:     s.percent()
		total:       engine.size_text(s.total_length)
		done:        engine.size_text(s.completed_length)
		speed:       engine.rate_text(s.download_speed)
		upload:      engine.rate_text(s.upload_speed)
		uploaded:    engine.size_text(s.upload_length)
		eta:         if s.is_finished() { '' } else { engine.eta_text(s.eta_seconds()) }
		dir:         s.dir
		connections: if s.connections > 0 { '${s.connections} in use' } else { '' }
		error:       s.error
	}
	if s.piece_length > 0 {
		d.piece_length = engine.size_text(s.piece_length)
	}
	d.num_pieces = s.num_pieces
	if s.verified_length > 0 {
		d.verified = engine.size_text(s.verified_length)
	}
	if s.is_torrent() {
		d.info_hash = s.info_hash
		d.seeders = s.num_seeders
		d.leechers = s.num_leechers
		for t in a.state.eng.client.get_trackers(gid) or { []rpc.Tracker{} } {
			if t.uri != '' {
				d.trackers << t.uri
			}
		}
	}
	for f in a.state.eng.client.get_files(gid) or { []rpc.FileEntry{} } {
		if f.path != '' {
			d.files << f.path
		}
	}
	set := engine.mirror_set_from(a.state.remembered(gid)) or { engine.MirrorSet{} }
	for m in set.uris {
		d.uris << m
	}
	for m in (a.state.eng.mirror_state(gid, set.uris) or { []engine.Mirror{} }) {
		if m.in_use {
			d.live << m.uri
		} else {
			d.idle << m.uri
		}
	}
	return d
}

// ---- settings (like fluxget.set_settings: clamp, push, report, save) ----

pub fn (mut a App) open_settings() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.show_settings = true
}

pub fn (mut a App) close_settings() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.show_settings = false
}

pub fn (mut a App) toggle_bt() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.settings.bt_enabled = !a.settings.bt_enabled
}

pub fn (mut a App) toggle_save_session() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.settings.save_session = !a.settings.save_session
}

pub fn (mut a App) pick_dir() {
	cur := a.snapshot().set_dir
	paths := ui2.open_folder_dialog(ui2.FileDialogConfig{
		title:     'Download folder'
		directory: cur
	})
	if paths.len == 0 {
		return
	}
	a.mu.lock()
	a.settings.dir = paths[0]
	a.mu.unlock()
	a.set_message(if a.fa { 'پوشه انتخاب شد' } else { 'folder picked' })
}

// save_settings_from reads the settings fields, clamps, pushes to the engine,
// rewrites from what aria2 actually holds on refusal, and persists.
pub fn (mut a App) save_settings_from(max_concurrent string, max_per_server string, split string, download_limit string, upload_limit string, dir string, seed_ratio string, seed_time string) {
	a.mu.lock()
	mut wanted := a.settings
	if n := strconv.atoi(max_concurrent.trim_space()) {
		wanted.max_concurrent = n
	}
	if n := strconv.atoi(max_per_server.trim_space()) {
		wanted.max_per_server = n
	}
	if n := strconv.atoi(split.trim_space()) {
		wanted.split = n
	}
	if n := strconv.atoi(download_limit.trim_space()) {
		wanted.download_limit = n
	}
	if n := strconv.atoi(upload_limit.trim_space()) {
		wanted.upload_limit = n
	}
	wanted.dir = dir.trim_space()
	if seed_ratio.trim_space() != '' {
		wanted.seed_ratio = seed_ratio.trim_space()
	}
	if seed_time.trim_space() != '' {
		wanted.seed_time = seed_time.trim_space()
	}
	mut corrections := wanted.normalise()
	a.settings = wanted
	a.mu.unlock()
	rejected := a.push_settings() or {
		a.set_message('settings: ' + err.msg())
		return
	}
	a.mu.lock()
	if rejected.len > 0 {
		for k, v in rejected {
			corrections << '${k}: aria2 refused (${v})'
		}
		if actual := a.read_back_settings() {
			a.settings = actual
		}
	}
	a.settings.save(a.settings_path) or {
		a.mu.unlock()
		a.set_message('settings: ' + err.msg())
		return
	}
	a.settings_notes = corrections
	a.show_settings = false
	a.message = if corrections.len == 0 {
		if a.fa { 'تنظیمات ذخیره شد' } else { 'settings saved' }
	} else {
		corrections.join('; ')
	}
	a.mu.unlock()
}

// push_settings sends the document to the engine. It owns the state lock.
fn (mut a App) push_settings() !map[string]string {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	raw := a.state.eng.client.change_global_option(a.settings.to_aria2()) or {
		return error(err.msg())
	}
	return rpc.refused_options(raw)
}

// push_settings_locked is push_settings for callers already holding the lock.
fn (mut a App) push_settings_locked() {
	raw := a.state.eng.client.change_global_option(a.settings.to_aria2()) or { return }
	_ = raw
}

// read_back_settings maps what aria2 echoes onto our document, keeping the
// current value for any key the engine does not echo (non-destructive).
fn (mut a App) read_back_settings() ?store.Settings {
	a.state.lock()
	defer {
		a.state.unlock()
	}
	opts := a.state.eng.client.get_global_option() or { return none }
	mut s := a.settings
	s.max_concurrent = int_or(s.max_concurrent, opts['max-concurrent-downloads'] or { '' })
	s.max_per_server = int_or(s.max_per_server, opts['max-connection-per-server'] or { '' })
	s.download_limit = int_or(s.download_limit, opts['max-download-limit'] or { '' })
	s.upload_limit = int_or(s.upload_limit, opts['max-upload-limit'] or { '' })
	s.split = int_or(s.split, opts['split'] or { '' })
	s.seed_ratio = opts['seed-ratio'] or { s.seed_ratio }
	s.seed_time = opts['seed-time'] or { s.seed_time }
	return s
}

fn int_or(current int, v string) int {
	if v == '' {
		return current
	}
	return strconv.atoi(v) or { current }
}

// ---- log / notices ----

pub fn (mut a App) open_log() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.show_log = true
}

pub fn (mut a App) close_log() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.show_log = false
}

pub fn (mut a App) clear_notices() {
	a.mu.lock()
	defer {
		a.mu.unlock()
	}
	a.notices = []string{}
	a.message = ''
}

// tr is the tiny locale helper. fa is the default (like the web UI).
pub fn tr(fa bool, key string) string {
	if fa {
		return match key {
			'add' { 'افزودن' }
			'url_hint' { 'نشانی، مگنت یا مسیر تورنت…' }
			'search_hint' { 'جست‌وجو در صف…' }
			'search' { 'جست‌وجو' }
			'clear' { 'پاک' }
			'pause' { 'توقف' }
			'resume' { 'ادامه' }
			'remove' { 'حذف' }
			'retry' { 'تلاش دوباره' }
			'details' { 'جزئیات' }
			'copy' { 'کپی GID' }
			'up' { '↑' }
			'down' { '↓' }
			'pause_all' { 'توقف همه' }
			'resume_all' { 'ادامه همه' }
			'forget_all' { 'پاک‌سازی تاریخچه' }
			'settings' { 'تنظیمات' }
			'log' { 'گزارش' }
			'lang' { 'English' }
			'empty' { 'صفی خالی است — یک نشانی بالا اضافه کن' }
			'needs_engine' { 'موتور آماده نیست' }
			'all' { 'همه' }
			'active' { 'در حال دانلود' }
			'waiting' { 'در صف' }
			'paused' { 'متوقف' }
			'done' { 'تمام‌شده' }
			'speed' { 'سرعت (KiB/s)' }
			'close' { 'بستن' }
			'save' { 'ذخیره' }
			'pick' { 'انتخاب…' }
			else { key }
		}
	}
	return match key {
		'add' { 'Add' }
		'url_hint' { 'URL, magnet or .torrent path…' }
		'search_hint' { 'Search the queue…' }
		'search' { 'Search' }
		'clear' { 'Clear' }
		'pause' { 'Pause' }
		'resume' { 'Resume' }
		'remove' { 'Remove' }
		'retry' { 'Retry' }
		'details' { 'Details' }
		'copy' { 'Copy GID' }
		'up' { 'Up' }
		'down' { 'Down' }
		'pause_all' { 'Pause all' }
		'resume_all' { 'Resume all' }
		'forget_all' { 'Clear history' }
		'settings' { 'Settings' }
		'log' { 'Log' }
		'lang' { 'فارسی' }
		'empty' { 'Queue is empty — add a URL above' }
		'needs_engine' { 'engine not ready' }
		'all' { 'All' }
		'active' { 'Active' }
		'waiting' { 'Waiting' }
		'paused' { 'Paused' }
		'done' { 'Done' }
		'speed' { 'Speed (KiB/s)' }
		'close' { 'Close' }
		'save' { 'Save' }
		'pick' { 'Pick…' }
		else { key }
	}
}
