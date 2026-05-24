# Drone Example

This example shows how the statechart fits into a larger program. The statechart is the operations brain: it decides which mode the drone is in, which transitions are legal, and which commands should be issued when transitions happen.

The surrounding program still owns:

- Sensor polling.
- Radio/control input.
- Navigation and control loops.
- Hardware drivers.
- Logging and telemetry.
- Command execution.

The statechart should not directly read hardware or block on I/O. It should receive events and enqueue commands.

## States and Events

```odin
package drone

import sc "statecharts"

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

## Context and Commands

The context is application-owned. Guards inspect it. Actions update it and enqueue commands.

```odin
Position :: struct {
	lat: f64,
	lon: f64,
	alt: f32,
}

Fault_Code :: enum {
	None,
	IMU,
	GPS,
	Motor,
	Battery,
	Radio,
}

Command_Kind :: enum {
	Boot_Systems,
	Start_Calibration,
	Enable_Motors,
	Disable_Motors,
	Start_Takeoff,
	Hold_Position,
	Start_Mission,
	Pause_Mission,
	Return_Home,
	Start_Landing,
	Kill_Motors,
	Publish_Telemetry,
	Log_Fault,
}

Command :: struct {
	kind: Command_Kind,
	fault: Fault_Code,
}

Drone_Ctx :: struct {
	battery_percent: int,
	gps_locked: bool,
	radio_link_ok: bool,
	home_position_valid: bool,
	home: Position,
	current_fault: Fault_Code,

	motors_enabled: bool,
	mission_loaded: bool,

	commands: [dynamic]Command,
}

enqueue :: proc(ctx: ^Drone_Ctx, kind: Command_Kind) {
	append(&ctx.commands, Command{kind = kind})
}
```

## Guards

Guards are pure decision functions. They should not issue commands.

```odin
can_arm :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := cast(^Drone_Ctx)ctx_raw
	return ctx.gps_locked &&
	       ctx.radio_link_ok &&
	       ctx.home_position_valid &&
	       ctx.battery_percent > 30
}

can_takeoff :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := cast(^Drone_Ctx)ctx_raw
	return ctx.motors_enabled && ctx.battery_percent > 25
}

can_start_mission :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := cast(^Drone_Ctx)ctx_raw
	return ctx.mission_loaded && ctx.gps_locked
}

can_return_home :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := cast(^Drone_Ctx)ctx_raw
	return ctx.home_position_valid && ctx.battery_percent > 8
}
```

## Actions

Actions enqueue commands for the rest of the application to execute.

```odin
boot_systems :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Boot_Systems)
}

start_calibration :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Start_Calibration)
}

enable_motors :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	ctx.motors_enabled = true
	enqueue(ctx, .Enable_Motors)
}

disable_motors :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	ctx.motors_enabled = false
	enqueue(ctx, .Disable_Motors)
}

start_takeoff :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Start_Takeoff)
}

hold_position :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Hold_Position)
}

start_mission :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Start_Mission)
}

pause_mission :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Pause_Mission)
}

return_home :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Return_Home)
}

start_landing :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	enqueue(ctx, .Start_Landing)
}

log_fault :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	append(&ctx.commands, Command{kind = .Log_Fault, fault = ctx.current_fault})
}

kill_motors :: proc(ctx_raw: rawptr, event_raw: rawptr) {
	ctx := cast(^Drone_Ctx)ctx_raw
	ctx.motors_enabled = false
	enqueue(ctx, .Kill_Motors)
}
```

## Chart Definition

The chart has no fake root state. `initial = .Off` picks the initial top-level state.

```odin
states := [?]sc.State_Def(Drone_State){
	{id = .Off},
	{id = .Booting, entry = boot_systems},

	{id = .Operational},
	{id = .Operational_Idle},
	{id = .Operational_Calibrating, entry = start_calibration},

	{id = .Armed, entry = enable_motors, exit = disable_motors},
	{id = .Armed_Ready},
	{id = .Armed_Taking_Off},

	{id = .Flying},
	{id = .Flying_Hover, entry = hold_position},
	{id = .Flying_Mission},
	{id = .Flying_Returning_Home, entry = return_home},
	{id = .Flying_Landing},

	{id = .Faulted, entry = log_fault},
	{id = .Emergency_Stop, entry = kill_motors},
}

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

regions := [?]sc.Region_Def(Drone_State){
	{superstate = .Operational, initial = .Operational_Idle},
	{superstate = .Armed, initial = .Armed_Ready},
	{superstate = .Flying, initial = .Flying_Hover},
}

