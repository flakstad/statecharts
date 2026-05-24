# Odin Statecharts API Spec

Draft status: exploratory API design.

This package implements a deterministic statechart runtime for Odin, inspired by Harel statecharts. The first version should focus on hierarchical statecharts with clear semantics, validation, and traceable execution. Orthogonal states, history, and delayed events should be designed for, but do not need to be present in the first implementation.

## Design Goals

- Use application-defined enum types for states and events.
- Avoid wrapper casts like `sid(.Off)` and `eid(.Power_On)` in normal chart definitions.
- Use statechart terminology where it helps the model: `superstate`, `substate`, `configuration`, `source`, `target`, `trigger`.
- Avoid forcing users to define a fake `Root` or `Top` enum value.
- Keep the runtime representation compact and deterministic.
- Make invalid charts fail during validation, not during dispatch.
- Support inspection and debugging of each transition step.

## Core Vocabulary

- **State**: A named mode of the system.
- **Atomic state**: A state with no substates.
- **Superstate**: A state that encapsulates substates.
- **Substate**: A state encapsulated by a superstate.
- **Initial substate**: The default substate entered when a superstate is entered directly.
- **Transition**: A directed relation from a source state to a target state.
- **Trigger**: The event that enables a transition.
- **Guard**: A condition that must be true for a transition to fire.
- **Action**: Code executed as part of a transition, entry, or exit.
- **Configuration**: The current active state set. In the MVP, this is one active leaf plus its active superstates. With orthogonal states, this becomes multiple active leaves plus their superstates.

## User-Facing Shape

The user defines domain enums:

```odin
Drone_State :: enum {
	Off,
	Booting,
	Operational,
	Operational_Idle,
	Operational_Calibrating,
	Armed,
	Armed_Ready,
	Armed_Taking_Off,
	Flying,
	Flying_Hover,
	Flying_Mission,
	Flying_Returning_Home,
	Flying_Landing,
	Faulted,
	Emergency_Stop,
}

Drone_Event :: enum {
	Power_On,
	Boot_Complete,
	Calibrate,
	Calibration_Done,
	Arm,
	Disarm,
	Takeoff,
	Takeoff_Complete,
	Start_Mission,
	Pause_Mission,
	Resume_Mission,
	Return_Home,
	Land,
	Landed,
	Low_Battery,
	Signal_Lost,
	Fault_Detected,
	Reset,
	Emergency_Stop,
}
```

Transitions should be plain typed literals:

```odin
transitions := [?]sc.Transition_Def(Drone_State, Drone_Event){
	{source = .Off, target = .Booting, trigger = .Power_On},
	{source = .Booting, target = .Operational, trigger = .Boot_Complete},

	{
		source = .Operational_Idle,
		target = .Armed,
		trigger = .Arm,
		guard = can_arm,
	},

	{source = .Armed, target = .Operational_Idle, trigger = .Disarm},
	{source = .Armed_Ready, target = .Armed_Taking_Off, trigger = .Takeoff},
	{source = .Armed_Taking_Off, target = .Flying, trigger = .Takeoff_Complete},

	{source = .Flying_Hover, target = .Flying_Mission, trigger = .Start_Mission},
	{source = .Flying_Mission, target = .Flying_Hover, trigger = .Pause_Mission},
	{source = .Flying_Hover, target = .Flying_Mission, trigger = .Resume_Mission},

	{source = .Flying, target = .Flying_Returning_Home, trigger = .Return_Home, guard = can_return_home},
	{source = .Flying, target = .Flying_Landing, trigger = .Land},
	{source = .Flying_Landing, target = .Operational_Idle, trigger = .Landed},

	{source = .Operational, target = .Faulted, trigger = .Fault_Detected},
	{source = .Flying, target = .Flying_Returning_Home, trigger = .Signal_Lost, guard = can_return_home},
	{source = .Faulted, target = .Booting, trigger = .Reset},
}
```

## State Relationship Problem

The chart model needs optional relationships:

- A top-level state has no superstate.
- An atomic state has no initial substate.

Putting those relationships directly on `State_Def` is risky because Odin enum fields have zero values. If `.Off` is enum value zero, then this:

