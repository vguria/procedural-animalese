## Detecta automaticamente el idioma de un texto y devuelve el LanguageProcessor apropiado.
## Usa heuristicas basadas en caracteres, patrones comunes y el sistema de internacionalizacion de Godot.
extends RefCounted
class_name LanguageDetector

## Codigos de idioma soportados.
enum Language {
	UNKNOWN,
	SPANISH,
	ENGLISH,
	JAPANESE,
	FRENCH,
	GERMAN,
	PORTUGUESE,
	ITALIAN,
	RUSSIAN,
	CHINESE,
}

## Mapeo de codigos de locale a Language enum.
const LOCALE_TO_LANGUAGE: Dictionary = {
	"es": Language.SPANISH,
	"en": Language.ENGLISH,
	"ja": Language.JAPANESE,
	"fr": Language.FRENCH,
	"de": Language.GERMAN,
	"pt": Language.PORTUGUESE,
	"it": Language.ITALIAN,
	"ru": Language.RUSSIAN,
	"zh": Language.CHINESE,
}

## Umbrales para deteccion.
const JAPANESE_THRESHOLD: float = 0.05  # 5% de caracteres japoneses = japones
const SPANISH_THRESHOLD: float = 0.02   # 2% de caracteres espanoles = espanol

## Caracteres japoneses: hiragana, katakana, kanji comunes.
const HIRAGANA_START: int = 0x3040
const HIRAGANA_END: int = 0x309F
const KATAKANA_START: int = 0x30A0
const KATAKANA_END: int = 0x30FF
const KANJI_START: int = 0x4E00
const KANJI_END: int = 0x9FFF

## Caracteres Cyrilicos (ruso).
const CYRILLIC_START: int = 0x0400
const CYRILLIC_END: int = 0x04FF

## Caracteres especificos por idioma.
const SPANISH_CHARS: String = "ñáéíóúüÑÁÉÍÓÚÜ¿¡"
const FRENCH_CHARS: String = "àâäçéèêëîïôùûüÿœæÀÂÄÇÉÈÊËÎÏÔÙÛÜŸŒÆ«»"
const GERMAN_CHARS: String = "äöüßÄÖÜ"
const PORTUGUESE_CHARS: String = "ãõçáéíóúàâêôÃÕÇÁÉÍÓÚÀÂÊÔ"
const ITALIAN_CHARS: String = "àèéìíîòóùúÀÈÉÌÍÎÒÓÙÚ"

## Palabras comunes en espanol (sin acentos para comparar con texto normalizado).
const SPANISH_WORDS: Array[String] = ["que", "de", "no", "es", "la", "el", "en", "los", "del", "las", "con", "una", "por", "para", "como", "pero", "sus", "mas", "este", "ya", "todo", "esta", "muy", "sin", "sobre", "ser", "tiene", "tambien", "hay", "puede", "asi", "cuando", "donde", "porque", "antes", "entre"]

## Palabras comunes en ingles.
const ENGLISH_WORDS: Array[String] = ["the", "and", "that", "have", "for", "not", "with", "you", "this", "but", "his", "from", "they", "say", "her", "she", "will", "one", "all", "would", "there", "their", "what", "out", "about", "who", "get", "which", "when", "make", "can", "like", "just", "him", "know", "take", "into", "your", "some", "could", "them", "than", "then", "now", "look", "only", "come", "its", "over", "think", "also"]

## Palabras comunes en frances.
const FRENCH_WORDS: Array[String] = ["le", "la", "les", "de", "des", "du", "un", "une", "et", "est", "que", "qui", "dans", "ce", "il", "elle", "nous", "vous", "ils", "elles", "je", "tu", "son", "sa", "ses", "pour", "pas", "sur", "avec", "tout", "faire", "comme", "plus", "bien", "ou", "si", "mais", "ont", "sont", "cette", "ces", "aux", "mon", "ton", "notre", "votre", "leur"]

## Palabras comunes en aleman.
const GERMAN_WORDS: Array[String] = ["der", "die", "das", "und", "ist", "ein", "eine", "nicht", "mit", "auf", "den", "dem", "sich", "von", "zu", "es", "sie", "ich", "wir", "ihr", "du", "er", "war", "sind", "hat", "haben", "werden", "kann", "sein", "aus", "bei", "nach", "auch", "nur", "wie", "wenn", "aber", "so", "noch", "mehr", "schon", "durch", "uber", "sehr", "muss", "hier"]

