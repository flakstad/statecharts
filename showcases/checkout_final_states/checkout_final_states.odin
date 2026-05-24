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
	{source = .EnteringPayment, target = .PaymentCaptured, trigger = .SubmitPayment},
	{source = .Checkout, target = .OrderClosed, trigger = .CheckoutDone},
}

done_events := [?]sc.Done_Def(Checkout_State, Checkout_Event){
	{state = .Checkout, trigger = .CheckoutDone},
}

chart_def :: proc() -> sc.Chart_Def(Checkout_State, Checkout_Event) {
	return sc.Chart_Def(Checkout_State, Checkout_Event){
		initial = .Checkout,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
		done_events = done_events[:],
	}
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

	result = sc.dispatch_run_to_completion(&machine, sc.Event(Checkout_Event){id = .SubmitPayment})
	defer sc.destroy_dispatch_result(&result)

	fmt.printf("submit status: %v\n", result.status)
	print_configuration(&machine, "after submit")
}
