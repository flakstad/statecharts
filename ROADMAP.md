# Roadmap

This package should grow from the current hierarchical statechart MVP into a practical, efficient Harel-style statechart engine for real software systems.

The long-term target is not just "an FSM helper." The goal is a deterministic statechart runtime that can model complex contained systems with hierarchy, orthogonality, history, and run-to-completion semantics while staying efficient enough for game loops, robotics, embedded-style control, and other performance-sensitive Odin programs.

## Guiding Principles

- Preserve ordinary Odin data definitions. Prefer plain struct tables over builder DSLs.
- Keep user-facing state and event ids typed as application enums.
- Compile chart definitions into dense internal tables.
- Avoid heap allocation during dispatch after initialization.
- Make semantics explicit and testable.
- Prefer validation errors at compile time over surprising runtime behavior.
- Grow toward real Harel statecharts in layers.

## Current MVP

Implemented:

- Typed `State_Def`, `Substate_Def`, `Region_Def`, `Transition_Def`, and `Chart_Def`.
- No fake `Root` or `Top` enum state.
- Hierarchical states using superstate/substate relationships.
- Initial substates for compound states.
- External transitions.
- Internal transitions.
- Local transitions.
- Validation rejects internal transitions whose target differs from their source.
- Entry and exit actions.
- Guards.
- Typed context, event, and event-payload helpers for callbacks.
- Transition actions.
- Leaf-to-superstate transition search.
- Child transition priority over superstate transition.
- External self-transition exits and re-enters.
- External parent-to-descendant transitions exit and re-enter the source compound; local transitions preserve it.
- Validation for common malformed charts.
- Dispatch tracing with exited, entered, and configuration state arrays.
- Compile options.
- Ambiguous source/trigger transitions rejected by default.
- Opt-in declaration-order priority for ambiguous transitions.
- Instance-owned dispatch trace buffers.
- Allocation-free dispatch after instance initialization.
- Compiled source adjacency tables for transition lookup.
- Compiled source+trigger adjacency groups for high fan-out states.
- Active leaves stored as dense state indices.
- Transition source/target endpoints compiled to dense state indices.
- Internal indices use distinct `State_Index` and `Transition_Index` types.
- Current OR-style regions are compiled into internal regions.
- Public `State_Kind` vocabulary exists: `Inferred`, `Atomic`, `Or`, and `And`.
- Explicit atomic states with substates are rejected.
- Dispatch selection scans all active leaves internally.
- External transitions remove the matched active leaf instead of clearing the whole active set.
- Explicit `And` states can enter multiple `Region_Def` entries owned by the same state.
- Explicit `And` states validate that each direct child branch has exactly one region initial.
- Region definitions can carry stable names for application-facing orthogonal regions.
- Runtime code can query the active leaf in a named region without allocating.
- Branch-local transitions in one active region preserve the other active regions.
- Transitions that leave a containing `And` state exit all active descendant branches.
- One event can apply multiple non-conflicting branch-local transitions across active regions in one dispatch.
- `dispatch_with_trace` can fill a caller-owned transition-step buffer for macrostep debugging.
- Same-depth overlapping cross-region transitions report `Conflict` and leave configuration unchanged.
- `last_conflict` exposes the two overlapping transition endpoint pairs after a conflict.
- `last_conflict_indices` exposes the corresponding `Chart_Def.transitions` declaration indices.
- `last_preemption` and `last_preemption_indices` expose descendant-priority preemptions.
- `last_preemptions` and `last_preemption_indices_all` expose every preemption recorded during a dispatch/RTC macrostep.
- A game character controller showcase demonstrates locomotion, combat, and status as concurrent regions.
- Shallow history targets can resume the last direct child of a compound state.
- Deep history targets can resume one nested leaf in an OR hierarchy.
- Deep history targets on `And` states can restore one remembered leaf per owned region.
- A media player showcase demonstrates pause/resume with shallow history.
- An editor workspace showcase demonstrates deep history across concurrent regions.
- `dispatch_run_to_completion` processes raised internal events until stable.
- Transition actions can call `raise` during run-to-completion dispatch.
- Raised internal events use the same active-region broadcast selection as external events.
- `dispatch_run_to_completion_with_trace` records all transition microsteps in a caller-owned buffer.
- `Always_Def` provides eventless stabilization transitions for run-to-completion entry points.
- `Init_Options.internal_event_capacity` lets applications reserve larger RTC queues without dispatch allocation.
- `Init_Options` exposes reserve knobs for active leaves, dispatch trace buffers, configuration snapshots, paths, and transition scratch buffers.
- A workflow showcase demonstrates one external event cascading to completion.
- `active_leaves` exposes the compact persistence snapshot for active runtime leaves.
- `restore_active_leaves` supports database-backed command handlers that hydrate current state before dispatch.
- An order persistence showcase demonstrates load-dispatch-persist command handling.
- `Final` states mark compound-state completion.
- `Done_Def` can raise typed completion events during run-to-completion dispatch.
- `enter_initial_run_to_completion` processes startup entry raises and completion events until stable.
- Validation rejects final states with substates or outgoing transitions.
- Validation rejects done events on states that cannot complete.
- Validation rejects duplicate done events for the same state/trigger.
- A checkout showcase demonstrates final-state completion advancing a workflow.
- `After_Def` arms delayed events when states are entered and cancels them on exit.
- Validation rejects duplicate after events for the same state/delay/trigger.
- `dispatch_due_events` processes app-clock due timers without allocation.
- `dispatch_due_events_with_trace` records due-timer transition cascades in a caller-owned buffer.
- `next_due_event_ms` exposes the earliest active timer for application schedulers.
- `active_timers` snapshots active delayed events for durable schedulers.
- `restore_active_timers` restores persisted delayed events after active leaves have been hydrated.
- `active_history` snapshots shallow/deep remembered history for durable workflows.
- `restore_history` restores remembered history after active leaves have been hydrated.
- A network retry showcase demonstrates timeout behavior.
- `active_leaves` writes the compact leaf-only persistence snapshot into a caller-owned buffer.
- `restore_active_leaves` hydrates an instance from persisted active leaves without dispatch allocation.
- An order persistence showcase demonstrates the database-as-source-of-truth integration pattern.
- `write_dot` exports compiled charts to Graphviz DOT for inspection and review tooling.
- A DOT export showcase demonstrates writing Graphviz output through a caller-owned builder.
- `write_scxml` exports a compact SCXML subset for interchange and review tooling.
- An SCXML export showcase demonstrates emitting XML from a compiled chart.
- `write_validation_error` formats structured compile errors into contextual messages.
- A validation errors showcase demonstrates user-facing compile diagnostics.

