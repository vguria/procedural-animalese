# res://addons/procedural_animalese/procedural_animalese_editor_plugin.gd
@tool
extends EditorPlugin

const TYPE_NODE_NAME := "ProceduralAnimalese"
const TYPE_NODE_BASE := "Node"

const TYPE_VOICE := "AnimaleseVoice"
const TYPE_LIBRARY := "AnimaleseVoiceLibrary"
const TYPE_ENTRY := "AnimaleseVoiceEntry"
const TYPE_EMOTION := "AnimaleseEmotion"
const TYPE_LANGUAGE := "LanguageProcessor"
const TYPE_SPANISH := "SpanishProcessor"
const TYPE_ENGLISH := "EnglishProcessor"
const TYPE_JAPANESE := "JapaneseProcessor"

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

	add_custom_type(
		TYPE_VOICE,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/animalese_voice.gd"),
		null
	)

	add_custom_type(
		TYPE_LIBRARY,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/animalese_voice_library.gd"),
		null
	)

	add_custom_type(
		TYPE_ENTRY,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/animalese_voice_entry.gd"),
		null
	)

	add_custom_type(
		TYPE_EMOTION,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/animalese_emotion.gd"),
		null
	)

	add_custom_type(
		TYPE_LANGUAGE,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/language_processor.gd"),
		null
	)

	add_custom_type(
		TYPE_SPANISH,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/spanish_processor.gd"),
		null
	)

	add_custom_type(
		TYPE_ENGLISH,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/english_processor.gd"),
		null
	)

	add_custom_type(
		TYPE_JAPANESE,
		"Resource",
		preload("res://addons/procedural_animalese/runtime/japanese_processor.gd"),
		null
	)

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
	remove_custom_type(TYPE_VOICE)
	remove_custom_type(TYPE_LIBRARY)
	remove_custom_type(TYPE_ENTRY)
	remove_custom_type(TYPE_EMOTION)
	remove_custom_type(TYPE_LANGUAGE)
	remove_custom_type(TYPE_SPANISH)
	remove_custom_type(TYPE_ENGLISH)
	remove_custom_type(TYPE_JAPANESE)

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
