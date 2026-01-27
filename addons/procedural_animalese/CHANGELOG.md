# Changelog

All notable changes to Procedural Animalese will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.9.0] - 2025-01-26

### Added

#### Core Synthesis
- Real-time procedural speech synthesis using formant filters
- Configurable voice parameters: pitch, jitter, duration, gain
- Vibrato support with rate, depth, and delay controls
- ADSR envelope for natural phoneme shaping
- Coarticulation for smooth transitions between phonemes
- Whisper mode with breath noise synthesis
- Threaded synthesis for non-blocking audio generation
- Audio caching for repeated phrases
- WAV export functionality

#### Voice System
- `AnimaleseVoice` resource with 30+ configurable parameters
- Formant control for vowels (a, e, i, o, u)
- Formant control for consonants (fricatives, stops, nasals)
- Extended formants (F4/F5) for additional brightness
- 8 voice presets included:
  - Default (neutral, balanced)
  - Masculine (deep, 120 Hz)
  - Feminine (higher, 240 Hz)
  - Child (high-pitched, 350 Hz)
  - Elder (slow, shaky, 110 Hz)
  - Robot (flat, mechanical)
  - Monster (low, growling, 85 Hz)
  - Ghost (ethereal, whispery)
- Voice blending with `blend_voices()` static method
- Default voice auto-loading when none assigned

#### Emotion System
- `AnimaleseEmotion` resource with multipliers and offsets
- 10 built-in emotion presets:
  - Neutral, Happy, Sad, Angry, Scared
  - Nervous, Excited, Tired, Whisper, Mysterious
- Emotion blending with `blend_with()` method
- `speak_with_emotion()` for easy emotion application

#### Multi-Language Support
- 9 language processors:
  - Spanish (default)
  - English
  - Japanese (romaji)
  - French
  - German
  - Portuguese
  - Italian
  - Russian (Cyrillic romanization)
  - Chinese (Pinyin + character conversion)
- Automatic language detection with `LanguageDetector`
- TranslationServer integration for system locale fallback

#### Markup System
- `speak_markup()` for inline text control
- Supported tags:
  - `[pause:seconds]` - Insert silence
  - `[pitch:factor]text[/pitch]` - Modify pitch
  - `[speed:factor]text[/speed]` - Modify speed
  - `[voice:id]text[/voice]` - Switch voice from library
  - `[emotion:name]text[/emotion]` - Apply emotion
- Nestable tags for complex combinations

#### Lip-Sync / Visemes
- 10 viseme shapes: SILENT, AA, EE, OO, OH, FF, TH, SS, NN, CH
- Real-time `viseme_changed` signal
- `get_viseme_track()` for pre-baked animation data
- Animation generation methods:
  - `create_viseme_animation()` for VALUE tracks (Sprite2D.frame)
  - `create_viseme_method_animation()` for METHOD tracks
  - `create_viseme_blend_shape_animation()` for 3D blend shapes
- JSON export with `export_viseme_track_json()`

#### Progress Signals
- `phoneme_started(phoneme, index)` - Per-phoneme callback
- `word_started(word, index)` - Per-word callback
- `speech_progress(ratio)` - 0.0 to 1.0 progress
- `speech_finished()` - Completion callback

#### Voice Library
- `AnimaleseVoiceLibrary` resource for multiple characters
- `AnimaleseVoiceEntry` for character-voice mapping
- `speak_for(character_id, text)` method

#### Editor Tools
- **Voice Editor Dock** with tabs:
  - Main: Parameters, randomization with locks
  - Formants: Per-phoneme formant editing, presets, vowel chart
  - Advanced: A/B comparison, voice blending
- **Voice Creation Wizard** (4-step guided process)
- **Voice Preset Browser** with filtering and sorting
- Waveform visualization
- Phoneme preview buttons
- Interactive formant graph
- F1-F2 vowel chart visualization
- Undo/redo support

#### Integrations
- Dialogic 2 integration with `DialogicAnimalese` node
- Character-to-voice mapping
- Character-to-emotion mapping
- Automatic BBCode tag cleaning

#### Internationalization
- Editor UI prepared for translation with `tr()` calls
- POT template file for translators
- Spanish translation included

#### Documentation
- Comprehensive README with:
  - Installation guide
  - Quick start examples
  - Full API reference
  - Markup tag documentation
  - Lip-sync integration guide
  - Multi-language usage
  - Voice creation guide
  - Performance tips

#### Demo
- Interactive demo scene (`demo/demo.tscn`)
- Voice selection and preview
- Emotion testing
- Language switching with sample texts
- Voice blending preview
- Markup tag examples
- Real-time viseme/phoneme/word display

#### Quality
- Error handling with informative warnings
- Parameter validation on public methods
- Graceful handling of null voices and empty text
- MIT License

### Technical Details

- **Godot Version**: 4.x
- **Audio**: AudioStreamGenerator at 44100 Hz (configurable)
- **Threading**: WorkerThreadPool for background synthesis
- **Caching**: Hash-based cache with int64 keys
- **Filters**: Biquad bandpass with pooling for performance

---

## Future Plans

See [ROADMAP.md](../../ROADMAP.md) for planned features and improvements.
