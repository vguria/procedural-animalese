@tool
extends Node
class_name ProceduralAnimalese
## Procedural "Animalese" speech synthesizer with syllable tokenization,
## basic prosody, and optional caching for repeated phrases.

## Path to the default voice preset (used when no voice is assigned).
const DEFAULT_VOICE_PATH := "res://addons/procedural_animalese/presets/voice_default.tres"

# Progress signals for lip-sync and subtitle synchronization.
signal phoneme_started(phoneme: String, index: int)
signal word_started(word: String, index: int)
signal speech_progress(ratio: float)  # 0.0 to 1.0
signal speech_finished()
signal viseme_changed(viseme: int, weight: float)  # Viseme index and blend weight (0-1)

@export var mix_rate: int = 44100 # Generator mix rate (Hz).
@export var buffer_length_sec: float = 0.35 # Generator buffer length (seconds).

@export var run_in_editor: bool = false # Allow playback in the editor.

@export var pause_space_sec: float = 0.03 # Pause for spaces.
@export var pause_comma_sec: float = 0.10 # Pause for commas/semicolons.
@export var pause_period_sec: float = 0.16 # Pause for sentence endings.

# Audio bus (procesado master para la voz)
@export var audio_bus_name: String = "Animalese"
@export var ensure_audio_bus: bool = true # Create the bus if it does not exist.
@export var auto_add_bus_effects: bool = true # Add EQ+compressor if missing.

# Cache
@export var enable_cache: bool = true # Cache synthesized segments.
@export var cache_unseeded: bool = false # si random_seed==0, por defecto NO cachea (para mantener variación)

@export var voice: AnimaleseVoice # Default voice.
@export var voice_library: AnimaleseVoiceLibrary # Optional per-character voices.
@export var language: LanguageProcessor # Language processor for text normalization and tokenization.
@export var auto_detect_language: bool = false # Automatically detect language from text (overrides language if true).
@export var emotion: AnimaleseEmotion # Default emotion (optional, modifies voice parameters).

# Default Spanish processor (created lazily if no language is set).
var _default_language: SpanishProcessor = null

@export_group("Threading")
@export var threaded_synthesis: bool = true # Use background thread for synthesis.

@export_group("Quality")
@export var use_extended_formants: bool = false # Use F4/F5 for extra brightness (more CPU).

var _gen: AudioStreamGenerator = AudioStreamGenerator.new()
var _player: AudioStreamPlayer = AudioStreamPlayer.new()
var _playback: AudioStreamGeneratorPlayback

var _segments: Array[PackedFloat32Array] = []
var _seg_idx: int = 0
var _frame_idx: int = 0

# Cache de segmentos ya sintetizados (hash int64 para mejor rendimiento)
var _segment_cache: Dictionary[int, PackedFloat32Array] = {}
var _cache_mutex: Mutex = Mutex.new()

# Gestión de invalidación de cache al cambiar la voz
var _connected_voice: AnimaleseVoice = null
var _voice_changed_callable: Callable = Callable()

# Threading state
var _pending_tasks: Array[int] = [] # WorkerThreadPool task IDs
var _segments_mutex: Mutex = Mutex.new()
var _stop_generation: int = 0 # Incremented on stop_all to cancel pending callbacks

# Progress tracking for signals
var _timing_markers: Array[Dictionary] = []  # [{type, value, sample_offset}]
var _total_samples: int = 0  # Total samples in current speech
var _global_sample_idx: int = 0  # Current playback position across all segments
var _last_emitted_marker: int = -1  # Index of last emitted marker
var _speech_active: bool = false  # Whether we're currently playing speech

# ---------------- Types ----------------
# Holds parameters for a synthesis task to be executed in a worker thread.
class SynthesisTask:
	var text: String
	var pitch_mul: float
	var voice_data: Dictionary # Serialized voice parameters (thread-safe copy)
	var mix_rate: int
	var pause_space_sec: float
	var pause_comma_sec: float
	var pause_period_sec: float
	var use_extended_formants: bool # Whether to use F4/F5 formants
	var node_id: int # Instance ID of the ProceduralAnimalese node
	var generation: int # Used to cancel stale callbacks after stop_all

enum Viseme {
	SILENT,  # Rest position, mouth closed (silence, M, B, P)
	AA,      # Open mouth (A)
	EE,      # Wide mouth, teeth visible (E, I)
	OO,      # Round/pursed lips (O, U)
	OH,      # Partially open, rounded (soft O)
	FF,      # Upper teeth on lower lip (F, V)
	TH,      # Tongue between teeth (TH, D, T)
	SS,      # Teeth together, narrow (S, Z, C)
	NN,      # Mouth slightly open, tongue up (N, L, R)
	CH,      # Lips pushed forward (CH, SH, J)
}

# Viseme marker for lip-sync track generation.
class VisemeMarker:
	var viseme: Viseme          # The viseme shape
	var phoneme: String         # Original phoneme that triggered this
	var time_sec: float         # Time in seconds from start
	var duration_sec: float     # Duration of this viseme
	var weight: float           # Blend weight (0-1), useful for transitions

	func _init(v: Viseme = Viseme.SILENT, ph: String = "", t: float = 0.0, dur: float = 0.0, w: float = 1.0) -> void:
		viseme = v
		phoneme = ph
		time_sec = t
		duration_sec = dur
		weight = w

	func to_dict() -> Dictionary:
		return {
			"viseme": viseme,
			"viseme_name": Viseme.keys()[viseme],
			"phoneme": phoneme,
			"time": time_sec,
			"duration": duration_sec,
			"weight": weight
		}

class MarkupSegment:
	var text: String = ""
	var pitch_mul: float = 1.0
	var speed_mul: float = 1.0
	var pause_sec: float = 0.0  # If > 0, this is a pause segment
	var voice_id: StringName = &""  # If not empty, use this voice from library
	var emotion_name: StringName = &""  # If not empty, apply this emotion

	func _init(t: String = "", pitch: float = 1.0, speed: float = 1.0, pause: float = 0.0, vid: StringName = &"", emo: StringName = &"") -> void:
		text = t
		pitch_mul = pitch
		speed_mul = speed
		pause_sec = pause
		voice_id = vid
		emotion_name = emo

# ---------------- Lifecycle ----------------
# Get the active language processor (assigned or default Spanish).
func _get_language() -> LanguageProcessor:
	if language != null:
		return language
	if _default_language == null:
		_default_language = SpanishProcessor.new()
	return _default_language

## Get language processor, with optional auto-detection from text.
func _get_language_for_text(text: String) -> LanguageProcessor:
	if auto_detect_language and not text.is_empty():
		return LanguageDetector.detect_and_create_processor(text)
	return _get_language()

## Detect the language of a text and return its ISO code (es, en, ja).
## Useful for debugging or manual language selection.
func detect_language(text: String) -> String:
	return LanguageDetector.detect_code(text)

