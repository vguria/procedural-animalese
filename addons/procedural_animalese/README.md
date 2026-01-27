# Procedural Animalese

Real-time procedural speech synthesis for Godot 4.x, inspired by Animal Crossing. Generate unique character voices without pre-recorded audio.

## Features

- **Pure synthesis** - No audio files needed, voices generated in real-time
- **Formant-based** - Realistic vowel and consonant sounds using resonant filters
- **9 languages** - Spanish, English, Japanese, French, German, Portuguese, Italian, Russian, Chinese
- **Emotions** - Happy, sad, angry, scared, nervous, excited, tired, whisper, mysterious
- **Lip-sync** - Viseme generation for character animation
- **Voice blending** - Mix two voices together
- **Editor dock** - Full voice editor with waveform visualization
- **Threaded synthesis** - Non-blocking audio generation

## Installation

1. Copy the `addons/procedural_animalese` folder to your project's `addons/` directory
2. Enable the plugin in **Project > Project Settings > Plugins**
3. The "Voice Editor" dock will appear on the right side

## Quick Start

### Minimal Setup

```gdscript
# Add a ProceduralAnimalese node to your scene
# It works immediately with the default voice!

func _ready():
    $ProceduralAnimalese.speak("Hello! How are you?")
```

### With Custom Voice

```gdscript
func _ready():
    # Load a voice preset
    var voice = preload("res://addons/procedural_animalese/presets/voice_feminine.tres")
    $ProceduralAnimalese.voice = voice
    $ProceduralAnimalese.speak("Hello! How are you?")
```

### With Emotions

```gdscript
func _ready():
    # Using emotion name
	$ProceduralAnimalese.speak_with_emotion("I'm so happy!", "happy")

    # Using emotion resource
    var emotion = AnimaleseEmotion.excited()
	$ProceduralAnimalese.speak_with_emotion("This is amazing!", emotion)
```

## Voice Presets

The plugin includes several voice presets in `addons/procedural_animalese/presets/`:

| Preset | Description | Pitch |
|--------|-------------|-------|
| `voice_default.tres` | Neutral, balanced voice | 180 Hz |
| `voice_masculine.tres` | Deep male voice | 120 Hz |
| `voice_feminine.tres` | Higher female voice | 240 Hz |
| `voice_child.tres` | High-pitched child voice | 350 Hz |
| `voice_elder.tres` | Slow, shaky elder voice | 110 Hz |
| `voice_robot.tres` | Flat, mechanical voice | 180 Hz |
| `voice_monster.tres` | Low, growling voice | 85 Hz |
| `voice_ghost.tres` | Ethereal, whispery voice | 200 Hz |

## API Reference

### ProceduralAnimalese (Node)

#### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `voice` | AnimaleseVoice | auto-loaded | The voice to use for synthesis |
| `voice_library` | AnimaleseVoiceLibrary | null | Collection of character voices |
| `language` | LanguageProcessor | Spanish | Text processing rules |
| `auto_detect_language` | bool | false | Auto-detect language from text |
| `emotion` | AnimaleseEmotion | null | Default emotion modifier |
| `mix_rate` | int | 44100 | Audio sample rate (Hz) |
| `threaded_synthesis` | bool | true | Use background thread |
| `enable_cache` | bool | true | Cache synthesized audio |

#### Methods

```gdscript
# Basic speech
func speak(text: String, pitch_mul: float = 1.0) -> void

# Speech for specific character from library
func speak_for(character_id: StringName, text: String, pitch_mul: float = 1.0) -> void

# Speech with emotion
func speak_with_emotion(text: String, emotion_or_name: Variant, pitch_mul: float = 1.0) -> void

# Speech with markup tags
func speak_markup(text: String, base_pitch_mul: float = 1.0) -> void

# Stop all speech
func stop_all() -> void

# Get audio samples (for visualization)
func synthesize_to_buffer(text: String, pitch_mul: float = 1.0, override_voice: AnimaleseVoice = null) -> PackedFloat32Array

# Export to WAV file
func export_to_wav(text: String, path: String, pitch_mul: float = 1.0, override_voice: AnimaleseVoice = null) -> Error

# Blend two voices
static func blend_voices(voice_a: AnimaleseVoice, voice_b: AnimaleseVoice, factor: float) -> AnimaleseVoice

# Get viseme track for lip-sync
func get_viseme_track(text: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Array[VisemeMarker]

# Create animation from visemes
func create_viseme_animation(text: String, property_path: String, pitch_mul: float = 1.0, v: AnimaleseVoice = null) -> Animation
```

