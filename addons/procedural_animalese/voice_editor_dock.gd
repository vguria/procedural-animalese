@tool
extends MarginContainer

# Dock UI to edit AnimaleseVoice resources and preview playback.
# Reorganized with tabs for better UX. All labels use tr() for i18n.

signal request_preview(voice: AnimaleseVoice, text: String, pitch_mul: float)

# Main structure
var _main_vbox: VBoxContainer
var _toolbar: HBoxContainer
var _preview_section: VBoxContainer
var _tabs: TabContainer

# Editor integration
var _editor: EditorInterface = null
var _undo_redo: EditorUndoRedoManager = null

# Toolbar controls
var _voice_picker: EditorResourcePicker
var _wizard_btn: Button
var _browse_btn: Button
var _save_btn: Button
var _play_btn: Button
var _wizard: AcceptDialog
var _browser: AcceptDialog  # VoicePresetBrowser

# Preview section
var _preview_text: LineEdit
var _pitch: SpinBox
var _voice_name_edit: LineEdit

# Tab: Principal
var _tab_main: ScrollContainer
var _tab_main_content: VBoxContainer

# Tab: Formantes
var _tab_formants: ScrollContainer
var _tab_formants_content: VBoxContainer

# Tab: Avanzado
var _tab_advanced: ScrollContainer
var _tab_advanced_content: VBoxContainer

# A/B comparison controls
var _voice_picker_b: EditorResourcePicker
var _ab_container: VBoxContainer
var _ab_toggle: Button
var _play_a_btn: Button
var _play_b_btn: Button
var _alternate_btn: Button
var _ab_current: int = 0

# Voice blending controls
var _blend_slider: HSlider
var _blend_spin: SpinBox
var _blend_preview_btn: Button

# Additional toolbar/inspector controls
var _edit_in_inspector_btn: Button

# Guard to prevent feedback while updating UI from a resource.
var _updating_ui: bool = false
# Map of voice property name -> param widgets (slider/spin/button).
class ParamWidgets:
	var slider: HSlider
	var spin: SpinBox
	var rand_btn: Button
	var minv: float
	var maxv: float
	var step: float

var _param_widgets: Dictionary[String, ParamWidgets] = {}

# Helper container for one formant (F1/F2/F3) row.
class FormantRow:
	var freq_spin: SpinBox
	var q_spin: SpinBox
	var amp_spin: SpinBox
	var freq_slider: HSlider
	var q_slider: HSlider
	var amp_slider: HSlider
	var lock: CheckBox
	var reset_btn: Button

# Vowel chart visualization (F1 vs F2 diagram).
# Standard phonetic chart: X = F2 (higher = front), Y = F1 (higher = open).
class VowelChart:
	extends Control
	const F1_MIN: float = 200.0
	const F1_MAX: float = 1000.0
	const F2_MIN: float = 500.0
	const F2_MAX: float = 3000.0
	const POINT_RADIUS: float = 8.0

	var _vowels: Dictionary = {}  # name -> Vector2(F1, F2)
	var _hover: String = ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_vowels(vowel_data: Dictionary) -> void:
		_vowels = vowel_data
		queue_redraw()

	func _f1_to_y(f1: float) -> float:
		# F1 increases downward (open vowels at bottom)
		var norm: float = (clampf(f1, F1_MIN, F1_MAX) - F1_MIN) / (F1_MAX - F1_MIN)
		return 10.0 + norm * (size.y - 20.0)

	func _f2_to_x(f2: float) -> float:
		# F2 decreases left-to-right (front vowels on right)
		var norm: float = (clampf(f2, F2_MIN, F2_MAX) - F2_MIN) / (F2_MAX - F2_MIN)
		return size.x - 10.0 - norm * (size.x - 20.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var mm: InputEventMouseMotion = event
			var new_hover: String = ""
			for name in _vowels.keys():
				var v: Vector2 = _vowels[name]
				var pos := Vector2(_f2_to_x(v.y), _f1_to_y(v.x))
				if mm.position.distance_to(pos) <= POINT_RADIUS + 4.0:
					new_hover = name
					break
			if new_hover != _hover:
				_hover = new_hover
				queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return

		# Background
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.08, 0.95), true)

		# Grid lines
		var grid_color := Color(0.25, 0.25, 0.3, 0.4)
		for f1 in [300.0, 500.0, 700.0, 900.0]:
			var y: float = _f1_to_y(f1)
			draw_line(Vector2(0, y), Vector2(size.x, y), grid_color, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), "F1:%d" % int(f1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.4, 0.4, 0.6))
		for f2 in [800.0, 1400.0, 2000.0, 2600.0]:
			var x: float = _f2_to_x(f2)
			draw_line(Vector2(x, 0), Vector2(x, size.y), grid_color, 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(x + 2, size.y - 4), "F2:%d" % int(f2), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.4, 0.4, 0.4, 0.6))

		# Axis labels
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 50, 12), "Front", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), "Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 40, size.y - 16), "Open", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.5, 0.5, 0.7))

		# Draw vowel points
		var vowel_colors := {
			"a": Color(1.0, 0.4, 0.4, 0.9),
			"e": Color(0.4, 1.0, 0.4, 0.9),
			"i": Color(0.4, 0.7, 1.0, 0.9),
			"o": Color(1.0, 0.7, 0.3, 0.9),
			"u": Color(0.8, 0.4, 1.0, 0.9),
		}

		# Draw connecting lines (vowel trapezoid)
		if _vowels.size() >= 5:
			var order := ["i", "e", "a", "o", "u"]
			var line_color := Color(0.5, 0.5, 0.5, 0.3)
			for idx in range(order.size()):
				var name1: String = order[idx]
				var name2: String = order[(idx + 1) % order.size()]
				if _vowels.has(name1) and _vowels.has(name2):
					var v1: Vector2 = _vowels[name1]
					var v2: Vector2 = _vowels[name2]
					var p1 := Vector2(_f2_to_x(v1.y), _f1_to_y(v1.x))
					var p2 := Vector2(_f2_to_x(v2.y), _f1_to_y(v2.x))
					draw_line(p1, p2, line_color, 1.0)

		for name in _vowels.keys():
			var v: Vector2 = _vowels[name]
			var pos := Vector2(_f2_to_x(v.y), _f1_to_y(v.x))
			var c: Color = vowel_colors.get(name, Color.WHITE)
			var r: float = POINT_RADIUS if name == _hover else POINT_RADIUS - 2.0
			draw_circle(pos, r, c)
			draw_arc(pos, r, 0, TAU, 16, Color.WHITE, 1.5)
			draw_string(ThemeDB.fallback_font, pos + Vector2(r + 4, 4), "/" + name + "/", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, c.lightened(0.2))

