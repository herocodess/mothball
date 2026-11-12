//go:build !darwin || cgo

// Package tray is Mothball's menu bar (macOS) and system tray (Windows,
// Linux) icon. It lives in the background service, so it costs almost nothing
// and keeps showing the state even when the app window is closed.
package tray

import (
	_ "embed"
	"os"
	"runtime"
	"sync"
	"time"

	"fyne.io/systray"

	"github.com/herocodess/mothball/core/service"
	"github.com/herocodess/mothball/core/words"
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

	saved := ""
	if c, err := s.Config(); err == nil {
		saved = c.Language
	}
	lang := words.Lang(saved)
	w := func(key string, args ...any) string { return words.T(lang, key, args...) }

	free := systray.AddMenuItem(w("checking"), "")
	free.Disable()
	idle := systray.AddMenuItem("", "")
	idle.Disable()
	back := systray.AddMenuItem("", w("wakeTip"))
	back.Hide()
	upd := systray.AddMenuItem("", w("updateTip"))
	upd.Hide()
	systray.AddSeparator()
	open := systray.AddMenuItem(w("open"), "")
	scan := systray.AddMenuItem(w("scanNow"), w("scanTip"))
	auto := systray.AddMenuItemCheckbox(w("autopilot"), w("autopilotTip"), false)
	systray.AddSeparator()
	quit := systray.AddMenuItem(w("quit"), w("quitTip"))

	// The fixed items follow the language too, so a change in Settings
	// shows here within one refresh.
	relabel := func() {
		back.SetTooltip(w("wakeTip"))
		upd.SetTooltip(w("updateTip"))
		open.SetTitle(w("open"))
		scan.SetTitle(w("scanNow"))
		scan.SetTooltip(w("scanTip"))
		auto.SetTitle(w("autopilot"))
		auto.SetTooltip(w("autopilotTip"))
		quit.SetTitle(w("quit"))
		quit.SetTooltip(w("quitTip"))
	}

	refresh := func() {
		st, err := s.Status()
		if err != nil {
			free.SetTitle(w("cantRead"))
			return
		}
		if l := words.Lang(st.Config.Language); l != lang {
			lang = l
			relabel()
		}
		size := func(b int64) string { return words.Size(lang, b) }
		f := w("free", size(int64(st.FreeBytes)))
		if st.Config.Autopilot && st.FreeBytes < st.TargetBytes {
			f = w("freeBelow", size(int64(st.FreeBytes)), size(int64(st.Config.TargetFreeGB)<<30))
		}
		free.SetTitle(f)
		systray.SetTooltip(w("tooltip", f))

		switch {
		case st.Scanning:
			idle.SetTitle(w("scanning"))
		case st.LastScan == nil:
			idle.SetTitle(w("notScanned"))
		case st.LastScan.IdleBytes+st.LastScan.CacheBytes == 0:
			idle.SetTitle(w("nothingIdle"))
		default:
			idle.SetTitle(w("canBeFreed", size(st.LastScan.IdleBytes+st.LastScan.CacheBytes)))
		}

		var returned []string
		for _, p := range st.Mothballed {
			if p.Returned {
				name := p.Name
				if name == "" {
					name = base(p.Path)
				}
				returned = append(returned, name)
			}
		}
		switch len(returned) {
		case 0:
			back.Hide()
		case 1:
			back.SetTitle(w("backOne", returned[0]))
			back.Show()
		default:
			back.SetTitle(w("backMany", len(returned)))
			back.Show()
		}

		switch u := st.Update; {
		case u == nil || !u.Available:
			upd.Hide()
		case u.Required:
			upd.SetTitle(w("updateRequired", u.Latest))
			upd.Show()
		case u.Phase == "ready":
			upd.SetTitle(w("updateReady", u.Latest))
			upd.Show()
		default:
			upd.SetTitle(w("updateAvailable", u.Latest))
			upd.Show()
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
			case <-upd.ClickedCh:
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
