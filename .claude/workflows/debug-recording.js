export const meta = {
  name: 'debug-recording',
  description: 'Reproduce, diagnose, red-test, fix and clean up terminal bugs from a pty recording',
  whenToUse: 'When the user provides a .rec file (made with `ruby harness/cli.rb record`) capturing a terminal rendering/state bug and wants it debugged end to end. args: {rec: "path.rec", description: "what looked wrong"} (or just the path as a string).',
  phases: [
    { title: 'Reproduce', detail: 'replay the recording, collect failing offsets' },
    { title: 'Localize', detail: 'extract + minimize each distinct failure' },
    { title: 'Diagnose', detail: 'root-cause hypothesis per minimal repro' },
    { title: 'Red test', detail: 'failing regression case in cases/bugs/' },
    { title: 'Fix', detail: 'one fixer per bug, sequential, mechanically gated' },
    { title: 'Cleanup', detail: 'simplify the fix, re-verify, fold into ratchet' },
  ],
}

// ---------------------------------------------------------------- input
// Accept {rec, description}, the same JSON-encoded as a string, or a
// bare path string.
let input = args
if (typeof input === 'string') {
  const s = input.trim()
  if (s.startsWith('{')) {
    try { input = JSON.parse(s) } catch (e) { input = { rec: s } }
  } else {
    input = { rec: s }
  }
}
input = input || {}
if (!input.rec) throw new Error('args.rec required: path to a recording made with `ruby harness/cli.rb record`')
const REC = input.rec
const DESC = input.description || '(none provided)'
const CLI = 'ruby harness/cli.rb'
const MAX_BUGS = input.max_bugs || 3
const FIX_ATTEMPTS = 2

// Mechanical agents run commands and report; they must never exercise
// judgment. This preamble keeps them honest.
const MECH = `You are a mechanical step in a deterministic pipeline.
Run exactly the commands given, from the repo root. Exit status 1 from
harness commands is an expected, reportable outcome - never a reason to
retry, investigate or fix anything. Do not modify any files except
those the commands themselves write. Report results verbatim.\n\n`

// ------------------------------------------------------------- schemas
const REPLAY_SCHEMA = {
  type: 'object',
  required: ['pass', 'geometry', 'failures'],
  properties: {
    pass: { type: 'boolean' },
    bytes: { type: 'integer' },
    geometry: { type: 'string', description: 'e.g. "80x24" from the replay JSON' },
    failures: {
      type: 'array',
      items: {
        type: 'object',
        required: ['offset', 'check'],
        properties: { offset: { type: 'integer' }, check: { type: 'string' } },
      },
    },
  },
}

const MIN_SCHEMA = {
  type: 'object',
  required: ['ok', 'minimal_path', 'minimal_inspect', 'signature', 'check'],
  properties: {
    ok: { type: 'boolean', description: 'false if extract/minimize itself errored' },
    minimal_path: { type: 'string' },
    minimal_inspect: { type: 'string', description: 'minimal_inspect field from minimize JSON' },
    signature: { type: 'string', description: 'result.signature from minimize JSON' },
    check: { type: 'string' },
    failing_detail: { type: 'string', description: 'the failing check object from result.checks, as a JSON string' },
    error: { type: 'string' },
  },
}

