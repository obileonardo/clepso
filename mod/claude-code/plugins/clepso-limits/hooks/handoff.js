// What the mod hands Clepso's helper: built field by field from the numbers below, never by copying an object, so
// nothing Claude Code adds to these events later can ride along. The helper checks every field again (it is the
// allowlist gate, PRIVACY_AND_SECURITY §4); this file only keeps the hand-off small and obvious.

export const HANDOFF_VERSION = 1

// The one command the mod runs. Clepso writes mod-handoff.sh when you turn this on: it starts Clepso's signed helper,
// which checks every field again and sends the numbers to the app over a local socket. No script there (Clepso
// removed), nothing happens. The plugin's own folder holds no generated file, so it stays byte-identical to the source.
export const HANDOFF_COMMAND =
  'f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/clepso/mod-handoff.sh"; [ -x "$f" ] && exec "$f"; exit 0'

// The windows the status line also carries. Any other kind is counted, never named.
const KINDS = ['five_hour', 'seven_day', 'spend_limit']
// The apps that draw a session without a status line. A session drawn in a terminal is left to the status line.
const SURFACES = ['desktop', 'vscode', 'mobile']

function finite(x) {
  return typeof x === 'number' && Number.isFinite(x) ? x : undefined
}

// One source per session: forward only from a session that no terminal draws (the status line reports those),
// and never from a session nothing draws (`claude -p`, the Agent SDK).
export function forwards(surfaces) {
  if (!Array.isArray(surfaces) || surfaces.length === 0) return false
  return !surfaces.includes('terminal')
}

// The first app that draws the session, or 'other'.
export function surfaceOf(surfaces) {
  for (const s of surfaces) if (SURFACES.includes(s)) return s
  return 'other'
}

// `measure` is the session.measure event (its rateLimits and context), `sessionId` the session's id, `version` the
// Claude Code version, `model` the session's model id (`$.session.model()`). Returns plain data: numbers, the known
// kind names, the id, the version string and the model id.
export function handoff(measure, sessionId, surfaces, version, model) {
  const out = { v: HANDOFF_VERSION, surface: surfaceOf(surfaces), rate_limits: [], other_windows: 0 }
  if (typeof sessionId === 'string' && sessionId.length > 0 && sessionId.length <= 128) out.session_id = sessionId
  if (typeof version === 'string' && version.length <= 32) out.version = version
  // The status line's `model.id` bound (64); the helper checks it again with the status line's string scrub.
  if (typeof model === 'string' && model.length > 0 && model.length <= 64) out.model = { id: model }

  const limits = Array.isArray(measure?.rateLimits) ? measure.rateLimits : []
  for (const r of limits.slice(0, 8)) {
    const kind = typeof r?.kind === 'string' && KINDS.includes(r.kind) ? r.kind : undefined
    const percent = finite(r?.percentUsed)
    if (kind === undefined || percent === undefined) {
      out.other_windows += 1
      continue
    }
    const window = { kind, percent_used: percent }
    if (typeof r.resetsAt === 'string' && r.resetsAt.length <= 40) window.resets_at = r.resetsAt
    out.rate_limits.push(window)
  }

  const c = measure?.context
  if (c && typeof c === 'object') {
    const context = {}
    const tokens = finite(c.tokens), size = finite(c.window), percent = finite(c.percent)
    if (tokens !== undefined) context.tokens = tokens
    if (size !== undefined) context.window = size
    if (percent !== undefined) context.percent = percent
    out.context = context
  }
  return out
}