Known MVP limitations:

- Full typed orthogonal region ids are not implemented.
- Current `And` support has named direct-child region membership and cached `Region_Handle` lookups; typed region ids are not implemented.
- Wall-clock integration is application-owned; the package only consumes caller-provided `now_ms`.
- Transition lookup keeps a direct scan for tiny source ranges and uses compiled source+trigger groups for high fan-out states.
- The dispatch benchmark now reports repeated-sample best/average results and includes a due-timer path, but more formal perf regression tooling is still future work.
- Durable active leaves, history, and timers now have snapshot/restore APIs; applications still own serialization format and database transactions.
- SCXML export is implemented for a compact runtime-structure subset; SCXML import is not implemented.

## Performance Target

Dispatch should become allocation-free after chart compilation and instance initialization.

The runtime should compile public enum-based definitions into dense indices:

```odin
State_Index :: distinct int
Transition_Index :: distinct int
Region_Index :: distinct int
```

The instance should own reusable buffers:

```odin
Instance :: struct($State, $Trigger: typeid) {
	chart: ^Chart(State, Trigger),

	active_leaves: []State_Index,
	active_bits: Bit_Set,

	exited_scratch: []State_Index,
	entered_scratch: []State_Index,
	configuration_scratch: []State_Index,
	enabled_scratch: []Transition_Index,
}
```

`dispatch` should clear and reuse scratch buffers. Result slices should be valid until the next dispatch on the same instance.

The public result can still expose user enum states:

```odin
Dispatch_Result :: struct($State: typeid) {
	status: Dispatch_Status,
	source: State,
	target: State,
	exited: []State,
	entered: []State,
	configuration: []State,
}
```

This may require the instance to maintain enum-valued scratch slices as well, or expose a separate low-level indexed trace.

## Compile-Time Tables

Transition lookup should avoid scanning all transitions for every event.

