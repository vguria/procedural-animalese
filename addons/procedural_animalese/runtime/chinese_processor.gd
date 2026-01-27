## Chinese language processor for ProceduralAnimalese.
## Handles Chinese text (Pinyin romanization or characters).
## For characters, uses simple phonetic approximation based on common readings.
extends LanguageProcessor
class_name ChineseProcessor

func _init() -> void:
	language_name = "中文"

func get_language_code() -> String:
	return "zh"

## Chinese vowels (pinyin)
func is_vowel(ch: String) -> bool:
	return ch == "a" or ch == "e" or ch == "i" or ch == "o" or ch == "u" or ch == "ü"

## Normalize Chinese text: handle pinyin tones, convert characters to approximate sounds.
func normalize(text: String) -> String:
	var s: String = text.to_lower()

	# Remove tone marks from pinyin vowels
	s = s.replace("ā", "a").replace("á", "a").replace("ǎ", "a").replace("à", "a")
	s = s.replace("ē", "e").replace("é", "e").replace("ě", "e").replace("è", "e")
	s = s.replace("ī", "i").replace("í", "i").replace("ǐ", "i").replace("ì", "i")
	s = s.replace("ō", "o").replace("ó", "o").replace("ǒ", "o").replace("ò", "o")
	s = s.replace("ū", "u").replace("ú", "u").replace("ǔ", "u").replace("ù", "u")
	s = s.replace("ǖ", "u").replace("ǘ", "u").replace("ǚ", "u").replace("ǜ", "u")
	s = s.replace("ü", "u")

	# Remove tone numbers (pinyin with numbers like "ni3 hao3")
	s = s.replace("1", "").replace("2", "").replace("3", "").replace("4", "").replace("5", "")

	# Common pinyin combinations
	s = s.replace("zh", "x")     # Similar to 'j' sound
	s = s.replace("ch", "x")     # Similar to 'ch'
	s = s.replace("sh", "x")     # Similar to 'sh'
	s = s.replace("ng", "n")     # Simplify final 'ng'

	# Pinyin special syllables
	s = s.replace("iu", "io")    # liu -> lio
	s = s.replace("ui", "ue")    # dui -> due
	s = s.replace("un", "uen")   # Restore hidden 'e'
	s = s.replace("ao", "au")    # hao -> hau

	# 'x' in pinyin is like 'sh'
	# 'q' in pinyin is like 'ch'
	s = s.replace("q", "x")

	# 'c' in pinyin is like 'ts'
	s = s.replace("c", "ts")

	# 'r' in pinyin has special sound, approximate
	# Keep as 'r'

	# Convert common Chinese characters to approximate pinyin sounds
	# This is a simplified mapping for the most common characters
	s = _convert_common_characters(s)

	return s

## Convert common Chinese characters to phonetic approximations.
func _convert_common_characters(text: String) -> String:
	var s: String = text

	# Common greetings and words
	s = s.replace("你", "ni")
	s = s.replace("好", "hau")
	s = s.replace("我", "uo")
	s = s.replace("是", "xi")
	s = s.replace("的", "de")
	s = s.replace("不", "bu")
	s = s.replace("在", "tsai")
	s = s.replace("有", "io")
	s = s.replace("这", "xe")
	s = s.replace("那", "na")
	s = s.replace("什", "xen")
	s = s.replace("么", "me")
	s = s.replace("他", "ta")
	s = s.replace("她", "ta")
	s = s.replace("它", "ta")
	s = s.replace("们", "men")
	s = s.replace("人", "ren")
	s = s.replace("中", "xon")
	s = s.replace("国", "kuo")
	s = s.replace("大", "da")
	s = s.replace("小", "xiau")
	s = s.replace("上", "xan")
	s = s.replace("下", "xia")
	s = s.replace("来", "lai")
	s = s.replace("去", "xu")
	s = s.replace("说", "xuo")
	s = s.replace("看", "kan")
	s = s.replace("听", "tin")
	s = s.replace("吃", "xi")
	s = s.replace("喝", "he")
	s = s.replace("一", "i")
	s = s.replace("二", "er")
	s = s.replace("三", "san")
	s = s.replace("四", "si")
	s = s.replace("五", "u")
	s = s.replace("六", "lio")
	s = s.replace("七", "xi")
	s = s.replace("八", "ba")
	s = s.replace("九", "xio")
	s = s.replace("十", "xi")
	s = s.replace("百", "bai")
	s = s.replace("千", "xien")
	s = s.replace("万", "uan")
	s = s.replace("谢", "xie")
	s = s.replace("对", "due")
	s = s.replace("请", "xin")
	s = s.replace("问", "uen")
	s = s.replace("想", "xian")
	s = s.replace("要", "iau")
	s = s.replace("能", "nen")
	s = s.replace("会", "hue")
	s = s.replace("可", "ke")
	s = s.replace("以", "i")
	s = s.replace("和", "he")
	s = s.replace("就", "xio")
	s = s.replace("也", "ie")
	s = s.replace("很", "hen")
	s = s.replace("太", "tai")
	s = s.replace("真", "xen")
	s = s.replace("没", "mei")
	s = s.replace("都", "du")

	# For remaining Chinese characters, use a simple approximation
	# (In a real implementation, you'd use a full pinyin dictionary)
	var result: String = ""
	for i in range(s.length()):
		var ch: String = s.substr(i, 1)
		var code: int = ch.unicode_at(0)

		# If it's still a Chinese character (CJK range), approximate
		if code >= 0x4E00 and code <= 0x9FFF:
			# Use a hash-based approximation for unknown characters
			var hash_val: int = code % 20
			var syllables: Array[String] = ["a", "ba", "da", "fa", "ga", "ha", "ka", "la", "ma", "na",
											"pa", "sa", "ta", "ua", "xa", "ia", "ie", "io", "iu", "o"]
			result += syllables[hash_val]
		else:
			result += ch

	return result

## Tokenize Chinese text (already romanized) using CV syllable structure.
## Chinese (Mandarin) has very regular CV(C) syllable structure.
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
		if ch == "," or ch == ";" or ch == ":" or ch == "." or ch == "!" or ch == "?" or \
		   ch == "，" or ch == "。" or ch == "！" or ch == "？" or ch == "、":
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
			# Chinese syllables can end in n or ng (simplified to n)
			if i < n:
				var next_ch: String = text.substr(i, 1)
				if (next_ch == "n" or next_ch == "r") and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					tokens.append(next_ch)
					i += 1
			continue

		# Consonant + vowel -> CV syllable
		if i + 1 < n and is_vowel(text.substr(i + 1, 1)):
			var vch: String = text.substr(i + 1, 1)
			tokens.append(ch + vch)
			i += 2
			# Final n/r
			if i < n:
				var coda: String = text.substr(i, 1)
				if (coda == "n" or coda == "r") and (i + 1 >= n or not is_vowel(text.substr(i + 1, 1))):
					tokens.append(coda)
					i += 1
			continue

		# Lone consonant
		tokens.append(ch)
		i += 1

	return tokens
