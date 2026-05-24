package statecharts

Action :: proc(ctx: rawptr, event: rawptr)
Guard :: proc(ctx: rawptr, event: rawptr) -> bool

State_Index :: distinct int
Transition_Index :: distinct int
Region_Index :: distinct int
History_Index :: distinct int

INVALID_STATE_INDEX :: State_Index(-1)
INVALID_TRANSITION_INDEX :: Transition_Index(-1)
INVALID_REGION_INDEX :: Region_Index(-1)
INVALID_HISTORY_INDEX :: History_Index(-1)

State_Kind :: enum {
	Inferred,
	Atomic,
	Or,
	And,
	Final,
}

State_Def :: struct($State: typeid) {
	id: State,
	kind: State_Kind,
	entry: Action,
	exit: Action,
}

Substate_Def :: struct($State: typeid) {
	substate: State,
	superstate: State,
}

Region_Def :: struct($State: typeid) {
	name: string,
	superstate: State,
	initial: State,
}

Initial_Def :: struct($State: typeid) {
	superstate: State,
	initial: State,
}

History_Kind :: enum {
	Shallow,
	Deep,
}

History_Def :: struct($State: typeid) {
	id: State,
	superstate: State,
	fallback: State,
	kind: History_Kind,
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

Done_Def :: struct($State, $Trigger: typeid) {
	state: State,
	trigger: Trigger,
}

After_Def :: struct($State, $Trigger: typeid) {
	state: State,
	delay_ms: u64,
	trigger: Trigger,
}

Event :: struct($Trigger: typeid) {
	id: Trigger,
	data: rawptr,
}

Runtime_Context :: struct($Trigger: typeid) {
	user: rawptr,
	internal_events: ^[dynamic]Event(Trigger),
	overflow: ^bool,
}

Runtime_Context_Header :: struct {
	user: rawptr,
}

Chart_Def :: struct($State, $Trigger: typeid) {
	initial: State,
	states: []State_Def(State),
	substates: []Substate_Def(State),
	regions: []Region_Def(State),
	initials: []Initial_Def(State),
	histories: []History_Def(State),
	transitions: []Transition_Def(State, Trigger),
	done_events: []Done_Def(State, Trigger),
	after_events: []After_Def(State, Trigger),
}

Transition_Range :: struct {
	start: int,
	count: int,
}

Region_Range :: struct {
	start: int,
	count: int,
}

Compiled_Region :: struct {
	name: string,
	superstate: State_Index,
	initial: State_Index,
}

Compiled_History :: struct($State: typeid) {
	id: State,
	superstate: State_Index,
	fallback: State_Index,
	kind: History_Kind,
}

Active_After :: struct($Trigger: typeid) {
	active: bool,
	state_index: State_Index,
	due_ms: u64,
	trigger: Trigger,
}

Chart :: struct($State, $Trigger: typeid) {
	def: Chart_Def(State, Trigger),
	parent_index: [dynamic]State_Index,
	initial_index: [dynamic]State_Index,
	regions: [dynamic]Compiled_Region,
	histories: [dynamic]Compiled_History(State),
	state_region_index: [dynamic]Region_Index,
	state_owned_region_index: [dynamic]Region_Index,
	state_owned_region_ranges: [dynamic]Region_Range,
	state_owned_region_indices: [dynamic]Region_Index,
	transition_ranges: [dynamic]Transition_Range,
	transition_indices: [dynamic]Transition_Index,
	transition_source_indices: [dynamic]State_Index,
	transition_target_indices: [dynamic]State_Index,
	transition_target_history_indices: [dynamic]History_Index,
}

Compile_Options :: struct {
	allow_ambiguous_transitions: bool,
}

Instance :: struct($State, $Trigger: typeid) {
	chart: ^Chart(State, Trigger),
	active_leaf_indices: [dynamic]State_Index,
	history_indices: [dynamic]State_Index,
	deep_history_indices: [dynamic]State_Index,
	internal_event_queue: [dynamic]Event(Trigger),
	after_events: [dynamic]Active_After(Trigger),
	current_time_ms: u64,

	exited_scratch: [dynamic]State,
	entered_scratch: [dynamic]State,
	configuration_scratch: [dynamic]State,
	path_scratch: [dynamic]State_Index,
	exit_index_scratch: [dynamic]State_Index,
	candidate_transition_scratch: [dynamic]Enabled_Transition,
	enabled_transition_scratch: [dynamic]Enabled_Transition,
}

Run_To_Completion_Options :: struct {
	max_internal_events: int,
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
	Missing_Done_State,
	Missing_After_State,
	Ambiguous_Transition,
	Atomic_State_Has_Substates,
	Final_State_Has_Substates,
	And_State_Missing_Region,
	Duplicate_Region_Name,
	Duplicate_History,
	History_Id_Conflicts_With_State,
	Missing_History_Superstate,
	Missing_History_Fallback,
	History_Fallback_Not_Direct_Substate,
	Deep_History_On_And_State,
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
	exited: []State,
	entered: []State,
	configuration: []State,
}

Transition_Step :: struct($State: typeid) {
	source: State,
	target: State,
}

Enabled_Transition :: struct {
	found: bool,
	blocked_by_guard: bool,
	leaf_index: State_Index,
	transition_index: Transition_Index,
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
	if chart.regions != nil {
		delete(chart.regions)
		chart.regions = nil
	}
	if chart.histories != nil {
		delete(chart.histories)
		chart.histories = nil
	}
	if chart.state_region_index != nil {
		delete(chart.state_region_index)
		chart.state_region_index = nil
	}
	if chart.state_owned_region_index != nil {
		delete(chart.state_owned_region_index)
		chart.state_owned_region_index = nil
	}
	if chart.state_owned_region_ranges != nil {
		delete(chart.state_owned_region_ranges)
		chart.state_owned_region_ranges = nil
	}
	if chart.state_owned_region_indices != nil {
		delete(chart.state_owned_region_indices)
		chart.state_owned_region_indices = nil
	}
	if chart.transition_ranges != nil {
		delete(chart.transition_ranges)
		chart.transition_ranges = nil
	}
	if chart.transition_indices != nil {
		delete(chart.transition_indices)
		chart.transition_indices = nil
	}
	if chart.transition_source_indices != nil {
		delete(chart.transition_source_indices)
		chart.transition_source_indices = nil
	}
	if chart.transition_target_indices != nil {
		delete(chart.transition_target_indices)
		chart.transition_target_indices = nil
	}
	if chart.transition_target_history_indices != nil {
		delete(chart.transition_target_history_indices)
		chart.transition_target_history_indices = nil
	}
}

destroy_instance :: proc(instance: ^Instance($State, $Trigger)) {
	if instance.active_leaf_indices != nil {
		delete(instance.active_leaf_indices)
		instance.active_leaf_indices = nil
	}
	if instance.history_indices != nil {
		delete(instance.history_indices)
		instance.history_indices = nil
	}
	if instance.deep_history_indices != nil {
		delete(instance.deep_history_indices)
		instance.deep_history_indices = nil
	}
	if instance.internal_event_queue != nil {
		delete(instance.internal_event_queue)
		instance.internal_event_queue = nil
	}
	if instance.after_events != nil {
		delete(instance.after_events)
		instance.after_events = nil
	}
	if instance.exited_scratch != nil {
		delete(instance.exited_scratch)
		instance.exited_scratch = nil
	}
	if instance.entered_scratch != nil {
		delete(instance.entered_scratch)
		instance.entered_scratch = nil
	}
	if instance.configuration_scratch != nil {
		delete(instance.configuration_scratch)
		instance.configuration_scratch = nil
	}
	if instance.path_scratch != nil {
		delete(instance.path_scratch)
		instance.path_scratch = nil
	}
	if instance.exit_index_scratch != nil {
		delete(instance.exit_index_scratch)
		instance.exit_index_scratch = nil
	}
	if instance.enabled_transition_scratch != nil {
		delete(instance.enabled_transition_scratch)
		instance.enabled_transition_scratch = nil
	}
	if instance.candidate_transition_scratch != nil {
		delete(instance.candidate_transition_scratch)
		instance.candidate_transition_scratch = nil
	}
	instance.chart = nil
}

destroy_dispatch_result :: proc(result: ^Dispatch_Result($State)) {
	result.exited = nil
	result.entered = nil
	result.configuration = nil
}

compile :: proc(out: ^Chart($State, $Trigger), def: Chart_Def(State, Trigger), options := Compile_Options{}) -> Compile_Result {
	destroy_chart(out)
	out.def = def
	out.parent_index = make([dynamic]State_Index, 0, len(def.states))
	out.initial_index = make([dynamic]State_Index, 0, len(def.states))
	out.regions = make([dynamic]Compiled_Region, 0, len(def.regions) + len(def.initials) + 1)
	out.histories = make([dynamic]Compiled_History(State), 0, len(def.histories))
	out.state_region_index = make([dynamic]Region_Index, 0, len(def.states))
	out.state_owned_region_index = make([dynamic]Region_Index, 0, len(def.states))
	out.state_owned_region_ranges = make([dynamic]Region_Range, 0, len(def.states))
	out.state_owned_region_indices = make([dynamic]Region_Index, 0, len(def.regions) + len(def.initials))
	out.transition_ranges = make([dynamic]Transition_Range, 0, len(def.states))
	out.transition_indices = make([dynamic]Transition_Index, 0, len(def.transitions))
	out.transition_source_indices = make([dynamic]State_Index, 0, len(def.transitions))
	out.transition_target_indices = make([dynamic]State_Index, 0, len(def.transitions))
	out.transition_target_history_indices = make([dynamic]History_Index, 0, len(def.transitions))

	for _ in def.states {
		append(&out.parent_index, INVALID_STATE_INDEX)
		append(&out.initial_index, INVALID_STATE_INDEX)
		append(&out.state_region_index, INVALID_REGION_INDEX)
		append(&out.state_owned_region_index, INVALID_REGION_INDEX)
		append(&out.state_owned_region_ranges, Region_Range{})
		append(&out.transition_ranges, Transition_Range{})
	}
	for _ in def.transitions {
		append(&out.transition_indices, INVALID_TRANSITION_INDEX)
		append(&out.transition_source_indices, INVALID_STATE_INDEX)
		append(&out.transition_target_indices, INVALID_STATE_INDEX)
		append(&out.transition_target_history_indices, INVALID_HISTORY_INDEX)
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
	if initial_idx == INVALID_STATE_INDEX {
		add_error(&result, .Missing_Initial_State)
	}

	for substate, i in def.substates {
		sub_idx := state_index(out, substate.substate)
		super_idx := state_index(out, substate.superstate)
		if sub_idx == INVALID_STATE_INDEX {
			add_error(&result, .Missing_Substate, substate_index = i)
			continue
		}
		if super_idx == INVALID_STATE_INDEX {
			add_error(&result, .Missing_Superstate, substate_index = i)
			continue
		}
		if sub_idx == super_idx {
			add_error(&result, .Self_Substate, substate_index = i)
			continue
		}
		if out.parent_index[sub_idx] != INVALID_STATE_INDEX {
			add_error(&result, .Duplicate_Substate, substate_index = i)
			continue
		}
		out.parent_index[sub_idx] = super_idx
	}

	if initial_idx != INVALID_STATE_INDEX && out.parent_index[initial_idx] != INVALID_STATE_INDEX {
		add_error(&result, .Initial_Not_Top_Level, state_index = int(initial_idx))
	}

	for region, i in def.regions {
		add_region_initial(out, &result, region.superstate, region.initial, i)
	}

	for initial, i in def.initials {
		add_region_initial(out, &result, initial.superstate, initial.initial, i)
	}

	validate_region_names(out, &result)
	validate_and_regions(out, &result)
	validate_histories(out, &result)

	for i in 0 ..< len(def.states) {
		state_idx := State_Index(i)
		if has_superstate_cycle(out, state_idx) {
			add_error(&result, .Superstate_Cycle, state_index = i)
		}

		has_child := state_has_child(out, state_idx)
		state_kind := effective_state_kind(out, state_idx)
		if state_kind == .Atomic && has_child {
			add_error(&result, .Atomic_State_Has_Substates, state_index = i)
		}
		if state_kind == .Final && has_child {
			add_error(&result, .Final_State_Has_Substates, state_index = i)
		}

		if has_child && out.initial_index[i] == INVALID_STATE_INDEX {
			add_error(&result, .Superstate_Missing_Initial, state_index = i)
		}
		if !has_child && out.initial_index[i] != INVALID_STATE_INDEX {
			add_error(&result, .Leaf_Has_Initial, state_index = i)
		}
	}

	for transition, i in def.transitions {
		source_idx := state_index(out, transition.source)
		target_idx := state_index(out, transition.target)
		history_idx := history_index(out, transition.target)
		if source_idx == INVALID_STATE_INDEX {
			add_error(&result, .Missing_Transition_Source, transition_index = i)
		} else {
			out.transition_source_indices[i] = source_idx
		}
		if target_idx == INVALID_STATE_INDEX && history_idx == INVALID_HISTORY_INDEX {
			add_error(&result, .Missing_Transition_Target, transition_index = i)
		} else if history_idx != INVALID_HISTORY_INDEX {
			out.transition_target_history_indices[i] = history_idx
		} else {
			out.transition_target_indices[i] = target_idx
		}
	}

	for done, i in def.done_events {
		done_idx := state_index(out, done.state)
		if done_idx == INVALID_STATE_INDEX {
			add_error(&result, .Missing_Done_State, initial_index = i)
		}
	}

	for after, i in def.after_events {
		after_idx := state_index(out, after.state)
		if after_idx == INVALID_STATE_INDEX {
			add_error(&result, .Missing_After_State, initial_index = i)
		}
	}

	if !options.allow_ambiguous_transitions {
		for i in 0 ..< len(def.transitions) {
			for j in i + 1 ..< len(def.transitions) {
				if def.transitions[i].source == def.transitions[j].source &&
				   def.transitions[i].trigger == def.transitions[j].trigger {
					add_error(&result, .Ambiguous_Transition, transition_index = j)
				}
			}
		}
	}

	build_transition_adjacency(out)
	build_regions(out)
	build_histories(out)

	result.ok = len(result.errors) == 0
	return result
}

add_region_initial :: proc(
	chart: ^Chart($State, $Trigger),
	result: ^Compile_Result,
	superstate: State,
	initial: State,
	index: int,
) {
	super_idx := state_index(chart, superstate)
	init_idx := state_index(chart, initial)
	if super_idx == INVALID_STATE_INDEX {
		add_error(result, .Missing_Initial_Superstate, initial_index = index)
		return
	}
	if init_idx == INVALID_STATE_INDEX {
		add_error(result, .Missing_Initial_Substate, initial_index = index)
		return
	}
	if chart.parent_index[init_idx] != super_idx {
		add_error(result, .Initial_Not_Direct_Substate, initial_index = index)
		return
	}
	if chart.initial_index[super_idx] != INVALID_STATE_INDEX && effective_state_kind(chart, super_idx) != .And {
		add_error(result, .Duplicate_Initial, initial_index = index)
		return
	}
	if chart.initial_index[super_idx] == INVALID_STATE_INDEX {
		chart.initial_index[super_idx] = init_idx
	}
}

validate_and_regions :: proc(chart: ^Chart($State, $Trigger), result: ^Compile_Result) {
	for _, i in chart.def.states {
		state_idx := State_Index(i)
		if effective_state_kind(chart, state_idx) != .And {
			continue
		}

		child_count := 0
		for parent, child_idx in chart.parent_index {
			if parent != state_idx {
				continue
			}

			child_count += 1
			region_count := region_initial_count_for_child(chart, state_idx, State_Index(child_idx))
			if region_count == 0 {
				add_error(result, .And_State_Missing_Region, state_index = child_idx)
			} else if region_count > 1 {
				add_error(result, .Duplicate_Initial, state_index = child_idx)
			}
		}

		if child_count == 0 {
			add_error(result, .And_State_Missing_Region, state_index = i)
		}
	}
}

validate_region_names :: proc(chart: ^Chart($State, $Trigger), result: ^Compile_Result) {
	for region, i in chart.def.regions {
		if region.name == "" {
			continue
		}

		for other, j in chart.def.regions {
			if j <= i {
				continue
			}
			if other.name == "" {
				continue
			}
			if region.superstate == other.superstate && region.name == other.name {
				add_error(result, .Duplicate_Region_Name, initial_index = j)
			}
		}
	}
}

validate_histories :: proc(chart: ^Chart($State, $Trigger), result: ^Compile_Result) {
	for history, i in chart.def.histories {
		if state_index(chart, history.id) != INVALID_STATE_INDEX {
			add_error(result, .History_Id_Conflicts_With_State, initial_index = i)
		}

		for other, j in chart.def.histories {
			if j <= i {
				continue
			}
			if history.id == other.id {
				add_error(result, .Duplicate_History, initial_index = j)
			}
		}

		super_idx := state_index(chart, history.superstate)
		if super_idx == INVALID_STATE_INDEX {
			add_error(result, .Missing_History_Superstate, initial_index = i)
			continue
		}
		if history.kind == .Deep && effective_state_kind(chart, super_idx) == .And {
			add_error(result, .Deep_History_On_And_State, initial_index = i)
		}

		fallback_idx := state_index(chart, history.fallback)
		if fallback_idx == INVALID_STATE_INDEX {
			add_error(result, .Missing_History_Fallback, initial_index = i)
			continue
		}

		if history.kind == .Shallow && chart.parent_index[fallback_idx] != super_idx {
			add_error(result, .History_Fallback_Not_Direct_Substate, initial_index = i)
		}
		if history.kind == .Deep && !state_is_descendant_or_self(chart, fallback_idx, super_idx) {
			add_error(result, .History_Fallback_Not_Direct_Substate, initial_index = i)
		}
	}
}

region_initial_count_for_child :: proc(
	chart: ^Chart($State, $Trigger),
	super_idx: State_Index,
	child_idx: State_Index,
) -> int {
	superstate := chart.def.states[super_idx].id
	child := chart.def.states[child_idx].id
	count := 0

	for region in chart.def.regions {
		if region.superstate == superstate && region.initial == child {
			count += 1
		}
	}

	for initial in chart.def.initials {
		if initial.superstate == superstate && initial.initial == child {
			count += 1
		}
	}

	return count
}

init :: proc(instance: ^Instance($State, $Trigger), chart: ^Chart(State, Trigger)) -> bool {
	destroy_instance(instance)
	instance.chart = chart
	if chart == nil do return false

	state_count := len(chart.def.states)
	instance.active_leaf_indices = make([dynamic]State_Index, 0, state_count)
	instance.history_indices = make([dynamic]State_Index, 0, state_count)
	instance.deep_history_indices = make([dynamic]State_Index, 0, state_count)
	internal_event_capacity := len(chart.def.transitions)
	if internal_event_capacity < state_count {
		internal_event_capacity = state_count
	}
	if internal_event_capacity < len(chart.def.done_events) + 1 {
		internal_event_capacity = len(chart.def.done_events) + 1
	}
	if internal_event_capacity < len(chart.def.after_events) + len(chart.def.done_events) + 1 {
		internal_event_capacity = len(chart.def.after_events) + len(chart.def.done_events) + 1
	}
	if internal_event_capacity < 8 {
		internal_event_capacity = 8
	}
	instance.internal_event_queue = make([dynamic]Event(Trigger), 0, internal_event_capacity)
	instance.after_events = make([dynamic]Active_After(Trigger), 0, len(chart.def.after_events))
	instance.exited_scratch = make([dynamic]State, 0, state_count)
	instance.entered_scratch = make([dynamic]State, 0, state_count)
	instance.configuration_scratch = make([dynamic]State, 0, state_count)
	instance.path_scratch = make([dynamic]State_Index, 0, state_count)
	instance.exit_index_scratch = make([dynamic]State_Index, 0, state_count)
	instance.candidate_transition_scratch = make([dynamic]Enabled_Transition, 0, state_count)
	instance.enabled_transition_scratch = make([dynamic]Enabled_Transition, 0, state_count)
	for _ in 0 ..< state_count {
		append(&instance.history_indices, INVALID_STATE_INDEX)
		append(&instance.deep_history_indices, INVALID_STATE_INDEX)
	}
	for _ in chart.def.after_events {
		append(&instance.after_events, Active_After(Trigger){state_index = INVALID_STATE_INDEX})
	}
	return true
}

enter_initial :: proc(instance: ^Instance($State, $Trigger), ctx: rawptr = nil) -> Dispatch_Result(State) {
	reset_dispatch_scratch(instance)
	result := Dispatch_Result(State){}
	if instance.chart == nil {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}

	clear(&instance.active_leaf_indices)
	reset_history(instance)
	reset_after_events(instance)
	if len(instance.chart.regions) == 0 {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}

	initial_idx := instance.chart.regions[0].initial
	if initial_idx == INVALID_STATE_INDEX {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}

	enter_from_index(instance, initial_idx, ctx, nil, &result)
	result.status = .Transitioned
	write_configuration_scratch(instance)
	finalize_dispatch_result(instance, &result)
	return result
}

enter_initial_at :: proc(
	instance: ^Instance($State, $Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
) -> Dispatch_Result(State) {
	instance.current_time_ms = now_ms
	return enter_initial(instance, ctx)
}

dispatch :: proc(instance: ^Instance($State, $Trigger), event: Event(Trigger), ctx: rawptr = nil) -> Dispatch_Result(State) {
	reset_dispatch_scratch(instance)
	result := Dispatch_Result(State){}
	event_value := event
	dispatch_event_step(instance, &event_value, ctx, &result)
	return result
}

dispatch_at :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
) -> Dispatch_Result(State) {
	instance.current_time_ms = now_ms
	return dispatch(instance, event, ctx)
}

dispatch_run_to_completion :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
	reset_dispatch_scratch(instance)
	result := Dispatch_Result(State){}
	if instance.chart == nil || len(instance.active_leaf_indices) == 0 {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}

	clear(&instance.internal_event_queue)
	overflow := false
	runtime_ctx := Runtime_Context(Trigger){
		user = ctx,
		internal_events = &instance.internal_event_queue,
		overflow = &overflow,
	}

	max_internal_events := options.max_internal_events
	if max_internal_events <= 0 {
		max_internal_events = cap(instance.internal_event_queue)
	}

	transitioned := false
	blocked_by_guard := false

	event_value := event
	entered_start := len(instance.entered_scratch)
	dispatch_event_step(instance, &event_value, &runtime_ctx, &result)
	if result.status == .Transitioned {
		raise_completion_events(instance, &runtime_ctx, entered_start)
	}
	if result.status == .Error || overflow {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}
	if result.status == .Transitioned {
		transitioned = true
	} else if result.status == .Blocked_By_Guard {
		blocked_by_guard = true
	}

	read_index := 0
	processed_internal_events := 0
	for read_index < len(instance.internal_event_queue) {
		if processed_internal_events >= max_internal_events {
			result.status = .Error
			finalize_dispatch_result(instance, &result)
			return result
		}

		event_value = instance.internal_event_queue[read_index]
		read_index += 1
		processed_internal_events += 1

		entered_start = len(instance.entered_scratch)
		dispatch_event_step(instance, &event_value, &runtime_ctx, &result)
		if result.status == .Transitioned {
			raise_completion_events(instance, &runtime_ctx, entered_start)
		}
		if result.status == .Error || overflow {
			result.status = .Error
			finalize_dispatch_result(instance, &result)
			return result
		}
		if result.status == .Transitioned {
			transitioned = true
		} else if result.status == .Blocked_By_Guard {
			blocked_by_guard = true
		}
	}

	clear(&instance.internal_event_queue)
	if transitioned {
		result.status = .Transitioned
	} else if blocked_by_guard {
		result.status = .Blocked_By_Guard
	} else {
		result.status = .Ignored
	}
	write_configuration_scratch(instance)
	finalize_dispatch_result(instance, &result)
	return result
}

dispatch_run_to_completion_at :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
	instance.current_time_ms = now_ms
	return dispatch_run_to_completion(instance, event, ctx, options)
}

