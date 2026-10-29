package main

import "ryoku-i18n"

// installPhase is one row of the install progress: the @@RYOKU_STEP id the
// backend prints when it starts the phase, and the label the row shows. Each
// kind of install keeps both in one table, so a row and its id never drift.
type installPhase struct {
	id, label string
}

func installPhases(variant string) []installPhase {
	if isPreinstalledVariant(variant) {
		return []installPhase{
			{"system", i18n.T("Setting up the system")},
			{"accounts", i18n.T("Creating the accounts")},
			{"desktop", i18n.T("Installing the Ryoku desktop")},
			{"finish", i18n.T("Finishing up")},
		}
	}
	return []installPhase{
		{"partition", i18n.T("Partitioning the disk")},
		{"filesystems", i18n.T("Creating filesystems and btrfs subvolumes")},
		{"mount", i18n.T("Mounting the target")},
		{"pacstrap", i18n.T("Installing the base system")},
		{"configure", i18n.T("Configuring the system")},
		{"bootloader", i18n.T("Installing the Limine bootloader")},
	}
}

func installSteps(variant string) []string {
	var labels []string
	for _, p := range installPhases(variant) {
		labels = append(labels, p.label)
	}
	return labels
}

// stepIndex maps a backend @@RYOKU_STEP id to an install row.
func stepIndex(variant, id string) (int, bool) {
	for i, p := range installPhases(variant) {
		if p.id == id {
			return i, true
		}
	}
	return 0, false
}