# Interactive graph for visualizing and editing formant peaks.
class FormantGraph:
	extends Control
	const MIN_HZ: float = 20.0
	const MAX_HZ: float = 10000.0
	const MAX_AMP: float = 2.0
	const HANDLE_RADIUS: float = 8.0

	signal formant_changed(index: int, freq: float, amp: float)

	var formants: Array[Vector3] = []
	var _dragging: int = -1  # Index of formant being dragged, -1 = none
	var _hover: int = -1  # Index of formant being hovered

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_formants(arr: Array) -> void:
		formants.clear()
		for v in arr:
			if v is Vector3:
				formants.append(v)
		queue_redraw()

	func _freq_to_x(freq: float) -> float:
		return (clampf(freq, MIN_HZ, MAX_HZ) - MIN_HZ) / (MAX_HZ - MIN_HZ) * size.x

	func _x_to_freq(x: float) -> float:
		return MIN_HZ + (clampf(x, 0.0, size.x) / size.x) * (MAX_HZ - MIN_HZ)

	func _amp_to_y(amp: float) -> float:
		var base_y: float = size.y - 2.0
		return base_y - (clampf(amp, 0.0, MAX_AMP) / MAX_AMP) * (size.y - 6.0)

	func _y_to_amp(y: float) -> float:
		var base_y: float = size.y - 2.0
		return clampf((base_y - y) / (size.y - 6.0) * MAX_AMP, 0.0, MAX_AMP)

	func _get_handle_pos(idx: int) -> Vector2:
		if idx < 0 or idx >= formants.size():
			return Vector2.ZERO
		var f: Vector3 = formants[idx]
		return Vector2(_freq_to_x(f.x), _amp_to_y(f.z))

	func _find_handle_at(pos: Vector2) -> int:
		for i in range(formants.size()):
			var hp: Vector2 = _get_handle_pos(i)
			if pos.distance_to(hp) <= HANDLE_RADIUS + 2.0:
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					var idx: int = _find_handle_at(mb.position)
					if idx >= 0:
						_dragging = idx
						accept_event()
				else:
					_dragging = -1
		elif event is InputEventMouseMotion:
			var mm: InputEventMouseMotion = event
			if _dragging >= 0:
				var new_freq: float = _x_to_freq(mm.position.x)
				var new_amp: float = _y_to_amp(mm.position.y)
				formant_changed.emit(_dragging, new_freq, new_amp)
				accept_event()
			else:
				var new_hover: int = _find_handle_at(mm.position)
				if new_hover != _hover:
					_hover = new_hover
					queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return

		# Background
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.08, 0.08, 0.3), true)

		# Grid lines (frequency markers)
		var freq_markers := [100.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0]
		for freq in freq_markers:
			var x: float = _freq_to_x(freq)
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.3, 0.3, 0.3, 0.3), 1.0)
			draw_string(ThemeDB.fallback_font, Vector2(x + 2, size.y - 4), "%d" % int(freq), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.4, 0.4, 0.4, 0.6))

		var base_y: float = size.y - 2.0
		draw_line(Vector2(0.0, base_y), Vector2(size.x, base_y), Color(0.6, 0.6, 0.6, 0.5))

		var colors := [
			Color(0.3, 0.8, 1.0, 0.85),
			Color(0.9, 0.8, 0.3, 0.85),
			Color(0.8, 0.4, 0.7, 0.85)
		]

		# Draw formant peaks
		for i in range(formants.size()):
			var f: Vector3 = formants[i]
			var freq: float = clampf(f.x, MIN_HZ, MAX_HZ)
			var q: float = maxf(0.1, f.y)
			var amp: float = clampf(f.z, 0.0, MAX_AMP)

			var bw: float = freq / q
			var x: float = _freq_to_x(freq)
			var bw_px: float = (bw / (MAX_HZ - MIN_HZ)) * size.x
			bw_px = clampf(bw_px, 4.0, size.x)

			var height: float = (amp / MAX_AMP) * (size.y - 6.0)
			var y: float = base_y - height
			var c: Color = colors[i % colors.size()]

			# Draw peak shape
			draw_rect(Rect2(Vector2(x - bw_px * 0.5, y), Vector2(bw_px, height)), c.darkened(0.3), true)
			draw_line(Vector2(x, base_y), Vector2(x, y), c, 2.0)

			# Draw handle
			var handle_c: Color = c.lightened(0.2) if (i == _hover or i == _dragging) else c
			var handle_r: float = HANDLE_RADIUS if (i == _hover or i == _dragging) else HANDLE_RADIUS - 2.0
			draw_circle(Vector2(x, y), handle_r, handle_c)
			draw_arc(Vector2(x, y), handle_r, 0, TAU, 16, Color.WHITE, 1.5)

			# Label
			draw_string(ThemeDB.fallback_font, Vector2(x - 8, y - 10), "F%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, c.lightened(0.3))

# Waveform visualization for audio preview.
class WaveformGraph:
	extends Control
	const MAX_DISPLAY_SAMPLES: int = 8000
	var _samples: PackedFloat32Array = PackedFloat32Array()
	var _zoom: float = 1.0
	var _offset: int = 0

	func set_samples(samples: PackedFloat32Array) -> void:
		_samples = samples
		_offset = 0
		queue_redraw()

	func clear() -> void:
		_samples = PackedFloat32Array()
		_offset = 0
		queue_redraw()

	func set_view_zoom(z: float) -> void:
		_zoom = clampf(z, 0.1, 10.0)
		queue_redraw()

	func set_view_offset(off: int) -> void:
		_offset = maxi(0, off)
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return

		# Background
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.08, 0.95), true)

		# Center line (zero amplitude)
		var center_y: float = size.y * 0.5
		draw_line(Vector2(0.0, center_y), Vector2(size.x, center_y), Color(0.3, 0.3, 0.35, 0.6), 1.0)

		# Grid lines at ±0.5 amplitude
		var quarter_h: float = size.y * 0.25
		draw_line(Vector2(0.0, center_y - quarter_h), Vector2(size.x, center_y - quarter_h), Color(0.25, 0.25, 0.3, 0.3), 1.0)
		draw_line(Vector2(0.0, center_y + quarter_h), Vector2(size.x, center_y + quarter_h), Color(0.25, 0.25, 0.3, 0.3), 1.0)

		if _samples.size() == 0:
			# Draw "No audio" text
			draw_string(ThemeDB.fallback_font, Vector2(8, center_y + 4), "No audio", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.5, 0.5, 0.6))
			return

		# Calculate visible range
		var visible_samples: int = int(float(MAX_DISPLAY_SAMPLES) / _zoom)
		var start_idx: int = mini(_offset, maxi(0, _samples.size() - visible_samples))
		var end_idx: int = mini(start_idx + visible_samples, _samples.size())

		if end_idx <= start_idx:
			return

		# Downsample if needed for performance
		var samples_to_draw: int = end_idx - start_idx
		var step: int = maxi(1, samples_to_draw / int(size.x))

		var points: PackedVector2Array = PackedVector2Array()
		var fill_points: PackedVector2Array = PackedVector2Array()

		var px: float = 0.0
		var px_step: float = size.x / float(samples_to_draw / step)

		# Build min/max envelope for thick waveform
		var i: int = start_idx
		while i < end_idx:
			var min_val: float = _samples[i]
			var max_val: float = _samples[i]

			var chunk_end: int = mini(i + step, end_idx)
			for j in range(i, chunk_end):
				var s: float = _samples[j]
				min_val = minf(min_val, s)
				max_val = maxf(max_val, s)

			var y_min: float = center_y - (max_val * center_y * 0.9)
			var y_max: float = center_y - (min_val * center_y * 0.9)

			# Draw vertical line for this chunk (envelope style)
			if y_max - y_min < 1.0:
				y_max = y_min + 1.0

			fill_points.append(Vector2(px, y_min))
			fill_points.append(Vector2(px, y_max))

			px += px_step
			i += step

		# Draw waveform as vertical lines (envelope)
		var wave_color := Color(0.3, 0.75, 0.95, 0.85)
		for idx in range(0, fill_points.size(), 2):
			if idx + 1 < fill_points.size():
				draw_line(fill_points[idx], fill_points[idx + 1], wave_color, 1.0)

		# Draw info text
		var duration_ms: float = float(_samples.size()) / 44100.0 * 1000.0
		var info_text: String = "%.0f ms | %d samples" % [duration_ms, _samples.size()]
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 150, 14), info_text, HORIZONTAL_ALIGNMENT_RIGHT, 145, 11, Color(0.6, 0.6, 0.6, 0.7))

# Waveform UI state
var _waveform_graph: WaveformGraph
var _waveform_zoom_slider: HSlider
var _waveform_container: VBoxContainer
var _waveform_toggle: Button

# Formant selection and editing state.
var _formant_select: OptionButton
var _formant_props: Array[String] = []
var _formant_rows: Array[FormantRow] = []
var _formant_graph: FormantGraph
var _vowel_chart: VowelChart
var _vowel_chart_container: VBoxContainer
var _vowel_chart_toggle: Button
var _formant_preset_select: OptionButton
var _formant_preset_apply_btn: Button
var _formant_preset_toggle: Button
var _formant_preset_row: HBoxContainer
var _formant_copy_btn: Button
var _formant_paste_btn: Button
var _formant_reset_group_btn: Button
var _formant_controls_enabled: bool = false
var _formant_copy_buffer: Array = []
var _default_voice: AnimaleseVoice = AnimaleseVoice.new()
var _default_formants_cache: Dictionary[String, Array] = {}

# Randomization UI controls.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rand_intensity: HSlider
var _lock_pitch: CheckBox
var _lock_timing: CheckBox
var _lock_timbre: CheckBox
var _lock_formants: CheckBox
var _seed_box: SpinBox
var _params_toggle: Button
var _params_container: VBoxContainer

# Inject the editor interface for inspector integration.
func set_editor_interface(editor: EditorInterface) -> void:
	_editor = editor

# Inject undo/redo manager for property edits.
func set_undo_redo(ur: EditorUndoRedoManager) -> void:
	_undo_redo = ur

# Build the entire dock UI and connect signals.
func _ready() -> void:
	name = "Voice Editor"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rng.randomize()

	# Main container
	_main_vbox = VBoxContainer.new()
	_main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.add_theme_constant_override("separation", 4)
	add_child(_main_vbox)

	# === TOOLBAR ===
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	_main_vbox.add_child(_toolbar)

	_voice_picker = EditorResourcePicker.new()
	_voice_picker.base_type = "AnimaleseVoice"
	_voice_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar.add_child(_voice_picker)

	if _voice_picker.has_signal("resource_changed"):
		_voice_picker.connect("resource_changed", Callable(self, "_on_voice_picker_changed"))
	elif _voice_picker.has_signal("resource_selected"):
		_voice_picker.connect("resource_selected", Callable(self, "_on_voice_picker_selected"))

	_wizard_btn = Button.new()
	_wizard_btn.text = tr("New...")
	_wizard_btn.tooltip_text = tr("Open voice creation wizard")
	_wizard_btn.pressed.connect(Callable(self, "_on_open_wizard"))
	_toolbar.add_child(_wizard_btn)

	_browse_btn = Button.new()
	_browse_btn.text = tr("Browse...")
	_browse_btn.tooltip_text = tr("Browse voice presets in project")
	_browse_btn.pressed.connect(Callable(self, "_on_open_browser"))
	_toolbar.add_child(_browse_btn)

	_save_btn = Button.new()
	_save_btn.text = tr("Save")
	_save_btn.tooltip_text = tr("Save voice resource")
	_save_btn.pressed.connect(Callable(self, "_on_save_voice"))
	_toolbar.add_child(_save_btn)

	_edit_in_inspector_btn = Button.new()
	_edit_in_inspector_btn.text = tr("Inspector")
	_edit_in_inspector_btn.tooltip_text = tr("Edit voice in Inspector panel")
	_edit_in_inspector_btn.pressed.connect(Callable(self, "_on_edit_voice_in_inspector"))
	_toolbar.add_child(_edit_in_inspector_btn)

	_play_btn = Button.new()
	_play_btn.text = tr("Play")
	_play_btn.tooltip_text = tr("Preview voice with sample text")
	_play_btn.pressed.connect(Callable(self, "_on_play_preview"))
	_toolbar.add_child(_play_btn)

	# Add icons to toolbar buttons if editor theme available
	_apply_toolbar_icons()

	_main_vbox.add_child(HSeparator.new())

	# === PREVIEW SECTION (always visible) ===
	_preview_section = VBoxContainer.new()
	_preview_section.add_theme_constant_override("separation", 4)
	_main_vbox.add_child(_preview_section)

	# Voice name row
	var name_row := HBoxContainer.new()
	_preview_section.add_child(name_row)

	var name_label := Label.new()
	name_label.text = tr("Voice name:")
	name_label.custom_minimum_size = Vector2(90, 0)
	name_row.add_child(name_label)

	_voice_name_edit = LineEdit.new()
	_voice_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voice_name_edit.placeholder_text = tr("Unnamed voice")
	_voice_name_edit.text_submitted.connect(Callable(self, "_on_voice_name_submitted"))
	_voice_name_edit.focus_exited.connect(Callable(self, "_on_voice_name_focus_exited"))
	name_row.add_child(_voice_name_edit)

	# Preview text
	_preview_text = LineEdit.new()
	_preview_text.text = "¡Hola! ¿Qué tal? Esto es una prueba: rápido, suave... ¡y con emoción!"
	_preview_text.placeholder_text = tr("Preview text...")
	_preview_section.add_child(_preview_text)

	# Pitch row
	var pitch_row := HBoxContainer.new()
	_preview_section.add_child(pitch_row)

	var pitch_label := Label.new()
	pitch_label.text = tr("Pitch x:")
	pitch_label.custom_minimum_size = Vector2(90, 0)
	pitch_row.add_child(pitch_label)

	_pitch = SpinBox.new()
	_pitch.min_value = 0.5
	_pitch.max_value = 2.0
	_pitch.step = 0.05
	_pitch.value = 1.15
	_pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pitch_row.add_child(_pitch)

	# Waveform visualization
	_waveform_container = VBoxContainer.new()
	_preview_section.add_child(_waveform_container)

	_waveform_toggle = Button.new()
	_waveform_toggle.toggle_mode = true
	_waveform_toggle.button_pressed = true
	_waveform_toggle.text = tr("Waveform") + " [-]"
	_waveform_toggle.toggled.connect(Callable(self, "_on_waveform_toggled"))
	_waveform_container.add_child(_waveform_toggle)

	_waveform_graph = WaveformGraph.new()
	_waveform_graph.custom_minimum_size = Vector2(0, 70)
	_waveform_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waveform_container.add_child(_waveform_graph)

	var zoom_row := HBoxContainer.new()
	_waveform_container.add_child(zoom_row)

	var zoom_label := Label.new()
	zoom_label.text = tr("Zoom:")
	zoom_label.custom_minimum_size = Vector2(50, 0)
	zoom_row.add_child(zoom_label)

	_waveform_zoom_slider = HSlider.new()
	_waveform_zoom_slider.min_value = 0.1
	_waveform_zoom_slider.max_value = 10.0
	_waveform_zoom_slider.step = 0.1
	_waveform_zoom_slider.value = 1.0
	_waveform_zoom_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waveform_zoom_slider.value_changed.connect(Callable(self, "_on_waveform_zoom_changed"))
	zoom_row.add_child(_waveform_zoom_slider)

	var clear_wave_btn := Button.new()
	clear_wave_btn.text = tr("Clear")
	clear_wave_btn.pressed.connect(Callable(self, "_on_waveform_clear_pressed"))
	zoom_row.add_child(clear_wave_btn)

	_main_vbox.add_child(HSeparator.new())

	# === TAB CONTAINER ===
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_vbox.add_child(_tabs)

	# --- TAB 1: Principal ---
	_tab_main = ScrollContainer.new()
	_tab_main.name = tr("Main")
	_tab_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_main.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(_tab_main)

	_tab_main_content = VBoxContainer.new()
	_tab_main_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_main_content.add_theme_constant_override("separation", 4)
	_tab_main.add_child(_tab_main_content)

	_build_tab_main()

	# --- TAB 2: Formantes ---
	_tab_formants = ScrollContainer.new()
	_tab_formants.name = tr("Formants")
	_tab_formants.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_formants.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(_tab_formants)

	_tab_formants_content = VBoxContainer.new()
	_tab_formants_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_formants_content.add_theme_constant_override("separation", 4)
	_tab_formants.add_child(_tab_formants_content)

	_build_tab_formants()

	# --- TAB 3: Avanzado ---
	_tab_advanced = ScrollContainer.new()
	_tab_advanced.name = tr("Advanced")
	_tab_advanced.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_advanced.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(_tab_advanced)

	_tab_advanced_content = VBoxContainer.new()
	_tab_advanced_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_advanced_content.add_theme_constant_override("separation", 4)
	_tab_advanced.add_child(_tab_advanced_content)

	_build_tab_advanced()

	# Apply tab icons
	_apply_tab_icons()

	_refresh_ui_from_voice(_get_voice())


