package pack

import (
	"strings"
	"testing"
	"testing/fstest"

	"github.com/herocodess/mothball/rules"
)

func TestBuiltInPacksLoad(t *testing.T) {
	set, err := Load(rules.Files)
	if err != nil {
		t.Fatal(err)
	}
	if len(set.Packs) < 5 {
		t.Fatalf("want at least 5 packs, got %d", len(set.Packs))
	}
	if len(set.ByDetect["pubspec.yaml"]) != 1 {
		t.Error("pubspec.yaml should map to the flutter pack")
	}
}

func TestPacksMustBeSafe(t *testing.T) {
	cases := map[string]string{
		"no requireAny":   `{"id":"a","name":"A","detect":["x"],"outputs":[{"path":"build"}],"wake":[{"run":"r"}]}`,
		"escapes project": `{"id":"a","name":"A","detect":["x"],"outputs":[{"path":"../build","requireAny":["m"]}],"wake":[{"run":"r"}]}`,
		"absolute path":   `{"id":"a","name":"A","detect":["x"],"outputs":[{"path":"/tmp","requireAny":["m"]}],"wake":[{"run":"r"}]}`,
		"project itself":  `{"id":"a","name":"A","detect":["x"],"outputs":[{"path":".","requireAny":["m"]}],"wake":[{"run":"r"}]}`,
		"detect has path": `{"id":"a","name":"A","detect":["sub/x"],"outputs":[{"path":"b","requireAny":["m"]}],"wake":[{"run":"r"}]}`,
		"empty wake":      `{"id":"a","name":"A","detect":["x"],"outputs":[{"path":"b","requireAny":["m"]}],"wake":[{"run":" "}]}`,
		"bad pattern":     `{"id":"a","name":"A","detect":["[x"],"outputs":[{"path":"b","requireAny":["m"]}]}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := Load(fstest.MapFS{"a.json": {Data: []byte(body)}})
			if err == nil {
				t.Fatal("unsafe pack was accepted")
			}
		})
	}
}

func TestDuplicateIDsRejected(t *testing.T) {
	p := `{"id":"a","name":"A","detect":["x"],"outputs":[{"path":"b","requireAny":["m"]}],"wake":[{"run":"r"}]}`
	_, err := Load(fstest.MapFS{"a.json": {Data: []byte(p)}, "b.json": {Data: []byte(p)}})
	if err == nil || !strings.Contains(err.Error(), "duplicate") {
		t.Fatalf("want duplicate error, got %v", err)
	}
}
