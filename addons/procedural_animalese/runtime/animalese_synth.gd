## Pure DSP + tokenization kernel for ProceduralAnimalese.
##
## Every method here is static and reads only from its arguments — the kernel
## touches no instance state — so it is safe to call from a worker thread.
## The main ProceduralAnimalese node serializes its AnimaleseVoice into a
## Dictionary with serialize_voice() and passes it into synthesize().
extends RefCounted
class_name AnimaleseSynth

# ---------------- Types ----------------

## Formant band-pass filter (classic biquad, constant-skirt band-pass).
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

## Configuration for one phoneme returned by _phoneme_for_token().
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


## Result of _scan_phrase(): length in phonemes + terminal punctuation flags.
class PhraseInfo:
	var len: int = 1
	var is_question: bool = false
	var is_exclaim: bool = false


# Marker types for progress signals.
enum MarkerType { PHONEME, WORD, END }

## Timing marker for one phoneme / word boundary / end-of-speech.
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


# ---------------- Public API ----------------

## Serialize an AnimaleseVoice to a thread-safe Dictionary.
static func serialize_voice(v: AnimaleseVoice) -> Dictionary:
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

# Worker thread function - performs synthesis and collects timing markers.

## Compute a stable int64 cache key from serialized voice + text + rate.
static func make_cache_key(vd: Dictionary, text: String, pitch_mul: float, mix_rate: int) -> int:
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

