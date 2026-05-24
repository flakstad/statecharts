# Benchmarks

Benchmarks are part of the development feedback loop. Performance changes should be measured before and after when they affect dispatch, memory allocation, chart compilation, or active configuration handling.

## Dispatch Benchmark

Benchmark source:

```text
benchmarks/dispatch_bench.odin
```

Run:

```sh
odin run benchmarks/dispatch_bench.odin -file -collection:local=. -o:speed
```

When running through a temporary collection directory, point `local:statecharts`
at the package directory inside the checkout:

```sh
mkdir -p /tmp/statecharts-odin-local
ln -sfn "$PWD/statecharts" /tmp/statecharts-odin-local/statecharts
odin run benchmarks/dispatch_bench.odin -file -collection:local=/tmp/statecharts-odin-local -o:speed
```

The benchmark uses a two-state ping-pong chart and dispatches the same event repeatedly.

It measures:

- Best and average nanoseconds per dispatch across repeated samples.
- Maximum allocator calls across samples.
- Maximum resize calls across samples.
- Maximum free calls across samples.
- Maximum bytes requested across samples.
- A loose regression guard that fails the process if core dispatch modes exceed timing thresholds or allocate.

The benchmark includes these modes:

- `scratch-buffer dispatch`: current implementation, where trace buffers are owned by `Instance` and reused.
- `caller-owned transition trace dispatch`: dispatch plus caller-owned transition-step trace output.
- `run-to-completion dispatch with one raised event`: one external event that raises and processes one internal event.
- `due timer dispatch`: app-clock timer processing with one due `After_Def` event per dispatch.
- `allocating trace/path dispatch`: simulated previous owned-result/path allocation model, where per-dispatch trace/path arrays are allocated and freed.
- `wide transition lookup dispatch`: 32-state ring chart with one transition per state, used to measure transition lookup costs.

## Current Measurement

Measured on May 23, 2026:

```text
scratch-buffer dispatch
  iterations:       2000000
  total:            60.109292ms
  ns/dispatch:      30.05
  alloc calls:      0
  resize calls:     0
  free calls:       0
  bytes requested:  0
  checksum:         8000000

allocating trace/path dispatch
  iterations:       2000000
  total:            305.593208ms
  ns/dispatch:      152.80
  alloc calls:      8000000
  resize calls:     0
  free calls:       8000000
  bytes requested:  512000000
  checksum:         10000000

wide transition lookup dispatch
  iterations:       2000000
  total:            56.841458ms
  ns/dispatch:      28.42
  alloc calls:      0
  resize calls:     0
  free calls:       0
  bytes requested:  0
  checksum:         8000000
```

Interpretation:

- Current dispatch performed no heap allocation in the measured loop.
- The scratch-buffer approach was about 5.1x faster in this microbenchmark.
- The allocation-heavy model requested about 512 MB over 2M dispatches.

## Transition Lookup Measurement

Before compiled transition adjacency, the 32-state ring benchmark scanned all transition definitions while searching for the active source state's transition.

Baseline measured before adjacency tables:

```text
wide source-scan dispatch
  iterations:       2000000
  total:            140.515042ms
  ns/dispatch:      70.26
  alloc calls:      0
  bytes requested:  0
```

After compiling transitions into source adjacency ranges:

```text
wide transition lookup dispatch
  iterations:       2000000
  total:            117.323625ms
  ns/dispatch:      58.66
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Source adjacency improved this benchmark by about 16.5%.
- The change did not introduce dispatch-loop allocation.
- Larger charts with more transitions per chart should benefit more than the two-state benchmark.

## Dense Runtime Index Measurement

After source adjacency, dispatch still converted active leaf states and transition endpoints from user enum values to state indices during dispatch. The runtime now stores active leaves as state indices and compiles transition source/target indices.

Baseline before dense runtime indices:

```text
scratch-buffer dispatch
  ns/dispatch:      32.25

wide transition lookup dispatch
  ns/dispatch:      58.98
```

After dense active leaves and transition endpoint indices:

```text
scratch-buffer dispatch
  ns/dispatch:      30.86

wide transition lookup dispatch
  ns/dispatch:      28.03
