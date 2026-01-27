## Modificador emocional para ProceduralAnimalese.
## Aplica multiplicadores y offsets a los parametros de voz para expresar emociones.
extends Resource
class_name AnimaleseEmotion

## Nombre de la emocion para identificarla en markup y codigo.
@export var emotion_name: String = "neutral"

## Multiplicadores de parametros base.
## Valores > 1.0 aumentan, < 1.0 reducen, 1.0 = sin cambio.
@export_group("Multiplicadores")
@export_range(0.5, 2.0, 0.01) var pitch_mul: float = 1.0 ## Multiplicador de pitch base.
@export_range(0.5, 2.0, 0.01) var speed_mul: float = 1.0 ## Multiplicador de velocidad (mayor = mas rapido).
@export_range(0.5, 2.0, 0.01) var volume_mul: float = 1.0 ## Multiplicador de volumen.
@export_range(0.0, 3.0, 0.01) var vibrato_mul: float = 1.0 ## Multiplicador de intensidad de vibrato.
@export_range(0.5, 3.0, 0.01) var jitter_mul: float = 1.0 ## Multiplicador de variacion de pitch.
@export_range(0.5, 2.0, 0.01) var prosody_mul: float = 1.0 ## Multiplicador de intensidad de prosodia.

## Offsets aditivos (se suman al valor base).
@export_group("Offsets")
@export_range(-0.5, 0.5, 0.01) var breathiness_add: float = 0.0 ## Ruido de respiracion adicional.
@export_range(-0.3, 0.3, 0.01) var brightness_add: float = 0.0 ## Brillo adicional (filtro).
@export_range(0.0, 1.0, 0.01) var whisper_add: float = 0.0 ## Cantidad de susurro adicional (0-1).

## Parametros de vibrato emocional (se aplican si son > 0).
## Utiles para emociones que introducen vibrato donde no lo habia.
@export_group("Vibrato Emocional")
@export_range(0.0, 8.0, 0.1) var vibrato_rate_override: float = 0.0 ## Frecuencia de vibrato (0 = usar el de voz).
@export_range(0.0, 0.5, 0.01) var vibrato_depth_override: float = 0.0 ## Profundidad de vibrato (0 = usar el de voz).

## Intensidad de la emocion (0-1). Permite mezclar con estado neutral.
@export_group("Intensidad")
@export_range(0.0, 1.0, 0.01) var intensity: float = 1.0 ## 0 = neutral, 1 = emocion completa.


## Aplica esta emocion a los parametros de voz, devolviendo un diccionario con los valores modificados.
## Los parametros originales no se modifican.
func apply_to_voice_params(params: Dictionary) -> Dictionary:
	var result: Dictionary = params.duplicate()
	var t: float = intensity

	# Aplicar multiplicadores interpolando con intensidad
	result["pitch_base_hz"] = params.get("pitch_base_hz", 220.0) * lerpf(1.0, pitch_mul, t)
	result["char_duration_s"] = params.get("char_duration_s", 0.055) / lerpf(1.0, speed_mul, t)
	result["output_gain"] = params.get("output_gain", 0.9) * lerpf(1.0, volume_mul, t)
	result["pitch_jitter"] = params.get("pitch_jitter", 0.06) * lerpf(1.0, jitter_mul, t)
	result["prosody_strength"] = params.get("prosody_strength", 0.6) * lerpf(1.0, prosody_mul, t)

	# Aplicar offsets
	result["breath_noise_level"] = clampf(params.get("breath_noise_level", 0.15) + breathiness_add * t, 0.0, 1.5)
	result["voiced_brightness"] = clampf(params.get("voiced_brightness", 0.55) + brightness_add * t, 0.0, 1.0)
	result["whisper_amount"] = clampf(params.get("whisper_amount", 0.0) + whisper_add * t, 0.0, 1.0)

	# Vibrato: multiplicar existente o usar override
	var base_vib_rate: float = params.get("vibrato_rate_hz", 0.0)
	var base_vib_depth: float = params.get("vibrato_depth", 0.0)

	if vibrato_rate_override > 0.0 and base_vib_rate == 0.0:
		# Introducir vibrato donde no habia
		result["vibrato_rate_hz"] = vibrato_rate_override * t
		result["vibrato_depth"] = vibrato_depth_override * t
	else:
		# Multiplicar vibrato existente
		result["vibrato_rate_hz"] = base_vib_rate * lerpf(1.0, vibrato_mul, t)
		result["vibrato_depth"] = base_vib_depth * lerpf(1.0, vibrato_mul, t)

	return result


## Mezcla esta emocion con otra, devolviendo una nueva emocion.
## factor 0.0 = esta emocion, 1.0 = otra emocion.
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


# ==================== PRESETS ESTATICOS ====================

## Crea una emocion neutral (sin modificaciones).
static func neutral() -> AnimaleseEmotion:
	var e := AnimaleseEmotion.new()
	e.emotion_name = "neutral"
	return e


## Emocion feliz: tono alto, rapido, energico.
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


## Emocion triste: tono bajo, lento, apagado.
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


## Emocion enfadada: tono bajo, fuerte, agresivo.
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


## Emocion asustada: tono alto, tembloroso, entrecortado.
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


## Emocion nerviosa: rapido, tembloroso, variable.
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


## Emocion emocionada/excitada: muy rapido, tono alto, energico.
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


## Emocion cansada/aburrida: muy lento, monotono, apagado.
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


## Emocion susurrada: voz susurrada, intima.
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
	e.whisper_add = 1.0  # Susurro completo
	return e


## Emocion misteriosa: susurro parcial, lento, misterioso.
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
	e.whisper_add = 0.5  # Medio susurro
	return e


## Obtiene una emocion por nombre.
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
