@tool
## Wizard dialog for creating new AnimaleseVoice resources step by step.
extends AcceptDialog
class_name VoiceWizard

signal voice_created(voice: AnimaleseVoice)
signal preview_requested(voice: AnimaleseVoice, text: String)

const STEP_COUNT: int = 4

## Voice presets for quick start.
enum VoicePreset {
	CUSTOM,
	MASCULINE,
	FEMININE,
	CHILD,
	ELDER,
	ROBOT,
	MONSTER,
	GHOST,
	WHISPER,
}

var _current_step: int = 0
var _voice: AnimaleseVoice = null
var _current_preset: VoicePreset = VoicePreset.CUSTOM
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Randomization limits per preset: {param: [min, max]}
const PRESET_LIMITS: Dictionary = {
	VoicePreset.CUSTOM: {
		"pitch": [100.0, 400.0],
		"duration": [0.035, 0.085],
		"jitter": [0.02, 0.15],
		"breathiness": [0.05, 0.40],
		"whisper": [0.0, 0.3],
		"vibrato_rate": [0.0, 6.0],
		"vibrato_depth": [0.0, 0.20],
	},
	VoicePreset.MASCULINE: {
		"pitch": [95.0, 180.0],
		"duration": [0.050, 0.075],
		"jitter": [0.03, 0.08],
		"breathiness": [0.05, 0.25],
		"whisper": [0.0, 0.1],
		"vibrato_rate": [0.0, 3.0],
		"vibrato_depth": [0.0, 0.10],
	},
	VoicePreset.FEMININE: {
		"pitch": [200.0, 340.0],
		"duration": [0.042, 0.065],
		"jitter": [0.04, 0.12],
		"breathiness": [0.10, 0.35],
		"whisper": [0.0, 0.15],
		"vibrato_rate": [2.0, 6.0],
		"vibrato_depth": [0.04, 0.15],
	},
	VoicePreset.CHILD: {
		"pitch": [280.0, 450.0],
		"duration": [0.035, 0.055],
		"jitter": [0.06, 0.18],
		"breathiness": [0.12, 0.35],
		"whisper": [0.0, 0.1],
		"vibrato_rate": [0.0, 2.0],
		"vibrato_depth": [0.0, 0.08],
	},
	VoicePreset.ELDER: {
		"pitch": [120.0, 200.0],
		"duration": [0.060, 0.090],
		"jitter": [0.05, 0.14],
		"breathiness": [0.15, 0.45],
		"whisper": [0.05, 0.25],
		"vibrato_rate": [3.0, 7.0],
		"vibrato_depth": [0.08, 0.25],
	},
	VoicePreset.ROBOT: {
		"pitch": [120.0, 250.0],
		"duration": [0.050, 0.075],
		"jitter": [0.0, 0.02],
		"breathiness": [0.0, 0.05],
		"whisper": [0.0, 0.0],
		"vibrato_rate": [0.0, 0.0],
		"vibrato_depth": [0.0, 0.0],
	},
	VoicePreset.MONSTER: {
		"pitch": [70.0, 130.0],
		"duration": [0.065, 0.095],
		"jitter": [0.08, 0.20],
		"breathiness": [0.35, 0.70],
		"whisper": [0.1, 0.4],
		"vibrato_rate": [1.5, 5.0],
		"vibrato_depth": [0.10, 0.30],
	},
	VoicePreset.GHOST: {
		"pitch": [160.0, 280.0],
		"duration": [0.055, 0.080],
		"jitter": [0.02, 0.08],
		"breathiness": [0.30, 0.60],
		"whisper": [0.35, 0.70],
		"vibrato_rate": [1.5, 4.0],
		"vibrato_depth": [0.08, 0.20],
	},
	VoicePreset.WHISPER: {
		"pitch": [180.0, 280.0],
		"duration": [0.050, 0.075],
		"jitter": [0.01, 0.06],
		"breathiness": [0.20, 0.50],
		"whisper": [0.85, 1.0],
		"vibrato_rate": [0.0, 1.5],
		"vibrato_depth": [0.0, 0.08],
	},
}

# UI containers
var _main_container: VBoxContainer
var _step_scroll: ScrollContainer
var _step_container: VBoxContainer
var _navigation_container: HBoxContainer
var _step_label: Label
var _prev_btn: Button
var _next_btn: Button
var _preview_btn: Button