## Create a language processor for a given ISO code.
## Codes: "es" (Spanish), "en" (English), "ja" (Japanese).
func create_language_processor(code: String) -> LanguageProcessor:
	return LanguageDetector.create_processor_for_code(code)

func _ready() -> void:
	if Engine.is_editor_hint() and not run_in_editor:
		set_process(false)
		return

	# Load default voice if none is assigned
	if voice == null:
		_load_default_voice()

	if ensure_audio_bus:
		_setup_audio_bus()

	_gen.mix_rate = mix_rate
	_gen.buffer_length = buffer_length_sec
	_player.stream = _gen
	_player.bus = audio_bus_name

	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()

	_ensure_voice_connected(voice)

## Load the default voice preset if available.
func _load_default_voice() -> void:
	if ResourceLoader.exists(DEFAULT_VOICE_PATH):
		var default_voice = ResourceLoader.load(DEFAULT_VOICE_PATH) as AnimaleseVoice
		if default_voice != null:
			voice = default_voice
		else:
			push_warning("ProceduralAnimalese: Default voice at '%s' could not be loaded." % DEFAULT_VOICE_PATH)
	else:
		push_warning("ProceduralAnimalese: Default voice not found at '%s'. Assign a voice manually." % DEFAULT_VOICE_PATH)

func _process(_delta: float) -> void:
	if _playback == null:
		return

	var frames: int = _playback.get_frames_available()
	while frames > 0:
		var s: float = _next_sample()
		_playback.push_frame(Vector2(s, s))
		frames -= 1

# ---------------- Public API ----------------
# Queue Animalese audio for the given text using the default voice.
func speak(text: String, pitch_mul: float = 1.0) -> void:
	var v: AnimaleseVoice = voice
	if v == null:
		push_warning("ProceduralAnimalese.speak(): No voice configured. Assign a voice resource to the 'voice' property.")
		return
	if text.strip_edges().is_empty():
		return  # Silent return for empty text is expected behavior
	_ensure_voice_connected(v)
	_speak_internal(v, text, pitch_mul)

# Queue Animalese audio for a character id from the voice library.
func speak_for(character_id: StringName, text: String, pitch_mul: float = 1.0) -> void:
	var v: AnimaleseVoice = voice
	if voice_library != null:
		var lv: AnimaleseVoice = voice_library.get_voice(character_id)
		if lv != null:
			v = lv
		elif character_id != &"":
			push_warning("ProceduralAnimalese.speak_for(): Character '%s' not found in voice library. Using default voice." % character_id)
	if v == null:
		push_warning("ProceduralAnimalese.speak_for(): No voice configured. Assign a voice resource or voice library.")
		return
	if text.strip_edges().is_empty():
		return
	_ensure_voice_connected(v)
	_speak_internal(v, text, pitch_mul)

# Queue Animalese audio with a specific emotion applied.
# emotion_or_name: Either an AnimaleseEmotion resource or a string name (e.g., "happy", "sad").
func speak_with_emotion(text: String, emotion_or_name: Variant, pitch_mul: float = 1.0) -> void:
	var v: AnimaleseVoice = voice
	if v == null:
		push_warning("ProceduralAnimalese.speak_with_emotion(): No voice configured.")
		return
	if text.strip_edges().is_empty():
		return
	_ensure_voice_connected(v)

	var emo: AnimaleseEmotion
	if emotion_or_name is AnimaleseEmotion:
		emo = emotion_or_name
	elif emotion_or_name is String or emotion_or_name is StringName:
		emo = AnimaleseEmotion.get_by_name(str(emotion_or_name))
	else:
		push_warning("ProceduralAnimalese.speak_with_emotion(): Invalid emotion type. Expected AnimaleseEmotion or String, got %s. Using neutral." % typeof(emotion_or_name))
		emo = AnimaleseEmotion.neutral()

	_speak_internal_with_emotion(v, text, pitch_mul, emo)

# Queue Animalese audio with markup control tags.
# Supported tags:
#   [pause:0.5] - Insert a pause of 0.5 seconds
#   [pitch:1.2]text[/pitch] - Modify pitch by factor
#   [speed:0.8]text[/speed] - Modify speed by factor (affects char_duration_s)
#   [voice:id]text[/voice] - Use voice from library by character_id
#   [emotion:name]text[/emotion] - Apply emotion (happy, sad, angry, scared, nervous, excited, tired)
# Tags can be nested: [pitch:1.2][emotion:happy]text[/emotion][/pitch]
func speak_markup(text: String, base_pitch_mul: float = 1.0) -> void:
	if voice == null:
		push_warning("ProceduralAnimalese.speak_markup(): No voice configured.")
		return
	if text.strip_edges().is_empty():
		return
	_ensure_voice_connected(voice)

	var segments: Array[MarkupSegment] = _parse_markup(text)
	if segments.is_empty():
		return

	# Reset progress tracking for the whole markup speech
	_reset_progress_tracking()

	# Synthesize and queue each segment
	var all_samples: PackedFloat32Array = PackedFloat32Array()
	var all_markers: Array[AnimaleseSynth.TimingMarker] = []
	var sample_offset: int = 0

	for seg in segments:
		if seg.pause_sec > 0.0:
			# Insert silence
			var silence_samples: int = int(seg.pause_sec * float(mix_rate))
			var start_idx: int = all_samples.size()
			all_samples.resize(start_idx + silence_samples)
			for i in range(silence_samples):
				all_samples[start_idx + i] = 0.0
			sample_offset += silence_samples
			continue

		if seg.text.is_empty():
			continue

		# Determine voice for this segment
		var v: AnimaleseVoice = voice
		if seg.voice_id != &"" and voice_library != null:
			var lib_voice: AnimaleseVoice = voice_library.get_voice(seg.voice_id)
			if lib_voice != null:
				v = lib_voice

		# Apply emotion if specified
		var emo: AnimaleseEmotion = null
		if seg.emotion_name != &"":
			emo = AnimaleseEmotion.get_by_name(str(seg.emotion_name))
			v = _apply_emotion_to_voice(v, emo)

		# Apply speed modifier by temporarily adjusting voice duration
		var original_duration: float = v.char_duration_s
		if seg.speed_mul != 1.0:
			v.char_duration_s = original_duration / seg.speed_mul

		# Synthesize with pitch modifier (include emotion pitch if present)
		var final_pitch: float = base_pitch_mul * seg.pitch_mul
		if emo != null:
			final_pitch *= lerpf(1.0, emo.pitch_mul, emo.intensity)
		var seg_vd: Dictionary = AnimaleseSynth.serialize_voice(v)
		seg_vd["language_code"] = _get_language_for_text(seg.text).get_language_code()
		var seg_markers: Array[AnimaleseSynth.TimingMarker] = []
		var seg_samples: PackedFloat32Array = AnimaleseSynth.synthesize(seg.text, final_pitch, seg_vd, mix_rate, pause_space_sec, pause_comma_sec, pause_period_sec, use_extended_formants, seg_markers)

		# Restore original duration (only needed if we modified the original voice, not emotion-modified copy)
		if seg.emotion_name == &"":
			v.char_duration_s = original_duration

		# Offset markers and add to collection
		for m in seg_markers:
			if m.type != AnimaleseSynth.MarkerType.END:  # Skip intermediate END markers
				all_markers.append(AnimaleseSynth.TimingMarker.new(m.type, m.value, m.index, m.sample_offset + sample_offset))

		all_samples.append_array(seg_samples)
		sample_offset += seg_samples.size()

	# Add final END marker
	all_markers.append(AnimaleseSynth.TimingMarker.new(AnimaleseSynth.MarkerType.END, "", 0, all_samples.size()))

	if all_samples.size() > 0:
		_setup_progress_tracking(all_samples, all_markers)
		_add_segment_safe(all_samples)

