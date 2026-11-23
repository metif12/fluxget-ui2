// fashape.v — minimal Persian/Arabic shaping + bidi for the custom renderer.
//
// The custom renderer draws codepoints left-to-right with isolated glyphs:
// it has no HarfBuzz, no FriBidi. Persian text therefore arrives reversed
// and unjoined ("ن ا د ا ن م" instead of "نمی‌دانم"). This module fixes that
// in pure V, with no dependencies:
//
//   1. joining: every letter maps to isolated/final/initial/medial
//      presentation form by its neighbours (ZWNJ/ZWJ honoured, diacritics
//      transparent, lam-alef intentionally NOT ligated);
//   2. bidi-lite: the string splits into RTL runs and everything-else runs;
//      an RTL paragraph lays runs right-to-left, RTL runs reversed, LTR runs
//      (Latin, digits, URLs, parens travelling with their run) intact.
//
// sh_auto(s) shapes only when the string holds an RTL character, so Latin,
// numbers, paths and GIDs pass through byte-identical — it is safe to apply
// at the display boundary in view.v.
module fashape

// join classes: 0 = non-joining, 1 = right-joining (alef group), 2 = dual.
fn fa_join(cp int) int {
	match cp {
		0x627, 0x62f, 0x630, 0x631, 0x632, 0x648, 0x629, 0x649, 0x623, 0x625, 0x624 {
			return 1
		}
		0x628, 0x67e, 0x62a, 0x62b, 0x62c, 0x686, 0x62d, 0x62e, 0x633, 0x634, 0x635,
		0x636, 0x637, 0x638, 0x639, 0x63a, 0x641, 0x642, 0x643, 0x6a9, 0x6af, 0x644,
		0x645, 0x646, 0x647, 0x6cc, 0x626, 0x640 {
			return 2
		}
		0x64b, 0x64c, 0x64d, 0x64e, 0x64f, 0x650, 0x651, 0x652, 0x670 {
			return 3
		}
		else {
			return 0
		}
	}
}

// fa_form returns the presentation form for a letter: pos 0 = isolated,
// 1 = final, 2 = initial, 3 = medial. Non-letters map to themselves.
fn fa_form(cp int, pos int) int {
	if pos == 0 {
		return cp
	}
	match cp {
		0x627 {
			return if pos == 1 { 0xfe8e } else { cp }
		}
		0x628 {
			return [0xfe8f, 0xfe90, 0xfe91, 0xfe92][pos]
		}
		0x67e {
			return [0x67e, 0xfb57, 0xfb58, 0xfb59][pos]
		}
		0x62a {
			return [0x62a, 0xfe96, 0xfe97, 0xfe98][pos]
		}
		0x62b {
			return [0x62b, 0xfe9a, 0xfe9b, 0xfe9c][pos]
		}
		0x62c {
			return [0x62c, 0xfe9e, 0xfe9f, 0xfea0][pos]
		}
		0x686 {
			return [0x686, 0xfb7b, 0xfb7c, 0xfb7d][pos]
		}
		0x62d {
			return [0x62d, 0xfea2, 0xfea3, 0xfea4][pos]
		}
		0x62e {
			return [0x62e, 0xfea6, 0xfea7, 0xfea8][pos]
		}
		0x62f {
			return if pos == 1 { 0xfeaa } else { cp }
		}
		0x630 {
			return if pos == 1 { 0xfeac } else { cp }
		}
		0x631 {
			return if pos == 1 { 0xfeae } else { cp }
		}
		0x632 {
			return if pos == 1 { 0xfeb0 } else { cp }
		}
		0x698 {
			return if pos == 1 { 0xfb8b } else { cp }
		}
		0x633 {
			return [0x633, 0xfeb2, 0xfeb3, 0xfeb4][pos]
		}
		0x634 {
			return [0x634, 0xfeb6, 0xfeb7, 0xfeb8][pos]
		}
		0x635 {
			return [0x635, 0xfeba, 0xfebb, 0xfebc][pos]
		}
		0x636 {
			return [0x636, 0xfebe, 0xfebf, 0xfec0][pos]
		}
		0x637 {
			return [0x637, 0xfec2, 0xfec3, 0xfec4][pos]
		}
		0x638 {
			return [0x638, 0xfec6, 0xfec7, 0xfec8][pos]
		}
		0x639 {
			return [0x639, 0xfeca, 0xfecb, 0xfecc][pos]
		}
		0x63a {
			return [0x63a, 0xfece, 0xfecf, 0xfed0][pos]
		}
		0x641 {
			return [0x641, 0xfed2, 0xfed3, 0xfed4][pos]
		}
		0x642 {
			return [0x642, 0xfed6, 0xfed7, 0xfed8][pos]
		}
		0x643 {
			return [0x643, 0xfeda, 0xfedb, 0xfedc][pos]
		}
		0x6a9 {
			return [0x6a9, 0xfb8f, 0xfb90, 0xfb91][pos]
		}
		0x6af {
			return [0x6af, 0xfb93, 0xfb94, 0xfb95][pos]
		}
		0x644 {
			return [0x644, 0xfede, 0xfedf, 0xfee0][pos]
		}
		0x645 {
			return [0x645, 0xfee2, 0xfee3, 0xfee4][pos]
		}
		0x646 {
			return [0x646, 0xfee6, 0xfee7, 0xfee8][pos]
		}
		0x647 {
			return [0x647, 0xfeea, 0xfeeb, 0xfeec][pos]
		}
		0x648 {
			return if pos == 1 { 0xfeee } else { cp }
		}
		0x6cc {
			return [0x6cc, 0xfbfd, 0xfbfe, 0xfbff][pos]
		}
		0x629 {
			return if pos == 1 { 0xfe94 } else { cp }
		}
		0x649 {
			return if pos == 1 { 0xfef2 } else { cp }
		}
		0x623 {
			return if pos == 1 { 0xfe84 } else { cp }
		}
		0x625 {
			return if pos == 1 { 0xfe88 } else { cp }
		}
		0x624 {
			return if pos == 1 { 0xfe86 } else { cp }
		}
		0x626 {
			return [0x626, 0xfe8a, 0xfe8b, 0xfe8c][pos]
		}
		else {
			return cp
		}
	}
}