# Step 1: Basic info
var _name_edit: LineEdit
var _preset_option: OptionButton
var _description_label: Label

# Step 2: Pitch and timing
var _pitch_slider: HSlider
var _pitch_spin: SpinBox
var _pitch_preview: Label
var _duration_slider: HSlider
var _duration_spin: SpinBox
var _jitter_slider: HSlider
var _jitter_spin: SpinBox

# Step 3: Character
var _breathiness_slider: HSlider
var _breathiness_spin: SpinBox
var _whisper_slider: HSlider
var _whisper_spin: SpinBox
var _vibrato_rate_slider: HSlider
var _vibrato_rate_spin: SpinBox
var _vibrato_depth_slider: HSlider
var _vibrato_depth_spin: SpinBox

# Step 4: Summary
var _summary_label: RichTextLabel
var _save_path_edit: LineEdit
var _browse_btn: Button

# Preview text
var _preview_text: LineEdit


func _init() -> void:
	title = tr("Voice Creation Wizard")
	min_size = Vector2i(420, 320)
	max_size = Vector2i(420, 320)
	size = Vector2i(420, 320)
	exclusive = true
	unresizable = true


func _ready() -> void:
	_rng.randomize()
	_voice = AnimaleseVoice.new()
	_voice.voice_name = tr("New Voice")

	_build_ui()
	_show_step(0)

	# Connect dialog buttons
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)

	get_ok_button().text = tr("Create Voice")
	get_ok_button().disabled = true


func _build_ui() -> void:
	_main_container = VBoxContainer.new()
	_main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_main_container)

	# Step indicator
	var step_header := HBoxContainer.new()
	_main_container.add_child(step_header)

	_step_label = Label.new()
	_step_label.text = tr("Step 1 of 4: Basic Information")
	_step_label.add_theme_font_size_override("font_size", 14)
	step_header.add_child(_step_label)

	_main_container.add_child(HSeparator.new())

	# Step content container with scroll
	_step_scroll = ScrollContainer.new()
	_step_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_step_scroll.custom_minimum_size = Vector2(0, 150)
	_main_container.add_child(_step_scroll)

	_step_container = VBoxContainer.new()
	_step_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step_container.add_theme_constant_override("separation", 4)
	_step_scroll.add_child(_step_container)

	# Preview section
	_main_container.add_child(HSeparator.new())

	var preview_row := HBoxContainer.new()
	_main_container.add_child(preview_row)

	var preview_label := Label.new()
	preview_label.text = tr("Preview text:")
	preview_label.custom_minimum_size = Vector2(90, 0)
	preview_row.add_child(preview_label)

	_preview_text = LineEdit.new()
	_preview_text.text = tr("Hello! This is a test of my new voice.")
	_preview_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_row.add_child(_preview_text)

	_preview_btn = Button.new()
	_preview_btn.text = tr("Preview")
	_preview_btn.pressed.connect(_on_preview_pressed)
	preview_row.add_child(_preview_btn)

	# Navigation buttons
	_main_container.add_child(HSeparator.new())

	_navigation_container = HBoxContainer.new()
	_navigation_container.alignment = BoxContainer.ALIGNMENT_END
	_main_container.add_child(_navigation_container)

	_prev_btn = Button.new()
	_prev_btn.text = tr("< Previous")
	_prev_btn.pressed.connect(_on_prev_pressed)
	_navigation_container.add_child(_prev_btn)

	_next_btn = Button.new()
	_next_btn.text = tr("Next >")
	_next_btn.pressed.connect(_on_next_pressed)
	_navigation_container.add_child(_next_btn)


func _show_step(step: int) -> void:
	_current_step = clampi(step, 0, STEP_COUNT - 1)

	# Clear step container
	for child in _step_container.get_children():
		child.queue_free()

	# Update step label
	var step_names := [tr("Basic Information"), tr("Pitch & Timing"), tr("Voice Character"), tr("Summary & Save")]
	_step_label.text = tr("Step %d of %d: %s") % [_current_step + 1, STEP_COUNT, step_names[_current_step]]

	# Update navigation buttons
	_prev_btn.disabled = _current_step == 0
	_next_btn.visible = _current_step < STEP_COUNT - 1
	get_ok_button().disabled = _current_step < STEP_COUNT - 1

	# Build step UI
	match _current_step:
		0:
			_build_step_1()
		1:
			_build_step_2()
		2:
			_build_step_3()
		3:
			_build_step_4()