```odin
{id = .Booting}
```

would silently mean `superstate = .Off` if `superstate` were just a plain enum field.

Therefore the public API should not rely on omitted enum fields for optional state relationships. Instead, states, containment, and initial substates should be separate tables.

## Recommended State Authoring API

Use ordinary struct literals for state definitions:

```odin
states := [?]sc.State_Def(Drone_State){
	{id = .Off},
	{id = .Booting, entry = boot_systems},

	{id = .Operational},
	{id = .Operational_Idle},
	{id = .Operational_Calibrating},

	{id = .Armed, entry = enable_motors, exit = disable_motors},
	{id = .Armed_Ready},
	{id = .Armed_Taking_Off},

	{id = .Flying},
	{id = .Flying_Hover},
	{id = .Flying_Mission},
	{id = .Flying_Returning_Home},
	{id = .Flying_Landing},

	{id = .Faulted, entry = log_fault},
	{id = .Emergency_Stop, entry = kill_motors},
}
```

Containment is a separate table:

```odin
substates := [?]sc.Substate_Def(Drone_State){
	{substate = .Operational_Idle, superstate = .Operational},
	{substate = .Operational_Calibrating, superstate = .Operational},

	{substate = .Armed, superstate = .Operational},
	{substate = .Armed_Ready, superstate = .Armed},
	{substate = .Armed_Taking_Off, superstate = .Armed},

	{substate = .Flying, superstate = .Armed},
	{substate = .Flying_Hover, superstate = .Flying},
	{substate = .Flying_Mission, superstate = .Flying},
	{substate = .Flying_Returning_Home, superstate = .Flying},
	{substate = .Flying_Landing, superstate = .Flying},
}
```

Regions are also a separate table. In the current OR-state model, each region has one containing superstate and one initial substate:

```odin
regions := [?]sc.Region_Def(Drone_State){
	{superstate = .Operational, initial = .Operational_Idle},
	{superstate = .Armed, initial = .Armed_Ready},
	{superstate = .Flying, initial = .Flying_Hover},
}
```

The records stay simple and inspectable:

```odin
State_Kind :: enum {
	Inferred,
	Atomic,
	Or,
	And,
	Final,
}

State_Def :: struct($State: typeid) {
	id: State,
	kind: State_Kind,
	entry: Action,
	exit: Action,
}

Substate_Def :: struct($State: typeid) {
	substate: State,
	superstate: State,
	region: string,
}

Region_Def :: struct($State: typeid) {
	name: string,
	superstate: State,
	initial: State,
}

Region_Handle :: distinct int

Initial_Def :: struct($State: typeid) {
	superstate: State,
	initial: State,
}

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

Done_Def :: struct($State, $Trigger: typeid) {
	state: State,
	trigger: Trigger,
}

After_Def :: struct($State, $Trigger: typeid) {
	state: State,
	delay_ms: u64,
	trigger: Trigger,
}

Timer_Snapshot :: struct($State, $Trigger: typeid) {
	after_index: int,
	state: State,
	due_ms: u64,
	trigger: Trigger,
}

History_Snapshot :: struct($State: typeid) {
	history_index: int,
	superstate: State,
	kind: History_Kind,
	region_index: int,
	region_name: string,
	target: State,
}
```

This avoids fake top states, sentinel enum values, `has_*` flags in public chart data, and constructor-only state definitions.

`kind` is optional in ordinary Odin struct literals because the zero value is `.Inferred`. Inferred states are treated as `.Atomic` when they have no substates and `.Or` when they do. Explicit `.Atomic` states may not have substates.

Explicit `.And` states enter all `Region_Def` entries owned by that state. A direct child can either use the legacy branch model, where a region starts at its `Region_Def.initial`, or set `Substate_Def.region` to the owning `Region_Def.name` so multiple direct children belong to the same named region. `Substate_Def.region` is valid only for direct children of `.And` states, and the named region must exist under that same superstate. Every direct child of an `.And` state must belong to exactly one region. `Region_Def.name` gives orthogonal regions a stable application-facing label; duplicate non-empty names under the same superstate are rejected.