#### Signals

```gdscript
signal phoneme_started(phoneme: String, index: int)  # Fired for each phoneme
signal word_started(word: String, index: int)        # Fired for each word
signal speech_progress(ratio: float)                  # 0.0 to 1.0 progress
signal speech_finished()                              # Speech completed
signal viseme_changed(viseme: int, weight: float)    # For real-time lip-sync
```

### AnimaleseVoice (Resource)

Voice configuration resource with the following key properties:

| Property | Range | Description |
|----------|-------|-------------|
| `voice_name` | String | Display name |
| `pitch_base_hz` | 80-600 | Base frequency |
| `pitch_jitter` | 0-0.25 | Random pitch variation |
| `char_duration_s` | 0.02-0.12 | Duration per character |
| `output_gain` | 0-2 | Volume |
| `breath_noise_level` | 0-1.5 | Breathiness |
| `whisper_amount` | 0-1 | Whisper mix (0=voiced, 1=whisper) |
| `vibrato_rate_hz` | 0-12 | Vibrato speed |
| `vibrato_depth` | 0-1 | Vibrato intensity |
| `prosody_strength` | 0-1 | Intonation strength |

### AnimaleseEmotion (Resource)

Emotion modifier with multipliers and offsets:

```gdscript
# Built-in emotions
AnimaleseEmotion.neutral()
AnimaleseEmotion.happy()
AnimaleseEmotion.sad()
AnimaleseEmotion.angry()
AnimaleseEmotion.scared()
AnimaleseEmotion.nervous()
AnimaleseEmotion.excited()
AnimaleseEmotion.tired()
AnimaleseEmotion.whisper()
AnimaleseEmotion.mysterious()

# Get by name
var emo = AnimaleseEmotion.get_by_name("happy")

# Blend emotions
var mixed = emotion_a.blend_with(emotion_b, 0.5)
```

## Markup Tags

Use `speak_markup()` for inline control:

```gdscript
# Pause
$Animalese.speak_markup("Hello...[pause:0.5]...world!")

# Pitch modifier
$Animalese.speak_markup("[pitch:1.3]Higher pitch![/pitch] Normal pitch.")

# Speed modifier
$Animalese.speak_markup("[speed:0.7]Slower speech[/speed] normal speed")

# Voice from library
$Animalese.speak_markup("[voice:villain]Ha ha ha![/voice]")

# Emotion
$Animalese.speak_markup("[emotion:angry]I'm so mad![/emotion]")

# Nested tags
$Animalese.speak_markup("[pitch:1.2][emotion:happy]So exciting![/emotion][/pitch]")
```

## Lip-Sync

### Real-time (Signals)

```gdscript
func _ready():
    $Animalese.viseme_changed.connect(_on_viseme)
    $Animalese.speak("Hello!")

func _on_viseme(viseme: int, weight: float):
    $Mouth.frame = viseme  # For Sprite2D with viseme frames
```

### Pre-baked Animation

```gdscript
# Create animation for Sprite2D.frame
var anim = $Animalese.create_viseme_animation("Hello world!", "Mouth:frame")
$AnimationPlayer.add_animation("talk", anim)
$AnimationPlayer.play("talk")
$Animalese.speak("Hello world!")

# For 3D blend shapes
var anim3d = $Animalese.create_viseme_blend_shape_animation(
    "Hello!",
    "Character/Head",
    "viseme_"  # Creates tracks for viseme_SILENT, viseme_AA, etc.
)
```

### Viseme List

| Index | Name | Mouth Shape |
|-------|------|-------------|
| 0 | SILENT | Closed |
| 1 | AA | Open (A) |
| 2 | EE | Wide (E, I) |
| 3 | OO | Round (O, U) |
| 4 | OH | Partially open |
| 5 | FF | Teeth on lip (F, V) |
| 6 | TH | Tongue out (TH, D, T) |
| 7 | SS | Teeth together (S, Z) |
| 8 | NN | Slightly open (N, L, R) |
| 9 | CH | Lips forward (CH, SH) |

## Multi-Language Support

### Manual Language Selection

