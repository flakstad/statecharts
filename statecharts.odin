package statecharts

Action :: proc(ctx: rawptr, event: rawptr)
Guard :: proc(ctx: rawptr, event: rawptr) -> bool

State_Def :: struct($State: typeid) {
	id: State,
	entry: Action,
	exit: Action,
}

Substate_Def :: struct($State: typeid) {
	substate: State,
	superstate: State,
}

Initial_Def :: struct($State: typeid) {
	superstate: State,
	initial: State,
}

Transition_Kind :: enum {
	External,
	Internal,
}

Transition_Def :: struct($State, $Trigger: typeid) {
	source: State,
	target: State,
	trigger: Trigger,

	kind: Transition_Kind,
	guard: Guard,
	action: Action,
}

Event :: struct($Trigger: typeid) {
	id: Trigger,
	data: rawptr,
}

Chart_Def :: struct($State, $Trigger: typeid) {
	initial: State,
	states: []State_Def(State),
	substates: []Substate_Def(State),
	initials: []Initial_Def(State),
	transitions: []Transition_Def(State, Trigger),
}

Chart :: struct($State, $Trigger: typeid) {
	def: Chart_Def(State, Trigger),
	parent_index: [dynamic]int,
	initial_index: [dynamic]int,
}

Instance :: struct($State, $Trigger: typeid) {
	chart: ^Chart(State, Trigger),
	active_leaves: [dynamic]State,
}

Validation_Error_Kind :: enum {
	Duplicate_State,
	Missing_Initial_State,
	Initial_Not_Top_Level,
	Missing_Substate,
	Missing_Superstate,
	Duplicate_Substate,
	Self_Substate,
	Superstate_Cycle,
	Missing_Initial_Superstate,
	Missing_Initial_Substate,
	Initial_Not_Direct_Substate,
	Duplicate_Initial,
	Superstate_Missing_Initial,
	Leaf_Has_Initial,
	Missing_Transition_Source,
	Missing_Transition_Target,
}

Validation_Error :: struct {
	kind: Validation_Error_Kind,
	state_index: int,
	substate_index: int,
	initial_index: int,
	transition_index: int,
}

Compile_Result :: struct {
	ok: bool,
	errors: [dynamic]Validation_Error,
}

Dispatch_Status :: enum {
	Ignored,
	Transitioned,
	Blocked_By_Guard,
	Error,
}

Dispatch_Result :: struct($State: typeid) {
	status: Dispatch_Status,
	source: State,
	target: State,
	exited: [dynamic]State,
	entered: [dynamic]State,
	configuration: [dynamic]State,
}

destroy_compile_result :: proc(result: ^Compile_Result) {
	if result.errors != nil {
		delete(result.errors)
		result.errors = nil
	}
}

destroy_chart :: proc(chart: ^Chart($State, $Trigger)) {
	if chart.parent_index != nil {
		delete(chart.parent_index)
		chart.parent_index = nil
	}
	if chart.initial_index != nil {
		delete(chart.initial_index)
		chart.initial_index = nil
	}
}

destroy_instance :: proc(instance: ^Instance($State, $Trigger)) {
	if instance.active_leaves != nil {
		delete(instance.active_leaves)
		instance.active_leaves = nil
	}
	instance.chart = nil
}

destroy_dispatch_result :: proc(result: ^Dispatch_Result($State)) {
	if result.exited != nil {
		delete(result.exited)
		result.exited = nil
	}
	if result.entered != nil {
		delete(result.entered)
		result.entered = nil
	}
	if result.configuration != nil {
		delete(result.configuration)
		result.configuration = nil
	}
}