External transitions compute an exit set from the transition source and target. If an external transition targets a descendant of its source, the source is exited and re-entered. A `Local` transition to a descendant preserves the source compound state and only exits the active child path needed to reach the target. A branch-local transition exits only that branch. A transition that leaves a containing `.And` state exits all active descendant branches before exiting the containing state itself.

When one event enables multiple non-conflicting branch-local transitions in active regions, dispatch applies those transitions in the same macrostep. This applies to external events and to raised internal events processed during run-to-completion dispatch. If enabled transitions have overlapping exit sets, the transition whose source is deeper in the state hierarchy preempts the ancestor-sourced transition. If overlapping transitions are from unrelated or same-depth sources, dispatch reports `Conflict`, records the conflicting transition endpoints on the instance for `last_conflict`, and leaves the active configuration unchanged. This keeps child transition priority consistent across orthogonal regions without silently choosing one same-depth branch by active-leaf order.

History is defined with `History_Def`. Its `id` is a transition target token from the user's state enum, but it is not a real active state and should not appear in `states`. When a transition targets that history id, the runtime enters the remembered configuration for `superstate`, or `fallback` if no history has been recorded.

`Shallow` history remembers the last direct child exited under `superstate`. `Deep` history remembers nested active leaves. For OR states this is one leaf; for `.And` states this is one remembered leaf per owned region. If a deep-history `.And` state has no complete remembered configuration yet, the runtime enters `fallback`; using the `.And` superstate itself as the fallback enters its default regional configuration.

Run-to-completion dispatch is available through `dispatch_run_to_completion`. Transition actions can call `raise(ctx, Event(...))` to append internal events to the instance-owned queue. In this mode callbacks receive a `Runtime_Context`, not the raw user pointer directly; use `user_context(ctx)` to recover application context. The ordinary `dispatch` and `dispatch_with_trace` calls continue to pass the raw user `ctx` unchanged.

Initial entry has both simple and run-to-completion forms. `enter_initial` enters the default configuration and stops. `enter_initial_run_to_completion` enters the default configuration with a `Runtime_Context`, then processes raised entry events and completion events until stable. This lets charts whose initial configuration is already complete advance through `Done_Def` transitions at startup without changing the compatibility behavior of `enter_initial`.

Raised internal events are broadcast through the same active-region selection rules as external events. A raised event can therefore advance multiple orthogonal regions in one RTC microstep when their transitions do not conflict.

Eventless transitions are defined with `Always_Def`. They have source, target, kind, guard, and action fields like ordinary transitions, but no trigger. Run-to-completion APIs process always transitions after the queued raised/done/due events have drained, and repeat until the chart is stable or `max_internal_events` is exceeded. Ordinary `dispatch` does not process always transitions.

`Final` states are atomic completion markers. `is_complete` reports whether a state's active regions have all reached final leaves. `Done_Def` maps a completed state to a typed event; during run-to-completion dispatch, entering a final state can raise that completion event automatically.

Delayed events are defined with `After_Def`. Entering `state` arms the timer at `now_ms + delay_ms`, exiting that state cancels it, and `dispatch_due_events(instance, now_ms, ...)` processes due timers through the same internal event queue used by run-to-completion dispatch. `next_due_event_ms(instance)` returns the earliest active due time for app schedulers. The application owns the clock and supplies `now_ms`; the package does not sleep or read wall-clock time.

## Chart Definition

The chart has an initial top-level state. States with no superstate are top-level states.

```odin
chart_def := sc.Chart_Def(Drone_State, Drone_Event){
	initial = .Off,
	states = states[:],
	substates = substates[:],
	regions = regions[:],
	transitions = transitions[:],
}
```

Proposed type:

```odin
Chart_Def :: struct($State, $Trigger: typeid) {
	initial: State,
	states: []State_Def(State),
	substates: []Substate_Def(State),
	regions: []Region_Def(State),
	initials: []Initial_Def(State),
	histories: []History_Def(State),
	transitions: []Transition_Def(State, Trigger),
	always_transitions: []Always_Def(State),
	done_events: []Done_Def(State, Trigger),
	after_events: []After_Def(State, Trigger),
}
```

