@tool
extends AcceptDialog
class_name VoicePresetBrowser

## Voice Preset Browser - Browse, preview, and load AnimaleseVoice presets from the project.
## Scans the project for .tres files containing AnimaleseVoice resources.

signal voice_selected(voice: AnimaleseVoice, path: String)
signal preview_requested(voice: AnimaleseVoice, text: String)

# UI Components
var _main_vbox: VBoxContainer
var _toolbar: HBoxContainer
var _search_field: LineEdit
var _filter_button: MenuButton
var _sort_button: MenuButton
var _refresh_button: Button
var _preview_text: LineEdit
var _scroll: ScrollContainer
var _grid: GridContainer
var _status_label: Label

# Data
var _presets: Array[Dictionary] = []  # [{path, voice, name, pitch, tags}]
var _filtered_presets: Array[Dictionary] = []
var _cards: Array[Control] = []

# Filter state
enum SortMode { NAME_ASC, NAME_DESC, PITCH_ASC, PITCH_DESC, PATH }
var _sort_mode: SortMode = SortMode.NAME_ASC
var _filter_tags: Array[String] = []
var _search_text: String = ""

# Editor reference for preview
var _editor: EditorInterface = null

# Card dimensions
const CARD_WIDTH: int = 180
const CARD_HEIGHT: int = 140
const GRID_COLUMNS: int = 4


func _init() -> void:
	title = tr("Voice Preset Browser")
	min_size = Vector2(800, 500)
	exclusive = false


func _ready() -> void:
	_build_ui()
	_scan_presets()


func set_editor(editor: EditorInterface) -> void:
	_editor = editor
	_apply_icons()


func _build_ui() -> void:
	_main_vbox = VBoxContainer.new()
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_vbox.add_theme_constant_override("separation", 8)
	add_child(_main_vbox)

	# === TOOLBAR ===
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 8)
	_main_vbox.add_child(_toolbar)

	# Search field
	var search_label := Label.new()
	search_label.text = tr("Search:")
	_toolbar.add_child(search_label)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = tr("Filter by name...")
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.custom_minimum_size = Vector2(150, 0)
	_search_field.text_changed.connect(_on_search_changed)
	_toolbar.add_child(_search_field)

	# Filter button (tags)
	_filter_button = MenuButton.new()
	_filter_button.text = tr("Tags")
	_filter_button.tooltip_text = tr("Filter by voice type")
	var filter_popup := _filter_button.get_popup()
	filter_popup.add_check_item(tr("Masculine"), 0)
	filter_popup.add_check_item(tr("Feminine"), 1)
	filter_popup.add_check_item(tr("Child"), 2)
	filter_popup.add_check_item(tr("Elder"), 3)
	filter_popup.add_check_item(tr("Robot"), 4)
	filter_popup.add_check_item(tr("Monster"), 5)
	filter_popup.add_check_item(tr("Ghost"), 6)
	filter_popup.add_check_item(tr("Whisper"), 7)
	filter_popup.id_pressed.connect(_on_filter_toggled)
	_toolbar.add_child(_filter_button)

	# Sort button
	_sort_button = MenuButton.new()
	_sort_button.text = tr("Sort")
	_sort_button.tooltip_text = tr("Sort presets")
	var sort_popup := _sort_button.get_popup()
	sort_popup.add_radio_check_item(tr("Name (A-Z)"), 0)
	sort_popup.add_radio_check_item(tr("Name (Z-A)"), 1)
	sort_popup.add_radio_check_item(tr("Pitch (Low-High)"), 2)
	sort_popup.add_radio_check_item(tr("Pitch (High-Low)"), 3)
	sort_popup.add_radio_check_item(tr("Path"), 4)
	sort_popup.set_item_checked(0, true)
	sort_popup.id_pressed.connect(_on_sort_changed)
	_toolbar.add_child(_sort_button)

	# Refresh button
	_refresh_button = Button.new()
	_refresh_button.text = tr("Refresh")
	_refresh_button.tooltip_text = tr("Rescan project for voice presets")
	_refresh_button.pressed.connect(_scan_presets)
	_toolbar.add_child(_refresh_button)

	# Preview text
	_main_vbox.add_child(HSeparator.new())

	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 8)
	_main_vbox.add_child(preview_row)

	var preview_label := Label.new()
	preview_label.text = tr("Preview text:")
	preview_row.add_child(preview_label)

	_preview_text = LineEdit.new()
	_preview_text.text = "Hello! This is a voice test."
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(_preview_text)

	_main_vbox.add_child(HSeparator.new())

	# === GRID SCROLL ===
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_main_vbox.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_grid)

	# === STATUS BAR ===
	_status_label = Label.new()
	_status_label.text = tr("Scanning...")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_main_vbox.add_child(_status_label)


