package statecharts

import "core:testing"
import "core:mem"

Test_State :: enum {
	Off,
	Booting,
	Operational,
	Operational_Idle,
	Armed,
	Armed_Ready,
	Flying,
	Flying_Hover,
	Flying_Returning_Home,
	Faulted,
	Player,
	Playing,
	Playing_Music,
	Playing_Podcast,
	Playing_History,
	Player_History,
	Paused,
	Rtc_Idle,
	Rtc_Armed,
	Rtc_Done,
	Rtc_Task,
	Rtc_Complete,
	Timer_Waiting,
	Timer_Done,
	Timer_Cancelled,
}

Test_Event :: enum {
	Power_On,
	Boot_Complete,
	Arm,
	Takeoff_Complete,
	Return_Home,
	Fault_Detected,
	Hover_Self,
	Internal_Ping,
	Ignored,
	Next,
	Pause,
	Resume,
	Begin,
	Raised,
	Done,
	Timeout,
	Cancel,
}

Test_Ctx :: struct {
	can_arm: bool,
	log: [dynamic]int,
}

Log :: enum {
	Boot_Entry,
	Armed_Entry,
	Armed_Exit,
	Hover_Entry,
	Hover_Exit,
	Return_Home_Entry,
	Internal_Action,
	Hover_Self_Action,
	Rtc_Raise_Action,
}

log_action :: proc(ctx_raw: rawptr, value: Log) {
	ctx := cast(^Test_Ctx)ctx_raw
	append(&ctx.log, int(value))
}

boot_entry :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Boot_Entry)
}

armed_entry :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Armed_Entry)
}

armed_exit :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Armed_Exit)
}

hover_entry :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Hover_Entry)
}

hover_exit :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Hover_Exit)
}

return_home_entry :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Return_Home_Entry)
}

internal_action :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Internal_Action)
}

hover_self_action :: proc(ctx: rawptr, event: rawptr) {
	log_action(ctx, .Hover_Self_Action)
}

rtc_raise_action :: proc(ctx: rawptr, event: rawptr) {
	user := cast(^Test_Ctx)user_context(ctx)
	append(&user.log, int(Log.Rtc_Raise_Action))
	ok := raise(ctx, Event(Test_Event){id = .Raised})
	assert(ok)
}

rtc_raise_no_log_action :: proc(ctx: rawptr, event: rawptr) {
	ok := raise(ctx, Event(Test_Event){id = .Raised})
	assert(ok)
}

can_arm_guard :: proc(ctx_raw: rawptr, event_raw: rawptr) -> bool {
	ctx := cast(^Test_Ctx)ctx_raw
	event := cast(^Event(Test_Event))event_raw
	return ctx.can_arm && event.id == .Arm
}

test_states := [?]State_Def(Test_State){
	{id = .Off},
	{id = .Booting, entry = boot_entry},
	{id = .Operational},
	{id = .Operational_Idle},
	{id = .Armed, entry = armed_entry, exit = armed_exit},
	{id = .Armed_Ready},
	{id = .Flying},
	{id = .Flying_Hover, entry = hover_entry, exit = hover_exit},
	{id = .Flying_Returning_Home, entry = return_home_entry},
	{id = .Faulted},
}

test_substates := [?]Substate_Def(Test_State){
	{substate = .Operational_Idle, superstate = .Operational},
	{substate = .Armed, superstate = .Operational},
	{substate = .Armed_Ready, superstate = .Armed},
	{substate = .Flying, superstate = .Armed},
	{substate = .Flying_Hover, superstate = .Flying},
	{substate = .Flying_Returning_Home, superstate = .Flying},
}

test_regions := [?]Region_Def(Test_State){
	{superstate = .Operational, initial = .Operational_Idle},
	{superstate = .Armed, initial = .Armed_Ready},
	{superstate = .Flying, initial = .Flying_Hover},
}

test_transitions := [?]Transition_Def(Test_State, Test_Event){
	{source = .Off, target = .Booting, trigger = .Power_On},
	{source = .Booting, target = .Operational, trigger = .Boot_Complete},
	{source = .Operational_Idle, target = .Armed, trigger = .Arm, guard = can_arm_guard},
	{source = .Armed_Ready, target = .Flying, trigger = .Takeoff_Complete},
	{source = .Flying, target = .Flying_Returning_Home, trigger = .Return_Home},
	{source = .Flying_Hover, target = .Flying_Hover, trigger = .Hover_Self, action = hover_self_action},
	{source = .Flying_Hover, target = .Flying_Hover, trigger = .Internal_Ping, kind = .Internal, action = internal_action},
	{source = .Flying_Hover, target = .Faulted, trigger = .Fault_Detected},
	{source = .Operational, target = .Faulted, trigger = .Fault_Detected},
}

