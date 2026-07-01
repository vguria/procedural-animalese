# Procedural Animalese

A Godot 4.4+ plugin for procedural speech synthesis inspired by Animal Crossing's "Animalese" speech style. Generate expressive, gibberish-like speech in real-time with customizable voices, emotions, and multi-language support.

## Features

- **Real-time procedural synthesis** - No pre-recorded audio files needed
- **Multi-language support** - Spanish, English, Japanese, French, German, Portuguese, Italian, Russian, and Chinese
- **Automatic language detection** - Detects language from text with TranslationServer integration
- **Customizable voices** - Full control over pitch, formants, prosody, and timbre
- **Emotion system** - Apply emotions like happy, sad, angry, scared, etc.
- **Lip-sync/Visemes** - Generate viseme tracks for character animation
- **Markup system** - Control pitch, speed, pauses, and emotions inline
- **Threaded synthesis** - Background processing for smooth gameplay
- **WAV export** - Export synthesized speech to audio files
- **Editor dock** - Visual voice editor with waveform preview

## Installation

1. Copy the `addons/procedural_animalese` folder to your project's `addons/` directory
2. Enable the plugin in Project Settings → Plugins
3. Add a `ProceduralAnimalese` node to your scene

## Quick Start

### Basic Usage

```gdscript
# Get the ProceduralAnimalese node
@onready var animalese: ProceduralAnimalese = $ProceduralAnimalese

func _ready():
    # Simple speech
    animalese.speak("Hello, world!")

    # With pitch modifier (1.0 = normal, higher = faster/higher pitch)
    animalese.speak("I'm excited!", 1.2)
```

### Using Voice Presets

```gdscript
# Load a voice preset
var voice = preload("res://addons/procedural_animalese/presets/voice_feminine.tres")
animalese.voice = voice

# Or create a voice in code
var custom_voice = AnimaleseVoice.new()
custom_voice.pitch_base_hz = 180.0  # Lower pitch
custom_voice.char_duration_s = 0.06  # Slightly slower
animalese.voice = custom_voice
```

### Multi-Language Support

```gdscript
# Set a specific language processor
animalese.language = preload("res://addons/procedural_animalese/runtime/japanese_processor.gd").new()
animalese.speak("こんにちは")  # Speaks with Japanese phonetics

# Or enable automatic detection
animalese.auto_detect_language = true
animalese.speak("Bonjour!")  # Auto-detects French
animalese.speak("Guten Tag!")  # Auto-detects German

# Manual language detection
var lang_code = animalese.detect_language("Ciao, come stai?")  # Returns "it"

# Use system locale (from TranslationServer)
var processor = LanguageDetector.create_processor_for_system_locale()
```

### Emotions

```gdscript
# Use built-in emotion presets
animalese.speak_with_emotion("I'm so happy!", "happy")
animalese.speak_with_emotion("This is terrible...", "sad")
animalese.speak_with_emotion("How dare you!", "angry")

# Available emotions: happy, sad, angry, scared, nervous, excited, tired, whisper, mysterious

# Create custom emotions
var custom_emotion = AnimaleseEmotion.new()
custom_emotion.pitch_mul = 1.3
custom_emotion.speed_mul = 1.2
custom_emotion.vibrato_mul = 2.0
animalese.speak_with_emotion("Custom emotion!", custom_emotion)

# Blend emotions
var mixed = AnimaleseEmotion.happy().blend_with(AnimaleseEmotion.nervous(), 0.5)
```

### Markup System

Control speech dynamically with inline tags:

```gdscript
# Pitch modification
animalese.speak_markup("Normal voice [pitch:1.3]higher pitch[/pitch] back to normal")

# Speed modification
animalese.speak_markup("[speed:0.7]Speaking slowly[/speed] now faster")

# Pauses
animalese.speak_markup("Wait for it... [pause:0.5] Surprise!")

# Emotions in markup
animalese.speak_markup("[emotion:happy]I'm so glad![/emotion] [emotion:sad]But now I'm sad.[/emotion]")

# Nested tags
animalese.speak_markup("[pitch:1.2][speed:1.1][emotion:excited]Very excited speech![/emotion][/speed][/pitch]")
```

### Character Voice Library

Assign different voices to characters:

```gdscript
# Set up voice library
var library = AnimaleseVoiceLibrary.new()
library.add_voice(&"hero", preload("res://voices/hero.tres"))
library.add_voice(&"villain", preload("res://voices/villain.tres"))
animalese.voice_library = library

# Speak as specific character
animalese.speak_for(&"hero", "I will save the day!")
animalese.speak_for(&"villain", "You cannot stop me!")
```

### Lip-Sync / Visemes

Generate viseme data for character animation:

```gdscript
# Get viseme track
var track = animalese.get_viseme_track("Hello there!")
for marker in track:
    print("Viseme: %s at %.2fs" % [marker.viseme, marker.time_sec])

# Real-time viseme signal
animalese.viseme_changed.connect(_on_viseme_changed)

func _on_viseme_changed(viseme: int, weight: float):
    # Update character mouth shape
    match viseme:
        ProceduralAnimalese.Viseme.AA:
            mouth_sprite.frame = 0  # Open mouth
        ProceduralAnimalese.Viseme.EE:
            mouth_sprite.frame = 1  # Wide mouth
        ProceduralAnimalese.Viseme.OO:
            mouth_sprite.frame = 2  # Round mouth
        # ... etc

# Generate Animation resource for AnimationPlayer
var anim = animalese.create_viseme_animation("Hello!", "Sprite2D:frame")
animation_player.add_animation("talk", anim)
animation_player.play("talk")

# For 3D blend shapes
var anim_3d = animalese.create_viseme_blend_shape_animation(
    "Hello!",
    "Character/MeshInstance3D",
    "viseme_"  # Prefix for blend shape names
)
```

