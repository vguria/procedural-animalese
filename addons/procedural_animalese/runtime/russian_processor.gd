## Russian language processor for ProceduralAnimalese.
## Handles Russian Cyrillic text, romanizing it for synthesis.
extends LanguageProcessor
class_name RussianProcessor

func _init() -> void:
	language_name = "Русский"

func get_language_code() -> String:
	return "ru"

## Russian vowels (Cyrillic)
func is_vowel(ch: String) -> bool:
	# Both Cyrillic and romanized vowels
	return ch == "a" or ch == "e" or ch == "i" or ch == "o" or ch == "u" or \
		   ch == "а" or ch == "е" or ch == "ё" or ch == "и" or ch == "о" or \
		   ch == "у" or ch == "ы" or ch == "э" or ch == "ю" or ch == "я"

## Normalize Russian text: romanize Cyrillic to Latin equivalents.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Romanization of Russian Cyrillic
	# Vowels
	s = s.replace("а", "a")
	s = s.replace("е", "e")
	s = s.replace("ё", "yo")
	s = s.replace("и", "i")
	s = s.replace("о", "o")
	s = s.replace("у", "u")
	s = s.replace("ы", "i")      # Hard 'i', simplified
	s = s.replace("э", "e")
	s = s.replace("ю", "yu")
	s = s.replace("я", "ya")

	# Consonants
	s = s.replace("б", "b")
	s = s.replace("в", "v")
	s = s.replace("г", "g")
	s = s.replace("д", "d")
	s = s.replace("ж", "x")      # zh sound, use fricative
	s = s.replace("з", "z")
	s = s.replace("й", "y")      # Short i/y
	s = s.replace("к", "k")
	s = s.replace("л", "l")
	s = s.replace("м", "m")
	s = s.replace("н", "n")
	s = s.replace("п", "p")
	s = s.replace("р", "r")
	s = s.replace("с", "s")
	s = s.replace("т", "t")
	s = s.replace("ф", "f")
	s = s.replace("х", "x")      # Kh sound, use fricative
	s = s.replace("ц", "ts")
	s = s.replace("ч", "x")      # Ch sound, use fricative
	s = s.replace("ш", "x")      # Sh sound, use fricative
	s = s.replace("щ", "x")      # Shch sound, use fricative
	s = s.replace("ъ", "")       # Hard sign, silent
	s = s.replace("ь", "")       # Soft sign, silent

	# Process combined vowels after consonant conversions
	s = s.replace("yo", "io")
	s = s.replace("yu", "iu")
	s = s.replace("ya", "ia")

	# Double consonants
	s = s.replace("tt", "t")
	s = s.replace("ss", "s")
	s = s.replace("nn", "n")
	s = s.replace("mm", "m")
	s = s.replace("ll", "l")
	s = s.replace("pp", "p")
	s = s.replace("bb", "b")
	s = s.replace("kk", "k")

	return s

## Tokenize Russian text using CV syllable structure.
func tokenize(text: String) -> Array[String]:
	var tokens: Array[String] = []
	var i: int = 0
	var n: int = text.length()

	while i < n:
		var ch: String = text.substr(i, 1)

		# Whitespace and punctuation
		if ch == " " or ch == "\t" or ch == "\n":
			tokens.append(" ")
			i += 1
			continue
		if ch == "," or ch == ";" or ch == ":" or ch == "." or ch == "!" or ch == "?":
			tokens.append(ch)
			i += 1
			continue

		# Handle 'ts' as single unit
		if ch == "t" and i + 1 < n and text.substr(i + 1, 1) == "s":
			if i + 2 < n and is_vowel(text.substr(i + 2, 1)):
				var vch: String = text.substr(i + 2, 1)
				tokens.append("ts" + vch)
				i += 3
				continue

		# Vowel
		if is_vowel(ch):
			tokens.append(ch)
			i += 1
			# Russian allows many coda consonants
			if i < n:
				var next_ch: String = text.substr(i, 1)
				if _is_coda_consonant(next_ch) and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					tokens.append(next_ch)
					i += 1
			continue

		# Consonant + vowel -> CV syllable
		if i + 1 < n and is_vowel(text.substr(i + 1, 1)):
			var vch: String = text.substr(i + 1, 1)
			tokens.append(ch + vch)
			i += 2
			# Coda consonants
			if i < n:
				var coda: String = text.substr(i, 1)
				if _is_coda_consonant(coda) and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					tokens.append(coda)
					i += 1
			continue

		# Lone consonant
		tokens.append(ch)
		i += 1

	return tokens

## Check if consonant commonly appears in coda position in Russian.
func _is_coda_consonant(ch: String) -> bool:
	# Russian allows complex consonant clusters
	return ch == "n" or ch == "m" or ch == "r" or ch == "l" or ch == "s" or ch == "t" or ch == "k" or ch == "p" or ch == "v" or ch == "f"