dispatch_due_events :: proc(
	instance: ^Instance($State, $Trigger),
	now_ms: u64,
	ctx: rawptr = nil,
	options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
	instance.current_time_ms = now_ms
	reset_dispatch_scratch(instance)
	result := Dispatch_Result(State){}
	if instance.chart == nil || len(instance.active_leaf_indices) == 0 {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}

	clear(&instance.internal_event_queue)
	overflow := false
	runtime_ctx := Runtime_Context(Trigger){
		user = ctx,
		internal_events = &instance.internal_event_queue,
		overflow = &overflow,
	}
	enqueue_due_events(instance, &runtime_ctx, now_ms)
	if overflow {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}
	if len(instance.internal_event_queue) == 0 {
		result.status = .Ignored
		write_configuration_scratch(instance)
		finalize_dispatch_result(instance, &result)
		return result
	}

	max_internal_events := options.max_internal_events
	if max_internal_events <= 0 {
		max_internal_events = cap(instance.internal_event_queue)
	}

	transitioned := false
	blocked_by_guard := false
	read_index := 0
	processed_internal_events := 0
	for read_index < len(instance.internal_event_queue) {
		if processed_internal_events >= max_internal_events {
			result.status = .Error
			finalize_dispatch_result(instance, &result)
			return result
		}

		event_value := instance.internal_event_queue[read_index]
		read_index += 1
		processed_internal_events += 1

		entered_start := len(instance.entered_scratch)
		dispatch_event_step(instance, &event_value, &runtime_ctx, &result)
		if result.status == .Transitioned {
			raise_completion_events(instance, &runtime_ctx, entered_start)
			enqueue_due_events(instance, &runtime_ctx, now_ms)
		}
		if result.status == .Error || overflow {
			result.status = .Error
			finalize_dispatch_result(instance, &result)
			return result
		}
		if result.status == .Transitioned {
			transitioned = true
		} else if result.status == .Blocked_By_Guard {
			blocked_by_guard = true
		}
	}

	clear(&instance.internal_event_queue)
	if transitioned {
		result.status = .Transitioned
	} else if blocked_by_guard {
		result.status = .Blocked_By_Guard
	} else {
		result.status = .Ignored
	}
	write_configuration_scratch(instance)
	finalize_dispatch_result(instance, &result)
	return result
}

