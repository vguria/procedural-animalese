## Emotional modifier for ProceduralAnimalese.
## Applies multipliers and offsets to voice parameters to express emotions.
extends Resource
class_name AnimaleseEmotion

## Name of the emotion, used from markup and code lookups.
@export var emotion_name: String = "neutral"

## Base-parameter multipliers.
## Values > 1.0 boost, < 1.0 reduce, 1.0 = no change.
@export_group("Multipliers")
@export_range(0.5, 2.0, 0.01) var pitch_mul: float = 1.0 ## Base pitch multiplier.
@export_range(0.5, 2.0, 0.01) var speed_mul: float = 1.0 ## Speed multiplier (higher = faster).
@export_range(0.5, 2.0, 0.01) var volume_mul: float = 1.0 ## Volume multiplier.
@export_range(0.0, 3.0, 0.01) var vibrato_mul: float = 1.0 ## Vibrato intensity multiplier.
@export_range(0.5, 3.0, 0.01) var jitter_mul: float = 1.0 ## Pitch-jitter multiplier.
@export_range(0.5, 2.0, 0.01) var prosody_mul: float = 1.0 ## Prosody intensity multiplier.

## Additive offsets (added to the base value).
@export_group("Offsets")
@export_range(-0.5, 0.5, 0.01) var breathiness_add: float = 0.0 ## Extra breath noise.
@export_range(-0.3, 0.3, 0.01) var brightness_add: float = 0.0 ## Extra brightness (filter).
@export_range(0.0, 1.0, 0.01) var whisper_add: float = 0.0 ## Extra whisper amount (0-1).

## Emotional-vibrato parameters (applied when > 0).
## Useful for emotions that introduce vibrato where the base voice had none.
@export_group("Emotional vibrato")
@export_range(0.0, 8.0, 0.1) var vibrato_rate_override: float = 0.0 ## Vibrato frequency (0 = keep the voice's own).
@export_range(0.0, 0.5, 0.01) var vibrato_depth_override: float = 0.0 ## Vibrato depth (0 = keep the voice's own).

## Emotion intensity (0-1). Interpolates from neutral to full expression.
@export_group("Intensity")
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0 ## 0 = neutral, 1 = full emotion.


## Apply this emotion to a serialized voice-params Dictionary and return a
## modified copy. The original is not mutated.
func apply_to_voice_params(params: Dictionary) -> Dictionary:
	var result: Dictionary = params.duplicate()
	var t: float = intensity

	result["pitch_base_hz"] = params.get("pitch_base_hz", 220.0) * lerpf(1.0, pitch_mul, t)
	result["char_duration_s"] = params.get("char_duration_s", 0.055) / lerpf(1.0, speed_mul, t)
	result["output_gain"] = params.get("output_gain", 0.9) * lerpf(1.0, volume_mul, t)
	result["pitch_jitter"] = params.get("pitch_jitter", 0.06) * lerpf(1.0, jitter_mul, t)
	result["prosody_strength"] = params.get("prosody_strength", 0.6) * lerpf(1.0, prosody_mul, t)

	result["breath_noise_level"] = clampf(params.get("breath_noise_level", 0.15) + breathiness_add * t, 0.0, 1.5)
	result["voiced_brightness"] = clampf(params.get("voiced_brightness", 0.55) + brightness_add * t, 0.0, 1.0)
	result["whisper_amount"] = clampf(params.get("whisper_amount", 0.0) + whisper_add * t, 0.0, 1.0)

	var base_vib_rate: float = params.get("vibrato_rate_hz", 0.0)
	var base_vib_depth: float = params.get("vibrato_depth", 0.0)

	if vibrato_rate_override > 0.0 and base_vib_rate == 0.0:
		# Introduce vibrato where the base voice had none.
		result["vibrato_rate_hz"] = vibrato_rate_override * t
		result["vibrato_depth"] = vibrato_depth_override * t
	else:
		# Scale the existing vibrato.
		result["vibrato_rate_hz"] = base_vib_rate * lerpf(1.0, vibrato_mul, t)
		result["vibrato_depth"] = base_vib_depth * lerpf(1.0, vibrato_mul, t)

	return result