// fa_is_rtl reports whether a codepoint belongs to an RTL run. Transparent
// marks inherit the run; ZWJ joins, ZWNJ breaks (handled by the caller).
fn fa_is_rtl(cp int) bool {
	if cp >= 0x600 && cp <= 0x6ff {
		return true
	}
	if cp >= 0xfb50 && cp <= 0xfdff {
		return true
	}
	if cp >= 0xfe70 && cp <= 0xfeff {
		return true
	}
	if cp == 0x200f {
		return true
	}
	return false
}

// sh shapes and reorders Persian/Arabic text for a renderer without complex
// text layout. Latin-only input is returned unchanged.
pub fn sh(s string) string {
	runes := s.runes()
	if runes.len == 0 {
		return s
	}
	mut has_rtl := false
	for ch in runes {
		if fa_is_rtl(int(ch)) {
			has_rtl = true
			break
		}
	}
	if !has_rtl {
		return s
	}
	// Pass 1: resolve forms. ZWNJ breaks, ZWJ forces, marks are transparent.
	// `base` parallels `out` with the ORIGINAL codepoints: forms must never
	// be join-checked, since fa_join only knows base letters.
	mut out := []int{cap: runes.len}
	mut base := []int{cap: runes.len}
	mut i := 0
	for i < runes.len {
		cp := int(runes[i])
		if cp == 0x200c {
			// ZWNJ: join breaker. Dropped: the forms already show the break.
			i++
			continue
		}
		if cp == 0x200d {
			// ZWJ: join forcer, kept as a marker the left scan understands.
			out << cp
			base << cp
			i++
			continue
		}
		j := fa_join(cp)
		if j == 0 || j == 3 {
			out << cp
			base << cp
			i++
			continue
		}
		// left neighbour: previous emitted letter, skipping emitted marks.
		mut lj := 0
		mut k := base.len - 1
		for k >= 0 {
			if base[k] == 0x200d {
				lj = 2
				break
			}
			pj := fa_join(base[k])
			if pj == 3 {
				k--
				continue
			}
			lj = pj
			break
		}
		// right neighbour: next letter, skipping marks and one ZWJ/ZWNJ.
		mut rj := 0
		mut m := i + 1
		mut forced := false
		mut broken := false
		for m < runes.len {
			nc := int(runes[m])
			if nc == 0x200c {
				broken = true
				break
			}
			if nc == 0x200d {
				forced = true
				m++
				continue
			}
			nj := fa_join(nc)
			if nj == 3 {
				m++
				continue
			}
			rj = nj
			break
		}
		left := (lj == 2) || (forced && lj != 0)
		right := (rj == 1 || rj == 2) && !broken
		if j == 1 {
			out << fa_form(cp, if left { 1 } else { 0 })
			base << cp
		} else {
			pos := if left && (right || forced) {
				3
			} else if left {
				1
			} else if right || forced {
				2
			} else {
				0
			}
			out << fa_form(cp, pos)
			base << cp
		}
		i++
	}
	// Pass 2: bidi-lite. Base direction comes from the first strong
	// character; RTL paragraphs lay runs right-to-left, LTR ones keep
	// logical order. RTL runs are reversed in both cases (their glyphs are
	// already shaped, only the order was logical); LTR runs stay intact.
	mut runs := [][]int{}
	mut cur := []int{}
	mut cur_rtl := false
	mut first := true
	for cp in out {
		rtl := fa_is_rtl(cp) || fa_join(cp) != 0
		if first {
			cur_rtl = rtl
			first = false
		}
		if rtl == cur_rtl {
			cur << cp
		} else {
			runs << cur
			cur = [cp]
			cur_rtl = rtl
		}
	}
	runs << cur
	mut base_rtl := false
	for cp in out {
		if fa_is_rtl(cp) || fa_join(cp) != 0 {
			base_rtl = true
			break
		}
		if (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) {
			base_rtl = false
			break
		}
	}
	mut res := []rune{}
	// reverse_run emits one run in display order: RTL runs reversed (their
	// glyphs are already shaped), LTR runs as-is.
	reverse_run := fn (r []int) []rune {
		mut o := []rune{}
		is_rtl_run := r.len > 0 && (fa_is_rtl(r[0]) || fa_join(r[0]) != 0)
		if is_rtl_run {
			mut k := r.len - 1
			for k >= 0 {
				o << rune(r[k])
				k--
			}
		} else {
			for cp in r {
				o << rune(cp)
			}
		}
		return o
	}
	if base_rtl {
		mut ri := runs.len - 1
		for ri >= 0 {
			for ch in reverse_run(runs[ri]) {
				res << ch
			}
			if ri == 0 {
				break
			}
			ri--
		}
	} else {
		for r in runs {
			for ch in reverse_run(r) {
				res << ch
			}
		}
	}
	return res.string()
}

// sh_auto shapes only strings holding RTL text; everything else passes
// through byte-identical. Apply at the display boundary.
pub fn sh_auto(s string) string {
	for ch in s.runes() {
		if fa_is_rtl(int(ch)) {
			return sh(s)
		}
	}
	return s
}
