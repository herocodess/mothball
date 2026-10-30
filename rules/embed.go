// Package rules holds the built-in rule packs, one JSON file per stack.
// The files are compiled into the binary so every install has the same rules.
package rules

import "embed"

//go:embed *.json
var Files embed.FS