## Blend this emotion with another and return a new emotion.
## factor 0.0 = this emotion, 1.0 = the other emotion.
func blend_with(other: AnimaleseEmotion, factor: float) -> AnimaleseEmotion:
	if other == null:
		push_warning("AnimaleseEmotion.blend_with(): other emotion is null, returning copy of this emotion.")
		return self.duplicate()

	var result := AnimaleseEmotion.new()
	result.emotion_name = emotion_name if factor < 0.5 else other.emotion_name

	result.pitch_mul = lerpf(pitch_mul, other.pitch_mul, factor)
	result.speed_mul = lerpf(speed_mul, other.speed_mul, factor)
	result.volume_mul = lerpf(volume_mul, other.volume_mul, factor)
	result.vibrato_mul = lerpf(vibrato_mul, other.vibrato_mul, factor)
	result.jitter_mul = lerpf(jitter_mul, other.jitter_mul, factor)
	result.prosody_mul = lerpf(prosody_mul, other.prosody_mul, factor)

	result.breathiness_add = lerpf(breathiness_add, other.breathiness_add, factor)
	result.brightness_add = lerpf(brightness_add, other.brightness_add, factor)
	result.whisper_add = lerpf(whisper_add, other.whisper_add, factor)

	result.vibrato_rate_override = lerpf(vibrato_rate_override, other.vibrato_rate_override, factor)
	result.vibrato_depth_override = lerpf(vibrato_depth_override, other.vibrato_depth_override, factor)

	result.intensity = lerpf(intensity, other.intensity, factor)

	return result


# ==================== STATIC PRESETS ====================

## Neutral emotion (no modifications).
static func neutral() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "neutral"
	return e


## Happy emotion: higher pitch, faster, energetic.
static func happy() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "happy"
	e.pitch_mul = 1.15
	e.speed_mul = 1.2
	e.volume_mul = 1.1
	e.jitter_mul = 1.3
	e.prosody_mul = 1.4
	e.brightness_add = 0.1
	return e


## Sad emotion: lower pitch, slower, dampened.
static func sad() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "sad"
	e.pitch_mul = 0.85
	e.speed_mul = 0.7
	e.volume_mul = 0.8
	e.jitter_mul = 0.7
	e.prosody_mul = 0.5
	e.breathiness_add = 0.1
	e.brightness_add = -0.15
	return e


## Angry emotion: lower pitch, louder, aggressive.
static func angry() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "angry"
	e.pitch_mul = 0.9
	e.speed_mul = 1.1
	e.volume_mul = 1.3
	e.jitter_mul = 1.5
	e.prosody_mul = 1.6
	e.brightness_add = 0.15
	e.vibrato_rate_override = 6.0
	e.vibrato_depth_override = 0.15
	return e


## Scared emotion: high pitch, trembling, broken.
static func scared() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "scared"
	e.pitch_mul = 1.2
	e.speed_mul = 1.3
	e.volume_mul = 0.85
	e.jitter_mul = 2.0
	e.prosody_mul = 1.3
	e.breathiness_add = 0.2
	e.vibrato_rate_override = 7.0
	e.vibrato_depth_override = 0.25
	return e


## Nervous emotion: fast, trembling, variable.
static func nervous() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "nervous"
	e.pitch_mul = 1.1
	e.speed_mul = 1.25
	e.volume_mul = 0.95
	e.jitter_mul = 1.8
	e.prosody_mul = 1.2
	e.breathiness_add = 0.15
	e.vibrato_rate_override = 5.0
	e.vibrato_depth_override = 0.12
	return e


## Excited emotion: very fast, high pitch, energetic.
static func excited() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "excited"
	e.pitch_mul = 1.25
	e.speed_mul = 1.4
	e.volume_mul = 1.2
	e.jitter_mul = 1.4
	e.prosody_mul = 1.8
	e.brightness_add = 0.15
	e.vibrato_rate_override = 4.0
	e.vibrato_depth_override = 0.1
	return e


## Tired / bored emotion: very slow, monotone, dampened.
static func tired() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "tired"
	e.pitch_mul = 0.9
	e.speed_mul = 0.6
	e.volume_mul = 0.75
	e.jitter_mul = 0.5
	e.prosody_mul = 0.3
	e.breathiness_add = 0.2
	e.brightness_add = -0.2
	return e


## Whispered emotion: hushed, intimate.
static func whisper() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "whisper"
	e.pitch_mul = 1.05
	e.speed_mul = 0.85
	e.volume_mul = 0.7
	e.jitter_mul = 0.6
	e.prosody_mul = 0.4
	e.breathiness_add = 0.25
	e.brightness_add = -0.1
	e.whisper_add = 1.0  # Full whisper.
	return e


## Mysterious emotion: partial whisper, slow, mysterious.
static func mysterious() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "mysterious"
	e.pitch_mul = 0.95
	e.speed_mul = 0.75
	e.volume_mul = 0.8
	e.jitter_mul = 0.7
	e.prosody_mul = 0.5
	e.breathiness_add = 0.15
	e.brightness_add = -0.15
	e.whisper_add = 0.5  # Half whisper.
	return e


## Look up an emotion by name.
static func get_by_name(name: String) -> AnimaleseEmotion:
	match name.to_lower():
		"neutral": return neutral()
		"happy": return happy()
		"sad": return sad()
		"angry": return angry()
		"scared": return scared()
		"nervous": return nervous()
		"excited": return excited()
		"tired": return tired()
		"whisper": return whisper()
		"mysterious": return mysterious()
		_: return neutral()
