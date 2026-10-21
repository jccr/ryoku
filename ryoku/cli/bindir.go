package main

import (
	"os"
	"path/filepath"
	"strings"
)

// ryoku starts programs that ship beside it (ryoku-wm-*, ryoku-hub,
// ryoku-rashin) by name. A source build installs them all in ~/.local/bin,
// which only the desktop session puts on PATH (hyprland/modules/env.lua), so
// from a TTY or over SSH the doctor would find no Rashin and switch its binds
// off. Our own directory goes first when PATH lacks it; a package install runs
// from /usr/bin, which every PATH already has.
func preferOwnBinDir() {
	exe, err := os.Executable()
	if err != nil {
		return
	}
	os.Setenv("PATH", withDirOnPath(filepath.Dir(exe), os.Getenv("PATH")))
}

// withDirOnPath returns path unchanged when dir is already one of its entries,
// else with dir first.
func withDirOnPath(dir, path string) string {
	if path == "" {
		return dir
	}
	for _, entry := range strings.Split(path, ":") {
		if entry == dir {
			return path
		}
	}
	return dir + ":" + path
}