func _build_step_1() -> void:
	## Step 1: Basic Information

	_description_label = Label.new()
	_description_label.text = tr("Choose a name and starting preset for your voice.")
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_container.add_child(_description_label)

	# Voice name
	var name_row := HBoxContainer.new()
	_step_container.add_child(name_row)

	var name_label := Label.new()
	name_label.text = tr("Voice Name:")
	name_label.custom_minimum_size = Vector2(120, 0)
	name_row.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.text = _voice.voice_name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = tr("Enter a name for this voice...")
	_name_edit.text_changed.connect(_on_name_changed)
	name_row.add_child(_name_edit)

	# Preset selection
	var preset_row := HBoxContainer.new()
	_step_container.add_child(preset_row)

	var preset_label := Label.new()
	preset_label.text = tr("Start from:")
	preset_label.custom_minimum_size = Vector2(120, 0)
	preset_row.add_child(preset_label)

	_preset_option = OptionButton.new()
	_preset_option.add_item(tr("Custom (blank)"), VoicePreset.CUSTOM)
	_preset_option.add_item(tr("Masculine"), VoicePreset.MASCULINE)
	_preset_option.add_item(tr("Feminine"), VoicePreset.FEMININE)
	_preset_option.add_item(tr("Child"), VoicePreset.CHILD)
	_preset_option.add_item(tr("Elder"), VoicePreset.ELDER)
	_preset_option.add_item(tr("Robot"), VoicePreset.ROBOT)
	_preset_option.add_item(tr("Monster"), VoicePreset.MONSTER)
	_preset_option.add_item(tr("Ghost"), VoicePreset.GHOST)
	_preset_option.add_item(tr("Whisper"), VoicePreset.WHISPER)
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_option.item_selected.connect(_on_preset_selected)
	preset_row.add_child(_preset_option)

	# Preset description
	var preset_desc := Label.new()
	preset_desc.name = "PresetDescription"
	preset_desc.text = _get_preset_description(VoicePreset.CUSTOM)
	preset_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preset_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_step_container.add_child(preset_desc)


func _build_step_2() -> void:
	## Step 2: Pitch and Timing

	var header_row := HBoxContainer.new()
	_step_container.add_child(header_row)

	var desc := Label.new()
	desc.text = tr("Adjust the base pitch and speaking speed.")
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(desc)

	var randomize_btn := Button.new()
	randomize_btn.text = tr("Randomize")
	randomize_btn.pressed.connect(_on_randomize_step_2)
	header_row.add_child(randomize_btn)

	# Pitch
	var pitch_label := Label.new()
	pitch_label.text = tr("Base Pitch (Hz):")
	_step_container.add_child(pitch_label)

	var pitch_row := HBoxContainer.new()
	_step_container.add_child(pitch_row)

	_pitch_slider = HSlider.new()
	_pitch_slider.min_value = 80.0
	_pitch_slider.max_value = 600.0
	_pitch_slider.step = 1.0
	_pitch_slider.value = _voice.pitch_base_hz
	_pitch_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pitch_slider.value_changed.connect(_on_pitch_changed)
	pitch_row.add_child(_pitch_slider)

	_pitch_spin = SpinBox.new()
	_pitch_spin.min_value = 80.0
	_pitch_spin.max_value = 600.0
	_pitch_spin.step = 1.0
	_pitch_spin.value = _voice.pitch_base_hz
	_pitch_spin.custom_minimum_size = Vector2(80, 0)
	_pitch_spin.value_changed.connect(_on_pitch_spin_changed)
	pitch_row.add_child(_pitch_spin)

	_pitch_preview = Label.new()
	_pitch_preview.text = _get_pitch_description(_voice.pitch_base_hz)
	_pitch_preview.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_step_container.add_child(_pitch_preview)

	# Duration
	var dur_label := Label.new()
	dur_label.text = tr("Character Duration (seconds):")
	_step_container.add_child(dur_label)

	var dur_row := HBoxContainer.new()
	_step_container.add_child(dur_row)

	_duration_slider = HSlider.new()
	_duration_slider.min_value = 0.02
	_duration_slider.max_value = 0.12
	_duration_slider.step = 0.001
	_duration_slider.value = _voice.char_duration_s
	_duration_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duration_slider.value_changed.connect(_on_duration_changed)
	dur_row.add_child(_duration_slider)

	_duration_spin = SpinBox.new()
	_duration_spin.min_value = 0.02
	_duration_spin.max_value = 0.12
	_duration_spin.step = 0.001
	_duration_spin.value = _voice.char_duration_s
	_duration_spin.custom_minimum_size = Vector2(80, 0)
	_duration_spin.value_changed.connect(_on_duration_spin_changed)
	dur_row.add_child(_duration_spin)

	# Jitter
	var jitter_label := Label.new()
	jitter_label.text = tr("Pitch Variation (jitter):")
	_step_container.add_child(jitter_label)

	var jitter_row := HBoxContainer.new()
	_step_container.add_child(jitter_row)

	_jitter_slider = HSlider.new()
	_jitter_slider.min_value = 0.0
	_jitter_slider.max_value = 0.25
	_jitter_slider.step = 0.005
	_jitter_slider.value = _voice.pitch_jitter
	_jitter_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jitter_slider.value_changed.connect(_on_jitter_changed)
	jitter_row.add_child(_jitter_slider)

	_jitter_spin = SpinBox.new()
	_jitter_spin.min_value = 0.0
	_jitter_spin.max_value = 0.25
	_jitter_spin.step = 0.005
	_jitter_spin.value = _voice.pitch_jitter
	_jitter_spin.custom_minimum_size = Vector2(80, 0)
	_jitter_spin.value_changed.connect(_on_jitter_spin_changed)
	jitter_row.add_child(_jitter_spin)