The runtime may compile this into a compact internal representation:

```odin
Chart :: struct($State, $Trigger: typeid) {
	def: Chart_Def(State, Trigger),

	// Internal lookup tables, including superstate indexes,
	// initial-substate indexes, source transition adjacency,
	// and source+trigger groups for high fan-out states.
	// Exact fields are implementation details.
}
```

The implementation uses distinct internal index types for readability and to avoid mixing state and transition indices:

```odin
State_Index :: distinct int
Transition_Index :: distinct int
Region_Index :: distinct int
```

Current `Region_Def` entries are compiled into internal regions:

- One implicit top region contains all top-level states and uses `Chart_Def.initial`.
- Each `Region_Def` creates one OR-region containing the direct substates of its superstate.
- Named regions can be queried at runtime by superstate and region name.
- `region_handle` resolves a named region once to a stable compiled handle.
- `active_leaf_in_region_handle` uses a resolved handle and avoids repeated string lookup in hot integration code.
- Current default entry follows the compiled region metadata, not the public definition tables directly.

`Initial_Def` remains as a compatibility type for older code. New code should prefer `Region_Def`.

## Transition Definition

```odin
Transition_Kind :: enum {
	External,
	Internal,
	Local,
}

Transition_Def :: struct($State, $Trigger: typeid) {
	source: State,
	target: State,
	trigger: Trigger,

	kind: Transition_Kind,
	guard: Guard,
	action: Action,
}

Always_Def :: struct($State: typeid) {
	source: State,
	target: State,

	kind: Transition_Kind,
	guard: Guard,
	action: Action,
}
```

For the MVP:

- Default transition kind is `External`.
- `Internal` transitions execute an action without exiting or entering states; because `Transition_Def` has an explicit `target` field, internal transitions must set `target` to the same state as `source`.
- `Local` transitions execute transition actions and change configuration, but when the target is inside the compound source state they do not exit and re-enter that source state. If a local transition targets outside its source, it behaves like an external transition.

Global transitions are intentionally not part of the first API. Prefer a high-level superstate transition when possible. If truly global transitions are needed later, add an explicit concept instead of overloading missing `source`.

## Events and Callbacks

Events are typed by the user's event enum and can carry arbitrary payload data:

```odin
Event :: struct($Trigger: typeid) {
	id: Trigger,
	data: rawptr,
}
```

Callback types:

```odin
Action :: proc(ctx: rawptr, event: rawptr)
Guard :: proc(ctx: rawptr, event: rawptr) -> bool
```

Callbacks stay type-erased so chart definitions can keep simple procedure fields. Use `context_as` for ordinary dispatch context, `user_context_as` for run-to-completion callbacks that receive a `Runtime_Context`, and `event_as`/`event_data_as` when a callback wants a typed event or typed payload. The event pointer passed to callbacks points to the full `Event(Event_Enum)` value, not only to the payload:

```odin
can_arm :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := sc.context_as(ctx_raw, Drone_Ctx)
	event := sc.event_as(event_raw, Drone_Event)
	return ctx.gps_locked && ctx.battery_percent > 25
}
```

## Instance and Runtime API

```odin
Instance :: struct($State, $Trigger: typeid) {
	chart: ^Chart(State, Trigger),

	// Current active leaf state indices.
	// OR-only charts produce length 1 after startup.
	// AND states can produce length > 1.
	active_leaf_indices: [dynamic]State_Index,
}
```

Proposed operations:

