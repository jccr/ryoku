package main

import (
	"os"
	"path/filepath"
	"strings"
)

// firstbootStateDir is where the Mac first-boot backend records the
// administrator a run created (installation/asahi/ryoku-firstboot-install). A
// var so tests point it at a fixture.
var firstbootStateDir = "/var/lib/ryoku-firstboot"

// keptAccountSteps are the steps a retried first boot no longer asks: the run
// that failed later already made the accounts, and the backend keeps them.
var keptAccountSteps = map[string]bool{"administrator": true, "root-account": true, "other-people": true}

// keptAdministrator names the administrator an earlier first-boot run created,
// when this preinstalled setup is a retry of it.
func keptAdministrator(variant string) (string, bool) {
	if !isPreinstalledVariant(variant) {
		return "", false
	}
	b, err := os.ReadFile(filepath.Join(firstbootStateDir, "accounts"))
	name := strings.TrimSpace(string(b))
	return name, err == nil && name != ""
}
