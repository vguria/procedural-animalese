extends Resource
class_name AnimaleseVoiceLibrary

@export var entries: Array[AnimaleseVoiceEntry] = []

func get_voice(character_id: StringName) -> AnimaleseVoice:
	for e: AnimaleseVoiceEntry in entries:
		if e != null and e.character_id == character_id and e.voice != null:
			return e.voice
	return null