dispatch_event_step :: proc(
	instance: ^Instance($State, $Trigger),
	event: ^Event(Trigger),
	ctx: rawptr,
	result: ^Dispatch_Result(State),
) {
	if instance.chart == nil || len(instance.active_leaf_indices) == 0 {
		result.status = .Error
		finalize_dispatch_result(instance, result)
		return
	}

	if len(instance.active_leaf_indices) == 1 {
		enabled := find_enabled_transition_from_leaf(instance, instance.active_leaf_indices[0], event, ctx)
		if enabled.found {
			transition := instance.chart.def.transitions[enabled.transition_index]
			apply_transition_step(instance, transition, enabled.transition_index, enabled.leaf_index, event, ctx, result)
			if result.status != .Error {
				result.status = .Transitioned
				write_configuration_scratch(instance)
			}
			finalize_dispatch_result(instance, result)
			return
		}

		if enabled.blocked_by_guard {
			result.status = .Blocked_By_Guard
		} else {
			result.status = .Ignored
		}
		write_configuration_scratch(instance)
		finalize_dispatch_result(instance, result)
		return
	}

	dispatch_multi_leaf(instance, event, ctx, result)
}

dispatch_with_trace :: proc(
	instance: ^Instance($State, $Trigger),
	event: Event(Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	ctx: rawptr = nil,
) -> Dispatch_Result(State) {
	clear(transitions)
	reset_dispatch_scratch(instance)
	result := Dispatch_Result(State){}
	if instance.chart == nil || len(instance.active_leaf_indices) == 0 {
		result.status = .Error
		finalize_dispatch_result(instance, &result)
		return result
	}

	event_value := event
	if len(instance.active_leaf_indices) == 1 {
		enabled := find_enabled_transition_from_leaf(instance, instance.active_leaf_indices[0], &event_value, ctx)
		if enabled.found {
			transition := instance.chart.def.transitions[enabled.transition_index]
			apply_transition_step(instance, transition, enabled.transition_index, enabled.leaf_index, &event_value, ctx, &result)
			if result.status != .Error {
				append_transition_trace(transitions, transition)
				result.status = .Transitioned
				write_configuration_scratch(instance)
			}
			finalize_dispatch_result(instance, &result)
			return result
		}

		if enabled.blocked_by_guard {
			result.status = .Blocked_By_Guard
		} else {
			result.status = .Ignored
		}
		write_configuration_scratch(instance)
		finalize_dispatch_result(instance, &result)
		return result
	}

	dispatch_multi_leaf_with_trace(instance, &event_value, transitions, ctx, &result)
	return result
}

dispatch_multi_leaf :: proc(
	instance: ^Instance($State, $Trigger),
	event: ^Event(Trigger),
	ctx: rawptr,
	result: ^Dispatch_Result(State),
) {
	blocked_by_guard := collect_enabled_transitions(instance, event, ctx)
	if len(instance.enabled_transition_scratch) > 0 {
		for enabled in instance.enabled_transition_scratch {
			transition := instance.chart.def.transitions[enabled.transition_index]
			apply_transition_step(instance, transition, enabled.transition_index, enabled.leaf_index, event, ctx, result)
			if result.status == .Error {
				finalize_dispatch_result(instance, result)
				return
			}
		}
		result.status = .Transitioned
		write_configuration_scratch(instance)
		finalize_dispatch_result(instance, result)
		return
	}

	if blocked_by_guard {
		result.status = .Blocked_By_Guard
	} else {
		result.status = .Ignored
	}
	write_configuration_scratch(instance)
	finalize_dispatch_result(instance, result)
}

dispatch_multi_leaf_with_trace :: proc(
	instance: ^Instance($State, $Trigger),
	event: ^Event(Trigger),
	transitions: ^[dynamic]Transition_Step(State),
	ctx: rawptr,
	result: ^Dispatch_Result(State),
) {
	blocked_by_guard := collect_enabled_transitions(instance, event, ctx)
	if len(instance.enabled_transition_scratch) > 0 {
		for enabled in instance.enabled_transition_scratch {
			transition := instance.chart.def.transitions[enabled.transition_index]
			apply_transition_step(instance, transition, enabled.transition_index, enabled.leaf_index, event, ctx, result)
			if result.status == .Error {
				finalize_dispatch_result(instance, result)
				return
			}
			append_transition_trace(transitions, transition)
		}
		result.status = .Transitioned
		write_configuration_scratch(instance)
		finalize_dispatch_result(instance, result)
		return
	}

	if blocked_by_guard {
		result.status = .Blocked_By_Guard
	} else {
		result.status = .Ignored
	}
	write_configuration_scratch(instance)
	finalize_dispatch_result(instance, result)
}

append_transition_trace :: proc(out: ^[dynamic]Transition_Step($State), transition: Transition_Def(State, $Trigger)) {
	append(out, Transition_Step(State){
		source = transition.source,
		target = transition.target,
	})
}

is_active :: proc(instance: ^Instance($State, $Trigger), state: State) -> bool {
	if instance.chart == nil do return false
	state_idx := state_index(instance.chart, state)
	if state_idx == INVALID_STATE_INDEX do return false
	for leaf_idx in instance.active_leaf_indices {
		cursor := leaf_idx
		for cursor != INVALID_STATE_INDEX {
			if cursor == state_idx do return true
			cursor = instance.chart.parent_index[cursor]
		}
	}
	return false
}

configuration :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]State) {
	write_configuration(instance, out)
}

