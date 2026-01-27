## French language processor for ProceduralAnimalese.
## Handles French text normalization and CV syllable tokenization.
extends LanguageProcessor
class_name FrenchProcessor

func _init() -> void:
	language_name = "Français"

func get_language_code() -> String:
	return "fr"

## Normalize French text: handle accents, digraphs, nasal vowels, silent letters.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Accents and special characters
	s = s.replace("à", "a").replace("â", "a").replace("ä", "a")
	s = s.replace("é", "e").replace("è", "e").replace("ê", "e").replace("ë", "e")
	s = s.replace("î", "i").replace("ï", "i")
	s = s.replace("ô", "o").replace("ö", "o")
	s = s.replace("ù", "u").replace("û", "u").replace("ü", "u")
	s = s.replace("ÿ", "i")
	s = s.replace("ç", "s")
	s = s.replace("œ", "e").replace("æ", "e")

	# Common French digraphs and combinations
	s = s.replace("eau", "o")    # beau, château
	s = s.replace("aux", "o")    # beaux, châteaux
	s = s.replace("eaux", "o")
	s = s.replace("au", "o")     # aussi, autour
	s = s.replace("ou", "u")     # vous, nous
	s = s.replace("oi", "ua")    # moi, toi -> simplified
	s = s.replace("ai", "e")     # mais, faire
	s = s.replace("ei", "e")     # neige, reine
	s = s.replace("eu", "e")     # peu, deux
	s = s.replace("œu", "e")     # cœur, sœur

	# Nasal vowels (simplified)
	s = s.replace("ain", "en")
	s = s.replace("aim", "en")
	s = s.replace("ein", "en")
	s = s.replace("ien", "ien")
	s = s.replace("oin", "uen")
	s = s.replace("un", "en")
	s = s.replace("an", "an")
	s = s.replace("am", "an")
	s = s.replace("en", "an")
	s = s.replace("em", "an")
	s = s.replace("on", "on")
	s = s.replace("om", "on")

	# Silent letters and endings
	s = s.replace("ent$", "")    # ils parlent -> silent
	s = s.replace("es$", "")     # tables -> silent
	s = s.replace("ed$", "e")
	s = s.replace("et$", "e")

	# Common digraphs
	s = s.replace("ch", "x")     # chat, chose
	s = s.replace("ph", "f")     # photo, philosophie
	s = s.replace("th", "t")     # thé, théâtre
	s = s.replace("gn", "n")     # montagne, campagne
	s = s.replace("qu", "k")     # que, qui
	s = s.replace("gu", "g")     # guerre, guide (before e/i)

	# Double consonants
	s = s.replace("ll", "l")
	s = s.replace("ss", "s")
	s = s.replace("tt", "t")
	s = s.replace("pp", "p")
	s = s.replace("ff", "f")
	s = s.replace("mm", "m")
	s = s.replace("nn", "n")
	s = s.replace("rr", "r")
	s = s.replace("cc", "k")

	# Silent h
	s = s.replace("h", "")

	# 'c' rules
	s = s.replace("ce", "se")
	s = s.replace("ci", "si")
	s = s.replace("cy", "si")

	# Final silent consonants (common ones)
	# These are often silent: d, t, s, x, z, p at end
	# Handled partially in tokenization

	return s

## Tokenize French text using CV syllable structure.
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

		# Vowel
		if is_vowel(ch):
			tokens.append(ch)
			i += 1
			# Coda consonants
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

## Check if consonant commonly appears in coda position in French.
func _is_coda_consonant(ch: String) -> bool:
	return ch == "n" or ch == "m" or ch == "r" or ch == "l" or ch == "s" or ch == "t" or ch == "k"
