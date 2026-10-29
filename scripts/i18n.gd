class_name I18n
extends RefCounted
## Translation shortcut for static functions (nodes can just call tr()).
## Settings loads data/i18n/<locale>.json into the TranslationServer; English is the key.


static func t(s) -> String:
	return TranslationServer.translate(str(s))


## Translate a format string, then fill it: I18n.f("Lv %d", [3]).
static func f(fmt: String, args) -> String:
	return TranslationServer.translate(fmt) % args
