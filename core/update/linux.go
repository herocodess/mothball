package update

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
)

// LinuxAppImage is the AppImage's file name in a release.
func LinuxAppImage(version, goarch string) string {
	arch := "x86_64"
	if goarch == "arm64" {
		arch = "aarch64"
	}
	return fmt.Sprintf("Mothball-%s-linux-%s.AppImage", version, arch)
}

// LinuxAppImagePath is the AppImage this service runs from, when it does.
// Packages (.deb, .rpm) update through the package manager instead.
func LinuxAppImagePath() string {
	p := os.Getenv("APPIMAGE")
	if p == "" {
		return ""
	}
	if info, err := os.Stat(p); err != nil || !info.Mode().IsRegular() {
		return ""
	}
	return p
}

func linuxCanInstall(app string) bool {
	if app == "" {
		return false
	}
	f, err := os.CreateTemp(filepath.Dir(app), ".mothball-write-test-")
	if err != nil {
		return false
	}
	name := f.Name()
	f.Close()
	os.Remove(name)
	return true
}

func linuxStaged(app, version string) string {
	return filepath.Join(filepath.Dir(app), ".Mothball-"+version+".AppImage.part")
}

// downloadAppImage fetches the AppImage for this machine next to the running
// one (so the swap is a rename on the same disk) and checks its checksum.
func (u *Updater) downloadAppImage(ctx context.Context, rel Release, version string) (string, error) {
	name := LinuxAppImage(version, u.GOARCH)
	url, size, ok := rel.asset(name)
	if !ok {
		return "", fmt.Errorf("release has no %s", name)
	}
	sums, err := u.checksums(ctx, rel, version)
	if err != nil {
		return "", err
	}
	want, ok := sums[name]
	if !ok {
		return "", fmt.Errorf("no checksum for %s", name)
	}
	staged := linuxStaged(u.App, version)
	if err := u.fetch(ctx, url, size, staged); err != nil {
		_ = os.Remove(staged)
		return "", err
	}
	if got, err := fileSHA256(staged); err != nil || got != want {
		_ = os.Remove(staged)
		if err == nil {
			err = fmt.Errorf("checksum does not match the release")
		}
		return "", err
	}
	if err := os.Chmod(staged, 0o755); err != nil {
		_ = os.Remove(staged)
		return "", err
	}
	u.mu.Lock()
	u.sum = want
	u.mu.Unlock()
	return staged, nil
}

// swapAppImage checks the download again and renames it over the running
// AppImage. The running copy keeps working until it restarts.
func (u *Updater) swapAppImage(staged string) error {
	u.mu.Lock()
	sum := u.sum
	u.mu.Unlock()
	if got, err := fileSHA256(staged); err != nil || got != sum {
		if err == nil {
			err = fmt.Errorf("checksum does not match the release")
		}
		return err
	}
	if info, err := os.Stat(u.App); err == nil {
		_ = os.Chmod(staged, info.Mode().Perm()|0o111)
	}
	return os.Rename(staged, u.App)
}
