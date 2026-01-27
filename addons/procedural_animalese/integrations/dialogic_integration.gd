## Integracion opcional con Dialogic 2.
## Reproduce Animalese automaticamente cuando Dialogic muestra texto.
##
## Uso:
## 1. Anade este nodo como hijo de tu nodo Dialogic o escena principal
## 2. Asigna el ProceduralAnimalese en el inspector
## 3. Opcionalmente configura voces por personaje en character_voices
##
## Requiere Dialogic 2 instalado. Si no esta disponible, el nodo se desactiva.
@tool
extends Node
class_name DialogicAnimalese

## El nodo ProceduralAnimalese que reproducira el audio.
@export var animalese: ProceduralAnimalese

## Mapeo de nombre de personaje Dialogic -> AnimaleseVoice.
## Si un personaje no esta en el mapa, usa la voz por defecto.
@export var character_voices: Dictionary = {}

## Mapeo de nombre de personaje -> emocion (String o AnimaleseEmotion).
@export var character_emotions: Dictionary = {}

## Multiplicador de pitch por defecto.
@export var default_pitch: float = 1.0

## Variacion aleatoria de pitch por personaje (para dar variedad).
@export_range(0.0, 0.3, 0.01) var pitch_variation: float = 0.05

## Si true, detecta automaticamente el idioma del texto.
@export var auto_detect_language: bool = true

## Si true, detiene el audio anterior cuando empieza nuevo texto.
@export var stop_on_new_text: bool = true

## Si true, procesa tags de Dialogic para modificar la voz.
@export var process_dialogic_tags: bool = true

# Estado interno
var _dialogic_available: bool = false
var _current_character: String = ""
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_check_dialogic_availability()

	if _dialogic_available:
		_connect_dialogic_signals()


func _check_dialogic_availability() -> void:
	# Verificar si Dialogic esta disponible
	if ClassDB.class_exists("Dialogic"):
		_dialogic_available = true
	elif Engine.has_singleton("Dialogic"):
		_dialogic_available = true
	else:
		# Intentar acceder via script
		var dialogic_script = load("res://addons/dialogic/Core/Dialogic.gd")
		_dialogic_available = (dialogic_script != null)

	if not _dialogic_available:
		push_warning("DialogicAnimalese: Dialogic 2 not found. Integration disabled.")


func _connect_dialogic_signals() -> void:
	# Dialogic 2 usa un singleton accesible via Dialogic
	# Las senales principales son:
	# - signal_event: emitida cuando se procesa un evento
	# - text_signal: cuando se muestra texto
	# - timeline_started / timeline_ended

	# Intentar conectar usando call_deferred para asegurar que Dialogic este listo
	call_deferred("_deferred_connect")


func _deferred_connect() -> void:
	if not _dialogic_available:
		return

	# Acceder al singleton de Dialogic
	var dialogic = _get_dialogic()
	if dialogic == null:
		return

	# Conectar a senales de texto
	if dialogic.has_signal("text_signal"):
		if not dialogic.is_connected("text_signal", _on_dialogic_text):
			dialogic.connect("text_signal", _on_dialogic_text)

	# Conectar a eventos de timeline
	if dialogic.has_signal("timeline_started"):
		if not dialogic.is_connected("timeline_started", _on_timeline_started):
			dialogic.connect("timeline_started", _on_timeline_started)

	if dialogic.has_signal("timeline_ended"):
		if not dialogic.is_connected("timeline_ended", _on_timeline_ended):
			dialogic.connect("timeline_ended", _on_timeline_ended)

	# Dialogic 2.x usa subsistemas, intentar conectar al Text subsystem
	if dialogic.has_method("get_subsystem"):
		var text_subsystem = dialogic.call("get_subsystem", "Text")
		if text_subsystem != null:
			if text_subsystem.has_signal("about_to_show_text"):
				if not text_subsystem.is_connected("about_to_show_text", _on_about_to_show_text):
					text_subsystem.connect("about_to_show_text", _on_about_to_show_text)

			if text_subsystem.has_signal("text_finished"):
				if not text_subsystem.is_connected("text_finished", _on_text_finished):
					text_subsystem.connect("text_finished", _on_text_finished)