## Palabras comunes en portugues.
const PORTUGUESE_WORDS: Array[String] = ["de", "que", "nao", "uma", "para", "com", "os", "as", "dos", "das", "em", "um", "por", "mais", "na", "se", "no", "foi", "isso", "como", "mas", "ao", "ele", "ela", "seu", "sua", "tem", "nos", "ja", "esta", "esse", "essa", "entre", "quando", "muito", "sem", "mesmo", "aos", "ter", "seus", "suas", "tambem", "so", "sobre", "pelo", "pela", "ate", "depois", "fazer", "voce"]

## Palabras comunes en italiano.
const ITALIAN_WORDS: Array[String] = ["di", "che", "non", "una", "per", "con", "sono", "la", "il", "le", "lo", "gli", "un", "da", "del", "della", "dei", "delle", "nel", "nella", "al", "alla", "ha", "hanno", "come", "ma", "anche", "se", "questo", "questa", "quello", "quella", "essere", "stato", "stata", "sono", "era", "erano", "molto", "tutto", "tutti", "tutte", "fare", "fatto", "piu", "solo", "poi", "sempre", "dove", "quando", "cosa"]

## Palabras comunes en ruso (romanizadas).
const RUSSIAN_WORDS: Array[String] = ["i", "v", "ne", "na", "ya", "chto", "on", "ona", "eto", "kak", "my", "vy", "oni", "vse", "tak", "ego", "no", "da", "ty", "za", "by", "po", "iz", "u", "ot", "o", "dlya", "pri", "bez", "do", "cherez", "mezhdu", "pod", "nad", "pered", "posle", "kogda", "gde", "kto", "chey", "kakoj", "odin", "dva", "tri"]


## Detecta el idioma del texto dado.
## Devuelve el codigo Language enum.
## Si use_locale_fallback es true, usa el locale del sistema cuando la deteccion es incierta.
static func detect(text: String, use_locale_fallback: bool = true) -> Language:
	if text.is_empty():
		if use_locale_fallback:
			return get_system_language()
		return Language.UNKNOWN

	var dominated_result := _check_dominated_language(text)
	if dominated_result != Language.UNKNOWN:
		return dominated_result

	# Si no hay caracteres dominantes, usar analisis de palabras
	var word_result := _analyze_words(text, use_locale_fallback)
	return word_result


## Obtiene el idioma del sistema usando TranslationServer.
static func get_system_language() -> Language:
	var locale := get_system_locale_code()
	return LOCALE_TO_LANGUAGE.get(locale, Language.SPANISH)


## Obtiene el codigo de locale del sistema (ej: "es", "en", "ja").
static func get_system_locale_code() -> String:
	var full_locale: String = TranslationServer.get_locale()
	# El locale puede ser "es_ES", "en_US", "ja_JP", etc.
	# Extraemos solo el codigo de idioma (primeras 2 letras)
	if full_locale.length() >= 2:
		return full_locale.substr(0, 2).to_lower()
	return "es"


## Verifica si el locale del sistema es un idioma soportado.
static func is_system_locale_supported() -> bool:
	var locale := get_system_locale_code()
	return locale in LOCALE_TO_LANGUAGE


## Crea un LanguageProcessor para el locale del sistema.
static func create_processor_for_system_locale() -> LanguageProcessor:
	var locale := get_system_locale_code()
	return create_processor_for_code(locale)


## Detecta el idioma y devuelve el codigo ISO (es, en, ja, fr, de, pt, it, ru, zh).
## Si use_locale_fallback es true, usa el locale del sistema cuando la deteccion es incierta.
static func detect_code(text: String, use_locale_fallback: bool = true) -> String:
	match detect(text, use_locale_fallback):
		Language.SPANISH:
			return "es"
		Language.ENGLISH:
			return "en"
		Language.JAPANESE:
			return "ja"
		Language.FRENCH:
			return "fr"
		Language.GERMAN:
			return "de"
		Language.PORTUGUESE:
			return "pt"
		Language.ITALIAN:
			return "it"
		Language.RUSSIAN:
			return "ru"
		Language.CHINESE:
			return "zh"
		_:
			if use_locale_fallback:
				return get_system_locale_code()
			return "es"  # Default a espanol