transitions := [?]sc.Transition_Def(Drone_State, Drone_Event){
	{source = .Off, target = .Booting, trigger = .Power_On},
	{source = .Booting, target = .Operational, trigger = .Boot_Complete},

	{source = .Operational_Idle, target = .Operational_Calibrating, trigger = .Calibrate},
	{source = .Operational_Calibrating, target = .Operational_Idle, trigger = .Calibration_Done},

	{source = .Operational_Idle, target = .Armed, trigger = .Arm, guard = can_arm},
	{source = .Armed, target = .Operational_Idle, trigger = .Disarm},

	{source = .Armed_Ready, target = .Armed_Taking_Off, trigger = .Takeoff, guard = can_takeoff, action = start_takeoff},
	{source = .Armed_Taking_Off, target = .Flying, trigger = .Takeoff_Complete},

	{source = .Flying_Hover, target = .Flying_Mission, trigger = .Start_Mission, guard = can_start_mission, action = start_mission},
	{source = .Flying_Mission, target = .Flying_Hover, trigger = .Pause_Mission, action = pause_mission},
	{source = .Flying_Hover, target = .Flying_Mission, trigger = .Resume_Mission, guard = can_start_mission, action = start_mission},

	{source = .Flying, target = .Flying_Returning_Home, trigger = .Return_Home, guard = can_return_home},
	{source = .Flying, target = .Flying_Returning_Home, trigger = .Low_Battery, guard = can_return_home},
	{source = .Flying, target = .Flying_Landing, trigger = .Land, action = start_landing},
	{source = .Flying_Landing, target = .Operational_Idle, trigger = .Landed},

	{source = .Operational, target = .Faulted, trigger = .Fault_Detected},
	{source = .Flying, target = .Flying_Returning_Home, trigger = .Signal_Lost, guard = can_return_home},
	{source = .Faulted, target = .Booting, trigger = .Reset},

	{source = .Operational, target = .Emergency_Stop, trigger = .Emergency_Stop},
}

chart_def := sc.Chart_Def(Drone_State, Drone_Event){
	initial = .Off,
	states = states[:],
	substates = substates[:],
	regions = regions[:],
	transitions = transitions[:],
}
```

## Application Shell

The larger program owns an application object. The statechart is one field in it.

```odin
Sensor_Snapshot :: struct {
	battery_percent: int,
	gps_locked: bool,
	radio_link_ok: bool,
	altitude_m: f32,
	fault: Fault_Code,
}

Pilot_Input :: struct {
	power_on: bool,
	calibrate: bool,
	arm: bool,
	disarm: bool,
	takeoff: bool,
	start_mission: bool,
	pause_mission: bool,
	return_home: bool,
	land: bool,
	reset: bool,
	emergency_stop: bool,
}

Drone_App :: struct {
	ctx: Drone_Ctx,
	chart: sc.Chart(Drone_State, Drone_Event),
	machine: sc.Instance(Drone_State, Drone_Event),
	event_queue: [dynamic]sc.Event(Drone_Event),
}
```

Initialization compiles and validates the chart once, then starts one machine instance.

```odin
app_init :: proc(app: ^Drone_App) -> bool {
	compile_result := sc.compile(&app.chart, chart_def)
	if !compile_result.ok {
		// Print compile_result.errors in real code.
		return false
	}

	if !sc.init(&app.machine, &app.chart) {
		return false
	}

	app.ctx = Drone_Ctx{
		battery_percent = 100,
		radio_link_ok = false,
		gps_locked = false,
		home_position_valid = false,
	}

	sc.enter_initial(&app.machine, &app.ctx)
	return sc.is_active(&app.machine, .Off)
}
```

## Translating Inputs Into Events

Sensors and pilot input are translated into statechart events. This boundary is important: the statechart receives discrete facts, not raw polling state.

```odin
push_event :: proc(app: ^Drone_App, id: Drone_Event) {
	append(&app.event_queue, sc.Event(Drone_Event){id = id})
}

ingest_sensors :: proc(app: ^Drone_App, snap: Sensor_Snapshot) {
	app.ctx.battery_percent = snap.battery_percent
	app.ctx.gps_locked = snap.gps_locked
	app.ctx.radio_link_ok = snap.radio_link_ok

	if snap.fault != .None {
		app.ctx.current_fault = snap.fault
		push_event(app, .Fault_Detected)
	}

	if snap.battery_percent < 20 && sc.is_active(&app.machine, .Flying) {
		push_event(app, .Low_Battery)
	}

	if !snap.radio_link_ok && sc.is_active(&app.machine, .Flying) {
		push_event(app, .Signal_Lost)
	}

	if sc.is_active(&app.machine, .Armed_Taking_Off) && snap.altitude_m > 8 {
		push_event(app, .Takeoff_Complete)
	}

	if sc.is_active(&app.machine, .Flying_Landing) && snap.altitude_m < 0.3 {
		push_event(app, .Landed)
	}
}