func _get_dialogic() -> Node:
	# Intentar obtener Dialogic de varias formas
	if Engine.has_singleton("Dialogic"):
		return Engine.get_singleton("Dialogic")

	# Buscar en el arbol
	var root := get_tree().root if get_tree() != null else null
	if root != null:
		var dialogic := root.get_node_or_null("/root/Dialogic")
		if dialogic != null:
			return dialogic

	return null


func _on_dialogic_text(text: String) -> void:
	_speak_text(text, _current_character)


func _on_about_to_show_text(info: Dictionary) -> void:
	# info contiene: text, character, portrait, etc.
	var text: String = info.get("text", "")
	var character: String = info.get("character", "")

	if character != "":
		_current_character = character

	_speak_text(text, character)


func _on_text_finished() -> void:
	# Opcional: detener audio cuando termina el texto
	pass


func _on_timeline_started() -> void:
	_current_character = ""


func _on_timeline_ended() -> void:
	_current_character = ""
	if animalese != null:
		animalese.stop()


## Reproduce el texto con la voz apropiada para el personaje.
func _speak_text(text: String, character: String) -> void:
	if animalese == null:
		return

	if text.is_empty():
		return

	# Detener audio anterior si esta configurado
	if stop_on_new_text:
		animalese.stop()

	# Limpiar texto de tags de Dialogic si es necesario
	var clean_text: String = _clean_dialogic_text(text) if process_dialogic_tags else text

	if clean_text.is_empty():
		return

	# Obtener voz para el personaje
	var voice: AnimaleseVoice = _get_voice_for_character(character)

	# Obtener emocion para el personaje
	var emotion: Variant = _get_emotion_for_character(character)

	# Calcular pitch con variacion
	var pitch: float = default_pitch
	if pitch_variation > 0.0:
		pitch += _rng.randf_range(-pitch_variation, pitch_variation)

	# Configurar auto-deteccion de idioma
	animalese.auto_detect_language = auto_detect_language

	# Reproducir
	if emotion != null:
		if emotion is AnimaleseEmotion:
			animalese.speak_with_emotion(clean_text, emotion, pitch)
		elif emotion is String:
			animalese.speak_with_emotion(clean_text, emotion, pitch)
	elif voice != null:
		animalese.speak_with_voice(clean_text, voice, pitch)
	else:
		animalese.speak(clean_text, pitch)


func _get_voice_for_character(character: String) -> AnimaleseVoice:
	if character.is_empty():
		return null

	# Buscar en el mapeo de voces
	if character_voices.has(character):
		var voice_entry = character_voices[character]
		if voice_entry is AnimaleseVoice:
			return voice_entry
		elif voice_entry is String:
			# Si es un string, intentar cargar como recurso
			var loaded = load(voice_entry)
			if loaded is AnimaleseVoice:
				return loaded

	# Buscar en la biblioteca de voces del animalese
	if animalese != null and animalese.voice_library != null:
		return animalese.voice_library.get_voice(character)

	return null


func _get_emotion_for_character(character: String) -> Variant:
	if character.is_empty():
		return null

	if character_emotions.has(character):
		return character_emotions[character]

	return null


## Limpia el texto de tags de Dialogic.
func _clean_dialogic_text(text: String) -> String:
	var result: String = text

	# Remover tags BBCode comunes de Dialogic
	var bbcode_regex := RegEx.new()
	bbcode_regex.compile("\\[/?[a-zA-Z_][a-zA-Z0-9_=:.,\\s]*\\]")
	result = bbcode_regex.sub(result, "", true)

	# Remover variables de Dialogic {variable}
	var var_regex := RegEx.new()
	var_regex.compile("\\{[^}]+\\}")
	result = var_regex.sub(result, "", true)

	# Limpiar espacios multiples
	while result.contains("  "):
		result = result.replace("  ", " ")

	return result.strip_edges()


## Asignar voz a un personaje en runtime.
func set_character_voice(character: String, voice: AnimaleseVoice) -> void:
	character_voices[character] = voice


## Asignar emocion a un personaje en runtime.
func set_character_emotion(character: String, emotion: Variant) -> void:
	character_emotions[character] = emotion


## Obtener si Dialogic esta disponible.
func is_dialogic_available() -> bool:
	return _dialogic_available