## Detecta el idioma y crea el LanguageProcessor correspondiente.
## Si use_locale_fallback es true, usa el locale del sistema cuando la deteccion es incierta.
static func detect_and_create_processor(text: String, use_locale_fallback: bool = true) -> LanguageProcessor:
	var code := detect_code(text, use_locale_fallback)
	return create_processor_for_code(code)


## Crea un LanguageProcessor para el codigo de idioma dado.
static func create_processor_for_code(code: String) -> LanguageProcessor:
	match code.to_lower():
		"es", "spanish":
			return preload("res://addons/procedural_animalese/runtime/spanish_processor.gd").new()
		"en", "english":
			return preload("res://addons/procedural_animalese/runtime/english_processor.gd").new()
		"ja", "japanese", "jp":
			return preload("res://addons/procedural_animalese/runtime/japanese_processor.gd").new()
		"fr", "french":
			return preload("res://addons/procedural_animalese/runtime/french_processor.gd").new()
		"de", "german":
			return preload("res://addons/procedural_animalese/runtime/german_processor.gd").new()
		"pt", "portuguese":
			return preload("res://addons/procedural_animalese/runtime/portuguese_processor.gd").new()
		"it", "italian":
			return preload("res://addons/procedural_animalese/runtime/italian_processor.gd").new()
		"ru", "russian":
			return preload("res://addons/procedural_animalese/runtime/russian_processor.gd").new()
		"zh", "chinese":
			return preload("res://addons/procedural_animalese/runtime/chinese_processor.gd").new()
		_:
			return preload("res://addons/procedural_animalese/runtime/spanish_processor.gd").new()


## Verifica si hay caracteres que dominan claramente el idioma.
static func _check_dominated_language(text: String) -> Language:
	var japanese_count: int = 0
	var chinese_count: int = 0
	var russian_count: int = 0
	var spanish_count: int = 0
	var french_count: int = 0
	var german_count: int = 0
	var portuguese_count: int = 0
	var italian_count: int = 0
	var total_letters: int = 0

	for i in range(text.length()):
		var ch: String = text[i]
		var code: int = ch.unicode_at(0)

		# Ignorar espacios y puntuacion basica
		if ch == " " or ch == "\n" or ch == "\t":
			continue

		total_letters += 1

		# Detectar japones (hiragana/katakana son definitivos)
		if _is_hiragana_or_katakana(code):
			japanese_count += 3  # Peso mayor para kana
		elif _is_cjk_char(code):
			# CJK puede ser japones o chino
			japanese_count += 1
			chinese_count += 1

		# Detectar ruso (Cyrilico)
		if _is_cyrillic_char(code):
			russian_count += 1

		# Detectar por caracteres especiales
		if SPANISH_CHARS.contains(ch):
			spanish_count += 1
		if FRENCH_CHARS.contains(ch):
			french_count += 1
		if GERMAN_CHARS.contains(ch):
			german_count += 1
		if PORTUGUESE_CHARS.contains(ch):
			portuguese_count += 1
		if ITALIAN_CHARS.contains(ch):
			italian_count += 1

	if total_letters == 0:
		return Language.UNKNOWN

	var japanese_ratio: float = float(japanese_count) / float(total_letters)
	var chinese_ratio: float = float(chinese_count) / float(total_letters)
	var russian_ratio: float = float(russian_count) / float(total_letters)
	var spanish_ratio: float = float(spanish_count) / float(total_letters)
	var french_ratio: float = float(french_count) / float(total_letters)
	var german_ratio: float = float(german_count) / float(total_letters)
	var portuguese_ratio: float = float(portuguese_count) / float(total_letters)
	var italian_ratio: float = float(italian_count) / float(total_letters)

	# Ruso es definitivo con caracteres Cyrilicos
	if russian_ratio >= 0.3:
		return Language.RUSSIAN

	# Japones con kana tiene prioridad
	if japanese_ratio >= JAPANESE_THRESHOLD and japanese_count > chinese_count:
		return Language.JAPANESE

	# Chino si hay muchos CJK pero no kana
	if chinese_ratio >= JAPANESE_THRESHOLD and chinese_count > 0 and japanese_count <= chinese_count:
		return Language.CHINESE

	# Aleman tiene ß que es unico
	if german_ratio >= SPANISH_THRESHOLD:
		return Language.GERMAN

	# Frances tiene caracteres unicos como œ, ç con combinaciones
	if french_ratio >= SPANISH_THRESHOLD:
		return Language.FRENCH

	# Portugues tiene ã, õ que son unicos
	if portuguese_ratio >= SPANISH_THRESHOLD:
		return Language.PORTUGUESE

	# Italiano tiene patrones de acentos especificos
	if italian_ratio >= SPANISH_THRESHOLD:
		return Language.ITALIAN

	# Espanol con ñ, ¿, ¡
	if spanish_ratio >= SPANISH_THRESHOLD:
		return Language.SPANISH

	return Language.UNKNOWN