user_context :: proc(ctx_raw: rawptr) -> rawptr {
	if ctx_raw == nil {
		return nil
	}
	runtime_ctx := cast(^Runtime_Context_Header)ctx_raw
	return runtime_ctx.user
}

enqueue_internal_event :: proc(runtime_ctx: ^Runtime_Context($Trigger), event: Event(Trigger)) -> bool {
	if runtime_ctx == nil || runtime_ctx.internal_events == nil {
		return false
	}
	if len(runtime_ctx.internal_events^) >= cap(runtime_ctx.internal_events^) {
		if runtime_ctx.overflow != nil {
			runtime_ctx.overflow^ = true
		}
		return false
	}
	append(runtime_ctx.internal_events, event)
	return true
}

raise :: proc(ctx_raw: rawptr, event: Event($Trigger)) -> bool {
	if ctx_raw == nil {
		return false
	}
	runtime_ctx := cast(^Runtime_Context(Trigger))ctx_raw
	return enqueue_internal_event(runtime_ctx, event)
}

active_leaf_in_region :: proc(
	instance: ^Instance($State, $Trigger),
	superstate: State,
	region_name: string,
) -> (State, bool) {
	state: State
	if instance.chart == nil {
		return state, false
	}

	super_idx := state_index(instance.chart, superstate)
	if super_idx == INVALID_STATE_INDEX {
		return state, false
	}

	region_idx := region_index(instance.chart, super_idx, region_name)
	if region_idx == INVALID_REGION_INDEX {
		return state, false
	}

	region_initial_idx := instance.chart.regions[region_idx].initial
	for leaf_idx in instance.active_leaf_indices {
		if state_is_descendant_or_self(instance.chart, leaf_idx, region_initial_idx) {
			return instance.chart.def.states[leaf_idx].id, true
		}
	}

	return state, false
}