Compile source adjacency:

```odin
Transition_Range :: struct {
	start: int,
	count: int,
}

Chart :: struct($State, $Trigger: typeid) {
	def: Chart_Def(State, Trigger),

	parent_index: []State_Index,
	initial_index: []State_Index,

	transitions_by_source: []Transition_Range,
	transition_indices: []Transition_Index,
}
```

Dispatch then searches from active leaf outward through superstates and scans only transitions attached to the current source state.

Later optimization options:

- Use dense trigger tables when event enums are suitable.
- Provide a compile option to trade memory for faster dispatch.

## Phase 1: Harden The Hierarchical Core

Before adding "true Harel" features, finish the current core.

Tasks:

- Add compile options. Done.
- Reject ambiguous transitions by default. Done.
- Support opt-in declaration-order priority for ambiguous transitions. Done.
- Move dispatch trace buffers onto `Instance`. Done.
- Make dispatch allocation-free after `init`. Done.
- Add `reserve`/capacity planning during instance initialization. Done.
- Compile transition adjacency tables. Done.
- Compile source+trigger transition groups for high fan-out states. Done.
- Store active leaves and transition endpoints as dense indices. Done.
- Use distinct types for dense runtime indices. Done.
- Ensure repeated `compile`, `init`, and `enter_initial` are leak-free and deterministic. Done.
- Improve validation error messages further as new validation rules are added.
- Keep tests focused on exact semantics.

Proposed API:

```odin
Compile_Options :: struct {
	allow_ambiguous_transitions: bool,
}

compile :: proc(
	out: ^Chart($State, $Trigger),
	def: Chart_Def(State, Trigger),
	options := Compile_Options{},
) -> Compile_Result
```

Ambiguity rule:

- By default, two transitions with the same source and trigger are invalid.
- If `allow_ambiguous_transitions` is true, declaration order is priority order.
- More advanced conflict detection involving guards can be deferred.

## Phase 2: Region-Oriented Model

The current `Region_Def` model is enough for simple OR decomposition. True Harel statecharts need named regions so a superstate can contain one or more concurrent regions.

Current status:

- The public API now prefers `Region_Def`.
- `Initial_Def` remains as a compatibility type for older examples/tests.
- Compilation now builds internal region metadata from `Chart_Def.initial` and `Region_Def`.
- There is one implicit top region.
- Each superstate with an initial substate owns one internal OR-region.
- `Region_Def.name` provides a stable string label for application-facing named regions.
- `Substate_Def.region` lets direct children of an `.And` state attach to a named region.
- Region-attached substates validate that the region exists and that the parent is an `.And` state.
- Duplicate non-empty region names under the same superstate are rejected.
- `active_leaf_in_region` returns the active leaf for a named region without allocation.
- `region_handle` resolves named regions once to stable compiled handles.
- `active_leaf_in_region_handle` avoids repeated string lookup for hot integration queries.

This is still a stepping stone. Typed region ids, such as `Region_Def(State, Region)`, may still be worth adding later if string labels feel too weak for larger Odin programs.

Replace or evolve:

```odin
Region_Def
```

into:

```odin
Region_Def :: struct($State, $Region: typeid) {
	id: Region,
	superstate: State,
	initial: State,
}
```

And evolve substates from:

```odin
Substate_Def :: struct($State: typeid) {
	substate: State,
	superstate: State,
}
```

to:

```odin
Substate_Def :: struct($State, $Region: typeid) {
	substate: State,
	region: Region,
}
```

The region defines the containing superstate. This avoids repeating the superstate on every substate and gives orthogonal regions a clean identity.

Example:

```odin
Drone_Region :: enum {
	Operation,
	Flight,
	Radio,
	Navigation,
	Battery,
	Payload,
}

regions := [?]sc.Region_Def(Drone_State, Drone_Region){
	{id = .Operation, superstate = .Operational, initial = .Flight_Idle},
	{id = .Radio, superstate = .Operational, initial = .Radio_Connected},
	{id = .Battery, superstate = .Operational, initial = .Battery_Normal},
}

substates := [?]sc.Substate_Def(Drone_State, Drone_Region){
	{substate = .Flight_Idle, region = .Operation},
	{substate = .Flight_Mission, region = .Operation},
	{substate = .Radio_Connected, region = .Radio},
	{substate = .Radio_Lost, region = .Radio},
	{substate = .Battery_Normal, region = .Battery},
	{substate = .Battery_Low, region = .Battery},
}
```

