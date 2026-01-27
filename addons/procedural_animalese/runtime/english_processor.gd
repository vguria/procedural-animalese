## English language processor for ProceduralAnimalese.
## Handles English text normalization and syllable tokenization.
extends LanguageProcessor
class_name EnglishProcessor

func _init() -> void:
	language_name = "English"

func get_language_code() -> String:
	return "en"

## Normalize English text: handle digraphs, common letter combinations, silent letters.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Common digraphs and letter combinations
	s = s.replace("th", "t")   # 'th' -> simplified to 't'
	s = s.replace("sh", "x")   # 'sh' -> fricative 'x'
	s = s.replace("ch", "x")   # 'ch' -> fricative 'x'
	s = s.replace("ph", "f")   # 'ph' -> 'f'
	s = s.replace("wh", "w")   # 'wh' -> 'w'
	s = s.replace("ck", "k")   # 'ck' -> 'k'
	s = s.replace("gh", "")    # 'gh' often silent (night, through)
	s = s.replace("kn", "n")   # 'kn' -> 'n' (knife, know)
	s = s.replace("wr", "r")   # 'wr' -> 'r' (write, wrong)
	s = s.replace("gn", "n")   # 'gn' -> 'n' (gnome, sign)
	s = s.replace("mb", "m")   # 'mb' -> 'm' (lamb, climb)
	s = s.replace("ng", "n")   # 'ng' -> 'n' simplified

	# Double consonants -> single
	s = s.replace("tt", "t")
	s = s.replace("ll", "l")
	s = s.replace("ss", "s")
	s = s.replace("ff", "f")
	s = s.replace("pp", "p")
	s = s.replace("dd", "d")
	s = s.replace("bb", "b")
	s = s.replace("gg", "g")
	s = s.replace("nn", "n")
	s = s.replace("mm", "m")
	s = s.replace("rr", "r")
	s = s.replace("zz", "z")

	# Common vowel combinations
	s = s.replace("oo", "u")   # 'oo' -> 'u' (book, food)
	s = s.replace("ee", "i")   # 'ee' -> 'i' (see, tree)
	s = s.replace("ea", "i")   # 'ea' -> 'i' (eat, tea)
	s = s.replace("ou", "a")   # 'ou' -> 'a' (house, out)
	s = s.replace("ow", "o")   # 'ow' -> 'o' (show, know)
	s = s.replace("ai", "e")   # 'ai' -> 'e' (rain, wait)
	s = s.replace("ay", "e")   # 'ay' -> 'e' (day, say)
	s = s.replace("ey", "e")   # 'ey' -> 'e' (they, key)
	s = s.replace("oa", "o")   # 'oa' -> 'o' (boat, road)
	s = s.replace("ie", "i")   # 'ie' -> 'i' (pie, tie)
	s = s.replace("ue", "u")   # 'ue' -> 'u' (blue, true)

	# Silent 'e' at end is handled by tokenization (not removed here)

	# 'qu' -> 'kw' (but simplified to 'k' for Animalese)
	s = s.replace("qu", "k")

	# 'x' -> 'ks' simplified to 'k'
	s = s.replace("x", "k")

	# 'c' before e/i -> 's', otherwise -> 'k'
	s = s.replace("ce", "se")
	s = s.replace("ci", "si")
	s = s.replace("cy", "si")
	s = s.replace("c", "k")

	# 'y' as consonant at start, otherwise treat as vowel
	# (handled in tokenization)

	return s

## Tokenize English text into CV-style syllables.
## English syllable structure is more complex than Spanish,
## but we simplify it for Animalese-style synthesis.
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

		# Handle 'y' - consonant at start of word/syllable, vowel otherwise
		if ch == "y":
			# Check if 'y' is at start or after consonant (consonant role)
			var prev_is_vowel: bool = i > 0 and is_vowel(text.substr(i - 1, 1))
			if not prev_is_vowel and i + 1 < n and is_vowel(text.substr(i + 1, 1)):
				# 'y' + vowel -> CV syllable (yes, you)
				var vch: String = text.substr(i + 1, 1)
				tokens.append("y" + vch)
				i += 2
				continue
			else:
				# 'y' as vowel (happy, my)
				tokens.append("i")  # Map 'y' vowel to 'i'
				i += 1
				continue

		# Vowel
		if is_vowel(ch):
			tokens.append(ch)
			i += 1
			# Check for coda consonants (single consonant at end)
			if i < n:
				var next_ch: String = text.substr(i, 1)
				if _is_coda_consonant(next_ch) and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					# This consonant is a coda, not onset of next syllable
					tokens.append(next_ch)
					i += 1
			continue

		# Consonant + vowel -> CV syllable
		if i + 1 < n and is_vowel(text.substr(i + 1, 1)):
			var vch: String = text.substr(i + 1, 1)
			tokens.append(ch + vch)
			i += 2
			# Check for coda
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

## Check if a consonant commonly appears in syllable coda position.
func _is_coda_consonant(ch: String) -> bool:
	return ch == "n" or ch == "m" or ch == "s" or ch == "t" or ch == "d" or ch == "l" or ch == "r" or ch == "k" or ch == "p"