func _apply_icons() -> void:
	if _editor == null:
		return
	var theme := _editor.get_editor_theme()
	if theme == null:
		return

	if theme.has_icon("Search", "EditorIcons"):
		_search_field.right_icon = theme.get_icon("Search", "EditorIcons")
	if theme.has_icon("Reload", "EditorIcons"):
		_refresh_button.icon = theme.get_icon("Reload", "EditorIcons")


# ---------- Scanning ----------
func _scan_presets() -> void:
	_presets.clear()
	_status_label.text = tr("Scanning...")

	# Scan common directories
	var dirs_to_scan: Array[String] = [
		"res://",
		"res://addons/procedural_animalese/presets/",
		"res://voices/",
		"res://audio/voices/",
		"res://resources/voices/",
	]

	for dir_path in dirs_to_scan:
		_scan_directory(dir_path)

	# Remove duplicates by path
	var seen_paths: Dictionary = {}
	var unique_presets: Array[Dictionary] = []
	for preset in _presets:
		if not seen_paths.has(preset.path):
			seen_paths[preset.path] = true
			unique_presets.append(preset)
	_presets = unique_presets

	_apply_filters()
	_status_label.text = tr("%d presets found") % _presets.size()


func _scan_directory(path: String, recursive: bool = true) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		var full_path := path.path_join(file_name)

		if dir.current_is_dir():
			if recursive and not file_name.begins_with("."):
				_scan_directory(full_path, true)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			_try_load_voice(full_path)

		file_name = dir.get_next()

	dir.list_dir_end()


func _try_load_voice(path: String) -> void:
	# Check if it's an AnimaleseVoice without fully loading
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res == null:
		return

	if not res is AnimaleseVoice:
		return

	var voice: AnimaleseVoice = res
	var preset_data: Dictionary = {
		"path": path,
		"voice": voice,
		"name": _get_voice_name(voice, path),
		"pitch": voice.pitch_base_hz,
		"tags": _detect_tags(voice),
	}
	_presets.append(preset_data)


func _get_voice_name(voice: AnimaleseVoice, path: String) -> String:
	if voice.voice_name != null and voice.voice_name != "":
		return voice.voice_name
	# Fallback to filename
	return path.get_file().get_basename().capitalize()


func _detect_tags(voice: AnimaleseVoice) -> Array[String]:
	var tags: Array[String] = []
	var pitch := voice.pitch_base_hz
	var whisper := voice.whisper_amount if "whisper_amount" in voice else 0.0
	var breath := voice.breath_noise_level if "breath_noise_level" in voice else 0.0

	# Pitch-based tags
	if pitch < 130:
		tags.append("masculine")
	elif pitch < 200:
		tags.append("masculine")
	elif pitch < 280:
		tags.append("feminine")
	elif pitch < 400:
		tags.append("feminine")
	else:
		tags.append("child")

	# Special characteristics
	if whisper > 0.5:
		tags.append("whisper")
	if whisper > 0.3 and breath > 0.3:
		tags.append("ghost")
	if voice.vibrato_rate_hz == 0.0 and voice.pitch_jitter < 0.02:
		tags.append("robot")
	if pitch < 100 and breath > 0.4:
		tags.append("monster")
	if pitch > 350:
		tags.append("child")
	if pitch < 120:
		tags.append("elder")

	return tags


# ---------- Filtering & Sorting ----------
func _apply_filters() -> void:
	_filtered_presets.clear()

	for preset in _presets:
		# Search filter
		if _search_text != "":
			var name_lower: String = preset.name.to_lower()
			var path_lower: String = preset.path.to_lower()
			var search_lower: String = _search_text.to_lower()
			if not name_lower.contains(search_lower) and not path_lower.contains(search_lower):
				continue

		# Tag filter
		if _filter_tags.size() > 0:
			var has_tag := false
			for tag in _filter_tags:
				if tag in preset.tags:
					has_tag = true
					break
			if not has_tag:
				continue

		_filtered_presets.append(preset)

	# Sort
	_filtered_presets.sort_custom(_sort_compare)

	_rebuild_grid()


func _sort_compare(a: Dictionary, b: Dictionary) -> bool:
	match _sort_mode:
		SortMode.NAME_ASC:
			return a.name.naturalcasecmp_to(b.name) < 0
		SortMode.NAME_DESC:
			return a.name.naturalcasecmp_to(b.name) > 0
		SortMode.PITCH_ASC:
			return a.pitch < b.pitch
		SortMode.PITCH_DESC:
			return a.pitch > b.pitch
		SortMode.PATH:
			return a.path.naturalcasecmp_to(b.path) < 0
	return false


