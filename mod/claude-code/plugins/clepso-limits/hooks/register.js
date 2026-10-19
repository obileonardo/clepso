// Clepso limits (https://github.com/obileonardo/clepso, docs/specs/mod-bridge.md).
//
// After each turn in the Claude desktop app's Code tab or the VS Code panel, hands Clepso's own helper on this Mac
// the plan-limit percentages, their reset times and the context window's numbers, so the menu bar stays current
// where Claude Code's status line doesn't run. It reads no prompt, reply, tool call, file, setting or credential,
// makes no network request, and does nothing in terminal sessions (the status line covers those).
import { HANDOFF_COMMAND, forwards, handoff } from './handoff.js'

export function register(on) {
  on('session.measure', async ($, e, next) => {
    const result = await next(e)
    try {
      const surfaces = await $.session.surfaces()
      if (!forwards(surfaces)) return result
      const sessionId = await $.session.id()
      const version = await $.session.version()
      const payload = handoff(e, sessionId, surfaces, version?.version)
      await $.process.run(['/bin/sh', '-c', HANDOFF_COMMAND], { stdin: JSON.stringify(payload), timeoutMs: 5000 })
    } catch {
      // Clepso quit, removed or slow: the session carries on as if this mod weren't here.
    }
    return result
  })
}