func _build_step_3() -> void:
	## Step 3: Voice Character

	var header_row := HBoxContainer.new()
	_step_container.add_child(header_row)

	var desc := Label.new()
	desc.text = tr("Fine-tune breathiness, whisper, and vibrato.")
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(desc)

	var randomize_btn := Button.new()
	randomize_btn.text = tr("Randomize")
	randomize_btn.pressed.connect(_on_randomize_step_3)
	header_row.add_child(randomize_btn)

	# Breathiness
	var breath_label := Label.new()
	breath_label.text = tr("Breathiness:")
	_step_container.add_child(breath_label)

	var breath_row := HBoxContainer.new()
	_step_container.add_child(breath_row)

	_breathiness_slider = HSlider.new()
	_breathiness_slider.min_value = 0.0
	_breathiness_slider.max_value = 1.5
	_breathiness_slider.step = 0.01
	_breathiness_slider.value = _voice.breath_noise_level
	_breathiness_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breathiness_slider.value_changed.connect(_on_breathiness_changed)
	breath_row.add_child(_breathiness_slider)

	_breathiness_spin = SpinBox.new()
	_breathiness_spin.min_value = 0.0
	_breathiness_spin.max_value = 1.5
	_breathiness_spin.step = 0.01
	_breathiness_spin.value = _voice.breath_noise_level
	_breathiness_spin.custom_minimum_size = Vector2(80, 0)
	_breathiness_spin.value_changed.connect(_on_breathiness_spin_changed)
	breath_row.add_child(_breathiness_spin)

	# Whisper
	var whisper_label := Label.new()
	whisper_label.text = tr("Whisper Amount:")
	_step_container.add_child(whisper_label)

	var whisper_row := HBoxContainer.new()
	_step_container.add_child(whisper_row)

	_whisper_slider = HSlider.new()
	_whisper_slider.min_value = 0.0
	_whisper_slider.max_value = 1.0
	_whisper_slider.step = 0.01
	_whisper_slider.value = _voice.whisper_amount
	_whisper_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_whisper_slider.value_changed.connect(_on_whisper_changed)
	whisper_row.add_child(_whisper_slider)

	_whisper_spin = SpinBox.new()
	_whisper_spin.min_value = 0.0
	_whisper_spin.max_value = 1.0
	_whisper_spin.step = 0.01
	_whisper_spin.value = _voice.whisper_amount
	_whisper_spin.custom_minimum_size = Vector2(80, 0)
	_whisper_spin.value_changed.connect(_on_whisper_spin_changed)
	whisper_row.add_child(_whisper_spin)

	# Vibrato Rate
	var vib_rate_label := Label.new()
	vib_rate_label.text = tr("Vibrato Rate (Hz):")
	_step_container.add_child(vib_rate_label)

	var vib_rate_row := HBoxContainer.new()
	_step_container.add_child(vib_rate_row)

	_vibrato_rate_slider = HSlider.new()
	_vibrato_rate_slider.min_value = 0.0
	_vibrato_rate_slider.max_value = 12.0
	_vibrato_rate_slider.step = 0.1
	_vibrato_rate_slider.value = _voice.vibrato_rate_hz
	_vibrato_rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vibrato_rate_slider.value_changed.connect(_on_vibrato_rate_changed)
	vib_rate_row.add_child(_vibrato_rate_slider)

	_vibrato_rate_spin = SpinBox.new()
	_vibrato_rate_spin.min_value = 0.0
	_vibrato_rate_spin.max_value = 12.0
	_vibrato_rate_spin.step = 0.1
	_vibrato_rate_spin.value = _voice.vibrato_rate_hz
	_vibrato_rate_spin.custom_minimum_size = Vector2(80, 0)
	_vibrato_rate_spin.value_changed.connect(_on_vibrato_rate_spin_changed)
	vib_rate_row.add_child(_vibrato_rate_spin)

	# Vibrato Depth
	var vib_depth_label := Label.new()
	vib_depth_label.text = tr("Vibrato Depth:")
	_step_container.add_child(vib_depth_label)

	var vib_depth_row := HBoxContainer.new()
	_step_container.add_child(vib_depth_row)

	_vibrato_depth_slider = HSlider.new()
	_vibrato_depth_slider.min_value = 0.0
	_vibrato_depth_slider.max_value = 1.0
	_vibrato_depth_slider.step = 0.01
	_vibrato_depth_slider.value = _voice.vibrato_depth
	_vibrato_depth_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vibrato_depth_slider.value_changed.connect(_on_vibrato_depth_changed)
	vib_depth_row.add_child(_vibrato_depth_slider)

	_vibrato_depth_spin = SpinBox.new()
	_vibrato_depth_spin.min_value = 0.0
	_vibrato_depth_spin.max_value = 1.0
	_vibrato_depth_spin.step = 0.01
	_vibrato_depth_spin.value = _voice.vibrato_depth
	_vibrato_depth_spin.custom_minimum_size = Vector2(80, 0)
	_vibrato_depth_spin.value_changed.connect(_on_vibrato_depth_spin_changed)
	vib_depth_row.add_child(_vibrato_depth_spin)


