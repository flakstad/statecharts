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

- Typed `State_Def`, `Substate_Def`, `Initial_Def`, `Transition_Def`, and `Chart_Def`.
- No fake `Root` or `Top` enum state.
- Hierarchical states using superstate/substate relationships.
- Initial substates for compound states.
- External transitions.
- Internal transitions.
- Entry and exit actions.
- Guards.
- Transition actions.
- Leaf-to-superstate transition search.
- Child transition priority over superstate transition.
- External self-transition exits and re-enters.
- Validation for common malformed charts.
- Dispatch tracing with exited, entered, and configuration state arrays.

Known MVP limitations:

- Dispatch trace arrays allocate per dispatch.
- Only one active leaf is supported.
- Orthogonal regions are not implemented.
- History states are not implemented.
- Run-to-completion macrosteps are not implemented.
- Internal/broadcast event queues are not implemented.
- Timed/delayed events are not implemented.
- Ambiguous duplicate transitions are deterministic by declaration order, but not yet rejected by validation.

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

- Compile transition lookup by `(source, trigger)`.
- Use dense trigger tables when event enums are suitable.
- Provide a compile option to trade memory for faster dispatch.

## Phase 1: Harden The Hierarchical Core

Before adding "true Harel" features, finish the current core.

Tasks:

- Add compile options.
- Reject ambiguous transitions by default.
- Support opt-in declaration-order priority for ambiguous transitions.
- Move dispatch trace buffers onto `Instance`.
- Make dispatch allocation-free after `init`.
- Add `reserve`/capacity planning during instance initialization.
- Ensure repeated `compile`, `init`, and `enter_initial` are leak-free and deterministic.
- Improve validation error messages or formatting helpers.
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

The current `Initial_Def` model is enough for simple OR decomposition. True Harel statecharts need regions so a superstate can contain one or more concurrent regions.

Replace or evolve:

```odin
Initial_Def
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

Open design question:

- Should the top-level chart have an implicit top region?
- Or should top-level states remain states with no region, using `chart.initial` for the first active top-level state?

Recommendation:

- Keep the current no-fake-top public model.
- Internally compile an implicit top region.
- Let region definitions describe regions inside explicit states.

## Phase 3: Orthogonal States

Orthogonality is the key feature that turns the package from a hierarchical state machine into a real Harel-style statechart engine.

Add state kinds:

```odin
State_Kind :: enum {
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

- `Atomic`: no regions.
- `Or`: exactly one active child region path.
- `And`: all child regions are active concurrently.

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

Open semantic questions:

- If an event enables transitions in multiple regions, should all non-conflicting transitions fire in the same step?
- How should conflicts be resolved when a transition exits a superstate that contains other enabled transitions?
- Should declaration order determine conflict priority, or should validation reject ambiguous cross-region conflicts?

Recommendation:

- Implement SCXML-like deterministic selection rules where possible.
- Prefer rejecting ambiguous cross-region conflicts during validation or dispatch until semantics are fully specified.
- Add tests for every conflict rule.

## Phase 4: History States

History is useful when leaving and later re-entering a superstate.

Real-world examples:

- A media player resumes the exact previous `Playing` submode.
- A drone mission returns to the previous mission submode after a temporary avoidance maneuver.
- An editor returns to the previous tool mode after a modal operation.

Potential public API:

```odin
History_Kind :: enum {
	Shallow,
	Deep,
}

History_Def :: struct($State: typeid) {
	state: State,
	kind: History_Kind,
	default: State,
}
```

Open design question:

- Should transitions target history explicitly with a separate target type?
- Or should history be modeled as pseudo-states in the user's state enum?

Recommendation:

- Avoid forcing pseudo-states into the user enum if possible.
- Consider a separate `Transition_Target` representation before implementing history.

## Phase 5: Run-To-Completion And Event Raising

Full statecharts use macrosteps: one external event may cause a cascade of internal transitions until the chart reaches a stable configuration.

Real-world examples:

- Entering `Faulted` raises `Kill_Motors`.
- Completing boot raises `Diagnostics_Start`.
- Entering `Battery_Critical` raises `Return_Home` and `Stop_Payload`.

The challenge is callback shape. Current callbacks are:

```odin
Action :: proc(ctx: rawptr, event: rawptr)
```

Actions cannot directly raise typed internal events without access to a generic runtime object.

Options:

1. Keep event queues application-owned. Actions append to the app's queue through `ctx`.
2. Add a generic runtime/action context.
3. Add a type-erased runtime handle with typed helper procedures.

Recommendation:

- Keep application-owned queues for now.
- Later add an optional statechart-owned internal event queue if the callback API can stay clean and efficient.

## Phase 6: Delayed Events

Timed behavior matters for UI, robotics, networking, and games.

Examples:

- `Booting` times out after 5 seconds.
- `Signal_Lost` waits 2 seconds before return-home.
- `Landing` times out if ground contact is not detected.

Potential API:

```odin
After_Def :: struct($State, $Trigger: typeid) {
	state: State,
	duration_ms: u64,
	trigger: Trigger,
}
```

Recommendation:

- Do not bake in a clock early.
- Let the application provide time and enqueue timer events.
- Add helpers later if the core semantics are stable.

## Real-World Example Track

Examples should justify features before implementation.

### Drone Operations

Use hierarchy, orthogonality, guards, and eventually delayed events:

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

Use hierarchy and history:

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

## Near-Term Implementation Order

1. Add `Compile_Options`.
2. Reject ambiguous transitions by default.
3. Move dispatch trace storage onto `Instance`.
4. Compile transition adjacency tables.
5. Make dispatch allocation-free.
6. Replace/evolve `Initial_Def` into `Region_Def`.
7. Re-implement current OR semantics on top of regions.
8. Add orthogonal `And` states.
9. Add real-world orthogonal drone example.
10. Revisit history states.

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