const HYP_SCHEMA = {
  type: 'object',
  required: ['summary', 'mechanism', 'files', 'confidence', 'suggested_case_name'],
  properties: {
    summary: { type: 'string', description: 'one-line root cause' },
    mechanism: { type: 'string', description: 'step-by-step: how these bytes lead to the wrong screen/state' },
    files: { type: 'array', items: { type: 'string' }, description: 'files (with line refs) where the cause lives' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    suggested_case_name: { type: 'string', description: 'short kebab-case name for the regression case, e.g. clear-bypasses-draw-batch' },
  },
}

const RED_SCHEMA = {
  type: 'object',
  required: ['case_path', 'red'],
  properties: {
    case_path: { type: 'string' },
    case_id: { type: 'string' },
    red: { type: 'boolean', description: 'true iff harness run on the new case FAILS (exit 1)' },
    signature: { type: 'string' },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['case_pass', 'ratchet_pass', 'tests_pass'],
  properties: {
    case_pass: { type: 'boolean', description: 'harness run on the regression case exits 0' },
    ratchet_pass: { type: 'boolean', description: 'ratchet sweep exits 0 with zero regressions' },
    tests_pass: { type: 'boolean', description: 'rake test reports 0 failures, 0 errors' },
    notes: { type: 'string', description: 'on failure: the relevant diff/diagnostic from the output, verbatim' },
  },
}

const FIX_SCHEMA = {
  type: 'object',
  required: ['fixed', 'summary', 'files_changed'],
  properties: {
    fixed: { type: 'boolean', description: 'your own assessment; the pipeline verifies independently' },
    summary: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
  },
}

const PROBE_SCHEMA = {
  type: 'object',
  required: ['found', 'report'],
  properties: {
    found: { type: 'boolean' },
    case_path: { type: 'string', description: 'path to a deterministic failing case file, if found' },
    check: { type: 'string', description: 'which check fails on it (redraw/markers/state)' },
    geometry: { type: 'string' },
    report: { type: 'string' },
  },
}

const verifyPrompt = (cases, geometry) => MECH +
  `Verification gate. Run, in order:
1. ${cases.map(c => `${CLI} run --case ${c.path} --checks ${c.check} --geometry ${c.geometry || geometry}`).join('\n   ')}
   (case_pass = ALL exit 0)
2. ${CLI} sweep --cases cases --oracle tmux --ratchet ratchet.json   (ratchet_pass = exit 0)
3. rake test   (tests_pass = "0 failures, 0 errors")
On any failure, copy the relevant failing diff/output into notes verbatim.`

// ============================================================ Reproduce
phase('Reproduce')
log(`replaying ${REC}`)
const replay = await agent(MECH +
  `Run: ${CLI} replay --rec ${REC} --checks redraw,markers
Report pass, bytes, geometry and the failures array from the JSON output.`,
  { schema: REPLAY_SCHEMA, label: 'replay' })
if (!replay) throw new Error('replay agent failed')

let targets = []
if (replay.pass) {
  log('automated checks pass; probing interactively from the user description')
  const probe = await agent(
    `A terminal emulator bug was seen while recording ${REC}, but the automated
replay checks (redraw, markers) pass. User's description of the glitch: "${DESC}".
Read docs/harness-quickstart.md and docs/harness.md. Investigate: replay with a
small --every; use "${CLI} extract" to cut the stream at suspicious points and
"${CLI} run --case ... --dump" / --oracle tmux to inspect screens and state
around them; relate what you see to the description. Goal: produce ONE
deterministic failing case file under /tmp/ (state, redraw or markers check).
Do not modify the repository. If you cannot make a failing case, say so in the
report with what you observed and where you looked.`,
    { schema: PROBE_SCHEMA, label: 'probe' })
  if (!probe || !probe.found) {
    return {
      status: 'not-reproduced',
      report: probe ? probe.report : 'probe agent failed',
      advice: 'The recording did not yield a machine-checkable failure. Debug interactively from the trace and the user description.',
    }
  }
  targets = [{ offset: null, check: probe.check || 'redraw', path: probe.case_path, geometry: probe.geometry || replay.geometry }]
} else {
  // First failing offset per check type; minimization dedupes the rest.
  for (const chk of ['redraw', 'markers']) {
    const f = replay.failures.find(x => x.check === chk)
    if (f) targets.push({ offset: f.offset, check: chk, geometry: replay.geometry })
  }
  log(`failing offsets: ${replay.failures.map(f => `${f.offset}(${f.check})`).join(', ')}`)
}

// ============================================================= Localize
phase('Localize')
const minimized = (await parallel(targets.map((t, i) => () => agent(MECH +
  (t.path
    ? `A failing case already exists at ${t.path}.
Run: ${CLI} minimize --case ${t.path} --checks ${t.check} --geometry ${t.geometry} --out /tmp/wf-min-${i}.bin`
    : `Run, in order:
1. ${CLI} extract --rec ${REC} --to ${t.offset} --out /tmp/wf-cut-${i}.bin
2. ${CLI} minimize --case /tmp/wf-cut-${i}.bin --checks ${t.check} --geometry ${t.geometry} --out /tmp/wf-min-${i}.bin`) +
  `
From the minimize JSON report: minimal_path=/tmp/wf-min-${i}.bin, minimal_inspect,
result.signature, and the failing check object from result.checks (as a JSON
string) in failing_detail. ok=false (with error) only if a command errored in a
way that produced no minimize JSON.`,
  { schema: MIN_SCHEMA, label: `minimize:${t.check}`, phase: 'Localize' })
  .then(m => m && m.ok ? { ...m, geometry: t.geometry } : (log(`minimize failed for ${t.check}: ${m && m.error}`), null))
))).filter(Boolean)

const seen = new Set()
const repros = minimized.filter(m => !seen.has(m.signature) && seen.add(m.signature)).slice(0, MAX_BUGS)
if (repros.length === 0) throw new Error('reproduced, but no failure survived minimization - inspect /tmp/wf-cut-*.bin manually')
log(`${repros.length} distinct bug(s) after dedup by signature`)

// ============================================================= Diagnose
phase('Diagnose')
const diagnosed = (await parallel(repros.map(r => () => agent(
  `Diagnose a terminal emulator bug. You may read anything but MODIFY NOTHING.

Minimal repro (Ruby string syntax): ${r.minimal_inspect}
Failing check: ${r.check}. Failure detail: ${r.failing_detail}
Reproduce with: ${CLI} run --case ${r.minimal_path} --checks ${r.check} --geometry ${r.geometry} --dump

Background: docs/harness.md (check semantics: "state" = grid wrong in lib/term.rb's
interpretation; "redraw"/"markers" = grid right but incremental rendering wrong,
usually lib/trackchanges.rb / lib/windowadapter.rb / the scroll-blit paths),
docs/state-schema.md (dump format). The render sink under test is modelled by
harness/lib/virtualwindow.rb, which mirrors lib/window.rb's drawing ops.

Trace the repro bytes through the code (lib/term.rb handle_csi/handle_escape/
putchar -> lib/termbuffer.rb -> lib/trackchanges.rb -> lib/windowadapter.rb) and
identify the root cause: the mechanism, not just the symptom. Vary the repro
(${CLI} run on edited copies under /tmp/) to confirm or kill your hypothesis
before settling.`,
  { schema: HYP_SCHEMA, label: `diagnose:${r.check}`, phase: 'Diagnose' })
  .then(h => h ? { ...r, hyp: h } : null)
))).filter(Boolean)
diagnosed.forEach(d => log(`hypothesis (${d.hyp.confidence}): ${d.hyp.summary}`))

// ============================================================= Red test
phase('Red test')
const redCases = []
for (const d of diagnosed) {
  const red = await agent(MECH +
    `Add a regression case for a confirmed bug (root cause: ${d.hyp.summary}).
1. Pick a free filename cases/bugs/${d.hyp.suggested_case_name}.bin (append -2
   etc. if taken) and copy ${d.minimal_path} to it.
2. ${d.geometry !== '80x24' ? `Write cases/bugs/<name>.meta.json: {"geometry": "${d.geometry}", "reason": "promoted from recording; fails only at this geometry"}.` : 'No meta sidecar needed (default geometry).'}
3. Run: ${CLI} run --case cases/bugs/<name>.bin --checks ${d.check} --geometry ${d.geometry}
   red = it exits 1 (the bug is still unfixed at this point, so it must be red).
Report case_path, case_id (bugs/<name>), red, and the signature from the run JSON.`,
    { schema: RED_SCHEMA, label: `red:${d.hyp.suggested_case_name}`, phase: 'Red test' })
  if (!red || !red.red) {
    log(`SKIPPING ${d.hyp.suggested_case_name}: regression case did not go red`)
    continue
  }
  redCases.push({ ...d, case_path: red.case_path, case_id: red.case_id })
}
if (redCases.length === 0) throw new Error('no red regression case could be established')

// ================================================================= Fix
// Sequential: fixes share lib/ and each is gated before the next starts.
const fixed = []
const unfixed = []
for (const bug of redCases) {
  let verdict = null
  let fix = null
  for (let attempt = 1; attempt <= FIX_ATTEMPTS; attempt++) {
    fix = await agent(
      `Fix ONE bug in the terminal emulator (attempt ${attempt}/${FIX_ATTEMPTS}).

Root-cause hypothesis (${bug.hyp.confidence} confidence): ${bug.hyp.summary}
Mechanism: ${bug.hyp.mechanism}
Suspect locations: ${bug.hyp.files.join(', ')}
Repro: ${CLI} run --case ${bug.case_path} --checks ${bug.check} --geometry ${bug.geometry}   (currently fails)
${attempt > 1 ? `Previous attempt did not verify. Verifier notes:\n${verdict && verdict.notes}\n` : ''}
Rules (binding):
- Fix the cause in production code (lib/, termtest.rb). Trust the hypothesis only
  as far as it matches what you read in the code.
- NEVER edit harness/, cases/, ratchet.json, or existing tests to make anything pass.
  You may ADD unit tests to test/.
- Match the existing code style (CLAUDE.md: terse but readable, 2-space indent).
- There are other known-failing cases; you only need YOUR repro green without
  breaking ratcheted cases: check with
  ${CLI} sweep --cases cases --oracle tmux --ratchet ratchet.json
- Done when your repro passes, the ratchet sweep passes, and rake test is green.
The pipeline verifies independently; misreporting wastes a fix attempt.`,
      { schema: FIX_SCHEMA, label: `fix:${bug.hyp.suggested_case_name}`, phase: 'Fix' })

    verdict = await agent(verifyPrompt([{ path: bug.case_path, check: bug.check, geometry: bug.geometry }], '80x24'),
      { schema: VERIFY_SCHEMA, label: `verify:${bug.hyp.suggested_case_name}`, phase: 'Fix' })
    if (verdict && verdict.case_pass && verdict.ratchet_pass && verdict.tests_pass) break
    log(`fix attempt ${attempt} for ${bug.hyp.suggested_case_name} failed verification`)
  }

  if (verdict && verdict.case_pass && verdict.ratchet_pass && verdict.tests_pass) {
    fixed.push({ ...bug, fix })
    log(`FIXED: ${bug.hyp.suggested_case_name} (${(fix && fix.files_changed || []).join(', ')})`)
  } else {
    unfixed.push({ ...bug, verifier_notes: verdict && verdict.notes })
    await agent(MECH +
      `A fix attempt failed verification and must not contaminate later fixes.
Run: git status --short, then revert all changes to lib/ and termtest.rb ONLY
(git checkout -- lib/ termtest.rb). Leave cases/bugs/ and any new test/ files in
place. Confirm with git status --short.`,
      { label: `revert:${bug.hyp.suggested_case_name}`, phase: 'Fix' })
    log(`UNFIXED (reverted): ${bug.hyp.suggested_case_name} - red case stays as backlog`)
  }
}

// ============================================================== Cleanup
phase('Cleanup')
let cleanupNote = 'no fixes to clean up'
if (fixed.length > 0) {
  await agent(MECH + `Run: git diff > /tmp/wf-verified-fix.diff and confirm the file is non-empty.`,
    { label: 'snapshot-diff', phase: 'Cleanup' })

  await agent(
    `Review and minimise the uncommitted fix in this repo (git diff; the verified
state is saved at /tmp/wf-verified-fix.diff).
Bugs fixed: ${fixed.map(f => f.hyp.summary).join(' | ')}
Goals, in order: (1) remove anything not needed to fix the bugs - debug output,
defensive code for impossible states, stray comments; (2) simplify per CLAUDE.md
style (terse but readable; the project values small code); (3) keep behaviour
identical otherwise. NEVER touch harness/, cases/, ratchet.json.
After each change re-run the fixed case(s):
${fixed.map(f => `${CLI} run --case ${f.case_path} --checks ${f.check} --geometry ${f.geometry}`).join('\n')}
and finish with rake test. If a simplification breaks anything, undo it
(git checkout + git apply /tmp/wf-verified-fix.diff restores the verified state).
If the diff is already minimal, change nothing and say so.`,
    { label: 'simplify', phase: 'Cleanup' })

  const finalVerdict = await agent(
    verifyPrompt(fixed.map(f => ({ path: f.case_path, check: f.check, geometry: f.geometry })), '80x24'),
    { schema: VERIFY_SCHEMA, label: 'verify:final', phase: 'Cleanup' })

  if (finalVerdict && finalVerdict.case_pass && finalVerdict.ratchet_pass && finalVerdict.tests_pass) {
    await agent(MECH +
      `Run: ${CLI} sweep --cases cases --oracle tmux --ratchet ratchet.json --update-ratchet
This folds the now-passing regression case(s) into the ratchet. Report the exit status.`,
      { label: 'update-ratchet', phase: 'Cleanup' })
    cleanupNote = 'cleaned up, verified, ratchet updated'
  } else {
    await agent(MECH +
      `Cleanup broke verification. Restore the verified fix exactly:
git checkout -- lib/ termtest.rb test/ && git apply /tmp/wf-verified-fix.diff
Then run rake test and report.`,
      { label: 'restore-verified', phase: 'Cleanup' })
    cleanupNote = 'cleanup attempt broke verification; restored the pre-cleanup verified fix. Ratchet NOT updated - run sweep --update-ratchet after review.'
  }
}

// ================================================================ done
return {
  status: fixed.length > 0 ? 'fixed' : 'reproduced-not-fixed',
  recording: REC,
  bugs_fixed: fixed.map(f => ({
    case: f.case_id, check: f.check, signature: f.signature,
    repro: f.minimal_inspect, cause: f.hyp.summary,
    files_changed: f.fix && f.fix.files_changed,
  })),
  bugs_unfixed: unfixed.map(f => ({
    case: f.case_id, check: f.check, repro: f.minimal_inspect,
    hypothesis: f.hyp.summary, verifier_notes: f.verifier_notes,
    note: 'red regression case left in cases/bugs/ as backlog',
  })),
  cleanup: cleanupNote,
  uncommitted: 'Changes are left uncommitted for review.',
}