```odin
Compile_Options :: struct {
	allow_ambiguous_transitions: bool,
}

Init_Options :: struct {
	internal_event_capacity: int,
	active_leaf_capacity: int,
	trace_capacity: int,
	configuration_capacity: int,
	path_capacity: int,
	transition_scratch_capacity: int,
}

compile :: proc(
	out: ^Chart($State, $Trigger),
	def: Chart_Def(State, Trigger),
	options := Compile_Options{},
) -> Compile_Result

init :: proc(
	instance: ^Instance($State, $Trigger),
	chart: ^Chart(State, Trigger),
	options := Init_Options{},
) -> bool

enter_initial :: proc(
	instance: ^Instance($State, $Trigger),
	ctx: rawptr = nil,
) -> Dispatch_Result(State)

enter_initial_at :: proc(
	instance: ^Instance($State, $Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
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

enter_initial_run_to_completion_at :: proc(
	instance: ^Instance($State, $Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

enter_initial_run_to_completion_with_trace_at :: proc(
	instance: ^Instance($State, $Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

dispatch :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	ctx: rawptr = nil,
) -> Dispatch_Result(State)

dispatch_at :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
) -> Dispatch_Result(State)

dispatch_with_trace :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	ctx: rawptr = nil,
) -> Dispatch_Result(State)

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

dispatch_run_to_completion_at :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

dispatch_run_to_completion_with_trace_at :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

dispatch_due_events :: proc(
	instance: ^Instance($State, $Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

dispatch_due_events_with_trace :: proc(
	instance: ^Instance($State, $Trigger),
	now_ms: u64,
	transitions: ^[dynamic]Transition_Step(State),
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State)

last_conflict :: proc(
	instance: ^Instance($State, $Trigger),
) -> (Transition_Step(State), Transition_Step(State), bool)

last_conflict_indices :: proc(
	instance: ^Instance($State, $Trigger),
) -> (int, int, bool)

last_preemption :: proc(
	instance: ^Instance($State, $Trigger),
) -> (Transition_Step(State), Transition_Step(State), bool)

last_preemption_indices :: proc(
	instance: ^Instance($State, $Trigger),
) -> (int, int, bool)

last_preemptions :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]Transition_Preemption(State),
)

last_preemption_indices_all :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]Transition_Preemption_Index,
)

next_due_event_ms :: proc(
	instance: ^Instance($State, $Trigger),
) -> (u64, bool)

raise :: proc(
	ctx: rawptr,
	event: Event($Trigger),
) -> bool

user_context :: proc(ctx: rawptr) -> rawptr

context_as :: proc(
	ctx: rawptr,
	$Data: typeid,
) -> ^Data

user_context_as :: proc(
	ctx: rawptr,
	$Data: typeid,
) -> ^Data

event_as :: proc(
	event_raw: rawptr,
	$Trigger: typeid,
) -> ^Event(Trigger)

event_data_as :: proc(
	event_raw: rawptr,
	$Trigger: typeid,
	$Data: typeid,
) -> ^Data

is_active :: proc(
	instance: ^Instance($State, $Trigger),
	state: State,
) -> bool

is_complete :: proc(
	instance: ^Instance($State, $Trigger),
	state: State,
) -> bool

configuration :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]State,
)

active_leaves :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]State,
)

restore_active_leaves :: proc(
	instance: ^Instance($State, $Trigger),
	leaves: []State,
) -> bool

active_history :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]History_Snapshot(State),
)

restore_history :: proc(
	instance: ^Instance($State, $Trigger),
	history_snapshots: []History_Snapshot(State),
) -> bool

active_timers :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]Timer_Snapshot(State, Trigger),
)

restore_active_timers :: proc(
	instance: ^Instance($State, $Trigger),
	timers: []Timer_Snapshot(State, Trigger),
) -> bool

region_handle :: proc(
	chart: ^Chart($State, $Trigger),
	superstate: State,
	region_name: string,
) -> (Region_Handle, bool)

active_leaf_in_region :: proc(
	instance: ^Instance($State, $Trigger),
	superstate: State,
	region_name: string,
) -> (State, bool)

active_leaf_in_region_handle :: proc(
	instance: ^Instance($State, $Trigger),
	handle: Region_Handle,
) -> (State, bool)

write_dot :: proc(
	chart: ^Chart($State, $Trigger),
	out: ^strings.Builder,
) -> bool

write_scxml :: proc(
	chart: ^Chart($State, $Trigger),
	out: ^strings.Builder,
	name: string = "statechart",
) -> bool

write_validation_error :: proc(
	def: Chart_Def($State, $Trigger),
	error: Validation_Error,
	out: ^strings.Builder,
)
```

Example usage:

