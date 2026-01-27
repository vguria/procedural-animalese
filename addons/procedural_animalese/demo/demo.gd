@tool
extends Control
## Procedural Animalese Demo Scene
## Demonstrates all major features of the plugin.

@onready var animalese: ProceduralAnimalese = $ProceduralAnimalese

# UI References
var _voice_select: OptionButton
var _emotion_select: OptionButton
var _language_select: OptionButton
var _text_input: TextEdit
var _pitch_slider: HSlider
var _pitch_label: Label
var _speak_btn: Button
var _stop_btn: Button
var _progress_bar: ProgressBar
var _viseme_label: Label
var _viseme_display: Control
var _phoneme_label: Label
var _word_label: Label

# Voice blending
var _voice_a_select: OptionButton
var _voice_b_select: OptionButton
var _blend_slider: HSlider
var _blend_label: Label
var _blend_preview_btn: Button

# Markup demo
var _markup_examples: OptionButton
var _markup_text: TextEdit
var _markup_speak_btn: Button

# Preloaded voices
var _voices: Dictionary = {}
var _voice_paths: Array[String] = [
	"res://addons/procedural_animalese/presets/voice_default.tres",
	"res://addons/procedural_animalese/presets/voice_masculine.tres",
	"res://addons/procedural_animalese/presets/voice_feminine.tres",
	"res://addons/procedural_animalese/presets/voice_child.tres",
	"res://addons/procedural_animalese/presets/voice_elder.tres",
	"res://addons/procedural_animalese/presets/voice_robot.tres",
	"res://addons/procedural_animalese/presets/voice_monster.tres",
	"res://addons/procedural_animalese/presets/voice_ghost.tres",
]

var _emotions: Array[String] = [
	"neutral", "happy", "sad", "angry", "scared",
	"nervous", "excited", "tired", "whisper", "mysterious"
]

var _languages: Dictionary = {
	"Spanish": "es",
	"English": "en",
	"Japanese": "ja",
	"French": "fr",
	"German": "de",
	"Portuguese": "pt",
	"Italian": "it",
	"Russian": "ru",
	"Chinese": "zh",
	"Auto-detect": "auto"
}

var _sample_texts: Dictionary = {
	"es": "¡Hola! ¿Cómo estás? Me llamo Animalese.",
	"en": "Hello! How are you? My name is Animalese.",
	"ja": "Konnichiwa! Ogenki desu ka?",
	"fr": "Bonjour! Comment allez-vous?",
	"de": "Guten Tag! Wie geht es Ihnen?",
	"pt": "Olá! Como você está?",
	"it": "Ciao! Come stai?",
	"ru": "Привет! Как дела?",
	"zh": "Ni hao! Ni hao ma?",
	"auto": "Hello! This is a test of procedural speech synthesis."
}

var _markup_samples: Array[Dictionary] = [
	{"name": "Pauses", "text": "Hello...[pause:0.5]...world![pause:0.3] How are you?"},
	{"name": "Pitch changes", "text": "[pitch:1.3]Higher pitch![/pitch] Normal. [pitch:0.7]Lower pitch.[/pitch]"},
	{"name": "Speed changes", "text": "[speed:0.6]Speaking slowly...[/speed] Normal speed. [speed:1.5]Fast![/speed]"},
	{"name": "Emotions", "text": "[emotion:happy]I'm so happy![/emotion] [emotion:sad]Now I'm sad...[/emotion]"},
	{"name": "Combined", "text": "[pitch:1.2][emotion:excited]This is amazing![/emotion][/pitch][pause:0.3][speed:0.7][emotion:tired]I'm getting tired...[/emotion][/speed]"},
]

func _ready() -> void:
	_build_ui()
	_load_voices()
	_connect_signals()
	_update_sample_text()

func _load_voices() -> void:
	for path in _voice_paths:
		if ResourceLoader.exists(path):
			var voice = ResourceLoader.load(path) as AnimaleseVoice
			if voice != null:
				_voices[voice.voice_name] = voice