```gdscript
# Set language processor
$Animalese.language = EnglishProcessor.new()
$Animalese.language = SpanishProcessor.new()
$Animalese.language = JapaneseProcessor.new()
$Animalese.language = FrenchProcessor.new()
$Animalese.language = GermanProcessor.new()
$Animalese.language = PortugueseProcessor.new()
$Animalese.language = ItalianProcessor.new()
$Animalese.language = RussianProcessor.new()
$Animalese.language = ChineseProcessor.new()
```

### Auto-Detection

```gdscript
# Enable auto-detection
$Animalese.auto_detect_language = true
$Animalese.speak("Bonjour!")  # Detected as French
$Animalese.speak("Hola!")     # Detected as Spanish

# Manual detection
var lang_code = $Animalese.detect_language("Guten Tag!")  # Returns "de"
```

## Voice Library (Multiple Characters)

```gdscript
# In editor: Create AnimaleseVoiceLibrary resource
# Add AnimaleseVoiceEntry for each character

# In code:
$Animalese.voice_library = preload("res://voices/characters.tres")
$Animalese.speak_for(&"hero", "I will save the day!")
$Animalese.speak_for(&"villain", "You cannot stop me!")
```

## Dialogic 2 Integration

```gdscript
# Add DialogicAnimalese node to your scene
# Map Dialogic characters to voices:

$DialogicAnimalese.character_voices = {
    "hero": preload("res://voices/hero.tres"),
    "npc": preload("res://voices/npc.tres")
}

# Optional: Map to emotions
$DialogicAnimalese.character_emotions = {
    "hero": AnimaleseEmotion.happy(),
    "npc": AnimaleseEmotion.neutral()
}

# Animalese will automatically play when Dialogic shows text
```

## Creating Custom Voices

### Using the Editor Dock

1. Click "New..." in the Voice Editor dock
2. Follow the wizard to set pitch, timing, and character
3. Save to a `.tres` file

### Programmatically

```gdscript
var voice = AnimaleseVoice.new()
voice.voice_name = "My Custom Voice"
voice.pitch_base_hz = 200.0
voice.pitch_jitter = 0.08
voice.char_duration_s = 0.05
voice.vibrato_rate_hz = 4.0
voice.vibrato_depth = 0.1
voice.breath_noise_level = 0.2

ResourceSaver.save(voice, "res://voices/custom.tres")
```

### Blending Voices

```gdscript
var voice_a = preload("res://presets/voice_masculine.tres")
var voice_b = preload("res://presets/voice_feminine.tres")

# 50% blend
var blended = ProceduralAnimalese.blend_voices(voice_a, voice_b, 0.5)
$Animalese.voice = blended
```

## Export to WAV

```gdscript
var error = $Animalese.export_to_wav(
    "Hello world!",
    "res://audio/hello.wav",
    1.0,  # pitch multiplier
    null  # use default voice
)

if error == OK:
    print("WAV exported successfully!")
```

## Performance Tips

1. **Enable caching** - Set `enable_cache = true` for repeated phrases
2. **Use threading** - Keep `threaded_synthesis = true` for non-blocking synthesis
3. **Reuse voices** - Load voice resources once and reuse them
4. **Seed for consistency** - Set `random_seed` on voice for reproducible output

## File Structure

```
procedural_animalese/
├── runtime/
│   ├── procedural_animalese.gd    # Main synthesizer
│   ├── animalese_voice.gd         # Voice resource
│   ├── animalese_emotion.gd       # Emotion resource
│   ├── animalese_voice_library.gd # Voice collection
│   ├── animalese_voice_entry.gd   # Library entry
│   ├── language_processor.gd      # Base language class
│   ├── language_detector.gd       # Auto language detection
│   └── [language]_processor.gd    # Language-specific processors
├── integrations/
│   └── dialogic_integration.gd    # Dialogic 2 support
├── presets/                       # Voice presets (.tres)
├── locale/                        # Translation files
│   ├── procedural_animalese.pot   # Template
│   └── procedural_animalese.es.po # Spanish
├── voice_editor_dock.gd           # Editor dock UI
├── voice_wizard.gd                # Voice creation wizard
├── voice_preset_browser.gd        # Preset browser dialog
└── procedural_animalese_editor_plugin.gd
```

## Localization

The editor UI supports localization. Translation files are in `locale/`:
- `procedural_animalese.pot` - Template
- `procedural_animalese.es.po` - Spanish

To add a new language, copy the `.pot` file to `procedural_animalese.XX.po` and translate.

## License

MIT License - See LICENSE file for details.

## Credits

Created by Víctor Gil - Monogatete Interactive