func _build_step_4() -> void:
	## Step 4: Summary and Save

	var desc := Label.new()
	desc.text = tr("Review your voice settings and save the resource.")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_container.add_child(desc)

	# Summary
	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_label.fit_content = true
	_step_container.add_child(_summary_label)

	_update_summary()

	# Save path
	var path_label := Label.new()
	path_label.text = tr("Save Location:")
	_step_container.add_child(path_label)

	var path_row := HBoxContainer.new()
	_step_container.add_child(path_row)

	_save_path_edit = LineEdit.new()
	_save_path_edit.text = "res://voices/%s.tres" % _voice.voice_name.to_snake_case()
	_save_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_path_edit.placeholder_text = tr("res://path/to/voice.tres")
	path_row.add_child(_save_path_edit)

	_browse_btn = Button.new()
	_browse_btn.text = tr("Browse...")
	_browse_btn.pressed.connect(_on_browse_pressed)
	path_row.add_child(_browse_btn)


func _update_summary() -> void:
	if _summary_label == null:
		return

	var summary := "[b]%s[/b]\n\n" % tr("Voice Summary")
	summary += "[color=gray]%s:[/color] %s\n" % [tr("Name"), _voice.voice_name]
	summary += "[color=gray]%s:[/color] %.0f Hz (%s)\n" % [tr("Base Pitch"), _voice.pitch_base_hz, _get_pitch_description(_voice.pitch_base_hz)]
	summary += "[color=gray]%s:[/color] %.3f s\n" % [tr("Duration"), _voice.char_duration_s]
	summary += "[color=gray]%s:[/color] %.3f\n" % [tr("Pitch Jitter"), _voice.pitch_jitter]
	summary += "[color=gray]%s:[/color] %.2f\n" % [tr("Breathiness"), _voice.breath_noise_level]
	summary += "[color=gray]%s:[/color] %.2f\n" % [tr("Whisper"), _voice.whisper_amount]

	if _voice.vibrato_rate_hz > 0:
		summary += "[color=gray]%s:[/color] %.1f Hz @ %.2f %s\n" % [tr("Vibrato"), _voice.vibrato_rate_hz, _voice.vibrato_depth, tr("depth")]
	else:
		summary += "[color=gray]%s:[/color] %s\n" % [tr("Vibrato"), tr("Off")]

	_summary_label.text = summary