# ---------- Apply editor theme icons ----------
func _apply_toolbar_icons() -> void:
	if _editor == null:
		return
	var theme := _editor.get_editor_theme()
	if theme == null:
		return

	if theme.has_icon("New", "EditorIcons"):
		_wizard_btn.icon = theme.get_icon("New", "EditorIcons")
	if theme.has_icon("FileList", "EditorIcons"):
		_browse_btn.icon = theme.get_icon("FileList", "EditorIcons")
	elif theme.has_icon("Folder", "EditorIcons"):
		_browse_btn.icon = theme.get_icon("Folder", "EditorIcons")
	if theme.has_icon("Save", "EditorIcons"):
		_save_btn.icon = theme.get_icon("Save", "EditorIcons")
	if theme.has_icon("ExternalLink", "EditorIcons"):
		_edit_in_inspector_btn.icon = theme.get_icon("ExternalLink", "EditorIcons")
	if theme.has_icon("Play", "EditorIcons"):
		_play_btn.icon = theme.get_icon("Play", "EditorIcons")


func _apply_tab_icons() -> void:
	if _editor == null:
		return
	var theme := _editor.get_editor_theme()
	if theme == null:
		return

	# Tab 0: Main - use AudioStreamPlayer icon or similar
	if theme.has_icon("AudioStreamPlayer", "EditorIcons"):
		_tabs.set_tab_icon(0, theme.get_icon("AudioStreamPlayer", "EditorIcons"))
	# Tab 1: Formants - use Curve icon
	if theme.has_icon("Curve", "EditorIcons"):
		_tabs.set_tab_icon(1, theme.get_icon("Curve", "EditorIcons"))
	# Tab 2: Advanced - use Tools icon
	if theme.has_icon("Tools", "EditorIcons"):
		_tabs.set_tab_icon(2, theme.get_icon("Tools", "EditorIcons"))


# ---------- Build Tab: Main ----------
func _build_tab_main() -> void:
	# Parameters section
	var params_title := Label.new()
	params_title.text = tr("Parameters")
	_tab_main_content.add_child(params_title)

	_params_container = VBoxContainer.new()
	_tab_main_content.add_child(_params_container)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_params_container.add_child(grid)

	_add_float_field(grid, tr("Base pitch (Hz)"), "pitch_base_hz", 80.0, 600.0, 1.0)
	_add_float_field(grid, tr("Pitch jitter"), "pitch_jitter", 0.0, 0.25, 0.005)
	_add_float_field(grid, tr("Char duration (s)"), "char_duration_s", 0.02, 0.12, 0.001)
	_add_float_field(grid, tr("Consonant mult (x)"), "consonant_duration_multiplier", 0.3, 1.2, 0.01)

	_add_float_field(grid, tr("Output gain"), "output_gain", 0.0, 2.0, 0.01)
	_add_float_field(grid, tr("Breath noise"), "breath_noise_level", 0.0, 1.5, 0.01)

	_add_float_field(grid, tr("Vocal tract scale"), "vocal_tract_scale", 0.5, 2.0, 0.01)
	_add_float_field(grid, tr("Vowel formant gain"), "vowel_formant_gain", 0.0, 2.0, 0.01)
	_add_float_field(grid, tr("Fricative formant gain"), "fricative_formant_gain", 0.0, 2.0, 0.01)
	_add_float_field(grid, tr("Stop formant gain"), "stop_formant_gain", 0.0, 2.0, 0.01)
	_add_float_field(grid, tr("Nasal formant gain"), "nasal_formant_gain", 0.0, 2.0, 0.01)

	_add_float_field(grid, tr("Prosody strength"), "prosody_strength", 0.0, 1.0, 0.01)
	_add_float_field(grid, tr("Question rise"), "question_rise", 0.0, 1.0, 0.01)
	_add_float_field(grid, tr("Statement fall"), "statement_fall", 0.0, 1.0, 0.01)
	_add_float_field(grid, tr("Exclamation boost"), "exclamation_boost", 0.0, 1.0, 0.01)

	_add_float_field(grid, tr("Vowel breathiness"), "vowel_breathiness", 0.0, 1.0, 0.01)
	_add_float_field(grid, tr("Voiced brightness"), "voiced_brightness", 0.0, 1.0, 0.01)

	_add_float_field(grid, tr("Segment fade (ms)"), "segment_edge_fade_ms", 0.0, 20.0, 0.5)

	_tab_main_content.add_child(HSeparator.new())

	# Randomization section
	var rand_title := Label.new()
	rand_title.text = tr("Randomization")
	_tab_main_content.add_child(rand_title)

	var intensity_row := HBoxContainer.new()
	_tab_main_content.add_child(intensity_row)

	var intensity_label := Label.new()
	intensity_label.text = tr("Intensity:")
	intensity_label.custom_minimum_size = Vector2(90, 0)
	intensity_row.add_child(intensity_label)

	_rand_intensity = HSlider.new()
	_rand_intensity.min_value = 0.0
	_rand_intensity.max_value = 1.0
	_rand_intensity.step = 0.01
	_rand_intensity.value = 0.55
	_rand_intensity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intensity_row.add_child(_rand_intensity)

	var locks := HBoxContainer.new()
	_tab_main_content.add_child(locks)

	_lock_pitch = CheckBox.new()
	_lock_pitch.text = tr("Lock pitch")
	_lock_pitch.button_pressed = false
	locks.add_child(_lock_pitch)

	_lock_timing = CheckBox.new()
	_lock_timing.text = tr("Lock timing")
	_lock_timing.button_pressed = false
	locks.add_child(_lock_timing)

	_lock_timbre = CheckBox.new()
	_lock_timbre.text = tr("Lock timbre")
	_lock_timbre.button_pressed = false
	locks.add_child(_lock_timbre)

	_lock_formants = CheckBox.new()
	_lock_formants.text = tr("Lock formants")
	_lock_formants.button_pressed = false
	locks.add_child(_lock_formants)

	var seed_row := HBoxContainer.new()
	_tab_main_content.add_child(seed_row)

	var seed_label := Label.new()
	seed_label.text = tr("Seed:")
	seed_label.custom_minimum_size = Vector2(90, 0)
	seed_row.add_child(seed_label)

	_seed_box = SpinBox.new()
	_seed_box.min_value = 0
	_seed_box.max_value = 2147483647
	_seed_box.step = 1
	_seed_box.value = 0
	_seed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_box)

	var apply_seed := Button.new()
	apply_seed.text = tr("Apply")
	apply_seed.pressed.connect(Callable(self, "_on_apply_seed_pressed"))
	seed_row.add_child(apply_seed)

	var reroll := Button.new()
	reroll.text = tr("Re-roll")
	reroll.pressed.connect(Callable(self, "_on_reroll_pressed"))
	seed_row.add_child(reroll)

	var rand_buttons := HBoxContainer.new()
	_tab_main_content.add_child(rand_buttons)

	var subtle := Button.new()
	subtle.text = tr("Subtle")
	subtle.pressed.connect(Callable(self, "_on_random_subtle_pressed"))
	rand_buttons.add_child(subtle)

	var strong := Button.new()
	strong.text = tr("Strong")
	strong.pressed.connect(Callable(self, "_on_random_strong_pressed"))
	rand_buttons.add_child(strong)

	var form_only := Button.new()
	form_only.text = tr("Formants only")
	form_only.pressed.connect(Callable(self, "_on_random_formants_pressed"))
	rand_buttons.add_child(form_only)


