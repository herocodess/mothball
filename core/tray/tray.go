//go:build !darwin || cgo

// Package tray is Mothball's menu bar (macOS) and system tray (Windows,
// Linux) icon. It lives in the background service, so it costs almost nothing
// and keeps showing the state even when the app window is closed.
package tray

import (
	_ "embed"
	"fmt"
	"os"
	"runtime"
	"sync"
	"time"

	"fyne.io/systray"

	"github.com/herocodess/mothball/core/service"
)

var (
	//go:embed icons/template@2x.png
	templateIcon2x []byte
	//go:embed icons/color.png
	colorIcon []byte
	//go:embed icons/icon.ico
	windowsIcon []byte
)

// Available reports whether a tray can be shown here. On Linux it needs a
// desktop session bus; headless machines run the service without one.
func Available() bool {
	if runtime.GOOS == "linux" {
		return os.Getenv("DBUS_SESSION_BUS_ADDRESS") != ""
	}
	return true
}

// Quit removes the icon and makes Run return.
func Quit() { systray.Quit() }

// Run shows the icon and blocks until the user quits or Quit is called. It
// must be called from the main goroutine. onQuit runs once, as it exits.
func Run(s *service.Service, openApp func(), onQuit func()) {
	var once sync.Once
	systray.Run(func() { ready(s, openApp) }, func() { once.Do(onQuit) })
}

func ready(s *service.Service, openApp func()) {
	switch runtime.GOOS {
	case "darwin":
		systray.SetTemplateIcon(templateIcon2x, templateIcon2x)
	case "windows":
		systray.SetIcon(windowsIcon)
	default:
		systray.SetIcon(colorIcon)
	}
	systray.SetTooltip("Mothball")

	free := systray.AddMenuItem("Checking free space…", "")
	free.Disable()
	idle := systray.AddMenuItem("", "")
	idle.Disable()
	back := systray.AddMenuItem("", "Open Mothball to wake it")
	back.Hide()
	systray.AddSeparator()
	open := systray.AddMenuItem("Open Mothball", "")
	scan := systray.AddMenuItem("Scan now", "Look for build output in idle projects")
	auto := systray.AddMenuItemCheckbox("Autopilot", "Put away idle output when space runs low", false)
	systray.AddSeparator()
	quit := systray.AddMenuItem("Quit Mothball", "Stop the background service")

	refresh := func() {
		st, err := s.Status()
		if err != nil {
			free.SetTitle("Mothball can't read its settings")
			return
		}
		f := human(int64(st.FreeBytes)) + " free"
		if st.Config.Autopilot && st.FreeBytes < st.TargetBytes {
			f += fmt.Sprintf(", below your %d GB target", st.Config.TargetFreeGB)
		}
		free.SetTitle(f)
		systray.SetTooltip("Mothball: " + f)

		switch {
		case st.Scanning:
			idle.SetTitle("Scanning your projects…")
		case st.LastScan == nil:
			idle.SetTitle("Not scanned yet")
		case st.LastScan.IdleBytes+st.LastScan.CacheBytes == 0:
			idle.SetTitle("Nothing idle to put away")
		default:
			idle.SetTitle(fmt.Sprintf("%s can be freed", human(st.LastScan.IdleBytes+st.LastScan.CacheBytes)))
		}

		var returned []string
		for _, p := range st.Mothballed {
			if p.Returned {
				returned = append(returned, base(p.Path))
			}
		}
		switch len(returned) {
		case 0:
			back.Hide()
		case 1:
			back.SetTitle(fmt.Sprintf("You're back on %s. Wake it?", returned[0]))
			back.Show()
		default:
			back.SetTitle(fmt.Sprintf("You're back on %d mothballed projects", len(returned)))
			back.Show()
		}

		if st.Config.Autopilot {
			auto.Check()
		} else {
			auto.Uncheck()
		}
	}
	refresh()

	go func() {
		tick := time.NewTicker(5 * time.Second)
		defer tick.Stop()
		for {
			select {
			case <-tick.C:
				refresh()
			case <-open.ClickedCh:
				openApp()
			case <-back.ClickedCh:
				openApp()
			case <-scan.ClickedCh:
				go func() { _, _ = s.Scan(); refresh() }()
				refresh()
			case <-auto.ClickedCh:
				if c, err := s.Config(); err == nil {
					c.Autopilot = !auto.Checked()
					_, _ = s.SetConfig(c)
				}
				refresh()
			case <-quit.ClickedCh:
				systray.Quit()
				return
			}
		}
	}()
}

func base(p string) string {
	for i := len(p) - 1; i >= 0; i-- {
		if p[i] == '/' || p[i] == '\\' {
			return p[i+1:]
		}
	}
	return p
}

func human(b int64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := int64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}