ingest_pilot_input :: proc(app: ^Drone_App, input: Pilot_Input) {
	if input.emergency_stop { push_event(app, .Emergency_Stop) }
	if input.power_on { push_event(app, .Power_On) }
	if input.calibrate { push_event(app, .Calibrate) }
	if input.arm { push_event(app, .Arm) }
	if input.disarm { push_event(app, .Disarm) }
	if input.takeoff { push_event(app, .Takeoff) }
	if input.start_mission { push_event(app, .Start_Mission) }
	if input.pause_mission { push_event(app, .Pause_Mission) }
	if input.return_home { push_event(app, .Return_Home) }
	if input.land { push_event(app, .Land) }
	if input.reset { push_event(app, .Reset) }
}
```

Some events come from subsystems completing work:

```odin
on_boot_complete :: proc(app: ^Drone_App) {
	push_event(app, .Boot_Complete)
}

on_calibration_done :: proc(app: ^Drone_App) {
	push_event(app, .Calibration_Done)
}
```

## Driving the Machine

The main update loop drains queued events through the statechart. The statechart may enqueue commands as actions run.

```odin
app_update :: proc(app: ^Drone_App, snap: Sensor_Snapshot, input: Pilot_Input) {
	clear(&app.ctx.commands)

	ingest_sensors(app, snap)
	ingest_pilot_input(app, input)

	for event in app.event_queue {
		result := sc.dispatch(&app.machine, event, &app.ctx)
		trace_dispatch(app, event, result)
	}
	clear(&app.event_queue)

	execute_commands(app.ctx.commands[:])
	publish_status(app)
}
```

This makes control flow explicit:

```text
sensors/input/subsystems
        |
        v
    event queue
        |
        v
    statechart
        |
        v
 command queue
        |
        v
 hardware/navigation/logging
```

## Command Execution

Commands are handled outside the statechart.

```odin
execute_commands :: proc(commands: []Command) {
	for command in commands {
		switch command.kind {
		case .Boot_Systems:
			hw_boot_systems()
		case .Start_Calibration:
			nav_start_calibration()
		case .Enable_Motors:
			motors_enable()
		case .Disable_Motors:
			motors_disable()
		case .Start_Takeoff:
			nav_takeoff()
		case .Hold_Position:
			nav_hold_position()
		case .Start_Mission:
			nav_start_mission()
		case .Pause_Mission:
			nav_pause_mission()
		case .Return_Home:
			nav_return_home()
		case .Start_Landing:
			nav_land()
		case .Kill_Motors:
			motors_kill()
		case .Publish_Telemetry:
			telemetry_publish()
		case .Log_Fault:
			log_fault(command.fault)
		}
	}
}
```

## Why This Shape Works

The statechart centralizes the legal operational modes:

- `Arm` is accepted only from `Operational_Idle`.
- `Takeoff` is accepted only from `Armed_Ready` and only when `can_takeoff` passes.
- `Start_Mission` is accepted only while hovering and only when a mission is loaded.
- `Signal_Lost` can be handled once at `Flying` and applies to all flying substates.
- `Fault_Detected` can be handled once at `Operational` and applies to all operational substates.

The surrounding program remains ordinary systems code:

- Poll sensors.
- Convert changes into events.
- Dispatch events.
- Execute commands.
- Publish status.

That separation is the point: the statechart owns mode logic, while the rest of the application owns I/O and continuous control.

## Example Timeline

```odin
push_event(&app, .Power_On)
// Off -> Booting
// action: Boot_Systems

push_event(&app, .Boot_Complete)
// Booting -> Operational -> Operational_Idle

push_event(&app, .Arm)
// Operational_Idle -> Armed -> Armed_Ready
// entry Armed: Enable_Motors

push_event(&app, .Takeoff)
// Armed_Ready -> Armed_Taking_Off
// action: Start_Takeoff

push_event(&app, .Takeoff_Complete)
// Armed_Taking_Off -> Flying -> Flying_Hover
// entry Flying_Hover: Hold_Position

push_event(&app, .Start_Mission)
// Flying_Hover -> Flying_Mission
// action: Start_Mission

push_event(&app, .Signal_Lost)
// Flying_Mission -> Flying_Returning_Home
// entry Flying_Returning_Home: Return_Home

push_event(&app, .Land)
// Flying_Returning_Home -> Flying_Landing
// action: Start_Landing

push_event(&app, .Landed)
// Flying_Landing -> Operational_Idle
// exit Armed: Disable_Motors
```