is_complete :: proc(instance: ^Instance($State, $Trigger), state: State) -> bool {
	if instance.chart == nil {
		return false
	}

	state_idx := state_index(instance.chart, state)
	if state_idx == INVALID_STATE_INDEX {
		return false
	}

	return state_is_complete(instance, state_idx)
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

state_index :: proc(chart: ^Chart($State, $Trigger), state: State) -> State_Index {
	for state_def, i in chart.def.states {
		if state_def.id == state do return State_Index(i)
	}
	return INVALID_STATE_INDEX
}

region_index :: proc(chart: ^Chart($State, $Trigger), super_idx: State_Index, name: string) -> Region_Index {
	for region, i in chart.regions {
		if region.superstate == super_idx && region.name == name {
			return Region_Index(i)
		}
	}
	return INVALID_REGION_INDEX
}

history_index :: proc(chart: ^Chart($State, $Trigger), history_id: State) -> History_Index {
	for history, i in chart.def.histories {
		if history.id == history_id {
			return History_Index(i)
		}
	}
	return INVALID_HISTORY_INDEX
}

state_has_child :: proc(chart: ^Chart($State, $Trigger), state_idx: State_Index) -> bool {
	for parent in chart.parent_index {
		if parent == state_idx do return true
	}
	return false
}

effective_state_kind :: proc(chart: ^Chart($State, $Trigger), state_idx: State_Index) -> State_Kind {
	state_kind := chart.def.states[state_idx].kind
	if state_kind != .Inferred do return state_kind
	if state_has_child(chart, state_idx) do return .Or
	return .Atomic
}

collect_enabled_transitions :: proc(
	instance: ^Instance($State, $Trigger),
	event: ^Event(Trigger),
	ctx: rawptr,
) -> bool {
	clear(&instance.candidate_transition_scratch)
	clear(&instance.enabled_transition_scratch)
	blocked_by_guard := false

	for leaf_idx in instance.active_leaf_indices {
		enabled := find_enabled_transition_from_leaf(instance, leaf_idx, event, ctx)
		if enabled.blocked_by_guard {
			blocked_by_guard = true
		}
		if !enabled.found {
			continue
		}

		append(&instance.candidate_transition_scratch, enabled)
	}

	select_enabled_transitions(instance)
	return blocked_by_guard
}

select_enabled_transitions :: proc(instance: ^Instance($State, $Trigger)) {
	for candidate in instance.candidate_transition_scratch {
		candidate_source_idx := instance.chart.transition_source_indices[candidate.transition_index]
		candidate_exit_root_idx := transition_exit_root(instance.chart, candidate.transition_index)

		should_select := true
		for i := len(instance.enabled_transition_scratch) - 1; i >= 0; i -= 1 {
			selected := instance.enabled_transition_scratch[i]
			selected_source_idx := instance.chart.transition_source_indices[selected.transition_index]
			selected_exit_root_idx := transition_exit_root(instance.chart, selected.transition_index)

			if !exit_roots_conflict(instance.chart, candidate_exit_root_idx, selected_exit_root_idx) {
				continue
			}

			if state_is_descendant_or_self(instance.chart, candidate_source_idx, selected_source_idx) {
				ordered_remove(&instance.enabled_transition_scratch, i)
				continue
			}

			should_select = false
			break
		}

		if should_select {
			append(&instance.enabled_transition_scratch, candidate)
		}
	}
}

find_enabled_transition_from_leaf :: #force_inline proc(
	instance: ^Instance($State, $Trigger),
	leaf_idx: State_Index,
	event: ^Event(Trigger),
	ctx: rawptr,
) -> Enabled_Transition {
	result := Enabled_Transition{
		leaf_index = INVALID_STATE_INDEX,
		transition_index = INVALID_TRANSITION_INDEX,
	}
	if leaf_idx == INVALID_STATE_INDEX do return result

	cursor := leaf_idx
	for cursor != INVALID_STATE_INDEX {
		transition_range := instance.chart.transition_ranges[cursor]
		for offset in 0 ..< transition_range.count {
			transition_idx := instance.chart.transition_indices[transition_range.start + offset]
			if transition_idx == INVALID_TRANSITION_INDEX do continue

			transition := instance.chart.def.transitions[transition_idx]
			if transition.trigger != event.id {
				continue
			}
			if transition.guard != nil && !transition.guard(ctx, event) {
				result.blocked_by_guard = true
				continue
			}

			result.found = true
			result.leaf_index = leaf_idx
			result.transition_index = transition_idx
			return result
		}
		cursor = instance.chart.parent_index[cursor]
	}

	return result
}

transition_exit_root :: proc(chart: ^Chart($State, $Trigger), transition_idx: Transition_Index) -> State_Index {
	source_idx := chart.transition_source_indices[transition_idx]
	target_idx := transition_target_entry_index(chart, transition_idx)
	if target_idx == INVALID_STATE_INDEX {
		return source_idx
	}
	lca_idx := least_common_superstate(chart, source_idx, target_idx)
	if chart.transition_target_history_indices[transition_idx] == INVALID_HISTORY_INDEX && source_idx == target_idx {
		lca_idx = chart.parent_index[source_idx]
	}
	return highest_exited_state(chart, source_idx, lca_idx)
}

