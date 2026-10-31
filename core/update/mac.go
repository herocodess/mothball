package update

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Mac is the macOS tooling the updater relies on, swappable for tests.
type Mac interface {
	// Extract copies Mothball.app out of the disk image to dest.
	Extract(dmg, dest string) error
	// Team returns the developer team that signed an app.
	Team(app string) (string, error)
	// Verify checks the signature and asks Gatekeeper to accept the app.
	Verify(app string) error
}

type realMac struct{}

func (realMac) Extract(dmg, dest string) error {
	mnt, err := os.MkdirTemp("", "mothball-update-")
	if err != nil {
		return err
	}
	defer os.Remove(mnt)
	if out, err := exec.Command("hdiutil", "attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet", "-mountpoint", mnt, dmg).CombinedOutput(); err != nil {
		return fmt.Errorf("could not open the disk image: %s", strings.TrimSpace(string(out)))
	}
	defer exec.Command("hdiutil", "detach", "-quiet", "-force", mnt).Run()
	src := filepath.Join(mnt, "Mothball.app")
	if _, err := os.Stat(src); err != nil {
		return fmt.Errorf("the disk image has no Mothball.app")
	}
	if out, err := exec.Command("ditto", src, dest).CombinedOutput(); err != nil {
		return fmt.Errorf("could not copy the new app: %s", strings.TrimSpace(string(out)))
	}
	return nil
}

func (realMac) Team(app string) (string, error) {
	var out bytes.Buffer
	cmd := exec.Command("codesign", "-dv", "--verbose=2", app)
	cmd.Stderr = &out
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("not signed: %s", strings.TrimSpace(out.String()))
	}
	for _, line := range strings.Split(out.String(), "\n") {
		if t, ok := strings.CutPrefix(line, "TeamIdentifier="); ok && t != "not set" {
			return strings.TrimSpace(t), nil
		}
	}
	return "", nil
}

func (realMac) Verify(app string) error {
	if out, err := exec.Command("codesign", "--verify", "--deep", "--strict", app).CombinedOutput(); err != nil {
		return fmt.Errorf("signature check failed: %s", strings.TrimSpace(string(out)))
	}
	if out, err := exec.Command("spctl", "--assess", "--type", "execute", app).CombinedOutput(); err != nil {
		return fmt.Errorf("Gatekeeper rejected the update: %s", strings.TrimSpace(string(out)))
	}
	return nil
}