```odin
chart: sc.Chart(Drone_State, Drone_Event)
result := sc.compile(&chart, chart_def)
assert(result.ok)

machine: sc.Instance(Drone_State, Drone_Event)
assert(sc.init(&machine, &chart))

ctx := Drone_Ctx{
	battery_percent = 82,
	gps_locked = true,
	home_position_valid = true,
}

sc.enter_initial(&machine, &ctx)
assert(sc.is_active(&machine, .Off))

sc.dispatch(&machine, sc.Event(Drone_Event){id = .Power_On}, &ctx)
assert(sc.is_active(&machine, .Booting))
```

## Dispatch Result

Dispatch should return enough information to debug and test behavior.

```odin
Dispatch_Status :: enum {
	Ignored,
	Transitioned,
	Blocked_By_Guard,
	Conflict,
	Error,
}

Dispatch_Result :: struct($State: typeid) {
	status: Dispatch_Status,

	source: State,
	target: State,

	exited: []State,
	entered: []State,
	configuration: []State,
}

Transition_Step :: struct($State: typeid) {
	source: State,
	target: State,
}

Transition_Preemption :: struct($State: typeid) {
	preempted: Transition_Step(State),
	preempted_by: Transition_Step(State),
}

Transition_Preemption_Index :: struct {
	preempted: int,
	preempted_by: int,
}
```

The dispatch result slices are views into scratch storage owned by the `Instance`. They are valid until the next call that mutates the same instance, such as `dispatch`, `enter_initial`, or `enter_initial_run_to_completion`.

`source` and `target` report the last applied transition, preserving the single-transition API. For orthogonal macrosteps that may apply more than one transition, call `dispatch_with_trace` with a caller-owned dynamic array. For run-to-completion cascades, call `dispatch_run_to_completion_with_trace` to record every applied transition across the external event and raised internal events, `enter_initial_run_to_completion_with_trace` to record startup cascades after initial entry, or `dispatch_due_events_with_trace` to record due-timer cascades. Initial entry itself is not a transition and is not appended to the trace. These functions clear and fill the caller-owned transition buffer. If transition selection reports `Conflict`, no transitions are applied for the conflicting event, `last_conflict(instance)` returns the two overlapping transition endpoint pairs, and `last_conflict_indices(instance)` returns their declaration indices in `Chart_Def.transitions`. If descendant priority preempts enabled transitions, `last_preemption(instance)` and `last_preemption_indices(instance)` expose the most recent preemption, while `last_preemptions(instance, out)` and `last_preemption_indices_all(instance, out)` write every preemption observed since the current dispatch began into caller-owned buffers. This keeps normal `dispatch` allocation-free, keeps `Dispatch_Result` small, and avoids always-on result growth.

`Init_Options` lets applications reserve instance-owned buffers at initialization. The defaults are compact and sized for ordinary dispatch. For long run-to-completion cascades, unusually wide orthogonal states, or callers that want larger debug traces without dispatch-time allocation, set `trace_capacity`, `configuration_capacity`, `active_leaf_capacity`, `path_capacity`, or `transition_scratch_capacity` explicitly. The runtime uses the larger of the default and requested capacity.

`active_leaves` writes only the active runtime leaf states to a caller-owned buffer. This is the compact shape to persist for database-backed workflows; `configuration` remains the debugging/introspection view that includes active superstates.

`restore_active_leaves` replaces the runtime configuration from a persisted set of active leaf states. It does not run entry or exit actions and does not arm timers. The function validates that every restored state exists, is a runtime leaf, and forms a complete legal configuration, including exactly one active direct child per active region. This is intended for database-backed workflows where the database is the durable source of truth and the chart is the deterministic transition engine.

A typical database-backed command handler loads an aggregate row, calls `restore_active_leaves` with the persisted leaf list, dispatches one event, calls `active_leaves` after a transition, and persists the new leaf list with any domain data and outbox effects in the same transaction.

`active_history` and `restore_history` snapshot and restore remembered shallow/deep history without running actions. A `History_Snapshot` records the `History_Def` declaration index, superstate, history kind, optional compiled region index/name for deep `.And` history, and remembered target state. Restore validates that the declaration still matches and that remembered targets are legal for the history kind. Applications should restore active leaves first, then restore history snapshots, then restore timers if durable timers are also used.

