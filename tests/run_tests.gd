extends SceneTree
## Golden-file regression tests for the ProceduralAnimalese synthesis kernel.
##
## Each case synthesizes a deterministic phrase against a seeded voice and
## records the SHA-256 of the raw PCM bytes plus the sample count. Runs
## compare against tests/golden.json and fail on any mismatch; pass
## `-- --generate` to (re)write the fixture instead.
##
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --generate

const GOLDEN_PATH := "res://tests/golden.json"

var _generate := false
var _pass := 0
var _fail := 0
var _generated: Dictionary = {}

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--generate":
			_generate = true

	var golden: Dictionary = _load_golden()
	_run_all(golden)

	if _generate:
		_write_golden(_generated)
		print("[generate] wrote %d cases to %s" % [_generated.size(), GOLDEN_PATH])
		quit(0)
	else:
		print("---")
		print("PASSED: %d  FAILED: %d" % [_pass, _fail])
		quit(1 if _fail > 0 else 0)

# ---------------- Harness ----------------

func _load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		return {}
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _write_golden(data: Dictionary) -> void:
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	assert(f != null, "cannot open %s for writing" % GOLDEN_PATH)
	# Sort keys for a stable, diff-friendly fixture.
	var sorted: Dictionary = {}
	var keys: Array = data.keys()
	keys.sort()
	for k in keys:
		sorted[k] = data[k]
	f.store_string(JSON.stringify(sorted, "\t"))
	f.close()

func _make_pa() -> ProceduralAnimalese:
	var pa := ProceduralAnimalese.new()
	pa.run_in_editor = false
	pa.threaded_synthesis = false
	pa.enable_cache = false
	pa.ensure_audio_bus = false
	return pa

func _hash_buf(buf: PackedFloat32Array) -> String:
	if buf.size() == 0:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(buf.to_byte_array())
	return ctx.finish().hex_encode()

# Compare `computed` (Variant) against golden[name] and record pass/fail, or
# capture it in _generated when regenerating the fixture.
func _record(golden: Dictionary, name: String, computed: Variant) -> void:
	if _generate:
		_generated[name] = computed
		print("[gen] %s" % name)
		return
	if not golden.has(name):
		print("[FAIL] %s: missing from golden.json (run with -- --generate to add)" % name)
		_fail += 1
		return
	# JSON parse gives us Dictionaries with the same fields but comparison is by value.
	if _variants_equal(golden[name], computed):
		print("[pass] %s" % name)
		_pass += 1
	else:
		print("[FAIL] %s\n        expected %s\n        got      %s" % [name, str(golden[name]), str(computed)])
		_fail += 1

