## Italian language processor for ProceduralAnimalese.
## Handles Italian text normalization and CV syllable tokenization.
## Italian has very regular phonetics, ideal for Animalese.
extends LanguageProcessor
class_name ItalianProcessor

func _init() -> void:
	language_name = "Italiano"

func get_language_code() -> String:
	return "it"

## Normalize Italian text: handle accents, digraphs, double consonants.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Accents (Italian uses grave and acute)
	s = s.replace("à", "a")
	s = s.replace("è", "e").replace("é", "e")
	s = s.replace("ì", "i").replace("í", "i")
	s = s.replace("ò", "o").replace("ó", "o")
	s = s.replace("ù", "u").replace("ú", "u")

	# Italian digraphs
	s = s.replace("gli", "li")   # famiglia, figlio (palatal l)
	s = s.replace("gn", "ni")    # gnocchi, signora (like Spanish ñ)
	s = s.replace("sci", "xi")   # scienza, pesce
	s = s.replace("sce", "xe")   # scena, scendere
	s = s.replace("chi", "ki")   # che, chi
	s = s.replace("che", "ke")
	s = s.replace("ghi", "gi")   # ghiaccio, luoghi
	s = s.replace("ghe", "ge")   # spaghetti, margherita

	# 'c' and 'g' before e/i are soft
	s = s.replace("ce", "xe")    # cena, voce
	s = s.replace("ci", "xi")    # cinema, città
	s = s.replace("ge", "je")    # gente, gelato
	s = s.replace("gi", "ji")    # giorno, già

	# 'qu' -> 'ku'
	s = s.replace("qu", "ku")

	# Double consonants are important in Italian but simplify for Animalese
	s = s.replace("zz", "ts")    # pizza, palazzo
	s = s.replace("tt", "t")
	s = s.replace("ll", "l")
	s = s.replace("ss", "s")
	s = s.replace("ff", "f")
	s = s.replace("pp", "p")
	s = s.replace("mm", "m")
	s = s.replace("nn", "n")
	s = s.replace("rr", "r")
	s = s.replace("bb", "b")
	s = s.replace("dd", "d")
	s = s.replace("gg", "g")
	s = s.replace("cc", "k")

	# 'z' can be 'ts' or 'dz', simplify to 'ts'
	s = s.replace("z", "ts")

	# 'h' is always silent in Italian
	s = s.replace("h", "")

	return s

## Tokenize Italian text using CV syllable structure.
## Italian has very regular CV structure, making it ideal for Animalese.
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

		# Handle 'ts' (from 'z') as single unit
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
			# Italian rarely has coda consonants except n, r, l
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

## Check if consonant commonly appears in coda position in Italian.
func _is_coda_consonant(ch: String) -> bool:
	# Italian words rarely end in consonants except foreign words
	return ch == "n" or ch == "r" or ch == "l" or ch == "m"