# ---------- Build Tab: Formants ----------
func _build_tab_formants() -> void:
	# Formant group selector
	var group_row := HBoxContainer.new()
	_tab_formants_content.add_child(group_row)

	var group_label := Label.new()
	group_label.text = tr("Group:")
	group_label.custom_minimum_size = Vector2(90, 0)
	group_row.add_child(group_label)

	_formant_select = OptionButton.new()
	_formant_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_row.add_child(_formant_select)

	_add_formant_option(tr("Vowel /a/"), "vowel_a_formants")
	_add_formant_option(tr("Vowel /e/"), "vowel_e_formants")
	_add_formant_option(tr("Vowel /i/"), "vowel_i_formants")
	_add_formant_option(tr("Vowel /o/"), "vowel_o_formants")
	_add_formant_option(tr("Vowel /u/"), "vowel_u_formants")
	_add_formant_option(tr("Fricative /s/"), "fricative_s_formants")
	_add_formant_option(tr("Fricative /f/"), "fricative_f_formants")
	_add_formant_option(tr("Fricative /x/"), "fricative_x_formants")
	_add_formant_option(tr("Stop /p/"), "stop_p_formants")
	_add_formant_option(tr("Stop /t/"), "stop_t_formants")
	_add_formant_option(tr("Stop /k/"), "stop_k_formants")
	_add_formant_option(tr("Nasal /m,n/"), "nasal_mn_formants")

	_formant_select.item_selected.connect(Callable(self, "_on_formant_selected"))

	# Formant action buttons
	var form_actions := HBoxContainer.new()
	_tab_formants_content.add_child(form_actions)

	_formant_copy_btn = Button.new()
	_formant_copy_btn.text = tr("Copy")
	_formant_copy_btn.pressed.connect(Callable(self, "_on_formant_copy_pressed"))
	form_actions.add_child(_formant_copy_btn)

	_formant_paste_btn = Button.new()
	_formant_paste_btn.text = tr("Paste")
	_formant_paste_btn.pressed.connect(Callable(self, "_on_formant_paste_pressed"))
	form_actions.add_child(_formant_paste_btn)

	_formant_reset_group_btn = Button.new()
	_formant_reset_group_btn.text = tr("Reset group")
	_formant_reset_group_btn.pressed.connect(Callable(self, "_on_formant_group_reset_pressed"))
	form_actions.add_child(_formant_reset_group_btn)

	# Formant presets
	var preset_box := VBoxContainer.new()
	_tab_formants_content.add_child(preset_box)

	_formant_preset_toggle = Button.new()
	_formant_preset_toggle.toggle_mode = true
	_formant_preset_toggle.button_pressed = true
	_formant_preset_toggle.text = tr("Presets") + " [-]"
	_formant_preset_toggle.toggled.connect(Callable(self, "_on_formant_preset_toggled"))
	preset_box.add_child(_formant_preset_toggle)

	_formant_preset_row = HBoxContainer.new()
	preset_box.add_child(_formant_preset_row)

	var preset_label := Label.new()
	preset_label.text = tr("Preset:")
	preset_label.custom_minimum_size = Vector2(60, 0)
	_formant_preset_row.add_child(preset_label)

	_formant_preset_select = OptionButton.new()
	_formant_preset_select.add_item(tr("Default"))
	_formant_preset_select.add_item(tr("Bright"))
	_formant_preset_select.add_item(tr("Dark"))
	_formant_preset_select.add_item(tr("Nasal"))
	_formant_preset_select.add_item(tr("Very bright"))
	_formant_preset_select.add_item(tr("Very dark"))
	_formant_preset_select.add_item(tr("Soft"))
	_formant_preset_select.add_item(tr("Focused"))
	_formant_preset_select.add_item(tr("Wide (low Q)"))
	_formant_preset_select.add_item(tr("Metallic"))
	_formant_preset_row.add_child(_formant_preset_select)

	_formant_preset_apply_btn = Button.new()
	_formant_preset_apply_btn.text = tr("Apply")
	_formant_preset_apply_btn.pressed.connect(Callable(self, "_on_formant_preset_apply_pressed"))
	_formant_preset_row.add_child(_formant_preset_apply_btn)

	_on_formant_preset_toggled(true)

	# Formant grid (F1, F2, F3)
	var form_grid := GridContainer.new()
	form_grid.columns = 5
	form_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_formants_content.add_child(form_grid)

	_add_header_cell(form_grid, "")
	_add_header_cell(form_grid, tr("Frequency (Hz)"), tr("Resonance position; changes timbre color."))
	_add_header_cell(form_grid, tr("Resonance (Q)"), tr("Bandwidth (higher = narrower)."))
	_add_header_cell(form_grid, tr("Gain"), tr("Resonance strength (higher = more pronounced)."))
	_add_header_cell(form_grid, tr("Actions"), tr("Lock or reset the row."))

	for idx in 3:
		_add_formant_row(form_grid, idx)

	# Formant graph
	_formant_graph = FormantGraph.new()
	_formant_graph.custom_minimum_size = Vector2(0, 90)
	_formant_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_formant_graph.mouse_filter = Control.MOUSE_FILTER_STOP
	_formant_graph.formant_changed.connect(_on_formant_graph_changed)
	_tab_formants_content.add_child(_formant_graph)

	# Phoneme preview buttons
	var phoneme_preview_label := Label.new()
	phoneme_preview_label.text = tr("Phoneme preview:")
	_tab_formants_content.add_child(phoneme_preview_label)

	var phoneme_btn_row := HBoxContainer.new()
	_tab_formants_content.add_child(phoneme_btn_row)

	_add_phoneme_preview_btn(phoneme_btn_row, "a", tr("Vowel /a/"))
	_add_phoneme_preview_btn(phoneme_btn_row, "e", tr("Vowel /e/"))
	_add_phoneme_preview_btn(phoneme_btn_row, "i", tr("Vowel /i/"))
	_add_phoneme_preview_btn(phoneme_btn_row, "o", tr("Vowel /o/"))
	_add_phoneme_preview_btn(phoneme_btn_row, "u", tr("Vowel /u/"))

	var phoneme_btn_row2 := HBoxContainer.new()
	_tab_formants_content.add_child(phoneme_btn_row2)

	_add_phoneme_preview_btn(phoneme_btn_row2, "sa", tr("Fricative /s/"))
	_add_phoneme_preview_btn(phoneme_btn_row2, "fa", tr("Fricative /f/"))
	_add_phoneme_preview_btn(phoneme_btn_row2, "ja", tr("Fricative /x/"))
	_add_phoneme_preview_btn(phoneme_btn_row2, "pa", tr("Stop /p/"))
	_add_phoneme_preview_btn(phoneme_btn_row2, "ta", tr("Stop /t/"))
	_add_phoneme_preview_btn(phoneme_btn_row2, "ka", tr("Stop /k/"))
	_add_phoneme_preview_btn(phoneme_btn_row2, "na", tr("Nasal /n/"))

	_tab_formants_content.add_child(HSeparator.new())

	# Vowel chart (F1 vs F2)
	_vowel_chart_container = VBoxContainer.new()
	_tab_formants_content.add_child(_vowel_chart_container)

	_vowel_chart_toggle = Button.new()
	_vowel_chart_toggle.toggle_mode = true
	_vowel_chart_toggle.button_pressed = true
	_vowel_chart_toggle.text = tr("Vowel chart") + " [-]"
	_vowel_chart_toggle.tooltip_text = tr("Shows vowel positions in F1-F2 space (openness vs frontness)")
	_vowel_chart_toggle.toggled.connect(Callable(self, "_on_vowel_chart_toggled"))
	_vowel_chart_container.add_child(_vowel_chart_toggle)

	_vowel_chart = VowelChart.new()
	_vowel_chart.custom_minimum_size = Vector2(0, 120)
	_vowel_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vowel_chart_container.add_child(_vowel_chart)


# ---------- Build Tab: Advanced ----------
func _build_tab_advanced() -> void:
	# A/B Comparison section
	var ab_title := Label.new()
	ab_title.text = tr("A/B Comparison")
	_tab_advanced_content.add_child(ab_title)

	_ab_container = VBoxContainer.new()
	_tab_advanced_content.add_child(_ab_container)

	# Voice B picker
	var h_voice_b := HBoxContainer.new()
	_ab_container.add_child(h_voice_b)

	var l_voice_b := Label.new()
	l_voice_b.text = tr("Voice B:")
	l_voice_b.custom_minimum_size = Vector2(90, 0)
	h_voice_b.add_child(l_voice_b)

	_voice_picker_b = EditorResourcePicker.new()
	_voice_picker_b.base_type = "AnimaleseVoice"
	_voice_picker_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_voice_b.add_child(_voice_picker_b)

	# A/B play buttons
	var ab_buttons := HBoxContainer.new()
	_ab_container.add_child(ab_buttons)

	_play_a_btn = Button.new()
	_play_a_btn.text = tr("Play A")
	_play_a_btn.pressed.connect(Callable(self, "_on_play_voice_a"))
	ab_buttons.add_child(_play_a_btn)

	_play_b_btn = Button.new()
	_play_b_btn.text = tr("Play B")
	_play_b_btn.pressed.connect(Callable(self, "_on_play_voice_b"))
	ab_buttons.add_child(_play_b_btn)

	_alternate_btn = Button.new()
	_alternate_btn.text = tr("Alternate")
	_alternate_btn.pressed.connect(Callable(self, "_on_alternate_ab"))
	ab_buttons.add_child(_alternate_btn)

	# Blend section
	_tab_advanced_content.add_child(HSeparator.new())

	var blend_title := Label.new()
	blend_title.text = tr("Voice Blending")
	_tab_advanced_content.add_child(blend_title)

	var blend_row := HBoxContainer.new()
	_tab_advanced_content.add_child(blend_row)

	var blend_label := Label.new()
	blend_label.text = tr("Mix A↔B:")
	blend_label.custom_minimum_size = Vector2(90, 0)
	blend_row.add_child(blend_label)

	_blend_slider = HSlider.new()
	_blend_slider.min_value = 0.0
	_blend_slider.max_value = 1.0
	_blend_slider.step = 0.01
	_blend_slider.value = 0.5
	_blend_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blend_slider.value_changed.connect(Callable(self, "_on_blend_slider_changed"))
	blend_row.add_child(_blend_slider)

	_blend_spin = SpinBox.new()
	_blend_spin.min_value = 0.0
	_blend_spin.max_value = 1.0
	_blend_spin.step = 0.01
	_blend_spin.value = 0.5
	_blend_spin.custom_minimum_size = Vector2(60, 0)
	_blend_spin.value_changed.connect(Callable(self, "_on_blend_spin_changed"))
	blend_row.add_child(_blend_spin)

	_blend_preview_btn = Button.new()
	_blend_preview_btn.text = tr("Play blend")
	_blend_preview_btn.pressed.connect(Callable(self, "_on_play_blend"))
	blend_row.add_child(_blend_preview_btn)

	# Apply icons to advanced tab buttons
	_apply_advanced_icons()


func _apply_advanced_icons() -> void:
	if _editor == null:
		return
	var theme := _editor.get_editor_theme()
	if theme == null:
		return

	if theme.has_icon("Play", "EditorIcons"):
		var play_icon := theme.get_icon("Play", "EditorIcons")
		_play_a_btn.icon = play_icon
		_play_b_btn.icon = play_icon
		_blend_preview_btn.icon = play_icon
	if theme.has_icon("Loop", "EditorIcons"):
		_alternate_btn.icon = theme.get_icon("Loop", "EditorIcons")

# ---------- Builders ----------
# Add a header label to a grid container.
func _add_header_cell(grid: GridContainer, text: String, tooltip: String = "") -> void:
	var l := Label.new()
	l.text = text
	if tooltip != "":
		l.tooltip_text = tooltip
	grid.add_child(l)