```

Interpretation:

- Simple two-state dispatch improved by about 4.3%.
- The 32-state transition lookup benchmark improved by about 52.5%.
- The change did not introduce dispatch-loop allocation.

After this measurement, internal dense indices were converted from plain `int` to distinct `State_Index` and `Transition_Index` types for readability and type safety. That cleanup kept dispatch allocation-free. It measured slightly slower than the best plain-int run, but still materially faster than the pre-dense-index baseline:

```text
typed-index scratch-buffer dispatch
  ns/dispatch:      30.05

typed-index wide transition lookup dispatch
  ns/dispatch:      28.42
```

## Internal Region Metadata Measurement

The runtime now compiles current `Region_Def` entries into internal region metadata. Legacy `Initial_Def` entries still work as compatibility input. This prepares the engine for explicit regions and orthogonal states. Dispatch does not yet use this metadata in the hot path, so no material dispatch change is expected.

Measured after adding internal region metadata:

```text
scratch-buffer dispatch
  ns/dispatch:      29.40
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      27.80
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- The result is within the same range as the typed-index baseline.
- The region work is primarily a structural stepping stone, not a dispatch optimization.

This is a microbenchmark, not a full application profile. It is still useful because dispatch allocation is a core design constraint for this package.

## Region-Backed OR Entry Measurement

Default entry now follows compiled region metadata instead of reading the public initial-substate table directly. This keeps the current OR-state behavior aligned with the internal model needed for orthogonal regions.

Measured after routing OR entry through compiled regions:

```text
scratch-buffer dispatch
  ns/dispatch:      29.76
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      27.51
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- Scratch-buffer dispatch is effectively in the same range as the previous `29.40 ns/dispatch` run.
- The change is structural: initial entry now uses the compiled region model that orthogonal states will extend.

## State-Kind Validation Measurement

`State_Def` now exposes `State_Kind` with an `.Inferred` default, explicit `.Atomic` validation, and future-facing `.And` validation. This is compile-time metadata and validation work; dispatch does not branch on state kind yet.

Measured after adding state-kind validation:

```text
scratch-buffer dispatch
  ns/dispatch:      29.16
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      26.99
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- No dispatch regression is visible; this change currently affects chart compilation and validation.

## Multi-Leaf Dispatch Selection Measurement

Dispatch now scans every active leaf internally and applies an external transition to the matched leaf instead of clearing the whole active set. Public entry semantics still produce one active leaf, but this prepares the runtime for orthogonal regions.

Measured after adding multi-leaf dispatch selection:

```text
scratch-buffer dispatch
  ns/dispatch:      29.93
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      27.76
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- The extra active-leaf loop costs roughly `0.77 ns/dispatch` compared with the previous `29.16 ns/dispatch` run in this microbenchmark.
- This is acceptable for now because it moves the hot path toward orthogonal configurations without changing the public API.
- A measured single-leaf fast-path attempt was rejected because it slowed this benchmark to `30.13 ns/dispatch`.

## Executable AND Entry Measurement

Explicit `.And` states can now enter multiple owned `Region_Def` entries. This is an intermediate unnamed-region model: each region enters a direct child branch, and branch-local transitions preserve other active branches.

Measured after adding executable AND entry:

```text
scratch-buffer dispatch
  ns/dispatch:      30.04
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      27.60
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- Scratch dispatch is effectively flat against the previous `29.93 ns/dispatch` run.
- The new work mostly affects entry and compiled region metadata; dispatch already paid for active-leaf scanning in the previous step.

## AND Exit-Set Measurement

External transitions now compute an exit root. If a transition leaves a containing `.And` state, all active descendant branches under that exited state are removed and exited. This fixes stale sibling branches when a branch transition targets outside the containing concurrent state.

The first implementation was correct but too expensive on the common single-leaf path:

```text
initial AND exit-set implementation
  scratch-buffer dispatch: 36.00 ns/dispatch
  wide transition lookup:  33.98 ns/dispatch
```

After adding unchecked single-leaf exit paths and a narrower leaf-source fast path:

