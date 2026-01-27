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

class PhonemeConfig:
	var kind: StringName
	var voiced: bool
	var local_noise: float
	var formants: Array[Vector3]
	var is_vowel: bool

	func _init(k: StringName, voiced_in: bool, n: float, f: Array[Vector3], vowel: bool) -> void:
		kind = k
		voiced = voiced_in
		local_noise = n
		formants = f
		is_vowel = vowel

# Marker types for progress signals.
enum MarkerType { PHONEME, WORD, END }

# Viseme types for lip-sync animation.
# Based on a simplified set optimized for game characters.
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

class TimingMarker:
	var type: MarkerType
	var value: String  # phoneme or word text
	var index: int  # index in sequence
	var sample_offset: int  # sample position where this marker should fire

	func _init(t: MarkerType, v: String, idx: int, offset: int) -> void:
		type = t
		value = v
		index = idx
		sample_offset = offset

class PhraseInfo:
	var len: int = 1
	var is_question: bool = false
	var is_exclaim: bool = false

# Parsed markup segment for text with control tags.
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

class BiquadBandpass:
	var b0: float
	var b1: float
	var b2: float
	var a1: float
	var a2: float
	var z1: float = 0.0
	var z2: float = 0.0

	# Classic biquad band-pass (constant skirt gain, peak gain = Q).
	func setup(center_hz: float, q: float, sr: float) -> void:
		center_hz = clampf(center_hz, 20.0, sr * 0.45)
		q = maxf(0.1, q)

		var w0: float = TAU * center_hz / sr
		var cosw0: float = cos(w0)
		var sinw0: float = sin(w0)
		var alpha: float = sinw0 / (2.0 * q)

		var _b0: float = alpha
		var _b1: float = 0.0
		var _b2: float = -alpha
		var a0: float = 1.0 + alpha
		var _a1: float = -2.0 * cosw0
		var _a2: float = 1.0 - alpha

		b0 = _b0 / a0
		b1 = _b1 / a0
		b2 = _b2 / a0
		a1 = _a1 / a0
		a2 = _a2 / a0

	func process(x: float) -> float:
		var y: float = b0 * x + z1
		z1 = b1 * x - a1 * y + z2
		z2 = b2 * x - a2 * y
		return y

	# Reset filter state for reuse from pool.
	func reset() -> void:
		z1 = 0.0
		z2 = 0.0

# Pool of reusable BiquadBandpass filters to avoid allocations.
class BiquadPool:
	var _pool: Array[BiquadBandpass] = []
	var _in_use: int = 0

	# Get N filters from the pool.
	func acquire(count: int) -> Array[BiquadBandpass]:
		while _pool.size() < _in_use + count:
			_pool.append(BiquadBandpass.new())
		var result: Array[BiquadBandpass] = []
		for i in range(count):
			var f: BiquadBandpass = _pool[_in_use + i]
			f.reset()
			result.append(f)
		_in_use += count
		return result

	# Get 3 filters from the pool (for F1, F2, F3).
	func acquire_three() -> Array[BiquadBandpass]:
		return acquire(3)

	# Get 5 filters from the pool (for F1-F5 extended).
	func acquire_five() -> Array[BiquadBandpass]:
		return acquire(5)

	# Release all acquired filters back to the pool.
	func release_all() -> void:
		_in_use = 0

	# Get pool statistics for debugging.
	func get_stats() -> Dictionary:
		return {"total": _pool.size(), "in_use": _in_use}

# Global filter pool (shared across synthesis calls).
var _filter_pool: BiquadPool = BiquadPool.new()

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
	var all_markers: Array[TimingMarker] = []
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
		var seg_markers: Array[TimingMarker] = []
		var seg_samples: PackedFloat32Array = _synthesize(seg.text, final_pitch, v, seg_markers)

		# Restore original duration (only needed if we modified the original voice, not emotion-modified copy)
		if seg.emotion_name == &"":
			v.char_duration_s = original_duration

		# Offset markers and add to collection
		for m in seg_markers:
			if m.type != MarkerType.END:  # Skip intermediate END markers
				all_markers.append(TimingMarker.new(m.type, m.value, m.index, m.sample_offset + sample_offset))

		all_samples.append_array(seg_samples)
		sample_offset += seg_samples.size()

	# Add final END marker
	all_markers.append(TimingMarker.new(MarkerType.END, "", 0, all_samples.size()))

	if all_samples.size() > 0:
		_setup_progress_tracking(all_samples, all_markers)
		_add_segment_safe(all_samples)

func _speak_internal(v: AnimaleseVoice, text: String, pitch_mul: float) -> void:
	# Apply default emotion if set
	if emotion != null:
		_speak_internal_with_emotion(v, text, pitch_mul, emotion)
		return

	# Reset progress tracking
	_reset_progress_tracking()

	# Check cache first (thread-safe)
	var use_cache: bool = enable_cache and (cache_unseeded or v.random_seed != 0)
	if use_cache:
		var key := _make_cache_key(v, text, pitch_mul)
		_cache_mutex.lock()
		var cached: bool = _segment_cache.has(key)
		var seg: PackedFloat32Array = _segment_cache.get(key, PackedFloat32Array()) if cached else PackedFloat32Array()
		_cache_mutex.unlock()
		if cached and seg.size() > 0:
			# For cached segments, regenerate markers (lightweight, no audio generation)
			var markers: Array[TimingMarker] = _collect_timing_markers(text, pitch_mul, v)
			_setup_progress_tracking(seg, markers)
			_add_segment_safe(seg)
			return

	# Use threading if enabled and not in editor
	if threaded_synthesis and not Engine.is_editor_hint():
		_queue_threaded_synthesis(v, text, pitch_mul)
	else:
		# Synchronous fallback with marker collection
		var markers: Array[TimingMarker] = []
		var seg: PackedFloat32Array = _synthesize(text, pitch_mul, v, markers)
		if seg.size() > 0:
			_setup_progress_tracking(seg, markers)
			_add_segment_safe(seg)
			# Cache the segment
			if use_cache:
				var key2 := _make_cache_key(v, text, pitch_mul)
				_cache_mutex.lock()
				_segment_cache[key2] = seg
				_cache_mutex.unlock()