Remaining design questions:

- Should region ids become typed enum values instead of strings?
- Should a future typed region API remove repeated superstate fields from region-attached substates?

Recommendation:

- Keep the current no-fake-top public model.
- Internally compile an implicit top region.
- Let region definitions describe regions inside explicit states.
- Keep string names for now because they preserve the simple `Region_Def(State)` API and avoid wrapper helpers.
- Use `Region_Handle` for applications that want to resolve names once and avoid string lookup in repeated queries.

## Phase 3: Orthogonal States

Orthogonality is the key feature that turns the package from a hierarchical state machine into a real Harel-style statechart engine.

Add state kinds:

```odin
State_Kind :: enum {
	Inferred,
	Atomic,
	Or,
	And,
}

State_Def :: struct($State: typeid) {
	id: State,
	kind: State_Kind,
	entry: Action,
	exit: Action,
}
```

Semantics:

- `Inferred`: current compatibility default; leaf states behave as `Atomic`, compound states behave as `Or`.
- `Atomic`: no regions.
- `Or`: exactly one active child region path.
- `And`: all child regions are active concurrently.

Current implementation status:

- `State_Kind` is exposed on `State_Def`.
- Existing charts can omit `kind` because `.Inferred` is the zero value.
- Explicit `.Atomic` states are validated.
- Explicit `.And` states are executable for direct-child branch regions.
- Multiple `Region_Def` entries with the same `.And` superstate are entered concurrently.
- Named direct-child regions are implemented with `Region_Def.name`.
- Direct child states can set `Substate_Def.region` to belong to a named region without a wrapper branch state.
- Region membership validation rejects unknown region names and non-`.And` parents.
- `active_leaf_in_region` provides a stable integration point for larger programs.
- `Region_Handle` provides a cached, allocation-free region query path while keeping the current string-named API.
- Transition exit sets now remove all active leaves under the highest state exited by the transition.
- Dispatch now selects all non-conflicting branch-local transitions enabled by one event.
- Overlapping transition conflicts use descendant-source priority: child transitions preempt ancestor transitions.
- Same-depth overlapping transition conflicts return `Dispatch_Status.Conflict` without applying a transition.
- `last_conflict` exposes both conflicting transition endpoint pairs without increasing `Dispatch_Result` size.
- `last_conflict_indices` exposes both conflicting transition declaration indices for unambiguous diagnostics.
- `last_preemption` exposes preempted candidates without always-on trace allocation.
- `last_preemptions` exposes every recorded preemption for richer debug tooling.
- Multi-transition macrostep tracing is available through `dispatch_with_trace`; always-on result tracing measured too expensive.
- `write_scxml` exports compiled state structure, transitions, final states, and history to a compact SCXML subset.
- Typed region ids are still not implemented; named regions currently use strings.

Entering an `And` state enters the initial state of each region it owns.

The runtime active configuration becomes a set of active leaves:

```odin
active_leaves: []State_Index
```

Example active configuration:

```text
Operational
  Flight.Mission
  Radio.Connected
  Navigation.GPSLocked
  Battery.Low
  Payload.Recording
```

Events can trigger transitions in multiple orthogonal regions during one macrostep.

Recommendation:

- Implement SCXML-like deterministic selection rules where possible.
- Keep rejecting ambiguous cross-region conflicts at dispatch until richer conflict reporting is available.
- Add tests for every conflict rule.

## Phase 4: History States

History is useful when leaving and later re-entering a superstate.

Real-world examples:

- A media player resumes the exact previous `Playing` submode.
- A drone mission returns to the previous mission submode after a temporary avoidance maneuver.
- An editor returns to the previous tool mode after a modal operation.

Implemented API:

```odin
History_Kind :: enum {
	Shallow,
	Deep,
}

History_Def :: struct($State: typeid) {
	id: State,
	superstate: State,
	fallback: State,
	kind: History_Kind,
}
```

Current status:

- `History_Def.id` is a transition target token, not an active state.
- History ids must not appear in `State_Def`.
- Shallow history remembers the last direct child exited under `superstate`.
- Deep history remembers one nested leaf under `superstate` for OR hierarchies.
- Deep history under `And` states remembers one leaf per owned region and restores the concurrent configuration.
- Empty history enters `fallback`.
- History storage is a dense `State_Index` table on `Instance`.
- Deep history for `And` states uses `fallback` when no complete remembered regional configuration exists.
- `active_history` and `restore_history` let applications persist remembered history without running actions.

Remaining design questions:

- Should history target ids remain values from the state enum, or should transitions grow a typed target union later?
- Should deep history fallback for `And` states require the fallback to be the superstate itself, or continue accepting any descendant target?

## Phase 5: Run-To-Completion And Event Raising

Full statecharts use macrosteps: one external event may cause a cascade of internal transitions until the chart reaches a stable configuration.

Real-world examples:

- Entering `Faulted` raises `Kill_Motors`.
- Completing boot raises `Diagnostics_Start`.
- Entering `Battery_Critical` raises `Return_Home` and `Stop_Payload`.

Implemented API:

```odin
dispatch_run_to_completion :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

dispatch_run_to_completion_with_trace :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

enter_initial_run_to_completion :: proc(
	instance: ^Instance($State, $Trigger),
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

enter_initial_run_to_completion_with_trace :: proc(
	instance: ^Instance($State, $Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

raise :: proc(ctx: rawptr, event: Event($Trigger)) -> bool
user_context :: proc(ctx: rawptr) -> rawptr
```

Current status:

- The instance owns a preallocated internal event queue.
- `raise` appends to that queue during run-to-completion dispatch.
- Queue overflow returns `Error`; it does not allocate.
- `Init_Options.internal_event_capacity` can reserve extra queue capacity during `init`.
- Normal `dispatch` passes raw user context unchanged.
- `dispatch_run_to_completion` passes a `Runtime_Context`; actions can call `user_context(ctx)` to recover the application context.
- `dispatch_run_to_completion_with_trace` fills a caller-owned transition buffer with every applied microstep.
- `enter_initial_run_to_completion` passes a `Runtime_Context` to startup entry actions, then processes raised events and completion events until stable.
- `Always_Def` transitions are processed after queued internal events drain, and repeat until stable or `max_internal_events` is exceeded.
- Raised internal events broadcast across all active regions and can apply multiple non-conflicting branch transitions in one microstep.
- Focused tests cover raised events and no-allocation run-to-completion dispatch.

## Phase 6: Delayed Events

Timed behavior matters for UI, robotics, networking, and games.

Examples:

- `Booting` times out after 5 seconds.
- `Signal_Lost` waits 2 seconds before return-home.
- `Landing` times out if ground contact is not detected.

Implemented API:

```odin
After_Def :: struct($State, $Trigger: typeid) {
	state: State,
	delay_ms: u64,
	trigger: Trigger,
}

enter_initial_at :: proc(..., now_ms: u64, ...)
dispatch_at :: proc(..., now_ms: u64, ...)
dispatch_run_to_completion_at :: proc(..., now_ms: u64, ...)
dispatch_due_events :: proc(..., now_ms: u64, ...)
next_due_event_ms :: proc(...) -> (u64, bool)
```

Current status:

- The application owns the clock and passes `now_ms`.
- Entering a state arms matching `After_Def` timers.
- Exiting a state cancels matching active timers.
- Due timers are processed through the internal event queue and run-to-completion path.
- Due timer cascades can be recorded with caller-owned trace storage.
- `next_due_event_ms` returns the earliest active timer for app-owned schedulers.
- Timer dispatch is allocation-free after `init`.

Design decision:

- After-events are app-clock driven and are processed only when the app calls `dispatch_due_events` or `dispatch_due_events_with_trace`.

## Tests, Examples, And Showcases

The project should use three different kinds of examples:

- **Unit tests**: small, focused charts that prove one semantic rule at a time.
- **Examples**: compact programs that show how to use the API correctly.
- **Showcases**: larger realistic models that demonstrate why statecharts are valuable.

Tests should stay narrow. They should not depend on a large drone chart just to prove one rule. For example, child-priority, self-transition, history restoration, or orthogonal conflict behavior should each have small dedicated charts.

Showcases should be allowed to be larger. Their job is to demonstrate how the package fits into real software and how Harel features reduce complexity.

Recommended directory shape:

```text
statecharts/
  statecharts/
    types.odin
    compile.odin
    runtime.odin
    export.odin
    statecharts_test.odin

  examples/
    door/
    media_player/
    editor_modes/

  showcases/
    drone_operations/
    media_player_history/
    editor_workspace/
    network_protocol/
```

Example programs should compile and preferably run as normal Odin programs. Showcase models should be testable too, but their tests should focus on high-value scenarios rather than exhaustive semantics.

## Real-World Showcase Track

Showcases should justify features before implementation. Drone operations is a strong anchor, but it should not be the only model. Different domains expose different statechart strengths.

### Drone Operations

Use hierarchy, orthogonality, guards, broadcast-style event handling, and eventually delayed events:

```text
Operational
  Flight
    Idle
    TakingOff
    Hover
    Mission
    ReturningHome
    Landing

  Radio
    Connected
    Degraded
    Lost

  Navigation
    GPSLocked
    GPSDegraded
    GPSLost

  Battery
    Normal
    Low
    Critical

  Payload
    Inactive
    Recording
    Streaming
```

Feature value:

- Orthogonal regions prevent mode explosion.
- Broadcast events let one event affect flight, payload, telemetry, and battery regions.
- Delayed events model signal-loss grace periods and timeouts.

### Media Player

Use hierarchy, history, and timed events:

```text
Player
  Stopped
  Playing
    Normal
    Buffering
    Casting
  Paused
```

Feature value:

- Parent-level transitions avoid duplicated `Stop`, `Pause`, and `Error`.
- History resumes the exact previous playing submode.
- Delayed events model buffering timeout and idle shutdown.

### Editor Modes

Use hierarchy, orthogonality, and history:

```text
Editor
  Tool
    Select
    Draw
    Text
    Erase

  Document
    Clean
    Dirty
    Saving

  Modal
    None
    CommandPalette
    ColorPicker
```

Feature value:

- Tool, document, and modal state evolve independently.
- History restores previous tool after temporary modal operations.

### Network Protocol Session

Use hierarchy, guards, retry counters, and delayed events:

```text
Session
  Disconnected
  Connecting
    Resolving
    OpeningSocket
    Handshaking
  Connected
    Idle
    Sending
    WaitingForAck
  BackingOff
  Failed
```

Feature value:

- Parent-level transitions handle `Disconnect`, `Timeout`, and `FatalError`.
- Delayed events model retries and exponential backoff.
- Guards decide whether retry budget remains.

### Game Character Controller

Use hierarchy and orthogonal regions:

```text
Character
  Locomotion
    Grounded
      Idle
      Run
      JumpStart
    Airborne
      Rising
      Falling

  Combat
    Unarmed
    Attacking
    Blocking

  Status
    Normal
    Stunned
    Invulnerable
```

Feature value:

- Movement, combat, and status evolve independently.
- Orthogonal regions avoid a combinatorial list of `RunningAndBlockingAndStunned` states.
- Timed events model attack recovery, stun duration, and invulnerability windows.

### Checkout Or Workflow Engine

Use hierarchy, guards, and history:

```text
Checkout
  Cart
  CustomerInfo
  Payment
    EnteringPayment
    Authorizing
    Failed
  Review
  Complete
  Cancelled
```

Feature value:

- Guards enforce domain requirements before advancing.
- History can return a user to the previous payment substep after fixing an error.
- Parent-level transitions handle cancellation and session expiry.

## Near-Term Implementation Order

1. Add `Compile_Options`.
2. Reject ambiguous transitions by default.
3. Move dispatch trace storage onto `Instance`.
4. Compile transition adjacency tables.
5. Make dispatch allocation-free.
6. Replace/evolve `Initial_Def` into `Region_Def`. Done for direct-child regions with optional names.
7. Re-implement current OR semantics on top of regions. Done for current single-region compound states.
8. Add orthogonal `And` states. Done.
9. Add real-world orthogonal showcases. Done.
10. Revisit history states. Done.

## Definition Of Done For Each Feature

Each feature should include:

- Public API docs.
- Validation rules.
- Runtime semantics.
- Tests for happy path.
- Tests for malformed charts.
- Tests for conflict or ambiguity behavior.
- At least one real-world example showing why the feature exists.
- No dispatch-time heap allocation unless explicitly documented.