# Add a labeled row with slider + spinbox + random button.
func _add_float_field(grid: GridContainer, label: String, prop: String, minv: float, maxv: float, step: float) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(row)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(Callable(self, "_on_param_slider_changed").bind(prop))
	row.add_child(slider)

	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.step = step
	sb.custom_minimum_size = Vector2(80, 0)
	sb.value_changed.connect(Callable(self, "_on_param_spin_changed").bind(prop))
	row.add_child(sb)

	var rand := Button.new()
	rand.text = "Rnd"
	rand.pressed.connect(Callable(self, "_on_param_random_pressed").bind(prop))
	row.add_child(rand)

	var widgets := ParamWidgets.new()
	widgets.slider = slider
	widgets.spin = sb
	widgets.rand_btn = rand
	widgets.minv = minv
	widgets.maxv = maxv
	widgets.step = step
	_param_widgets[prop] = widgets

# Register a formant group in the selector.
func _add_formant_option(label: String, prop: String) -> void:
	_formant_select.add_item(label)
	_formant_props.append(prop)

# Add a phoneme preview button.
func _add_phoneme_preview_btn(container: HBoxContainer, phoneme: String, tooltip: String) -> void:
	var btn := Button.new()
	btn.text = phoneme
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(32, 0)
	btn.pressed.connect(Callable(self, "_on_phoneme_preview_pressed").bind(phoneme))
	container.add_child(btn)

# Create a single F1/F2/F3 row (freq, Q, amp).
func _add_formant_row(grid: GridContainer, idx: int) -> void:
	var row_label := Label.new()
	var row_names := [tr("F1 (openness)"), tr("F2 (frontness)"), tr("F3 (color)")]
	if idx < row_names.size():
		row_label.text = row_names[idx]
	else:
		row_label.text = "F%d" % (idx + 1)
	if idx == 0:
		row_label.tooltip_text = tr("F1: vowel openness (higher = more open vowel).")
	elif idx == 1:
		row_label.tooltip_text = tr("F2: frontness (higher = brighter).")
	elif idx == 2:
		row_label.tooltip_text = tr("F3: fine timbre color.")
	grid.add_child(row_label)

	var freq_box := HBoxContainer.new()
	freq_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(freq_box)

	var freq_slider := HSlider.new()
	freq_slider.min_value = 20.0
	freq_slider.max_value = 10000.0
	freq_slider.step = 1.0
	freq_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	freq_slider.tooltip_text = tr("Resonance frequency (Hz).")
	freq_slider.value_changed.connect(Callable(self, "_on_formant_slider_changed").bind(idx, 0))
	freq_box.add_child(freq_slider)

	var freq_spin := SpinBox.new()
	freq_spin.min_value = 20.0
	freq_spin.max_value = 10000.0
	freq_spin.step = 1.0
	freq_spin.custom_minimum_size = Vector2(70, 0)
	freq_spin.tooltip_text = tr("Resonance frequency (Hz).")
	freq_spin.value_changed.connect(Callable(self, "_on_formant_spin_changed").bind(idx, 0))
	freq_box.add_child(freq_spin)

	var q_box := HBoxContainer.new()
	q_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(q_box)

	var q_slider := HSlider.new()
	q_slider.min_value = 0.1
	q_slider.max_value = 30.0
	q_slider.step = 0.1
	q_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q_slider.tooltip_text = tr("Resonance/Q: bandwidth (higher = narrower).")
	q_slider.value_changed.connect(Callable(self, "_on_formant_slider_changed").bind(idx, 1))
	q_box.add_child(q_slider)

	var q_spin := SpinBox.new()
	q_spin.min_value = 0.1
	q_spin.max_value = 30.0
	q_spin.step = 0.1
	q_spin.custom_minimum_size = Vector2(70, 0)
	q_spin.tooltip_text = tr("Resonance/Q: bandwidth (higher = narrower).")
	q_spin.value_changed.connect(Callable(self, "_on_formant_spin_changed").bind(idx, 1))
	q_box.add_child(q_spin)

	var amp_box := HBoxContainer.new()
	amp_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(amp_box)

	var amp_slider := HSlider.new()
	amp_slider.min_value = 0.0
	amp_slider.max_value = 2.0
	amp_slider.step = 0.01
	amp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amp_slider.tooltip_text = tr("Gain: resonance strength.")
	amp_slider.value_changed.connect(Callable(self, "_on_formant_slider_changed").bind(idx, 2))
	amp_box.add_child(amp_slider)

	var amp_spin := SpinBox.new()
	amp_spin.min_value = 0.0
	amp_spin.max_value = 2.0
	amp_spin.step = 0.01
	amp_spin.custom_minimum_size = Vector2(70, 0)
	amp_spin.tooltip_text = tr("Gain: resonance strength.")
	amp_spin.value_changed.connect(Callable(self, "_on_formant_spin_changed").bind(idx, 2))
	amp_box.add_child(amp_spin)

	var action_box := HBoxContainer.new()
	grid.add_child(action_box)

	var lock := CheckBox.new()
	lock.text = tr("Lock")
	lock.tooltip_text = tr("Lock editing of this row.")
	lock.toggled.connect(Callable(self, "_on_formant_lock_toggled").bind(idx))
	action_box.add_child(lock)

	var reset_btn := Button.new()
	reset_btn.text = tr("Reset")
	reset_btn.tooltip_text = tr("Restore default values.")
	reset_btn.pressed.connect(Callable(self, "_on_formant_row_reset_pressed").bind(idx))
	action_box.add_child(reset_btn)

	var row := FormantRow.new()
	row.freq_spin = freq_spin
	row.q_spin = q_spin
	row.amp_spin = amp_spin
	row.freq_slider = freq_slider
	row.q_slider = q_slider
	row.amp_slider = amp_slider
	row.lock = lock
	row.reset_btn = reset_btn
	_formant_rows.append(row)

# ---------- Voice selection ----------
# Current voice resource selected in the picker.
func _get_voice() -> AnimaleseVoice:
	return _voice_picker.edited_resource as AnimaleseVoice

# Refresh UI when the picker resource changes (Godot 4.0+).
func _on_voice_picker_changed(_res: Resource) -> void:
	_refresh_ui_from_voice(_get_voice())

# Refresh UI when the picker resource is selected (older signal variant).
func _on_voice_picker_selected(_res: Resource, _inspect: bool = false) -> void:
	_refresh_ui_from_voice(_get_voice())

# ---------- Inspector / Save ----------
# Open the selected voice resource in the inspector.
func _on_edit_voice_in_inspector() -> void:
	if _editor == null:
		return
	var v := _get_voice()
	if v != null:
		_editor.edit_resource(v)

# Save the selected voice resource (if it has a path).
func _on_save_voice() -> void:
	var v := _get_voice()
	if v == null:
		return
	if v.resource_path == "":
		return
	ResourceSaver.save(v, v.resource_path)


# ---------- Voice Wizard ----------

func _on_open_wizard() -> void:
	if _wizard != null:
		_wizard.queue_free()
		_wizard = null

	var WizardClass = preload("res://addons/procedural_animalese/voice_wizard.gd")
	_wizard = WizardClass.new()
	_wizard.preview_requested.connect(_on_wizard_preview_requested)
	_wizard.voice_created.connect(_on_wizard_voice_created)
	add_child(_wizard)
	_wizard.popup_centered()


func _on_wizard_preview_requested(voice: AnimaleseVoice, text: String) -> void:
	request_preview.emit(voice, text, 1.0)


func _on_wizard_voice_created(voice: AnimaleseVoice) -> void:
	# Load the newly created voice into the picker
	if _voice_picker != null and voice != null and not voice.resource_path.is_empty():
		var loaded_voice := load(voice.resource_path)
		if loaded_voice:
			_voice_picker.edited_resource = loaded_voice
			_on_voice_picker_changed(loaded_voice)
	if _wizard != null:
		_wizard.queue_free()
		_wizard = null


# ---------- Browser ----------
func _on_open_browser() -> void:
	if _browser != null:
		_browser.queue_free()
		_browser = null

	var BrowserClass = preload("res://addons/procedural_animalese/voice_preset_browser.gd")
	_browser = BrowserClass.new()
	_browser.set_editor(_editor)
	_browser.preview_requested.connect(_on_browser_preview_requested)
	_browser.voice_selected.connect(_on_browser_voice_selected)
	add_child(_browser)
	_browser.popup_centered()


func _on_browser_preview_requested(voice: AnimaleseVoice, text: String) -> void:
	request_preview.emit(voice, text, 1.0)


func _on_browser_voice_selected(voice: AnimaleseVoice, path: String) -> void:
	if _voice_picker != null and voice != null:
		_voice_picker.edited_resource = voice
		_on_voice_picker_changed(voice)
	if _browser != null:
		_browser.queue_free()
		_browser = null


# ---------- Preview ----------
# Emit preview request with current text and pitch multiplier.
func _on_play_preview() -> void:
	var v := _get_voice()
	if v == null:
		return
	request_preview.emit(v, _preview_text.text, float(_pitch.value))

# ---------- Waveform ----------
# Receive waveform data from the editor plugin.
func set_waveform_samples(samples: PackedFloat32Array) -> void:
	if _waveform_graph != null:
		_waveform_graph.set_samples(samples)

func _on_waveform_toggled(pressed: bool) -> void:
	if _waveform_graph != null:
		_waveform_graph.visible = pressed
	if _waveform_zoom_slider != null:
		_waveform_zoom_slider.get_parent().visible = pressed
	if _waveform_toggle != null:
		_waveform_toggle.text = tr("Waveform") + " [-]" if pressed else tr("Waveform") + " [+]"

func _on_waveform_zoom_changed(value: float) -> void:
	if _waveform_graph != null:
		_waveform_graph.set_view_zoom(value)

func _on_waveform_clear_pressed() -> void:
	if _waveform_graph != null:
		_waveform_graph.clear()

# ---------- Params group ----------
func _on_params_toggled(pressed: bool) -> void:
	if _params_container != null:
		_params_container.visible = pressed
	if _params_toggle != null:
		_params_toggle.text = tr("Parameters") + " [-]" if pressed else tr("Parameters") + " [+]"

# ---------- Voice name ----------
func _on_voice_name_submitted(text: String) -> void:
	_commit_voice_name(text)

func _on_voice_name_focus_exited() -> void:
	if _voice_name_edit == null:
		return
	_commit_voice_name(_voice_name_edit.text)

func _commit_voice_name(text: String) -> void:
	if _updating_ui:
		return
	var v := _get_voice()
	if v == null:
		return
	_apply_property_change(v, "voice_name", text)

# ---------- Params editing ----------
# Push a change from UI to the voice resource.
func _on_param_spin_changed(value: float, prop: String) -> void:
	if _updating_ui:
		return
	_set_param_value(prop, value)

# Push a change from slider to the voice resource.
func _on_param_slider_changed(value: float, prop: String) -> void:
	if _updating_ui:
		return
	_set_param_value(prop, value)

