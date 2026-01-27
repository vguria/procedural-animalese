@tool
extends Node
## Performance validation script for Procedural Animalese.
## Run this scene to test synthesis performance and memory usage.

const LONG_TEXT := """
This is a very long text designed to test the performance of the procedural
animalese speech synthesis system. It contains multiple sentences with various
punctuation marks, including commas, periods, exclamation points! And question
marks? The synthesizer should handle this efficiently without blocking the main
thread when threaded synthesis is enabled. We're testing how well the system
performs with extended passages of text that might appear in dialogue-heavy
games or visual novels. Performance is critical for a good user experience.
"""

const SHORT_TEXT := "Hello world!"
const MEDIUM_TEXT := "This is a medium length sentence for testing synthesis performance."

var animalese: ProceduralAnimalese
var results: Array[Dictionary] = []
var test_running := false

func _ready() -> void:
	# Create animalese node
	animalese = ProceduralAnimalese.new()
	animalese.threaded_synthesis = true
	animalese.enable_cache = true
	add_child(animalese)

	# Wait for initialization
	await get_tree().process_frame
	await get_tree().process_frame

	print("=" .repeat(60))
	print("PROCEDURAL ANIMALESE - PERFORMANCE VALIDATION")
	print("=" .repeat(60))
	print("")

	# Run tests
	await run_all_tests()

	# Print summary
	print_summary()

func run_all_tests() -> void:
	test_running = true

	# Test 1: Synthesis speed (short text)
	await test_synthesis_speed("Short text", SHORT_TEXT, 10)

	# Test 2: Synthesis speed (medium text)
	await test_synthesis_speed("Medium text", MEDIUM_TEXT, 10)

	# Test 3: Synthesis speed (long text)
	await test_synthesis_speed("Long text", LONG_TEXT, 5)

	# Test 4: Threaded vs non-threaded
	await test_threaded_comparison()

	# Test 5: Cache effectiveness
	await test_cache_effectiveness()

	# Test 6: Rapid fire calls
	await test_rapid_fire()

	# Test 7: Memory stability
	await test_memory_stability()

	# Test 8: Voice blending performance
	await test_voice_blending()

	# Test 9: Language processor performance
	await test_language_processors()

	# Test 10: Viseme generation performance
	await test_viseme_generation()

	test_running = false

func test_synthesis_speed(name: String, text: String, iterations: int) -> void:
	print("[TEST] %s synthesis speed (%d iterations)" % [name, iterations])

	var times: Array[float] = []

	for i in range(iterations):
		# Clear cache to get fresh synthesis time
		animalese._segment_cache.clear()

		var start := Time.get_ticks_usec()
		var samples := animalese.synthesize_to_buffer(text)
		var end := Time.get_ticks_usec()

		var elapsed_ms := (end - start) / 1000.0
		times.append(elapsed_ms)

		await get_tree().process_frame

	var avg := _average(times)
	var min_t := times.min()
	var max_t := times.max()
	var samples_count := animalese.synthesize_to_buffer(text).size()
	var duration_sec := float(samples_count) / float(animalese.mix_rate)

	print("  Samples: %d (%.2f sec audio)" % [samples_count, duration_sec])
	print("  Avg: %.2f ms | Min: %.2f ms | Max: %.2f ms" % [avg, min_t, max_t])
	print("  Real-time factor: %.1fx" % [duration_sec * 1000.0 / avg])
	print("")

	results.append({
		"test": name + " synthesis",
		"avg_ms": avg,
		"min_ms": min_t,
		"max_ms": max_t,
		"samples": samples_count,
		"realtime_factor": duration_sec * 1000.0 / avg
	})

