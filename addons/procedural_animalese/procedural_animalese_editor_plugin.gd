# res://addons/procedural_animalese/procedural_animalese_editor_plugin.gd
@tool
extends EditorPlugin

const TYPE_NODE_NAME := "ProceduralAnimalese"
const TYPE_NODE_BASE := "Node"

# Non-language custom types: registered individually below.
const NODE_TYPES := [
	["AnimaleseVoice",         "Resource", "res://addons/procedural_animalese/runtime/animalese_voice.gd"],
	["AnimaleseVoiceLibrary",  "Resource", "res://addons/procedural_animalese/runtime/animalese_voice_library.gd"],
	["AnimaleseVoiceEntry",    "Resource", "res://addons/procedural_animalese/runtime/animalese_voice_entry.gd"],
	["AnimaleseEmotion",       "Resource", "res://addons/procedural_animalese/runtime/animalese_emotion.gd"],
	["LanguageProcessor",      "Resource", "res://addons/procedural_animalese/runtime/language_processor.gd"],
]

# Every language processor gets registered as a Resource so it appears in the
# editor's "New Resource" menu. To add a new language, add one line here and one
# match arm in LanguageDetector.create_processor_for_code — no other files.
const LANGUAGE_PROCESSORS := [
	["SpanishProcessor",    "res://addons/procedural_animalese/runtime/spanish_processor.gd"],
	["EnglishProcessor",    "res://addons/procedural_animalese/runtime/english_processor.gd"],
	["JapaneseProcessor",   "res://addons/procedural_animalese/runtime/japanese_processor.gd"],
	["FrenchProcessor",     "res://addons/procedural_animalese/runtime/french_processor.gd"],
	["GermanProcessor",     "res://addons/procedural_animalese/runtime/german_processor.gd"],
	["PortugueseProcessor", "res://addons/procedural_animalese/runtime/portuguese_processor.gd"],
	["ItalianProcessor",    "res://addons/procedural_animalese/runtime/italian_processor.gd"],
	["RussianProcessor",    "res://addons/procedural_animalese/runtime/russian_processor.gd"],
	["ChineseProcessor",    "res://addons/procedural_animalese/runtime/chinese_processor.gd"],
]

var _dock: Control
var _preview_node: ProceduralAnimalese

func _enter_tree() -> void:
	# --- Register custom types ---
	add_custom_type(
		TYPE_NODE_NAME,
		TYPE_NODE_BASE,
		preload("res://addons/procedural_animalese/runtime/procedural_animalese.gd"),
		null
	)

	for entry in NODE_TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), null)

	for entry in LANGUAGE_PROCESSORS:
		add_custom_type(entry[0], "Resource", load(entry[1]), null)

	# --- Dock UI ---
	_dock = preload("res://addons/procedural_animalese/voice_editor_dock.gd").new()
	_dock.name = tr("Voice Editor")
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	_dock.call("set_editor_interface", get_editor_interface())
	_dock.call("set_undo_redo", get_undo_redo())

	# Connect preview signal
	if _dock.has_signal("request_preview"):
		_dock.connect("request_preview", Callable(self, "_on_request_preview"))

	# --- Preview node (lives under the plugin so it can play audio in-editor) ---
	_preview_node = preload("res://addons/procedural_animalese/runtime/procedural_animalese.gd").new()
	_preview_node.run_in_editor = true

	# Provide a default voice instance if none is selected in the dock (safe fallback)
	# (Artists will normally load a .tres voice in the dock.)
	var default_voice: AnimaleseVoice = AnimaleseVoice.new()
	default_voice.voice_name = "Preview Default"
	_preview_node.voice = default_voice
	default_voice.random_seed = 12345

	add_child(_preview_node)

func _exit_tree() -> void:
	# Remove preview node
	if _preview_node != null:
		_preview_node.queue_free()
		_preview_node = null

	# Remove dock
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	# Unregister custom types
	remove_custom_type(TYPE_NODE_NAME)
	for entry in NODE_TYPES:
		remove_custom_type(entry[0])
	for entry in LANGUAGE_PROCESSORS:
		remove_custom_type(entry[0])

func _on_request_preview(voice: AnimaleseVoice, text: String, pitch_mul: float) -> void:
	if _preview_node == null:
		return
	if voice == null:
		return
	_preview_node.voice = voice
	_preview_node.speak(text, pitch_mul)

	# Send waveform data to dock for visualization
	var samples: PackedFloat32Array = _preview_node.synthesize_to_buffer(text, pitch_mul, voice)
	if _dock != null and samples.size() > 0:
		_dock.call("set_waveform_samples", samples)
