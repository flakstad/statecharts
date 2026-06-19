package main

import "core:fmt"

import sc "local:statecharts"

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
  current_fault: Fault_Code,
  motors_enabled: bool,
  mission_loaded: bool,
  commands: [dynamic]Command,
}

Sensor_Snapshot :: struct {
  battery_percent: int,
  gps_locked: bool,
  radio_link_ok: bool,
  altitude_m: f32,
  fault: Fault_Code,
}

Pilot_Input :: struct {
  power_on: bool,
  arm: bool,
  takeoff: bool,
  start_mission: bool,
  land: bool,
  emergency_stop: bool,
}

Drone_App :: struct {
  ctx: Drone_Ctx,
  chart: sc.Chart(Drone_State, Drone_Event),
  machine: sc.Instance(Drone_State, Drone_Event),
  event_queue: [dynamic]sc.Event(Drone_Event),
  trace: [dynamic]sc.Transition_Step(Drone_State),
}

enqueue_command :: proc(ctx: ^Drone_Ctx, kind: Command_Kind) {
  append(&ctx.commands, Command{kind = kind})
}

boot_systems :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Boot_Systems)
}

start_calibration :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Start_Calibration)
}

enable_motors :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  ctx := cast(^Drone_Ctx)ctx_raw
  ctx.motors_enabled = true
  enqueue_command(ctx, .Enable_Motors)
}

disable_motors :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  ctx := cast(^Drone_Ctx)ctx_raw
  ctx.motors_enabled = false
  enqueue_command(ctx, .Disable_Motors)
}

start_takeoff :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Start_Takeoff)
}

hold_position :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Hold_Position)
}

start_mission :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Start_Mission)
}

return_home :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Return_Home)
}

start_landing :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  enqueue_command(cast(^Drone_Ctx)ctx_raw, .Start_Landing)
}

log_fault :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  ctx := cast(^Drone_Ctx)ctx_raw
  append(&ctx.commands, Command{kind = .Log_Fault, fault = ctx.current_fault})
}

kill_motors :: proc(ctx_raw: rawptr, event_raw: rawptr) {
  ctx := cast(^Drone_Ctx)ctx_raw
  ctx.motors_enabled = false
  enqueue_command(ctx, .Kill_Motors)
}

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
  sc.on(Drone_State.Off, Drone_Event.Power_On, Drone_State.Booting),
  sc.on(Drone_State.Booting, Drone_Event.Boot_Complete, Drone_State.Operational),

  sc.on(Drone_State.Operational_Idle, Drone_Event.Calibrate, Drone_State.Operational_Calibrating),
  sc.on(Drone_State.Operational_Calibrating, Drone_Event.Calibration_Done, Drone_State.Operational_Idle),

  sc.on(Drone_State.Operational_Idle, Drone_Event.Arm, Drone_State.Armed, guard = can_arm),
  sc.on(Drone_State.Armed, Drone_Event.Disarm, Drone_State.Operational_Idle),

  sc.on(Drone_State.Armed_Ready, Drone_Event.Takeoff, Drone_State.Armed_Taking_Off, guard = can_takeoff, action = start_takeoff),
  sc.on(Drone_State.Armed_Taking_Off, Drone_Event.Takeoff_Complete, Drone_State.Flying),

  sc.on(Drone_State.Flying_Hover, Drone_Event.Start_Mission, Drone_State.Flying_Mission, guard = can_start_mission, action = start_mission),
  sc.on(Drone_State.Flying_Mission, Drone_Event.Pause_Mission, Drone_State.Flying_Hover),
  sc.on(Drone_State.Flying_Hover, Drone_Event.Resume_Mission, Drone_State.Flying_Mission, guard = can_start_mission, action = start_mission),

  sc.on(Drone_State.Flying, Drone_Event.Return_Home, Drone_State.Flying_Returning_Home, guard = can_return_home),
  sc.on(Drone_State.Flying, Drone_Event.Low_Battery, Drone_State.Flying_Returning_Home, guard = can_return_home),
  sc.on(Drone_State.Flying, Drone_Event.Signal_Lost, Drone_State.Flying_Returning_Home, guard = can_return_home),
  sc.on(Drone_State.Flying, Drone_Event.Land, Drone_State.Flying_Landing, action = start_landing),
  sc.on(Drone_State.Flying_Landing, Drone_Event.Landed, Drone_State.Operational_Idle),

  sc.on(Drone_State.Operational, Drone_Event.Fault_Detected, Drone_State.Faulted),
  sc.on(Drone_State.Faulted, Drone_Event.Reset, Drone_State.Booting),
  sc.on(Drone_State.Operational, Drone_Event.Emergency_Stop, Drone_State.Emergency_Stop),
}

chart_def :: proc() -> sc.Chart_Def(Drone_State, Drone_Event) {
  return sc.define_full(
    Drone_State.Off,
    states[:],
    substates[:],
    regions[:],
    nil,
    nil,
    transitions[:],
    nil,
    nil,
    nil,
  )
}

