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

Initial substates are also a separate table:

```odin
initials := [?]sc.Initial_Def(Drone_State){
	{superstate = .Operational, initial = .Operational_Idle},
	{superstate = .Armed, initial = .Armed_Ready},
	{superstate = .Flying, initial = .Flying_Hover},
}
```

The records stay simple and inspectable:

```odin
State_Def :: struct($State: typeid) {
	id: State,
	entry: Action,
	exit: Action,
}

Substate_Def :: struct($State: typeid) {
	substate: State,
	superstate: State,
}

Initial_Def :: struct($State: typeid) {
	superstate: State,
	initial: State,
}
```

This avoids fake top states, sentinel enum values, `has_*` flags in public chart data, and constructor-only state definitions.

## Chart Definition

The chart has an initial top-level state. States with no superstate are top-level states.

```odin
chart_def := sc.Chart_Def(Drone_State, Drone_Event){
	initial = .Off,
	states = states[:],
	substates = substates[:],
	initials = initials[:],
	transitions = transitions[:],
}
```

Proposed type:

```odin
Chart_Def :: struct($State, $Trigger: typeid) {
	initial: State,
	states: []State_Def(State),
	substates: []Substate_Def(State),
	initials: []Initial_Def(State),
	transitions: []Transition_Def(State, Trigger),
}
```

The runtime may compile this into a compact internal representation:

```odin
Chart :: struct($State, $Trigger: typeid) {
	def: Chart_Def(State, Trigger),

	// Internal lookup tables and normalized integer ids.
	// Exact fields are implementation details.
}
```

## Transition Definition

```odin
Transition_Kind :: enum {
	External,
	Internal,
}

Transition_Def :: struct($State, $Trigger: typeid) {
	source: State,
	target: State,
	trigger: Trigger,

	kind: Transition_Kind,
	guard: Guard,
	action: Action,
}
```

For the MVP:

- Default transition kind is `External`.
- `Internal` transitions execute an action without exiting or entering states.
- `Local` transitions are deferred until the semantics are fully specified.

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

Open question: callbacks may be clearer if the event parameter is `^Event($Trigger)`, but Odin procedure types cannot easily be generic fields without making every callback type parameterized by `$Trigger`. The simple `rawptr` callback keeps the core type-erased. The event pointer passed to callbacks should point to the full `Event(Event_Enum)` value, not only to the payload:

```odin
can_arm :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := cast(^Drone_Ctx)ctx_raw
	event := cast(^sc.Event(Drone_Event))event_raw
	return ctx.gps_locked && ctx.battery_percent > 25
}
```

## Instance and Runtime API

```odin
Instance :: struct($State, $Trigger: typeid) {
	chart: ^Chart(State, Trigger),

	// Current active leaf states.
	// MVP has length 1 after startup.
	// Orthogonal states will allow length > 1.
	active_leaves: [dynamic]State,
}
```

Proposed operations:

```odin
compile :: proc(
	out: ^Chart($State, $Trigger),
	def: Chart_Def(State, Trigger),
) -> Compile_Result

init :: proc(
	instance: ^Instance($State, $Trigger),
	chart: ^Chart(State, Trigger),
) -> bool

enter_initial :: proc(
	instance: ^Instance($State, $Trigger),
	ctx: rawptr = nil,
) -> Dispatch_Result(State)

dispatch :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	ctx: rawptr = nil,
) -> Dispatch_Result(State)

is_active :: proc(
	instance: ^Instance($State, $Trigger),
	state: State,
) -> bool

configuration :: proc(
	instance: ^Instance($State, $Trigger),
	out: ^[dynamic]State,
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
	Error,
}

Dispatch_Result :: struct($State: typeid) {
	status: Dispatch_Status,

	source: State,
	target: State,

	exited: [dynamic]State,
	entered: [dynamic]State,
	configuration: [dynamic]State,
}
```

Open question: returning dynamic arrays in every dispatch may be too allocation-heavy. The implementation can instead store scratch buffers on the instance, accept output buffers from the caller, or provide a lightweight `Dispatch_Result` plus optional tracing hooks.

## Execution Semantics

For the MVP, dispatch is deterministic:

1. A dispatch processes one external event.
2. The active leaf state is searched first.
3. If no enabled transition is found, its superstate is searched.
4. The search continues outward until a transition is found or the event is ignored.
5. A transition is enabled when the trigger matches and the guard is nil or returns true.
6. If multiple transitions from the same source match, declaration order wins.
7. External transition exit order is leaf to least common superstate.
8. External transition entry order is least common superstate to target leaf.
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
- Every state that appears as a superstate has exactly one initial substate.
- No state that lacks substates appears in the initial-substate table.
- No state appears as a substate of more than one superstate.
- Duplicate enabled transitions are either rejected or deterministically ordered.

The first implementation should prefer rejecting ambiguous charts unless declaration-order priority is explicitly documented.

## Future Features

Planned but not MVP:

- Orthogonal states / AND decomposition.
- Shallow history.
- Deep history.
- Internal event queue and run-to-completion macrosteps.
- Delayed or timed events.
- Final states.
- DOT graph export.
- SCXML import/export subset.
- Typed callback helpers for application contexts and events.

## Current Recommendation

Use typed chart definitions:

```odin
sc.Transition_Def(Drone_State, Drone_Event)
sc.State_Def(Drone_State)
sc.Substate_Def(Drone_State)
sc.Initial_Def(Drone_State)
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

initials := [?]sc.Initial_Def(Drone_State){
	{superstate = .Operational, initial = .Operational_Idle},
}
```

Use plain struct literals for transitions:

```odin
{source = .Off, target = .Booting, trigger = .Power_On}
```

Do not require a fake `Root` or `Top` state in the user's enum. The chart's top is implicit, and `chart_def.initial` selects the initial top-level state.