test_chart_def :: proc() -> Chart_Def(Test_State, Test_Event) {
	return Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = test_states[:],
		substates = test_substates[:],
		regions = test_regions[:],
		transitions = test_transitions[:],
	}
}

@(test)
test_compile_accepts_hierarchical_chart :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, result.ok)
	testing.expect_value(t, len(result.errors), 0)
}

@(test)
test_compile_builds_or_regions :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	testing.expect_value(t, len(chart.regions), 4)
	testing.expect_value(t, chart.regions[0].superstate, INVALID_STATE_INDEX)
	testing.expect_value(t, chart.regions[0].initial, state_index(&chart, Test_State.Off))

	operational_idx := state_index(&chart, Test_State.Operational)
	operational_idle_idx := state_index(&chart, Test_State.Operational_Idle)
	armed_idx := state_index(&chart, Test_State.Armed)
	flying_idx := state_index(&chart, Test_State.Flying)
	flying_hover_idx := state_index(&chart, Test_State.Flying_Hover)

	testing.expect_value(t, chart.regions[1].superstate, operational_idx)
	testing.expect_value(t, chart.regions[1].initial, operational_idle_idx)
	testing.expect_value(t, chart.state_region_index[armed_idx], Region_Index(1))
	testing.expect_value(t, chart.state_owned_region_index[operational_idx], Region_Index(1))

	testing.expect_value(t, chart.regions[2].superstate, armed_idx)
	testing.expect_value(t, chart.state_region_index[flying_idx], Region_Index(2))
	testing.expect_value(t, chart.state_owned_region_index[armed_idx], Region_Index(2))

	testing.expect_value(t, chart.regions[3].superstate, flying_idx)
	testing.expect_value(t, chart.state_region_index[flying_hover_idx], Region_Index(3))
	testing.expect_value(t, chart.state_owned_region_index[flying_idx], Region_Index(3))
}

@(test)
test_compile_accepts_explicit_atomic_and_or_state_kinds :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off, kind = .Atomic},
		{id = .Operational, kind = .Or},
		{id = .Operational_Idle, kind = .Atomic},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Operational_Idle, superstate = .Operational},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Operational_Idle},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, result.ok)
}

@(test)
test_compile_rejects_atomic_state_with_substates :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Operational, kind = .Atomic},
		{id = .Operational_Idle},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Operational_Idle, superstate = .Operational},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Operational_Idle},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .Atomic_State_Has_Substates))
}

@(test)
test_enter_and_state_enters_all_owned_regions :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed, kind = .Or},
		{id = .Armed_Ready},
		{id = .Flying, kind = .Or},
		{id = .Flying_Hover},
		{id = .Faulted},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Armed_Ready, superstate = .Armed},
		{substate = .Flying, superstate = .Operational},
		{substate = .Flying_Hover, superstate = .Flying},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Armed},
		{superstate = .Operational, initial = .Flying},
		{superstate = .Armed, initial = .Armed_Ready},
		{superstate = .Flying, initial = .Flying_Hover},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Armed_Ready, target = .Armed_Ready, trigger = .Internal_Ping},
		{source = .Flying_Hover, target = .Flying_Hover, trigger = .Internal_Ping},
		{source = .Operational, target = .Faulted, trigger = .Fault_Detected},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	defer destroy_dispatch_result(&dispatch_result)

	testing.expect_value(t, len(machine.active_leaf_indices), 2)
	testing.expect(t, is_active(&machine, Test_State.Operational))
	testing.expect(t, is_active(&machine, Test_State.Armed))
	testing.expect(t, is_active(&machine, Test_State.Armed_Ready))
	testing.expect(t, is_active(&machine, Test_State.Flying))
	testing.expect(t, is_active(&machine, Test_State.Flying_Hover))

	destroy_dispatch_result(&dispatch_result)
	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Internal_Ping})

	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect_value(t, len(machine.active_leaf_indices), 2)
	testing.expect(t, is_active(&machine, Test_State.Armed_Ready))
	testing.expect(t, is_active(&machine, Test_State.Flying_Hover))
	testing.expect_value(t, len(dispatch_result.exited), 2)
	testing.expect_value(t, len(dispatch_result.entered), 2)

	trace := make([dynamic]Transition_Step(Test_State))
	defer delete(trace)
	destroy_dispatch_result(&dispatch_result)
	dispatch_result = dispatch_with_trace(&machine, Event(Test_Event){id = .Fault_Detected}, &trace)

	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect_value(t, len(machine.active_leaf_indices), 1)
	testing.expect_value(t, len(trace), 1)
	testing.expect_value(t, trace[0].source, Test_State.Operational)
	testing.expect_value(t, trace[0].target, Test_State.Faulted)
	testing.expect(t, is_active(&machine, Test_State.Faulted))
	testing.expect(t, !is_active(&machine, Test_State.Operational))
	testing.expect(t, !is_active(&machine, Test_State.Armed_Ready))
	testing.expect(t, !is_active(&machine, Test_State.Flying_Hover))
	testing.expect_value(t, dispatch_result.exited[len(dispatch_result.exited) - 1], Test_State.Operational)
}