# Randomize a single parameter within its configured range.
func _on_param_random_pressed(prop: String) -> void:
	if _updating_ui:
		return
	var widgets: ParamWidgets = _param_widgets.get(prop)
	if widgets == null:
		return

	var seed_val: int = 0
	if _seed_box != null:
		seed_val = int(_seed_box.value)
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()

	var value: float = _random_step_value(widgets.minv, widgets.maxv, widgets.step)
	_set_param_value(prop, value)

# Sync slider + spinbox and apply the property change once.
func _set_param_value(prop: String, value: float) -> void:
	var v := _get_voice()
	if v == null:
		return
	var widgets: ParamWidgets = _param_widgets.get(prop)
	_updating_ui = true
	if widgets != null:
		widgets.spin.value = value
		widgets.slider.value = value
	_updating_ui = false
	_apply_property_change(v, prop, value)

# Apply a property change with undo/redo if available.
func _apply_property_change(obj: Object, prop: String, new_val: Variant) -> void:
	var old_val: Variant = obj.get(prop)
	if old_val == new_val:
		return

	if _undo_redo != null:
		_undo_redo.create_action(tr("Change %s") % prop)
		_undo_redo.add_do_property(obj, prop, new_val)
		_undo_redo.add_undo_property(obj, prop, old_val)
		_undo_redo.commit_action()
	else:
		obj.set(prop, new_val)

# Pick a random value snapped to step within a min/max range.
func _random_step_value(minv: float, maxv: float, step: float) -> float:
	if step <= 0.0:
		return _rng.randf_range(minv, maxv)
	var steps: int = int(round((maxv - minv) / step))
	if steps <= 0:
		return minv
	var idx: int = _rng.randi_range(0, steps)
	return _clampf(minv + float(idx) * step, minv, maxv)

# ---------- Vowel chart ----------
func _on_vowel_chart_toggled(pressed: bool) -> void:
	if _vowel_chart != null:
		_vowel_chart.visible = pressed
	if _vowel_chart_toggle != null:
		_vowel_chart_toggle.text = tr("Vowel chart") + " [-]" if pressed else tr("Vowel chart") + " [+]"

func _refresh_vowel_chart() -> void:
	if _vowel_chart == null:
		return
	var v := _get_voice()
	if v == null:
		_vowel_chart.set_vowels({})
		return

	# Extract F1 and F2 from each vowel's formants
	var vowel_data: Dictionary = {}
	var vowel_props := {
		"a": "vowel_a_formants",
		"e": "vowel_e_formants",
		"i": "vowel_i_formants",
		"o": "vowel_o_formants",
		"u": "vowel_u_formants",
	}
	for name in vowel_props.keys():
		var prop: String = vowel_props[name]
		var arr: Array = v.get(prop) as Array
		if arr != null and arr.size() >= 2:
			var f1: float = (arr[0] as Vector3).x
			var f2: float = (arr[1] as Vector3).x
			vowel_data[name] = Vector2(f1, f2)

	_vowel_chart.set_vowels(vowel_data)

# ---------- Phoneme preview ----------
# Play a short preview of a single phoneme.
func _on_phoneme_preview_pressed(phoneme: String) -> void:
	var v := _get_voice()
	if v == null:
		return
	# Generate a short syllable to preview the phoneme sound
	var preview_text: String = phoneme + phoneme + phoneme
	request_preview.emit(v, preview_text, float(_pitch.value))

# ---------- Formant graph interaction ----------
# Handle formant changes from the interactive graph.
func _on_formant_graph_changed(index: int, freq: float, amp: float) -> void:
	if _updating_ui:
		return
	if index < 0 or index >= _formant_rows.size():
		return
	var row: FormantRow = _formant_rows[index]
	if row.lock != null and row.lock.button_pressed:
		return

	var v := _get_voice()
	if v == null:
		return
	var prop := _current_formant_prop()
	if prop == "":
		return
	var arr: Array = v.get(prop) as Array
	if arr == null or arr.size() <= index:
		return

	# Get current Q value (we only change freq and amp from graph)
	var current_vec: Vector3 = arr[index] as Vector3
	var new_vec := Vector3(freq, current_vec.y, amp)

	var new_arr: Array = arr.duplicate(true)
	new_arr[index] = new_vec

	# Update UI
	_updating_ui = true
	row.freq_spin.value = freq
	row.freq_slider.value = freq
	row.amp_spin.value = amp
	row.amp_slider.value = amp
	_updating_ui = false

	# Apply change
	_apply_property_change(v, prop, new_arr)
	if _formant_graph != null:
		_formant_graph.set_formants(new_arr)
	# Update vowel chart if we changed a vowel
	if prop.begins_with("vowel_"):
		_refresh_vowel_chart()

# ---------- Formants editing ----------
# Update formant editor when the group changes.
func _on_formant_selected(_idx: int) -> void:
	_refresh_formant_ui()

# Current formant property name from the selector.
func _current_formant_prop() -> String:
	if _formant_select.item_count == 0:
		return ""
	var idx: int = _formant_select.selected
	if idx < 0 or idx >= _formant_props.size():
		return ""
	return _formant_props[idx]

# Copy the current formant group into a local buffer.
func _on_formant_copy_pressed() -> void:
	var v := _get_voice()
	if v == null:
		return
	var prop := _current_formant_prop()
	if prop == "":
		return
	var arr: Array = v.get(prop) as Array
	if arr == null or arr.size() < 3:
		return
	_formant_copy_buffer = arr.duplicate(true)
	if _formant_paste_btn != null:
		_formant_paste_btn.disabled = false

# Paste the copied formant group into the current group.
func _on_formant_paste_pressed() -> void:
	var v := _get_voice()
	if v == null:
		return
	if _formant_copy_buffer.is_empty():
		return
	var prop := _current_formant_prop()
	if prop == "":
		return
	if _formant_copy_buffer.size() < 3:
		return
	var new_arr: Array = _formant_copy_buffer.duplicate(true)
	_apply_property_change(v, prop, new_arr)
	_refresh_formant_ui()

# Reset the current formant group to defaults.
func _on_formant_group_reset_pressed() -> void:
	var v := _get_voice()
	if v == null:
		return
	var prop := _current_formant_prop()
	if prop == "":
		return
	var defaults: Array = _get_default_formants(prop)
	if defaults == null or defaults.size() < 3:
		return
	_apply_property_change(v, prop, defaults.duplicate(true))
	_refresh_formant_ui()

# Apply a preset transform to the current formant group.
func _on_formant_preset_apply_pressed() -> void:
	var v := _get_voice()
	if v == null:
		return
	var prop := _current_formant_prop()
	if prop == "":
		return
	var arr: Array = v.get(prop) as Array
	if arr == null or arr.size() < 3:
		return

	var preset_id: int = _formant_preset_select.selected
	var new_arr: Array

	match preset_id:
		0: # Default
			var defaults: Array = _get_default_formants(prop)
			if defaults.size() < 3:
				return
			new_arr = defaults.duplicate(true)
		1: # Brillante
			new_arr = _apply_formant_transform(arr, 1.08, 1.0, 1.10)
		2: # Oscuro
			new_arr = _apply_formant_transform(arr, 0.92, 1.0, 0.90)
		3: # Nasal
			new_arr = _apply_formant_transform(arr, 0.95, 1.15, 1.10)
		4: # Muy brillante
			new_arr = _apply_formant_transform(arr, 1.16, 1.05, 1.25)
		5: # Muy oscuro
			new_arr = _apply_formant_transform(arr, 0.85, 0.95, 0.75)
		6: # Suave
			new_arr = _apply_formant_transform(arr, 0.98, 0.80, 0.85)
		7: # Enfocado
			new_arr = _apply_formant_transform(arr, 1.02, 1.35, 1.05)
		8: # Ancho (Q bajo)
			new_arr = _apply_formant_transform(arr, 1.00, 0.70, 0.95)
		9: # Metalico
			new_arr = _apply_formant_transform(arr, 1.08, 1.55, 1.20)
		_:
			new_arr = arr.duplicate(true)

	_apply_property_change(v, prop, new_arr)
	_refresh_formant_ui()

func _on_formant_preset_toggled(pressed: bool) -> void:
	if _formant_preset_row != null:
		_formant_preset_row.visible = pressed
	if _formant_preset_toggle != null:
		_formant_preset_toggle.text = tr("Presets") + " [-]" if pressed else tr("Presets") + " [+]"

func _get_default_formants(prop: String) -> Array:
	if _default_formants_cache.has(prop):
		return _default_formants_cache[prop]
	if _default_voice == null:
		return []
	var arr: Array = _default_voice.get(prop) as Array
	if arr == null:
		return []
	var dup: Array = arr.duplicate(true)
	_default_formants_cache[prop] = dup
	return dup

func _apply_formant_transform(arr: Array, freq_mul: float, q_mul: float, amp_mul: float) -> Array:
	var new_arr: Array = arr.duplicate(true)
	for i in range(min(3, new_arr.size())):
		var v3: Vector3 = new_arr[i] as Vector3
		var f: float = _clampf(v3.x * freq_mul, 20.0, 10000.0)
		var q: float = _clampf(v3.y * q_mul, 0.1, 30.0)
		var a: float = _clampf(v3.z * amp_mul, 0.0, 2.0)
		new_arr[i] = Vector3(f, q, a)
	return new_arr

func _get_locked_formant_indices() -> Array[int]:
	var out: Array[int] = []
	for i in range(_formant_rows.size()):
		var row: FormantRow = _formant_rows[i]
		if row.lock != null and row.lock.button_pressed:
			out.append(i)
	return out

# Update one component (freq/Q/amp) of a formant vector.
func _on_formant_spin_changed(value: float, formant_index: int, component: int) -> void:
	if _updating_ui:
		return
	var row: FormantRow = _formant_rows[formant_index]
	if row.lock != null and row.lock.button_pressed:
		return
	_set_formant_value(formant_index, component, value)

# Update one component (freq/Q/amp) of a formant vector from slider.
func _on_formant_slider_changed(value: float, formant_index: int, component: int) -> void:
	if _updating_ui:
		return
	var row: FormantRow = _formant_rows[formant_index]
	if row.lock != null and row.lock.button_pressed:
		return
	_set_formant_value(formant_index, component, value)

# Lock/unlock a formant row and refresh control state.
func _on_formant_lock_toggled(_pressed: bool, _idx: int) -> void:
	_set_formant_controls_enabled(_formant_controls_enabled)

# Reset a single formant row to defaults.
func _on_formant_row_reset_pressed(idx: int) -> void:
	var v := _get_voice()
	if v == null:
		return
	var prop := _current_formant_prop()
	if prop == "":
		return
	var defaults: Array = _get_default_formants(prop)
	if defaults == null or defaults.size() < 3:
		return

	var arr: Array = v.get(prop) as Array
	if arr == null or arr.size() < 3:
		return
	var new_arr: Array = arr.duplicate(true)
	new_arr[idx] = defaults[idx]
	_apply_property_change(v, prop, new_arr)
	_refresh_formant_ui()

