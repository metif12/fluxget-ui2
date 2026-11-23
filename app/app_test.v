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
		'forget_all', 'settings', 'log', 'search', 'clear', 'close', 'save', 'progress', 'files',
		'all', 'downloading', 'paused', 'finished', 'video', 'torrents']
	for k in keys {
		assert tr(true, k) != k, 'missing fa: ' + k
		assert tr(false, k) != k, 'missing en: ' + k
	}
}

fn test_file_kind_by_extension() {
	assert file_kind('movie.mkv') == 'video'
	assert file_kind('song.FLAC') == 'audio'
	assert file_kind('book.pdf') == 'documents'
	assert file_kind('setup.exe') == 'programs'
	assert file_kind('data.zip') == 'archives'
	assert file_kind('x.torrent') == 'torrents'
	assert file_kind('README') == 'other'
	assert file_kind('magnet:?xt=urn:btih:abc') == 'other'
}

fn test_filter_downloading_covers_active_and_waiting() {
	for st in ['active', 'waiting'] {
		d := UiDownload{
			status: st
			name:   'x'
		}
		assert matches_filter(d, 'downloading', '') == true, st
		assert matches_filter(d, 'paused', '') == false, st
	}
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

fn test_filter_kind_prefix() {
	d := UiDownload{
		status: 'active'
		name:   'movie.mkv'
		kind:   'video'
	}
	assert matches_filter(d, 'kind:video', '') == true
	assert matches_filter(d, 'kind:audio', '') == false
	assert matches_filter(d, 'all', '') == true
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

fn test_count_kind() {
	rows := [
		UiDownload{ kind: 'video', name: 'a' },
		UiDownload{ kind: 'video', name: 'b' },
		UiDownload{ kind: 'audio', name: 'c' },
	]
	assert count_kind(rows, 'video') == 2
	assert count_kind(rows, 'audio') == 1
	assert count_kind(rows, 'torrents') == 0
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

fn test_nav_events_set_filters() {
	mut a := new_app_for_test()
	assert handle_event(mut a, 'nav_finished') == true
	assert a.snapshot().filter == 'done'
	assert handle_event(mut a, 'kind_video') == true
	assert a.snapshot().filter == 'kind:video'
}

fn test_tab_events_set_bottom_tab() {
	mut a := new_app_for_test()
	assert handle_event(mut a, 'tab_files') == true
	assert a.snapshot().bottom_tab == 'files'
}

fn test_toggle_lang_flips() {
	mut a := new_app_for_test()
	before := a.snapshot().fa
	assert handle_event(mut a, 'lang') == true
	assert a.snapshot().fa == !before
}

fn test_build_screen_has_sidebar_toolbar_and_status() {
	mut a := new_app_for_test()
	el := build_screen(a.snapshot())
	// sidebar + toolbar + add + status + side_status at minimum.
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
		kind:    'archives'
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
