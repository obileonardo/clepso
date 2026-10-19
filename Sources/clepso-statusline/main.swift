import Darwin
import StatusLineShim

// `--hook`: a Claude Code hook event (agents per task, increment 1.9). `--mod`: a hand-off from Clepso's Claude Code mod
// (the desktop app's Code tab and the VS Code panel, v0.3). Otherwise: the status line.
switch CommandLine.arguments.dropFirst().first {
case "--hook": exit(StatusLineShim.hookMain())
case "--mod": exit(StatusLineShim.modMain())
default: exit(StatusLineShim.main())
}
