package main

import "core:fmt"

import sc "local:statecharts"

Character_State :: enum {
  Character,

  Locomotion,
  Grounded,
  Idle,
  Running,
  Airborne,
  Falling,

  Combat,
  Ready,
  Attacking,
  Recovering,

  Status,
  Normal,
  Stunned,
}

Character_Event :: enum {
  Move,
  Stop,
  Jump,
  Land,
  Attack,
  Hit,
  Recover,
}

Character_Region_Handles :: struct {
  locomotion: sc.Region_Handle,
  combat: sc.Region_Handle,
  status: sc.Region_Handle,
}

states := [?]sc.State_Def(Character_State){
  {id = .Character, kind = .And},

  {id = .Locomotion, kind = .Or},
  {id = .Grounded, kind = .Or},
  {id = .Idle},
  {id = .Running},
  {id = .Airborne, kind = .Or},
  {id = .Falling},

  {id = .Combat, kind = .Or},
  {id = .Ready},
  {id = .Attacking},
  {id = .Recovering},

  {id = .Status, kind = .Or},
  {id = .Normal},
  {id = .Stunned},
}

substates := [?]sc.Substate_Def(Character_State){
  {substate = .Locomotion, superstate = .Character},
  {substate = .Combat, superstate = .Character},
  {substate = .Status, superstate = .Character},

  {substate = .Grounded, superstate = .Locomotion},
  {substate = .Airborne, superstate = .Locomotion},
  {substate = .Idle, superstate = .Grounded},
  {substate = .Running, superstate = .Grounded},
  {substate = .Falling, superstate = .Airborne},

  {substate = .Ready, superstate = .Combat},
  {substate = .Attacking, superstate = .Combat},
  {substate = .Recovering, superstate = .Combat},

  {substate = .Normal, superstate = .Status},
  {substate = .Stunned, superstate = .Status},
}

regions := [?]sc.Region_Def(Character_State){
  {name = "locomotion", superstate = .Character, initial = .Locomotion},
  {name = "combat", superstate = .Character, initial = .Combat},
  {name = "status", superstate = .Character, initial = .Status},

  {superstate = .Locomotion, initial = .Grounded},
  {superstate = .Grounded, initial = .Idle},
  {superstate = .Airborne, initial = .Falling},
  {superstate = .Combat, initial = .Ready},
  {superstate = .Status, initial = .Normal},
}

transitions := [?]sc.Transition_Def(Character_State, Character_Event){
  sc.on(Character_State.Idle, Character_Event.Move, Character_State.Running),
  sc.on(Character_State.Running, Character_Event.Stop, Character_State.Idle),
  sc.on(Character_State.Grounded, Character_Event.Jump, Character_State.Airborne),
  sc.on(Character_State.Airborne, Character_Event.Land, Character_State.Grounded),

  sc.on(Character_State.Ready, Character_Event.Attack, Character_State.Attacking),
  sc.on(Character_State.Attacking, Character_Event.Hit, Character_State.Recovering),
  sc.on(Character_State.Recovering, Character_Event.Recover, Character_State.Ready),

  sc.on(Character_State.Normal, Character_Event.Hit, Character_State.Stunned),
  sc.on(Character_State.Stunned, Character_Event.Recover, Character_State.Normal),
}

chart_def :: proc() -> sc.Chart_Def(Character_State, Character_Event) {
  return sc.define_full(
    Character_State.Character,
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

print_region_leaf :: proc(
  machine: ^sc.Instance(Character_State, Character_Event),
  handle: sc.Region_Handle,
  region_name: string,
) {
  leaf, ok := sc.active_leaf_in_region_handle(machine, handle)
  if ok {
    fmt.printf("%s: %v\n", region_name, leaf)
    return
  }
  fmt.printf("%s: <inactive>\n", region_name)
}

print_configuration :: proc(
  machine: ^sc.Instance(Character_State, Character_Event),
  handles: Character_Region_Handles,
  label: string,
) {
  fmt.println(label)
  print_region_leaf(machine, handles.locomotion, "locomotion")
  print_region_leaf(machine, handles.combat, "combat")
  print_region_leaf(machine, handles.status, "status")
  fmt.println()
}

dispatch :: proc(
  machine: ^sc.Instance(Character_State, Character_Event),
  event: Character_Event,
  trace: ^[dynamic]sc.Transition_Step(Character_State),
) {
  result := sc.dispatch_with_trace(machine, sc.event(event), trace)
  defer sc.destroy_dispatch_result(&result)

  fmt.printf("event: %v status: %v transitions: %d\n", event, result.status, len(trace^))
  for step in trace^ {
    fmt.printf("  %v -> %v\n", step.source, step.target)
  }
  fmt.println()
}

main :: proc() {
  chart: sc.Chart(Character_State, Character_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  handles: Character_Region_Handles
  ok: bool
  handles.locomotion, ok = sc.region_handle(&chart, Character_State.Character, "locomotion")
  assert(ok)
  handles.combat, ok = sc.region_handle(&chart, Character_State.Character, "combat")
  assert(ok)
  handles.status, ok = sc.region_handle(&chart, Character_State.Character, "status")
  assert(ok)

  machine: sc.Instance(Character_State, Character_Event)
  ok = sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  result := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&result)
  print_configuration(&machine, handles, "initial")

  trace := make([dynamic]sc.Transition_Step(Character_State), 0, 2)
  defer delete(trace)

  dispatch(&machine, .Move, &trace)
  print_configuration(&machine, handles, "after move")

  dispatch(&machine, .Attack, &trace)
  print_configuration(&machine, handles, "after attack")

  dispatch(&machine, .Hit, &trace)
  print_configuration(&machine, handles, "after hit")

  dispatch(&machine, .Recover, &trace)
  print_configuration(&machine, handles, "after recover")
}
