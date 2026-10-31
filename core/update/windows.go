package update

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/herocodess/mothball/core/proc"
)

// Win is the Windows tooling the updater relies on, swappable for tests.
type Win interface {
	// Signer returns the subject of a valid Authenticode signature on a
	// file, or "" when it is not signed.
	Signer(path string) (string, error)
	// Launch starts the installer and returns without waiting for it.
	Launch(installer string, args []string) error
}

// WindowsInstaller is the installer's file name in a release.
func WindowsInstaller(version, goarch string) string {
	arch := "x64"
	if goarch == "arm64" {
		arch = "arm64"
	}
	return fmt.Sprintf("Mothball-%s-windows-%s-setup.exe", version, arch)
}

// WindowsAppDir is the folder Mothball was installed to when this binary is
// its bin\mothball.exe or bin\mothballw.exe, next to Mothball.exe.
func WindowsAppDir() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	return windowsAppDirOf(exe)
}

func windowsAppDirOf(exe string) string {
	bin := filepath.Dir(exe)
	if !strings.EqualFold(filepath.Base(bin), "bin") {
		return ""
	}
	dir := filepath.Dir(bin)
	if _, err := os.Stat(filepath.Join(dir, "Mothball.exe")); err != nil {
		return ""
	}
	return dir
}

// downloadWindows fetches the installer for this machine's architecture and
// checks it against the release's checksums.
func (u *Updater) downloadWindows(ctx context.Context, rel Release, version string) (string, error) {
	name := WindowsInstaller(version, u.GOARCH)
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
	if err := os.MkdirAll(u.Dir, 0o700); err != nil {
		return "", err
	}
	path := filepath.Join(u.Dir, name)
	if err := u.fetch(ctx, url, size, path); err != nil {
		_ = os.Remove(path)
		return "", err
	}
	if err := u.verifyInstaller(path, want); err != nil {
		_ = os.Remove(path)
		return "", err
	}
	u.mu.Lock()
	u.sum = want
	u.mu.Unlock()
	return path, nil
}

// verifyInstaller checks the installer's checksum and, when the installed
// Mothball is code signed, that the installer is signed by the same publisher.
func (u *Updater) verifyInstaller(path, sum string) error {
	got, err := fileSHA256(path)
	if err != nil {
		return err
	}
	if got != sum {
		return errors.New("checksum does not match the release")
	}
	want, err := u.Win.Signer(filepath.Join(u.App, "Mothball.exe"))
	if err != nil || want == "" {
		return nil // an unsigned build: the checksum is the check
	}
	signer, err := u.Win.Signer(path)
	if err != nil {
		return err
	}
	if signer != want {
		return fmt.Errorf("the update is signed by %q, not %q", signer, want)
	}
	return nil
}

// runInstaller checks the downloaded installer again and starts it silently.
// It stops the background service, replaces the files, starts the service
// again and reopens the app.
func (u *Updater) runInstaller(path string) error {
	u.mu.Lock()
	sum := u.sum
	u.mu.Unlock()
	if err := u.verifyInstaller(path, sum); err != nil { // it sat on disk meanwhile
		return err
	}
	return u.Win.Launch(path, []string{
		"/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/RELAUNCH=1",
		"/LOG=" + filepath.Join(u.Dir, "install.log"),
	})
}

type realWin struct{}

func (realWin) Signer(path string) (string, error) {
	script := fmt.Sprintf(`$s = Get-AuthenticodeSignature -LiteralPath '%s'; if ($s.Status -eq 'Valid') { $s.SignerCertificate.Subject }`,
		strings.ReplaceAll(path, "'", "''"))
	out, err := proc.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script).Output()
	if err != nil {
		return "", fmt.Errorf("checking the signature: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func (realWin) Launch(installer string, args []string) error {
	return proc.Command(installer, args...).Start()
}
