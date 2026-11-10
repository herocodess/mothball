//go:build !windows

package words

import "testing"

func TestFirstWord(t *testing.T) {
	if got := firstWord("(\n    en\n)"); got != "en" {
		t.Errorf("firstWord = %q", got)
	}
}