func _set_formant_value(formant_index: int, component: int, value: float) -> void:
	var v := _get_voice()
	if v == null:
		return

	var prop := _current_formant_prop()
	if prop == "":
		return

	var arr: Array = v.get(prop) as Array
	if arr == null or arr.size() < 3:
		return

	var vec: Vector3 = arr[formant_index] as Vector3
	if component == 0:
		vec.x = value
	elif component == 1:
		vec.y = value
	else:
		vec.z = value

	var new_arr: Array = arr.duplicate(true)
	new_arr[formant_index] = vec

	_updating_ui = true
	var row: FormantRow = _formant_rows[formant_index]
	if component == 0:
		row.freq_spin.value = value
		row.freq_slider.value = value
	elif component == 1:
		row.q_spin.value = value
		row.q_slider.value = value
	else:
		row.amp_spin.value = value
		row.amp_slider.value = value
	_updating_ui = false

	_apply_property_change(v, prop, new_arr)
	if _formant_graph != null:
		_formant_graph.set_formants(new_arr)
	# Update vowel chart if we changed a vowel
	if prop.begins_with("vowel_"):
		_refresh_vowel_chart()

# Populate formant UI from the selected voice property.
func _refresh_formant_ui() -> void:
	var v := _get_voice()
	if v == null:
		_set_formant_controls_enabled(false)
		if _formant_graph != null:
			_formant_graph.set_formants([])
		return

	var prop := _current_formant_prop()
	if prop == "":
		_set_formant_controls_enabled(false)
		if _formant_graph != null:
			_formant_graph.set_formants([])
		return

	var arr: Array = v.get(prop) as Array
	if arr == null or arr.size() < 3:
		_set_formant_controls_enabled(false)
		if _formant_graph != null:
			_formant_graph.set_formants([])
		return

	_updating_ui = true
	_set_formant_controls_enabled(true)

	for i in range(3):
		var vec: Vector3 = arr[i] as Vector3
		var row: FormantRow = _formant_rows[i]
		row.freq_spin.value = float(vec.x)
		row.freq_slider.value = float(vec.x)
		row.q_spin.value = float(vec.y)
		row.q_slider.value = float(vec.y)
		row.amp_spin.value = float(vec.z)
		row.amp_slider.value = float(vec.z)

	_updating_ui = false
	if _formant_graph != null:
		_formant_graph.set_formants(arr)

# Enable/disable formant controls as a group.
func _set_formant_controls_enabled(enabled: bool) -> void:
	_formant_controls_enabled = enabled
	for row in _formant_rows:
		var row_enabled: bool = enabled and not row.lock.button_pressed
		row.freq_spin.editable = row_enabled
		row.freq_slider.editable = row_enabled
		row.q_spin.editable = row_enabled
		row.q_slider.editable = row_enabled
		row.amp_spin.editable = row_enabled
		row.amp_slider.editable = row_enabled
		row.reset_btn.disabled = not row_enabled
		row.lock.disabled = not enabled

	if _formant_graph != null:
		_formant_graph.visible = enabled

# ---------- UI refresh ----------
# Sync all UI fields from the current voice resource.
func _refresh_ui_from_voice(v: AnimaleseVoice) -> void:
	var has_voice: bool = (v != null)

	_edit_in_inspector_btn.disabled = not has_voice
	_save_btn.disabled = not has_voice

	_updating_ui = true
	if _voice_name_edit != null:
		_voice_name_edit.editable = has_voice
		_voice_name_edit.text = v.voice_name if has_voice else ""
	for prop in _param_widgets.keys():
		var widgets: ParamWidgets = _param_widgets[prop]
		widgets.spin.editable = has_voice
		widgets.slider.editable = has_voice
		widgets.rand_btn.disabled = not has_voice
		var value: float = 0.0
		if has_voice:
			value = float(v.get(prop))
		widgets.spin.value = value
		widgets.slider.value = value
	_updating_ui = false

	if _formant_copy_btn != null:
		_formant_copy_btn.disabled = not has_voice
	if _formant_select != null:
		_formant_select.disabled = not has_voice
	if _formant_paste_btn != null:
		_formant_paste_btn.disabled = (not has_voice) or _formant_copy_buffer.is_empty()
	if _formant_reset_group_btn != null:
		_formant_reset_group_btn.disabled = not has_voice
	if _formant_preset_select != null:
		_formant_preset_select.disabled = not has_voice
	if _formant_preset_apply_btn != null:
		_formant_preset_apply_btn.disabled = not has_voice
	if _formant_preset_toggle != null:
		_formant_preset_toggle.disabled = not has_voice

	if has_voice:
		_seed_box.value = float(v.random_seed)

	_refresh_formant_ui()
	_refresh_vowel_chart()

# ==========================================================
# Randomización con locks + seed
# ==========================================================
# Apply seed value to the voice resource.
func _on_apply_seed_pressed() -> void:
	var v := _get_voice()
	if v == null:
		return
	_apply_property_change(v, "random_seed", int(_seed_box.value))

# Bump seed by one and apply it.
func _on_reroll_pressed() -> void:
	var v := _get_voice()
	if v == null:
		return
	var s: int = int(_seed_box.value)
	s += 1
	_seed_box.value = float(s)
	_apply_property_change(v, "random_seed", s)

func _on_random_subtle_pressed() -> void:
	_randomize_voice(false, false)

func _on_random_strong_pressed() -> void:
	_randomize_voice(true, false)

func _on_random_formants_pressed() -> void:
	_randomize_voice(false, true)

# Randomize voice parameters with locks and intensity controls.
func _randomize_voice(strong: bool, only_formants: bool) -> void:
	var v := _get_voice()
	if v == null:
		return

	var intensity: float = float(_rand_intensity.value)
	_rng.randomize()

	# Si hay seed, úsala para reproducibilidad
	var seed_val: int = int(_seed_box.value)
	if seed_val != 0:
		_rng.seed = seed_val

	var changes: Dictionary[String, Variant] = {}

	var pitch_locked: bool = _lock_pitch.button_pressed
	var timing_locked: bool = _lock_timing.button_pressed
	var timbre_locked: bool = _lock_timbre.button_pressed
	var formants_locked: bool = _lock_formants.button_pressed

	# Helpers
	var wide: float = 1.0 if strong else 0.0
	var amt: float = clampf(intensity, 0.0, 1.0)

	# Pitch/ritmo
	if (not only_formants) and (not pitch_locked):
		if strong:
			changes["pitch_base_hz"] = _rng.randf_range(120.0, 380.0)
			changes["pitch_jitter"] = _rng.randf_range(0.02, 0.16)
		else:
			changes["pitch_base_hz"] = _clampf(v.pitch_base_hz * _rng.randf_range(1.0 - 0.12 * amt, 1.0 + 0.12 * amt), 80.0, 600.0)
			changes["pitch_jitter"] = _clampf(v.pitch_jitter * _rng.randf_range(1.0 - 0.25 * amt, 1.0 + 0.25 * amt), 0.0, 0.25)

	if (not only_formants) and (not timing_locked):
		if strong:
			changes["char_duration_s"] = _rng.randf_range(0.03, 0.095)
			changes["consonant_duration_multiplier"] = _rng.randf_range(0.45, 1.05)
		else:
			changes["char_duration_s"] = _clampf(v.char_duration_s * _rng.randf_range(1.0 - 0.14 * amt, 1.0 + 0.14 * amt), 0.02, 0.12)
			changes["consonant_duration_multiplier"] = _clampf(v.consonant_duration_multiplier * _rng.randf_range(1.0 - 0.16 * amt, 1.0 + 0.16 * amt), 0.3, 1.2)

	# Timbre (no formantes)
	if (not only_formants) and (not timbre_locked):
		if strong:
			changes["output_gain"] = _rng.randf_range(0.55, 1.25)
			changes["breath_noise_level"] = _rng.randf_range(0.03, 0.55)
			changes["vocal_tract_scale"] = _rng.randf_range(0.70, 1.45)
			changes["vowel_formant_gain"] = _rng.randf_range(0.65, 1.45)
			changes["fricative_formant_gain"] = _rng.randf_range(0.65, 1.60)
			changes["stop_formant_gain"] = _rng.randf_range(0.65, 1.45)
			changes["nasal_formant_gain"] = _rng.randf_range(0.65, 1.45)
			changes["voiced_brightness"] = _rng.randf_range(0.25, 0.85)
			changes["vowel_breathiness"] = _rng.randf_range(0.0, 0.35)
		else:
			changes["output_gain"] = _clampf(v.output_gain * _rng.randf_range(1.0 - 0.15 * amt, 1.0 + 0.15 * amt), 0.0, 2.0)
			changes["breath_noise_level"] = _clampf(v.breath_noise_level * _rng.randf_range(1.0 - 0.25 * amt, 1.0 + 0.30 * amt), 0.0, 1.5)
			changes["vocal_tract_scale"] = _clampf(v.vocal_tract_scale * _rng.randf_range(1.0 - 0.10 * amt, 1.0 + 0.10 * amt), 0.5, 2.0)
			changes["vowel_formant_gain"] = _clampf(v.vowel_formant_gain * _rng.randf_range(1.0 - 0.15 * amt, 1.0 + 0.15 * amt), 0.0, 2.0)
			changes["fricative_formant_gain"] = _clampf(v.fricative_formant_gain * _rng.randf_range(1.0 - 0.18 * amt, 1.0 + 0.18 * amt), 0.0, 2.0)
			changes["stop_formant_gain"] = _clampf(v.stop_formant_gain * _rng.randf_range(1.0 - 0.15 * amt, 1.0 + 0.15 * amt), 0.0, 2.0)
			changes["nasal_formant_gain"] = _clampf(v.nasal_formant_gain * _rng.randf_range(1.0 - 0.15 * amt, 1.0 + 0.15 * amt), 0.0, 2.0)
			changes["voiced_brightness"] = _clampf(v.voiced_brightness + _rng.randf_range(-0.12 * amt, 0.12 * amt), 0.0, 1.0)
			changes["vowel_breathiness"] = _clampf(v.vowel_breathiness + _rng.randf_range(-0.10 * amt, 0.12 * amt), 0.0, 1.0)

	# Formantes
	if not formants_locked:
		var locked_prop: String = _current_formant_prop()
		var locked_indices: Array[int] = _get_locked_formant_indices()

		var freq_min: float
		var freq_max: float
		var q_min: float
		var q_max: float
		var amp_min: float
		var amp_max: float

		if strong:
			freq_min = 0.85; freq_max = 1.15
			q_min = 0.80; q_max = 1.25
			amp_min = 0.75; amp_max = 1.30
		else:
			freq_min = lerpf(0.95, 0.90, amt)
			freq_max = lerpf(1.05, 1.10, amt)
			q_min = lerpf(0.92, 0.85, amt)
			q_max = lerpf(1.08, 1.15, amt)
			amp_min = lerpf(0.92, 0.85, amt)
			amp_max = lerpf(1.08, 1.15, amt)

		_add_formant_group_variation(changes, v, freq_min, freq_max, q_min, q_max, amp_min, amp_max, locked_prop, locked_indices)

	_apply_bulk_changes(v, tr("Randomize voice"), changes)
	_refresh_ui_from_voice(v)

