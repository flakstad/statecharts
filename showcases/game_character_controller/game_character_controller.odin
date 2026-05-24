package main

import "core:fmt"

import sc "local:statecharts"

Character_State :: enum {
	Character,

	Locomotion,
	Grounded,
	Idle,
	Running,
	Airborne,
	Falling,

	Combat,
	Ready,
	Attacking,
	Recovering,

	Status,
	Normal,
	Stunned,
}

Character_Event :: enum {
	Move,
	Stop,
	Jump,
	Land,
	Attack,
	Hit,
	Recover,
}

states := [?]sc.State_Def(Character_State){
	{id = .Character, kind = .And},

	{id = .Locomotion, kind = .Or},
	{id = .Grounded, kind = .Or},
	{id = .Idle},
	{id = .Running},
	{id = .Airborne, kind = .Or},
	{id = .Falling},

	{id = .Combat, kind = .Or},
	{id = .Ready},
	{id = .Attacking},
	{id = .Recovering},

	{id = .Status, kind = .Or},
	{id = .Normal},
	{id = .Stunned},
}

substates := [?]sc.Substate_Def(Character_State){
	{substate = .Locomotion, superstate = .Character},
	{substate = .Combat, superstate = .Character},
	{substate = .Status, superstate = .Character},

	{substate = .Grounded, superstate = .Locomotion},
	{substate = .Airborne, superstate = .Locomotion},
	{substate = .Idle, superstate = .Grounded},
	{substate = .Running, superstate = .Grounded},
	{substate = .Falling, superstate = .Airborne},

	{substate = .Ready, superstate = .Combat},
	{substate = .Attacking, superstate = .Combat},
	{substate = .Recovering, superstate = .Combat},

	{substate = .Normal, superstate = .Status},
	{substate = .Stunned, superstate = .Status},
}

regions := [?]sc.Region_Def(Character_State){
	{name = "locomotion", superstate = .Character, initial = .Locomotion},
	{name = "combat", superstate = .Character, initial = .Combat},
	{name = "status", superstate = .Character, initial = .Status},

	{superstate = .Locomotion, initial = .Grounded},
	{superstate = .Grounded, initial = .Idle},
	{superstate = .Airborne, initial = .Falling},
	{superstate = .Combat, initial = .Ready},
	{superstate = .Status, initial = .Normal},
}

transitions := [?]sc.Transition_Def(Character_State, Character_Event){
	{source = .Idle, target = .Running, trigger = .Move},
	{source = .Running, target = .Idle, trigger = .Stop},
	{source = .Grounded, target = .Airborne, trigger = .Jump},
	{source = .Airborne, target = .Grounded, trigger = .Land},

	{source = .Ready, target = .Attacking, trigger = .Attack},
	{source = .Attacking, target = .Recovering, trigger = .Hit},
	{source = .Recovering, target = .Ready, trigger = .Recover},

	{source = .Normal, target = .Stunned, trigger = .Hit},
	{source = .Stunned, target = .Normal, trigger = .Recover},
}

chart_def :: proc() -> sc.Chart_Def(Character_State, Character_Event) {
	return sc.Chart_Def(Character_State, Character_Event){
		initial = .Character,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}
}

print_region_leaf :: proc(
	machine: ^sc.Instance(Character_State, Character_Event),
	region_name: string,
) {
	leaf, ok := sc.active_leaf_in_region(machine, Character_State.Character, region_name)
	if ok {
		fmt.printf("%s: %v\n", region_name, leaf)
		return
	}
	fmt.printf("%s: <inactive>\n", region_name)
}

print_configuration :: proc(machine: ^sc.Instance(Character_State, Character_Event), label: string) {
	fmt.println(label)
	print_region_leaf(machine, "locomotion")
	print_region_leaf(machine, "combat")
	print_region_leaf(machine, "status")
	fmt.println()
}

dispatch :: proc(
	machine: ^sc.Instance(Character_State, Character_Event),
	event: Character_Event,
	trace: ^[dynamic]sc.Transition_Step(Character_State),
) {
	result := sc.dispatch_with_trace(machine, sc.Event(Character_Event){id = event}, trace)
	defer sc.destroy_dispatch_result(&result)

	fmt.printf("event: %v status: %v transitions: %d\n", event, result.status, len(trace^))
	for step in trace^ {
		fmt.printf("  %v -> %v\n", step.source, step.target)
	}
	fmt.println()
}

main :: proc() {
	chart: sc.Chart(Character_State, Character_Event)
	compile_result := sc.compile(&chart, chart_def())
	defer sc.destroy_compile_result(&compile_result)
	defer sc.destroy_chart(&chart)
	assert(compile_result.ok)

	machine: sc.Instance(Character_State, Character_Event)
	ok := sc.init(&machine, &chart)
	defer sc.destroy_instance(&machine)
	assert(ok)

	result := sc.enter_initial(&machine)
	sc.destroy_dispatch_result(&result)
	print_configuration(&machine, "initial")

	trace := make([dynamic]sc.Transition_Step(Character_State), 0, 2)
	defer delete(trace)

	dispatch(&machine, .Move, &trace)
	print_configuration(&machine, "after move")

	dispatch(&machine, .Attack, &trace)
	print_configuration(&machine, "after attack")

	dispatch(&machine, .Hit, &trace)
	print_configuration(&machine, "after hit")

	dispatch(&machine, .Recover, &trace)
	print_configuration(&machine, "after recover")
}
