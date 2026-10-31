package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/herocodess/mothball/core/history"
	"github.com/herocodess/mothball/core/pack"
	"github.com/herocodess/mothball/core/service"
	"github.com/herocodess/mothball/core/tray"
	"github.com/herocodess/mothball/rules"
)

func newService() (*service.Service, error) {
	dir, err := history.DefaultDir()
	if err != nil {
		return nil, err
	}
	home, _ := os.UserHomeDir()
	packs, err := pack.Load(rules.Files)
	if err != nil {
		return nil, err
	}
	return service.New(dir, home, packs)
}

func cmdService(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, "usage: mothball service run | install | uninstall")
		return 2
	}
	switch args[0] {
	case "run":
		s, err := newService()
		if err != nil {
			fmt.Fprintln(stderr, "mothball:", err)
			return 1
		}
		ln, err := s.Serve()
		if err != nil {
			fmt.Fprintln(stderr, "mothball: cannot start the local API:", err)
			return 1
		}
		defer ln.Close()
		defer os.Remove(service.EndpointFile(s.Dir))
		fmt.Fprintln(stdout, "Mothball service running.")
		stop := make(chan struct{})
		var once sync.Once
		shutdown := func() { once.Do(func() { close(stop) }) }
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
		withTray := tray.Available() && !hasFlag(args[1:], "--no-tray")
		go func() {
			<-sig
			shutdown()
			if withTray {
				tray.Quit()
			}
		}()
		if !withTray {
			s.Run(stop)
			return 0
		}
		done := make(chan struct{})
		go func() { s.Run(stop); close(done) }()
		tray.Run(s, openApp, shutdown) // owns the main thread until Quit
		shutdown()
		<-done
		return 0
	case "install":
		return installService(stdout, stderr)
	case "uninstall":
		return uninstallService(stdout, stderr)
	}
	fmt.Fprintf(stderr, "mothball: unknown service command %q\n", args[0])
	return 2
}