@(test)
test_compile_rejects_and_state_missing_region_for_direct_child :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed},
		{id = .Flying},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Flying, superstate = .Operational},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Armed},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .And_State_Missing_Region))
}

@(test)
test_compile_rejects_duplicate_and_region_initial :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed},
		{id = .Flying},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Flying, superstate = .Operational},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Armed},
		{superstate = .Operational, initial = .Armed},
		{superstate = .Operational, initial = .Flying},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .Duplicate_Initial))
}

@(test)
test_named_and_regions_report_active_leaf :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed, kind = .Or},
		{id = .Armed_Ready},
		{id = .Flying, kind = .Or},
		{id = .Flying_Hover},
		{id = .Flying_Returning_Home},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Armed_Ready, superstate = .Armed},
		{substate = .Flying, superstate = .Operational},
		{substate = .Flying_Hover, superstate = .Flying},
		{substate = .Flying_Returning_Home, superstate = .Flying},
	}
	regions := [?]Region_Def(Test_State){
		{name = "arming", superstate = .Operational, initial = .Armed},
		{name = "flight", superstate = .Operational, initial = .Flying},
		{superstate = .Armed, initial = .Armed_Ready},
		{superstate = .Flying, initial = .Flying_Hover},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Flying_Hover, target = .Flying_Returning_Home, trigger = .Return_Home},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)

	leaf, ok := active_leaf_in_region(&machine, Test_State.Operational, "flight")
	testing.expect(t, ok)
	testing.expect_value(t, leaf, Test_State.Flying_Hover)

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Return_Home})
	defer destroy_dispatch_result(&dispatch_result)

	leaf, ok = active_leaf_in_region(&machine, Test_State.Operational, "flight")
	testing.expect(t, ok)
	testing.expect_value(t, leaf, Test_State.Flying_Returning_Home)
}

@(test)
test_compile_rejects_duplicate_named_regions_for_same_superstate :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed},
		{id = .Flying},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Flying, superstate = .Operational},
	}
	regions := [?]Region_Def(Test_State){
		{name = "control", superstate = .Operational, initial = .Armed},
		{name = "control", superstate = .Operational, initial = .Flying},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .Duplicate_Region_Name))
}

@(test)
test_shallow_history_resumes_last_direct_child :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Player, kind = .Or},
		{id = .Playing, kind = .Or},
		{id = .Playing_Music},
		{id = .Playing_Podcast},
		{id = .Paused},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Playing, superstate = .Player},
		{substate = .Paused, superstate = .Player},
		{substate = .Playing_Music, superstate = .Playing},
		{substate = .Playing_Podcast, superstate = .Playing},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Player, initial = .Playing},
		{superstate = .Playing, initial = .Playing_Music},
	}
	histories := [?]History_Def(Test_State){
		{id = .Playing_History, superstate = .Playing, fallback = .Playing_Music},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Playing_Music, target = .Playing_Podcast, trigger = .Next},
		{source = .Playing, target = .Paused, trigger = .Pause},
		{source = .Paused, target = .Playing_History, trigger = .Resume},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Player,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		histories = histories[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)
	testing.expect(t, is_active(&machine, Test_State.Playing_Music))

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Next})
	destroy_dispatch_result(&dispatch_result)
	testing.expect(t, is_active(&machine, Test_State.Playing_Podcast))

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Pause})
	destroy_dispatch_result(&dispatch_result)
	testing.expect(t, is_active(&machine, Test_State.Paused))

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Resume})
	defer destroy_dispatch_result(&dispatch_result)
	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Playing_Podcast))
	testing.expect(t, !is_active(&machine, Test_State.Playing_Music))
}

