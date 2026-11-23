// app_test.v — pure tests for the ui2 App: no window, no network.
module app

import core
import store
import sync

fn test_tr_fa_add_is_persian() {
	assert tr(true, 'add') == 'افزودن'
}

fn test_tr_en_add_is_english() {
	assert tr(false, 'add') == 'Add'
}

fn test_tr_has_every_action_key_in_both_locales() {
	keys := ['add', 'pause', 'resume', 'remove', 'retry', 'details', 'copy', 'pause_all', 'resume_all',
		'forget_all', 'settings', 'log', 'search', 'clear', 'close', 'save']
	for k in keys {
		assert tr(true, k) != k, 'missing fa: ' + k
		assert tr(false, k) != k, 'missing en: ' + k
	}
}

fn test_filter_all_passes_everything() {
	d := UiDownload{
		gid:    'abc'
		name:   'file.iso'
		status: 'active'
	}
	assert matches_filter(d, 'all', '') == true
	assert matches_filter(d, 'active', '') == true
	assert matches_filter(d, 'waiting', '') == false
	assert matches_filter(d, 'done', '') == false
}

fn test_filter_done_covers_terminal_states() {
	for st in ['complete', 'error', 'removed'] {
		d := UiDownload{
			status: st
			name:   'x'
		}
		assert matches_filter(d, 'done', '') == true, st
		assert matches_filter(d, 'paused', '') == false, st
	}
}

fn test_query_matches_name_gid_dir_and_error() {
	d := UiDownload{
		gid:    'a1b2c3'
		name:   'Ubuntu.iso'
		dir:    '/dl/linux'
		status: 'error'
		err:    'Got EOF from the server.'
	}
	assert matches_filter(d, 'all', 'ubuntu') == true
	assert matches_filter(d, 'all', 'A1B2') == true
	assert matches_filter(d, 'all', 'linux') == true
	assert matches_filter(d, 'all', 'eof') == true
	assert matches_filter(d, 'all', 'windows') == false
}

fn test_push_hist_caps_at_max_hist() {
	mut h := []f64{}
	for i in 0 .. max_hist + 10 {
		push_hist(mut h, f64(i))
	}
	assert h.len == max_hist
	assert h[0] == 10.0
}

fn test_handle_unknown_event_returns_false() {
	mut a := new_app_for_test()
	assert handle_event(mut a, 'no_such_button') == false
}

fn test_select_sets_selected_and_returns_true() {
	mut a := new_app_for_test()
	assert handle_event(mut a, 'sel_abc123') == true
	assert a.snapshot().selected == 'abc123'
}

fn test_filter_event_sets_filter() {
	mut a := new_app_for_test()
	assert handle_event(mut a, 'filter_paused') == true
	assert a.snapshot().filter == 'paused'
}

fn test_toggle_lang_flips() {
	mut a := new_app_for_test()
	before := a.snapshot().fa
	assert handle_event(mut a, 'lang') == true
	assert a.snapshot().fa == !before
}

fn test_build_screen_has_header_add_and_status() {
	mut a := new_app_for_test()
	el := build_screen(a.snapshot())
	// header + add + ops + search + statusbar at minimum, even with no rows.
	assert el.children.len >= 5
}

fn test_build_screen_with_rows_and_history() {
	mut a := new_app_for_test()
	a.downloads << UiDownload{
		gid:     'g1'
		name:    'f.iso'
		status:  'active'
		percent: 42.0
		speed:   '1.0 MiB/s'
		total:   '10 MiB'
		done:    '4.2 MiB'
	}
	for i in 0 .. 5 {
		push_hist(mut a.down_hist, f64(i))
		push_hist(mut a.up_hist, f64(i) / 2.0)
	}
	el := build_screen(a.snapshot())
	assert el.children.len >= 6
}

// new_app_for_test builds an App without touching disk or network.
fn new_app_for_test() &App {
	return &App{
		state:         core.new_state(core.Config{})
		settings:      store.defaults()
		settings_path: ':memory:'
		mu:            sync.new_mutex()
		fa:            true
	}
}