# Apply a set of property changes as one undo/redo action.
func _apply_bulk_changes(v: AnimaleseVoice, action_name: String, changes: Dictionary[String, Variant]) -> void:
	if changes.is_empty():
		return

	if _undo_redo != null:
		_undo_redo.create_action(action_name)
		for prop in changes.keys():
			var new_val: Variant = changes[prop]
			var old_val: Variant = v.get(prop)
			if old_val == new_val:
				continue
			_undo_redo.add_do_property(v, prop, new_val)
			_undo_redo.add_undo_property(v, prop, old_val)
		_undo_redo.commit_action()
	else:
		for prop in changes.keys():
			v.set(prop, changes[prop])

# Add randomized formant arrays for all formant groups.
func _add_formant_group_variation(
	changes: Dictionary[String, Variant],
	v: AnimaleseVoice,
	freq_min: float, freq_max: float,
	q_min: float, q_max: float,
	amp_min: float, amp_max: float,
	locked_prop: String,
	locked_indices: Array[int]
) -> void:
	var props: Array[String] = [
		"vowel_a_formants","vowel_e_formants","vowel_i_formants","vowel_o_formants","vowel_u_formants",
		"fricative_s_formants","fricative_f_formants","fricative_x_formants",
		"stop_p_formants","stop_t_formants","stop_k_formants",
		"nasal_mn_formants"
	]

	for prop in props:
		var arr: Array = v.get(prop) as Array
		if arr == null or arr.size() < 3:
			continue
		var row_locks: Array[int] = []
		if prop == locked_prop:
			row_locks = locked_indices
		changes[prop] = _randomize_formant_array(arr, freq_min, freq_max, q_min, q_max, amp_min, amp_max, row_locks)

# Randomize the first 3 formants in a given array.
func _randomize_formant_array(
	arr: Array,
	freq_min: float, freq_max: float,
	q_min: float, q_max: float,
	amp_min: float, amp_max: float,
	locked_indices: Array[int]
) -> Array:
	var new_arr: Array = arr.duplicate(true)
	for i in range(min(3, new_arr.size())):
		if locked_indices.has(i):
			new_arr[i] = arr[i]
			continue
		var v3: Vector3 = new_arr[i] as Vector3
		var f: float = _clampf(v3.x * _rng.randf_range(freq_min, freq_max), 20.0, 10000.0)
		var q: float = _clampf(v3.y * _rng.randf_range(q_min, q_max), 0.1, 30.0)
		var a: float = _clampf(v3.z * _rng.randf_range(amp_min, amp_max), 0.0, 2.0)
		new_arr[i] = Vector3(f, q, a)
	return new_arr

# Local clamp helper to keep values in range.
func _clampf(x: float, lo: float, hi: float) -> float:
	return clampf(x, lo, hi)

# ==========================================================
# A/B Comparison
# ==========================================================
func _on_ab_toggled(pressed: bool) -> void:
	var content := _ab_container.get_node_or_null("ABContent")
	if content != null:
		content.visible = pressed
	if _ab_toggle != null:
		_ab_toggle.text = tr("A/B Comparison") + " [-]" if pressed else tr("A/B Comparison") + " [+]"

func _on_play_voice_a() -> void:
	var v := _get_voice()
	if v == null:
		return
	request_preview.emit(v, _preview_text.text, float(_pitch.value))

func _on_play_voice_b() -> void:
	var v := _voice_picker_b.edited_resource as AnimaleseVoice
	if v == null:
		return
	request_preview.emit(v, _preview_text.text, float(_pitch.value))

func _on_alternate_ab() -> void:
	if _ab_current == 0:
		_on_play_voice_b()
		_ab_current = 1
	else:
		_on_play_voice_a()
		_ab_current = 0

func _on_blend_slider_changed(value: float) -> void:
	if _updating_ui:
		return
	_updating_ui = true
	_blend_spin.value = value
	_updating_ui = false

func _on_blend_spin_changed(value: float) -> void:
	if _updating_ui:
		return
	_updating_ui = true
	_blend_slider.value = value
	_updating_ui = false

func _on_play_blend() -> void:
	var voice_a := _get_voice()
	var voice_b := _voice_picker_b.edited_resource as AnimaleseVoice
	if voice_a == null or voice_b == null:
		return
	var factor: float = _blend_slider.value
	var blended: AnimaleseVoice = blend_voices(voice_a, voice_b, factor)
	request_preview.emit(blended, _preview_text.text, float(_pitch.value))

# ==========================================================
# Voice Blending
# ==========================================================
# Interpolate all numeric parameters between two voices.
# factor = 0.0 -> voice_a, factor = 1.0 -> voice_b
static func blend_voices(voice_a: AnimaleseVoice, voice_b: AnimaleseVoice, factor: float) -> AnimaleseVoice:
	var result := AnimaleseVoice.new()
	var t: float = clampf(factor, 0.0, 1.0)

	# Basic parameters
	result.voice_name = voice_a.voice_name + " + " + voice_b.voice_name if t > 0.0 and t < 1.0 else (voice_b.voice_name if t >= 0.5 else voice_a.voice_name)
	result.pitch_base_hz = lerpf(voice_a.pitch_base_hz, voice_b.pitch_base_hz, t)
	result.pitch_jitter = lerpf(voice_a.pitch_jitter, voice_b.pitch_jitter, t)
	result.char_duration_s = lerpf(voice_a.char_duration_s, voice_b.char_duration_s, t)
	result.consonant_duration_multiplier = lerpf(voice_a.consonant_duration_multiplier, voice_b.consonant_duration_multiplier, t)

	# Vibrato
	result.vibrato_rate_hz = lerpf(voice_a.vibrato_rate_hz, voice_b.vibrato_rate_hz, t)
	result.vibrato_depth = lerpf(voice_a.vibrato_depth, voice_b.vibrato_depth, t)
	result.vibrato_delay = lerpf(voice_a.vibrato_delay, voice_b.vibrato_delay, t)

	# Mix and character
	result.output_gain = lerpf(voice_a.output_gain, voice_b.output_gain, t)
	result.breath_noise_level = lerpf(voice_a.breath_noise_level, voice_b.breath_noise_level, t)
	result.vocal_tract_scale = lerpf(voice_a.vocal_tract_scale, voice_b.vocal_tract_scale, t)
	result.vowel_formant_gain = lerpf(voice_a.vowel_formant_gain, voice_b.vowel_formant_gain, t)
	result.fricative_formant_gain = lerpf(voice_a.fricative_formant_gain, voice_b.fricative_formant_gain, t)
	result.stop_formant_gain = lerpf(voice_a.stop_formant_gain, voice_b.stop_formant_gain, t)
	result.nasal_formant_gain = lerpf(voice_a.nasal_formant_gain, voice_b.nasal_formant_gain, t)

	# Prosody
	result.prosody_strength = lerpf(voice_a.prosody_strength, voice_b.prosody_strength, t)
	result.question_rise = lerpf(voice_a.question_rise, voice_b.question_rise, t)
	result.statement_fall = lerpf(voice_a.statement_fall, voice_b.statement_fall, t)
	result.exclamation_boost = lerpf(voice_a.exclamation_boost, voice_b.exclamation_boost, t)
	result.vowel_breathiness = lerpf(voice_a.vowel_breathiness, voice_b.vowel_breathiness, t)
	result.voiced_brightness = lerpf(voice_a.voiced_brightness, voice_b.voiced_brightness, t)

	# Envelope
	result.envelope_attack = lerpf(voice_a.envelope_attack, voice_b.envelope_attack, t)
	result.envelope_sustain = lerpf(voice_a.envelope_sustain, voice_b.envelope_sustain, t)
	result.envelope_release = lerpf(voice_a.envelope_release, voice_b.envelope_release, t)

	# Coarticulation
	result.coarticulation_strength = lerpf(voice_a.coarticulation_strength, voice_b.coarticulation_strength, t)
	result.coarticulation_window = lerpf(voice_a.coarticulation_window, voice_b.coarticulation_window, t)

	# Edge fade
	result.segment_edge_fade_ms = lerpf(voice_a.segment_edge_fade_ms, voice_b.segment_edge_fade_ms, t)

	# Seed (use A's seed if t < 0.5, else B's)
	result.random_seed = voice_a.random_seed if t < 0.5 else voice_b.random_seed

	# Formants - interpolate each Vector3
	result.vowel_a_formants = _blend_formants(voice_a.vowel_a_formants, voice_b.vowel_a_formants, t)
	result.vowel_e_formants = _blend_formants(voice_a.vowel_e_formants, voice_b.vowel_e_formants, t)
	result.vowel_i_formants = _blend_formants(voice_a.vowel_i_formants, voice_b.vowel_i_formants, t)
	result.vowel_o_formants = _blend_formants(voice_a.vowel_o_formants, voice_b.vowel_o_formants, t)
	result.vowel_u_formants = _blend_formants(voice_a.vowel_u_formants, voice_b.vowel_u_formants, t)
	result.fricative_s_formants = _blend_formants(voice_a.fricative_s_formants, voice_b.fricative_s_formants, t)
	result.fricative_f_formants = _blend_formants(voice_a.fricative_f_formants, voice_b.fricative_f_formants, t)
	result.fricative_x_formants = _blend_formants(voice_a.fricative_x_formants, voice_b.fricative_x_formants, t)
	result.stop_p_formants = _blend_formants(voice_a.stop_p_formants, voice_b.stop_p_formants, t)
	result.stop_t_formants = _blend_formants(voice_a.stop_t_formants, voice_b.stop_t_formants, t)
	result.stop_k_formants = _blend_formants(voice_a.stop_k_formants, voice_b.stop_k_formants, t)
	result.nasal_mn_formants = _blend_formants(voice_a.nasal_mn_formants, voice_b.nasal_mn_formants, t)

	return result

# Interpolate formant arrays (Array[Vector3]).
static func _blend_formants(arr_a: Array[Vector3], arr_b: Array[Vector3], t: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count: int = mini(arr_a.size(), arr_b.size())
	for i in range(count):
		var va: Vector3 = arr_a[i]
		var vb: Vector3 = arr_b[i]
		result.append(va.lerp(vb, t))
	return result
