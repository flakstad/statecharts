package main

import "core:fmt"
import "core:strings"

import sc "local:statecharts"

Demo_State :: enum {
	Idle,
	Busy,
	Failed,
}

Demo_Event :: enum {
	Start,
}

states := [?]sc.State_Def(Demo_State){
	{id = .Idle},
	{id = .Busy},
	{id = .Failed},
}

transitions := [?]sc.Transition_Def(Demo_State, Demo_Event){
	{source = .Idle, target = .Busy, trigger = .Start},
	{source = .Idle, target = .Failed, trigger = .Start},
}

main :: proc() {
	chart_def := sc.Chart_Def(Demo_State, Demo_Event){
		initial = .Idle,
		states = states[:],
		transitions = transitions[:],
	}

	chart: sc.Chart(Demo_State, Demo_Event)
	result := sc.compile(&chart, chart_def)
	defer sc.destroy_compile_result(&result)
	defer sc.destroy_chart(&chart)

	if result.ok {
		fmt.println("chart compiled")
		return
	}

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	for error in result.errors {
		strings.builder_reset(&builder)
		sc.write_validation_error(chart_def, error, &builder)
		fmt.println(strings.to_string(builder))
	}
}
