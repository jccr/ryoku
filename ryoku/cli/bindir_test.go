package main

import "testing"

func TestWithDirOnPath(t *testing.T) {
	cases := []struct {
		name, dir, path, want string
	}{
		{"source box from a TTY", "/home/u/.local/bin", "/usr/local/bin:/usr/bin", "/home/u/.local/bin:/usr/local/bin:/usr/bin"},
		{"inside the session", "/home/u/.local/bin", "/home/u/.local/bin:/usr/bin", "/home/u/.local/bin:/usr/bin"},
		{"package install keeps its order", "/usr/bin", "/usr/local/bin:/usr/bin", "/usr/local/bin:/usr/bin"},
		{"empty PATH", "/usr/bin", "", "/usr/bin"},
	}
	for _, c := range cases {
		if got := withDirOnPath(c.dir, c.path); got != c.want {
			t.Errorf("%s: withDirOnPath(%q, %q) = %q, want %q", c.name, c.dir, c.path, got, c.want)
		}
	}
}