func _build_ui() -> void:
	# Main container
	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.add_theme_constant_override("separation", 10)
	add_child(main_vbox)

	# Title
	var title := Label.new()
	title.text = "Procedural Animalese Demo"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_vbox.add_child(title)

	# HSplit for two columns
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hsplit)

	# Left column - Basic controls
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left_vbox)

	# === BASIC SPEECH ===
	_add_section_header(left_vbox, "Basic Speech")

	# Voice selection
	var voice_row := _create_row(left_vbox, "Voice:")
	_voice_select = OptionButton.new()
	_voice_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	voice_row.add_child(_voice_select)

	# Emotion selection
	var emotion_row := _create_row(left_vbox, "Emotion:")
	_emotion_select = OptionButton.new()
	_emotion_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for emo in _emotions:
		_emotion_select.add_item(emo.capitalize())
	emotion_row.add_child(_emotion_select)

	# Language selection
	var lang_row := _create_row(left_vbox, "Language:")
	_language_select = OptionButton.new()
	_language_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lang_name in _languages.keys():
		_language_select.add_item(lang_name)
	lang_row.add_child(_language_select)

	# Pitch slider
	var pitch_row := _create_row(left_vbox, "Pitch:")
	_pitch_slider = HSlider.new()
	_pitch_slider.min_value = 0.5
	_pitch_slider.max_value = 2.0
	_pitch_slider.step = 0.05
	_pitch_slider.value = 1.0
	_pitch_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pitch_row.add_child(_pitch_slider)
	_pitch_label = Label.new()
	_pitch_label.text = "1.00x"
	_pitch_label.custom_minimum_size.x = 50
	pitch_row.add_child(_pitch_label)

	# Text input
	var text_label := Label.new()
	text_label.text = "Text to speak:"
	left_vbox.add_child(text_label)

	_text_input = TextEdit.new()
	_text_input.custom_minimum_size.y = 80
	_text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_input.placeholder_text = "Enter text to speak..."
	left_vbox.add_child(_text_input)

	# Speak/Stop buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	left_vbox.add_child(btn_row)

	_speak_btn = Button.new()
	_speak_btn.text = "Speak"
	_speak_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_speak_btn)

	_stop_btn = Button.new()
	_stop_btn.text = "Stop"
	_stop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(_stop_btn)

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	left_vbox.add_child(_progress_bar)

	# === VOICE BLENDING ===
	_add_section_header(left_vbox, "Voice Blending")

	var blend_a_row := _create_row(left_vbox, "Voice A:")
	_voice_a_select = OptionButton.new()
	_voice_a_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blend_a_row.add_child(_voice_a_select)

	var blend_b_row := _create_row(left_vbox, "Voice B:")
	_voice_b_select = OptionButton.new()
	_voice_b_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blend_b_row.add_child(_voice_b_select)

	var blend_row := _create_row(left_vbox, "Blend:")
	_blend_slider = HSlider.new()
	_blend_slider.min_value = 0.0
	_blend_slider.max_value = 1.0
	_blend_slider.step = 0.05
	_blend_slider.value = 0.5
	_blend_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blend_row.add_child(_blend_slider)
	_blend_label = Label.new()
	_blend_label.text = "50%"
	_blend_label.custom_minimum_size.x = 50
	blend_row.add_child(_blend_label)

	_blend_preview_btn = Button.new()
	_blend_preview_btn.text = "Preview Blended Voice"
	left_vbox.add_child(_blend_preview_btn)

	# Right column - Markup and Feedback
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right_scroll)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_vbox)

	# === MARKUP DEMO ===
	_add_section_header(right_vbox, "Markup Tags")

	var markup_ex_row := _create_row(right_vbox, "Example:")
	_markup_examples = OptionButton.new()
	_markup_examples.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for sample in _markup_samples:
		_markup_examples.add_item(sample["name"])
	markup_ex_row.add_child(_markup_examples)

	_markup_text = TextEdit.new()
	_markup_text.custom_minimum_size.y = 60
	_markup_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_markup_text)

	_markup_speak_btn = Button.new()
	_markup_speak_btn.text = "Speak with Markup"
	right_vbox.add_child(_markup_speak_btn)

	# === FEEDBACK ===
	_add_section_header(right_vbox, "Real-time Feedback")

	# Viseme display
	var viseme_row := _create_row(right_vbox, "Viseme:")
	_viseme_display = Control.new()
	_viseme_display.custom_minimum_size = Vector2(60, 60)
	viseme_row.add_child(_viseme_display)
	_viseme_label = Label.new()
	_viseme_label.text = "SILENT (0)"
	viseme_row.add_child(_viseme_label)

	# Phoneme
	var phoneme_row := _create_row(right_vbox, "Phoneme:")
	_phoneme_label = Label.new()
	_phoneme_label.text = "-"
	phoneme_row.add_child(_phoneme_label)

	# Word
	var word_row := _create_row(right_vbox, "Word:")
	_word_label = Label.new()
	_word_label.text = "-"
	word_row.add_child(_word_label)

	# === INFO ===
	_add_section_header(right_vbox, "Instructions")

	var info := RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = """[b]Basic Speech:[/b] Select voice, emotion, language, and click Speak.

[b]Voice Blending:[/b] Mix two voices together with the slider.

[b]Markup Tags:[/b] Use special tags for dynamic speech:
• [code][pause:0.5][/code] - Insert pause
• [code][pitch:1.2]text[/pitch][/code] - Change pitch
• [code][speed:0.8]text[/speed][/code] - Change speed
• [code][emotion:happy]text[/emotion][/code] - Apply emotion

[b]Viseme:[/b] Shows mouth shape for lip-sync animation."""
	right_vbox.add_child(info)

func _add_section_header(parent: Control, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)