@(test)
test_shallow_history_uses_fallback_when_empty :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Player, kind = .Or},
		{id = .Playing, kind = .Or},
		{id = .Playing_Music},
		{id = .Playing_Podcast},
		{id = .Paused},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Playing, superstate = .Player},
		{substate = .Paused, superstate = .Player},
		{substate = .Playing_Music, superstate = .Playing},
		{substate = .Playing_Podcast, superstate = .Playing},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Player, initial = .Paused},
		{superstate = .Playing, initial = .Playing_Podcast},
	}
	histories := [?]History_Def(Test_State){
		{id = .Playing_History, superstate = .Playing, fallback = .Playing_Music},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Paused, target = .Playing_History, trigger = .Resume},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Player,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		histories = histories[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)
	testing.expect(t, is_active(&machine, Test_State.Paused))

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Resume})
	defer destroy_dispatch_result(&dispatch_result)
	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Playing_Music))
	testing.expect(t, !is_active(&machine, Test_State.Playing_Podcast))
}

@(test)
test_deep_history_resumes_nested_leaf_in_or_state :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Player, kind = .Or},
		{id = .Playing, kind = .Or},
		{id = .Playing_Music},
		{id = .Playing_Podcast},
		{id = .Paused},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Playing, superstate = .Player},
		{substate = .Paused, superstate = .Player},
		{substate = .Playing_Music, superstate = .Playing},
		{substate = .Playing_Podcast, superstate = .Playing},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Player, initial = .Playing},
		{superstate = .Playing, initial = .Playing_Music},
	}
	histories := [?]History_Def(Test_State){
		{id = .Player_History, superstate = .Player, fallback = .Playing_Music, kind = .Deep},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Playing_Music, target = .Playing_Podcast, trigger = .Next},
		{source = .Playing, target = .Paused, trigger = .Pause},
		{source = .Paused, target = .Player_History, trigger = .Resume},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Player,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		histories = histories[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)
	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Next})
	destroy_dispatch_result(&dispatch_result)
	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Pause})
	destroy_dispatch_result(&dispatch_result)
	testing.expect(t, is_active(&machine, Test_State.Paused))

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Resume})
	defer destroy_dispatch_result(&dispatch_result)
	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Playing_Podcast))
}

@(test)
test_run_to_completion_processes_raised_internal_event :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Rtc_Idle},
		{id = .Rtc_Armed},
		{id = .Rtc_Done},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Rtc_Idle, target = .Rtc_Armed, trigger = .Begin, action = rtc_raise_action},
		{source = .Rtc_Armed, target = .Rtc_Done, trigger = .Raised},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Rtc_Idle,
		states = states[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	ctx := Test_Ctx{log = make([dynamic]int)}
	defer delete(ctx.log)

	dispatch_result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&dispatch_result)

	dispatch_result = dispatch_run_to_completion(&machine, Event(Test_Event){id = .Begin}, &ctx)
	defer destroy_dispatch_result(&dispatch_result)

	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Rtc_Done))
	testing.expect_value(t, len(ctx.log), 1)
	testing.expect_value(t, ctx.log[0], int(Log.Rtc_Raise_Action))
	testing.expect_value(t, len(dispatch_result.exited), 2)
	testing.expect_value(t, len(dispatch_result.entered), 2)
}

@(test)
test_run_to_completion_does_not_allocate_after_init :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Rtc_Idle},
		{id = .Rtc_Armed},
		{id = .Rtc_Done},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Rtc_Idle, target = .Rtc_Armed, trigger = .Begin, action = rtc_raise_no_log_action},
		{source = .Rtc_Armed, target = .Rtc_Done, trigger = .Raised},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Rtc_Idle,
		states = states[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine)
	destroy_dispatch_result(&result)

	old_allocator := context.allocator
	context.allocator = mem.panic_allocator()
	result = dispatch_run_to_completion(&machine, Event(Test_Event){id = .Begin})
	context.allocator = old_allocator
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Rtc_Done))
}

@(test)
test_final_state_completion_raises_done_event_in_run_to_completion :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Rtc_Task, kind = .Or},
		{id = .Rtc_Idle},
		{id = .Rtc_Done, kind = .Final},
		{id = .Rtc_Complete},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Rtc_Idle, superstate = .Rtc_Task},
		{substate = .Rtc_Done, superstate = .Rtc_Task},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Rtc_Task, initial = .Rtc_Idle},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Rtc_Idle, target = .Rtc_Done, trigger = .Begin},
		{source = .Rtc_Task, target = .Rtc_Complete, trigger = .Done},
	}
	done_events := [?]Done_Def(Test_State, Test_Event){
		{state = .Rtc_Task, trigger = .Done},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Rtc_Task,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
		done_events = done_events[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine)
	destroy_dispatch_result(&result)
	testing.expect(t, !is_complete(&machine, Test_State.Rtc_Task))

	result = dispatch_run_to_completion(&machine, Event(Test_Event){id = .Begin})
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Rtc_Complete))
	testing.expect(t, !is_active(&machine, Test_State.Rtc_Task))
}

