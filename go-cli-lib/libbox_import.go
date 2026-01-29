// libbox_import.go
// This file ensures sing-box/experimental/libbox is retained as a dependency
// for gomobile bind. Without this import, `go mod tidy` would remove sing-box
// from go.mod since it's not directly used by other Go code in this module.

package main

import (
	// Blank import to retain dependency
	_ "github.com/sagernet/sing-box/experimental/libbox"
)
