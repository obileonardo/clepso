import { expect, test } from 'claude-code/testing'

// A session.measure as Claude Code 2.1.299 sent it in the desktop app's Code tab on 19 Oct 2026
// (docs evidence/mod-spike-19oct/desktop-code-tab.json), plus marker strings in places a careless mod might copy from.
const CANARY = 'CANARY-7f3a-do-not-forward'
const MEASURE = {
  context: { tokens: 88744, window: 1000000, percent: 9, breakdown: { note: CANARY } },
  rateLimits: [
    { kind: 'five_hour', percentUsed: 26, resetsAt: '2026-10-19T14:30:00.000Z', label: CANARY },
    { kind: 'seven_day', percentUsed: 70, resetsAt: '2026-10-22T04:00:00.000Z' },
    { kind: CANARY, percentUsed: 12 },
  ],
  cost: { usd: 0.91527775 },
  changed: ['context', 'rateLimits', 'cost'],
  prompt: CANARY,
  cwd: '/Users/someone/' + CANARY,
}
const SESSION = '1f5e4b85-aff5-4060-9460-e347da1179ef'

type Run = { argv: readonly string[]; init?: { stdin?: string; timeoutMs?: number } }

function stubs(on: any, surfaces: string[], runs: Run[], fail = false) {
  on('session.measure', ($: any, e: any) => ({ changed: e.changed }))
  on('session.surfaces', () => ({ value: surfaces }))
  on('session.id', () => ({ value: SESSION }))
  on('session.version', () => ({ value: { version: '2.1.299', base: '2.1.299', builtAt: '2026-10-13T21:37:33Z' } }))
  on('process.run', ($: any, e: any) => {
    runs.push({ argv: e.argv, init: e.init })
    return fail ? { deny: 'helper missing' } : { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
}

test('desktop session: one hand-off with numbers only', async ($, on) => {
  const runs: Run[] = []
  stubs(on, ['desktop'], runs)
  const result = await $.session.measure(MEASURE as any)
  expect(result).toEqual({ changed: ['context', 'rateLimits', 'cost'] })
  expect(runs.length).toBe(1)
  expect(runs[0].argv).toEqual([
    '/bin/sh', '-c', 'f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/clepso/mod-handoff.sh"; [ -x "$f" ] && exec "$f"; exit 0',
  ])
  expect(runs[0].init?.timeoutMs).toBe(5000)
  const stdin = runs[0].init?.stdin ?? ''
  expect(stdin).not.toContain(CANARY)
  expect(stdin).not.toContain('usd')
  expect(JSON.parse(stdin)).toEqual({
    v: 1,
    surface: 'desktop',
    session_id: SESSION,
    version: '2.1.299',
    rate_limits: [
      { kind: 'five_hour', percent_used: 26, resets_at: '2026-10-19T14:30:00.000Z' },
      { kind: 'seven_day', percent_used: 70, resets_at: '2026-10-22T04:00:00.000Z' },
    ],
    other_windows: 1,
    context: { tokens: 88744, window: 1000000, percent: 9 },
  })
})

test('VS Code panel with a phone attached: forwarded, surface vscode', async ($, on) => {
  const runs: Run[] = []
  stubs(on, ['vscode', 'mobile'], runs)
  await $.session.measure(MEASURE as any)
  expect(runs.length).toBe(1)
  expect(JSON.parse(runs[0].init?.stdin ?? '{}').surface).toBe('vscode')
})

test('terminal session: nothing sent (the status line reports it)', async ($, on) => {
  const runs: Run[] = []
  stubs(on, ['terminal', 'mobile'], runs)
  await $.session.measure(MEASURE as any)
  expect(runs.length).toBe(0)
})

test('claude -p or the Agent SDK (nothing draws): nothing sent', async ($, on) => {
  const runs: Run[] = []
  stubs(on, [], runs)
  await $.session.measure(MEASURE as any)
  expect(runs.length).toBe(0)
})

test('helper missing: the event still completes', async ($, on) => {
  const runs: Run[] = []
  stubs(on, ['desktop'], runs, true)
  const result = await $.session.measure(MEASURE as any)
  expect(runs.length).toBe(1)
  expect(result).toEqual({ changed: ['context', 'rateLimits', 'cost'] })
})

test('before the first reply: empty windows and no fill still hand off cleanly', async ($, on) => {
  const runs: Run[] = []
  stubs(on, ['desktop'], runs)
  await $.session.measure({ context: { window: 1000000 }, rateLimits: [], changed: ['context'] } as any)
  expect(JSON.parse(runs[0].init?.stdin ?? '{}')).toEqual({
    v: 1, surface: 'desktop', session_id: SESSION, version: '2.1.299', rate_limits: [], other_windows: 0,
    context: { window: 1000000 },
  })
})