`active_timers` and `restore_active_timers` provide the same snapshot/restore pattern for active delayed events. A `Timer_Snapshot` records the `After_Def` declaration index, active state, due time, and trigger. Restore validates that the declaration still matches and that the timer state is currently active. Applications can persist timer snapshots next to active leaves when delayed events must survive process restarts.

`write_dot` exports a compiled chart to Graphviz DOT using a caller-owned `strings.Builder`. It includes state nodes, containment edges, region initial markers, transition labels, history nodes, and final-state styling. This is an inspection/debugging feature and is not on the dispatch hot path.

`write_scxml` exports a compact SCXML 1.0 subset using a caller-owned `strings.Builder`. It writes atomic states, compound states, parallel states, final states, transitions, and shallow/deep history fallback targets. Runtime callbacks, guards, and action bodies are intentionally not serialized.

`write_validation_error` formats a structured `Validation_Error` into a caller-owned builder. Messages include the error kind plus the relevant state, substate, region/initial/history, or transition table entry when that context is available.

## Execution Semantics

For the MVP, dispatch is deterministic:

1. A dispatch processes one external event.
2. The active leaf state is searched first.
3. If no enabled transition is found, its superstate is searched.
4. The search continues outward until a transition is found or the event is ignored.
5. A transition is enabled when the trigger matches and the guard is nil or returns true.
6. If multiple transitions from the same source match, declaration order wins.
7. External transition exit order is leaf to the computed exit boundary.
8. External transition entry order is exit boundary to target leaf.
9. When a compound state is targeted, its initial substate chain is entered.
10. Entry and exit actions execute in the same order as the state entry/exit sequence.
11. Transition action executes after exits and before entries.

The exact action order should be documented and tested. The recommended order is:

```text
exit actions
transition action
entry actions
```

## Validation

Compilation should validate:

- All state ids are unique.
- The chart initial state exists and has no superstate.
- Every superstate reference exists.
- Every initial substate exists.
- Every initial substate is a direct substate of the state that declares it.
- No superstate cycles exist.
- Every transition source exists.
- Every transition target exists, unless the transition kind explicitly permits no target.
- Every always transition source and target exists.
- Every state that appears as a superstate has exactly one initial substate.
- No state that lacks substates appears in the initial-substate table.
- No state appears as a substate of more than one superstate.
- Final states have no substates and no outgoing transitions.
- Done events target states that can complete: compound states or final states.
- Duplicate done events for the same state/trigger are rejected.
- Duplicate after events for the same state/delay/trigger are rejected.
- Internal transitions target their source state.
- Internal always transitions target their source state.
- Duplicate transitions with the same source and trigger are rejected by default.
- Duplicate always transitions with the same source are rejected by default.

If `Compile_Options.allow_ambiguous_transitions` is true, duplicate source/trigger transitions and duplicate always transitions from the same source are accepted and declaration order is priority order.

## Future Features

Planned but not MVP:

- Typed region ids and typed region-attached substate definitions.
- SCXML import subset.

## Current Recommendation

Use typed chart definitions:

```odin
sc.Transition_Def(Drone_State, Drone_Event)
sc.State_Def(Drone_State)
sc.Substate_Def(Drone_State)
sc.Region_Def(Drone_State)
sc.Chart_Def(Drone_State, Drone_Event)
sc.Instance(Drone_State, Drone_Event)
```

Use plain struct tables for states, containment, and initial substates:

```odin
states := [?]sc.State_Def(Drone_State){
	{id = .Off},
	{id = .Operational},
	{id = .Operational_Idle},
}

substates := [?]sc.Substate_Def(Drone_State){
	{substate = .Operational_Idle, superstate = .Operational},
}

regions := [?]sc.Region_Def(Drone_State){
	{superstate = .Operational, initial = .Operational_Idle},
}
```

Use plain struct literals for transitions:

```odin
{source = .Off, target = .Booting, trigger = .Power_On}
```

Do not require a fake `Root` or `Top` state in the user's enum. The chart's top is implicit, and `chart_def.initial` selects the initial top-level state.
