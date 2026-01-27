## Portuguese language processor for ProceduralAnimalese.
## Handles Portuguese (Brazilian/European) text normalization and CV syllable tokenization.
extends LanguageProcessor
class_name PortugueseProcessor

func _init() -> void:
	language_name = "Português"

func get_language_code() -> String:
	return "pt"

## Normalize Portuguese text: handle accents, digraphs, nasal vowels.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Accents
	s = s.replace("á", "a").replace("à", "a").replace("â", "a").replace("ã", "a")
	s = s.replace("é", "e").replace("ê", "e")
	s = s.replace("í", "i")
	s = s.replace("ó", "o").replace("ô", "o").replace("õ", "o")
	s = s.replace("ú", "u").replace("ü", "u")
	s = s.replace("ç", "s")

	# Digraphs
	s = s.replace("lh", "li")    # filho, trabalho -> like Spanish 'll'
	s = s.replace("nh", "ni")    # senhor, minha -> like Spanish 'ñ'
	s = s.replace("ch", "x")     # chave, achar
	s = s.replace("rr", "r")     # carro, terra
	s = s.replace("ss", "s")     # passo, isso
	s = s.replace("qu", "k")     # que, aqui
	s = s.replace("gu", "g")     # guerra, guitarra

	# Vowel combinations
	s = s.replace("ou", "o")     # outro, pouco
	s = s.replace("ei", "e")     # primeiro, leite
	s = s.replace("ai", "ai")    # pai, mais
	s = s.replace("oi", "oi")    # dois, noite
	s = s.replace("au", "au")    # auto, Paulo
	s = s.replace("eu", "eu")    # meu, seu
	s = s.replace("ão", "aun")   # não, são (nasal)
	s = s.replace("ões", "oins") # nações (nasal plural)
	s = s.replace("ãe", "ain")   # mãe, pães

	# Nasal vowels (simplified)
	s = s.replace("am", "an")
	s = s.replace("em", "en")
	s = s.replace("im", "in")
	s = s.replace("om", "on")
	s = s.replace("um", "un")

	# Silent h
	s = s.replace("h", "")

	# Double consonants
	s = s.replace("ll", "l")
	s = s.replace("tt", "t")
	s = s.replace("pp", "p")
	s = s.replace("ff", "f")
	s = s.replace("mm", "m")
	s = s.replace("nn", "n")
	s = s.replace("bb", "b")
	s = s.replace("dd", "d")
	s = s.replace("gg", "g")

	# 'c' rules (like Spanish)
	s = s.replace("ce", "se")
	s = s.replace("ci", "si")

	# 'x' has various sounds in Portuguese, simplify to 'x'
	# (already handled)

	return s

## Tokenize Portuguese text using CV syllable structure.
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
			# Coda consonants (similar to Spanish)
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

## Check if consonant commonly appears in coda position in Portuguese.
func _is_coda_consonant(ch: String) -> bool:
	return ch == "n" or ch == "m" or ch == "r" or ch == "l" or ch == "s" or ch == "x"