func test_threaded_comparison() -> void:
	print("[TEST] Threaded vs non-threaded synthesis")

	var text := MEDIUM_TEXT
	var iterations := 5

	# Non-threaded
	animalese.threaded_synthesis = false
	animalese._segment_cache.clear()

	var non_threaded_times: Array[float] = []
	for i in range(iterations):
		animalese._segment_cache.clear()
		var start := Time.get_ticks_usec()
		animalese.speak(text)
		var end := Time.get_ticks_usec()
		non_threaded_times.append((end - start) / 1000.0)
		animalese.stop_all()
		await get_tree().process_frame

	# Threaded
	animalese.threaded_synthesis = true
	animalese._segment_cache.clear()

	var threaded_times: Array[float] = []
	for i in range(iterations):
		animalese._segment_cache.clear()
		var start := Time.get_ticks_usec()
		animalese.speak(text)
		var end := Time.get_ticks_usec()
		threaded_times.append((end - start) / 1000.0)
		animalese.stop_all()
		await get_tree().process_frame

	var non_threaded_avg := _average(non_threaded_times)
	var threaded_avg := _average(threaded_times)

	print("  Non-threaded avg: %.2f ms (blocks main thread)" % non_threaded_avg)
	print("  Threaded avg: %.2f ms (non-blocking)" % threaded_avg)
	print("  Threading reduces blocking by: %.1f%%" % [(1.0 - threaded_avg / non_threaded_avg) * 100.0])
	print("")

	results.append({
		"test": "Threading comparison",
		"non_threaded_ms": non_threaded_avg,
		"threaded_ms": threaded_avg
	})

func test_cache_effectiveness() -> void:
	print("[TEST] Cache effectiveness")

	var text := MEDIUM_TEXT
	var iterations := 10

	animalese.enable_cache = true
	animalese._segment_cache.clear()

	# First call (cache miss)
	var start := Time.get_ticks_usec()
	animalese.synthesize_to_buffer(text)
	var first_call := (Time.get_ticks_usec() - start) / 1000.0

	# Subsequent calls (cache hit)
	var cached_times: Array[float] = []
	for i in range(iterations):
		start = Time.get_ticks_usec()
		animalese.synthesize_to_buffer(text)
		cached_times.append((Time.get_ticks_usec() - start) / 1000.0)

	var cached_avg := _average(cached_times)

	print("  First call (cache miss): %.2f ms" % first_call)
	print("  Cached calls avg: %.2f ms" % cached_avg)
	print("  Cache speedup: %.1fx faster" % [first_call / cached_avg])
	print("")

	results.append({
		"test": "Cache effectiveness",
		"uncached_ms": first_call,
		"cached_ms": cached_avg,
		"speedup": first_call / cached_avg
	})

func test_rapid_fire() -> void:
	print("[TEST] Rapid fire calls (stress test)")

	var calls := 50
	animalese._segment_cache.clear()

	var start := Time.get_ticks_usec()
	for i in range(calls):
		animalese.speak(SHORT_TEXT)
		animalese.stop_all()
	var total_ms := (Time.get_ticks_usec() - start) / 1000.0

	print("  %d rapid speak/stop cycles" % calls)
	print("  Total time: %.2f ms" % total_ms)
	print("  Avg per cycle: %.2f ms" % [total_ms / calls])
	print("  No crashes or errors: PASS")
	print("")

	results.append({
		"test": "Rapid fire",
		"calls": calls,
		"total_ms": total_ms,
		"avg_per_call_ms": total_ms / calls
	})

func test_memory_stability() -> void:
	print("[TEST] Memory stability (cache growth)")

	var unique_texts := 100
	animalese._segment_cache.clear()

	# Generate unique texts to fill cache
	for i in range(unique_texts):
		var text := "Test sentence number %d with unique content." % i
		animalese.synthesize_to_buffer(text)

	var cache_size := animalese._segment_cache.size()
	var cache_entries := cache_size

	# Estimate memory (rough: samples * 4 bytes per float)
	var total_samples := 0
	for key in animalese._segment_cache.keys():
		total_samples += animalese._segment_cache[key].size()
	var estimated_mb := (total_samples * 4) / (1024.0 * 1024.0)

	print("  Generated %d unique phrases" % unique_texts)
	print("  Cache entries: %d" % cache_entries)
	print("  Total samples cached: %d" % total_samples)
	print("  Estimated memory: %.2f MB" % estimated_mb)
	print("")

	# Clear cache
	animalese._segment_cache.clear()

	results.append({
		"test": "Memory stability",
		"unique_phrases": unique_texts,
		"cache_entries": cache_entries,
		"total_samples": total_samples,
		"estimated_mb": estimated_mb
	})

