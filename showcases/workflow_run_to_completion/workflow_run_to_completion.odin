package main

import "core:fmt"

import sc "local:statecharts"

Workflow_State :: enum {
  Draft,
  Authorizing,
  Capturing,
  Complete,
  Failed,
}

Workflow_Event :: enum {
  Submit,
  Authorized,
  Captured,
  Declined,
}

Workflow_Ctx :: struct {
  log: [dynamic]string,
}

log :: proc(ctx_raw: rawptr, message: string) {
  ctx := cast(^Workflow_Ctx)sc.user_context(ctx_raw)
  append(&ctx.log, message)
}

authorize :: proc(ctx: rawptr, event: rawptr) {
  log(ctx, "authorized")
  ok := sc.raise(ctx, sc.Event(Workflow_Event){id = .Authorized})
  assert(ok)
}

capture :: proc(ctx: rawptr, event: rawptr) {
  log(ctx, "captured")
}

states := [?]sc.State_Def(Workflow_State){
  {id = .Draft},
  {id = .Authorizing},
  {id = .Capturing},
  {id = .Complete},
  {id = .Failed},
}

transitions := [?]sc.Transition_Def(Workflow_State, Workflow_Event){
  {source = .Draft, target = .Authorizing, trigger = .Submit, action = authorize},
  {source = .Authorizing, target = .Capturing, trigger = .Authorized, action = capture},
  {source = .Authorizing, target = .Failed, trigger = .Declined},
}

always_transitions := [?]sc.Always_Def(Workflow_State){
  {source = .Capturing, target = .Complete},
}

chart_def :: proc() -> sc.Chart_Def(Workflow_State, Workflow_Event) {
  return sc.Chart_Def(Workflow_State, Workflow_Event){
    initial = .Draft,
    states = states[:],
    transitions = transitions[:],
    always_transitions = always_transitions[:],
  }
}

print_configuration :: proc(machine: ^sc.Instance(Workflow_State, Workflow_Event), label: string) {
  states := make([dynamic]Workflow_State)
  defer delete(states)

  sc.configuration(machine, &states)
  fmt.printf("%s:", label)
  for state in states {
    fmt.printf(" %v", state)
  }
  fmt.println()
}

main :: proc() {
  chart: sc.Chart(Workflow_State, Workflow_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  machine: sc.Instance(Workflow_State, Workflow_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  ctx := Workflow_Ctx{log = make([dynamic]string)}
  defer delete(ctx.log)

  result := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&result)
  print_configuration(&machine, "initial")

  trace := make([dynamic]sc.Transition_Step(Workflow_State), 0, 3)
  defer delete(trace)
  result = sc.dispatch_run_to_completion_with_trace(&machine, sc.Event(Workflow_Event){id = .Submit}, &trace, &ctx)
  defer sc.destroy_dispatch_result(&result)

  fmt.printf("submit status: %v\n", result.status)
  for step in trace {
    fmt.printf("  %v -> %v\n", step.source, step.target)
  }
  print_configuration(&machine, "after submit")
  fmt.print("log:")
  for entry in ctx.log {
    fmt.printf(" %s", entry)
  }
  fmt.println()
}
