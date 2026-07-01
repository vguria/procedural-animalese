## Voice profile for ProceduralAnimalese: pitch, timing, formants, and prosody.
extends Resource
class_name AnimaleseVoice

## Preset identity.
@export_group("Identity")
@export var voice_name: String = "Default" # Display name for the preset.

## Base pitch and timing.
@export_group("Pitch and timing")
@export_range(80.0, 600.0, 1.0) var pitch_base_hz: float = 220.0 # Base frequency (Hz).
@export_range(0.0, 0.25, 0.005) var pitch_jitter: float = 0.06 # Random pitch variation per phoneme.
@export_range(0.02, 0.12, 0.001) var char_duration_s: float = 0.055 # Base duration per character (s).
@export_range(0.3, 1.2, 0.01) var consonant_duration_multiplier: float = 0.75 # Duration multiplier for consonants.

## Vibrato: periodic pitch oscillation.
@export_group("Vibrato")
@export_range(0.0, 12.0, 0.1) var vibrato_rate_hz: float = 0.0 # Vibrato frequency (0 = disabled).
@export_range(0.0, 1.0, 0.01) var vibrato_depth: float = 0.0 # Vibrato depth (0-1, affects pitch).
@export_range(0.0, 1.0, 0.01) var vibrato_delay: float = 0.3 # Delay before vibrato kicks in (0-1 of phoneme).

## Mix and timbre character.
@export_group("Mix and character")
@export_range(0.0, 2.0, 0.01) var output_gain: float = 0.9 # Global output gain.
@export_range(0.0, 1.5, 0.01) var breath_noise_level: float = 0.15 # Airy noise level.
@export_range(0.0, 1.0, 0.01) var whisper_amount: float = 0.0 # Whisper mix (0 = normal voice, 1 = full whisper).

@export_range(0.5, 2.0, 0.01) var vocal_tract_scale: float = 1.0 # Vocal tract scale (shifts formants).
@export_range(0.0, 2.0, 0.01) var vowel_formant_gain: float = 1.0 # Formant gain for vowels.
@export_range(0.0, 2.0, 0.01) var fricative_formant_gain: float = 1.0 # Formant gain for fricatives.
@export_range(0.0, 2.0, 0.01) var stop_formant_gain: float = 1.0 # Formant gain for stops.
@export_range(0.0, 2.0, 0.01) var nasal_formant_gain: float = 1.0 # Formant gain for nasals.

## Prosody and brightness controls.
@export_group("Expressivity")
@export_range(0.0, 1.0, 0.01) var prosody_strength: float = 0.6 # Overall prosody intensity.
@export_range(0.0, 1.0, 0.01) var question_rise: float = 0.35 # Pitch rise on questions.
@export_range(0.0, 1.0, 0.01) var statement_fall: float = 0.15 # Pitch fall on statements.
@export_range(0.0, 1.0, 0.01) var exclamation_boost: float = 0.25 # Energy boost on exclamations.
@export_range(0.0, 1.0, 0.01) var vowel_breathiness: float = 0.10 # Extra noise on vowels.
@export_range(0.0, 1.0, 0.01) var voiced_brightness: float = 0.55 # Voiced brightness (low-pass filter).

## ADSR envelope for each phoneme.
@export_group("Envelope")
@export_range(0.01, 0.5, 0.01) var envelope_attack: float = 0.10 # Attack fraction of the phoneme (0-1).
@export_range(0.1, 1.0, 0.01) var envelope_sustain: float = 0.65 # Sustain level (0-1).
@export_range(0.01, 0.5, 0.01) var envelope_release: float = 0.20 # Release fraction of the phoneme (0-1).

## Coarticulation: smooths transitions between phonemes.
@export_group("Coarticulation")
@export_range(0.0, 1.0, 0.01) var coarticulation_strength: float = 0.0 # Interpolation intensity between phonemes (0 = off).
@export_range(0.05, 0.4, 0.01) var coarticulation_window: float = 0.15 # Fraction of the phoneme used for the transition (0-1).