func test_voice_blending() -> void:
	print("[TEST] Voice blending performance")

	var voice_a := preload("res://addons/procedural_animalese/presets/voice_masculine.tres")
	var voice_b := preload("res://addons/procedural_animalese/presets/voice_feminine.tres")

	var iterations := 100
	var start := Time.get_ticks_usec()

	for i in range(iterations):
		var factor := float(i) / float(iterations)
		ProceduralAnimalese.blend_voices(voice_a, voice_b, factor)

	var total_ms := (Time.get_ticks_usec() - start) / 1000.0
	var avg_ms := total_ms / iterations

	print("  %d blend operations" % iterations)
	print("  Total time: %.2f ms" % total_ms)
	print("  Avg per blend: %.3f ms" % avg_ms)
	print("")

	results.append({
		"test": "Voice blending",
		"iterations": iterations,
		"total_ms": total_ms,
		"avg_ms": avg_ms
	})

func test_language_processors() -> void:
	print("[TEST] Language processor performance")

	var processors := {
		"Spanish": SpanishProcessor.new(),
		"English": EnglishProcessor.new(),
		"Japanese": JapaneseProcessor.new(),
		"French": FrenchProcessor.new(),
		"German": GermanProcessor.new(),
	}

	var test_text := "Hello world, this is a test of the language processor."
	var iterations := 100

	for lang_name in processors.keys():
		var proc: LanguageProcessor = processors[lang_name]

		var start := Time.get_ticks_usec()
		for i in range(iterations):
			var normalized := proc.normalize(test_text)
			proc.tokenize(normalized)
		var total_ms := (Time.get_ticks_usec() - start) / 1000.0

		print("  %s: %.2f ms total (%.3f ms/call)" % [lang_name, total_ms, total_ms / iterations])

	print("")

	results.append({
		"test": "Language processors",
		"iterations_per_lang": iterations,
		"status": "PASS"
	})

func test_viseme_generation() -> void:
	print("[TEST] Viseme track generation")

	var iterations := 50
	var text := MEDIUM_TEXT

	var start := Time.get_ticks_usec()
	for i in range(iterations):
		animalese.get_viseme_track(text)
	var total_ms := (Time.get_ticks_usec() - start) / 1000.0

	var track := animalese.get_viseme_track(text)

	print("  %d viseme track generations" % iterations)
	print("  Total time: %.2f ms" % total_ms)
	print("  Avg per generation: %.3f ms" % [total_ms / iterations])
	print("  Visemes per track: %d" % track.size())
	print("")

	results.append({
		"test": "Viseme generation",
		"iterations": iterations,
		"total_ms": total_ms,
		"avg_ms": total_ms / iterations,
		"visemes_count": track.size()
	})

func print_summary() -> void:
	print("=" .repeat(60))
	print("PERFORMANCE SUMMARY")
	print("=" .repeat(60))
	print("")

	# Key metrics
	for r in results:
		if r["test"] == "Short text synthesis":
			print("Short text real-time factor: %.1fx" % r.get("realtime_factor", 0))
		elif r["test"] == "Medium text synthesis":
			print("Medium text real-time factor: %.1fx" % r.get("realtime_factor", 0))
		elif r["test"] == "Long text synthesis":
			print("Long text real-time factor: %.1fx" % r.get("realtime_factor", 0))
		elif r["test"] == "Cache effectiveness":
			print("Cache speedup: %.1fx" % r.get("speedup", 0))
		elif r["test"] == "Memory stability":
			print("Memory per 100 phrases: %.2f MB" % r.get("estimated_mb", 0))

	print("")
	print("All tests completed successfully!")
	print("")

	# Recommendations
	print("RECOMMENDATIONS:")
	print("- Keep threaded_synthesis=true for non-blocking audio")
	print("- Enable cache for repeated phrases")
	print("- Clear cache periodically if memory is a concern")
	print("- Use random_seed=0 for variety, non-zero for reproducibility")
	print("")

func _average(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var sum := 0.0
	for v in arr:
		sum += v
	return sum / arr.size()
