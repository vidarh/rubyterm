export const meta = {
  name: 'debug-recording',
  description: 'Reproduce, diagnose, red-test, fix and clean up terminal bugs from a pty recording',
  whenToUse: 'When the user provides a .rec file (made with `ruby harness/cli.rb record`) capturing a terminal rendering/state bug and wants it debugged end to end. args: {rec: "path.rec", description: "what looked wrong"} (or just the path as a string).',
  phases: [
    { title: 'Hunt', detail: 'deterministic search: harness hunt scans configs, minimizes repros' },
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

// Flags that pin down how a repro fails: the check needs its oracle
// (state is only meaningful against tmux), the geometry, and - for
// chunk-phase-dependent bugs like split escape/UTF-8 sequences - the
// feed chunk size.
const flagsFor = (t) =>
  `--checks ${t.check} --geometry ${t.geometry}` +
  (t.chunk ? ` --chunk ${t.chunk}` : '') +
  (t.check === 'state' ? ' --oracle tmux' : '')

// ------------------------------------------------------------- schemas
const REPRO_PROPS = {
  check: { type: 'string' },
  signature: { type: 'string' },
  case_path: { type: 'string' },
  meta_path: { type: 'string' },
  geometry: { type: 'string' },
  chunk: { type: 'integer' },
  bytes: { type: 'integer' },
  minimal_inspect: { type: 'string' },
  failing_detail: { type: 'string', description: 'the failing_detail object as a JSON string' },
}

const HUNT_SCHEMA = {
  type: 'object',
  required: ['found', 'repros'],
  properties: {
    found: { type: 'boolean' },
    note: { type: 'string' },
    repros: {
      type: 'array',
      items: { type: 'object',
               required: ['check', 'signature', 'case_path', 'geometry', 'chunk', 'minimal_inspect'],
               properties: REPRO_PROPS },
    },
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
    chunk: { type: 'integer', description: 'the --chunk value it fails under (omit if default)' },
    report: { type: 'string' },
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

const verifyPrompt = (cases) => MECH +
  `Verification gate. Run, in order:
1. ${cases.map(c => `${CLI} run --case ${c.case_path} ${flagsFor(c)}`).join('\n   ')}
   (case_pass = ALL exit 0)
2. ${CLI} sweep --cases cases --oracle tmux --ratchet ratchet.json   (ratchet_pass = exit 0)
3. rake test   (tests_pass = "0 failures, 0 errors")
On any failure, copy the relevant failing diff/output into notes verbatim.`

// ================================================================ Hunt
// Reproduction and minimization are fully deterministic: one harness
// command scans configurations (chunk sizes, offset checkpoints,
// end-state vs oracle) and emits minimal repros. The agent only
// relays JSON.
phase('Hunt')
log(`hunting ${REC}`)
const hunt = await agent(MECH +
  `Run: ${CLI} hunt --rec ${REC}
(This scans feed-chunk sizes and check offsets, then minimizes; it can take
several minutes. Use a generous Bash timeout, e.g. 600000ms.)
Report found, note, and the repros array verbatim (failing_detail as a JSON
string).`,
  { schema: HUNT_SCHEMA, label: 'hunt' })
if (!hunt) throw new Error('hunt agent failed')

let repros = (hunt.repros || []).slice(0, MAX_BUGS)

if (repros.length === 0) {
  // Nothing machine-checkable: fall back to a judgment probe driven
  // by the user's description.
  log('hunt found nothing mechanically; probing from the user description')
  const probe = await agent(
    `A terminal emulator bug was seen while recording ${REC}, but the harness's
deterministic hunt (${CLI} hunt --rec ${REC}) found nothing${hunt.note ? ` (note: ${hunt.note})` : ''}.
User's description of the glitch: "${DESC}".
Read docs/harness-quickstart.md and docs/harness.md. Investigate: replay with a
small --every; use "${CLI} extract" to cut the stream at suspicious points and
"${CLI} run --case ... --dump" / --oracle tmux to inspect screens and state
around them; consider mid-stream resizes (hunt skips the state oracle when the
recording resizes); relate what you see to the description. Goal: produce ONE
deterministic failing case file under /tmp/. Do not modify the repository.
If you cannot make a failing case, say so in the report with what you observed.`,
    { schema: PROBE_SCHEMA, label: 'probe' })
  if (!probe || !probe.found) {
    return {
      status: 'not-reproduced',
      report: probe ? probe.report : 'probe agent failed',
      advice: 'The recording did not yield a machine-checkable failure. Debug interactively from the trace and the user description.',
    }
  }
  const t = { check: probe.check || 'redraw', geometry: probe.geometry || '80x24', chunk: probe.chunk }
  const min = await agent(MECH +
    `Run: ${CLI} minimize --case ${probe.case_path} ${flagsFor(t)} --out /tmp/wf-min-probe.bin
From the minimize JSON report case_path=/tmp/wf-min-probe.bin, minimal_inspect,
signature (= result.signature), check=${t.check}, geometry=${t.geometry},
chunk=${t.chunk || 128}, bytes (= minimal_bytes), and failing_detail (the
failing check object from result.checks, as a JSON string).`,
    { schema: { type: 'object', required: ['check', 'signature', 'case_path', 'geometry', 'chunk', 'minimal_inspect'], properties: REPRO_PROPS },
      label: 'minimize:probe' })
  if (!min) throw new Error('probe produced a case but minimization failed')
  repros = [min]
}
repros.forEach(r => log(`repro: ${r.check}@chunk=${r.chunk} ${r.bytes} bytes (${r.signature})`))

// ============================================================= Diagnose
phase('Diagnose')
const diagnosed = (await parallel(repros.map(r => () => agent(
  `Diagnose a terminal emulator bug. You may read anything but MODIFY NOTHING.

Minimal repro (Ruby string syntax): ${r.minimal_inspect}
Failing check: ${r.check}. Failure detail: ${r.failing_detail}
It fails under this exact configuration (chunk size matters - chunk-split
escape/UTF-8 sequences are a common bug class):
  ${CLI} run --case ${r.case_path} ${flagsFor(r)} --dump

Background: docs/harness.md (check semantics: "state" = wrong grid - parsing,
interpretation or decoding, see lib/term.rb and lib/utf8decoder.rb; "redraw"/
"markers" = grid right but incremental rendering wrong, usually
lib/trackchanges.rb / lib/windowadapter.rb / scroll-blit paths),
docs/state-schema.md (dump format). The render sink under test is modelled by
harness/lib/virtualwindow.rb, which mirrors lib/window.rb's drawing ops.

Trace the repro bytes through the code (lib/utf8decoder.rb -> lib/term.rb
feed/putchar/handle_csi/handle_escape -> lib/termbuffer.rb ->
lib/trackchanges.rb -> lib/windowadapter.rb) and identify the root cause: the
mechanism, not just the symptom. Vary the repro (${CLI} run on edited copies
under /tmp/, varying --chunk) to confirm or kill your hypothesis before
settling.`,
  { schema: HYP_SCHEMA, label: `diagnose:${r.check}`, phase: 'Diagnose' })
  .then(h => h ? { ...r, hyp: h } : null)
))).filter(Boolean)
diagnosed.forEach(d => log(`hypothesis (${d.hyp.confidence}): ${d.hyp.summary}`))
if (diagnosed.length === 0) throw new Error('no diagnosis succeeded')

// ============================================================= Red test
phase('Red test')
const redCases = []
for (const d of diagnosed) {
  const red = await agent(MECH +
    `Add a regression case for a confirmed bug (root cause: ${d.hyp.summary}).
1. Pick a free filename cases/bugs/${d.hyp.suggested_case_name}.bin (append -2
   etc. if taken) and copy ${d.case_path} to it.
2. ${(d.geometry !== '80x24' || (d.chunk && d.chunk !== 128))
      ? `Copy ${d.meta_path || 'the repro\'s .meta.json sidecar'} to cases/bugs/<name>.meta.json (it records geometry/chunk; keep only non-default fields plus a one-line reason).`
      : 'No meta sidecar needed (default geometry and chunk).'}
3. Run: ${CLI} run --case cases/bugs/<name>.bin ${flagsFor(d)}
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
Repro: ${CLI} run --case ${bug.case_path} ${flagsFor(bug)}   (currently fails)
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

    verdict = await agent(verifyPrompt([bug]),
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
${fixed.map(f => `${CLI} run --case ${f.case_path} ${flagsFor(f)}`).join('\n')}
and finish with rake test. If a simplification breaks anything, undo it
(git checkout + git apply /tmp/wf-verified-fix.diff restores the verified state).
If the diff is already minimal, change nothing and say so.`,
    { label: 'simplify', phase: 'Cleanup' })

  const finalVerdict = await agent(verifyPrompt(fixed),
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