func _speak_internal(v: AnimaleseVoice, text: String, pitch_mul: float) -> void:
	# Apply default emotion if set
	if emotion != null:
		_speak_internal_with_emotion(v, text, pitch_mul, emotion)
		return

	_reset_progress_tracking()

	var vd: Dictionary = AnimaleseSynth.serialize_voice(v)
	vd["language_code"] = _get_language_for_text(text).get_language_code()

	# Check cache first (thread-safe)
	var use_cache: bool = enable_cache and (cache_unseeded or v.random_seed != 0)
	if use_cache:
		var key := AnimaleseSynth.make_cache_key(vd, text, pitch_mul, mix_rate)
		_cache_mutex.lock()
		var cached: bool = _segment_cache.has(key)
		var seg: PackedFloat32Array = _segment_cache.get(key, PackedFloat32Array()) if cached else PackedFloat32Array()
		_cache_mutex.unlock()
		if cached and seg.size() > 0:
			# Regenerate markers from a dry pass (no DSP).
			var markers: Array[AnimaleseSynth.TimingMarker] = AnimaleseSynth.collect_timing_markers(text, vd, mix_rate, pause_space_sec, pause_comma_sec, pause_period_sec)
			_setup_progress_tracking(seg, markers)
			_add_segment_safe(seg)
			return

	if threaded_synthesis and not Engine.is_editor_hint():
		_queue_threaded_synthesis(v, text, pitch_mul)
	else:
		var markers: Array[AnimaleseSynth.TimingMarker] = []
		var seg: PackedFloat32Array = AnimaleseSynth.synthesize(text, pitch_mul, vd, mix_rate, pause_space_sec, pause_comma_sec, pause_period_sec, use_extended_formants, markers)
		if seg.size() > 0:
			_setup_progress_tracking(seg, markers)
			_add_segment_safe(seg)
			if use_cache:
				_cache_mutex.lock()
				_segment_cache[AnimaleseSynth.make_cache_key(vd, text, pitch_mul, mix_rate)] = seg
				_cache_mutex.unlock()

# Internal speak with emotion applied.
func _speak_internal_with_emotion(v: AnimaleseVoice, text: String, pitch_mul: float, emo: AnimaleseEmotion) -> void:
	_reset_progress_tracking()

	# Apply emotion to voice parameters using a temporary modified voice.
	var modified_v: AnimaleseVoice = _apply_emotion_to_voice(v, emo)
	var final_pitch_mul: float = pitch_mul * lerpf(1.0, emo.pitch_mul, emo.intensity)

	var vd: Dictionary = AnimaleseSynth.serialize_voice(modified_v)
	vd["language_code"] = _get_language_for_text(text).get_language_code()

	# Caching intentionally skipped for emotion-modified speech (emotion state varies).
	var markers: Array[AnimaleseSynth.TimingMarker] = []
	var seg: PackedFloat32Array = AnimaleseSynth.synthesize(text, final_pitch_mul, vd, mix_rate, pause_space_sec, pause_comma_sec, pause_period_sec, use_extended_formants, markers)
	if seg.size() > 0:
		_setup_progress_tracking(seg, markers)
		_add_segment_safe(seg)

# Create a temporary voice with emotion modifications applied.
func _apply_emotion_to_voice(v: AnimaleseVoice, emo: AnimaleseEmotion) -> AnimaleseVoice:
	var result: AnimaleseVoice = AnimaleseVoice.new()
	var t: float = emo.intensity

	# Copy all base values first
	result.voice_name = v.voice_name
	result.pitch_base_hz = v.pitch_base_hz  # Pitch handled via pitch_mul
	result.pitch_jitter = v.pitch_jitter * lerpf(1.0, emo.jitter_mul, t)
	result.char_duration_s = v.char_duration_s / lerpf(1.0, emo.speed_mul, t)
	result.consonant_duration_multiplier = v.consonant_duration_multiplier

	# Vibrato: use override if set and base has no vibrato
	if emo.vibrato_rate_override > 0.0 and v.vibrato_rate_hz == 0.0:
		result.vibrato_rate_hz = emo.vibrato_rate_override * t
		result.vibrato_depth = emo.vibrato_depth_override * t
	else:
		result.vibrato_rate_hz = v.vibrato_rate_hz * lerpf(1.0, emo.vibrato_mul, t)
		result.vibrato_depth = v.vibrato_depth * lerpf(1.0, emo.vibrato_mul, t)
	result.vibrato_delay = v.vibrato_delay

	# Mix and character
	result.output_gain = v.output_gain * lerpf(1.0, emo.volume_mul, t)
	result.breath_noise_level = clampf(v.breath_noise_level + emo.breathiness_add * t, 0.0, 1.5)
	result.whisper_amount = clampf(v.whisper_amount + emo.whisper_add * t, 0.0, 1.0)
	result.vocal_tract_scale = v.vocal_tract_scale
	result.vowel_formant_gain = v.vowel_formant_gain
	result.fricative_formant_gain = v.fricative_formant_gain
	result.stop_formant_gain = v.stop_formant_gain
	result.nasal_formant_gain = v.nasal_formant_gain

	# Expressivity
	result.prosody_strength = v.prosody_strength * lerpf(1.0, emo.prosody_mul, t)
	result.question_rise = v.question_rise
	result.statement_fall = v.statement_fall
	result.exclamation_boost = v.exclamation_boost
	result.vowel_breathiness = v.vowel_breathiness
	result.voiced_brightness = clampf(v.voiced_brightness + emo.brightness_add * t, 0.0, 1.0)

	# Envelope (preserve original)
	result.envelope_attack = v.envelope_attack
	result.envelope_sustain = v.envelope_sustain
	result.envelope_release = v.envelope_release

	# Coarticulation (preserve original)
	result.coarticulation_strength = v.coarticulation_strength
	result.coarticulation_window = v.coarticulation_window

	# Other settings
	result.segment_edge_fade_ms = v.segment_edge_fade_ms
	result.random_seed = v.random_seed

	# Copy formants
	result.vowel_a_formants = v.vowel_a_formants.duplicate()
	result.vowel_e_formants = v.vowel_e_formants.duplicate()
	result.vowel_i_formants = v.vowel_i_formants.duplicate()
	result.vowel_o_formants = v.vowel_o_formants.duplicate()
	result.vowel_u_formants = v.vowel_u_formants.duplicate()
	result.fricative_s_formants = v.fricative_s_formants.duplicate()
	result.fricative_f_formants = v.fricative_f_formants.duplicate()
	result.fricative_x_formants = v.fricative_x_formants.duplicate()
	result.stop_p_formants = v.stop_p_formants.duplicate()
	result.stop_t_formants = v.stop_t_formants.duplicate()
	result.stop_k_formants = v.stop_k_formants.duplicate()
	result.nasal_mn_formants = v.nasal_mn_formants.duplicate()
	result.extended_f4 = v.extended_f4
	result.extended_f5 = v.extended_f5

	return result

