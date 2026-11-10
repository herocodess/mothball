//go:build windows

package words

import "syscall"

// Primary language IDs (the low 10 bits of a LANGID).
var primary = map[uint16]string{
	0x01: "ar", 0x04: "zh", 0x09: "en", 0x0a: "es", 0x0c: "fr", 0x11: "ja", 0x16: "pt",
}

func detect() string {
	proc := syscall.NewLazyDLL("kernel32.dll").NewProc("GetUserDefaultUILanguage")
	if proc.Find() != nil {
		return ""
	}
	id, _, _ := proc.Call()
	return primary[uint16(id)&0x3ff]
}