```text
scratch-buffer dispatch
  ns/dispatch:      31.12
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      28.54
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- The final measured overhead is roughly `1.08 ns/dispatch` over the previous `30.04 ns/dispatch` executable-AND-entry run.
- The rejected implementation is recorded because the measurement directly shaped the final code.

## Multi-Region Macrostep Measurement

Dispatch now collects and applies multiple non-conflicting branch-local transitions across active regions for one event. Conflicting transitions that would exit shared active ancestors are still narrowed to a deterministic single transition.

The first implementation was correct but too expensive for OR-only charts:

```text
initial multi-transition collection
  scratch-buffer dispatch: 40.17 ns/dispatch
  wide transition lookup:  36.71 ns/dispatch
```

Adding a single-active-leaf fast path improved it, but still left too much helper overhead:

```text
single-leaf fast path before inlining
  scratch-buffer dispatch: 36.56 ns/dispatch
  wide transition lookup:  33.01 ns/dispatch
```

After force-inlining the single-leaf lookup and transition application helpers:

```text
scratch-buffer dispatch
  ns/dispatch:      32.47
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      29.59
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- The final measured overhead is roughly `1.35 ns/dispatch` over the previous `31.12 ns/dispatch` exit-set run.
- The measured failed attempts are kept here because they directly shaped the fast path.

## Orthogonal Conflict Priority Measurement

Overlapping transition conflicts now use descendant-source priority. A child transition preempts an ancestor transition even if the ancestor transition is discovered first from another active region.

The first implementation added a second candidate-selection pass directly to the dispatch body and regressed OR-only dispatch:

```text
initial descendant-priority selector
  scratch-buffer dispatch: 39.35 ns/dispatch
  wide transition lookup:  31.03 ns/dispatch
```

After splitting the multi-leaf selector out of the hot single-leaf dispatch body and avoiding candidate scratch clears in `reset_dispatch_scratch`:

```text
scratch-buffer dispatch
  ns/dispatch:      32.20
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      29.90
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- The final measured result is effectively flat against the previous `32.47 ns/dispatch` multi-region macrostep run.
- Separating hot single-leaf dispatch from multi-leaf selection is important for keeping OR-only charts cheap.

## Rejected Macrostep Transition Trace Measurement

An always-on `Dispatch_Result.transitions` slice was tested with one `{source, target}` entry for each applied transition in a macrostep. Existing `source` and `target` fields would have remained for compatibility and reported the last applied transition.

Measured after adding the transition trace slice directly:

```text
scratch-buffer dispatch
  ns/dispatch:      35.28
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      32.41
  alloc calls:      0
  bytes requested:  0
```

Measuring an alternate transition-index scratch plus finalize materialization was worse:

```text
transition-index trace materialized during finalize
  scratch-buffer dispatch: 38.99 ns/dispatch
  wide transition lookup:  36.14 ns/dispatch
```

Interpretation:

- Both designs remained allocation-free but added too much overhead to always-on dispatch.
- The public `transitions` slice was rejected for now.
- After backing out always-on transition tracing, scratch dispatch measured `31.92 ns/dispatch` with zero allocations.

## Caller-Owned Transition Trace Measurement

`dispatch_with_trace` fills a caller-owned `[dynamic]Transition_Step(State)` buffer. Normal `dispatch` does not trace transitions and should retain the hot-path baseline.

Measured after adding `dispatch_with_trace`:

```text
scratch-buffer dispatch
  ns/dispatch:      32.68
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      34.06
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      30.73
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Normal dispatch remains allocation-free and close to the previous `31.92 ns/dispatch` restored baseline.
- Caller-owned transition tracing is also allocation-free when the caller reserves the output buffer.
- The opt-in trace path measured roughly `1.38 ns/dispatch` slower than normal dispatch in this microbenchmark.

## AND Region Validation Measurement

The unnamed `.And` model now validates that every direct child branch has exactly one region initial. This is compile-time validation and should not affect dispatch.

Measured after adding the validation:

```text
scratch-buffer dispatch
  ns/dispatch:      32.41
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      33.79
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      30.89
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Normal dispatch stayed allocation-free and in line with the prior `32.68 ns/dispatch` measurement.
- The validation happens during `compile`; no per-dispatch state or branch was added.

## Named Region Measurement

`Region_Def` now carries an optional `name`, duplicate non-empty names are rejected per superstate, and `active_leaf_in_region` can query the active leaf for a named region. Normal dispatch does not call the region-name lookup path.

Measured after adding named regions and the game character controller showcase:

```text
scratch-buffer dispatch
  ns/dispatch:      31.88
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      33.10
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      30.77
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Normal dispatch stayed allocation-free and slightly faster than the prior `32.41 ns/dispatch` run, within normal microbenchmark noise.
- Named region lookup is opt-in application code; the dispatch hot path did not gain a string comparison.

