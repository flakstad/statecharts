package statecharts

import "core:testing"

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

test_initials := [?]Initial_Def(Test_State){
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
		initials = test_initials[:],
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
	initials := [?]Initial_Def(Test_State){
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
		initials = initials[:],
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
	testing.expect_value(t, len(machine.active_leaves), 1)

	testing.expect(t, init(&machine, &chart))
	result = enter_initial(&machine, &ctx)
	defer destroy_dispatch_result(&result)
	testing.expect(t, is_active(&machine, Test_State.Off))
	testing.expect_value(t, len(machine.active_leaves), 1)
}

has_validation_error :: proc(errors: []Validation_Error, kind: Validation_Error_Kind) -> bool {
	for err in errors {
		if err.kind == kind do return true
	}
	return false
}
