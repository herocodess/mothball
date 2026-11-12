#!/usr/bin/env python3
"""Writes the website in every language from one template.

    site/i18n/page.html    the page, with {{key}} where text goes
    site/i18n/en.json      the English text (the source)
    site/i18n/<code>.json  each translation, same keys

Run it after changing any of those, and commit what it writes:

    python3 scripts/build-site.py           writes site/index.html and site/<code>/index.html
    python3 scripts/build-site.py --check   fails if a written page is out of date (CI)

The site stays plain HTML: Cloudflare serves the written pages as they are.
"""
import html
import json
import re
import sys
from pathlib import Path

SITE = Path(__file__).resolve().parent.parent / "site"
ORIGIN = "https://usemothball.dev"

# code, name in its own language, html lang, direction, og:locale.
# English lives at /, every other language at /<code>/.
LANGUAGES = [
    ("en", "English", "en", "ltr", "en_US"),
    ("ar", "العربية", "ar", "rtl", "ar_AR"),
    ("es", "Español", "es", "ltr", "es_ES"),
    ("fr", "Français", "fr", "ltr", "fr_FR"),
    ("ja", "日本語", "ja", "ltr", "ja_JP"),
    ("pt", "Português (Brasil)", "pt-BR", "ltr", "pt_BR"),
    ("zh", "简体中文", "zh-Hans", "ltr", "zh_CN"),
]

# Text that may hold markup; everything else is escaped.
RAW = {"madeBy"}

# Text the page's script uses (main.js reads it from #mb-words).
SCRIPT_KEYS = [
    "themeSystem", "themeLight", "themeDark", "themeTap", "themeSystemLabel", "themeLightLabel", "themeDarkLabel",
    "macTitle", "macFits", "winX64Title", "winX64Fits", "winArmTitle", "winArmFits",
    "linuxX64Title", "linuxX64Fits", "linuxArmTitle", "linuxArmFits",
    "orHomebrew", "appIncludesCli", "orScoop", "scoopNote", "preferPackage", "packageNote",
    "pickedFor", "osOnArm", "yourSystem", "dlDefault", "unitMB",
]

PLACEHOLDER = re.compile(r"\{\{(\w+)\}\}")
BLANK = re.compile(r"\{(\w+)\}")


def path_of(code):
    return "/" if code == "en" else f"/{code}/"


def out_file(code):
    return SITE / "index.html" if code == "en" else SITE / code / "index.html"


def load(code):
    return json.loads((SITE / "i18n" / f"{code}.json").read_text(encoding="utf-8"))


def check_words(en, words, code):
    """Every language needs every English key, with the same {blanks}."""
    problems = []
    for k, v in en.items():
        if k not in words:
            problems.append(f"{code}: missing {k}")
        elif set(BLANK.findall(words[k])) != set(BLANK.findall(v)):
            problems.append(f"{code}: {k} has blanks {sorted(BLANK.findall(words[k]))}, English {sorted(BLANK.findall(v))}")
    for k in words:
        if k not in en:
            problems.append(f"{code}: unknown key {k}")
    return problems


def language_menu(current, en_words, words):
    items = []
    for code, name, lang, _, _ in LANGUAGES:
        here = ' aria-current="page"' if code == current else ""
        items.append(
            f'<li><a href="{path_of(code)}" hreflang="{lang}" lang="{lang}" data-lang="{code}"{here}>{html.escape(name)}</a></li>'
        )
    label = html.escape(words["languageLabel"])
    return (
        '      <details class="langs">\n'
        f'        <summary aria-label="{label}" title="{label}">'
        '<svg aria-hidden="true" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
        'stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18"/>'
        '<path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18"/></svg>'
        f'<span class="langs-code">{current.upper()}</span></summary>\n'
        f'        <ul class="langs-list">{"".join(items)}</ul>\n'
        "      </details>"
    )


def render(template, code, en):
    words = load(code) if code != "en" else en
    _, _, lang, direction, og_locale = next(l for l in LANGUAGES if l[0] == code)
    alternates = "\n".join(
        f'<link rel="alternate" hreflang="{l[2]}" href="{ORIGIN}{path_of(l[0])}">' for l in LANGUAGES
    ) + f'\n<link rel="alternate" hreflang="x-default" href="{ORIGIN}/">'
    # Each language's own invitation, for the "view in your language" note.
    langs = {
        c: {"name": n, "path": path_of(c), "suggest": (load(c) if c != "en" else en)["suggest"],
            "view": (load(c) if c != "en" else en)["suggestView"], "close": (load(c) if c != "en" else en)["close"]}
        for c, n, _, _, _ in LANGUAGES
    }
    values = {
        "code": code,
        "lang": lang,
        "dir": direction,
        "ogLocale": og_locale,
        "url": ORIGIN + path_of(code),
        "alternates": alternates,
        "languageMenu": language_menu(code, en, words),
        # </ in the JSON would end the <script>; \u003c keeps it inert.
        "words": json.dumps({k: words[k] for k in SCRIPT_KEYS}, ensure_ascii=False).replace("</", "\\u003c/"),
        "langs": json.dumps({"current": code, "languages": langs}, ensure_ascii=False).replace("</", "\\u003c/"),
    }

    def fill(m):
        k = m.group(1)
        if k in values:
            return values[k]
        if k not in words:
            raise SystemExit(f"{code}: the template uses {{{{{k}}}}}, which is not in the text files")
        # Attributes in the template use double quotes, so only those need escaping.
        return words[k] if k in RAW else html.escape(words[k], quote=False).replace('"', "&quot;")

    return PLACEHOLDER.sub(fill, template)


def main():
    check = "--check" in sys.argv[1:]
    template = (SITE / "i18n" / "page.html").read_text(encoding="utf-8")
    en = load("en")
    problems = []
    for code, *_ in LANGUAGES[1:]:
        problems += check_words(en, load(code), code)
    if problems:
        raise SystemExit("\n".join(problems))
    stale = []
    for code, *_ in LANGUAGES:
        page = render(template, code, en)
        out = out_file(code)
        if check:
            if not out.exists() or out.read_text(encoding="utf-8") != page:
                stale.append(str(out.relative_to(SITE.parent)))
        else:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(page, encoding="utf-8")
    if stale:
        raise SystemExit("Out of date; run python3 scripts/build-site.py and commit:\n  " + "\n  ".join(stale))
    print("site pages up to date" if check else f"wrote {len(LANGUAGES)} pages")


if __name__ == "__main__":
    main()
