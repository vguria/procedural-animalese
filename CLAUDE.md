# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Godot 4.x editor plugin (`addons/procedural_animalese`) that generates procedural "Animalese"-style speech at runtime via formant synthesis — no pre-recorded audio. The repo root is a thin Godot host project whose only role is to load the plugin and run the demo scene (`main.tscn` → `addons/procedural_animalese/demo/demo.tscn`). All real code lives under the plugin folder.

- Engine: Godot 4.6 (see `project.godot` → `config/features`)
- Language: GDScript only (no C#, no GDExtension)
- Plugin version: see `addons/procedural_animalese/plugin.cfg`

## Running & testing

There is no CLI build/lint/test toolchain — the workflow is Godot-editor driven:

- Open the project in Godot 4.6+ (`godot -e project.godot`).
- Enable the plugin: **Project → Project Settings → Plugins → Procedural Animalese** (already enabled in `project.godot`; disable/re-enable to reload after plugin script changes).
- Run the demo: F5, or `godot --path . res://main.tscn` — this launches `demo/demo.tscn` with UI to exercise voices, emotions, languages, blending, markup, and lip-sync.
- Performance benchmark: run `addons/procedural_animalese/demo/performance_test.tscn`.
- No unit test suite exists. Verification is manual via the demo scene and the editor **Voice Editor** dock (right-side UL slot).

Locale: to add an editor UI translation, copy `addons/procedural_animalese/locale/procedural_animalese.pot` to `procedural_animalese.<code>.po` and translate — the plugin wraps user-facing strings with `tr()`.

## Architecture

### Two layers: plugin bootstrap vs. runtime

- `procedural_animalese_editor_plugin.gd` (`@tool`, extends `EditorPlugin`) registers the custom types (`ProceduralAnimalese`, `AnimaleseVoice`, `AnimaleseVoiceLibrary`, `AnimaleseVoiceEntry`, `AnimaleseEmotion`, `LanguageProcessor`, and language subclasses) and mounts the **Voice Editor** dock. It also spawns a hidden `ProceduralAnimalese` node with `run_in_editor = true` so the dock's "Preview" button can play audio without a running game.
- Runtime code (`runtime/*.gd`) is engine-agnostic beyond `Node`/`Resource` and is what ships to users' games. Editor UI (`voice_editor_dock.gd`, `voice_wizard.gd`, `voice_preset_browser.gd`) is `@tool`-only and must not be referenced from runtime.

### Synthesis pipeline (runtime/procedural_animalese.gd, ~2200 LOC)

This one file is the heart of the plugin. Flow for a `speak()` call:

1. **Text → tokens.** The active `LanguageProcessor` (auto-detected if `auto_detect_language`, else `language`, else lazy `SpanishProcessor`) runs `normalize()` then `tokenize()` to produce phoneme/syllable tokens plus punctuation.
2. **Markup parse** (only via `speak_markup`). `_parse_markup()` splits text into `MarkupSegment`s carrying per-segment `pitch_mul`, `speed_mul`, `pause_sec`, `voice_id`, `emotion_name`. Tags supported: `[pause:s]`, `[pitch:x]`, `[speed:x]`, `[voice:id]`, `[emotion:name]`, nestable.
3. **Voice resolution.** `speak_for(id, …)` looks the voice up in `voice_library`; `speak_with_emotion` clones the voice via `_apply_emotion_to_voice()` (which calls `AnimaleseEmotion.apply_to_voice_params()` on a serialized dict, then rehydrates a new `AnimaleseVoice`) — the original resource is never mutated.
4. **Synthesis.** For each token, `_render_phoneme[_dict]()` builds a `PhonemeConfig` (kind, voiced, formants, is_vowel) then runs source+filter synthesis: glottal-ish source (voiced) or noise (fricatives) → parallel biquad band-pass filters at F1/F2/F3 (optionally F4/F5 when `use_extended_formants`) → ADSR envelope → coarticulation crossfade with the previous/next phoneme's formants. Prosody (`_prosody_pitch_mul*`) tilts pitch across the phrase based on `?`/`!`/statement scan (`_scan_phrase`). Vibrato, jitter, breath noise, whisper mix, and edge fades are applied per-phoneme.
5. **Playback.** Segments are fed frame-by-frame to an `AudioStreamGenerator` playing on a dedicated `"Animalese"` audio bus (auto-created with EQ+compressor if `ensure_audio_bus`/`auto_add_bus_effects`).

Synthesis has a single kernel: `_synthesize_from_dict()` (which internally calls `_render_phoneme_dict()`, `_phoneme_for_token_dict()`, `_peek_next_formants_dict()`, `_prosody_pitch_mul_dict()`). It takes a serialized `Dictionary` produced by `_serialize_voice()` because Godot Resources aren't thread-safe. Every entry point serializes the voice up front and calls the kernel:

- `speak` / `speak_for` / `speak_with_emotion` / `speak_markup` → `_speak_internal*` → kernel (sync or via `WorkerThreadPool` when `threaded_synthesis = true`, default).
- `synthesize_to_buffer` / `export_to_wav` → kernel directly, sync.
- Worker path posts results back with `call_deferred` → `_on_synthesis_complete`, carrying the sample buffer AND the timing markers the kernel produced (no separate dry pass). A `_stop_generation` counter invalidates stale callbacks after `stop_all()`.

Timing markers (`TimingMarker`, `MarkerType.PHONEME/WORD/END`) are emitted inline during synthesis. `_collect_timing_markers()` runs the same tokenization + duration math *without* the DSP and is used only on cache hits to rebuild the marker track for a cached sample buffer.

### Timing, visemes, and signals

`_collect_timing_markers()` runs a dry synthesis pass to compute `TimingMarker`s (PHONEME / WORD / END) at sample offsets. During playback `_check_and_emit_markers()` fires `phoneme_started`, `word_started`, `speech_progress`, `speech_finished`, and `viseme_changed`. Phoneme→viseme mapping lives in `_phoneme_to_viseme()`; `get_viseme_track()` returns a pre-baked `Array[VisemeMarker]` and the `create_viseme_*_animation()` helpers convert that into Godot `Animation` resources for `Sprite2D:frame`, arbitrary method tracks, or 3D blend-shape properties.

### Caching

`_segment_cache: Dictionary[int, PackedFloat32Array]` keyed by an int64 hash of `(voice params, text, pitch_mul)`. Cache is guarded by `_cache_mutex`. When a voice's `changed` signal fires, `_on_voice_changed()` clears the cache. If `random_seed == 0` and `cache_unseeded` is false (defaults), synthesis intentionally skips caching to preserve per-call variation.

### Language processors

`LanguageProcessor` (base) declares `normalize(text) → String`, `tokenize(text) → Array[String]`, `is_vowel(ch)`, `get_language_code()`. Each language subclass under `runtime/*_processor.gd` implements its own normalization (e.g. Spanish collapses `ll`/`rr`/`ch`, drops silent `h`, maps `que`→`ke`) and CV-style syllable tokenization. When adding a new language:

1. Create `runtime/<lang>_processor.gd` extending `LanguageProcessor` with a `class_name`, override the four methods.
2. Register it in `procedural_animalese_editor_plugin.gd` (`add_custom_type` + matching `remove_custom_type` in `_exit_tree`) if it needs to appear in the editor's "New Resource" menu.
3. Wire it into `LanguageDetector` (`runtime/language_detector.gd`) — add the ISO code to `LOCALE_TO_LANGUAGE`, add character/word heuristics, and update `create_processor_for_language()`.
4. Update `ProceduralAnimalese._create_language_from_code()` / `create_language_processor()`.

### Voice presets

`.tres` resources under `addons/procedural_animalese/presets/` (default, masculine, feminine, child, elder, robot, monster, ghost). `procedural_animalese.gd` auto-loads `voice_default.tres` from `DEFAULT_VOICE_PATH` in `_ready()` if no voice is assigned — keep that path stable.

### Integrations

`integrations/dialogic_integration.gd` (`DialogicAnimalese`) is opt-in; it looks for the Dialogic autoload at runtime and does nothing if absent, so it must not hard-import Dialogic symbols.

## Conventions

- All plugin-facing scripts use `class_name` so they resolve globally in user projects.
- The editor plugin script and any script that must run in-editor use `@tool`. `run_in_editor` on `ProceduralAnimalese` is the runtime-side toggle for in-editor playback (preview node in the dock).
- Comments in `animalese_voice.gd`, `animalese_emotion.gd`, and older runtime files are Spanish; newer code and public docs are English. Match the surrounding file's language when editing.
- Never mutate a user's `AnimaleseVoice` resource in place — clone via `duplicate()` or the emotion apply path.
- All DSP changes go in the single `_synthesize_from_dict` / `_render_phoneme_dict` pair. Both are safe to call from a worker thread (no member-state access beyond `self._env_adsr` / `self._soft_clip_in_place` / `self._append_silence_sr` / `self._apply_edge_fade`, which are pure helpers).