exit_roots_conflict :: proc(chart: ^Chart($State, $Trigger), a: State_Index, b: State_Index) -> bool {
	if state_is_descendant_or_self(chart, a, b) {
		return true
	}
	if state_is_descendant_or_self(chart, b, a) {
		return true
	}
	return false
}

build_transition_adjacency :: proc(chart: ^Chart($State, $Trigger)) {
	for i in 0 ..< len(chart.transition_ranges) {
		chart.transition_ranges[i] = Transition_Range{}
	}
	for i in 0 ..< len(chart.transition_indices) {
		chart.transition_indices[i] = INVALID_TRANSITION_INDEX
	}

	for _, transition_index in chart.def.transitions {
		source_idx := chart.transition_source_indices[transition_index]
		if source_idx != INVALID_STATE_INDEX {
			chart.transition_ranges[source_idx].count += 1
		}
	}

	start := 0
	write_offsets := make([dynamic]State_Index, 0, len(chart.def.states))
	defer delete(write_offsets)
	for i in 0 ..< len(chart.transition_ranges) {
		chart.transition_ranges[i].start = start
		append(&write_offsets, State_Index(start))
		start += chart.transition_ranges[i].count
	}

	for _, transition_idx in chart.def.transitions {
		source_idx := chart.transition_source_indices[transition_idx]
		if source_idx == INVALID_STATE_INDEX do continue

		write_idx := write_offsets[source_idx]
		chart.transition_indices[int(write_idx)] = Transition_Index(transition_idx)
		write_offsets[source_idx] += 1
	}
}

build_regions :: proc(chart: ^Chart($State, $Trigger)) {
	clear(&chart.regions)
	clear(&chart.state_owned_region_indices)
	for i in 0 ..< len(chart.state_region_index) {
		chart.state_region_index[i] = INVALID_REGION_INDEX
		chart.state_owned_region_index[i] = INVALID_REGION_INDEX
		chart.state_owned_region_ranges[i] = Region_Range{}
	}

	top_initial := state_index(chart, chart.def.initial)
	top_region := Region_Index(len(chart.regions))
	append(&chart.regions, Compiled_Region{
		name = "",
		superstate = INVALID_STATE_INDEX,
		initial = top_initial,
	})

	for state_idx in 0 ..< len(chart.def.states) {
		if chart.parent_index[state_idx] == INVALID_STATE_INDEX {
			chart.state_region_index[state_idx] = top_region
		}
	}

	for region in chart.def.regions {
		add_compiled_region(chart, region.name, state_index(chart, region.superstate), state_index(chart, region.initial))
	}
	for initial in chart.def.initials {
		add_compiled_region(chart, "", state_index(chart, initial.superstate), state_index(chart, initial.initial))
	}

	build_owned_region_ranges(chart)
}

build_histories :: proc(chart: ^Chart($State, $Trigger)) {
	clear(&chart.histories)
	for history in chart.def.histories {
		super_idx := state_index(chart, history.superstate)
		fallback_idx := state_index(chart, history.fallback)
		if super_idx == INVALID_STATE_INDEX || fallback_idx == INVALID_STATE_INDEX {
			continue
		}

		append(&chart.histories, Compiled_History(State){
			id = history.id,
			superstate = super_idx,
			fallback = fallback_idx,
			kind = history.kind,
		})
	}
}

add_compiled_region :: proc(
	chart: ^Chart($State, $Trigger),
	name: string,
	superstate_idx: State_Index,
	initial_idx: State_Index,
) {
	if superstate_idx == INVALID_STATE_INDEX || initial_idx == INVALID_STATE_INDEX do return

	region_idx := Region_Index(len(chart.regions))
	append(&chart.regions, Compiled_Region{
		name = name,
		superstate = superstate_idx,
		initial = initial_idx,
	})

	if chart.state_owned_region_index[superstate_idx] == INVALID_REGION_INDEX {
		chart.state_owned_region_index[superstate_idx] = region_idx
	}

	if effective_state_kind(chart, superstate_idx) == .And {
		chart.state_region_index[initial_idx] = region_idx
		return
	}

	for substate_idx in 0 ..< len(chart.def.states) {
		if chart.parent_index[substate_idx] == superstate_idx {
			chart.state_region_index[substate_idx] = region_idx
		}
	}
}

build_owned_region_ranges :: proc(chart: ^Chart($State, $Trigger)) {
	for region_idx in 0 ..< len(chart.regions) {
		superstate_idx := chart.regions[region_idx].superstate
		if superstate_idx != INVALID_STATE_INDEX {
			chart.state_owned_region_ranges[superstate_idx].count += 1
		}
	}

	start := 0
	write_offsets := make([dynamic]int, 0, len(chart.def.states))
	defer delete(write_offsets)
	for i in 0 ..< len(chart.state_owned_region_ranges) {
		chart.state_owned_region_ranges[i].start = start
		append(&write_offsets, start)
		start += chart.state_owned_region_ranges[i].count
	}

	for _ in 0 ..< start {
		append(&chart.state_owned_region_indices, INVALID_REGION_INDEX)
	}

	for region_idx in 0 ..< len(chart.regions) {
		superstate_idx := chart.regions[region_idx].superstate
		if superstate_idx == INVALID_STATE_INDEX do continue

		write_idx := write_offsets[superstate_idx]
		chart.state_owned_region_indices[write_idx] = Region_Index(region_idx)
		write_offsets[superstate_idx] += 1
	}
}

has_superstate_cycle :: proc(chart: ^Chart($State, $Trigger), state_idx: State_Index) -> bool {
	cursor := chart.parent_index[state_idx]
	steps := 0
	for cursor != INVALID_STATE_INDEX {
		if cursor == state_idx do return true
		steps += 1
		if steps > len(chart.def.states) do return true
		cursor = chart.parent_index[cursor]
	}
	return false
}

apply_transition_step :: #force_inline proc(
	instance: ^Instance($State, $Trigger),
	transition: Transition_Def(State, Trigger),
	transition_idx: Transition_Index,
	source_leaf_idx: State_Index,
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
		return
	}

	source_idx := instance.chart.transition_source_indices[transition_idx]
	if len(instance.chart.histories) == 0 {
		target_idx := instance.chart.transition_target_indices[transition_idx]
		if source_leaf_idx == INVALID_STATE_INDEX ||
		   source_idx == INVALID_STATE_INDEX ||
		   target_idx == INVALID_STATE_INDEX {
			result.status = .Error
			return
		}

		lca_idx := least_common_superstate(instance.chart, source_idx, target_idx)
		if source_idx == target_idx {
			lca_idx = instance.chart.parent_index[source_idx]
		}

		exit_transition_source(instance, source_idx, source_leaf_idx, lca_idx, ctx, event, result)
		if transition.action != nil {
			transition.action(ctx, event)
		}
		enter_from_index(instance, target_idx, ctx, event, result, stop_idx = lca_idx)
		return
	}

	target_idx := instance.chart.transition_target_indices[transition_idx]
	history_idx := instance.chart.transition_target_history_indices[transition_idx]
	target_entry_idx := transition_target_entry_index(instance.chart, transition_idx)
	resolved_target_idx := target_idx
	if history_idx != INVALID_HISTORY_INDEX {
		resolved_target_idx = resolved_history_target_index(instance, history_idx)
	}
	if source_leaf_idx == INVALID_STATE_INDEX ||
	   source_idx == INVALID_STATE_INDEX ||
	   target_entry_idx == INVALID_STATE_INDEX {
		result.status = .Error
		return
	}

	lca_idx := least_common_superstate(instance.chart, source_idx, target_entry_idx)
	if history_idx == INVALID_HISTORY_INDEX && source_idx == target_idx {
		lca_idx = instance.chart.parent_index[source_idx]
	}

	exit_transition_source(instance, source_idx, source_leaf_idx, lca_idx, ctx, event, result)
	if transition.action != nil {
		transition.action(ctx, event)
	}
	enter_from_index(instance, resolved_target_idx, ctx, event, result, stop_idx = lca_idx)
}