app_init :: proc(app: ^Drone_App) -> bool {
  compile_result := sc.compile(&app.chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  if !compile_result.ok {
    return false
  }

  if !sc.init(&app.machine, &app.chart) {
    return false
  }

  app.ctx = Drone_Ctx{
    battery_percent = 100,
    gps_locked = false,
    radio_link_ok = false,
    home_position_valid = false,
    current_fault = .None,
    commands = make([dynamic]Command, 0, 8),
  }
  app.event_queue = make([dynamic]sc.Event(Drone_Event), 0, 8)
  app.trace = make([dynamic]sc.Transition_Step(Drone_State), 0, 2)

  result := sc.enter_initial(&app.machine, &app.ctx)
  sc.destroy_dispatch_result(&result)
  return sc.is_active(&app.machine, Drone_State.Off)
}

app_destroy :: proc(app: ^Drone_App) {
  if app.ctx.commands != nil do delete(app.ctx.commands)
  if app.event_queue != nil do delete(app.event_queue)
  if app.trace != nil do delete(app.trace)
  sc.destroy_instance(&app.machine)
  sc.destroy_chart(&app.chart)
}

push_event :: proc(app: ^Drone_App, id: Drone_Event) {
  append(&app.event_queue, sc.event(id))
}

ingest_sensors :: proc(app: ^Drone_App, snap: Sensor_Snapshot) {
  app.ctx.battery_percent = snap.battery_percent
  app.ctx.gps_locked = snap.gps_locked
  app.ctx.radio_link_ok = snap.radio_link_ok

  if snap.gps_locked && snap.radio_link_ok {
    app.ctx.home_position_valid = true
  }

  if snap.fault != .None {
    app.ctx.current_fault = snap.fault
    push_event(app, .Fault_Detected)
  }
  if snap.battery_percent < 20 && sc.is_active(&app.machine, Drone_State.Flying) {
    push_event(app, .Low_Battery)
  }
  if !snap.radio_link_ok && sc.is_active(&app.machine, Drone_State.Flying) {
    push_event(app, .Signal_Lost)
  }
  if sc.is_active(&app.machine, Drone_State.Armed_Taking_Off) && snap.altitude_m > 8 {
    push_event(app, .Takeoff_Complete)
  }
  if sc.is_active(&app.machine, Drone_State.Flying_Landing) && snap.altitude_m < 0.3 {
    push_event(app, .Landed)
  }
}

ingest_pilot_input :: proc(app: ^Drone_App, input: Pilot_Input) {
  if input.emergency_stop do push_event(app, .Emergency_Stop)
  if input.power_on do push_event(app, .Power_On)
  if input.arm do push_event(app, .Arm)
  if input.takeoff do push_event(app, .Takeoff)
  if input.start_mission do push_event(app, .Start_Mission)
  if input.land do push_event(app, .Land)
}

print_commands :: proc(commands: []Command) {
  if len(commands) == 0 {
    fmt.println("  commands: <none>")
    return
  }
  fmt.println("  commands:")
  for command in commands {
    if command.kind == .Log_Fault {
      fmt.printf("    %v %v\n", command.kind, command.fault)
    } else {
      fmt.printf("    %v\n", command.kind)
    }
  }
}

print_active_leaves :: proc(app: ^Drone_App) {
  leaves := make([dynamic]Drone_State, 0, 4)
  defer delete(leaves)
  sc.active_leaves(&app.machine, &leaves)
  fmt.printf("  active leaves: %v\n", leaves[:])
}

drain_events :: proc(app: ^Drone_App, label: string) {
  fmt.println(label)
  clear(&app.ctx.commands)
  if len(app.event_queue) == 0 {
    print_active_leaves(app)
    print_commands(app.ctx.commands[:])
    fmt.println()
    return
  }

  for event in app.event_queue {
    result := sc.dispatch_with_trace(&app.machine, event, &app.trace, &app.ctx)
    fmt.printf("  event: %v status: %v\n", event.id, result.status)
    for step in app.trace {
      fmt.printf("    %v -> %v\n", step.source, step.target)
    }
    sc.destroy_dispatch_result(&result)
  }
  clear(&app.event_queue)

  print_active_leaves(app)
  print_commands(app.ctx.commands[:])
  fmt.println()
}

app_update :: proc(app: ^Drone_App, label: string, snap: Sensor_Snapshot, input: Pilot_Input) {
  ingest_sensors(app, snap)
  ingest_pilot_input(app, input)
  drain_events(app, label)
}

main :: proc() {
  app: Drone_App
  ok := app_init(&app)
  defer app_destroy(&app)
  assert(ok)

  nominal := Sensor_Snapshot{
    battery_percent = 100,
    gps_locked = true,
    radio_link_ok = true,
    altitude_m = 0,
    fault = .None,
  }

  print_active_leaves(&app)
  fmt.println()

  app_update(&app, "power on", nominal, Pilot_Input{power_on = true})
  push_event(&app, .Boot_Complete)
  drain_events(&app, "boot complete")

  not_ready := nominal
  not_ready.gps_locked = false
  app_update(&app, "arm before checks pass", not_ready, Pilot_Input{arm = true})

  app_update(&app, "arm after checks pass", nominal, Pilot_Input{arm = true})

  app_update(&app, "takeoff request", nominal, Pilot_Input{takeoff = true})
  airborne := nominal
  airborne.altitude_m = 12
  app_update(&app, "takeoff sensor completion", airborne, Pilot_Input{})

  app.ctx.mission_loaded = true
  app_update(&app, "start mission", airborne, Pilot_Input{start_mission = true})

  link_lost := airborne
  link_lost.radio_link_ok = false
  app_update(&app, "radio link lost", link_lost, Pilot_Input{})

  app_update(&app, "land request", airborne, Pilot_Input{land = true})
  landed := nominal
  landed.altitude_m = 0
  app_update(&app, "landing sensor completion", landed, Pilot_Input{})
}