func _create_row(parent: Control, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 80
	row.add_child(label)
	return row

func _connect_signals() -> void:
	# Populate voice selects
	for voice_name in _voices.keys():
		_voice_select.add_item(voice_name)
		_voice_a_select.add_item(voice_name)
		_voice_b_select.add_item(voice_name)

	# Set defaults for blend
	if _voice_a_select.item_count > 1:
		_voice_a_select.selected = 1  # Masculine
	if _voice_b_select.item_count > 2:
		_voice_b_select.selected = 2  # Feminine

	# Connect UI signals
	_speak_btn.pressed.connect(_on_speak)
	_stop_btn.pressed.connect(_on_stop)
	_pitch_slider.value_changed.connect(_on_pitch_changed)
	_blend_slider.value_changed.connect(_on_blend_changed)
	_blend_preview_btn.pressed.connect(_on_blend_preview)
	_language_select.item_selected.connect(_on_language_changed)
	_markup_examples.item_selected.connect(_on_markup_example_changed)
	_markup_speak_btn.pressed.connect(_on_markup_speak)

	# Connect animalese signals
	animalese.speech_progress.connect(_on_speech_progress)
	animalese.speech_finished.connect(_on_speech_finished)
	animalese.viseme_changed.connect(_on_viseme_changed)
	animalese.phoneme_started.connect(_on_phoneme_started)
	animalese.word_started.connect(_on_word_started)

	# Initialize markup text
	_on_markup_example_changed(0)

func _update_sample_text() -> void:
	var lang_idx := _language_select.selected
	var lang_name := _language_select.get_item_text(lang_idx)
	var lang_code: String = _languages.get(lang_name, "en")
	_text_input.text = _sample_texts.get(lang_code, _sample_texts["en"])

func _on_speak() -> void:
	var text := _text_input.text
	if text.is_empty():
		return

	# Set voice
	var voice_idx := _voice_select.selected
	if voice_idx >= 0:
		var voice_name := _voice_select.get_item_text(voice_idx)
		animalese.voice = _voices.get(voice_name)

	# Set language
	var lang_idx := _language_select.selected
	var lang_name := _language_select.get_item_text(lang_idx)
	var lang_code: String = _languages.get(lang_name, "es")

	if lang_code == "auto":
		animalese.auto_detect_language = true
		animalese.language = null
	else:
		animalese.auto_detect_language = false
		animalese.language = LanguageDetector.create_processor_for_code(lang_code)

	# Get emotion
	var emo_idx := _emotion_select.selected
	var emo_name := _emotions[emo_idx] if emo_idx >= 0 else "neutral"

	# Speak
	var pitch := _pitch_slider.value
	animalese.speak_with_emotion(text, emo_name, pitch)

	_progress_bar.value = 0.0

func _on_stop() -> void:
	animalese.stop_all()
	_progress_bar.value = 0.0
	_viseme_label.text = "SILENT (0)"
	_phoneme_label.text = "-"
	_word_label.text = "-"

func _on_pitch_changed(value: float) -> void:
	_pitch_label.text = "%.2fx" % value

func _on_blend_changed(value: float) -> void:
	_blend_label.text = "%d%%" % int(value * 100)

func _on_blend_preview() -> void:
	var voice_a_idx := _voice_a_select.selected
	var voice_b_idx := _voice_b_select.selected

	if voice_a_idx < 0 or voice_b_idx < 0:
		return

	var voice_a_name := _voice_a_select.get_item_text(voice_a_idx)
	var voice_b_name := _voice_b_select.get_item_text(voice_b_idx)

	var voice_a: AnimaleseVoice = _voices.get(voice_a_name)
	var voice_b: AnimaleseVoice = _voices.get(voice_b_name)

	if voice_a == null or voice_b == null:
		return

	var blended := ProceduralAnimalese.blend_voices(voice_a, voice_b, _blend_slider.value)
	animalese.voice = blended
	animalese.speak(_text_input.text, _pitch_slider.value)

func _on_language_changed(_idx: int) -> void:
	_update_sample_text()

func _on_markup_example_changed(idx: int) -> void:
	if idx >= 0 and idx < _markup_samples.size():
		_markup_text.text = _markup_samples[idx]["text"]

func _on_markup_speak() -> void:
	var text := _markup_text.text
	if text.is_empty():
		return

	# Use default voice for markup demo
	var voice_idx := _voice_select.selected
	if voice_idx >= 0:
		var voice_name := _voice_select.get_item_text(voice_idx)
		animalese.voice = _voices.get(voice_name)

	animalese.speak_markup(text, _pitch_slider.value)

func _on_speech_progress(ratio: float) -> void:
	_progress_bar.value = ratio

func _on_speech_finished() -> void:
	_progress_bar.value = 1.0
	# Reset after a moment
	await get_tree().create_timer(0.5).timeout
	_progress_bar.value = 0.0
	_viseme_label.text = "SILENT (0)"

func _on_viseme_changed(viseme: int, _weight: float) -> void:
	var viseme_names := ProceduralAnimalese.get_viseme_names()
	var name := viseme_names[viseme] if viseme < viseme_names.size() else "?"
	_viseme_label.text = "%s (%d)" % [name, viseme]
	_viseme_display.queue_redraw()

func _on_phoneme_started(phoneme: String, _idx: int) -> void:
	_phoneme_label.text = phoneme if not phoneme.is_empty() else "-"

func _on_word_started(word: String, _idx: int) -> void:
	_word_label.text = word if not word.is_empty() else "-"