## Shallow History Measurement

Shallow history adds `History_Def`, compiled history targets, and an instance-owned dense table that remembers the last direct child exited under a compound state. The first implementation recorded history on every exit and resolved history-capable targets for every transition.

First measurement:

```text
scratch-buffer dispatch
  ns/dispatch:      33.44
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      34.81
  alloc calls:      0
  bytes requested:  0
```

After adding a no-history transition fast path for charts without history definitions:

```text
scratch-buffer dispatch
  ns/dispatch:      32.40
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      33.79
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      30.40
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Shallow history remains allocation-free after `init`.
- Normal no-history charts avoid the history target path in `apply_transition_step`.
- The optimized no-history dispatch path is close to the previous named-region measurement of `31.88 ns/dispatch`; the remaining difference is small enough to track over repeated runs rather than optimize blindly.

## Deep History Measurement

Deep history for OR hierarchies adds a second dense history table on the instance. On leaf exit, the runtime records that leaf for ancestor deep-history targets. Deep history under `And` states also records one remembered leaf per compiled region so concurrent history can restore multiple active leaves.

Measured after adding deep history and keeping the no-history transition fast path:

```text
scratch-buffer dispatch
  ns/dispatch:      33.15
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      33.75
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      30.28
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- A helper extraction for the history transition path was tried and measured worse (`34.30 ns/dispatch` normal), so it was backed out.
- The no-history benchmark remains in the same low-30ns range, but history support has made the hot function more sensitive to code layout. Keep watching this before adding run-to-completion.

## Run-To-Completion Measurement

Run-to-completion dispatch adds an instance-owned internal event queue. Transition actions can call `raise` to append internal events, and `dispatch_run_to_completion` processes those events until the chart reaches a stable configuration. The queue is reserved during `init`; overflow returns `Error` instead of allocating. Applications can pass `Init_Options.internal_event_capacity` to reserve a larger queue up front.

Measured after adding run-to-completion dispatch and a benchmark case with one raised internal event:

```text
scratch-buffer dispatch
  ns/dispatch:      32.51
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      35.11
  alloc calls:      0
  bytes requested:  0

run-to-completion dispatch with one raised event
  ns/dispatch:      78.60
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      30.67
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Normal dispatch stayed allocation-free and close to the previous `33.15 ns/dispatch` deep-history measurement.
- Run-to-completion with one raised event costs about 2.4x normal dispatch in this microbenchmark because it performs two transition steps and queue bookkeeping.
- The run-to-completion path is also allocation-free after `init`.

## Final State Measurement

Final states add `State_Kind.Final`, `Done_Def`, `is_complete`, and run-to-completion completion-event raising. Normal dispatch does not run completion checks, but this change still affected code layout enough to show up in the microbenchmark.

Measured after adding final states and completion events:

```text
scratch-buffer dispatch
  ns/dispatch:      34.72
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      37.15
  alloc calls:      0
  bytes requested:  0

run-to-completion dispatch with one raised event
  ns/dispatch:      86.62
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      33.65
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Dispatch remains allocation-free.
- Normal dispatch regressed from the prior `32.51 ns/dispatch` run. Completion checks are not executed by normal dispatch, so the likely cause is code layout or inlining sensitivity after adding more statechart features.
- Do not ignore this: before adding delayed events, revisit hot-path shape and consider splitting less common features out of `apply_transition_step` or adding a lower-level benchmark harness for more stable measurements.

## Delayed Event Measurement

Delayed events add `After_Def`, instance-owned active timer slots, and timed dispatch helpers. Timers are armed on state entry, cancelled on state exit, and processed by `dispatch_due_events(now_ms)`. The application owns the clock.

First delayed-event measurement showed a large no-timer regression:

```text
scratch-buffer dispatch
  ns/dispatch:      36.97
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      53.53
  alloc calls:      0
  bytes requested:  0
```

