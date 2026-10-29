package main

import (
	"reflect"
	"strings"
	"testing"
)

func TestPreinstalledFlowLeavesTheDiskAlone(t *testing.T) {
	t.Setenv("RYOKU_KB_PRESET", "")
	want := []string{
		"keyboard", "locale", "timezone", "network",
		"compositor", "browser", "login-shell", "file-manager", "rashin", "apps",
		"hostname", "administrator", "root-account", "other-people", "review",
	}
	for _, variant := range []string{variantAsahi, variantAsahiALARM} {
		var keys []string
		for _, s := range stepsForVariant(variant) {
			keys = append(keys, s.key)
		}
		if !reflect.DeepEqual(keys, want) {
			t.Fatalf("%s flow = %v, want %v", variant, keys, want)
		}
	}
}

func TestPreinstalledChoicesFollowTheInstalledEdition(t *testing.T) {
	for variant, want := range map[string]string{variantAsahi: "fedora", variantAsahiALARM: "arch"} {
		if got := installerChoicesForVariant(variant).Edition; got != want {
			t.Fatalf("%s choices come from %q, want %q", variant, got, want)
		}
	}
}

func TestPreinstalledInstallRowsMatchItsBackend(t *testing.T) {
	if got := len(installSteps(variantAsahi)); got != 4 {
		t.Fatalf("Asahi install rows = %d, want 4", got)
	}
	if i, ok := stepIndex(variantAsahi, "desktop"); !ok || i != 2 {
		t.Fatalf("stepIndex(desktop) = %d, %v; want 2", i, ok)
	}
	if _, ok := stepIndex(variantAsahi, "partition"); ok {
		t.Fatal("an installed system has no partition row")
	}
}

func TestPreinstalledReviewNamesNoDisk(t *testing.T) {
	m := model{variant: variantAsahi, flow: stepsForVariant(variantAsahi), picks: map[string]string{
		"keyboard": "us", "locale": "en_US.UTF-8", "timezone": "UTC", "hostname": "ryoku", "username": "ryoku",
	}}
	body := m.reviewBody(100)
	for _, word := range []string{"strategy", "encryption", "subvols", "firmware"} {
		if strings.Contains(body, word) {
			t.Fatalf("Asahi review shows %q:\n%s", word, body)
		}
	}
	if !strings.Contains(body, "this system") {
		t.Fatalf("Asahi review does not say it sets up this system:\n%s", body)
	}
}

func TestPreinstalledHandsUntickedAppsToWithout(t *testing.T) {
	m := model{variant: variantAsahi, picks: map[string]string{}}
	rows := appRowsForVariant(variantAsahi)
	m.keep = appDefaultsForVariant(variantAsahi)
	var dropped string
	for _, r := range rows {
		if r.Req == "" && r.Def {
			m.keep[r.ID] = false
			dropped = r.ID
			break
		}
	}
	if dropped == "" {
		t.Fatal("the Fedora table offers no removable app")
	}
	var without string
	for _, kv := range m.installEnv() {
		if v, ok := strings.CutPrefix(kv, "RYOKU_WITHOUT="); ok {
			without = v
		}
	}
	if !strings.Contains(","+without+",", ","+dropped+",") {
		t.Fatalf("RYOKU_WITHOUT = %q, want it to name %s", without, dropped)
	}
	for _, r := range rows {
		if r.Req != "" && strings.Contains(","+without+",", ","+r.ID+",") {
			t.Fatalf("RYOKU_WITHOUT names required app %s", r.ID)
		}
	}
}

func TestPreinstalledReviewStartsWithoutADiskStrategy(t *testing.T) {
	t.Setenv("RYOKU_KB_PRESET", "")
	t.Setenv("RYOKU_BACKEND", "true")
	flow := stepsForVariant(variantAsahi)
	m := model{
		variant: variantAsahi, flow: flow, idx: flowIndex(flow, "review"),
		state: "wizard", netOnline: true, yes: true, pwHash: sha512Crypt("password", "ownersalt"),
		picks: map[string]string{
			"keyboard": "us", "locale": "en_US.UTF-8", "timezone": "UTC", "hostname": "ryoku", "username": "ryoku",
		},
	}
	if _, err := m.installEnvChecked(); err != nil {
		t.Fatalf("Asahi install env refused: %v", err)
	}
	next, _ := m.onKey("enter")
	if got := next.(model).state; got != "install" {
		t.Fatalf("Enter on Asahi review left state %q, want install", got)
	}
}