# Internal speak with emotion applied.
func _speak_internal_with_emotion(v: AnimaleseVoice, text: String, pitch_mul: float, emo: AnimaleseEmotion) -> void:
	# Reset progress tracking
	_reset_progress_tracking()

	# Apply emotion to voice parameters using a temporary modified voice
	var modified_v: AnimaleseVoice = _apply_emotion_to_voice(v, emo)

	# Adjust pitch_mul with emotion's pitch modifier
	var final_pitch_mul: float = pitch_mul * lerpf(1.0, emo.pitch_mul, emo.intensity)

	# Note: caching disabled for emotion-modified speech (emotion state varies)
	# Synchronous synthesis only for now (threaded would need emotion serialization)
	var markers: Array[TimingMarker] = []
	var seg: PackedFloat32Array = _synthesize(text, final_pitch_mul, modified_v, markers)
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
func _setup_progress_tracking(seg: PackedFloat32Array, markers: Array[TimingMarker]) -> void:
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
	task.voice_data = _serialize_voice(v)
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
func _serialize_voice(v: AnimaleseVoice) -> Dictionary:
	return {
		"pitch_base_hz": v.pitch_base_hz,
		"pitch_jitter": v.pitch_jitter,
		"char_duration_s": v.char_duration_s,
		"consonant_duration_multiplier": v.consonant_duration_multiplier,
		"output_gain": v.output_gain,
		"breath_noise_level": v.breath_noise_level,
		"whisper_amount": v.whisper_amount,
		"vocal_tract_scale": v.vocal_tract_scale,
		"vowel_formant_gain": v.vowel_formant_gain,
		"fricative_formant_gain": v.fricative_formant_gain,
		"stop_formant_gain": v.stop_formant_gain,
		"nasal_formant_gain": v.nasal_formant_gain,
		"prosody_strength": v.prosody_strength,
		"question_rise": v.question_rise,
		"statement_fall": v.statement_fall,
		"exclamation_boost": v.exclamation_boost,
		"vowel_breathiness": v.vowel_breathiness,
		"voiced_brightness": v.voiced_brightness,
		"segment_edge_fade_ms": v.segment_edge_fade_ms,
		"random_seed": v.random_seed,
		# Vibrato
		"vibrato_rate_hz": v.vibrato_rate_hz,
		"vibrato_depth": v.vibrato_depth,
		"vibrato_delay": v.vibrato_delay,
		# Envelope ADSR
		"envelope_attack": v.envelope_attack,
		"envelope_sustain": v.envelope_sustain,
		"envelope_release": v.envelope_release,
		# Coarticulation
		"coarticulation_strength": v.coarticulation_strength,
		"coarticulation_window": v.coarticulation_window,
		# Formants
		"vowel_a_formants": v.vowel_a_formants.duplicate(),
		"vowel_e_formants": v.vowel_e_formants.duplicate(),
		"vowel_i_formants": v.vowel_i_formants.duplicate(),
		"vowel_o_formants": v.vowel_o_formants.duplicate(),
		"vowel_u_formants": v.vowel_u_formants.duplicate(),
		"fricative_s_formants": v.fricative_s_formants.duplicate(),
		"fricative_f_formants": v.fricative_f_formants.duplicate(),
		"fricative_x_formants": v.fricative_x_formants.duplicate(),
		"stop_p_formants": v.stop_p_formants.duplicate(),
		"stop_t_formants": v.stop_t_formants.duplicate(),
		"stop_k_formants": v.stop_k_formants.duplicate(),
		"nasal_mn_formants": v.nasal_mn_formants.duplicate(),
		# Extended formants
		"extended_f4": v.extended_f4,
		"extended_f5": v.extended_f5,
		"resource_path": v.resource_path,
	}

# Worker thread function - performs synthesis.
func _synthesis_worker(task: SynthesisTask) -> void:
	var seg: PackedFloat32Array = _synthesize_from_dict(task.text, task.pitch_mul, task.voice_data, task.mix_rate, task.pause_space_sec, task.pause_comma_sec, task.pause_period_sec, task.use_extended_formants)

	# Use call_deferred to safely add segment on main thread
	call_deferred("_on_synthesis_complete", seg, task)

# Called on main thread when synthesis completes.
func _on_synthesis_complete(seg: PackedFloat32Array, task: SynthesisTask) -> void:
	# Check if this task was cancelled by stop_all
	if task.generation != _stop_generation:
		return

	if seg.size() > 0:
		# Generate markers for progress tracking (lightweight, no audio generation)
		var markers: Array[TimingMarker] = []
		if voice != null:
			markers = _collect_timing_markers(task.text, task.pitch_mul, voice)
		_setup_progress_tracking(seg, markers)

		_add_segment_safe(seg)

		# Update cache
		var use_cache: bool = enable_cache and (cache_unseeded or task.voice_data.get("random_seed", 0) != 0)
		if use_cache:
			var key := _make_cache_key_from_dict(task.voice_data, task.text, task.pitch_mul)
			_cache_mutex.lock()
			_segment_cache[key] = seg
			_cache_mutex.unlock()

# Generate cache key as int64 hash for better performance.
func _make_cache_key_from_dict(vd: Dictionary, text: String, pitch_mul: float) -> int:
	var pm: int = int(pitch_mul * 1000.0)  # 3 decimal precision
	var seed_val: int = vd.get("random_seed", 0)
	var path_hash: int = hash(vd.get("resource_path", ""))
	# Combine hashes using XOR and bit rotation for good distribution
	var h: int = hash(text)
	h = h ^ (path_hash * 31)
	h = h ^ (mix_rate * 17)
	h = h ^ (pm * 13)
	h = h ^ (seed_val * 7)
	return h

# Synthesize audio for the given text and return the raw samples (for visualization).
func synthesize_to_buffer(text: String, pitch_mul: float = 1.0, override_voice: AnimaleseVoice = null) -> PackedFloat32Array:
	var v: AnimaleseVoice = override_voice if override_voice != null else voice
	if v == null:
		push_warning("ProceduralAnimalese.synthesize_to_buffer(): No voice configured.")
		return PackedFloat32Array()
	if text.strip_edges().is_empty():
		return PackedFloat32Array()
	return _synthesize(text, pitch_mul, v)

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

	var samples: PackedFloat32Array = _synthesize(text, pitch_mul, v)
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
func _get_or_build_segment(v: AnimaleseVoice, text: String, pitch_mul: float) -> PackedFloat32Array:
	var use_cache: bool = enable_cache and (cache_unseeded or v.random_seed != 0)
	if use_cache:
		var key := _make_cache_key(v, text, pitch_mul)
		if _segment_cache.has(key):
			return _segment_cache[key]

	var seg := _synthesize(text, pitch_mul, v)

	if use_cache:
		var key2 := _make_cache_key(v, text, pitch_mul)
		_segment_cache[key2] = seg

	return seg

# Generate cache key as int64 hash for better performance.
func _make_cache_key(v: AnimaleseVoice, text: String, pitch_mul: float) -> int:
	var pm: int = int(pitch_mul * 1000.0)  # 3 decimal precision
	var path_hash: int = hash(v.resource_path) if v.resource_path != "" else v.get_instance_id()
	# Combine hashes using XOR and bit rotation for good distribution
	var h: int = hash(text)
	h = h ^ (path_hash * 31)
	h = h ^ (mix_rate * 17)
	h = h ^ (pm * 13)
	h = h ^ (v.random_seed * 7)
	return h

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
static func _create_language_from_code(code: String) -> LanguageProcessor:
	match code:
		"es":
			return SpanishProcessor.new()
		"en":
			return EnglishProcessor.new()
		"ja":
			return JapaneseProcessor.new()
		_:
			return SpanishProcessor.new()  # Default fallback