## Edge smoothing to avoid clicks.
@export_group("Smoothing")
@export_range(0.0, 20.0, 0.5) var segment_edge_fade_ms: float = 4.0 # Fade in/out time in ms.

## Randomness control.
@export_group("Reproducibility")
@export var random_seed: int = 0 # Fixed seed (0 = randomize each call).

## Formants: Vector3(freq_hz, Q, amp). freq_hz in Hz, Q is bandwidth, amp is gain.
## Main vowel formants (F1/F2/F3).
@export_group("Formants - Vowels")
@export var vowel_a_formants: Array[Vector3] = [Vector3(800, 7.0, 1.00), Vector3(1150, 8.0, 0.55), Vector3(2900, 10.0, 0.25)] # Vowel "a".
@export var vowel_e_formants: Array[Vector3] = [Vector3(400, 6.0, 1.00), Vector3(1700, 9.0, 0.50), Vector3(2600, 10.0, 0.22)] # Vowel "e".
@export var vowel_i_formants: Array[Vector3] = [Vector3(300, 6.0, 1.00), Vector3(2200, 10.0, 0.45), Vector3(3000, 10.0, 0.20)] # Vowel "i".
@export var vowel_o_formants: Array[Vector3] = [Vector3(500, 7.0, 1.00), Vector3(900, 8.0, 0.55), Vector3(2600, 10.0, 0.20)] # Vowel "o".
@export var vowel_u_formants: Array[Vector3] = [Vector3(350, 6.0, 1.00), Vector3(600, 7.0, 0.60), Vector3(2700, 10.0, 0.18)] # Vowel "u".

## Fricative formants.
@export_group("Formants - Fricatives")
@export var fricative_s_formants: Array[Vector3] = [Vector3(4500, 3.5, 0.80), Vector3(6500, 2.5, 0.60), Vector3(2500, 2.0, 0.25)] # Fricative "s".
@export var fricative_f_formants: Array[Vector3] = [Vector3(1800, 2.2, 0.55), Vector3(3200, 2.0, 0.45), Vector3(5000, 1.8, 0.30)] # Fricative "f".
@export var fricative_x_formants: Array[Vector3] = [Vector3(2400, 2.5, 0.55), Vector3(3800, 2.2, 0.45), Vector3(5200, 2.0, 0.30)] # Fricative "x" (j/ch).

## Stop formants.
@export_group("Formants - Stops")
@export var stop_p_formants: Array[Vector3] = [Vector3(1200, 2.0, 0.45), Vector3(2500, 2.0, 0.35), Vector3(4000, 2.0, 0.25)] # Stop "p".
@export var stop_t_formants: Array[Vector3] = [Vector3(1600, 2.0, 0.45), Vector3(3200, 2.0, 0.35), Vector3(5200, 2.0, 0.25)] # Stop "t".
@export var stop_k_formants: Array[Vector3] = [Vector3(2000, 2.0, 0.45), Vector3(3500, 2.0, 0.35), Vector3(6000, 2.0, 0.25)] # Stop "k".

## Nasal formants.
@export_group("Formants - Nasals")
@export var nasal_mn_formants: Array[Vector3] = [Vector3(300, 4.5, 0.95), Vector3(900, 6.0, 0.35), Vector3(2200, 8.0, 0.18)] # Nasal "m/n".

## Optional extended formants (F4/F5) for extra brightness and realism.
## Only used when use_extended_formants is enabled on ProceduralAnimalese.
@export_group("Extended formants")
@export var extended_f4: Vector3 = Vector3(3500, 12.0, 0.12) # F4: high brightness (~3500 Hz).
@export var extended_f5: Vector3 = Vector3(4500, 14.0, 0.08) # F5: very high brightness (~4500 Hz).
