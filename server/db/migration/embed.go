// Package migration embeds the SQL migrations so the server binary can apply
// them itself (AUTO_MIGRATE) without the golang-migrate CLI being installed.
package migration

import "embed"

//go:embed *.sql
var FS embed.FS
