class_name StatsScreen
extends Control
## Developer stats screen (TEMPORARY — remove before release, with RunStats and the Developer
## tab in Settings). Everything from your recorded runs (user://run_stats.jsonl), per
## character: runs, wins, times, levels, kills, keys, shards, chests, boss HP left, what kills
## you, what hurts you, which weapons and abilities do the damage, favourite picks, and the
## recent runs one by one. English only (a developer tool).

signal closed

const ALL := "all"

var _map := ALL
var _char := ""          # "" = the overview of every character
var _runs: Array = []
var _map_pick: OptionButton
var _list: VBoxContainer   # left: characters
var _body: RichTextLabel   # right: the selected character (or the overview)
var _clear: Button
var _clear_armed := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.06, 0.97)
	sb.border_color = Color(0.45, 0.8, 1.0, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	margin.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	# Header: title, map filter, clear, close
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	var title := Label.new()
	title.text = "MY STATS  (developer)"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_map_pick = OptionButton.new()
	_map_pick.add_theme_font_size_override("font_size", 18)
	_map_pick.add_item("All maps")
	_map_pick.set_item_metadata(0, ALL)
	for m in MapPicker.MAPS:
		_map_pick.add_item(str(m["name"]))
		_map_pick.set_item_metadata(_map_pick.item_count - 1, str(m["id"]))
	_map_pick.item_selected.connect(func(i: int): _map = str(_map_pick.get_item_metadata(i)); _refresh())
	head.add_child(_map_pick)
	_clear = _button("Clear stats", _on_clear)
	head.add_child(_clear)
	head.add_child(_button("Close", close))

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	left.add_child(_list)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.scroll_active = true
	_body.selection_enabled = true
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	split.add_child(_body)


func open() -> void:
	visible = true
	_char = ""
	_clear_armed = false
	_clear.text = "Clear stats"
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _on_clear() -> void:
	if not _clear_armed:   # two clicks, so it can't happen by accident
		_clear_armed = true
		_clear.text = "Click again to clear"
		return
	RunStats.clear()
	_clear_armed = false
	_clear.text = "Clear stats"
	_refresh()


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.custom_minimum_size = Vector2(120, 38)
	b.pressed.connect(cb)
	return b


# ------------------------------------------------------------------ content

func _refresh() -> void:
	_runs = []
	for r in RunStats.load_runs():
		if _map == ALL or str(r.get("map", "")) == _map:
			_runs.append(r)
	# Left: everyone you've played, most runs first
	for c in _list.get_children():
		c.queue_free()
	var by_char := {}
	for r in _runs:
		var id := str(r.get("char", "?"))
		if not by_char.has(id):
			by_char[id] = []
		by_char[id].append(r)
	var ids := by_char.keys()
	ids.sort_custom(func(a, b): return by_char[a].size() > by_char[b].size())
	var all_b := _char_button("All characters  (%d runs)" % _runs.size(), "")
	_list.add_child(all_b)
	for id in ids:
		var runs: Array = by_char[id]
		var wins := runs.filter(func(r): return str(r.get("result", "")) == "WON").size()
		_list.add_child(_char_button("%s   %d runs · %d won" % [_name(id), runs.size(), wins], id))
	if _char != "" and not by_char.has(_char):
		_char = ""
	_body.text = _overview(by_char, ids) if _char == "" else _character(_char, by_char[_char])
	_body.scroll_to_line(0)


func _char_button(text: String, id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_pressed = id == _char
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func(): _char = id; _refresh())
	return b


## Every character side by side.
func _overview(by_char: Dictionary, ids: Array) -> String:
	if _runs.is_empty():
		return "[color=#aaa]No runs recorded%s yet. Play a run and it shows up here.[/color]" % ("" if _map == ALL else " on this map")
	var s := RunStats.summarize(_runs)
	var t := "[b][color=#8fd3ff]ALL CHARACTERS[/color][/b]   %s\n" % _map_label()
	t += _totals_line(s) + "\n\n"
	t += "[table=9]"
	for h in ["Character", "Runs", "Won", "Win %", "Best win", "Avg time", "Avg lvl", "Avg kills", "Top weapon"]:
		t += "[cell][b][color=#ffcc66]%s[/color][/b]   [/cell]" % h
	for id in ids:
		var cs := RunStats.summarize(by_char[id])
		var top := RunStats.ranked(cs["dealt"], 1)
		t += "[cell]%s   [/cell][cell]%d[/cell][cell]%d[/cell][cell]%d%%[/cell][cell]%s[/cell][cell]%s[/cell][cell]%.1f[/cell][cell]%s[/cell][cell]%s[/cell]" % [
			_name(id), cs["runs"], cs["wins"], _pct(cs["wins"], cs["runs"]), _best(cs), _time(cs["time"] / maxi(cs["runs"], 1)),
			cs["level"] / maxi(cs["runs"], 1), Wallet.fmt(roundi(cs["kills"] / maxi(cs["runs"], 1))),
			(str(top[0][0]) if not top.is_empty() else "-")]
	t += "[/table]\n\n"
	t += _breakdown("What kills you", s["killers"], s["deaths"], true)
	t += _breakdown("Damage taken by source", s["taken"], -1)
	t += "\n[b][color=#8fd3ff]RECENT RUNS[/color][/b]\n" + _recent(_runs, 15)
	return t


## One character in depth.
func _character(id: String, runs: Array) -> String:
	var s := RunStats.summarize(runs)
	var n := maxi(s["runs"], 1)
	var t := "[b][color=#8fd3ff]%s[/color][/b]   %s\n" % [_name(id).to_upper(), _map_label()]
	t += _totals_line(s) + "\n"
	t += "Best win [b]%s[/b]  ·  longest run [b]%s[/b]  ·  avg time [b]%s[/b]  ·  avg level [b]%.1f[/b]  ·  avg kills [b]%s[/b] (best %s)\n" % [
		_best(s), _time(s["longest"]), _time(s["time"] / n), s["level"] / n, Wallet.fmt(roundi(s["kills"] / n)), Wallet.fmt(s["max_kills"])]
	var bh: Array = s["boss_hp"]
	if not bh.is_empty():
		var avg := 0.0
		var lo := 1.0
		for v in bh:
			avg += v
			lo = minf(lo, v)
		t += "Boss HP left when you lost: avg [b]%d%%[/b], best [b]%d%%[/b] (%d runs that reached the boss)\n" % [roundi(avg / bh.size() * 100.0), roundi(lo * 100.0), bh.size()]
	t += "\n"
	t += _breakdown("Damage dealt by weapon / ability", s["dealt"], -1)
	t += _breakdown("What kills you", s["killers"], s["deaths"], true)
	t += _breakdown("Damage taken by source", s["taken"], -1)
	t += _breakdown("Upgrades taken (in how many runs)", s["picks"], s["runs"], true, 12)
	t += "\n[b][color=#8fd3ff]RUNS[/color][/b]\n" + _recent(runs, 30)
	return t


func _totals_line(s: Dictionary) -> String:
	var sh := PackedStringArray()
	for k in s["shards"]:
		sh.append("%s %d" % [str(k).capitalize(), roundi(s["shards"][k])])
	return "Runs [b]%d[/b]  ·  won [b]%d[/b] (%d%%)  ·  died %d  ·  quit %d  ·  keys [color=#cd7f32]%d[/color] / [color=#c0c0c0]%d[/color] / [color=#ffd700]%d[/color]  ·  shards %s  ·  chests %d" % [
		s["runs"], s["wins"], _pct(s["wins"], s["runs"]), s["deaths"], s["quits"], s["keys"][0], s["keys"][1], s["keys"][2],
		(", ".join(sh) if not sh.is_empty() else "0"), s["chests"]]


## A ranked list: "name   value   share". `of` > 0: share of that count (times), else of the total.
func _breakdown(title: String, d: Dictionary, of: int, counts := false, n := 10) -> String:
	if d.is_empty():
		return ""
	var rows := RunStats.ranked(d, n)
	var total := 0.0
	for k in d:
		total += float(d[k])
	var t := "[b][color=#ffcc66]%s[/color][/b]\n[table=3]" % title
	for r in rows:
		var v: float = r[1]
		var share := (v / of) if of > 0 else (v / maxf(total, 1.0))
		t += "[cell]  %s   [/cell][cell]%s   [/cell][cell][color=#aaa]%d%%[/color][/cell]" % [r[0], (str(roundi(v)) + "x") if counts else Wallet.fmt(roundi(v)), roundi(share * 100.0)]
	return t + "[/table]\n\n"


func _recent(runs: Array, n: int) -> String:
	var t := ""
	var start := maxi(0, runs.size() - n)
	for k in range(runs.size() - 1, start - 1, -1):
		var r: Dictionary = runs[k]
		var res := str(r.get("result", "?"))
		var col := "#7dff8a" if res == "WON" else ("#ff7a6a" if res == "DIED" else "#aaaaaa")
		var when := Time.get_datetime_string_from_unix_time(int(r.get("ts", 0)) + _tz_offset(), true).substr(5, 11)
		var top := RunStats.ranked(r.get("damage_dealt", {}), 3)
		var tops := PackedStringArray()
		for d in top:
			tops.append("%s %s" % [d[0], Wallet.fmt(roundi(d[1]))])
		var k: Dictionary = r.get("keys", {})
		var extra := ""
		if res == "DIED":
			extra = "  ·  killed by %s" % str(r.get("killed_by", "?"))
			if float(r.get("boss_hp", -1.0)) >= 0.0:
				extra += " (boss at %d%%)" % roundi(float(r["boss_hp"]) * 100.0)
		var sh := PackedStringArray()
		for s in r.get("shards", {}):
			sh.append("%s %d" % [str(s).capitalize(), int(r["shards"][s])])
		var who := (_name(str(r.get("char", ""))) + "  ·  ") if _char == "" else ""
		t += "[color=#888]%s[/color]  [color=%s][b]%s[/b][/color] %s  ·  %s%s  ·  lvl %d  ·  %s kills%s\n" % [
			when, col, res, _time(float(r.get("time", 0.0))), who, _map_name(str(r.get("map", ""))),
			int(r.get("level", 0)), Wallet.fmt(int(r.get("kills", 0))), extra]
		t += "      [color=#aaa]keys %d/%d/%d  ·  shards %s  ·  %s[/color]\n" % [int(k.get("Bronze", 0)), int(k.get("Silver", 0)), int(k.get("Gold", 0)),
			(", ".join(sh) if not sh.is_empty() else "0"), (", ".join(tops) if not tops.is_empty() else "no damage")]
	return t


# ------------------------------------------------------------------ helpers

func _name(id: String) -> String:
	return WeaponSystem._char_name(id) if id != "" else "?"


func _map_name(id: String) -> String:
	for m in MapPicker.MAPS:
		if m["id"] == id:
			return str(m["name"])
	return id


func _map_label() -> String:
	return "[color=#aaa](%s)[/color]" % ("all maps" if _map == ALL else _map_name(_map))


static func _pct(a: int, b: int) -> int:
	return roundi(100.0 * a / b) if b > 0 else 0


func _best(s: Dictionary) -> String:
	return _time(s["best_win"]) if s["best_win"] >= 0.0 else "-"


static func _time(secs: float) -> String:
	var t := int(round(secs))
	return "%d:%02d" % [t / 60, t % 60]


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60