@(test)
test_compile_rejects_final_state_with_substates :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Rtc_Task, kind = .Final},
		{id = .Rtc_Idle},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Rtc_Idle, superstate = .Rtc_Task},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Rtc_Task, initial = .Rtc_Idle},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Rtc_Task,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .Final_State_Has_Substates))
}

@(test)
test_after_event_dispatches_when_due :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Timer_Waiting},
		{id = .Timer_Done},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Timer_Waiting, target = .Timer_Done, trigger = .Timeout},
	}
	after_events := [?]After_Def(Test_State, Test_Event){
		{state = .Timer_Waiting, delay_ms = 100, trigger = .Timeout},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Timer_Waiting,
		states = states[:],
		transitions = transitions[:],
		after_events = after_events[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial_at(&machine, 1_000)
	destroy_dispatch_result(&result)

	result = dispatch_due_events(&machine, 1_099)
	destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Timer_Waiting))

	result = dispatch_due_events(&machine, 1_100)
	defer destroy_dispatch_result(&result)
	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Timer_Done))
}

@(test)
test_after_event_is_cancelled_when_state_exits :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Timer_Waiting},
		{id = .Timer_Done},
		{id = .Timer_Cancelled},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Timer_Waiting, target = .Timer_Done, trigger = .Timeout},
		{source = .Timer_Waiting, target = .Timer_Cancelled, trigger = .Cancel},
	}
	after_events := [?]After_Def(Test_State, Test_Event){
		{state = .Timer_Waiting, delay_ms = 100, trigger = .Timeout},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Timer_Waiting,
		states = states[:],
		transitions = transitions[:],
		after_events = after_events[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial_at(&machine, 1_000)
	destroy_dispatch_result(&result)
	result = dispatch_at(&machine, Event(Test_Event){id = .Cancel}, 1_050)
	destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Timer_Cancelled))

	result = dispatch_due_events(&machine, 1_100)
	defer destroy_dispatch_result(&result)
	testing.expect_value(t, result.status, Dispatch_Status.Ignored)
	testing.expect(t, is_active(&machine, Test_State.Timer_Cancelled))
}

@(test)
test_due_event_dispatch_does_not_allocate_after_init :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Timer_Waiting},
		{id = .Timer_Done},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Timer_Waiting, target = .Timer_Done, trigger = .Timeout},
	}
	after_events := [?]After_Def(Test_State, Test_Event){
		{state = .Timer_Waiting, delay_ms = 100, trigger = .Timeout},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Timer_Waiting,
		states = states[:],
		transitions = transitions[:],
		after_events = after_events[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial_at(&machine, 1_000)
	destroy_dispatch_result(&result)

	old_allocator := context.allocator
	context.allocator = mem.panic_allocator()
	result = dispatch_due_events(&machine, 1_100)
	context.allocator = old_allocator
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Timer_Done))
}

@(test)
test_dispatch_with_trace_reports_multi_transition_macrostep :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed, kind = .Or},
		{id = .Armed_Ready},
		{id = .Flying, kind = .Or},
		{id = .Flying_Hover},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Armed_Ready, superstate = .Armed},
		{substate = .Flying, superstate = .Operational},
		{substate = .Flying_Hover, superstate = .Flying},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Armed},
		{superstate = .Operational, initial = .Flying},
		{superstate = .Armed, initial = .Armed_Ready},
		{superstate = .Flying, initial = .Flying_Hover},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Armed_Ready, target = .Armed_Ready, trigger = .Internal_Ping},
		{source = .Flying_Hover, target = .Flying_Hover, trigger = .Internal_Ping},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)

	trace := make([dynamic]Transition_Step(Test_State))
	defer delete(trace)
	dispatch_result = dispatch_with_trace(&machine, Event(Test_Event){id = .Internal_Ping}, &trace)
	defer destroy_dispatch_result(&dispatch_result)

	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect_value(t, len(trace), 2)
	testing.expect_value(t, trace[0].source, Test_State.Armed_Ready)
	testing.expect_value(t, trace[0].target, Test_State.Armed_Ready)
	testing.expect_value(t, trace[1].source, Test_State.Flying_Hover)
	testing.expect_value(t, trace[1].target, Test_State.Flying_Hover)
	testing.expect_value(t, len(machine.active_leaf_indices), 2)
}

