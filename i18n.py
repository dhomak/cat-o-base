"""Tiny translation layer for Pet-o-Base (English, Russian, Ukrainian).

Strings are written in English in the code and templates and wrapped in
_("…"). Translations live in translations.py as plain dictionaries, keyed by
the English text. Placeholders use {name} and are filled with str.format.
Plurals go through _n(), which picks the Russian/Ukrainian form for a number.
"""
import datetime as dt

from flask import g, has_request_context, request

LANGUAGES = {"en": "English", "ru": "Русский", "uk": "Українська"}
DEFAULT = "en"


def current_language():
    if has_request_context():
        return getattr(g, "lang", None) or detect_language()
    return DEFAULT


def detect_language():
    chosen = request.cookies.get("lang")
    if chosen in LANGUAGES:
        return chosen
    best = request.accept_languages.best_match(list(LANGUAGES))
    return best or DEFAULT


def gettext(message, /, **values):
    from translations import TRANSLATIONS
    lang = current_language()
    message = " ".join(str(message).split())  # template text may span lines
    translated = TRANSLATIONS.get(lang, {}).get(message, message) if lang != DEFAULT else message
    return translated.format(**values) if values else translated


def plural_index(lang, n):
    """CLDR plural category index: en one/other; ru and uk one/few/many."""
    n = abs(int(n))
    if lang in ("ru", "uk"):
        if n % 10 == 1 and n % 100 != 11:
            return 0
        if 2 <= n % 10 <= 4 and not 12 <= n % 100 <= 14:
            return 1
        return 2
    return 0 if n == 1 else 1


def ngettext(key, n, /, **values):
    """`key` is a PLURALS entry, e.g. "{n} day". Forms come from translations.PLURALS."""
    from translations import PLURALS
    lang = current_language()
    forms = PLURALS.get(key, {}).get(lang) or PLURALS.get(key, {}).get(DEFAULT) or (key, key)
    form = forms[min(plural_index(lang, n), len(forms) - 1)]
    return form.format(n=n, **values)


MONTHS = {
    "en": ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
    "ru": ["янв.", "февр.", "мар.", "апр.", "мая", "июн.", "июл.", "авг.", "сент.", "окт.", "нояб.", "дек."],
    "uk": ["січ.", "лют.", "бер.", "квіт.", "трав.", "черв.", "лип.", "серп.", "вер.", "жовт.", "лист.", "груд."],
}


def format_date(d):
    """21 Nov 2026 / 21 нояб. 2026 / 21 лист. 2026"""
    months = MONTHS.get(current_language(), MONTHS[DEFAULT])
    return f"{d.day} {months[d.month - 1]} {d.year}"


AGE_UNITS = {"en": ("y", "mo"), "ru": ("г.", "мес."), "uk": ("р.", "міс.")}


def format_age(years, months):
    y, m = AGE_UNITS.get(current_language(), AGE_UNITS[DEFAULT])
    if years == 0:
        return f"{months} {m}"
    return f"{years} {y} {months} {m}" if months else f"{years} {y}"


def today_iso():
    return dt.date.today().isoformat()