# Thread-safe synthesis using dictionary voice data.
func _synthesize_from_dict(text: String, pitch_mul: float, vd: Dictionary, mr: int, p_space: float, p_comma: float, p_period: float, use_f4f5: bool = false) -> PackedFloat32Array:
	var original: String = text
	var lang_code: String = vd.get("language_code", "es")
	var lang: LanguageProcessor = _create_language_from_code(lang_code)
	var s: String = lang.normalize(text)
	var tokens: Array[String] = lang.tokenize(s)
	var out: PackedFloat32Array = PackedFloat32Array()

	var rng := RandomNumberGenerator.new()
	var seed_val: int = vd.get("random_seed", 0)
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.randomize()

	var phrase_pos: int = 0
	var phrase_len: int = 1
	var phrase_is_question: bool = false
	var phrase_is_exclaim: bool = false

	for idx in range(tokens.size()):
		var tok: String = tokens[idx]

		if phrase_pos == 0:
			var info := _scan_phrase(tokens, idx, original)
			phrase_len = info.len
			phrase_is_question = info.is_question
			phrase_is_exclaim = info.is_exclaim

		if tok == " ":
			_append_silence_sr(out, p_space, mr)
			continue
		if tok == "," or tok == ";":
			_append_silence_sr(out, p_comma, mr)
			continue
		if tok == "." or tok == "!" or tok == "?" or tok == ":":
			_append_silence_sr(out, p_period, mr)
			phrase_pos = 0
			continue

		var prosody_mul: float = _prosody_pitch_mul_dict(phrase_pos, phrase_len, phrase_is_question, phrase_is_exclaim, vd)
		var gain_mul: float = 1.0
		if phrase_is_exclaim:
			gain_mul += vd.get("prosody_strength", 0.6) * vd.get("exclamation_boost", 0.25) * 0.25

		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var c: String = tok.substr(0, 1)
			var vv: String = tok.substr(1, 1)

			var ph_c: PhonemeConfig = _phoneme_for_token_dict(c, vd)
			if ph_c != null and (ph_c.kind != &"vowel"):
				var jitter_c: float = 1.0 + rng.randf_range(-vd.get("pitch_jitter", 0.06), vd.get("pitch_jitter", 0.06))
				var f0_c: float = vd.get("pitch_base_hz", 220.0) * pitch_mul * prosody_mul * jitter_c
				var dur_c: float = (vd.get("char_duration_s", 0.055) * 0.55) * vd.get("consonant_duration_multiplier", 0.75)
				out.append_array(_render_phoneme_dict(ph_c, f0_c, dur_c, vd, rng, gain_mul, mr, use_f4f5))

			var ph_v: PhonemeConfig = _phoneme_for_token_dict(vv, vd)
			if ph_v != null:
				var jitter_v: float = 1.0 + rng.randf_range(-vd.get("pitch_jitter", 0.06), vd.get("pitch_jitter", 0.06))
				var f0_v: float = vd.get("pitch_base_hz", 220.0) * pitch_mul * prosody_mul * jitter_v
				var dur_v: float = vd.get("char_duration_s", 0.055) * 1.15
				out.append_array(_render_phoneme_dict(ph_v, f0_v, dur_v, vd, rng, gain_mul, mr, use_f4f5))
		else:
			var ph: PhonemeConfig = _phoneme_for_token_dict(tok, vd)
			if ph == null:
				continue

			var dur: float = vd.get("char_duration_s", 0.055)
			if ph.kind != &"vowel" and ph.kind != &"nasal":
				dur *= vd.get("consonant_duration_multiplier", 0.75)
			if ph.kind == &"vowel":
				dur *= 1.10

			var jitter: float = 1.0 + rng.randf_range(-vd.get("pitch_jitter", 0.06), vd.get("pitch_jitter", 0.06))
			var f0: float = vd.get("pitch_base_hz", 220.0) * pitch_mul * prosody_mul * jitter
			out.append_array(_render_phoneme_dict(ph, f0, dur, vd, rng, gain_mul, mr, use_f4f5))

		phrase_pos += 1
		if phrase_pos >= phrase_len:
			phrase_pos = 0

	_apply_edge_fade(out, int((vd.get("segment_edge_fade_ms", 4.0) / 1000.0) * float(mr)))
	return out

func _append_silence_sr(out: PackedFloat32Array, sec: float, sr: int) -> void:
	var n: int = int(sec * float(sr))
	if n <= 0:
		return
	var start: int = out.size()
	out.resize(start + n)
	for i in range(n):
		out[start + i] = 0.0

func _prosody_pitch_mul_dict(pos: int, length: int, is_question: bool, is_exclaim: bool, vd: Dictionary) -> float:
	if length <= 1:
		return 1.0
	var p: float = float(pos) / float(length - 1)
	var ease: float = p * p * (3.0 - 2.0 * p)
	var s: float = vd.get("prosody_strength", 0.6)
	var mul: float = 1.0
	if is_question:
		mul += s * vd.get("question_rise", 0.35) * pow(ease, 2.2)
	else:
		mul -= s * vd.get("statement_fall", 0.15) * ease * 0.6
	if is_exclaim:
		mul += s * vd.get("exclamation_boost", 0.25) * 0.15
	return maxf(0.5, mul)

func _phoneme_for_token_dict(tok: String, vd: Dictionary) -> PhonemeConfig:
	match tok:
		"a":
			return PhonemeConfig.new(&"vowel", true, 0.03, vd.get("vowel_a_formants", []), true)
		"e":
			return PhonemeConfig.new(&"vowel", true, 0.02, vd.get("vowel_e_formants", []), true)
		"i":
			return PhonemeConfig.new(&"vowel", true, 0.02, vd.get("vowel_i_formants", []), true)
		"o":
			return PhonemeConfig.new(&"vowel", true, 0.02, vd.get("vowel_o_formants", []), true)
		"u":
			return PhonemeConfig.new(&"vowel", true, 0.02, vd.get("vowel_u_formants", []), true)
	match tok:
		"s":
			return PhonemeConfig.new(&"fricative", false, 0.90, vd.get("fricative_s_formants", []), false)
		"f":
			return PhonemeConfig.new(&"fricative", false, 0.75, vd.get("fricative_f_formants", []), false)
		"x":
			return PhonemeConfig.new(&"fricative", false, 0.80, vd.get("fricative_x_formants", []), false)
	match tok:
		"p":
			return PhonemeConfig.new(&"stop", false, 0.85, vd.get("stop_p_formants", []), false)
		"t":
			return PhonemeConfig.new(&"stop", false, 0.85, vd.get("stop_t_formants", []), false)
		"k":
			return PhonemeConfig.new(&"stop", false, 0.85, vd.get("stop_k_formants", []), false)
	match tok:
		"m", "n":
			return PhonemeConfig.new(&"nasal", true, 0.04, vd.get("nasal_mn_formants", []), true)
	match tok:
		"b":
			return PhonemeConfig.new(&"stop", false, 0.85, vd.get("stop_p_formants", []), false)
		"d":
			return PhonemeConfig.new(&"stop", false, 0.85, vd.get("stop_t_formants", []), false)
		"g", "c", "q":
			return PhonemeConfig.new(&"stop", false, 0.85, vd.get("stop_k_formants", []), false)
		"v":
			return PhonemeConfig.new(&"fricative", false, 0.70, vd.get("fricative_f_formants", []), false)
		"z":
			return PhonemeConfig.new(&"fricative", false, 0.85, vd.get("fricative_s_formants", []), false)
		"j":
			return PhonemeConfig.new(&"fricative", false, 0.85, vd.get("fricative_x_formants", []), false)
		"y":
			return PhonemeConfig.new(&"vowel", true, 0.02, vd.get("vowel_i_formants", []), true)
		"l", "r":
			return PhonemeConfig.new(&"vowel", true, 0.02, vd.get("vowel_a_formants", []), true)
	return null

