package main

import "core:fmt"

import sc "local:statecharts"

Session_State :: enum {
  Disconnected,
  Connecting,
  Connected,
  Failed,
}

Session_Event :: enum {
  Connect,
  Connected,
  Timeout,
  GiveUp,
}

states := [?]sc.State_Def(Session_State){
  {id = .Disconnected},
  {id = .Connecting},
  {id = .Connected},
  {id = .Failed},
}

transitions := [?]sc.Transition_Def(Session_State, Session_Event){
  sc.on(Session_State.Disconnected, Session_Event.Connect, Session_State.Connecting),
  sc.on(Session_State.Connecting, Session_Event.Connected, Session_State.Connected),
  sc.on(Session_State.Connecting, Session_Event.Timeout, Session_State.Failed),
  sc.on(Session_State.Connecting, Session_Event.GiveUp, Session_State.Failed),
}

after_events := [?]sc.After_Def(Session_State, Session_Event){
  sc.after(Session_State.Connecting, 2_000, Session_Event.Timeout),
}

chart_def :: proc() -> sc.Chart_Def(Session_State, Session_Event) {
  return sc.define_full(
    Session_State.Disconnected,
    states[:],
    nil,
    nil,
    nil,
    nil,
    transitions[:],
    nil,
    nil,
    after_events[:],
  )
}

print_configuration :: proc(machine: ^sc.Instance(Session_State, Session_Event), label: string) {
  states := make([dynamic]Session_State)
  defer delete(states)

  sc.configuration(machine, &states)
  fmt.printf("%s:", label)
  for state in states {
    fmt.printf(" %v", state)
  }
  fmt.println()
}

main :: proc() {
  chart: sc.Chart(Session_State, Session_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  machine: sc.Instance(Session_State, Session_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  result := sc.enter_initial_at(&machine, 10_000)
  sc.destroy_dispatch_result(&result)
  print_configuration(&machine, "initial")

  result = sc.dispatch_at(&machine, sc.event(Session_Event.Connect), 10_100)
  sc.destroy_dispatch_result(&result)
  print_configuration(&machine, "after connect")
  if due_ms, ok := sc.next_due_event_ms(&machine); ok {
    fmt.printf("next timer: %d\n", due_ms)
  }

  persisted_leaves := make([dynamic]Session_State, 0, 1)
  defer delete(persisted_leaves)
  persisted_timers := make([dynamic]sc.Timer_Snapshot(Session_State, Session_Event), 0, 1)
  defer delete(persisted_timers)
  sc.active_leaves(&machine, &persisted_leaves)
  sc.active_timers(&machine, &persisted_timers)

  restored: sc.Instance(Session_State, Session_Event)
  ok = sc.init(&restored, &chart)
  defer sc.destroy_instance(&restored)
  assert(ok)
  assert(sc.restore_active_leaves(&restored, persisted_leaves[:]))
  assert(sc.restore_active_timers(&restored, persisted_timers[:]))
  print_configuration(&restored, "after restore")

  result = sc.dispatch_due_events(&restored, 12_099)
  sc.destroy_dispatch_result(&result)
  print_configuration(&restored, "before timeout")

  trace := make([dynamic]sc.Transition_Step(Session_State), 0, 1)
  defer delete(trace)
  result = sc.dispatch_due_events_with_trace(&restored, 12_100, &trace)
  defer sc.destroy_dispatch_result(&result)
  fmt.printf("timer status: %v\n", result.status)
  for step in trace {
    fmt.printf("  %v -> %v\n", step.source, step.target)
  }
  print_configuration(&restored, "after timeout")
}