@(test)
test_branch_transition_exiting_and_state_clears_sibling_regions :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed, kind = .Or},
		{id = .Armed_Ready},
		{id = .Flying, kind = .Or},
		{id = .Flying_Hover},
		{id = .Faulted},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Armed, superstate = .Operational},
		{substate = .Armed_Ready, superstate = .Armed},
		{substate = .Flying, superstate = .Operational},
		{substate = .Flying_Hover, superstate = .Flying},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Armed},
		{superstate = .Operational, initial = .Flying},
		{superstate = .Armed, initial = .Armed_Ready},
		{superstate = .Flying, initial = .Flying_Hover},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Armed, target = .Faulted, trigger = .Fault_Detected},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Fault_Detected})
	defer destroy_dispatch_result(&dispatch_result)

	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect_value(t, len(machine.active_leaf_indices), 1)
	testing.expect(t, is_active(&machine, Test_State.Faulted))
	testing.expect(t, !is_active(&machine, Test_State.Operational))
	testing.expect(t, !is_active(&machine, Test_State.Armed_Ready))
	testing.expect(t, !is_active(&machine, Test_State.Flying_Hover))
	testing.expect_value(t, dispatch_result.exited[len(dispatch_result.exited) - 1], Test_State.Operational)
}

@(test)
test_descendant_transition_preempts_parent_conflict_regardless_of_leaf_order :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Operational, kind = .And},
		{id = .Armed, kind = .Or},
		{id = .Armed_Ready},
		{id = .Flying, kind = .Or},
		{id = .Flying_Hover},
		{id = .Faulted},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Flying, superstate = .Operational},
		{substate = .Flying_Hover, superstate = .Flying},
		{substate = .Armed, superstate = .Operational},
		{substate = .Armed_Ready, superstate = .Armed},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Flying},
		{superstate = .Operational, initial = .Armed},
		{superstate = .Flying, initial = .Flying_Hover},
		{superstate = .Armed, initial = .Armed_Ready},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Operational, target = .Faulted, trigger = .Fault_Detected},
		{source = .Armed_Ready, target = .Armed_Ready, trigger = .Fault_Detected},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Operational,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)
	testing.expect(t, result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	dispatch_result := enter_initial(&machine)
	destroy_dispatch_result(&dispatch_result)

	testing.expect_value(t, machine.active_leaf_indices[0], state_index(&chart, Test_State.Flying_Hover))
	testing.expect_value(t, machine.active_leaf_indices[1], state_index(&chart, Test_State.Armed_Ready))

	dispatch_result = dispatch(&machine, Event(Test_Event){id = .Fault_Detected})
	defer destroy_dispatch_result(&dispatch_result)

	testing.expect_value(t, dispatch_result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Operational))
	testing.expect(t, is_active(&machine, Test_State.Flying_Hover))
	testing.expect(t, is_active(&machine, Test_State.Armed_Ready))
	testing.expect(t, !is_active(&machine, Test_State.Faulted))
	testing.expect_value(t, len(machine.active_leaf_indices), 2)
	testing.expect_value(t, dispatch_result.source, Test_State.Armed_Ready)
}

@(test)
test_enter_initial_and_dispatch_through_superstates :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Off))

	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Booting))
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Boot_Complete}, &ctx)
	testing.expect(t, is_active(&machine, Test_State.Operational))
	testing.expect(t, is_active(&machine, Test_State.Operational_Idle))
	testing.expect_value(t, result.entered[0], Test_State.Operational)
	testing.expect_value(t, result.entered[1], Test_State.Operational_Idle)
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Arm}, &ctx)
	testing.expect(t, is_active(&machine, Test_State.Armed))
	testing.expect(t, is_active(&machine, Test_State.Armed_Ready))
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Takeoff_Complete}, &ctx)
	testing.expect(t, is_active(&machine, Test_State.Armed))
	testing.expect(t, is_active(&machine, Test_State.Flying))
	testing.expect(t, is_active(&machine, Test_State.Flying_Hover))
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Return_Home}, &ctx)
	testing.expect_value(t, result.exited[0], Test_State.Flying_Hover)
	testing.expect_value(t, result.entered[0], Test_State.Flying_Returning_Home)
	testing.expect(t, is_active(&machine, Test_State.Flying_Returning_Home))
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Fault_Detected}, &ctx)
	testing.expect(t, is_active(&machine, Test_State.Faulted))
	testing.expect_value(t, result.exited[0], Test_State.Flying_Returning_Home)
	testing.expect_value(t, result.exited[len(result.exited) - 1], Test_State.Operational)
	destroy_dispatch_result(&result)

	testing.expect_value(t, ctx.log[0], int(Log.Boot_Entry))
	testing.expect_value(t, ctx.log[1], int(Log.Armed_Entry))
	testing.expect_value(t, ctx.log[2], int(Log.Hover_Entry))
	testing.expect_value(t, ctx.log[3], int(Log.Hover_Exit))
	testing.expect_value(t, ctx.log[4], int(Log.Return_Home_Entry))
	testing.expect_value(t, ctx.log[5], int(Log.Armed_Exit))
}