## Verifica si es hiragana o katakana (definitivamente japones).
static func _is_hiragana_or_katakana(code: int) -> bool:
	return (code >= HIRAGANA_START and code <= HIRAGANA_END) or \
		   (code >= KATAKANA_START and code <= KATAKANA_END)


## Verifica si es un caracter CJK (puede ser japones o chino).
static func _is_cjk_char(code: int) -> bool:
	return code >= KANJI_START and code <= KANJI_END


## Verifica si es un caracter Cyrilico (ruso).
static func _is_cyrillic_char(code: int) -> bool:
	return code >= CYRILLIC_START and code <= CYRILLIC_END


## Analiza palabras para distinguir entre idiomas.
## Si use_locale_fallback es true, usa el locale del sistema en caso de empate.
static func _analyze_words(text: String, use_locale_fallback: bool = true) -> Language:
	var lower_text := text.to_lower()

	# Normalizar acentos para comparacion
	var normalized := _remove_accents(lower_text)

	# Extraer palabras
	var words := _extract_words(normalized)

	if words.is_empty():
		if use_locale_fallback:
			return get_system_language()
		return Language.SPANISH  # Default

	var scores: Dictionary = {
		Language.SPANISH: 0,
		Language.ENGLISH: 0,
		Language.FRENCH: 0,
		Language.GERMAN: 0,
		Language.PORTUGUESE: 0,
		Language.ITALIAN: 0,
		Language.RUSSIAN: 0,
	}

	for word in words:
		if word in SPANISH_WORDS:
			scores[Language.SPANISH] += 1
		if word in ENGLISH_WORDS:
			scores[Language.ENGLISH] += 1
		if word in FRENCH_WORDS:
			scores[Language.FRENCH] += 1
		if word in GERMAN_WORDS:
			scores[Language.GERMAN] += 1
		if word in PORTUGUESE_WORDS:
			scores[Language.PORTUGUESE] += 1
		if word in ITALIAN_WORDS:
			scores[Language.ITALIAN] += 1
		if word in RUSSIAN_WORDS:
			scores[Language.RUSSIAN] += 1

	# Encontrar el idioma con mayor puntuacion
	var best_lang: Language = Language.SPANISH
	var best_score: int = 0
	var second_score: int = 0

	for lang in scores.keys():
		var score: int = scores[lang]
		if score > best_score:
			second_score = best_score
			best_score = score
			best_lang = lang
		elif score > second_score:
			second_score = score

	# Si hay clara diferencia, usar el ganador
	if best_score > second_score + 1:
		return best_lang

	# En caso de empate cercano, usar heuristicas adicionales
	var tiebreaker_result := _tiebreaker_extended(text, scores)

	# Si el tiebreaker no fue concluyente y tenemos locale fallback
	if use_locale_fallback and best_score == 0:
		var system_lang := get_system_language()
		# Dar preferencia al idioma del sistema si esta entre los candidatos
		if system_lang in scores:
			return system_lang

	return tiebreaker_result