An attempted no-timer split in `enter_from_index` measured worse and was backed out. Marking the timer schedule/cancel helpers `#force_inline` recovered some normal dispatch performance but remained noisy:

```text
scratch-buffer dispatch
  ns/dispatch:      38.81
  alloc calls:      0
  bytes requested:  0

caller-owned transition trace dispatch
  ns/dispatch:      35.94
  alloc calls:      0
  bytes requested:  0

run-to-completion dispatch with one raised event
  ns/dispatch:      95.66
  alloc calls:      0
  bytes requested:  0

wide transition lookup dispatch
  ns/dispatch:      42.44
  alloc calls:      0
  bytes requested:  0
```

Interpretation:

- Delayed event dispatch is allocation-free after `init`, proven by tests.
- The no-timer hot path is now too sensitive to code layout. Before adding more features, build a tighter benchmark harness and isolate optional feature paths more aggressively.

## Repeated-Sample Benchmark Harness

The benchmark now runs five samples per mode and reports both best and average
nanoseconds per dispatch. This makes layout noise easier to see without treating
one sample as the whole story. It also includes a due-timer benchmark so delayed
event changes measure both the no-timer hot path and the timer path.

Measured on May 24, 2026:

```text
scratch-buffer dispatch
  iterations/sample: 2000000
  samples:           5
  best ns/dispatch:  36.05
  avg ns/dispatch:   36.24
  alloc calls max:   0
  resize calls max:  0
  free calls max:    0
  bytes req max:     0

caller-owned transition trace dispatch
  best ns/dispatch:  37.26
  avg ns/dispatch:   37.36
  alloc calls max:   0

run-to-completion dispatch with one raised event
  best ns/dispatch:  88.91
  avg ns/dispatch:   90.21
  alloc calls max:   0

due timer dispatch
  best ns/dispatch:  61.13
  avg ns/dispatch:   62.25
  alloc calls max:   0

allocating trace/path dispatch
  best ns/dispatch:  158.46
  avg ns/dispatch:   159.34
  alloc calls max:   8000000
  bytes req max:     512000000

wide transition lookup dispatch
  best ns/dispatch:  33.58
  avg ns/dispatch:   33.79
  alloc calls max:   0

benchmark guard: PASS
```

Interpretation:

- The previously recorded delayed-event no-timer regression did not reproduce in this repeated-sample run.
- Normal dispatch and wide lookup are back in the low-30ns range with no allocation.
- Due timer dispatch is allocation-free and measures the real `dispatch_due_events` path with one due event per iteration.
- The transition hot path now reads transition definitions by pointer after source-adjacency lookup, avoiding an unnecessary struct copy before guard evaluation.
- Conflict endpoint diagnostics are stored on the instance for `last_conflict`, keeping `Dispatch_Result` small on the hot path.
- Preemption diagnostics are also instance-owned so descendant-priority reporting does not grow normal dispatch results.
- Durable history snapshot/restore is outside the dispatch hot path; the post-change guard still passes with zero allocation in all guarded dispatch modes.
- High fan-out states now have compiled source+trigger groups, while states with one or two outgoing transitions stay on the direct source-range scan.
- `Init_Options` reserve knobs let applications pre-size larger instance buffers for long RTC cascades and wide configurations without changing normal dispatch allocation behavior.
- Complete preemption diagnostics are stored in an instance-owned buffer and remain outside `Dispatch_Result`; guarded dispatch modes remain allocation-free.
- Startup run-to-completion and due-timer trace variants reuse the existing instance-owned queue and caller-owned trace buffers; focused panic-allocator tests cover their no-allocation behavior.
- SCXML export is an offline builder API and is not on the dispatch hot path; guarded dispatch benchmarks remain allocation-free after adding it.
- `Always_Def` adds run-to-completion stabilization semantics while keeping ordinary dispatch allocation-free; no-always charts skip the stabilization helper.
- The benchmark process now exits non-zero if guarded dispatch modes allocate or exceed loose timing limits.

## Regression Test

The test suite also includes a dispatch allocation regression test using Odin's panic allocator:

```text
test_dispatch_does_not_allocate_after_init
```

That test initializes the chart and instance first, then switches `context.allocator` to `mem.panic_allocator()` before dispatch. Any heap allocation during dispatch fails the test.