### Progress Signals

Track speech progress for subtitles or effects:

```gdscript
animalese.phoneme_started.connect(_on_phoneme)
animalese.word_started.connect(_on_word)
animalese.speech_progress.connect(_on_progress)
animalese.speech_finished.connect(_on_finished)

func _on_phoneme(phoneme: String, index: int):
    print("Phoneme: ", phoneme)

func _on_word(word: String, index: int):
    subtitle_label.text = word

func _on_progress(ratio: float):
    progress_bar.value = ratio

func _on_finished():
    print("Speech complete!")
```

### Export to WAV

Save synthesized speech to audio files:

```gdscript
var error = animalese.export_to_wav("Hello world!", "res://audio/hello.wav")
if error == OK:
    print("Exported successfully!")
```

### Synthesize to Buffer

Get raw audio data for custom processing:

```gdscript
var buffer: PackedFloat32Array = animalese.synthesize_to_buffer("Hello!")
# Use buffer with AudioStreamGenerator or process further
```

## Voice Parameters

The `AnimaleseVoice` resource contains all voice customization options:

| Parameter | Range | Description |
|-----------|-------|-------------|
| `pitch_base_hz` | 80-600 | Base pitch frequency in Hz |
| `pitch_jitter` | 0-0.25 | Random pitch variation per phoneme |
| `char_duration_s` | 0.02-0.12 | Duration per character in seconds |
| `vibrato_rate_hz` | 0-12 | Vibrato frequency (0 = disabled) |
| `vibrato_depth` | 0-1 | Vibrato intensity |
| `output_gain` | 0-2 | Output volume |
| `breath_noise_level` | 0-1.5 | Breath/air noise amount |
| `whisper_amount` | 0-1 | Whisper mix (0 = normal, 1 = full whisper) |
| `prosody_strength` | 0-1 | Intonation intensity |
| `coarticulation_strength` | 0-1 | Smoothness between phonemes |

### Formants

Each voice has configurable formants (F1, F2, F3) for vowels, fricatives, stops, and nasals. Formants are defined as `Vector3(frequency_hz, Q, amplitude)`.

## Supported Languages

| Language | Code | Processor | Features |
|----------|------|-----------|----------|
| Spanish | `es` | SpanishProcessor | Native CV syllables |
| English | `en` | EnglishProcessor | Digraphs, diphthongs |
| Japanese | `ja` | JapaneseProcessor | Romaji/hiragana/katakana |
| French | `fr` | FrenchProcessor | Nasal vowels, liaisons |
| German | `de` | GermanProcessor | Umlauts, ß, compound sounds |
| Portuguese | `pt` | PortugueseProcessor | Nasal vowels, lh/nh |
| Italian | `it` | ItalianProcessor | Pure vowels, gli/gn |
| Russian | `ru` | RussianProcessor | Cyrillic romanization |
| Chinese | `zh` | ChineseProcessor | Pinyin, character mapping |

## Viseme Types

| Viseme | Description | Phonemes |
|--------|-------------|----------|
| SILENT | Mouth closed | Silence, M, B, P |
| AA | Open mouth | A |
| EE | Wide, teeth visible | E, I |
| OO | Round/pursed lips | O, U |
| OH | Partially open, rounded | Soft O |
| FF | Upper teeth on lower lip | F, V |
| TH | Tongue between teeth | TH, D, T |
| SS | Teeth together, narrow | S, Z, C |
| NN | Slightly open, tongue up | N, L, R |
| CH | Lips pushed forward | CH, SH, J |

## Editor Dock

The plugin includes a visual editor dock for voice creation:

- **Voice Creation Wizard** - Step-by-step guided voice creation
- **Waveform preview** - See synthesized audio in real-time
- **Formant graph** - Drag handles to adjust formant frequencies
- **Vowel chart** - Visualize vowel space (F1 vs F2)
- **Phoneme preview** - Test individual sounds
- **A/B comparison** - Compare two voices side by side
- **Voice blending** - Create hybrid voices

### Voice Creation Wizard

The wizard guides you through creating a new voice in 4 steps:

1. **Basic Information** - Name and preset selection (Masculine, Feminine, Child, Elder, Robot, Monster, Ghost, Whisper)
2. **Pitch & Timing** - Base frequency, duration, and pitch variation
3. **Voice Character** - Breathiness, whisper amount, and vibrato settings
4. **Summary & Save** - Review settings and save the resource

Click "New Voice Wizard..." in the Voice Editor dock to start.

## Performance Tips

1. **Enable caching** - Set `enable_cache = true` for repeated phrases
2. **Use threading** - Keep `threaded_synthesis = true` for smooth gameplay
3. **Disable extended formants** - Set `use_extended_formants = false` if CPU is limited
4. **Reuse processors** - Store language processors instead of creating new ones

## Dialogic 2 Integration

For projects using Dialogic 2:

```gdscript
var dialogic_animalese = DialogicAnimalese.new()
dialogic_animalese.animalese = $ProceduralAnimalese
dialogic_animalese.character_voices = {
    "hero": preload("res://voices/hero.tres"),
    "npc": preload("res://voices/npc.tres")
}
add_child(dialogic_animalese)
# Now Dialogic text events will automatically play Animalese
```

## License

MIT License - See LICENSE file for details.

## Credits

Inspired by Nintendo's Animal Crossing series and the "Animalese" speech style.
