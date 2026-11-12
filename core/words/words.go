// Package words holds the text the background service shows itself (the
// menu bar and tray menu) in each of the desktop app's languages. The app's
// own text lives in app/lib/l10n.
package words

import (
	"fmt"
	"strings"
	"sync"
	"time"
)

// Languages the tray speaks: the same set as the desktop app.
var Languages = []string{"en", "ar", "es", "fr", "ja", "pt", "zh"}

// Lang picks the language to show: the one saved in settings if Mothball has
// it, else the system's, else English.
func Lang(saved string) string {
	if l := match(saved); l != "" {
		return l
	}
	if l := match(systemLanguage()); l != "" {
		return l
	}
	return "en"
}

// match reduces a code like "fr-CA", "pt_BR.UTF-8" or "zh-Hans" to one of
// Languages, or "".
func match(code string) string {
	code = strings.ToLower(code)
	if i := strings.IndexAny(code, "-_.@"); i >= 0 {
		code = code[:i]
	}
	for _, l := range Languages {
		if l == code {
			return l
		}
	}
	return ""
}

var (
	sysMu   sync.Mutex
	sysLang string
	sysAt   time.Time
)

// systemLanguage asks the OS at most once a minute.
func systemLanguage() string {
	sysMu.Lock()
	defer sysMu.Unlock()
	if sysAt.IsZero() || time.Since(sysAt) > time.Minute {
		sysLang, sysAt = detect(), time.Now()
	}
	return sysLang
}

// T returns the text for key in lang, filled in like fmt.Sprintf. A key a
// language lacks falls back to English.
func T(lang, key string, args ...any) string {
	s, ok := table[lang][key]
	if !ok {
		s = table["en"][key]
	}
	if len(args) == 0 {
		return s
	}
	return fmt.Sprintf(s, args...)
}

// Size formats bytes the way the app does: 1024-based, one decimal, with the
// language's decimal mark and units ("19,3 Go" in French).
func Size(lang string, b int64) string {
	units := []string{"KB", "MB", "GB", "TB", "PB", "EB"}
	unitB := "B"
	if lang == "fr" {
		units = []string{"Ko", "Mo", "Go", "To", "Po", "Eo"}
		unitB = "o"
	}
	if lang == "ar" {
		unitB = "بايت"
	}
	if b < 1024 {
		return fmt.Sprintf("%d %s", b, unitB)
	}
	v, i := float64(b)/1024, 0
	for v >= 1024 && i < len(units)-1 {
		v /= 1024
		i++
	}
	n := fmt.Sprintf("%.1f", v)
	switch lang {
	case "fr", "es", "pt":
		n = strings.Replace(n, ".", ",", 1)
	}
	s := n + " " + units[i]
	if lang == "ar" {
		// Keep the size whole and left to right inside Arabic text.
		s = "⁦" + s + "⁩"
	}
	return s
}
