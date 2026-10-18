import Darwin
import StatusLineShim

// `--hook`: a Claude Code hook event (agents per task, increment 1.9). Otherwise: the status line.
exit(CommandLine.arguments.dropFirst().first == "--hook" ? StatusLineShim.hookMain() : StatusLineShim.main())
