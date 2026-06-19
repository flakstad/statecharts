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
  sc.on(Flow_State.Draft, Flow_Event.Submit, Flow_State.Reviewing),
  sc.on(Flow_State.Reviewing, Flow_Event.Approve, Flow_State.Approved),
  sc.on(Flow_State.Reviewing, Flow_Event.Reject, Flow_State.Rejected),
  sc.on(Flow_State.Reviewing, Flow_Event.Revise, Flow_State.Draft),
}

main :: proc() {
  chart_def := sc.define(Flow_State.Draft, states[:], transitions[:])

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