func cmdStatus(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(stderr)
	asJSON := fs.Bool("json", false, "print JSON")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	var st service.Status
	running := false
	if s, err := newService(); err == nil {
		if ep, err := service.ReadEndpoint(s.Dir); err == nil {
			req, _ := http.NewRequest("GET", ep.URL+"/v1/status", nil)
			req.Header.Set("Authorization", "Bearer "+ep.Token)
			client := &http.Client{Timeout: 3 * time.Second}
			if resp, err := client.Do(req); err == nil {
				if resp.StatusCode == 200 && json.NewDecoder(resp.Body).Decode(&st) == nil {
					running = true
				}
				resp.Body.Close()
			}
		}
		if !running {
			if st, err = s.Status(); err != nil {
				fmt.Fprintln(stderr, "mothball:", err)
				return 1
			}
		}
	} else {
		fmt.Fprintln(stderr, "mothball:", err)
		return 1
	}
	if *asJSON {
		enc := json.NewEncoder(stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(map[string]any{"running": running, "status": st})
		return 0
	}
	state := "not running"
	if running {
		state = "running"
		if st.Scanning {
			state = "running, scanning now"
		}
	}
	auto := "off"
	if st.Config.Autopilot {
		auto = fmt.Sprintf("on, keeping %d GB free", st.Config.TargetFreeGB)
	}
	fmt.Fprintf(stdout, "Service:      %s\n", state)
	fmt.Fprintf(stdout, "Free space:   %s\n", human(int64(st.FreeBytes)))
	fmt.Fprintf(stdout, "Autopilot:    %s\n", auto)
	if st.WaitingBytes > 0 {
		fmt.Fprintf(stdout, "In the %s:  %s from Mothball, not emptied yet\n", trashName(), human(st.WaitingBytes))
	}
	if st.LastScan != nil {
		fmt.Fprintf(stdout, "Reclaimable:  %s in %s (scanned %s)\n", human(st.LastScan.IdleBytes),
			folders(len(st.LastScan.Idle)), st.LastScan.At.Format("2 Jan 15:04"))
	}
	if n := len(st.Mothballed); n > 0 {
		fmt.Fprintf(stdout, "Mothballed:   %d projects (mothball wake to list)\n", n)
	}
	return 0
}

func hasFlag(args []string, f string) bool {
	for _, a := range args {
		if a == f {
			return true
		}
	}
	return false
}

// openApp opens the desktop window. MOTHBALL_APP overrides where it is.
func openApp() {
	app := os.Getenv("MOTHBALL_APP")
	switch runtime.GOOS {
	case "darwin":
		if app != "" {
			_ = exec.Command("open", app).Start()
		} else {
			_ = exec.Command("open", "-a", "Mothball").Start()
		}
	case "windows":
		if app == "" {
			exe, _ := os.Executable()
			app = filepath.Join(filepath.Dir(exe), "Mothball.exe")
		}
		_ = exec.Command("cmd", "/C", "start", "", app).Start()
	default:
		if app == "" {
			app = "mothball-app"
		}
		_ = exec.Command(app).Start()
	}
}

const launchdLabel = "dev.mothball.service"

func installService(stdout, stderr io.Writer) int {
	exe, err := os.Executable()
	if err != nil {
		fmt.Fprintln(stderr, "mothball:", err)
		return 1
	}
	exe, _ = filepath.EvalSymlinks(exe)
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "darwin":
		plist := filepath.Join(home, "Library", "LaunchAgents", launchdLabel+".plist")
		body := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>%s</string>
  <key>ProgramArguments</key>
  <array><string>%s</string><string>service</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>LowPriorityIO</key><true/>
  <key>Nice</key><integer>10</integer>
</dict>
</plist>
`, launchdLabel, xmlEscape(exe))
		if err := os.MkdirAll(filepath.Dir(plist), 0o755); err != nil {
			fmt.Fprintln(stderr, "mothball:", err)
			return 1
		}
		if err := os.WriteFile(plist, []byte(body), 0o644); err != nil {
			fmt.Fprintln(stderr, "mothball:", err)
			return 1
		}
		uid := strconv.Itoa(os.Getuid())
		_ = exec.Command("launchctl", "bootout", "gui/"+uid, plist).Run()
		if out, err := exec.Command("launchctl", "bootstrap", "gui/"+uid, plist).CombinedOutput(); err != nil {
			fmt.Fprintf(stderr, "mothball: launchctl: %v %s\n", err, out)
			return 1
		}
	case "linux":
		unit := filepath.Join(home, ".config", "systemd", "user", "mothball.service")
		body := fmt.Sprintf("[Unit]\nDescription=Mothball\n\n[Service]\nExecStart=%q service run\nRestart=on-failure\nNice=10\nIOSchedulingClass=idle\n\n[Install]\nWantedBy=default.target\n", exe)
		if err := os.MkdirAll(filepath.Dir(unit), 0o755); err != nil {
			fmt.Fprintln(stderr, "mothball:", err)
			return 1
		}
		if err := os.WriteFile(unit, []byte(body), 0o644); err != nil {
			fmt.Fprintln(stderr, "mothball:", err)
			return 1
		}
		for _, a := range [][]string{{"daemon-reload"}, {"enable", "--now", "mothball.service"}} {
			if out, err := exec.Command("systemctl", append([]string{"--user"}, a...)...).CombinedOutput(); err != nil {
				fmt.Fprintf(stderr, "mothball: systemctl: %v %s\n", err, out)
				return 1
			}
		}
	case "windows":
		tr := fmt.Sprintf(`"%s" service run`, exe)
		if out, err := exec.Command("schtasks", "/Create", "/F", "/SC", "ONLOGON", "/RL", "LIMITED", "/TN", "Mothball", "/TR", tr).CombinedOutput(); err != nil {
			fmt.Fprintf(stderr, "mothball: schtasks: %v %s\n", err, out)
			return 1
		}
		_ = exec.Command("schtasks", "/Run", "/TN", "Mothball").Run()
	default:
		fmt.Fprintln(stderr, "mothball: starting at login is not supported on this system")
		return 1
	}
	fmt.Fprintln(stdout, "Mothball now runs in the background and starts when you log in.")
	return 0
}

func uninstallService(stdout, stderr io.Writer) int {
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "darwin":
		plist := filepath.Join(home, "Library", "LaunchAgents", launchdLabel+".plist")
		_ = exec.Command("launchctl", "bootout", "gui/"+strconv.Itoa(os.Getuid()), plist).Run()
		_ = os.Remove(plist)
	case "linux":
		_ = exec.Command("systemctl", "--user", "disable", "--now", "mothball.service").Run()
		_ = os.Remove(filepath.Join(home, ".config", "systemd", "user", "mothball.service"))
	case "windows":
		_ = exec.Command("schtasks", "/End", "/TN", "Mothball").Run()
		_ = exec.Command("schtasks", "/Delete", "/F", "/TN", "Mothball").Run()
	}
	fmt.Fprintln(stdout, "Mothball no longer runs in the background.")
	return 0
}

func xmlEscape(s string) string {
	r := strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;", "'", "&apos;")
	return r.Replace(s)
}
