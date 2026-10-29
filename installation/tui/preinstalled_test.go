package main

import (
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
)

func useFirstbootState(t *testing.T) {
	old := firstbootStateDir
	firstbootStateDir = t.TempDir()
	t.Cleanup(func() { firstbootStateDir = old })
}

func flowKeys(flow []step) []string {
	var keys []string
	for _, s := range flow {
		keys = append(keys, s.key)
	}
	return keys
}

// The preinstalled flow is the ISO flow without the questions the installer
// that laid the system down already answered. The skip set is spelled out here,
// not read from preinstalledSkips, so a wrong entry there fails the test.
func TestPreinstalledFlowLeavesTheDiskAlone(t *testing.T) {
	t.Setenv("RYOKU_KB_PRESET", "")
	useFirstbootState(t)
	skipped := map[string]bool{
		"hardware": true, "profile": true, "gpu": true, "gaming": true,
		"diskpick": true, "disk": true, "partitions": true, "encryption": true,
	}
	var want []string
	for _, key := range flowKeys(stepsForVariant("")) {
		if !skipped[key] {
			want = append(want, key)
		}
	}
	for _, variant := range []string{variantAsahi, variantAsahiALARM} {
		if got := flowKeys(stepsForVariant(variant)); !reflect.DeepEqual(got, want) {
			t.Fatalf("%s flow = %v, want the ISO flow without the disk and hardware steps: %v", variant, got, want)
		}
	}
	for _, key := range []string{"administrator", "root-account", "other-people", "review"} {
		if !slices.Contains(want, key) {
			t.Fatalf("the preinstalled flow lost its %s step: %v", key, want)
		}
	}
}

// A retried first boot keeps the accounts the failed run made: the wizard asks
// no account questions, names the kept administrator, and hands the backend no
// account answers.
func TestPreinstalledRetryKeepsTheAccounts(t *testing.T) {
	t.Setenv("RYOKU_KB_PRESET", "")
	useFirstbootState(t)
	if err := os.WriteFile(filepath.Join(firstbootStateDir, "accounts"), []byte("ada\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, kept := keptAdministrator(variantVoid); kept {
		t.Fatal("an ISO install read the first-boot marker")
	}
	name, kept := keptAdministrator(variantAsahiALARM)
	if !kept || name != "ada" {
		t.Fatalf("keptAdministrator = %q, %v; want ada, true", name, kept)
	}
	flow := flowKeys(stepsForVariant(variantAsahiALARM))
	for key := range keptAccountSteps {
		if slices.Contains(flow, key) {
			t.Fatalf("the retry still asks %s: %v", key, flow)
		}
	}
	m := model{variant: variantAsahiALARM, keptAccounts: true, flow: stepsForVariant(variantAsahiALARM), picks: map[string]string{
		"keyboard": "us", "locale": "en_US.UTF-8", "timezone": "UTC", "hostname": "ryoku", "username": name,
	}}
	if env, err := m.accountsEnv(); err != nil || len(env) != 0 {
		t.Fatalf("accountsEnv = %v, %v; want no account answers", env, err)
	}
	if body := m.reviewBody(100); !strings.Contains(body, "ada, kept from the earlier setup") {
		t.Fatalf("the review does not name the kept administrator:\n%s", body)
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