func _get_preset_description(preset: VoicePreset) -> String:
	match preset:
		VoicePreset.CUSTOM:
			return tr("Start with default values and customize everything yourself.")
		VoicePreset.MASCULINE:
			return tr("A deep, resonant voice with lower pitch (120-180 Hz). Good for adult male characters.")
		VoicePreset.FEMININE:
			return tr("A higher-pitched voice (220-320 Hz) with slightly more breathiness. Good for adult female characters.")
		VoicePreset.CHILD:
			return tr("A high-pitched voice (300-400 Hz) with faster speech and more pitch variation. Good for young characters.")
		VoicePreset.ELDER:
			return tr("A slower, slightly shaky voice with moderate vibrato. Good for elderly characters.")
		VoicePreset.ROBOT:
			return tr("A flat, mechanical voice with no vibrato or jitter. Perfect for AI or robotic characters.")
		VoicePreset.MONSTER:
			return tr("A very low, growling voice (80-120 Hz) with high breathiness. Good for creatures and monsters.")
		VoicePreset.GHOST:
			return tr("An ethereal, whispery voice with high breathiness and slow vibrato. Good for supernatural characters.")
		VoicePreset.WHISPER:
			return tr("A soft, hushed voice using mostly breath sounds. Good for secretive or intimate dialogue.")
		_:
			return ""


func _get_pitch_description(pitch: float) -> String:
	if pitch < 100:
		return tr("Very deep (bass)")
	elif pitch < 150:
		return tr("Deep (baritone)")
	elif pitch < 200:
		return tr("Low (tenor)")
	elif pitch < 260:
		return tr("Medium (alto)")
	elif pitch < 350:
		return tr("High (soprano)")
	elif pitch < 450:
		return tr("Very high (child)")
	else:
		return tr("Extremely high")


func _apply_preset(preset: VoicePreset) -> void:
	match preset:
		VoicePreset.CUSTOM:
			# Keep defaults
			_voice.pitch_base_hz = 220.0
			_voice.char_duration_s = 0.055
			_voice.pitch_jitter = 0.06
			_voice.breath_noise_level = 0.15
			_voice.whisper_amount = 0.0
			_voice.vibrato_rate_hz = 0.0
			_voice.vibrato_depth = 0.0

		VoicePreset.MASCULINE:
			_voice.pitch_base_hz = 140.0
			_voice.char_duration_s = 0.058
			_voice.pitch_jitter = 0.05
			_voice.breath_noise_level = 0.12
			_voice.whisper_amount = 0.0
			_voice.vibrato_rate_hz = 0.0
			_voice.vibrato_depth = 0.0

		VoicePreset.FEMININE:
			_voice.pitch_base_hz = 260.0
			_voice.char_duration_s = 0.052
			_voice.pitch_jitter = 0.07
			_voice.breath_noise_level = 0.18
			_voice.whisper_amount = 0.0
			_voice.vibrato_rate_hz = 4.5
			_voice.vibrato_depth = 0.08

		VoicePreset.CHILD:
			_voice.pitch_base_hz = 340.0
			_voice.char_duration_s = 0.045
			_voice.pitch_jitter = 0.10
			_voice.breath_noise_level = 0.20
			_voice.whisper_amount = 0.0
			_voice.vibrato_rate_hz = 0.0
			_voice.vibrato_depth = 0.0

		VoicePreset.ELDER:
			_voice.pitch_base_hz = 160.0
			_voice.char_duration_s = 0.070
			_voice.pitch_jitter = 0.08
			_voice.breath_noise_level = 0.25
			_voice.whisper_amount = 0.1
			_voice.vibrato_rate_hz = 5.5
			_voice.vibrato_depth = 0.15

		VoicePreset.ROBOT:
			_voice.pitch_base_hz = 180.0
			_voice.char_duration_s = 0.060
			_voice.pitch_jitter = 0.0
			_voice.breath_noise_level = 0.0
			_voice.whisper_amount = 0.0
			_voice.vibrato_rate_hz = 0.0
			_voice.vibrato_depth = 0.0
			_voice.prosody_strength = 0.0
			_voice.coarticulation_strength = 0.0

		VoicePreset.MONSTER:
			_voice.pitch_base_hz = 95.0
			_voice.char_duration_s = 0.075
			_voice.pitch_jitter = 0.12
			_voice.breath_noise_level = 0.50
			_voice.whisper_amount = 0.2
			_voice.vibrato_rate_hz = 3.0
			_voice.vibrato_depth = 0.20

		VoicePreset.GHOST:
			_voice.pitch_base_hz = 200.0
			_voice.char_duration_s = 0.065
			_voice.pitch_jitter = 0.04
			_voice.breath_noise_level = 0.40
			_voice.whisper_amount = 0.5
			_voice.vibrato_rate_hz = 2.5
			_voice.vibrato_depth = 0.12

		VoicePreset.WHISPER:
			_voice.pitch_base_hz = 220.0
			_voice.char_duration_s = 0.060
			_voice.pitch_jitter = 0.03
			_voice.breath_noise_level = 0.30
			_voice.whisper_amount = 1.0
			_voice.vibrato_rate_hz = 0.0
			_voice.vibrato_depth = 0.0