func _render_phoneme_dict(ph: PhonemeConfig, f0: float, dur_sec: float, vd: Dictionary, rng: RandomNumberGenerator, gain_mul: float, mr: int, use_f4f5: bool = false) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur_sec * float(mr)))
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)

	var has_formants: bool = ph.formants.size() >= 3
	var use_extended: bool = use_f4f5 and has_formants

	var r1: BiquadBandpass = BiquadBandpass.new()
	var r2: BiquadBandpass = BiquadBandpass.new()
	var r3: BiquadBandpass = BiquadBandpass.new()
	var r4: BiquadBandpass = BiquadBandpass.new() if use_extended else null
	var r5: BiquadBandpass = BiquadBandpass.new() if use_extended else null

	var f1_hz: float = 0.0
	var f1_q: float = 1.0
	var f1_amp: float = 0.0
	var f2_hz: float = 0.0
	var f2_q: float = 1.0
	var f2_amp: float = 0.0
	var f3_hz: float = 0.0
	var f3_q: float = 1.0
	var f3_amp: float = 0.0
	var f4_hz: float = 0.0
	var f4_q: float = 1.0
	var f4_amp: float = 0.0
	var f5_hz: float = 0.0
	var f5_q: float = 1.0
	var f5_amp: float = 0.0

	if has_formants:
		var F1: Vector3 = ph.formants[0]
		var F2: Vector3 = ph.formants[1]
		var F3: Vector3 = ph.formants[2]

		var scale: float = maxf(0.25, vd.get("vocal_tract_scale", 1.0))
		f1_hz = F1.x * scale
		f2_hz = F2.x * scale
		f3_hz = F3.x * scale

		f1_q = maxf(0.1, F1.y)
		f2_q = maxf(0.1, F2.y)
		f3_q = maxf(0.1, F3.y)

		var family_mul: float = 1.0
		if ph.kind == &"vowel":
			family_mul = vd.get("vowel_formant_gain", 1.0)
		elif ph.kind == &"fricative":
			family_mul = vd.get("fricative_formant_gain", 1.0)
		elif ph.kind == &"stop":
			family_mul = vd.get("stop_formant_gain", 1.0)
		elif ph.kind == &"nasal":
			family_mul = vd.get("nasal_formant_gain", 1.0)

		f1_amp = F1.z * family_mul
		f2_amp = F2.z * family_mul
		f3_amp = F3.z * family_mul

		r1.setup(f1_hz, f1_q, float(mr))
		r2.setup(f2_hz, f2_q, float(mr))
		r3.setup(f3_hz, f3_q, float(mr))

		# Setup F4/F5 extended formants for extra brightness
		if use_extended:
			var F4: Vector3 = vd.get("extended_f4", Vector3(3500, 12.0, 0.12))
			var F5: Vector3 = vd.get("extended_f5", Vector3(4500, 14.0, 0.08))
			f4_hz = F4.x * scale
			f5_hz = F5.x * scale
			f4_q = maxf(0.1, F4.y)
			f5_q = maxf(0.1, F5.y)
			f4_amp = F4.z * family_mul
			f5_amp = F5.z * family_mul
			r4.setup(f4_hz, f4_q, float(mr))
			r5.setup(f5_hz, f5_q, float(mr))

	var cutoff: float = lerpf(1400.0, 9000.0, vd.get("voiced_brightness", 0.55))
	cutoff *= clampf(0.85 + (f0 / 400.0) * 0.35, 0.85, 1.35)
	var lp_a: float = exp(-TAU * cutoff / float(mr))
	var lp_state: float = 0.0

	var phase: float = 0.0
	var base_inc: float = TAU * f0 / float(mr)

	var breath_noise: float = vd.get("breath_noise_level", 0.15)
	var vowel_breath: float = vd.get("vowel_breathiness", 0.10)
	var out_gain: float = vd.get("output_gain", 0.9)

	# Vibrato parameters
	var vib_rate: float = vd.get("vibrato_rate_hz", 0.0)
	var vib_depth: float = vd.get("vibrato_depth", 0.0)
	var vib_delay: float = vd.get("vibrato_delay", 0.3)
	var vib_phase: float = 0.0
	var vib_inc: float = TAU * vib_rate / float(mr)
	var vib_delay_samples: int = int(float(n) * vib_delay)

	# ADSR parameters
	var env_attack: float = vd.get("envelope_attack", 0.10)
	var env_sustain: float = vd.get("envelope_sustain", 0.65)
	var env_release: float = vd.get("envelope_release", 0.20)

	# Whisper mode
	var whisper: float = clampf(vd.get("whisper_amount", 0.0), 0.0, 1.0)

	for i in range(n):
		var env: float = _env_adsr(i, n, env_attack, env_sustain, env_release)
		var x: float = 0.0

		if ph.voiced:
			# Apply vibrato after delay
			var inc: float = base_inc
			if vib_rate > 0.0 and vib_depth > 0.0 and i >= vib_delay_samples:
				vib_phase += vib_inc
				if vib_phase > TAU:
					vib_phase -= TAU
				var vib_mod: float = sin(vib_phase) * vib_depth * 0.1
				inc = base_inc * (1.0 + vib_mod)

			phase += inc
			if phase > TAU:
				phase -= TAU

			# Whisper mode: blend periodic signal with filtered noise
			if whisper < 1.0:
				var saw: float = (phase / TAU) * 2.0 - 1.0
				var sig: float = 0.65 * saw + 0.35 * sin(phase)
				lp_state = (1.0 - lp_a) * sig + lp_a * lp_state
				if whisper > 0.0:
					var whisper_noise: float = rng.randf_range(-1.0, 1.0) * 0.7
					x += lerpf(lp_state, whisper_noise, whisper)
				else:
					x += lp_state
			else:
				var whisper_noise: float = rng.randf_range(-1.0, 1.0) * 0.7
				x += whisper_noise

		var nz: float = rng.randf_range(-1.0, 1.0)
		x += nz * (breath_noise + ph.local_noise + whisper * 0.15)

		if ph.is_vowel and vowel_breath > 0.0:
			var nz2: float = rng.randf_range(-1.0, 1.0)
			x += nz2 * (vowel_breath * 0.25)

		var y: float
		if has_formants:
			y = 0.0
			y += r1.process(x) * f1_amp
			y += r2.process(x) * f2_amp
			y += r3.process(x) * f3_amp
			if use_extended:
				y += r4.process(x) * f4_amp
				y += r5.process(x) * f5_amp
		else:
			y = x

		if ph.kind == &"stop":
			var burst_env: float = 1.0 - float(i) / float(n)
			burst_env = pow(maxf(0.0, burst_env), 3.0)
			y *= burst_env

		buf[i] = y * env * out_gain * gain_mul

	_soft_clip_in_place(buf, 0.95)
	return buf

