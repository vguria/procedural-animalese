## Japanese (Romaji) language processor for ProceduralAnimalese.
## Handles romaji text normalization and CV mora tokenization.
## Japanese is ideal for Animalese due to its natural CV syllable structure.
extends LanguageProcessor
class_name JapaneseProcessor

func _init() -> void:
	language_name = "日本語 (Romaji)"

func get_language_code() -> String:
	return "ja"

## Normalize Japanese romaji text.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Long vowel markers
	s = s.replace("ā", "aa")
	s = s.replace("ē", "ee")
	s = s.replace("ī", "ii")
	s = s.replace("ō", "oo")
	s = s.replace("ū", "uu")
	s = s.replace("â", "aa")
	s = s.replace("ê", "ee")
	s = s.replace("î", "ii")
	s = s.replace("ô", "oo")
	s = s.replace("û", "uu")

	# Special romaji combinations
	s = s.replace("shi", "si")  # し
	s = s.replace("chi", "ti")  # ち
	s = s.replace("tsu", "tu")  # つ
	s = s.replace("sha", "sa")  # しゃ (simplified)
	s = s.replace("sho", "so")  # しょ
	s = s.replace("shu", "su")  # しゅ
	s = s.replace("cha", "ta")  # ちゃ
	s = s.replace("cho", "to")  # ちょ
	s = s.replace("chu", "tu")  # ちゅ
	s = s.replace("ja", "za")   # じゃ
	s = s.replace("jo", "zo")   # じょ
	s = s.replace("ju", "zu")   # じゅ
	s = s.replace("ji", "zi")   # じ

	# 'fu' is the only F sound in Japanese
	s = s.replace("fu", "hu")   # ふ -> simplified to 'hu'

	# Double consonants (っ) - small tsu
	# These create a pause/geminate, keep as single for Animalese
	s = s.replace("kk", "k")
	s = s.replace("ss", "s")
	s = s.replace("tt", "t")
	s = s.replace("pp", "p")
	s = s.replace("nn", "n")  # ん + な行 exception

	# 'n' before consonants or at end is syllabic (ん)
	# This is handled in tokenization

	return s

## Tokenize Japanese romaji into natural CV morae.
## Japanese has a very regular CV structure which is perfect for Animalese.
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
		if ch == "," or ch == ";" or ch == ":" or ch == "." or ch == "!" or ch == "?" or ch == "、" or ch == "。":
			tokens.append(ch)
			i += 1
			continue

		# Japanese punctuation
		if ch == "「" or ch == "」" or ch == "『" or ch == "』":
			i += 1
			continue

		# Check for 'n' as syllabic nasal (ん)
		# 'n' is syllabic when:
		# - at end of word
		# - before a consonant (not y)
		# - before 'n' (but we normalized nn -> n)
		if ch == "n":
			var next_ch: String = text.substr(i + 1, 1) if i + 1 < n else ""
			var is_syllabic_n: bool = false

			if next_ch == "":
				is_syllabic_n = true  # End of text
			elif next_ch == " " or next_ch == "," or next_ch == "." or next_ch == "!" or next_ch == "?":
				is_syllabic_n = true  # Before punctuation
			elif not is_vowel(next_ch) and next_ch != "y":
				is_syllabic_n = true  # Before consonant (not 'ny')

			if is_syllabic_n:
				tokens.append("n")  # Syllabic 'n' (ん)
				i += 1
				continue

		# Check for 'y' + vowel combination (ya, yu, yo)
		if ch == "y" and i + 1 < n and _is_y_vowel(text.substr(i + 1, 1)):
			var vch: String = text.substr(i + 1, 1)
			tokens.append("y" + vch)
			i += 2
			continue

		# Vowel alone (a, i, u, e, o)
		if is_vowel(ch):
			tokens.append(ch)
			i += 1
			continue

		# Consonant + vowel -> CV mora (ka, ki, ku, ke, ko, etc.)
		if i + 1 < n and is_vowel(text.substr(i + 1, 1)):
			var vch: String = text.substr(i + 1, 1)
			tokens.append(ch + vch)
			i += 2
			continue

		# Consonant + y + vowel -> CyV mora (kya, kyu, kyo, etc.)
		if i + 2 < n and text.substr(i + 1, 1) == "y" and _is_y_vowel(text.substr(i + 2, 1)):
			# Simplified: treat as C + ya/yu/yo
			var yv: String = text.substr(i + 1, 2)
			tokens.append(ch + yv.substr(1, 1))  # Just use the vowel part
			i += 3
			continue

		# Lone consonant (shouldn't happen in proper romaji, but handle gracefully)
		tokens.append(ch)
		i += 1

	return tokens

## Check if character is a vowel that can follow 'y' (a, u, o - not i, e in standard Japanese)
func _is_y_vowel(ch: String) -> bool:
	return ch == "a" or ch == "u" or ch == "o"