## Main synthesis kernel. Text + serialized voice → PCM samples.
## If markers_out is non-empty on entry it is still filled; pass a fresh
## Array[TimingMarker] to receive per-phoneme / per-word / end markers.
static func synthesize(text: String, pitch_mul: float, vd: Dictionary, mr: int, p_space: float, p_comma: float, p_period: float, use_f4f5: bool = false, markers_out: Array[TimingMarker] = []) -> PackedFloat32Array:
	var original: String = text
	var lang_code: String = vd.get("language_code", "es")
	var lang: LanguageProcessor = LanguageDetector.create_processor_for_code(lang_code)
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

	# Coarticulation: track previous phoneme's formants across the phrase.
	var last_formants: Array[Vector3] = []

	# Progress tracking state.
	var phoneme_idx: int = 0
	var word_idx: int = 0
	var current_word: String = ""
	var word_start_sample: int = 0

	for idx in range(tokens.size()):
		var tok: String = tokens[idx]

		if phrase_pos == 0:
			var info := _scan_phrase(tokens, idx, original)
			phrase_len = info.len
			phrase_is_question = info.is_question
			phrase_is_exclaim = info.is_exclaim

		if tok == " ":
			if current_word.length() > 0:
				markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			_append_silence(out, p_space, mr)
			word_start_sample = out.size()
			continue
		if tok == "," or tok == ";":
			if current_word.length() > 0:
				markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			_append_silence(out, p_comma, mr)
			last_formants = []
			word_start_sample = out.size()
			continue
		if tok == "." or tok == "!" or tok == "?" or tok == ":":
			if current_word.length() > 0:
				markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			_append_silence(out, p_period, mr)
			phrase_pos = 0
			last_formants = []
			word_start_sample = out.size()
			continue

		var prosody_mul: float = _prosody_pitch_mul(phrase_pos, phrase_len, phrase_is_question, phrase_is_exclaim, vd)
		var gain_mul: float = 1.0
		if phrase_is_exclaim:
			gain_mul += vd.get("prosody_strength", 0.6) * vd.get("exclamation_boost", 0.25) * 0.25

		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var c: String = tok.substr(0, 1)
			var vv: String = tok.substr(1, 1)
			current_word += tok

			var ph_c: PhonemeConfig = _phoneme_for_token(c, vd)
			if ph_c != null and (ph_c.kind != &"vowel"):
				markers_out.append(TimingMarker.new(MarkerType.PHONEME, c, phoneme_idx, out.size()))
				phoneme_idx += 1
				var jitter_c: float = 1.0 + rng.randf_range(-vd.get("pitch_jitter", 0.06), vd.get("pitch_jitter", 0.06))
				var f0_c: float = vd.get("pitch_base_hz", 220.0) * pitch_mul * prosody_mul * jitter_c
				var dur_c: float = (vd.get("char_duration_s", 0.055) * 0.55) * vd.get("consonant_duration_multiplier", 0.75)
				# Coarticulate the consonant into the coming vowel.
				var ph_v_next: PhonemeConfig = _phoneme_for_token(vv, vd)
				var next_f: Array[Vector3] = ph_v_next.formants if ph_v_next != null else []
				out.append_array(_render_phoneme(ph_c, f0_c, dur_c, vd, rng, gain_mul, mr, use_f4f5, last_formants, next_f))
				last_formants = ph_c.formants

			var ph_v: PhonemeConfig = _phoneme_for_token(vv, vd)
			if ph_v != null:
				markers_out.append(TimingMarker.new(MarkerType.PHONEME, vv, phoneme_idx, out.size()))
				phoneme_idx += 1
				var jitter_v: float = 1.0 + rng.randf_range(-vd.get("pitch_jitter", 0.06), vd.get("pitch_jitter", 0.06))
				var f0_v: float = vd.get("pitch_base_hz", 220.0) * pitch_mul * prosody_mul * jitter_v
				var dur_v: float = vd.get("char_duration_s", 0.055) * 1.15
				var next_f: Array[Vector3] = _peek_next_formants(tokens, idx + 1, vd, lang)
				out.append_array(_render_phoneme(ph_v, f0_v, dur_v, vd, rng, gain_mul, mr, use_f4f5, last_formants, next_f))
				last_formants = ph_v.formants
		else:
			var ph: PhonemeConfig = _phoneme_for_token(tok, vd)
			if ph == null:
				continue
			current_word += tok

			markers_out.append(TimingMarker.new(MarkerType.PHONEME, tok, phoneme_idx, out.size()))
			phoneme_idx += 1

			var dur: float = vd.get("char_duration_s", 0.055)
			if ph.kind != &"vowel" and ph.kind != &"nasal":
				dur *= vd.get("consonant_duration_multiplier", 0.75)
			if ph.kind == &"vowel":
				dur *= 1.10

			var jitter: float = 1.0 + rng.randf_range(-vd.get("pitch_jitter", 0.06), vd.get("pitch_jitter", 0.06))
			var f0: float = vd.get("pitch_base_hz", 220.0) * pitch_mul * prosody_mul * jitter
			var next_f: Array[Vector3] = _peek_next_formants(tokens, idx + 1, vd, lang)
			out.append_array(_render_phoneme(ph, f0, dur, vd, rng, gain_mul, mr, use_f4f5, last_formants, next_f))
			last_formants = ph.formants

		phrase_pos += 1
		if phrase_pos >= phrase_len:
			phrase_pos = 0

	if current_word.length() > 0:
		markers_out.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
	markers_out.append(TimingMarker.new(MarkerType.END, "", 0, out.size()))

	_apply_edge_fade(out, int((vd.get("segment_edge_fade_ms", 4.0) / 1000.0) * float(mr)))
	return out