# Normalize + tokenize text, then render phonemes into a sample buffer.
# If markers_out is provided, timing markers will be appended to it.
func _synthesize(text: String, pitch_mul: float, v: AnimaleseVoice, markers_out: Array[TimingMarker] = []) -> PackedFloat32Array:
	var original: String = text
	var lang: LanguageProcessor = _get_language_for_text(text)
	var s: String = lang.normalize(text)

	var tokens: Array[String] = lang.tokenize(s)
	var out: PackedFloat32Array = PackedFloat32Array()

	var rng := RandomNumberGenerator.new()
	if v.random_seed != 0:
		rng.seed = v.random_seed
	else:
		rng.randomize()

	var phrase_pos: int = 0
	var phrase_len: int = 1
	var phrase_is_question: bool = false
	var phrase_is_exclaim: bool = false

	# Coarticulation: track previous phoneme's formants
	var last_formants: Array[Vector3] = []

	# Progress tracking
	var phoneme_idx: int = 0
	var word_idx: int = 0
	var current_word: String = ""
	var word_start_sample: int = 0
	var collect_markers: bool = markers_out != null

	for idx in range(tokens.size()):
		var tok: String = tokens[idx]

		if phrase_pos == 0:
			var info := _scan_phrase(tokens, idx, original)
			phrase_len = info.len
			phrase_is_question = info.is_question
			phrase_is_exclaim = info.is_exclaim

		# Pausas/puntuación
		if tok == " ":
			# Word boundary - emit word marker if we have accumulated a word
			if collect_markers and current_word.length() > 0:
				markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			_append_silence(out, pause_space_sec)
			word_start_sample = out.size()
			continue
		if tok == "," or tok == ";":
			if collect_markers and current_word.length() > 0:
				markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			_append_silence(out, pause_comma_sec)
			last_formants = []  # Reset coarticulation on pause
			word_start_sample = out.size()
			continue
		if tok == "." or tok == "!" or tok == "?" or tok == ":":
			if collect_markers and current_word.length() > 0:
				markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			_append_silence(out, pause_period_sec)
			phrase_pos = 0
			last_formants = []  # Reset coarticulation on pause
			word_start_sample = out.size()
			continue

		var prosody_mul: float = _prosody_pitch_mul(phrase_pos, phrase_len, phrase_is_question, phrase_is_exclaim, v)
		var gain_mul: float = 1.0
		if phrase_is_exclaim:
			gain_mul += v.prosody_strength * v.exclamation_boost * 0.25

		# Token tipo sílaba "CV" (p.ej. "ka","se","xi"...)
		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var c: String = tok.substr(0, 1)
			var vv: String = tok.substr(1, 1)
			current_word += tok  # Accumulate for word tracking

			# consonante (si existe)
			var ph_c: PhonemeConfig = _phoneme_for_token(c, v)
			if ph_c != null and (ph_c.kind != &"vowel"):
				if collect_markers:
					markers_out.append(TimingMarker.new(MarkerType.PHONEME, c, phoneme_idx, out.size()))
					phoneme_idx += 1
				var jitter_c: float = 1.0 + rng.randf_range(-v.pitch_jitter, v.pitch_jitter)
				var f0_c: float = v.pitch_base_hz * pitch_mul * prosody_mul * jitter_c
				var dur_c: float = (v.char_duration_s * 0.55) * v.consonant_duration_multiplier
				# Look ahead for next formants (the vowel)
				var ph_v_next: PhonemeConfig = _phoneme_for_token(vv, v)
				var next_f: Array[Vector3] = ph_v_next.formants if ph_v_next != null else []
				out.append_array(_render_phoneme(ph_c, f0_c, dur_c, v, rng, gain_mul, last_formants, next_f))
				last_formants = ph_c.formants

			# vocal
			var ph_v: PhonemeConfig = _phoneme_for_token(vv, v)
			if ph_v != null:
				if collect_markers:
					markers_out.append(TimingMarker.new(MarkerType.PHONEME, vv, phoneme_idx, out.size()))
					phoneme_idx += 1
				var jitter_v: float = 1.0 + rng.randf_range(-v.pitch_jitter, v.pitch_jitter)
				var f0_v: float = v.pitch_base_hz * pitch_mul * prosody_mul * jitter_v
				var dur_v: float = v.char_duration_s * 1.15
				# Peek next token for coarticulation
				var next_f: Array[Vector3] = _peek_next_formants(tokens, idx + 1, v)
				out.append_array(_render_phoneme(ph_v, f0_v, dur_v, v, rng, gain_mul, last_formants, next_f))
				last_formants = ph_v.formants

		else:
			# token normal (vocal suelta o consonante final tipo "n","s", etc.)
			var ph: PhonemeConfig = _phoneme_for_token(tok, v)
			if ph == null:
				continue
			current_word += tok  # Accumulate for word tracking

			if collect_markers:
				markers_out.append(TimingMarker.new(MarkerType.PHONEME, tok, phoneme_idx, out.size()))
				phoneme_idx += 1

			var dur: float = v.char_duration_s
			if ph.kind != &"vowel" and ph.kind != &"nasal":
				dur *= v.consonant_duration_multiplier
			if ph.kind == &"vowel":
				dur *= 1.10

			var jitter: float = 1.0 + rng.randf_range(-v.pitch_jitter, v.pitch_jitter)
			var f0: float = v.pitch_base_hz * pitch_mul * prosody_mul * jitter
			var next_f: Array[Vector3] = _peek_next_formants(tokens, idx + 1, v)
			out.append_array(_render_phoneme(ph, f0, dur, v, rng, gain_mul, last_formants, next_f))
			last_formants = ph.formants

		phrase_pos += 1
		if phrase_pos >= phrase_len:
			phrase_pos = 0

	# Emit final word if any remains
	if collect_markers and current_word.length() > 0:
		markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))

	# Add end marker
	if collect_markers:
		markers_out.append(TimingMarker.new(MarkerType.END, "", 0, out.size()))

	_apply_edge_fade(out, int((v.segment_edge_fade_ms / 1000.0) * float(mix_rate)))

	# Release pooled filters back
	_filter_pool.release_all()

	return out

