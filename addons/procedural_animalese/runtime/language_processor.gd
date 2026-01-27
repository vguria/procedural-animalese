## Base class for language-specific text processing in ProceduralAnimalese.
## Subclass this to add support for new languages.
extends Resource
class_name LanguageProcessor

## Display name of the language (e.g., "Spanish", "English").
@export var language_name: String = "Base"

## Normalize text for synthesis: lowercase, remove diacritics, handle digraphs, etc.
## Override in subclasses to implement language-specific normalization rules.
func normalize(text: String) -> String:
	return text.to_lower()

## Tokenize normalized text into phoneme/syllable tokens for synthesis.
## Returns an array of strings where each element is either:
## - A phoneme or syllable (e.g., "a", "ka", "s")
## - Punctuation/whitespace (" ", ",", ".", "!", "?", etc.)
## Override in subclasses to implement language-specific tokenization.
func tokenize(text: String) -> Array[String]:
	var tokens: Array[String] = []
	for i in range(text.length()):
		tokens.append(text.substr(i, 1))
	return tokens

## Check if a character is a vowel in this language.
## Override if the language has different vowel definitions.
func is_vowel(ch: String) -> bool:
	return ch == "a" or ch == "e" or ch == "i" or ch == "o" or ch == "u"

## Get the language code (ISO 639-1 style, e.g., "es", "en", "ja").
## Used for identification and potentially for automatic language detection.
func get_language_code() -> String:
	return "base"