# Stop playback and clear the queued segments.
func stop_all() -> void:
	# Increment generation to cancel pending synthesis callbacks
	_stop_generation += 1

	_segments_mutex.lock()
	_segments.clear()
	_seg_idx = 0
	_frame_idx = 0
	_segments_mutex.unlock()

	# Clear pending task list (tasks will complete but their callbacks will be ignored)
	_pending_tasks.clear()

	# Reset progress tracking
	_reset_progress_tracking()

# Thread-safe segment addition.
func _add_segment_safe(seg: PackedFloat32Array) -> void:
	_segments_mutex.lock()
	_segments.append(seg)
	_segments_mutex.unlock()

# Reset progress tracking state.
func _reset_progress_tracking() -> void:
	_timing_markers.clear()
	_total_samples = 0
	_global_sample_idx = 0
	_last_emitted_marker = -1
	_speech_active = false

# Setup progress tracking with markers from synthesis.
func _setup_progress_tracking(seg: PackedFloat32Array, markers: Array[AnimaleseSynth.TimingMarker]) -> void:
	_timing_markers.clear()
	for m in markers:
		_timing_markers.append({
			"type": m.type,
			"value": m.value,
			"index": m.index,
			"sample_offset": m.sample_offset
		})
	_total_samples = seg.size()
	_global_sample_idx = 0
	_last_emitted_marker = -1
	_speech_active = true

# Queue synthesis to worker thread.
func _queue_threaded_synthesis(v: AnimaleseVoice, text: String, pitch_mul: float) -> void:
	var task := SynthesisTask.new()
	task.text = text
	task.pitch_mul = pitch_mul
	task.voice_data = AnimaleseSynth.serialize_voice(v)
	task.mix_rate = mix_rate
	task.pause_space_sec = pause_space_sec
	task.pause_comma_sec = pause_comma_sec
	task.pause_period_sec = pause_period_sec
	task.use_extended_formants = use_extended_formants
	task.node_id = get_instance_id()
	task.generation = _stop_generation
	# Add language code for thread-safe processing (with auto-detection if enabled)
	task.voice_data["language_code"] = _get_language_for_text(text).get_language_code()

	var task_id: int = WorkerThreadPool.add_task(Callable(self, "_synthesis_worker").bind(task))
	_pending_tasks.append(task_id)

# Serialize voice parameters for thread-safe access.
func _synthesis_worker(task: SynthesisTask) -> void:
	var markers: Array[AnimaleseSynth.TimingMarker] = []
	var seg: PackedFloat32Array = AnimaleseSynth.synthesize(task.text, task.pitch_mul, task.voice_data, task.mix_rate, task.pause_space_sec, task.pause_comma_sec, task.pause_period_sec, task.use_extended_formants, markers)

	# Use call_deferred to safely add segment on main thread
	call_deferred("_on_synthesis_complete", seg, task, markers)

# Called on main thread when synthesis completes.
func _on_synthesis_complete(seg: PackedFloat32Array, task: SynthesisTask, markers: Array[AnimaleseSynth.TimingMarker]) -> void:
	# Check if this task was cancelled by stop_all
	if task.generation != _stop_generation:
		return

	if seg.size() > 0:
		_setup_progress_tracking(seg, markers)
		_add_segment_safe(seg)

		# Update cache
		var use_cache: bool = enable_cache and (cache_unseeded or task.voice_data.get("random_seed", 0) != 0)
		if use_cache:
			var key := AnimaleseSynth.make_cache_key(task.voice_data, task.text, task.pitch_mul, task.mix_rate)
			_cache_mutex.lock()
			_segment_cache[key] = seg
			_cache_mutex.unlock()

# Generate cache key as int64 hash for better performance.
func synthesize_to_buffer(text: String, pitch_mul: float = 1.0, override_voice: AnimaleseVoice = null) -> PackedFloat32Array:
	var v: AnimaleseVoice = override_voice if override_voice != null else voice
	if v == null:
		push_warning("ProceduralAnimalese.synthesize_to_buffer(): No voice configured.")
		return PackedFloat32Array()
	if text.strip_edges().is_empty():
		return PackedFloat32Array()
	var vd: Dictionary = AnimaleseSynth.serialize_voice(v)
	vd["language_code"] = _get_language_for_text(text).get_language_code()
	return AnimaleseSynth.synthesize(text, pitch_mul, vd, mix_rate, pause_space_sec, pause_comma_sec, pause_period_sec, use_extended_formants)