# Collect timing markers without generating audio (lightweight).
func _collect_timing_markers(text: String, pitch_mul: float, v: AnimaleseVoice) -> Array[TimingMarker]:
	var markers: Array[TimingMarker] = []
	var lang: LanguageProcessor = _get_language_for_text(text)
	var s: String = lang.normalize(text)
	var tokens: Array[String] = lang.tokenize(s)

	var sample_offset: int = 0
	var phoneme_idx: int = 0
	var word_idx: int = 0
	var current_word: String = ""
	var word_start_sample: int = 0

	for idx in range(tokens.size()):
		var tok: String = tokens[idx]

		# Pausas/puntuación
		if tok == " ":
			if current_word.length() > 0:
				markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			sample_offset += int(pause_space_sec * float(mix_rate))
			word_start_sample = sample_offset
			continue
		if tok == "," or tok == ";":
			if current_word.length() > 0:
				markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			sample_offset += int(pause_comma_sec * float(mix_rate))
			word_start_sample = sample_offset
			continue
		if tok == "." or tok == "!" or tok == "?" or tok == ":":
			if current_word.length() > 0:
				markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			sample_offset += int(pause_period_sec * float(mix_rate))
			word_start_sample = sample_offset
			continue

		# Token tipo sílaba "CV"
		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var c: String = tok.substr(0, 1)
			var vv: String = tok.substr(1, 1)
			current_word += tok

			# consonante
			var ph_c: PhonemeConfig = _phoneme_for_token(c, v)
			if ph_c != null and (ph_c.kind != &"vowel"):
				markers.append(TimingMarker.new(MarkerType.PHONEME, c, phoneme_idx, sample_offset))
				phoneme_idx += 1
				var dur_c: float = (v.char_duration_s * 0.55) * v.consonant_duration_multiplier
				sample_offset += int(dur_c * float(mix_rate))

			# vocal
			var ph_v: PhonemeConfig = _phoneme_for_token(vv, v)
			if ph_v != null:
				markers.append(TimingMarker.new(MarkerType.PHONEME, vv, phoneme_idx, sample_offset))
				phoneme_idx += 1
				var dur_v: float = v.char_duration_s * 1.15
				sample_offset += int(dur_v * float(mix_rate))
		else:
			# token normal
			var ph: PhonemeConfig = _phoneme_for_token(tok, v)
			if ph == null:
				continue
			current_word += tok

			markers.append(TimingMarker.new(MarkerType.PHONEME, tok, phoneme_idx, sample_offset))
			phoneme_idx += 1

			var dur: float = v.char_duration_s
			if ph.kind != &"vowel" and ph.kind != &"nasal":
				dur *= v.consonant_duration_multiplier
			if ph.kind == &"vowel":
				dur *= 1.10
			sample_offset += int(dur * float(mix_rate))

	# Final word
	if current_word.length() > 0:
		markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))

	# End marker
	markers.append(TimingMarker.new(MarkerType.END, "", 0, sample_offset))

	return markers

# Helper to peek at next token's formants for coarticulation
func _peek_next_formants(tokens: Array[String], start_idx: int, v: AnimaleseVoice) -> Array[Vector3]:
	var lang: LanguageProcessor = _get_language()
	for i in range(start_idx, mini(start_idx + 3, tokens.size())):
		var tok: String = tokens[i]
		if tok == " " or tok == "," or tok == ";" or tok == "." or tok == "!" or tok == "?" or tok == ":":
			continue
		# Check for CV syllable
		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var ph: PhonemeConfig = _phoneme_for_token(tok.substr(0, 1), v)
			if ph != null:
				return ph.formants
		else:
			var ph: PhonemeConfig = _phoneme_for_token(tok, v)
			if ph != null:
				return ph.formants
	return []

func _scan_phrase(tokens: Array[String], start_idx: int, original: String) -> PhraseInfo:
	var info := PhraseInfo.new()

	# si el original contiene ?/! lo consideramos para toda la frase
	var orig_q: bool = (original.find("?") != -1)
	var orig_e: bool = (original.find("!") != -1)

	var count: int = 0
	for i in range(start_idx, tokens.size()):
		var t := tokens[i]
		if t == "?":
			info.is_question = true
		if t == "!":
			info.is_exclaim = true
		if t == "." or t == "!" or t == "?":
			break
		if t != " " and t != "," and t != ";" and t != ":":
			count += 1

	info.len = maxi(1, count)
	info.is_question = info.is_question or orig_q
	info.is_exclaim = info.is_exclaim or orig_e
	return info

func _prosody_pitch_mul(pos: int, length: int, is_question: bool, is_exclaim: bool, v: AnimaleseVoice) -> float:
	if length <= 1:
		return 1.0
	var p: float = float(pos) / float(length - 1)
	var ease: float = p * p * (3.0 - 2.0 * p) # smoothstep

	var s: float = v.prosody_strength
	var mul: float = 1.0

	if is_question:
		mul += s * v.question_rise * pow(ease, 2.2)
	else:
		mul -= s * v.statement_fall * ease * 0.6

	if is_exclaim:
		mul += s * v.exclamation_boost * 0.15

	return maxf(0.5, mul)

