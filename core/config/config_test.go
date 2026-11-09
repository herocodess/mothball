package config

import "testing"

func TestValidateLanguage(t *testing.T) {
	for _, c := range []struct {
		in, want string
	}{
		{"", ""},
		{"fr", "fr"},
		{"pt", "pt"},
		{"zh_Hans", "zh_Hans"},
		{"pt-BR", "pt-BR"},
		{"../etc", ""},
		{"_fr", ""},
		{"fr fr", ""},
		{"averyveryverylongcode", ""},
	} {
		cfg := Default()
		cfg.Language = c.in
		cfg.Validate()
		if cfg.Language != c.want {
			t.Errorf("Validate(language %q) = %q, want %q", c.in, cfg.Language, c.want)
		}
	}
}