# Blend two voices by interpolating all numeric parameters.
# factor = 0.0 -> voice_a, factor = 1.0 -> voice_b
static func blend_voices(voice_a: AnimaleseVoice, voice_b: AnimaleseVoice, factor: float) -> AnimaleseVoice:
	if voice_a == null and voice_b == null:
		push_warning("ProceduralAnimalese.blend_voices(): Both voices are null.")
		return AnimaleseVoice.new()
	if voice_a == null:
		push_warning("ProceduralAnimalese.blend_voices(): voice_a is null, returning voice_b.")
		return voice_b.duplicate() if voice_b != null else AnimaleseVoice.new()
	if voice_b == null:
		push_warning("ProceduralAnimalese.blend_voices(): voice_b is null, returning voice_a.")
		return voice_a.duplicate() if voice_a != null else AnimaleseVoice.new()

	var result := AnimaleseVoice.new()
	var t: float = clampf(factor, 0.0, 1.0)

	result.voice_name = voice_a.voice_name + " + " + voice_b.voice_name if t > 0.0 and t < 1.0 else (voice_b.voice_name if t >= 0.5 else voice_a.voice_name)
	result.pitch_base_hz = lerpf(voice_a.pitch_base_hz, voice_b.pitch_base_hz, t)
	result.pitch_jitter = lerpf(voice_a.pitch_jitter, voice_b.pitch_jitter, t)
	result.char_duration_s = lerpf(voice_a.char_duration_s, voice_b.char_duration_s, t)
	result.consonant_duration_multiplier = lerpf(voice_a.consonant_duration_multiplier, voice_b.consonant_duration_multiplier, t)

	result.vibrato_rate_hz = lerpf(voice_a.vibrato_rate_hz, voice_b.vibrato_rate_hz, t)
	result.vibrato_depth = lerpf(voice_a.vibrato_depth, voice_b.vibrato_depth, t)
	result.vibrato_delay = lerpf(voice_a.vibrato_delay, voice_b.vibrato_delay, t)

	result.output_gain = lerpf(voice_a.output_gain, voice_b.output_gain, t)
	result.breath_noise_level = lerpf(voice_a.breath_noise_level, voice_b.breath_noise_level, t)
	result.vocal_tract_scale = lerpf(voice_a.vocal_tract_scale, voice_b.vocal_tract_scale, t)
	result.vowel_formant_gain = lerpf(voice_a.vowel_formant_gain, voice_b.vowel_formant_gain, t)
	result.fricative_formant_gain = lerpf(voice_a.fricative_formant_gain, voice_b.fricative_formant_gain, t)
	result.stop_formant_gain = lerpf(voice_a.stop_formant_gain, voice_b.stop_formant_gain, t)
	result.nasal_formant_gain = lerpf(voice_a.nasal_formant_gain, voice_b.nasal_formant_gain, t)

	result.prosody_strength = lerpf(voice_a.prosody_strength, voice_b.prosody_strength, t)
	result.question_rise = lerpf(voice_a.question_rise, voice_b.question_rise, t)
	result.statement_fall = lerpf(voice_a.statement_fall, voice_b.statement_fall, t)
	result.exclamation_boost = lerpf(voice_a.exclamation_boost, voice_b.exclamation_boost, t)
	result.vowel_breathiness = lerpf(voice_a.vowel_breathiness, voice_b.vowel_breathiness, t)
	result.voiced_brightness = lerpf(voice_a.voiced_brightness, voice_b.voiced_brightness, t)

	result.envelope_attack = lerpf(voice_a.envelope_attack, voice_b.envelope_attack, t)
	result.envelope_sustain = lerpf(voice_a.envelope_sustain, voice_b.envelope_sustain, t)
	result.envelope_release = lerpf(voice_a.envelope_release, voice_b.envelope_release, t)

	result.coarticulation_strength = lerpf(voice_a.coarticulation_strength, voice_b.coarticulation_strength, t)
	result.coarticulation_window = lerpf(voice_a.coarticulation_window, voice_b.coarticulation_window, t)

	result.segment_edge_fade_ms = lerpf(voice_a.segment_edge_fade_ms, voice_b.segment_edge_fade_ms, t)
	result.random_seed = voice_a.random_seed if t < 0.5 else voice_b.random_seed

	result.vowel_a_formants = _blend_formants_static(voice_a.vowel_a_formants, voice_b.vowel_a_formants, t)
	result.vowel_e_formants = _blend_formants_static(voice_a.vowel_e_formants, voice_b.vowel_e_formants, t)
	result.vowel_i_formants = _blend_formants_static(voice_a.vowel_i_formants, voice_b.vowel_i_formants, t)
	result.vowel_o_formants = _blend_formants_static(voice_a.vowel_o_formants, voice_b.vowel_o_formants, t)
	result.vowel_u_formants = _blend_formants_static(voice_a.vowel_u_formants, voice_b.vowel_u_formants, t)
	result.fricative_s_formants = _blend_formants_static(voice_a.fricative_s_formants, voice_b.fricative_s_formants, t)
	result.fricative_f_formants = _blend_formants_static(voice_a.fricative_f_formants, voice_b.fricative_f_formants, t)
	result.fricative_x_formants = _blend_formants_static(voice_a.fricative_x_formants, voice_b.fricative_x_formants, t)
	result.stop_p_formants = _blend_formants_static(voice_a.stop_p_formants, voice_b.stop_p_formants, t)
	result.stop_t_formants = _blend_formants_static(voice_a.stop_t_formants, voice_b.stop_t_formants, t)
	result.stop_k_formants = _blend_formants_static(voice_a.stop_k_formants, voice_b.stop_k_formants, t)
	result.nasal_mn_formants = _blend_formants_static(voice_a.nasal_mn_formants, voice_b.nasal_mn_formants, t)

	return result

static func _blend_formants_static(arr_a: Array[Vector3], arr_b: Array[Vector3], t: float) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count: int = mini(arr_a.size(), arr_b.size())
	for i in range(count):
		result.append(arr_a[i].lerp(arr_b[i], t))
	return result

# Export synthesized speech to a WAV file.
# Returns OK on success, or an error code on failure.
func export_to_wav(text: String, path: String, pitch_mul: float = 1.0, override_voice: AnimaleseVoice = null) -> Error:
	var v: AnimaleseVoice = override_voice if override_voice != null else voice
	if v == null:
		push_error("ProceduralAnimalese: No voice configured for WAV export")
		return ERR_UNCONFIGURED

	var vd: Dictionary = AnimaleseSynth.serialize_voice(v)
	vd["language_code"] = _get_language_for_text(text).get_language_code()
	var samples: PackedFloat32Array = AnimaleseSynth.synthesize(text, pitch_mul, vd, mix_rate, pause_space_sec, pause_comma_sec, pause_period_sec, use_extended_formants)
	if samples.size() == 0:
		push_error("ProceduralAnimalese: No audio samples generated")
		return ERR_INVALID_DATA

	return _write_wav_file(path, samples, mix_rate)

# Write PCM samples to a WAV file (16-bit mono).
func _write_wav_file(path: String, samples: PackedFloat32Array, sample_rate: int) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ProceduralAnimalese: Cannot open file for writing: " + path)
		return FileAccess.get_open_error()

	var num_samples: int = samples.size()
	var num_channels: int = 1  # Mono
	var bits_per_sample: int = 16
	var byte_rate: int = sample_rate * num_channels * bits_per_sample / 8
	var block_align: int = num_channels * bits_per_sample / 8
	var data_size: int = num_samples * block_align

	# RIFF header
	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_size)  # File size - 8
	file.store_buffer("WAVE".to_ascii_buffer())

	# fmt subchunk
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)  # Subchunk size (16 for PCM)
	file.store_16(1)   # Audio format (1 = PCM)
	file.store_16(num_channels)
	file.store_32(sample_rate)
	file.store_32(byte_rate)
	file.store_16(block_align)
	file.store_16(bits_per_sample)

	# data subchunk
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_size)

	# Convert float samples to 16-bit PCM and write
	for i in range(num_samples):
		var sample_f: float = clampf(samples[i], -1.0, 1.0)
		var sample_i: int = int(sample_f * 32767.0)
		file.store_16(sample_i)

	file.close()
	return OK

