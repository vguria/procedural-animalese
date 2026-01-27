## German language processor for ProceduralAnimalese.
## Handles German text normalization and CV syllable tokenization.
extends LanguageProcessor
class_name GermanProcessor

func _init() -> void:
	language_name = "Deutsch"

func get_language_code() -> String:
	return "de"

## Normalize German text: handle umlauts, ß, digraphs, compound consonants.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Umlauts
	s = s.replace("ä", "e")      # Mädchen -> Medchen
	s = s.replace("ö", "e")      # schön -> schen
	s = s.replace("ü", "u")      # für -> fur
	s = s.replace("ß", "s")      # Straße -> Strase

	# Common German digraphs and combinations
	s = s.replace("sch", "x")    # schön, Schule
	s = s.replace("tsch", "x")   # Deutsch, tschüss
	s = s.replace("ch", "x")     # ich, auch, Buch
	s = s.replace("ck", "k")     # Glück, Stück
	s = s.replace("ph", "f")     # Philosophie
	s = s.replace("th", "t")     # Theater, Thema
	s = s.replace("qu", "kv")    # Quelle, Quatsch

	# Vowel combinations
	s = s.replace("ie", "i")     # die, sie, wie
	s = s.replace("ei", "ai")    # ein, mein, dein
	s = s.replace("eu", "oi")    # heute, Leute
	s = s.replace("äu", "oi")    # Häuser, Bäume
	s = s.replace("au", "au")    # auch, Haus

	# Double consonants (simplify)
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
	s = s.replace("zz", "z")

	# German 'z' is pronounced 'ts'
	s = s.replace("z", "ts")

	# 'v' often pronounced as 'f' in German
	s = s.replace("v", "f")

	# 'w' pronounced as 'v'
	s = s.replace("w", "v")

	# 'j' pronounced as 'y'
	s = s.replace("j", "y")

	# Silent 'h' after vowels (lengthening)
	s = s.replace("ah", "a")
	s = s.replace("eh", "e")
	s = s.replace("ih", "i")
	s = s.replace("oh", "o")
	s = s.replace("uh", "u")

	return s

## Tokenize German text using CV syllable structure.
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

		# Handle 'ts' as single consonant unit
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
			# German has many coda consonants
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

## Check if consonant commonly appears in coda position in German.
func _is_coda_consonant(ch: String) -> bool:
	# German allows many consonant clusters in coda
	return ch == "n" or ch == "m" or ch == "r" or ch == "l" or ch == "s" or ch == "t" or ch == "k" or ch == "p" or ch == "f" or ch == "x"