# ---------- Grid Building ----------
func _rebuild_grid() -> void:
	# Clear existing cards
	for card in _cards:
		card.queue_free()
	_cards.clear()

	# Create cards for filtered presets
	for preset in _filtered_presets:
		var card := _create_card(preset)
		_grid.add_child(card)
		_cards.append(card)

	_status_label.text = tr("Showing %d of %d presets") % [_filtered_presets.size(), _presets.size()]


func _create_card(preset: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.3, 0.35, 1.0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Voice name
	var name_label := Label.new()
	name_label.text = preset.name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(name_label)

	# Pitch indicator
	var pitch_label := Label.new()
	pitch_label.text = "%d Hz" % int(preset.pitch)
	pitch_label.add_theme_font_size_override("font_size", 11)
	pitch_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	pitch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pitch_label)

	# Pitch description
	var pitch_desc := _get_pitch_description(preset.pitch)
	var desc_label := Label.new()
	desc_label.text = pitch_desc
	desc_label.add_theme_font_size_override("font_size", 10)
	desc_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_label)

	# Tags
	var tags_str := ", ".join(preset.tags.slice(0, 3))  # Show max 3 tags
	var tags_label := Label.new()
	tags_label.text = tags_str
	tags_label.add_theme_font_size_override("font_size", 9)
	tags_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	tags_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tags_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(tags_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var play_btn := Button.new()
	play_btn.text = tr("Play")
	play_btn.custom_minimum_size = Vector2(60, 0)
	play_btn.pressed.connect(_on_play_pressed.bind(preset))
	btn_row.add_child(play_btn)

	var load_btn := Button.new()
	load_btn.text = tr("Load")
	load_btn.custom_minimum_size = Vector2(60, 0)
	load_btn.pressed.connect(_on_load_pressed.bind(preset))
	btn_row.add_child(load_btn)

	# Apply icons
	if _editor != null:
		var theme := _editor.get_editor_theme()
		if theme != null:
			if theme.has_icon("Play", "EditorIcons"):
				play_btn.icon = theme.get_icon("Play", "EditorIcons")
			if theme.has_icon("Load", "EditorIcons"):
				load_btn.icon = theme.get_icon("Load", "EditorIcons")

	# Hover effect
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))

	return card


func _get_pitch_description(pitch: float) -> String:
	if pitch < 100:
		return tr("Bass")
	elif pitch < 140:
		return tr("Baritone")
	elif pitch < 180:
		return tr("Tenor")
	elif pitch < 230:
		return tr("Alto")
	elif pitch < 300:
		return tr("Soprano")
	elif pitch < 400:
		return tr("High soprano")
	else:
		return tr("Very high")


func _on_card_hover(card: PanelContainer, hovering: bool) -> void:
	var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	if hovering:
		style.border_color = Color(0.5, 0.6, 0.8, 1.0)
		style.bg_color = Color(0.18, 0.18, 0.22, 1.0)
	else:
		style.border_color = Color(0.3, 0.3, 0.35, 1.0)
		style.bg_color = Color(0.15, 0.15, 0.18, 1.0)
	card.add_theme_stylebox_override("panel", style)


# ---------- Event Handlers ----------
func _on_search_changed(text: String) -> void:
	_search_text = text
	_apply_filters()


func _on_filter_toggled(id: int) -> void:
	var popup := _filter_button.get_popup()
	var is_checked := popup.is_item_checked(id)
	popup.set_item_checked(id, not is_checked)

	# Map id to tag name
	var tag_map: Array[String] = ["masculine", "feminine", "child", "elder", "robot", "monster", "ghost", "whisper"]
	var tag := tag_map[id]

	if not is_checked:
		if tag not in _filter_tags:
			_filter_tags.append(tag)
	else:
		_filter_tags.erase(tag)

	_apply_filters()


func _on_sort_changed(id: int) -> void:
	var popup := _sort_button.get_popup()
	# Uncheck all
	for i in popup.item_count:
		popup.set_item_checked(i, false)
	popup.set_item_checked(id, true)

	_sort_mode = id as SortMode
	_apply_filters()


func _on_play_pressed(preset: Dictionary) -> void:
	preview_requested.emit(preset.voice, _preview_text.text)


func _on_load_pressed(preset: Dictionary) -> void:
	voice_selected.emit(preset.voice, preset.path)
	hide()