# ---------------- Cache ----------------
func _ensure_voice_connected(v: AnimaleseVoice) -> void:
	if v == _connected_voice:
		return

	# desconecta anterior
	if _connected_voice != null and _voice_changed_callable.is_valid():
		if _connected_voice.changed.is_connected(_voice_changed_callable):
			_connected_voice.changed.disconnect(_voice_changed_callable)

	_connected_voice = v
	_voice_changed_callable = Callable(self, "_on_voice_changed")

	if _connected_voice != null:
		if not _connected_voice.changed.is_connected(_voice_changed_callable):
			_connected_voice.changed.connect(_voice_changed_callable)

	# por seguridad, limpia cache cuando cambias de voz
	_cache_mutex.lock()
	_segment_cache.clear()
	_cache_mutex.unlock()

func _on_voice_changed() -> void:
	_cache_mutex.lock()
	_segment_cache.clear()
	_cache_mutex.unlock()

# ---------------- Audio bus ----------------
func _setup_audio_bus() -> void:
	var idx: int = AudioServer.get_bus_index(audio_bus_name)
	if idx == -1:
		AudioServer.add_bus(AudioServer.bus_count)
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, audio_bus_name)

	# Evita duplicados
	if not auto_add_bus_effects:
		return

	var has_eq: bool = false
	var has_comp: bool = false
	var ec: int = AudioServer.get_bus_effect_count(idx)
	for i in range(ec):
		var e: AudioEffect = AudioServer.get_bus_effect(idx, i)
		if e is AudioEffectEQ10:
			has_eq = true
		elif e is AudioEffectCompressor:
			has_comp = true

	if not has_eq:
		var eq := AudioEffectEQ10.new()
		# 10 bandas: 31,62,125,250,500,1k,2k,4k,8k,16k
		eq.set_band_gain_db(0, -4.0)
		eq.set_band_gain_db(1, -2.0)
		eq.set_band_gain_db(2, -1.0)
		eq.set_band_gain_db(3,  0.0)
		eq.set_band_gain_db(4,  1.0)
		eq.set_band_gain_db(5,  2.0)
		eq.set_band_gain_db(6,  2.0)
		eq.set_band_gain_db(7,  1.0)
		eq.set_band_gain_db(8,  0.0)
		eq.set_band_gain_db(9, -1.0)
		AudioServer.add_bus_effect(idx, eq, AudioServer.get_bus_effect_count(idx))

	if not has_comp:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -18.0
		comp.ratio = 3.5
		comp.attack_us = 200.0
		comp.release_ms = 250.0
		comp.gain = 2.5
		comp.mix = 1.0
		AudioServer.add_bus_effect(idx, comp, AudioServer.get_bus_effect_count(idx))

# ---------------- Synthesis (syllable tokenization) ----------------
# Create a language processor from a language code (for threaded synthesis).
# ---------------- Utilities ----------------
func _parse_markup(text: String) -> Array[MarkupSegment]:
	var segments: Array[MarkupSegment] = []
	var regex := RegEx.new()

	# Match tags: [tag:value] or [/tag]
	regex.compile("\\[(/?)(pause|pitch|speed|voice|emotion)(?::([^\\]]+))?\\]")

	var pos: int = 0
	var pitch_stack: Array[float] = [1.0]
	var speed_stack: Array[float] = [1.0]
	var voice_stack: Array[StringName] = [&""]
	var emotion_stack: Array[StringName] = [&""]

	while pos < text.length():
		var match_result: RegExMatch = regex.search(text, pos)

		if match_result == null:
			# No more tags, add remaining text
			var remaining: String = text.substr(pos)
			if remaining.length() > 0:
				segments.append(MarkupSegment.new(
					remaining,
					pitch_stack[-1],
					speed_stack[-1],
					0.0,
					voice_stack[-1],
					emotion_stack[-1]
				))
			break

		var match_start: int = match_result.get_start()
		var match_end: int = match_result.get_end()

		# Add text before the tag
		if match_start > pos:
			var before_text: String = text.substr(pos, match_start - pos)
			if before_text.length() > 0:
				segments.append(MarkupSegment.new(
					before_text,
					pitch_stack[-1],
					speed_stack[-1],
					0.0,
					voice_stack[-1],
					emotion_stack[-1]
				))

		var is_closing: bool = match_result.get_string(1) == "/"
		var tag_name: String = match_result.get_string(2)
		var tag_value: String = match_result.get_string(3) if match_result.get_string(3) else ""

		if is_closing:
			# Closing tag - pop from appropriate stack
			match tag_name:
				"pitch":
					if pitch_stack.size() > 1:
						pitch_stack.pop_back()
				"speed":
					if speed_stack.size() > 1:
						speed_stack.pop_back()
				"voice":
					if voice_stack.size() > 1:
						voice_stack.pop_back()
				"emotion":
					if emotion_stack.size() > 1:
						emotion_stack.pop_back()
		else:
			# Opening tag
			match tag_name:
				"pause":
					# Pause is immediate, add as a pause segment
					var pause_sec: float = tag_value.to_float() if tag_value.length() > 0 else 0.5
					segments.append(MarkupSegment.new("", 1.0, 1.0, pause_sec, &"", &""))
				"pitch":
					var pitch_val: float = tag_value.to_float() if tag_value.length() > 0 else 1.0
					pitch_stack.append(pitch_stack[-1] * pitch_val)
				"speed":
					var speed_val: float = tag_value.to_float() if tag_value.length() > 0 else 1.0
					speed_stack.append(speed_stack[-1] * speed_val)
				"voice":
					var voice_id: StringName = StringName(tag_value) if tag_value.length() > 0 else &""
					voice_stack.append(voice_id)
				"emotion":
					var emo_name: StringName = StringName(tag_value) if tag_value.length() > 0 else &""
					emotion_stack.append(emo_name)

		pos = match_end

	return segments

func _normalize_text(text: String) -> String:
	var s: String = text.to_lower()

	# diacríticos
	s = s.replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u").replace("ü", "u")
	s = s.replace("ñ", "n")

	# h muda
	s = s.replace("h", "")

	# dígrafos
	s = s.replace("ll", "y")
	s = s.replace("rr", "r")
	s = s.replace("ch", "x")

	# reglas ES básicas
	s = s.replace("que", "ke").replace("qui", "ki")
	s = s.replace("gue", "ge").replace("gui", "gi") # elimina u muda
	s = s.replace("ce", "se").replace("ci", "si")
	s = s.replace("ge", "xe").replace("gi", "xi")
	s = s.replace("qu", "k")

	return s