@(test)
test_blocked_guard_leaves_configuration_unchanged :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = false, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Boot_Complete}, &ctx)
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Arm}, &ctx)
	defer destroy_dispatch_result(&result)
	testing.expect_value(t, result.status, Dispatch_Status.Blocked_By_Guard)
	testing.expect(t, is_active(&machine, Test_State.Operational_Idle))
	testing.expect(t, !is_active(&machine, Test_State.Armed))
}

@(test)
test_child_transition_has_priority_over_superstate_transition :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Boot_Complete}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Arm}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Takeoff_Complete}, &ctx)
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Fault_Detected}, &ctx)
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.source, Test_State.Flying_Hover)
	testing.expect_value(t, result.target, Test_State.Faulted)
	testing.expect(t, is_active(&machine, Test_State.Faulted))
}

@(test)
test_internal_transition_runs_action_without_exit_or_entry :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Boot_Complete}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Arm}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Takeoff_Complete}, &ctx)
	destroy_dispatch_result(&result)

	log_len_before := len(ctx.log)
	result = dispatch(&machine, Event(Test_Event){id = .Internal_Ping}, &ctx)
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect_value(t, len(result.exited), 0)
	testing.expect_value(t, len(result.entered), 0)
	testing.expect(t, is_active(&machine, Test_State.Flying_Hover))
	testing.expect_value(t, len(ctx.log), log_len_before + 1)
	testing.expect_value(t, ctx.log[len(ctx.log) - 1], int(Log.Internal_Action))
}

@(test)
test_external_self_transition_exits_actions_and_reenters :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Boot_Complete}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Arm}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Takeoff_Complete}, &ctx)
	destroy_dispatch_result(&result)

	log_len_before := len(ctx.log)
	result = dispatch(&machine, Event(Test_Event){id = .Hover_Self}, &ctx)
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.exited[0], Test_State.Flying_Hover)
	testing.expect_value(t, result.entered[0], Test_State.Flying_Hover)
	testing.expect(t, is_active(&machine, Test_State.Flying_Hover))
	testing.expect_value(t, ctx.log[log_len_before], int(Log.Hover_Exit))
	testing.expect_value(t, ctx.log[log_len_before + 1], int(Log.Hover_Self_Action))
	testing.expect_value(t, ctx.log[log_len_before + 2], int(Log.Hover_Entry))
}

@(test)
test_configuration_reports_superstates_then_leaf :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Boot_Complete}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Arm}, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Takeoff_Complete}, &ctx)
	destroy_dispatch_result(&result)

	config := make([dynamic]Test_State)
	defer delete(config)
	configuration(&machine, &config)

	testing.expect_value(t, len(config), 4)
	testing.expect_value(t, config[0], Test_State.Operational)
	testing.expect_value(t, config[1], Test_State.Armed)
	testing.expect_value(t, config[2], Test_State.Flying)
	testing.expect_value(t, config[3], Test_State.Flying_Hover)
}

@(test)
test_ignored_event_leaves_configuration_unchanged :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)

	result = dispatch(&machine, Event(Test_Event){id = .Ignored}, &ctx)
	defer destroy_dispatch_result(&result)
	testing.expect_value(t, result.status, Dispatch_Status.Ignored)
	testing.expect(t, is_active(&machine, Test_State.Off))
}

@(test)
test_dispatch_scans_all_active_leaves :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Booting},
		{id = .Faulted},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Booting, target = .Faulted, trigger = .Fault_Detected},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine)
	destroy_dispatch_result(&result)
	append(&machine.active_leaf_indices, state_index(&chart, Test_State.Booting))

	result = dispatch(&machine, Event(Test_Event){id = .Fault_Detected})
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Off))
	testing.expect(t, is_active(&machine, Test_State.Faulted))
	testing.expect(t, !is_active(&machine, Test_State.Booting))
	testing.expect_value(t, len(machine.active_leaf_indices), 2)
}

@(test)
test_compile_rejects_missing_initial_for_superstate :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Operational},
		{id = .Operational_Idle},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Operational_Idle, superstate = .Operational},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		substates = substates[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect_value(t, result.errors[0].kind, Validation_Error_Kind.Superstate_Missing_Initial)
}

@(test)
test_compile_accepts_legacy_initial_defs :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Operational},
		{id = .Operational_Idle},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Operational_Idle, superstate = .Operational},
	}
	initials := [?]Initial_Def(Test_State){
		{superstate = .Operational, initial = .Operational_Idle},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		substates = substates[:],
		initials = initials[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, result.ok)
	testing.expect_value(t, len(chart.regions), 2)
}