compile :: proc(out: ^Chart($State, $Trigger), def: Chart_Def(State, Trigger)) -> Compile_Result {
	destroy_chart(out)
	out.def = def
	out.parent_index = make([dynamic]int, 0, len(def.states))
	out.initial_index = make([dynamic]int, 0, len(def.states))

	for _ in def.states {
		append(&out.parent_index, -1)
		append(&out.initial_index, -1)
	}

	result := Compile_Result{errors = make([dynamic]Validation_Error)}

	for i in 0 ..< len(def.states) {
		for j in i + 1 ..< len(def.states) {
			if def.states[i].id == def.states[j].id {
				add_error(&result, .Duplicate_State, state_index = j)
			}
		}
	}

	initial_idx := state_index(out, def.initial)
	if initial_idx < 0 {
		add_error(&result, .Missing_Initial_State)
	}

	for substate, i in def.substates {
		sub_idx := state_index(out, substate.substate)
		super_idx := state_index(out, substate.superstate)
		if sub_idx < 0 {
			add_error(&result, .Missing_Substate, substate_index = i)
			continue
		}
		if super_idx < 0 {
			add_error(&result, .Missing_Superstate, substate_index = i)
			continue
		}
		if sub_idx == super_idx {
			add_error(&result, .Self_Substate, substate_index = i)
			continue
		}
		if out.parent_index[sub_idx] != -1 {
			add_error(&result, .Duplicate_Substate, substate_index = i)
			continue
		}
		out.parent_index[sub_idx] = super_idx
	}

	if initial_idx >= 0 && out.parent_index[initial_idx] != -1 {
		add_error(&result, .Initial_Not_Top_Level, state_index = initial_idx)
	}

	for initial, i in def.initials {
		super_idx := state_index(out, initial.superstate)
		init_idx := state_index(out, initial.initial)
		if super_idx < 0 {
			add_error(&result, .Missing_Initial_Superstate, initial_index = i)
			continue
		}
		if init_idx < 0 {
			add_error(&result, .Missing_Initial_Substate, initial_index = i)
			continue
		}
		if out.initial_index[super_idx] != -1 {
			add_error(&result, .Duplicate_Initial, initial_index = i)
			continue
		}
		if out.parent_index[init_idx] != super_idx {
			add_error(&result, .Initial_Not_Direct_Substate, initial_index = i)
			continue
		}
		out.initial_index[super_idx] = init_idx
	}

	for i in 0 ..< len(def.states) {
		if has_superstate_cycle(out, i) {
			add_error(&result, .Superstate_Cycle, state_index = i)
		}

		has_child := false
		for parent in out.parent_index {
			if parent == i {
				has_child = true
				break
			}
		}

		if has_child && out.initial_index[i] == -1 {
			add_error(&result, .Superstate_Missing_Initial, state_index = i)
		}
		if !has_child && out.initial_index[i] != -1 {
			add_error(&result, .Leaf_Has_Initial, state_index = i)
		}
	}

	for transition, i in def.transitions {
		if state_index(out, transition.source) < 0 {
			add_error(&result, .Missing_Transition_Source, transition_index = i)
		}
		if state_index(out, transition.target) < 0 {
			add_error(&result, .Missing_Transition_Target, transition_index = i)
		}
	}

	result.ok = len(result.errors) == 0
	return result
}

init :: proc(instance: ^Instance($State, $Trigger), chart: ^Chart(State, Trigger)) -> bool {
	destroy_instance(instance)
	instance.chart = chart
	instance.active_leaves = make([dynamic]State)
	return chart != nil
}

enter_initial :: proc(instance: ^Instance($State, $Trigger), ctx: rawptr = nil) -> Dispatch_Result(State) {
	result := new_dispatch_result(State)
	if instance.chart == nil {
		result.status = .Error
		return result
	}

	clear(&instance.active_leaves)
	initial_idx := state_index(instance.chart, instance.chart.def.initial)
	if initial_idx < 0 {
		result.status = .Error
		return result
	}

	enter_from_index(instance, initial_idx, ctx, nil, &result)
	result.status = .Transitioned
	write_configuration(instance, &result.configuration)
	return result
}

dispatch :: proc(instance: ^Instance($State, $Trigger), event: Event(Trigger), ctx: rawptr = nil) -> Dispatch_Result(State) {
	result := new_dispatch_result(State)
	if instance.chart == nil || len(instance.active_leaves) == 0 {
		result.status = .Error
		return result
	}

	leaf_idx := state_index(instance.chart, instance.active_leaves[0])
	if leaf_idx < 0 {
		result.status = .Error
		return result
	}

	event_value := event
	blocked_by_guard := false
	cursor := leaf_idx
	for cursor != -1 {
		for transition in instance.chart.def.transitions {
			if transition.source != instance.chart.def.states[cursor].id || transition.trigger != event_value.id {
				continue
			}
			if transition.guard != nil && !transition.guard(ctx, &event_value) {
				blocked_by_guard = true
				continue
			}
			apply_transition(instance, transition, &event_value, ctx, &result)
			return result
		}
		cursor = instance.chart.parent_index[cursor]
	}

	if blocked_by_guard {
		result.status = .Blocked_By_Guard
	} else {
		result.status = .Ignored
	}
	write_configuration(instance, &result.configuration)
	return result
}

is_active :: proc(instance: ^Instance($State, $Trigger), state: State) -> bool {
	if instance.chart == nil do return false
	for leaf in instance.active_leaves {
		cursor := state_index(instance.chart, leaf)
		for cursor != -1 {
			if instance.chart.def.states[cursor].id == state do return true
			cursor = instance.chart.parent_index[cursor]
		}
	}
	return false
}

configuration :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]State) {
	write_configuration(instance, out)
}

