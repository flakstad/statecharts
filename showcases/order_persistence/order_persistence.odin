package main

import "core:fmt"

import sc "local:statecharts"

Order_State :: enum {
  Draft,
  Submitted,
  Paid,
  Fulfilled,
  Cancelled,
}

Order_Event :: enum {
  Submit,
  Payment_Captured,
  Fulfill,
  Cancel,
}

Order_Row :: struct {
  id: int,
  active_leaves: [dynamic]Order_State,
}

states := [?]sc.State_Def(Order_State){
  {id = .Draft},
  {id = .Submitted},
  {id = .Paid},
  {id = .Fulfilled},
  {id = .Cancelled},
}

transitions := [?]sc.Transition_Def(Order_State, Order_Event){
  sc.on(Order_State.Draft, Order_Event.Submit, Order_State.Submitted),
  sc.on(Order_State.Submitted, Order_Event.Payment_Captured, Order_State.Paid),
  sc.on(Order_State.Paid, Order_Event.Fulfill, Order_State.Fulfilled),
  sc.on(Order_State.Draft, Order_Event.Cancel, Order_State.Cancelled),
  sc.on(Order_State.Submitted, Order_Event.Cancel, Order_State.Cancelled),
  sc.on(Order_State.Paid, Order_Event.Cancel, Order_State.Cancelled),
}

chart_def :: proc() -> sc.Chart_Def(Order_State, Order_Event) {
  return sc.define(Order_State.Draft, states[:], transitions[:])
}

persist_leaves :: proc(row: ^Order_Row, machine: ^sc.Instance(Order_State, Order_Event)) {
  sc.active_leaves(machine, &row.active_leaves)
}

handle_command :: proc(
  row: ^Order_Row,
  chart: ^sc.Chart(Order_State, Order_Event),
  event: Order_Event,
) -> sc.Dispatch_Status {
  machine: sc.Instance(Order_State, Order_Event)
  ok := sc.init(&machine, chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  if len(row.active_leaves) == 0 {
    result := sc.enter_initial(&machine)
    sc.destroy_dispatch_result(&result)
    persist_leaves(row, &machine)
  } else {
    ok = sc.restore_active_leaves(&machine, row.active_leaves[:])
    assert(ok)
  }

  result := sc.dispatch(&machine, sc.event(event))
  defer sc.destroy_dispatch_result(&result)
  if result.status == .Transitioned {
    persist_leaves(row, &machine)
  }
  return result.status
}

main :: proc() {
  chart: sc.Chart(Order_State, Order_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  row := Order_Row{
    id = 42,
    active_leaves = make([dynamic]Order_State, 0, 1),
  }
  defer delete(row.active_leaves)

  status := handle_command(&row, &chart, .Submit)
  fmt.printf("submit status: %v stored: %v\n", status, row.active_leaves[:])

  status = handle_command(&row, &chart, .Payment_Captured)
  fmt.printf("payment status: %v stored: %v\n", status, row.active_leaves[:])

  status = handle_command(&row, &chart, .Fulfill)
  fmt.printf("fulfill status: %v stored: %v\n", status, row.active_leaves[:])
}