# ---------------- Streaming queue ----------------
func _next_sample() -> float:
	_segments_mutex.lock()
	while _seg_idx < _segments.size():
		var seg: PackedFloat32Array = _segments[_seg_idx]
		if _frame_idx < seg.size():
			var v: float = seg[_frame_idx]
			_frame_idx += 1
			_segments_mutex.unlock()

			# Progress tracking and signal emission
			if _speech_active:
				_global_sample_idx += 1
				_check_and_emit_markers()

			return v
		_seg_idx += 1
		_frame_idx = 0

	if _segments.size() > 0:
		_segments.clear()
		_seg_idx = 0
		_frame_idx = 0
		# Speech finished
		if _speech_active:
			_speech_active = false
			call_deferred("_emit_speech_finished")

	_segments_mutex.unlock()
	return 0.0

# Check markers and emit signals (called from _next_sample).
func _check_and_emit_markers() -> void:
	# Emit progress signal periodically (every ~1000 samples to avoid spam)
	if _total_samples > 0 and (_global_sample_idx % 1000) == 0:
		var ratio: float = float(_global_sample_idx) / float(_total_samples)
		call_deferred("emit_signal", "speech_progress", clampf(ratio, 0.0, 1.0))

	# Check if we've crossed any marker boundaries
	for i in range(_last_emitted_marker + 1, _timing_markers.size()):
		var marker: Dictionary = _timing_markers[i]
		if _global_sample_idx >= marker["sample_offset"]:
			_last_emitted_marker = i
			var marker_type: int = marker["type"]
			if marker_type == AnimaleseSynth.MarkerType.PHONEME:
				call_deferred("emit_signal", "phoneme_started", marker["value"], marker["index"])
				# Emit viseme signal for lip-sync
				var viseme: Viseme = _phoneme_to_viseme(marker["value"])
				call_deferred("emit_signal", "viseme_changed", viseme, 1.0)
			elif marker_type == AnimaleseSynth.MarkerType.WORD:
				call_deferred("emit_signal", "word_started", marker["value"], marker["index"])
			# END marker is handled when segments clear
		else:
			break  # Markers are ordered, no need to check further

func _emit_speech_finished() -> void:
	speech_finished.emit()
	# Return to silent viseme when speech ends
	viseme_changed.emit(Viseme.SILENT, 1.0)

# ==================== LIP-SYNC / VISEME SYSTEM ====================

# Map a phoneme character to its corresponding viseme.
func _phoneme_to_viseme(phoneme: String) -> Viseme:
	if phoneme.is_empty():
		return Viseme.SILENT

	var ch: String = phoneme.to_lower()[0]
	match ch:
		# Vowels
		"a": return Viseme.AA
		"e": return Viseme.EE
		"i": return Viseme.EE
		"o": return Viseme.OO
		"u": return Viseme.OO

		# Bilabials (lips together)
		"m", "b", "p": return Viseme.SILENT

		# Labiodentals (teeth on lip)
		"f", "v": return Viseme.FF

		# Dentals/Alveolars
		"t", "d": return Viseme.TH
		"n", "l", "r": return Viseme.NN

		# Sibilants (teeth together)
		"s", "z", "c": return Viseme.SS

		# Affricates and palatals
		"x", "j", "y": return Viseme.CH  # ch, sh, y sounds

		# Velars
		"k", "g", "q": return Viseme.OH

		# Default
		_: return Viseme.SILENT