## Dry marker collection — same tokenization + duration math without DSP.
## Used on cache hits to rebuild markers for a cached sample buffer.
static func collect_timing_markers(text: String, vd: Dictionary, mr: int, p_space: float, p_comma: float, p_period: float) -> Array[TimingMarker]:
	var markers: Array[TimingMarker] = []
	var lang_code: String = vd.get("language_code", "es")
	var lang: LanguageProcessor = LanguageDetector.create_processor_for_code(lang_code)
	var s: String = lang.normalize(text)
	var tokens: Array[String] = lang.tokenize(s)

	var sample_offset: int = 0
	var phoneme_idx: int = 0
	var word_idx: int = 0
	var current_word: String = ""
	var word_start_sample: int = 0

	for idx in range(tokens.size()):
		var tok: String = tokens[idx]

		if tok == " ":
			if current_word.length() > 0:
				markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			sample_offset += int(p_space * float(mr))
			word_start_sample = sample_offset
			continue
		if tok == "," or tok == ";":
			if current_word.length() > 0:
				markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			sample_offset += int(p_comma * float(mr))
			word_start_sample = sample_offset
			continue
		if tok == "." or tok == "!" or tok == "?" or tok == ":":
			if current_word.length() > 0:
				markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
				word_idx += 1
				current_word = ""
			sample_offset += int(p_period * float(mr))
			word_start_sample = sample_offset
			continue

		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var c: String = tok.substr(0, 1)
			var vv: String = tok.substr(1, 1)
			current_word += tok

			var ph_c: PhonemeConfig = _phoneme_for_token(c, vd)
			if ph_c != null and (ph_c.kind != &"vowel"):
				markers.append(TimingMarker.new(MarkerType.PHONEME, c, phoneme_idx, sample_offset))
				phoneme_idx += 1
				var dur_c: float = (vd.get("char_duration_s", 0.055) * 0.55) * vd.get("consonant_duration_multiplier", 0.75)
				sample_offset += int(dur_c * float(mr))

			var ph_v: PhonemeConfig = _phoneme_for_token(vv, vd)
			if ph_v != null:
				markers.append(TimingMarker.new(MarkerType.PHONEME, vv, phoneme_idx, sample_offset))
				phoneme_idx += 1
				var dur_v: float = vd.get("char_duration_s", 0.055) * 1.15
				sample_offset += int(dur_v * float(mr))
		else:
			var ph: PhonemeConfig = _phoneme_for_token(tok, vd)
			if ph == null:
				continue
			current_word += tok

			markers.append(TimingMarker.new(MarkerType.PHONEME, tok, phoneme_idx, sample_offset))
			phoneme_idx += 1

			var dur: float = vd.get("char_duration_s", 0.055)
			if ph.kind != &"vowel" and ph.kind != &"nasal":
				dur *= vd.get("consonant_duration_multiplier", 0.75)
			if ph.kind == &"vowel":
				dur *= 1.10
			sample_offset += int(dur * float(mr))

	if current_word.length() > 0:
		markers.append(TimingMarker.new(MarkerType.WORD, current_word, word_idx, word_start_sample))
	markers.append(TimingMarker.new(MarkerType.END, "", 0, sample_offset))

	return markers

# ---------------- Private helpers (all static) ----------------

static func _append_silence(out: PackedFloat32Array, sec: float, sr: int) -> void:
	var n: int = int(sec * float(sr))
	if n <= 0:
		return
	var start: int = out.size()
	out.resize(start + n)
	for i in range(n):
		out[start + i] = 0.0

static func _prosody_pitch_mul(pos: int, length: int, is_question: bool, is_exclaim: bool, vd: Dictionary) -> float:
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

static func _phoneme_for_token(tok: String, vd: Dictionary) -> PhonemeConfig:
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

# Coarticulation helper: return the formants of the next non-punctuation phoneme.

static func _peek_next_formants(tokens: Array[String], start_idx: int, vd: Dictionary, lang: LanguageProcessor) -> Array[Vector3]:
	for i in range(start_idx, mini(start_idx + 3, tokens.size())):
		var tok: String = tokens[i]
		if tok == " " or tok == "," or tok == ";" or tok == "." or tok == "!" or tok == "?" or tok == ":":
			continue
		if tok.length() == 2 and lang.is_vowel(tok.substr(1, 1)):
			var ph: PhonemeConfig = _phoneme_for_token(tok.substr(0, 1), vd)
			if ph != null:
				return ph.formants
		else:
			var ph: PhonemeConfig = _phoneme_for_token(tok, vd)
			if ph != null:
				return ph.formants
	return []