# ---------------- Render ----------------
func _render_phoneme(ph: PhonemeConfig, f0: float, dur_sec: float, v: AnimaleseVoice, rng: RandomNumberGenerator, gain_mul: float, prev_formants: Array[Vector3] = [], next_formants: Array[Vector3] = []) -> PackedFloat32Array:
	var n: int = maxi(1, int(dur_sec * float(mix_rate)))
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(n)

	var has_formants: bool = ph.formants.size() >= 3
	var use_f4f5: bool = use_extended_formants and has_formants

	# Use pooled filters to avoid allocations
	var filters: Array[BiquadBandpass]
	if use_f4f5:
		filters = _filter_pool.acquire_five()
	else:
		filters = _filter_pool.acquire_three()
	var r1: BiquadBandpass = filters[0]
	var r2: BiquadBandpass = filters[1]
	var r3: BiquadBandpass = filters[2]
	var r4: BiquadBandpass = filters[3] if use_f4f5 else null
	var r5: BiquadBandpass = filters[4] if use_f4f5 else null

	# F4/F5 parameters (extended formants for brightness)
	var f4_hz: float = 0.0
	var f4_q: float = 1.0
	var f4_amp: float = 0.0
	var f5_hz: float = 0.0
	var f5_q: float = 1.0
	var f5_amp: float = 0.0

	# Coarticulation settings
	var coart_strength: float = v.coarticulation_strength
	var coart_window: float = v.coarticulation_window
	var coart_samples: int = int(float(n) * coart_window)
	var has_prev: bool = prev_formants.size() >= 3 and coart_strength > 0.0
	var has_next: bool = next_formants.size() >= 3 and coart_strength > 0.0

	var f1_hz: float = 0.0
	var f1_q: float = 1.0
	var f1_amp: float = 0.0
	var f2_hz: float = 0.0
	var f2_q: float = 1.0
	var f2_amp: float = 0.0
	var f3_hz: float = 0.0
	var f3_q: float = 1.0
	var f3_amp: float = 0.0

	# Base formant values (will be interpolated if coarticulation is active)
	var base_f1_hz: float = 0.0
	var base_f2_hz: float = 0.0
	var base_f3_hz: float = 0.0

	# Prev/next formant frequencies for coarticulation
	var prev_f1_hz: float = 0.0
	var prev_f2_hz: float = 0.0
	var prev_f3_hz: float = 0.0
	var next_f1_hz: float = 0.0
	var next_f2_hz: float = 0.0
	var next_f3_hz: float = 0.0

	if has_formants:
		var F1: Vector3 = ph.formants[0]
		var F2: Vector3 = ph.formants[1]
		var F3: Vector3 = ph.formants[2]

		var scale: float = maxf(0.25, v.vocal_tract_scale)
		base_f1_hz = F1.x * scale
		base_f2_hz = F2.x * scale
		base_f3_hz = F3.x * scale
		f1_hz = base_f1_hz
		f2_hz = base_f2_hz
		f3_hz = base_f3_hz

		f1_q = maxf(0.1, F1.y)
		f2_q = maxf(0.1, F2.y)
		f3_q = maxf(0.1, F3.y)

		var family_mul: float = 1.0
		if ph.kind == &"vowel":
			family_mul = v.vowel_formant_gain
		elif ph.kind == &"fricative":
			family_mul = v.fricative_formant_gain
		elif ph.kind == &"stop":
			family_mul = v.stop_formant_gain
		elif ph.kind == &"nasal":
			family_mul = v.nasal_formant_gain

		f1_amp = F1.z * family_mul
		f2_amp = F2.z * family_mul
		f3_amp = F3.z * family_mul

		# Get prev/next formant frequencies for coarticulation
		if has_prev:
			prev_f1_hz = prev_formants[0].x * scale
			prev_f2_hz = prev_formants[1].x * scale
			prev_f3_hz = prev_formants[2].x * scale
		else:
			prev_f1_hz = base_f1_hz
			prev_f2_hz = base_f2_hz
			prev_f3_hz = base_f3_hz

		if has_next:
			next_f1_hz = next_formants[0].x * scale
			next_f2_hz = next_formants[1].x * scale
			next_f3_hz = next_formants[2].x * scale
		else:
			next_f1_hz = base_f1_hz
			next_f2_hz = base_f2_hz
			next_f3_hz = base_f3_hz

		r1.setup(f1_hz, f1_q, float(mix_rate))
		r2.setup(f2_hz, f2_q, float(mix_rate))
		r3.setup(f3_hz, f3_q, float(mix_rate))

		# Setup F4/F5 extended formants for extra brightness
		if use_f4f5:
			var F4: Vector3 = v.extended_f4
			var F5: Vector3 = v.extended_f5
			f4_hz = F4.x * scale
			f5_hz = F5.x * scale
			f4_q = maxf(0.1, F4.y)
			f5_q = maxf(0.1, F5.y)
			f4_amp = F4.z * family_mul
			f5_amp = F5.z * family_mul
			r4.setup(f4_hz, f4_q, float(mix_rate))
			r5.setup(f5_hz, f5_q, float(mix_rate))

	# Coarticulation: update interval for filter coefficients (every N samples)
	var coart_update_interval: int = 32

	# Low-pass dinámico para suavizar el voiced
	var cutoff: float = lerpf(1400.0, 9000.0, v.voiced_brightness)
	cutoff *= clampf(0.85 + (f0 / 400.0) * 0.35, 0.85, 1.35)
	var lp_a: float = exp(-TAU * cutoff / float(mix_rate))
	var lp_state: float = 0.0

	var phase: float = 0.0
	var base_inc: float = TAU * f0 / float(mix_rate)

	# Vibrato parameters
	var vib_rate: float = v.vibrato_rate_hz
	var vib_depth: float = v.vibrato_depth
	var vib_delay: float = v.vibrato_delay
	var vib_phase: float = 0.0
	var vib_inc: float = TAU * vib_rate / float(mix_rate)
	var vib_delay_samples: int = int(float(n) * vib_delay)

	# ADSR parameters from voice
	var env_attack: float = v.envelope_attack
	var env_sustain: float = v.envelope_sustain
	var env_release: float = v.envelope_release

	# Whisper mode: blend voiced with noise
	var whisper: float = clampf(v.whisper_amount, 0.0, 1.0)

	for i in range(n):
		var env: float = _env_adsr(i, n, env_attack, env_sustain, env_release)

		# Coarticulation: interpolate formant frequencies at phoneme edges
		if has_formants and coart_strength > 0.0 and (i % coart_update_interval) == 0:
			var interp_f1: float = base_f1_hz
			var interp_f2: float = base_f2_hz
			var interp_f3: float = base_f3_hz

			if i < coart_samples and has_prev:
				# Interpolate from previous phoneme's formants
				var t: float = float(i) / float(coart_samples)
				t = t * t * (3.0 - 2.0 * t)  # smoothstep
				interp_f1 = lerpf(prev_f1_hz, base_f1_hz, t) * coart_strength + base_f1_hz * (1.0 - coart_strength)
				interp_f2 = lerpf(prev_f2_hz, base_f2_hz, t) * coart_strength + base_f2_hz * (1.0 - coart_strength)
				interp_f3 = lerpf(prev_f3_hz, base_f3_hz, t) * coart_strength + base_f3_hz * (1.0 - coart_strength)
			elif i >= (n - coart_samples) and has_next:
				# Interpolate towards next phoneme's formants
				var t: float = float(i - (n - coart_samples)) / float(coart_samples)
				t = t * t * (3.0 - 2.0 * t)  # smoothstep
				interp_f1 = lerpf(base_f1_hz, next_f1_hz, t) * coart_strength + base_f1_hz * (1.0 - coart_strength)
				interp_f2 = lerpf(base_f2_hz, next_f2_hz, t) * coart_strength + base_f2_hz * (1.0 - coart_strength)
				interp_f3 = lerpf(base_f3_hz, next_f3_hz, t) * coart_strength + base_f3_hz * (1.0 - coart_strength)

			# Update filter coefficients if frequencies changed significantly
			if absf(interp_f1 - f1_hz) > 5.0 or absf(interp_f2 - f2_hz) > 5.0 or absf(interp_f3 - f3_hz) > 5.0:
				f1_hz = interp_f1
				f2_hz = interp_f2
				f3_hz = interp_f3
				r1.setup(f1_hz, f1_q, float(mix_rate))
				r2.setup(f2_hz, f2_q, float(mix_rate))
				r3.setup(f3_hz, f3_q, float(mix_rate))

		var x: float = 0.0

		if ph.voiced:
			# Apply vibrato after delay
			var inc: float = base_inc
			if vib_rate > 0.0 and vib_depth > 0.0 and i >= vib_delay_samples:
				vib_phase += vib_inc
				if vib_phase > TAU:
					vib_phase -= TAU
				var vib_mod: float = sin(vib_phase) * vib_depth * 0.1  # 0.1 = max 10% pitch variation
				inc = base_inc * (1.0 + vib_mod)

			phase += inc
			if phase > TAU:
				phase -= TAU

			# Whisper mode: blend periodic signal with filtered noise
			if whisper < 1.0:
				var saw: float = (phase / TAU) * 2.0 - 1.0
				var sig: float = 0.65 * saw + 0.35 * sin(phase)
				lp_state = (1.0 - lp_a) * sig + lp_a * lp_state
				if whisper > 0.0:
					# Blend voiced with whisper noise
					var whisper_noise: float = rng.randf_range(-1.0, 1.0) * 0.7
					x += lerpf(lp_state, whisper_noise, whisper)
				else:
					x += lp_state
			else:
				# Full whisper: only filtered noise (no periodic component)
				var whisper_noise: float = rng.randf_range(-1.0, 1.0) * 0.7
				x += whisper_noise

		var nz: float = rng.randf_range(-1.0, 1.0)
		x += nz * (v.breath_noise_level + ph.local_noise + whisper * 0.15)

		if ph.is_vowel and v.vowel_breathiness > 0.0:
			var nz2: float = rng.randf_range(-1.0, 1.0)
			x += nz2 * (v.vowel_breathiness * 0.25)

		var y: float
		if has_formants:
			y = 0.0
			y += r1.process(x) * f1_amp
			y += r2.process(x) * f2_amp
			y += r3.process(x) * f3_amp
			if use_f4f5:
				y += r4.process(x) * f4_amp
				y += r5.process(x) * f5_amp
		else:
			y = x

		if ph.kind == &"stop":
			var burst_env: float = 1.0 - float(i) / float(n)
			burst_env = pow(maxf(0.0, burst_env), 3.0)
			y *= burst_env

		buf[i] = y * env * v.output_gain * gain_mul

	_soft_clip_in_place(buf, 0.95)
	return buf

