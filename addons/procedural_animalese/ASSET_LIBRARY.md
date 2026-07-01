# Asset Library Submission Info

Use this information when submitting to the Godot Asset Library.

## Basic Info

**Asset Name:** Procedural Animalese

**Category:** Tools

**Godot Version:** 4.4+

**License:** MIT

**Repository URL:** (your GitHub URL)

**Download URL:** (your release ZIP URL)

## Short Description (140 chars max)

```
Real-time procedural speech synthesis inspired by Animal Crossing. No audio files needed - generate unique character voices on the fly.
```

## Full Description (Markdown)

```markdown
# Procedural Animalese

Generate unique character voices in real-time without pre-recorded audio, inspired by Animal Crossing's "Animalese" speech style.

## Features

- **Pure Synthesis** - No audio files needed, voices generated procedurally
- **9 Languages** - Spanish, English, Japanese, French, German, Portuguese, Italian, Russian, Chinese
- **10 Emotions** - Happy, sad, angry, scared, nervous, excited, tired, whisper, and more
- **Lip-Sync** - 10 visemes with real-time signals and animation generation
- **Voice Editor** - Full editor dock with waveform visualization
- **Voice Blending** - Mix two voices together
- **Markup Tags** - Inline control for pitch, speed, pauses, emotions
- **Dialogic 2 Integration** - Works with popular dialogue addon

## Quick Start

```gdscript
# Just add a ProceduralAnimalese node and speak!
$ProceduralAnimalese.speak("Hello world!")

# With emotion
$ProceduralAnimalese.speak_with_emotion("I'm happy!", "happy")

# With markup
$ProceduralAnimalese.speak_markup("[pitch:1.2]Exciting![/pitch]")
```

## Included

- 8 voice presets (masculine, feminine, child, robot, monster, ghost, etc.)
- Voice creation wizard
- Voice preset browser
- Interactive demo scene
- Full documentation
- Spanish translation

## Documentation

See the included README.md for complete documentation, API reference, and examples.
```

## Tags

```
audio, speech, synthesis, voice, tts, animalese, animal-crossing, dialogue, lip-sync, viseme, procedural, sound
```

## Screenshots

Take screenshots of:

1. **Editor Dock - Main Tab**
   - Show the Voice Editor dock with a voice loaded
   - Parameters visible, waveform shown
   - File: `screenshots/01_dock_main.png`

2. **Editor Dock - Formants Tab**
   - Show formant editor with sliders
   - Vowel chart visible
   - File: `screenshots/02_dock_formants.png`

3. **Voice Creation Wizard**
   - Show step 2 (Pitch & Timing) with sliders
   - File: `screenshots/03_wizard.png`

4. **Voice Preset Browser**
   - Show grid of voice cards
   - File: `screenshots/04_browser.png`

5. **Demo Scene Running**
   - Show the demo with controls and feedback
   - File: `screenshots/05_demo.png`

### Screenshot Guidelines

- Resolution: 1920x1080 or similar
- Use a clean Godot theme
- Show the plugin in action with a voice loaded
- Crop to relevant area if needed

## Icon

The plugin icon is at `icon.svg` (16x16 scalable).
For Asset Library, export a 128x128 PNG version.

## Folder Structure Verification

```
addons/procedural_animalese/
├── plugin.cfg                 ✓ Plugin metadata
├── LICENSE                    ✓ MIT license
├── README.md                  ✓ Documentation
├── CHANGELOG.md               ✓ Version history
├── icon.svg                   ✓ Plugin icon
├── procedural_animalese_editor_plugin.gd
├── voice_editor_dock.gd
├── voice_wizard.gd
├── voice_preset_browser.gd
├── runtime/
│   ├── procedural_animalese.gd
│   ├── animalese_voice.gd
│   ├── animalese_emotion.gd
│   ├── animalese_voice_library.gd
│   ├── animalese_voice_entry.gd
│   ├── language_processor.gd
│   ├── language_detector.gd
│   ├── spanish_processor.gd
│   ├── english_processor.gd
│   ├── japanese_processor.gd
│   ├── french_processor.gd
│   ├── german_processor.gd
│   ├── portuguese_processor.gd
│   ├── italian_processor.gd
│   ├── russian_processor.gd
│   └── chinese_processor.gd
├── integrations/
│   └── dialogic_integration.gd
├── presets/
│   ├── voice_default.tres
│   ├── voice_masculine.tres
│   ├── voice_feminine.tres
│   ├── voice_child.tres
│   ├── voice_elder.tres
│   ├── voice_robot.tres
│   ├── voice_monster.tres
│   └── voice_ghost.tres
├── locale/
│   ├── procedural_animalese.pot
│   └── procedural_animalese.es.po
└── demo/
    ├── demo.tscn
    └── demo.gd
```

## Pre-submission Checklist

- [ ] Test plugin on clean Godot 4.4+ project
- [ ] Verify all presets load correctly
- [ ] Test demo scene runs without errors
- [ ] Take 5 screenshots
- [ ] Export icon to 128x128 PNG
- [ ] Create GitHub release with ZIP
- [ ] Fill in repository and download URLs
- [ ] Submit to Asset Library
