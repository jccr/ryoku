package main

import (
	"reflect"
	"strings"
	"testing"
)

func TestPreinstalledFlowLeavesTheDiskAlone(t *testing.T) {
	t.Setenv("RYOKU_KB_PRESET", "")
	var keys []string
	for _, s := range stepsForVariant(variantAsahi) {
		keys = append(keys, s.key)
	}
	want := []string{
		"keyboard", "locale", "timezone", "network",
		"compositor", "browser", "login-shell", "file-manager", "rashin",
		"hostname", "administrator", "root-account", "other-people", "review",
	}
	if !reflect.DeepEqual(keys, want) {
		t.Fatalf("Asahi flow = %v, want %v", keys, want)
	}
}

func TestPreinstalledChoicesFollowTheFedoraTable(t *testing.T) {
	if got := installerChoicesForVariant(variantAsahi).Edition; got != "fedora" {
		t.Fatalf("Asahi choices come from %q, want the Fedora table", got)
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