# --- Event handlers ---

func _on_name_changed(new_name: String) -> void:
	_voice.voice_name = new_name if not new_name.is_empty() else tr("New Voice")


func _on_preset_selected(index: int) -> void:
	var preset: VoicePreset = _preset_option.get_item_id(index) as VoicePreset
	_current_preset = preset
	_apply_preset(preset)

	# Update preset description
	var desc_node := _step_container.find_child("PresetDescription", true, false)
	if desc_node and desc_node is Label:
		desc_node.text = _get_preset_description(preset)


func _on_pitch_changed(value: float) -> void:
	_voice.pitch_base_hz = value
	if _pitch_spin:
		_pitch_spin.set_value_no_signal(value)
	if _pitch_preview:
		_pitch_preview.text = _get_pitch_description(value)


func _on_pitch_spin_changed(value: float) -> void:
	_voice.pitch_base_hz = value
	if _pitch_slider:
		_pitch_slider.set_value_no_signal(value)
	if _pitch_preview:
		_pitch_preview.text = _get_pitch_description(value)


func _on_duration_changed(value: float) -> void:
	_voice.char_duration_s = value
	if _duration_spin:
		_duration_spin.set_value_no_signal(value)


func _on_duration_spin_changed(value: float) -> void:
	_voice.char_duration_s = value
	if _duration_slider:
		_duration_slider.set_value_no_signal(value)


func _on_jitter_changed(value: float) -> void:
	_voice.pitch_jitter = value
	if _jitter_spin:
		_jitter_spin.set_value_no_signal(value)


func _on_jitter_spin_changed(value: float) -> void:
	_voice.pitch_jitter = value
	if _jitter_slider:
		_jitter_slider.set_value_no_signal(value)


func _on_breathiness_changed(value: float) -> void:
	_voice.breath_noise_level = value
	if _breathiness_spin:
		_breathiness_spin.set_value_no_signal(value)


func _on_breathiness_spin_changed(value: float) -> void:
	_voice.breath_noise_level = value
	if _breathiness_slider:
		_breathiness_slider.set_value_no_signal(value)


func _on_whisper_changed(value: float) -> void:
	_voice.whisper_amount = value
	if _whisper_spin:
		_whisper_spin.set_value_no_signal(value)


func _on_whisper_spin_changed(value: float) -> void:
	_voice.whisper_amount = value
	if _whisper_slider:
		_whisper_slider.set_value_no_signal(value)


func _on_vibrato_rate_changed(value: float) -> void:
	_voice.vibrato_rate_hz = value
	if _vibrato_rate_spin:
		_vibrato_rate_spin.set_value_no_signal(value)


func _on_vibrato_rate_spin_changed(value: float) -> void:
	_voice.vibrato_rate_hz = value
	if _vibrato_rate_slider:
		_vibrato_rate_slider.set_value_no_signal(value)


func _on_vibrato_depth_changed(value: float) -> void:
	_voice.vibrato_depth = value
	if _vibrato_depth_spin:
		_vibrato_depth_spin.set_value_no_signal(value)


func _on_vibrato_depth_spin_changed(value: float) -> void:
	_voice.vibrato_depth = value
	if _vibrato_depth_slider:
		_vibrato_depth_slider.set_value_no_signal(value)


func _on_prev_pressed() -> void:
	_show_step(_current_step - 1)


func _on_next_pressed() -> void:
	_show_step(_current_step + 1)
	if _current_step == STEP_COUNT - 1:
		_update_summary()


func _on_preview_pressed() -> void:
	preview_requested.emit(_voice, _preview_text.text)


