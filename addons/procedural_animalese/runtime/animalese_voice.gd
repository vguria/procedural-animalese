## Perfil de voz para ProceduralAnimalese: tono, ritmo, formantes y prosodia.
extends Resource
class_name AnimaleseVoice

## Identidad basica del preset.
@export_group("Identidad")
@export var voice_name: String = "Default" # Nombre del preset en el editor.

## Ritmo y tono base de la voz.
@export_group("Ritmo y tono")
@export_range(80.0, 600.0, 1.0) var pitch_base_hz: float = 220.0 # Frecuencia base (Hz).
@export_range(0.0, 0.25, 0.005) var pitch_jitter: float = 0.06 # Variacion aleatoria del tono por fonema.
@export_range(0.02, 0.12, 0.001) var char_duration_s: float = 0.055 # Duracion base por caracter (s).
@export_range(0.3, 1.2, 0.01) var consonant_duration_multiplier: float = 0.75 # Multiplicador de duracion para consonantes.

## Vibrato: oscilacion periodica del tono.
@export_group("Vibrato")
@export_range(0.0, 12.0, 0.1) var vibrato_rate_hz: float = 0.0 # Frecuencia del vibrato (0 = desactivado).
@export_range(0.0, 1.0, 0.01) var vibrato_depth: float = 0.0 # Profundidad del vibrato (0-1, afecta al pitch).
@export_range(0.0, 1.0, 0.01) var vibrato_delay: float = 0.3 # Delay antes de que empiece el vibrato (0-1, fraccion del fonema).
## Mezcla y caracter del timbre.

@export_group("Mezcla y carácter")
@export_range(0.0, 2.0, 0.01) var output_gain: float = 0.9 # Ganancia global de salida.
@export_range(0.0, 1.5, 0.01) var breath_noise_level: float = 0.15 # Nivel de ruido de aire.
@export_range(0.0, 1.0, 0.01) var whisper_amount: float = 0.0 # Cantidad de susurro (0 = voz normal, 1 = susurro completo).

@export_range(0.5, 2.0, 0.01) var vocal_tract_scale: float = 1.0 # Escala del tracto vocal (afecta formantes).
@export_range(0.0, 2.0, 0.01) var vowel_formant_gain: float = 1.0 # Ganancia de formantes en vocales.
@export_range(0.0, 2.0, 0.01) var fricative_formant_gain: float = 1.0 # Ganancia de formantes en fricativas.
@export_range(0.0, 2.0, 0.01) var stop_formant_gain: float = 1.0 # Ganancia de formantes en oclusivas.
@export_range(0.0, 2.0, 0.01) var nasal_formant_gain: float = 1.0 # Ganancia de formantes en nasales.
## Controles de prosodia y brillo.

@export_group("Expresividad")
@export_range(0.0, 1.0, 0.01) var prosody_strength: float = 0.6 # Intensidad global de la prosodia.
@export_range(0.0, 1.0, 0.01) var question_rise: float = 0.35 # Subida de tono en preguntas.
@export_range(0.0, 1.0, 0.01) var statement_fall: float = 0.15 # Caida de tono en enunciados.
@export_range(0.0, 1.0, 0.01) var exclamation_boost: float = 0.25 # Aumento de energia en exclamaciones.
@export_range(0.0, 1.0, 0.01) var vowel_breathiness: float = 0.10 # Ruido extra en vocales.
@export_range(0.0, 1.0, 0.01) var voiced_brightness: float = 0.55 # Brillo del voiced (filtro pasa-bajos).
## Envolvente ADSR para cada fonema.
@export_group("Envolvente")
@export_range(0.01, 0.5, 0.01) var envelope_attack: float = 0.10 # Fraccion del fonema para attack (0-1).
@export_range(0.1, 1.0, 0.01) var envelope_sustain: float = 0.65 # Nivel de sustain (0-1).
@export_range(0.01, 0.5, 0.01) var envelope_release: float = 0.20 # Fraccion del fonema para release (0-1).

