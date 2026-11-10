package words

import (
	"regexp"
	"slices"
	"strings"
	"testing"
)

var verb = regexp.MustCompile(`%[sd]`)

func TestEveryLanguageHasEveryLineWithTheSameBlanks(t *testing.T) {
	for _, l := range Languages {
		if _, ok := table[l]; !ok {
			t.Fatalf("no table for %s", l)
		}
		for k, en := range table["en"] {
			s, ok := table[l][k]
			if !ok {
				t.Errorf("%s: missing %q", l, k)
				continue
			}
			if !slices.Equal(verb.FindAllString(s, -1), verb.FindAllString(en, -1)) {
				t.Errorf("%s %q: blanks %v, English has %v", l, k, verb.FindAllString(s, -1), verb.FindAllString(en, -1))
			}
			if strings.ContainsAny(s, "–—") {
				t.Errorf("%s %q has a dash", l, k)
			}
		}
		if len(table[l]) != len(table["en"]) {
			t.Errorf("%s has %d lines, English %d", l, len(table[l]), len(table["en"]))
		}
	}
}

func TestLang(t *testing.T) {
	for in, want := range map[string]string{
		"fr": "fr", "fr-CA": "fr", "pt_BR.UTF-8": "pt", "zh-Hans": "zh", "AR": "ar",
	} {
		if got := Lang(in); got != want {
			t.Errorf("Lang(%q) = %q, want %q", in, got, want)
		}
	}
	if got := match("de"); got != "" {
		t.Errorf("match(de) = %q, want no match", got)
	}
}

func TestT(t *testing.T) {
	if got := T("fr", "free", "19,3 Go"); got != "19,3 Go libres" {
		t.Errorf("T = %q", got)
	}
	if got := T("xx", "open"); got != "Open Mothball" {
		t.Errorf("unknown language should fall back to English, got %q", got)
	}
}

func TestSize(t *testing.T) {
	const b = 20723217203 // 19.3 GB
	for lang, want := range map[string]string{
		"en": "19.3 GB",
		"fr": "19,3 Go",
		"pt": "19,3 GB",
		"ar": "⁦19.3 GB⁩",
	} {
		if got := Size(lang, b); got != want {
			t.Errorf("Size(%s) = %q, want %q", lang, got, want)
		}
	}
	if got := Size("en", 512); got != "512 B" {
		t.Errorf("small size = %q", got)
	}
}