@(test)
test_compile_rejects_ancestor_cycle :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Operational},
		{id = .Armed},
		{id = .Flying},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Operational, superstate = .Armed},
		{substate = .Armed, superstate = .Flying},
		{substate = .Flying, superstate = .Armed},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		substates = substates[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	found_cycle := false
	for err in result.errors {
		if err.kind == .Superstate_Cycle {
			found_cycle = true
			break
		}
	}
	testing.expect(t, found_cycle)
}

@(test)
test_compile_reports_duplicate_state_substate_initial_and_missing_transition_endpoints :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Off},
		{id = .Operational},
		{id = .Operational_Idle},
		{id = .Armed},
		{id = .Faulted},
	}
	substates := [?]Substate_Def(Test_State){
		{substate = .Operational_Idle, superstate = .Operational},
		{substate = .Operational_Idle, superstate = .Armed},
	}
	regions := [?]Region_Def(Test_State){
		{superstate = .Operational, initial = .Operational_Idle},
		{superstate = .Operational, initial = .Operational_Idle},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Flying, target = .Faulted, trigger = .Fault_Detected},
		{source = .Off, target = .Flying, trigger = .Power_On},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		substates = substates[:],
		regions = regions[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .Duplicate_State))
	testing.expect(t, has_validation_error(result.errors[:], .Duplicate_Substate))
	testing.expect(t, has_validation_error(result.errors[:], .Duplicate_Initial))
	testing.expect(t, has_validation_error(result.errors[:], .Missing_Transition_Source))
	testing.expect(t, has_validation_error(result.errors[:], .Missing_Transition_Target))
}

@(test)
test_compile_rejects_ambiguous_transitions_by_default :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Booting},
		{id = .Faulted},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Off, target = .Booting, trigger = .Power_On},
		{source = .Off, target = .Faulted, trigger = .Power_On},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def)
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, !result.ok)
	testing.expect(t, has_validation_error(result.errors[:], .Ambiguous_Transition))
}

@(test)
test_compile_allows_ambiguous_transitions_when_requested :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Booting},
		{id = .Faulted},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Off, target = .Booting, trigger = .Power_On},
		{source = .Off, target = .Faulted, trigger = .Power_On},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	result := compile(&chart, chart_def, Compile_Options{allow_ambiguous_transitions = true})
	defer destroy_compile_result(&result)
	defer destroy_chart(&chart)

	testing.expect(t, result.ok)
}

@(test)
test_reinit_and_reenter_initial_reset_active_leaf :: proc(t: ^testing.T) {
	chart_def := test_chart_def()
	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	ctx := Test_Ctx{can_arm = true, log = make([dynamic]int)}
	defer delete(ctx.log)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	result = dispatch(&machine, Event(Test_Event){id = .Power_On}, &ctx)
	destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Booting))

	result = enter_initial(&machine, &ctx)
	destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Off))
	testing.expect_value(t, len(machine.active_leaf_indices), 1)

	testing.expect(t, init(&machine, &chart))
	result = enter_initial(&machine, &ctx)
	defer destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Off))
	testing.expect_value(t, len(machine.active_leaf_indices), 1)
}

@(test)
test_dispatch_does_not_allocate_after_init :: proc(t: ^testing.T) {
	states := [?]State_Def(Test_State){
		{id = .Off},
		{id = .Booting},
	}
	transitions := [?]Transition_Def(Test_State, Test_Event){
		{source = .Off, target = .Booting, trigger = .Power_On},
	}
	chart_def := Chart_Def(Test_State, Test_Event){
		initial = .Off,
		states = states[:],
		transitions = transitions[:],
	}

	chart: Chart(Test_State, Test_Event)
	compile_result := compile(&chart, chart_def)
	defer destroy_compile_result(&compile_result)
	defer destroy_chart(&chart)
	testing.expect(t, compile_result.ok)

	machine: Instance(Test_State, Test_Event)
	testing.expect(t, init(&machine, &chart))
	defer destroy_instance(&machine)

	result := enter_initial(&machine)
	destroy_dispatch_result(&result)

	old_allocator := context.allocator
	context.allocator = mem.panic_allocator()
	result = dispatch(&machine, Event(Test_Event){id = .Power_On})
	context.allocator = old_allocator
	defer destroy_dispatch_result(&result)

	testing.expect_value(t, result.status, Dispatch_Status.Transitioned)
	testing.expect(t, is_active(&machine, Test_State.Booting))
}

has_validation_error :: proc(errors: []Validation_Error, kind: Validation_Error_Kind) -> bool {
	for err in errors {
		if err.kind == kind do return true
	}
	return false
}