# Small helper so int/float coercion from JSON doesn't spuriously fail equality.
func _variants_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for k in a.keys():
			if not b.has(k):
				return false
			if not _variants_equal(a[k], b[k]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _variants_equal(a[i], b[i]):
				return false
		return true
	# Coerce numerics so 42 (int from re-run) equals 42.0 (float from JSON parse) etc.
	if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
		return float(a) == float(b)
	return a == b

func _load_seeded_voice(name: String, seed_val: int) -> AnimaleseVoice:
	var v: AnimaleseVoice = load("res://addons/procedural_animalese/presets/%s.tres" % name)
	assert(v != null, "preset failed to load: %s" % name)
	v = v.duplicate() as AnimaleseVoice
	v.random_seed = seed_val
	return v

# ---------------- Cases ----------------

const SPANISH_PHRASE := "Hola mundo, ¿cómo estás? Me llamo Animalese."
const PRESETS: Array[String] = [
	"voice_default", "voice_masculine", "voice_feminine", "voice_child",
	"voice_elder", "voice_robot", "voice_monster", "voice_ghost",
]

func _run_all(golden: Dictionary) -> void:
	var pa := _make_pa()

	# 1. Each preset synthesizing the same Spanish phrase with a fixed seed.
	# Catches any drift in the DSP, prosody, or per-preset formant handling.
	for name in PRESETS:
		var v := _load_seeded_voice(name, 12345)
		var buf := pa.synthesize_to_buffer(SPANISH_PHRASE, 1.0, v)
		_record(golden, "preset/" + name, {"len": buf.size(), "hash": _hash_buf(buf)})

	# 2. Auto-detect languages against the default voice.
	# Catches drift in language normalize/tokenize or the detector.
	pa.auto_detect_language = true
	var lang_texts := {
		"es": "Hola mundo, esto es una prueba.",
		"en": "Hello world, this is a test.",
		"fr": "Bonjour le monde, ceci est un test.",
		"de": "Hallo Welt, das ist ein Test.",
		"ja": "Konnichiwa sekai, kore wa tesuto desu.",
		"it": "Ciao mondo, questa è una prova.",
	}
	for code in lang_texts.keys():
		var v := _load_seeded_voice("voice_default", 99)
		var buf := pa.synthesize_to_buffer(lang_texts[code], 1.0, v)
		_record(golden, "autolang/" + code, {"len": buf.size(), "hash": _hash_buf(buf)})
	pa.auto_detect_language = false

	# 3. Coarticulation off vs on. The two hashes must differ — this is the drift
	# point the dual-code-path unification fixed. If threaded synthesis silently
	# skipped coarticulation again, coart/on and coart/off would match.
	var v_off := _load_seeded_voice("voice_default", 7)
	v_off.coarticulation_strength = 0.0
	var buf_off := pa.synthesize_to_buffer("caballo camina", 1.0, v_off)
	_record(golden, "coart/off", {"len": buf_off.size(), "hash": _hash_buf(buf_off)})

	var v_on := _load_seeded_voice("voice_default", 7)
	v_on.coarticulation_strength = 0.9
	v_on.coarticulation_window = 0.25
	var buf_on := pa.synthesize_to_buffer("caballo camina", 1.0, v_on)
	_record(golden, "coart/on", {"len": buf_on.size(), "hash": _hash_buf(buf_on)})
	_record(golden, "coart/differs", {"differs": _hash_buf(buf_off) != _hash_buf(buf_on)})

	# 4. Language routing: the SAME text tokenized with a French processor must
	# produce different audio than with the Spanish processor. Regression guard
	# for the silent-Spanish-fallback bug where AnimaleseSynth used to ignore
	# fr/de/pt/it/ru/zh language codes and tokenize everything as Spanish.
	var v_lang := _load_seeded_voice("voice_default", 21)
	pa.language = load("res://addons/procedural_animalese/runtime/french_processor.gd").new()
	var buf_fr_route := pa.synthesize_to_buffer("Bonjour le monde", 1.0, v_lang)
	pa.language = load("res://addons/procedural_animalese/runtime/spanish_processor.gd").new()
	var buf_es_route := pa.synthesize_to_buffer("Bonjour le monde", 1.0, v_lang)
	pa.language = null
	_record(golden, "lang/fr_differs_from_es", {"differs": _hash_buf(buf_fr_route) != _hash_buf(buf_es_route)})

	# 5. Determinism: same seed, same input → byte-identical output on a repeat call.
	var v_det := _load_seeded_voice("voice_default", 55555)
	var a := pa.synthesize_to_buffer("Prueba de determinismo", 1.0, v_det)
	var b := pa.synthesize_to_buffer("Prueba de determinismo", 1.0, v_det)
	_record(golden, "determinism/repeat", {"identical": _hash_buf(a) == _hash_buf(b)})

	# 6. Viseme track structure for a mixed phrase. Locks in the phoneme→viseme
	# mapping and the timing calc that get_viseme_track shares with the kernel.
	var v_viseme := _load_seeded_voice("voice_default", 1)
	var track: Array = pa.get_viseme_track("Hola, ¿qué tal? Perfecto.", 1.0, v_viseme)
	var sig: Array = []
	for m in track:
		sig.append([m.viseme, m.phoneme, snappedf(m.time_sec, 0.0001), snappedf(m.duration_sec, 0.0001)])
	_record(golden, "viseme/mixed", {"count": track.size(), "sig_hash": sig.hash()})