transition_target_entry_index :: proc(chart: ^Chart($State, $Trigger), transition_idx: Transition_Index) -> State_Index {
	history_idx := chart.transition_target_history_indices[transition_idx]
	if history_idx != INVALID_HISTORY_INDEX {
		return chart.histories[history_idx].superstate
	}
	return chart.transition_target_indices[transition_idx]
}

least_common_superstate :: proc(chart: ^Chart($State, $Trigger), a: State_Index, b: State_Index) -> State_Index {
	cursor_a := a
	for cursor_a != INVALID_STATE_INDEX {
		cursor_b := b
		for cursor_b != INVALID_STATE_INDEX {
			if cursor_a == cursor_b do return cursor_a
			cursor_b = chart.parent_index[cursor_b]
		}
		cursor_a = chart.parent_index[cursor_a]
	}
	return INVALID_STATE_INDEX
}

exit_transition_source :: proc(
	instance: ^Instance($State, $Trigger),
	source_idx: State_Index,
	source_leaf_idx: State_Index,
	stop_idx: State_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	if len(instance.active_leaf_indices) == 1 &&
	   instance.active_leaf_indices[0] == source_leaf_idx &&
	   source_idx == source_leaf_idx {
		clear(&instance.active_leaf_indices)
		exit_path_to_index_unchecked(instance, source_idx, stop_idx, ctx, event, result)
		return
	}

	exit_root_idx := highest_exited_state(instance.chart, source_idx, stop_idx)
	if len(instance.active_leaf_indices) == 1 && instance.active_leaf_indices[0] == source_leaf_idx {
		if source_leaf_idx != exit_root_idx {
			exit_path_to_index_unchecked(instance, source_leaf_idx, exit_root_idx, ctx, event, result)
		}
		clear(&instance.active_leaf_indices)
		exit_path_to_index_unchecked(instance, exit_root_idx, stop_idx, ctx, event, result)
		return
	}

	clear(&instance.exit_index_scratch)

	removed_any := false
	for i := len(instance.active_leaf_indices) - 1; i >= 0; i -= 1 {
		leaf_idx := instance.active_leaf_indices[i]
		if !state_is_descendant_or_self(instance.chart, leaf_idx, exit_root_idx) {
			continue
		}

		if leaf_idx != exit_root_idx {
			exit_path_to_index(instance, leaf_idx, exit_root_idx, ctx, event, result)
		}
		ordered_remove(&instance.active_leaf_indices, i)
		removed_any = true
	}

	if !removed_any && source_leaf_idx != INVALID_STATE_INDEX {
		exit_path_to_index(instance, source_leaf_idx, exit_root_idx, ctx, event, result)
		remove_active_leaf(instance, source_leaf_idx)
	}

	exit_path_to_index(instance, exit_root_idx, stop_idx, ctx, event, result)
}

highest_exited_state :: proc(chart: ^Chart($State, $Trigger), source_idx: State_Index, stop_idx: State_Index) -> State_Index {
	result := source_idx
	cursor := source_idx
	for cursor != INVALID_STATE_INDEX && cursor != stop_idx {
		result = cursor
		cursor = chart.parent_index[cursor]
	}
	return result
}

exit_path_to_index_unchecked :: proc(
	instance: ^Instance($State, $Trigger),
	from_idx: State_Index,
	stop_idx: State_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	if len(instance.chart.histories) == 0 && len(instance.chart.def.after_events) == 0 {
		cursor := from_idx
		for cursor != INVALID_STATE_INDEX && cursor != stop_idx {
			state_def := instance.chart.def.states[cursor]
			if state_def.exit != nil {
				state_def.exit(ctx, event)
			}
			append(&instance.exited_scratch, state_def.id)
			cursor = instance.chart.parent_index[cursor]
		}
		return
	}

	cursor := from_idx
	for cursor != INVALID_STATE_INDEX && cursor != stop_idx {
		cancel_after_events_under_state(instance, cursor)
		remember_history(instance, cursor)
		state_def := instance.chart.def.states[cursor]
		if state_def.exit != nil {
			state_def.exit(ctx, event)
		}
		append(&instance.exited_scratch, state_def.id)
		cursor = instance.chart.parent_index[cursor]
	}
}

exit_path_to_index :: proc(
	instance: ^Instance($State, $Trigger),
	from_idx: State_Index,
	stop_idx: State_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	cursor := from_idx
	for cursor != INVALID_STATE_INDEX && cursor != stop_idx {
		exit_one_index(instance, cursor, ctx, event, result)
		cursor = instance.chart.parent_index[cursor]
	}
}

remove_active_leaf :: proc(instance: ^Instance($State, $Trigger), leaf_idx: State_Index) {
	for active_leaf, i in instance.active_leaf_indices {
		if active_leaf == leaf_idx {
			ordered_remove(&instance.active_leaf_indices, i)
			return
		}
	}
}

exit_one_index :: proc(
	instance: ^Instance($State, $Trigger),
	idx: State_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	if state_was_exited(instance, idx) do return

	cancel_after_events_under_state(instance, idx)
	remember_history(instance, idx)
	state_def := instance.chart.def.states[idx]
	if state_def.exit != nil {
		state_def.exit(ctx, event)
	}
	append(&instance.exited_scratch, state_def.id)
	append(&instance.exit_index_scratch, idx)
}

state_was_exited :: proc(instance: ^Instance($State, $Trigger), idx: State_Index) -> bool {
	for exited_idx in instance.exit_index_scratch {
		if exited_idx == idx do return true
	}
	return false
}

remember_history :: #force_inline proc(instance: ^Instance($State, $Trigger), idx: State_Index) {
	if len(instance.chart.histories) == 0 {
		return
	}
	parent_idx := instance.chart.parent_index[idx]
	if parent_idx == INVALID_STATE_INDEX {
		return
	}
	instance.history_indices[parent_idx] = idx

	if instance.chart.state_owned_region_ranges[idx].count != 0 {
		return
	}

	cursor := parent_idx
	for cursor != INVALID_STATE_INDEX {
		instance.deep_history_indices[cursor] = idx
		cursor = instance.chart.parent_index[cursor]
	}
}

reset_history :: proc(instance: ^Instance($State, $Trigger)) {
	for i in 0 ..< len(instance.history_indices) {
		instance.history_indices[i] = INVALID_STATE_INDEX
		instance.deep_history_indices[i] = INVALID_STATE_INDEX
	}
}

reset_after_events :: proc(instance: ^Instance($State, $Trigger)) {
	for &timer in instance.after_events {
		timer.active = false
		timer.state_index = INVALID_STATE_INDEX
	}
}

state_is_descendant_or_self :: proc(chart: ^Chart($State, $Trigger), state_idx: State_Index, ancestor_idx: State_Index) -> bool {
	cursor := state_idx
	for cursor != INVALID_STATE_INDEX {
		if cursor == ancestor_idx do return true
		cursor = chart.parent_index[cursor]
	}
	return false
}

state_is_complete :: proc(instance: ^Instance($State, $Trigger), state_idx: State_Index) -> bool {
	state_kind := effective_state_kind(instance.chart, state_idx)
	if state_kind == .Final {
		return is_active_index(instance, state_idx)
	}

	owned_regions := instance.chart.state_owned_region_ranges[state_idx]
	if owned_regions.count == 0 {
		return false
	}

	for offset in 0 ..< owned_regions.count {
		region_idx := instance.chart.state_owned_region_indices[owned_regions.start + offset]
		if region_idx == INVALID_REGION_INDEX || !region_is_complete(instance, region_idx) {
			return false
		}
	}

	return true
}

