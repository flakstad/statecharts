package main

import "core:fmt"
import "core:strings"

import sc "local:statecharts"

Flow_State :: enum {
  Draft,
  Reviewing,
  Approved,
  Rejected,
}

Flow_Event :: enum {
  Submit,
  Approve,
  Reject,
  Revise,
}

states := [?]sc.State_Def(Flow_State){
  {id = .Draft},
  {id = .Reviewing},
  {id = .Approved, kind = .Final},
  {id = .Rejected, kind = .Final},
}

transitions := [?]sc.Transition_Def(Flow_State, Flow_Event){
  {source = .Draft, target = .Reviewing, trigger = .Submit},
  {source = .Reviewing, target = .Approved, trigger = .Approve},
  {source = .Reviewing, target = .Rejected, trigger = .Reject},
  {source = .Reviewing, target = .Draft, trigger = .Revise},
}

main :: proc() {
  chart_def := sc.Chart_Def(Flow_State, Flow_Event){
    initial = .Draft,
    states = states[:],
    transitions = transitions[:],
  }

  chart: sc.Chart(Flow_State, Flow_Event)
  compile_result := sc.compile(&chart, chart_def)
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  builder := strings.builder_make()
  defer strings.builder_destroy(&builder)
  ok := sc.write_scxml(&chart, &builder, "review_flow")
  assert(ok)

  fmt.print(strings.to_string(builder))
}