# Get the viseme track for a given text (for pre-baked animation).
# Returns an array of VisemeMarker with timing information.
func get_viseme_track(text: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Array[VisemeMarker]:
	if v == null:
		v = voice
	if v == null:
		push_warning("ProceduralAnimalese.get_viseme_track(): No voice configured.")
		return []
	if text.strip_edges().is_empty():
		return []

	var track: Array[VisemeMarker] = []
	var lang: LanguageProcessor = _get_language_for_text(text)
	var s: String = lang.normalize(text)
	var tokens: Array[String] = lang.tokenize(s)

	var time_sec: float = 0.0
	var char_dur: float = v.char_duration_s
	var cons_mul: float = v.consonant_duration_multiplier

	for tok in tokens:
		# Handle punctuation/pauses
		if tok == " ":
			# Add silent viseme for space
			track.append(VisemeMarker.new(Viseme.SILENT, " ", time_sec, pause_space_sec, 1.0))
			time_sec += pause_space_sec
			continue
		if tok == "," or tok == ";":
			track.append(VisemeMarker.new(Viseme.SILENT, tok, time_sec, pause_comma_sec, 1.0))
			time_sec += pause_comma_sec
			continue
		if tok == "." or tok == "!" or tok == "?" or tok == ":":
			track.append(VisemeMarker.new(Viseme.SILENT, tok, time_sec, pause_period_sec, 1.0))
			time_sec += pause_period_sec
			continue

		# Handle CV syllables (consonant + vowel)
		if tok.length() == 2 and lang.is_vowel(tok[1]):
			var consonant: String = tok[0]
			var vowel: String = tok[1]

			# Consonant
			var cons_dur: float = char_dur * 0.55 * cons_mul
			var cons_viseme: Viseme = _phoneme_to_viseme(consonant)
			track.append(VisemeMarker.new(cons_viseme, consonant, time_sec, cons_dur, 1.0))
			time_sec += cons_dur

			# Vowel
			var vowel_dur: float = char_dur * 1.15
			var vowel_viseme: Viseme = _phoneme_to_viseme(vowel)
			track.append(VisemeMarker.new(vowel_viseme, vowel, time_sec, vowel_dur, 1.0))
			time_sec += vowel_dur
		else:
			# Single phoneme
			var dur: float = char_dur
			if not lang.is_vowel(tok):
				dur *= cons_mul
			else:
				dur *= 1.10

			var viseme: Viseme = _phoneme_to_viseme(tok)
			track.append(VisemeMarker.new(viseme, tok, time_sec, dur, 1.0))
			time_sec += dur

	# Add final silent
	track.append(VisemeMarker.new(Viseme.SILENT, "", time_sec, 0.1, 1.0))

	return track

# Get viseme track as an array of dictionaries (for JSON export or animation tools).
func get_viseme_track_as_dict(text: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Array[Dictionary]:
	var track: Array[VisemeMarker] = get_viseme_track(text, pitch_mul, v)
	var result: Array[Dictionary] = []
	for marker in track:
		result.append(marker.to_dict())
	return result

# Export viseme track to JSON string.
func export_viseme_track_json(text: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> String:
	var track: Array[Dictionary] = get_viseme_track_as_dict(text, pitch_mul, v)
	return JSON.stringify(track, "\t")

# Get the current viseme for real-time lip-sync (call during playback).
# Returns the viseme index and blend weight based on current playback position.
func get_current_viseme() -> Dictionary:
	if not _speech_active or _timing_markers.is_empty():
		return {"viseme": Viseme.SILENT, "weight": 1.0, "phoneme": ""}

	var current_time: float = float(_global_sample_idx) / float(mix_rate)

	# Find the current phoneme marker
	var current_phoneme: String = ""
	for i in range(_timing_markers.size() - 1, -1, -1):
		var marker: Dictionary = _timing_markers[i]
		if marker["type"] == AnimaleseSynth.MarkerType.PHONEME:
			var marker_time: float = float(marker["sample_offset"]) / float(mix_rate)
			if current_time >= marker_time:
				current_phoneme = marker["value"]
				break

	var viseme: Viseme = _phoneme_to_viseme(current_phoneme)
	return {"viseme": viseme, "weight": 1.0, "phoneme": current_phoneme}

# Get all available viseme names (useful for animation setup).
static func get_viseme_names() -> PackedStringArray:
	return PackedStringArray([
		"SILENT", "AA", "EE", "OO", "OH", "FF", "TH", "SS", "NN", "CH"
	])

# Get viseme count.
static func get_viseme_count() -> int:
	return 10

# ==================== ANIMATION GENERATION ====================

## Generate an Animation resource from viseme track.
## The animation will have a VALUE track that animates an integer property.
## Useful for Sprite2D.frame, AnimatedSprite2D, or custom viseme properties.
## - text: The text to synthesize and generate visemes from.
## - property_path: Node path + property (e.g., "Mouth:frame" or "Character/Mouth:frame").
## - pitch_mul: Pitch multiplier for synthesis timing.
## - v: Voice to use (optional, uses default if null).
func create_viseme_animation(text: String, property_path: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Animation:
	if property_path.is_empty():
		push_error("ProceduralAnimalese.create_viseme_animation(): property_path cannot be empty.")
		return null
	var track_data: Array[VisemeMarker] = get_viseme_track(text, pitch_mul, v)
	if track_data.is_empty():
		return null

	var anim := Animation.new()
	var track_idx: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track_idx, property_path)
	anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_NEAREST)
	anim.value_track_set_update_mode(track_idx, Animation.UPDATE_DISCRETE)

	for marker in track_data:
		anim.track_insert_key(track_idx, marker.time_sec, marker.viseme)

	# Set animation length
	if track_data.size() > 0:
		var last: VisemeMarker = track_data[track_data.size() - 1]
		anim.length = last.time_sec + last.duration_sec

	return anim


## Generate an Animation with a METHOD track that calls a method with viseme data.
## The method will be called with (viseme: int, weight: float) parameters.
## Useful for custom lip-sync implementations.
## - text: The text to synthesize.
## - node_path: Path to the node with the method (e.g., "Character/Mouth").
## - method_name: Name of the method to call (e.g., "set_viseme").
func create_viseme_method_animation(text: String, node_path: String, method_name: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Animation:
	if node_path.is_empty():
		push_error("ProceduralAnimalese.create_viseme_method_animation(): node_path cannot be empty.")
		return null
	if method_name.is_empty():
		push_error("ProceduralAnimalese.create_viseme_method_animation(): method_name cannot be empty.")
		return null
	var track_data: Array[VisemeMarker] = get_viseme_track(text, pitch_mul, v)
	if track_data.is_empty():
		return null

	var anim := Animation.new()
	var track_idx: int = anim.add_track(Animation.TYPE_METHOD)
	anim.track_set_path(track_idx, node_path)

	for marker in track_data:
		var method_dict := {
			"method": method_name,
			"args": [marker.viseme, marker.weight]
		}
		anim.track_insert_key(track_idx, marker.time_sec, method_dict)

	# Set animation length
	if track_data.size() > 0:
		var last: VisemeMarker = track_data[track_data.size() - 1]
		anim.length = last.time_sec + last.duration_sec

	return anim


## Generate an Animation with BLEND_SHAPE tracks for 3D characters.
## Creates one track per viseme that animates from 0 to 1 and back.
## - text: The text to synthesize.
## - mesh_path: Path to the MeshInstance3D (e.g., "Character/Head").
## - blend_shape_prefix: Prefix for blend shape names (e.g., "viseme_" -> "viseme_AA", "viseme_EE", etc.).
func create_viseme_blend_shape_animation(text: String, mesh_path: String, blend_shape_prefix: String = "viseme_", pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Animation:
	if mesh_path.is_empty():
		push_error("ProceduralAnimalese.create_viseme_blend_shape_animation(): mesh_path cannot be empty.")
		return null
	var track_data: Array[VisemeMarker] = get_viseme_track(text, pitch_mul, v)
	if track_data.is_empty():
		return null

	var anim := Animation.new()
	var viseme_names := get_viseme_names()

	# Create a track for each viseme blend shape
	var track_indices: Dictionary = {}
	for i in range(viseme_names.size()):
		var blend_name: String = blend_shape_prefix + viseme_names[i]
		var track_idx: int = anim.add_track(Animation.TYPE_BLEND_SHAPE)
		anim.track_set_path(track_idx, mesh_path + ":" + blend_name)
		anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
		track_indices[i] = track_idx
		# Initialize all blend shapes to 0 at time 0
		anim.track_insert_key(track_idx, 0.0, 0.0)

	# Add keys for each viseme transition
	var prev_viseme: int = Viseme.SILENT
	for marker in track_data:
		var cur_viseme: int = marker.viseme

		# Fade out previous viseme
		if prev_viseme != cur_viseme and track_indices.has(prev_viseme):
			var prev_track: int = track_indices[prev_viseme]
			anim.track_insert_key(prev_track, marker.time_sec, 0.0)

		# Fade in current viseme
		if track_indices.has(cur_viseme):
			var cur_track: int = track_indices[cur_viseme]
			anim.track_insert_key(cur_track, marker.time_sec, marker.weight)

		prev_viseme = cur_viseme

	# Set animation length
	if track_data.size() > 0:
		var last: VisemeMarker = track_data[track_data.size() - 1]
		anim.length = last.time_sec + last.duration_sec

		# Ensure all tracks end at 0
		for viseme_idx in track_indices.keys():
			var track_idx: int = track_indices[viseme_idx]
			anim.track_insert_key(track_idx, anim.length, 0.0)

	return anim


## Helper to add a generated animation to an AnimationPlayer.
## Returns the animation name.
func add_viseme_animation_to_player(player: AnimationPlayer, anim: Animation, anim_name: String = "lip_sync") -> String:
	if player == null:
		push_error("ProceduralAnimalese.add_viseme_animation_to_player(): player cannot be null.")
		return ""
	if anim == null:
		push_error("ProceduralAnimalese.add_viseme_animation_to_player(): anim cannot be null.")
		return ""

	var lib: AnimationLibrary
	if player.has_animation_library(""):
		lib = player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)

	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)
	lib.add_animation(anim_name, anim)

	return anim_name