func _on_browse_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.tres ; Godot Resource"])
	dialog.current_path = _save_path_edit.text if not _save_path_edit.text.is_empty() else "res://voices/"
	dialog.file_selected.connect(_on_file_selected)
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String) -> void:
	_save_path_edit.text = path


func _on_randomize_step_2() -> void:
	var limits: Dictionary = PRESET_LIMITS.get(_current_preset, PRESET_LIMITS[VoicePreset.CUSTOM])

	# Randomize pitch
	var pitch_range: Array = limits.get("pitch", [100.0, 400.0])
	var new_pitch: float = _rng.randf_range(pitch_range[0], pitch_range[1])
	_voice.pitch_base_hz = new_pitch
	if _pitch_slider:
		_pitch_slider.value = new_pitch
	if _pitch_spin:
		_pitch_spin.value = new_pitch
	if _pitch_preview:
		_pitch_preview.text = _get_pitch_description(new_pitch)

	# Randomize duration
	var dur_range: Array = limits.get("duration", [0.035, 0.085])
	var new_dur: float = _rng.randf_range(dur_range[0], dur_range[1])
	_voice.char_duration_s = new_dur
	if _duration_slider:
		_duration_slider.value = new_dur
	if _duration_spin:
		_duration_spin.value = new_dur

	# Randomize jitter
	var jitter_range: Array = limits.get("jitter", [0.02, 0.15])
	var new_jitter: float = _rng.randf_range(jitter_range[0], jitter_range[1])
	_voice.pitch_jitter = new_jitter
	if _jitter_slider:
		_jitter_slider.value = new_jitter
	if _jitter_spin:
		_jitter_spin.value = new_jitter


func _on_randomize_step_3() -> void:
	var limits: Dictionary = PRESET_LIMITS.get(_current_preset, PRESET_LIMITS[VoicePreset.CUSTOM])

	# Randomize breathiness
	var breath_range: Array = limits.get("breathiness", [0.05, 0.40])
	var new_breath: float = _rng.randf_range(breath_range[0], breath_range[1])
	_voice.breath_noise_level = new_breath
	if _breathiness_slider:
		_breathiness_slider.value = new_breath
	if _breathiness_spin:
		_breathiness_spin.value = new_breath

	# Randomize whisper
	var whisper_range: Array = limits.get("whisper", [0.0, 0.3])
	var new_whisper: float = _rng.randf_range(whisper_range[0], whisper_range[1])
	_voice.whisper_amount = new_whisper
	if _whisper_slider:
		_whisper_slider.value = new_whisper
	if _whisper_spin:
		_whisper_spin.value = new_whisper

	# Randomize vibrato rate
	var vib_rate_range: Array = limits.get("vibrato_rate", [0.0, 6.0])
	var new_vib_rate: float = _rng.randf_range(vib_rate_range[0], vib_rate_range[1])
	_voice.vibrato_rate_hz = new_vib_rate
	if _vibrato_rate_slider:
		_vibrato_rate_slider.value = new_vib_rate
	if _vibrato_rate_spin:
		_vibrato_rate_spin.value = new_vib_rate

	# Randomize vibrato depth
	var vib_depth_range: Array = limits.get("vibrato_depth", [0.0, 0.20])
	var new_vib_depth: float = _rng.randf_range(vib_depth_range[0], vib_depth_range[1])
	_voice.vibrato_depth = new_vib_depth
	if _vibrato_depth_slider:
		_vibrato_depth_slider.value = new_vib_depth
	if _vibrato_depth_spin:
		_vibrato_depth_spin.value = new_vib_depth


func _on_confirmed() -> void:
	# Save the voice resource
	var path: String = _save_path_edit.text.strip_edges()
	if path.is_empty():
		path = "res://voices/%s.tres" % _voice.voice_name.to_snake_case()

	# Ensure directory exists
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	# Save resource
	var error := ResourceSaver.save(_voice, path)
	if error == OK:
		print("Voice saved to: ", path)
		voice_created.emit(_voice)
	else:
		push_error("Failed to save voice: %s" % error_string(error))


func _on_canceled() -> void:
	pass


## Reset the wizard to initial state for reuse.
func reset() -> void:
	_voice = AnimaleseVoice.new()
	_voice.voice_name = "New Voice"
	_show_step(0)


## Get the current voice being edited.
func get_voice() -> AnimaleseVoice:
	return _voice
