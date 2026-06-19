package main

import "core:fmt"

import sc "local:statecharts"

Player_State :: enum {
  Player,
  Stopped,
  Playing,
  Track,
  Podcast,
  AdBreak,
  Paused,

  Playing_History,
}

Player_Event :: enum {
  Play,
  Next,
  AdStarted,
  AdFinished,
  Pause,
  Resume,
  Stop,
}

states := [?]sc.State_Def(Player_State){
  {id = .Player, kind = .Or},
  {id = .Stopped},
  {id = .Playing, kind = .Or},
  {id = .Track},
  {id = .Podcast},
  {id = .AdBreak},
  {id = .Paused},
}

substates := [?]sc.Substate_Def(Player_State){
  {substate = .Stopped, superstate = .Player},
  {substate = .Playing, superstate = .Player},
  {substate = .Paused, superstate = .Player},
  {substate = .Track, superstate = .Playing},
  {substate = .Podcast, superstate = .Playing},
  {substate = .AdBreak, superstate = .Playing},
}

regions := [?]sc.Region_Def(Player_State){
  {superstate = .Player, initial = .Stopped},
  {superstate = .Playing, initial = .Track},
}

histories := [?]sc.History_Def(Player_State){
  {id = .Playing_History, superstate = .Playing, fallback = .Track},
}

transitions := [?]sc.Transition_Def(Player_State, Player_Event){
  sc.on(Player_State.Stopped, Player_Event.Play, Player_State.Playing),
  sc.on(Player_State.Track, Player_Event.Next, Player_State.Podcast),
  sc.on(Player_State.Podcast, Player_Event.AdStarted, Player_State.AdBreak),
  sc.on(Player_State.AdBreak, Player_Event.AdFinished, Player_State.Podcast),
  sc.on(Player_State.Playing, Player_Event.Pause, Player_State.Paused),
  sc.on(Player_State.Paused, Player_Event.Resume, Player_State.Playing_History),
  sc.on(Player_State.Player, Player_Event.Stop, Player_State.Stopped),
}

chart_def :: proc() -> sc.Chart_Def(Player_State, Player_Event) {
  return sc.define_full(
    Player_State.Player,
    states[:],
    substates[:],
    regions[:],
    nil,
    histories[:],
    transitions[:],
    nil,
    nil,
    nil,
  )
}

print_configuration :: proc(machine: ^sc.Instance(Player_State, Player_Event), label: string) {
  states := make([dynamic]Player_State)
  defer delete(states)

  sc.configuration(machine, &states)
  fmt.printf("%s:", label)
  for state in states {
    fmt.printf(" %v", state)
  }
  fmt.println()
}

dispatch :: proc(machine: ^sc.Instance(Player_State, Player_Event), event: Player_Event) {
  result := sc.dispatch(machine, sc.event(event))
  defer sc.destroy_dispatch_result(&result)
  fmt.printf("event: %v status: %v\n", event, result.status)
}

main :: proc() {
  chart: sc.Chart(Player_State, Player_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  machine: sc.Instance(Player_State, Player_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  result := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&result)
  print_configuration(&machine, "initial")

  dispatch(&machine, .Play)
  print_configuration(&machine, "after play")

  dispatch(&machine, .Next)
  print_configuration(&machine, "after next")

  dispatch(&machine, .Pause)
  print_configuration(&machine, "after pause")

  dispatch(&machine, .Resume)
  print_configuration(&machine, "after resume")

  dispatch(&machine, .AdStarted)
  print_configuration(&machine, "after ad started")

  dispatch(&machine, .Pause)
  print_configuration(&machine, "after pause during ad")

  dispatch(&machine, .Resume)
  print_configuration(&machine, "after resume during ad")
}
