package main

import "core:fmt"

import sc "local:statecharts"

Checkout_State :: enum {
  Checkout,
  EnteringPayment,
  PaymentCaptured,
  OrderClosed,
}

Checkout_Event :: enum {
  SubmitPayment,
  CheckoutDone,
}

states := [?]sc.State_Def(Checkout_State){
  {id = .Checkout, kind = .Or},
  {id = .EnteringPayment},
  {id = .PaymentCaptured, kind = .Final},
  {id = .OrderClosed},
}

substates := [?]sc.Substate_Def(Checkout_State){
  {substate = .EnteringPayment, superstate = .Checkout},
  {substate = .PaymentCaptured, superstate = .Checkout},
}

regions := [?]sc.Region_Def(Checkout_State){
  {superstate = .Checkout, initial = .EnteringPayment},
}

transitions := [?]sc.Transition_Def(Checkout_State, Checkout_Event){
  sc.on(Checkout_State.EnteringPayment, Checkout_Event.SubmitPayment, Checkout_State.PaymentCaptured),
  sc.on(Checkout_State.Checkout, Checkout_Event.CheckoutDone, Checkout_State.OrderClosed),
}

done_events := [?]sc.Done_Def(Checkout_State, Checkout_Event){
  sc.done(Checkout_State.Checkout, Checkout_Event.CheckoutDone),
}

chart_def :: proc() -> sc.Chart_Def(Checkout_State, Checkout_Event) {
  return sc.define_full(
    Checkout_State.Checkout,
    states[:],
    substates[:],
    regions[:],
    nil,
    nil,
    transitions[:],
    nil,
    done_events[:],
    nil,
  )
}

print_configuration :: proc(machine: ^sc.Instance(Checkout_State, Checkout_Event), label: string) {
  states := make([dynamic]Checkout_State)
  defer delete(states)

  sc.configuration(machine, &states)
  fmt.printf("%s:", label)
  for state in states {
    fmt.printf(" %v", state)
  }
  fmt.println()
}

main :: proc() {
  chart: sc.Chart(Checkout_State, Checkout_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  machine: sc.Instance(Checkout_State, Checkout_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  result := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&result)
  print_configuration(&machine, "initial")

  result = sc.dispatch_run_to_completion(&machine, sc.event(Checkout_Event.SubmitPayment))
  defer sc.destroy_dispatch_result(&result)

  fmt.printf("submit status: %v\n", result.status)
  print_configuration(&machine, "after submit")
}
