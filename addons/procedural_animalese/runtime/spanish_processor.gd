## Spanish language processor for ProceduralAnimalese.
## Handles Spanish text normalization and CV syllable tokenization.
extends LanguageProcessor
class_name SpanishProcessor

func _init() -> void:
	language_name = "Español"

func get_language_code() -> String:
	return "es"

## Normalize Spanish text: remove diacritics, handle digraphs, apply phonetic rules.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Diacríticos
	s = s.replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u").replace("ü", "u")
	s = s.replace("ñ", "n")

	# H muda
	s = s.replace("h", "")

	# Dígrafos
	s = s.replace("ll", "y")
	s = s.replace("rr", "r")
	s = s.replace("ch", "x")

	# Reglas ES básicas
	s = s.replace("que", "ke").replace("qui", "ki")
	s = s.replace("gue", "ge").replace("gui", "gi")  # Elimina u muda
	s = s.replace("ce", "se").replace("ci", "si")
	s = s.replace("ge", "xe").replace("gi", "xi")
	s = s.replace("qu", "k")

	return s

## Tokenize Spanish text using CV (consonant-vowel) syllable structure.
## This produces natural-sounding Animalese for Spanish text.
func tokenize(text: String) -> Array[String]:
	var tokens: Array[String] = []
	var i: int = 0
	var n: int = text.length()

	while i < n:
		var ch: String = text.substr(i, 1)

		# Separadores / puntuación
		if ch == " " or ch == "\t" or ch == "\n":
			tokens.append(" ")
			i += 1
			continue
		if ch == "," or ch == ";" or ch == ":" or ch == "." or ch == "!" or ch == "?":
			tokens.append(ch)
			i += 1
			continue

		# Vocal suelta
		if is_vowel(ch):
			tokens.append(ch)
			i += 1
			# Consonante final (n/m/s) al final de sílaba
			if i < n:
				var c2 := text.substr(i, 1)
				if (c2 == "n" or c2 == "m" or c2 == "s") and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					tokens.append(c2)
					i += 1
			continue

		# Consonante + vocal => sílaba CV
		if i + 1 < n and is_vowel(text.substr(i + 1, 1)):
			var vch := text.substr(i + 1, 1)
			tokens.append(ch + vch)
			i += 2
			# Consonante final (n/m/s)
			if i < n:
				var c3 := text.substr(i, 1)
				if (c3 == "n" or c3 == "m" or c3 == "s") and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					tokens.append(c3)
					i += 1
			continue

		# Fallback: consonante suelta
		tokens.append(ch)
		i += 1

	return tokens