region_is_complete :: proc(instance: ^Instance($State, $Trigger), region_idx: Region_Index) -> bool {
	region := instance.chart.regions[region_idx]
	if region.initial == INVALID_STATE_INDEX {
		return false
	}

	ancestor_idx := region.initial
	if region.superstate != INVALID_STATE_INDEX &&
	   effective_state_kind(instance.chart, region.superstate) != .And {
		ancestor_idx = region.superstate
	}

	for leaf_idx in instance.active_leaf_indices {
		if state_is_descendant_or_self(instance.chart, leaf_idx, ancestor_idx) &&
		   effective_state_kind(instance.chart, leaf_idx) == .Final {
			return true
		}
	}

	return false
}

is_active_index :: proc(instance: ^Instance($State, $Trigger), state_idx: State_Index) -> bool {
	for leaf_idx in instance.active_leaf_indices {
		if state_is_descendant_or_self(instance.chart, leaf_idx, state_idx) {
			return true
		}
	}
	return false
}

raise_completion_events :: proc(
	instance: ^Instance($State, $Trigger),
	runtime_ctx: ^Runtime_Context(Trigger),
	entered_start: int,
) {
	if len(instance.chart.def.done_events) == 0 {
		return
	}

	for done in instance.chart.def.done_events {
		done_idx := state_index(instance.chart, done.state)
		if done_idx == INVALID_STATE_INDEX {
			continue
		}
		if !completion_touched(instance, done_idx, entered_start) {
			continue
		}
		if state_is_complete(instance, done_idx) {
			enqueue_internal_event(runtime_ctx, Event(Trigger){id = done.trigger})
		}
	}
}

completion_touched :: proc(instance: ^Instance($State, $Trigger), state_idx: State_Index, entered_start: int) -> bool {
	for i in entered_start ..< len(instance.entered_scratch) {
		entered_idx := state_index(instance.chart, instance.entered_scratch[i])
		if entered_idx != INVALID_STATE_INDEX &&
		   state_is_descendant_or_self(instance.chart, entered_idx, state_idx) {
			return true
		}
	}
	return false
}

schedule_after_events_for_state :: #force_inline proc(instance: ^Instance($State, $Trigger), state_idx: State_Index) {
	if len(instance.chart.def.after_events) == 0 {
		return
	}

	state := instance.chart.def.states[state_idx].id
	for after, i in instance.chart.def.after_events {
		if after.state != state {
			continue
		}
		instance.after_events[i] = Active_After(Trigger){
			active = true,
			state_index = state_idx,
			due_ms = instance.current_time_ms + after.delay_ms,
			trigger = after.trigger,
		}
	}
}

cancel_after_events_under_state :: #force_inline proc(instance: ^Instance($State, $Trigger), state_idx: State_Index) {
	if len(instance.after_events) == 0 {
		return
	}

	for &timer in instance.after_events {
		if timer.active && state_is_descendant_or_self(instance.chart, timer.state_index, state_idx) {
			timer.active = false
		}
	}
}

enqueue_due_events :: proc(
	instance: ^Instance($State, $Trigger),
	runtime_ctx: ^Runtime_Context(Trigger),
	now_ms: u64,
) {
	if len(instance.after_events) == 0 {
		return
	}

	for &timer in instance.after_events {
		if !timer.active || timer.due_ms > now_ms {
			continue
		}
		if !is_active_index(instance, timer.state_index) {
			timer.active = false
			continue
		}

		timer.active = false
		if !enqueue_internal_event(runtime_ctx, Event(Trigger){id = timer.trigger}) {
			return
		}
	}
}

enter_from_index :: proc(
	instance: ^Instance($State, $Trigger),
	target_idx: State_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
	stop_idx := INVALID_STATE_INDEX,
) {
	clear(&instance.path_scratch)

	cursor := target_idx
	for cursor != INVALID_STATE_INDEX && cursor != stop_idx {
		append(&instance.path_scratch, cursor)
		cursor = instance.chart.parent_index[cursor]
	}

	for i := len(instance.path_scratch) - 1; i >= 0; i -= 1 {
		enter_one_index(instance, instance.path_scratch[i], ctx, event, result)
	}

	cursor = target_idx
	owned_regions := instance.chart.state_owned_region_ranges[cursor]
	if owned_regions.count == 0 {
		append(&instance.active_leaf_indices, cursor)
		return
	}

	for offset in 0 ..< owned_regions.count {
		region_idx := instance.chart.state_owned_region_indices[owned_regions.start + offset]
		if region_idx == INVALID_REGION_INDEX do continue

		initial_idx := instance.chart.regions[region_idx].initial
		if initial_idx == INVALID_STATE_INDEX do continue
		enter_from_index(instance, initial_idx, ctx, event, result, stop_idx = cursor)
	}
}

enter_history_index :: proc(
	instance: ^Instance($State, $Trigger),
	history_idx: History_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
	stop_idx := INVALID_STATE_INDEX,
) {
	target_idx := resolved_history_target_index(instance, history_idx)
	enter_from_index(instance, target_idx, ctx, event, result, stop_idx = stop_idx)
}

resolved_history_target_index :: proc(instance: ^Instance($State, $Trigger), history_idx: History_Index) -> State_Index {
	history := instance.chart.histories[history_idx]
	target_idx := history.fallback

	if history.kind == .Deep &&
	   history.superstate != INVALID_STATE_INDEX &&
	   int(history.superstate) < len(instance.deep_history_indices) {
		remembered_idx := instance.deep_history_indices[history.superstate]
		if remembered_idx != INVALID_STATE_INDEX &&
		   state_is_descendant_or_self(instance.chart, remembered_idx, history.superstate) {
			target_idx = remembered_idx
		}
	} else if history.superstate != INVALID_STATE_INDEX && int(history.superstate) < len(instance.history_indices) {
		remembered_idx := instance.history_indices[history.superstate]
		if remembered_idx != INVALID_STATE_INDEX &&
		   instance.chart.parent_index[remembered_idx] == history.superstate {
			target_idx = remembered_idx
		}
	}

	return target_idx
}

enter_one_index :: proc(
	instance: ^Instance($State, $Trigger),
	idx: State_Index,
	ctx: rawptr,
	event: rawptr,
	result: ^Dispatch_Result(State),
) {
	state_def := instance.chart.def.states[idx]
	if state_def.entry != nil {
		state_def.entry(ctx, event)
	}
	append(&instance.entered_scratch, state_def.id)
	schedule_after_events_for_state(instance, idx)
}

write_configuration :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]State) {
	clear(out)
	if instance.chart == nil do return

	for leaf_idx in instance.active_leaf_indices {
		clear(&instance.path_scratch)
		cursor := leaf_idx
		for cursor != INVALID_STATE_INDEX {
			append(&instance.path_scratch, cursor)
			cursor = instance.chart.parent_index[cursor]
		}
		for i := len(instance.path_scratch) - 1; i >= 0; i -= 1 {
			append(out, instance.chart.def.states[instance.path_scratch[i]].id)
		}
	}
}

reset_dispatch_scratch :: proc(instance: ^Instance($State, $Trigger)) {
	clear(&instance.exited_scratch)
	clear(&instance.entered_scratch)
	clear(&instance.configuration_scratch)
	clear(&instance.path_scratch)
	clear(&instance.exit_index_scratch)
}

write_configuration_scratch :: proc(instance: ^Instance($State, $Trigger)) {
	write_configuration(instance, &instance.configuration_scratch)
}

finalize_dispatch_result :: proc(instance: ^Instance($State, $Trigger), result: ^Dispatch_Result(State)) {
	result.exited = instance.exited_scratch[:]
	result.entered = instance.entered_scratch[:]
	result.configuration = instance.configuration_scratch[:]
}