static func _render_phoneme(ph: PhonemeConfig, f0: float, dur_sec: float, vd: Dictionary, rng: RandomNumberGenerator, gain_mul: float, mr: int, use_f4f5: bool = false, prev_formants: Array[Vector3] = [], next_formants: Array[Vector3] = []) -> PackedFloat32Array:
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

	var coart_strength: float = vd.get("coarticulation_strength", 0.0)
	var coart_window: float = vd.get("coarticulation_window", 0.15)
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
	var f4_hz: float = 0.0
	var f4_q: float = 1.0
	var f4_amp: float = 0.0
	var f5_hz: float = 0.0
	var f5_q: float = 1.0
	var f5_amp: float = 0.0

	var base_f1_hz: float = 0.0
	var base_f2_hz: float = 0.0
	var base_f3_hz: float = 0.0
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

		var scale: float = maxf(0.25, vd.get("vocal_tract_scale", 1.0))
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

		r1.setup(f1_hz, f1_q, float(mr))
		r2.setup(f2_hz, f2_q, float(mr))
		r3.setup(f3_hz, f3_q, float(mr))

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

	var coart_update_interval: int = 32

	var cutoff: float = lerpf(1400.0, 9000.0, vd.get("voiced_brightness", 0.55))
	cutoff *= clampf(0.85 + (f0 / 400.0) * 0.35, 0.85, 1.35)
	var lp_a: float = exp(-TAU * cutoff / float(mr))
	var lp_state: float = 0.0

	var phase: float = 0.0
	var base_inc: float = TAU * f0 / float(mr)

	var breath_noise: float = vd.get("breath_noise_level", 0.15)
	var vowel_breath: float = vd.get("vowel_breathiness", 0.10)
	var out_gain: float = vd.get("output_gain", 0.9)

	var vib_rate: float = vd.get("vibrato_rate_hz", 0.0)
	var vib_depth: float = vd.get("vibrato_depth", 0.0)
	var vib_delay: float = vd.get("vibrato_delay", 0.3)
	var vib_phase: float = 0.0
	var vib_inc: float = TAU * vib_rate / float(mr)
	var vib_delay_samples: int = int(float(n) * vib_delay)

	var env_attack: float = vd.get("envelope_attack", 0.10)
	var env_sustain: float = vd.get("envelope_sustain", 0.65)
	var env_release: float = vd.get("envelope_release", 0.20)

	var whisper: float = clampf(vd.get("whisper_amount", 0.0), 0.0, 1.0)

	for i in range(n):
		var env: float = _env_adsr(i, n, env_attack, env_sustain, env_release)

		if has_formants and coart_strength > 0.0 and (i % coart_update_interval) == 0:
			var interp_f1: float = base_f1_hz
			var interp_f2: float = base_f2_hz
			var interp_f3: float = base_f3_hz

			if i < coart_samples and has_prev:
				var t: float = float(i) / float(coart_samples)
				t = t * t * (3.0 - 2.0 * t)
				interp_f1 = lerpf(prev_f1_hz, base_f1_hz, t) * coart_strength + base_f1_hz * (1.0 - coart_strength)
				interp_f2 = lerpf(prev_f2_hz, base_f2_hz, t) * coart_strength + base_f2_hz * (1.0 - coart_strength)
				interp_f3 = lerpf(prev_f3_hz, base_f3_hz, t) * coart_strength + base_f3_hz * (1.0 - coart_strength)
			elif i >= (n - coart_samples) and has_next:
				var t: float = float(i - (n - coart_samples)) / float(coart_samples)
				t = t * t * (3.0 - 2.0 * t)
				interp_f1 = lerpf(base_f1_hz, next_f1_hz, t) * coart_strength + base_f1_hz * (1.0 - coart_strength)
				interp_f2 = lerpf(base_f2_hz, next_f2_hz, t) * coart_strength + base_f2_hz * (1.0 - coart_strength)
				interp_f3 = lerpf(base_f3_hz, next_f3_hz, t) * coart_strength + base_f3_hz * (1.0 - coart_strength)

			if absf(interp_f1 - f1_hz) > 5.0 or absf(interp_f2 - f2_hz) > 5.0 or absf(interp_f3 - f3_hz) > 5.0:
				f1_hz = interp_f1
				f2_hz = interp_f2
				f3_hz = interp_f3
				r1.setup(f1_hz, f1_q, float(mr))
				r2.setup(f2_hz, f2_q, float(mr))
				r3.setup(f3_hz, f3_q, float(mr))

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

# Dry marker collection with no DSP — used to regenerate progress markers on a
# cache hit without re-synthesizing the audio.

static func _scan_phrase(tokens: Array[String], start_idx: int, original: String) -> PhraseInfo:
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

static func _env_adsr(i: int, n: int, a_frac: float, s_level: float, r_frac: float) -> float:
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

static func _soft_clip_in_place(buf: PackedFloat32Array, drive: float) -> void:
	var denom: float = maxf(0.001, drive)
	for i in range(buf.size()):
		var x: float = buf[i] / denom
		buf[i] = (x * (27.0 + x * x)) / (27.0 + 9.0 * x * x) * drive

static func _apply_edge_fade(buf: PackedFloat32Array, fade_samples: int) -> void:
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