add_error :: proc(
	result: ^Compile_Result,
	kind: Validation_Error_Kind,
	state_index := -1,
	substate_index := -1,
	initial_index := -1,
	transition_index := -1,
) {
	append(&result.errors, Validation_Error{
		kind = kind,
		state_index = state_index,
		substate_index = substate_index,
		initial_index = initial_index,
		transition_index = transition_index,
	})
}

new_dispatch_result :: proc($State: typeid) -> Dispatch_Result(State) {
	return Dispatch_Result(State){
		exited = make([dynamic]State),
		entered = make([dynamic]State),
		configuration = make([dynamic]State),
	}
}

state_index :: proc(chart: ^Chart($State, $Trigger), state: State) -> int {
	for state_def, i in chart.def.states {
		if state_def.id == state do return i
	}
	return -1
}

has_superstate_cycle :: proc(chart: ^Chart($State, $Trigger), state_idx: int) -> bool {
	cursor := chart.parent_index[state_idx]
	steps := 0
	for cursor != -1 {
		if cursor == state_idx do return true
		steps += 1
		if steps > len(chart.def.states) do return true
		cursor = chart.parent_index[cursor]
	}
	return false
}

apply_transition :: proc(
	instance: ^Instance($State, $Trigger),
	transition: Transition_Def(State, Trigger),
	event: ^Event(Trigger),
	ctx: rawptr,
	result: ^Dispatch_Result(State),
) {
	result.source = transition.source
	result.target = transition.target

	if transition.kind == .Internal {
		if transition.action != nil {
			transition.action(ctx, event)
		}
		result.status = .Transitioned
		write_configuration(instance, &result.configuration)
		return
	}

	leaf_idx := state_index(instance.chart, instance.active_leaves[0])
	source_idx := state_index(instance.chart, transition.source)
	target_idx := state_index(instance.chart, transition.target)
	if leaf_idx < 0 || source_idx < 0 || target_idx < 0 {
		result.status = .Error
		return
	}

	lca_idx := least_common_superstate(instance.chart, source_idx, target_idx)
	if source_idx == target_idx {
		lca_idx = instance.chart.parent_index[source_idx]
	}

	exit_to_index(instance, leaf_idx, lca_idx, ctx, event, result)
	if transition.action != nil {
		transition.action(ctx, event)
	}
	enter_from_index(instance, target_idx, ctx, event, result, stop_idx = lca_idx)

	result.status = .Transitioned
	write_configuration(instance, &result.configuration)
}

least_common_superstate :: proc(chart: ^Chart($State, $Trigger), a: int, b: int) -> int {
	cursor_a := a
	for cursor_a != -1 {
		cursor_b := b
		for cursor_b != -1 {
			if cursor_a == cursor_b do return cursor_a
			cursor_b = chart.parent_index[cursor_b]
		}
		cursor_a = chart.parent_index[cursor_a]
	}
	return -1
}

exit_to_index :: proc(
	instance: ^Instance($State, $Trigger),
	from_idx: int,
	stop_idx: int,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	cursor := from_idx
	for cursor != -1 && cursor != stop_idx {
		state_def := instance.chart.def.states[cursor]
		if state_def.exit != nil {
			state_def.exit(ctx, event)
		}
		append(&result.exited, state_def.id)
		cursor = instance.chart.parent_index[cursor]
	}
	clear(&instance.active_leaves)
}

enter_from_index :: proc(
	instance: ^Instance($State, $Trigger),
	target_idx: int,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
	stop_idx := -1,
) {
	path := make([dynamic]int)
	defer delete(path)

	cursor := target_idx
	for cursor != -1 && cursor != stop_idx {
		append(&path, cursor)
		cursor = instance.chart.parent_index[cursor]
	}

	for i := len(path) - 1; i >= 0; i -= 1 {
		enter_one_index(instance, path[i], ctx, event, result)
	}

	cursor = target_idx
	for instance.chart.initial_index[cursor] != -1 {
		cursor = instance.chart.initial_index[cursor]
		enter_one_index(instance, cursor, ctx, event, result)
	}

	append(&instance.active_leaves, instance.chart.def.states[cursor].id)
}

enter_one_index :: proc(
	instance: ^Instance($State, $Trigger),
	idx: int,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	state_def := instance.chart.def.states[idx]
	if state_def.entry != nil {
		state_def.entry(ctx, event)
	}
	append(&result.entered, state_def.id)
}

write_configuration :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]State) {
	clear(out)
	if instance.chart == nil do return

	for leaf in instance.active_leaves {
		path := make([dynamic]State)
		cursor := state_index(instance.chart, leaf)
		for cursor != -1 {
			append(&path, instance.chart.def.states[cursor].id)
			cursor = instance.chart.parent_index[cursor]
		}
		for i := len(path) - 1; i >= 0; i -= 1 {
			append(out, path[i])
		}
		delete(path)
	}
}