## Coarticulacion: suaviza transiciones entre fonemas.
@export_group("Coarticulacion")
@export_range(0.0, 1.0, 0.01) var coarticulation_strength: float = 0.0 # Intensidad de interpolacion entre fonemas (0 = desactivado).
@export_range(0.05, 0.4, 0.01) var coarticulation_window: float = 0.15 # Fraccion del fonema para la transicion (0-1).

## Suavizado de bordes para evitar clicks.
@export_group("Suavizado")
@export_range(0.0, 20.0, 0.5) var segment_edge_fade_ms: float = 4.0 # Tiempo de fade in/out en ms.
## Control de aleatoriedad.

@export_group("Reproducibilidad")
@export var random_seed: int = 0 # Semilla fija (0 = aleatorio).

## Formantes: Vector3(freq_hz, Q, amp). freq_hz en Hz, Q ancho de banda, amp ganancia.
## Formantes principales de vocales (F1/F2/F3).
@export_group("Formantes - Vocales")
@export var vowel_a_formants: Array[Vector3] = [Vector3(800, 7.0, 1.00), Vector3(1150, 8.0, 0.55), Vector3(2900, 10.0, 0.25)] # Vocal "a".
@export var vowel_e_formants: Array[Vector3] = [Vector3(400, 6.0, 1.00), Vector3(1700, 9.0, 0.50), Vector3(2600, 10.0, 0.22)] # Vocal "e".
@export var vowel_i_formants: Array[Vector3] = [Vector3(300, 6.0, 1.00), Vector3(2200, 10.0, 0.45), Vector3(3000, 10.0, 0.20)] # Vocal "i".
@export var vowel_o_formants: Array[Vector3] = [Vector3(500, 7.0, 1.00), Vector3(900, 8.0, 0.55), Vector3(2600, 10.0, 0.20)] # Vocal "o".
@export var vowel_u_formants: Array[Vector3] = [Vector3(350, 6.0, 1.00), Vector3(600, 7.0, 0.60), Vector3(2700, 10.0, 0.18)] # Vocal "u".
## Formantes para fricativas.

@export_group("Formantes - Fricativas")
@export var fricative_s_formants: Array[Vector3] = [Vector3(4500, 3.5, 0.80), Vector3(6500, 2.5, 0.60), Vector3(2500, 2.0, 0.25)] # Fricativa "s".
@export var fricative_f_formants: Array[Vector3] = [Vector3(1800, 2.2, 0.55), Vector3(3200, 2.0, 0.45), Vector3(5000, 1.8, 0.30)] # Fricativa "f".
@export var fricative_x_formants: Array[Vector3] = [Vector3(2400, 2.5, 0.55), Vector3(3800, 2.2, 0.45), Vector3(5200, 2.0, 0.30)] # Fricativa "x" (j/ch).
## Formantes para oclusivas.

@export_group("Formantes - Oclusivas")
@export var stop_p_formants: Array[Vector3] = [Vector3(1200, 2.0, 0.45), Vector3(2500, 2.0, 0.35), Vector3(4000, 2.0, 0.25)] # Oclusiva "p".
@export var stop_t_formants: Array[Vector3] = [Vector3(1600, 2.0, 0.45), Vector3(3200, 2.0, 0.35), Vector3(5200, 2.0, 0.25)] # Oclusiva "t".
@export var stop_k_formants: Array[Vector3] = [Vector3(2000, 2.0, 0.45), Vector3(3500, 2.0, 0.35), Vector3(6000, 2.0, 0.25)] # Oclusiva "k".
## Formantes para nasales.

@export_group("Formantes - Nasales")
@export var nasal_mn_formants: Array[Vector3] = [Vector3(300, 4.5, 0.95), Vector3(900, 6.0, 0.35), Vector3(2200, 8.0, 0.18)] # Nasal "m/n".

## Formantes extendidos opcionales (F4/F5) para más brillo y realismo.
## Solo se usan si use_extended_formants está activado en ProceduralAnimalese.
@export_group("Formantes Extendidos")
@export var extended_f4: Vector3 = Vector3(3500, 12.0, 0.12) # F4: brillo alto (~3500 Hz).
@export var extended_f5: Vector3 = Vector3(4500, 14.0, 0.08) # F5: brillo muy alto (~4500 Hz).