## Desempate extendido usando patrones para todos los idiomas.
## Considera el locale del sistema para resolver empates.
static func _tiebreaker_extended(text: String, scores: Dictionary) -> Language:
	var lower := text.to_lower()

	# Patrones tipicos por idioma
	var patterns: Dictionary = {
		Language.SPANISH: ["el ", "la ", "los ", "las ", "un ", "una ", "cion", "mente", " y ", " o ", " que ", " del ", " al "],
		Language.ENGLISH: ["the ", " a ", " an ", "tion", "ing ", " of ", " to ", " is ", " are ", " was ", " were ", "'s ", "'t "],
		Language.FRENCH: [" le ", " la ", " les ", " de ", " des ", " du ", " un ", " une ", " et ", " est ", " que ", " qui ", "ment ", " aux "],
		Language.GERMAN: [" der ", " die ", " das ", " und ", " ist ", " ein ", " eine ", " nicht ", " mit ", " auf ", "ung ", "keit ", " zu "],
		Language.PORTUGUESE: [" de ", " que ", " nao ", " uma ", " para ", " com ", " os ", " as ", " em ", " por ", "cao ", " ao ", " da "],
		Language.ITALIAN: [" di ", " che ", " non ", " una ", " per ", " con ", " la ", " il ", " le ", " gli ", " del ", " della ", "zione "],
		Language.RUSSIAN: [],  # Ruso ya deberia estar detectado por Cyrilico
	}

	var pattern_scores: Dictionary = {}
	for lang in patterns.keys():
		pattern_scores[lang] = 0
		for pattern in patterns[lang]:
			if lower.contains(pattern):
				pattern_scores[lang] += 1

	# Combinar scores de palabras con scores de patrones
	var combined_scores: Dictionary = {}
	for lang in scores.keys():
		combined_scores[lang] = scores[lang] * 2 + pattern_scores.get(lang, 0)

	# Dar un bonus al idioma del sistema si es un empate cercano
	var system_lang := get_system_language()
	if system_lang in combined_scores:
		combined_scores[system_lang] += 1  # Bonus leve para desempate

	# Encontrar el mejor
	var best_lang: Language = Language.SPANISH
	var best_score: int = 0

	for lang in combined_scores.keys():
		if combined_scores[lang] > best_score:
			best_score = combined_scores[lang]
			best_lang = lang

	# Si aun no hay informacion suficiente, usar heuristicas adicionales
	if best_score <= 1:  # Solo el bonus del sistema
		# Buscar terminaciones tipicas
		if lower.contains("zione") or lower.contains("aggio") or lower.contains(" gli "):
			return Language.ITALIAN
		if lower.contains("cao") or lower.contains("oes") or lower.contains(" nao "):
			return Language.PORTUGUESE
		if lower.contains("schaft") or lower.contains("lich") or lower.contains("heit"):
			return Language.GERMAN
		if lower.contains("eux") or lower.contains("oir") or lower.contains(" nous "):
			return Language.FRENCH
		# Si no hay patrones, usar el idioma del sistema
		if system_lang != Language.UNKNOWN:
			return system_lang

	return best_lang


## Verifica si un codigo Unicode es un caracter japones.
static func _is_japanese_char(code: int) -> bool:
	# Hiragana
	if code >= HIRAGANA_START and code <= HIRAGANA_END:
		return true
	# Katakana
	if code >= KATAKANA_START and code <= KATAKANA_END:
		return true
	# Kanji comunes
	if code >= KANJI_START and code <= KANJI_END:
		return true
	# Puntuacion japonesa
	if code == 0x3001 or code == 0x3002:  # 、。
		return true
	return false


## Elimina acentos del texto para comparacion.
static func _remove_accents(text: String) -> String:
	var result := text
	result = result.replace("á", "a").replace("é", "e").replace("í", "i").replace("ó", "o").replace("ú", "u")
	result = result.replace("Á", "a").replace("É", "e").replace("Í", "i").replace("Ó", "o").replace("Ú", "u")
	result = result.replace("ü", "u").replace("Ü", "u")
	result = result.replace("ñ", "n").replace("Ñ", "n")
	return result


## Extrae palabras del texto (solo letras).
static func _extract_words(text: String) -> Array[String]:
	var words: Array[String] = []
	var current_word := ""

	for i in range(text.length()):
		var ch: String = text[i]
		var code: int = ch.unicode_at(0)

		# Solo letras ASCII basicas
		if (code >= 97 and code <= 122) or (code >= 65 and code <= 90):
			current_word += ch
		else:
			if current_word.length() >= 2:
				words.append(current_word)
			current_word = ""

	if current_word.length() >= 2:
		words.append(current_word)

	return words
