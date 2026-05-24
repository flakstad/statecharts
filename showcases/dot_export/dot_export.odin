package main

import "core:fmt"
import "core:strings"

import sc "local:statecharts"

Door_State :: enum {
	Closed,
	Open,
	Locked,
}

Door_Event :: enum {
	Open,
	Close,
	Lock,
	Unlock,
}

states := [?]sc.State_Def(Door_State){
	{id = .Closed},
	{id = .Open},
	{id = .Locked},
}

transitions := [?]sc.Transition_Def(Door_State, Door_Event){
	{source = .Closed, target = .Open, trigger = .Open},
	{source = .Open, target = .Closed, trigger = .Close},
	{source = .Closed, target = .Locked, trigger = .Lock},
	{source = .Locked, target = .Closed, trigger = .Unlock},
}

main :: proc() {
	chart_def := sc.Chart_Def(Door_State, Door_Event){
		initial = .Closed,
		states = states[:],
		transitions = transitions[:],
	}

	chart: sc.Chart(Door_State, Door_Event)
	compile_result := sc.compile(&chart, chart_def)
	defer sc.destroy_compile_result(&compile_result)
	defer sc.destroy_chart(&chart)
	assert(compile_result.ok)

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	ok := sc.write_dot(&chart, &builder)
	assert(ok)

	fmt.print(strings.to_string(builder))
}