# ---------------- Phoneme mapping ----------------
func _phoneme_for_token(tok: String, v: AnimaleseVoice) -> PhonemeConfig:
	match tok:
		"a":
			return PhonemeConfig.new(&"vowel", true, 0.03, v.vowel_a_formants, true)
		"e":
			return PhonemeConfig.new(&"vowel", true, 0.02, v.vowel_e_formants, true)
		"i":
			return PhonemeConfig.new(&"vowel", true, 0.02, v.vowel_i_formants, true)
		"o":
			return PhonemeConfig.new(&"vowel", true, 0.02, v.vowel_o_formants, true)
		"u":
			return PhonemeConfig.new(&"vowel", true, 0.02, v.vowel_u_formants, true)

	match tok:
		"s":
			return PhonemeConfig.new(&"fricative", false, 0.90, v.fricative_s_formants, false)
		"f":
			return PhonemeConfig.new(&"fricative", false, 0.75, v.fricative_f_formants, false)
		"x": # (j/ch)
			return PhonemeConfig.new(&"fricative", false, 0.80, v.fricative_x_formants, false)

	match tok:
		"p":
			return PhonemeConfig.new(&"stop", false, 0.85, v.stop_p_formants, false)
		"t":
			return PhonemeConfig.new(&"stop", false, 0.85, v.stop_t_formants, false)
		"k":
			return PhonemeConfig.new(&"stop", false, 0.85, v.stop_k_formants, false)

	match tok:
		"m", "n":
			return PhonemeConfig.new(&"nasal", true, 0.04, v.nasal_mn_formants, true)

	match tok:
		"b":
			return PhonemeConfig.new(&"stop", false, 0.85, v.stop_p_formants, false)
		"d":
			return PhonemeConfig.new(&"stop", false, 0.85, v.stop_t_formants, false)
		"g", "c", "q":
			return PhonemeConfig.new(&"stop", false, 0.85, v.stop_k_formants, false)
		"v":
			return PhonemeConfig.new(&"fricative", false, 0.70, v.fricative_f_formants, false)
		"z":
			return PhonemeConfig.new(&"fricative", false, 0.85, v.fricative_s_formants, false)
		"j":
			return PhonemeConfig.new(&"fricative", false, 0.85, v.fricative_x_formants, false)
		"y":
			return PhonemeConfig.new(&"vowel", true, 0.02, v.vowel_i_formants, true)
		"l", "r":
			return PhonemeConfig.new(&"vowel", true, 0.02, v.vowel_a_formants, true)

	return null

# ---------------- Tokenization (ES syllable-ish CV) ----------------
# ES-oriented CV tokenization with simple punctuation handling.
func _tokenize_es_cv(s: String) -> Array[String]:
	var tokens: Array[String] = []
	var i: int = 0
	var n: int = s.length()

	while i < n:
		var ch: String = s.substr(i, 1)

		# separadores / puntuación
		if ch == " " or ch == "\t" or ch == "\n":
			tokens.append(" ")
			i += 1
			continue
		if ch == "," or ch == ";" or ch == ":" or ch == "." or ch == "!" or ch == "?":
			tokens.append(ch)
			i += 1
			continue

		# vocal suelta
		if _is_vowel(ch):
			tokens.append(ch)
			i += 1
			# consonante final (n/m/s) al final de sílaba
			if i < n:
				var c2 := s.substr(i, 1)
				if (c2 == "n" or c2 == "m" or c2 == "s") and (i + 1 >= n or not _is_vowel(s.substr(i + 1, 1))):
					tokens.append(c2)
					i += 1
			continue

		# consonante + vocal => sílaba CV
		if i + 1 < n and _is_vowel(s.substr(i + 1, 1)):
			var vch := s.substr(i + 1, 1)
			tokens.append(ch + vch)
			i += 2
			# consonante final (n/m/s)
			if i < n:
				var c3 := s.substr(i, 1)
				if (c3 == "n" or c3 == "m" or c3 == "s") and (i + 1 >= n or not _is_vowel(s.substr(i + 1, 1))):
					tokens.append(c3)
					i += 1
			continue

		# fallback consonante suelta
		tokens.append(ch)
		i += 1

	return tokens

func _is_vowel(ch: String) -> bool:
	return ch == "a" or ch == "e" or ch == "i" or ch == "o" or ch == "u"

# ---------------- Utilities ----------------
func _env_adsr(i: int, n: int, a_frac: float, s_level: float, r_frac: float) -> float:
	var a: int = maxi(1, int(float(n) * a_frac))
	var r: int = maxi(1, int(float(n) * r_frac))
	var s_start: int = a
	var s_end: int = maxi(s_start, n - r)

	if i < s_start:
		return float(i) / float(a)
	if i < s_end:
		return s_level

	var ri: int = i - s_end
	return s_level * (1.0 - float(ri) / float(maxi(1, n - s_end)))

func _soft_clip_in_place(buf: PackedFloat32Array, drive: float) -> void:
	var denom: float = maxf(0.001, drive)
	for i in range(buf.size()):
		var x: float = buf[i] / denom
		buf[i] = (x * (27.0 + x * x)) / (27.0 + 9.0 * x * x) * drive

func _append_silence(out: PackedFloat32Array, sec: float) -> void:
	var n: int = int(sec * float(mix_rate))
	if n <= 0:
		return
	var start: int = out.size()
	out.resize(start + n)
	for i in range(n):
		out[start + i] = 0.0

func _apply_edge_fade(buf: PackedFloat32Array, fade_samples: int) -> void:
	if fade_samples <= 0:
		return
	var n: int = buf.size()
	if n <= 1:
		return
	var fs: int = mini(fade_samples, n / 2)
	if fs <= 0:
		return

	for i in range(fs):
		var t: float = float(i) / float(fs)
		buf[i] *= t

	for i in range(fs):
		var t2: float = float(i) / float(fs)
		buf[n - 1 - i] *= (1.0 - t2)

# Parse markup text and return array of segments with modifiers.
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
			if marker_type == MarkerType.PHONEME:
				call_deferred("emit_signal", "phoneme_started", marker["value"], marker["index"])
				# Emit viseme signal for lip-sync
				var viseme: Viseme = _phoneme_to_viseme(marker["value"])
				call_deferred("emit_signal", "viseme_changed", viseme, 1.0)
			elif marker_type == MarkerType.WORD:
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
		if marker["type"] == MarkerType.PHONEME:
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
