package statecharts

init :: proc(
  instance: ^Instance($State, $Trigger),
  chart: ^Chart(State, Trigger),
  options := Init_Options{},
) -> bool {
  destroy_instance(instance)
  instance.chart = chart
  if chart == nil do return false
  instance.conflict_first = INVALID_TRANSITION_INDEX
  instance.conflict_second = INVALID_TRANSITION_INDEX
  instance.preempted_transition = INVALID_TRANSITION_INDEX
  instance.preempted_by_transition = INVALID_TRANSITION_INDEX

  state_count := len(chart.def.states)
  active_leaf_capacity := max_capacity(state_count, options.active_leaf_capacity)
  trace_capacity := max_capacity(state_count, options.trace_capacity)
  configuration_capacity := max_capacity(state_count, options.configuration_capacity)
  path_capacity := max_capacity(state_count, options.path_capacity)
  transition_scratch_capacity := max_capacity(state_count, options.transition_scratch_capacity)

  instance.active_leaf_indices = make([dynamic]State_Index, 0, active_leaf_capacity)
  instance.history_indices = make([dynamic]State_Index, 0, state_count)
  instance.deep_history_indices = make([dynamic]State_Index, 0, state_count)
  instance.deep_history_region_indices = make([dynamic]State_Index, 0, len(chart.regions))
  internal_event_capacity := len(chart.def.transitions) + len(chart.def.always_transitions)
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
  if internal_event_capacity < options.internal_event_capacity {
    internal_event_capacity = options.internal_event_capacity
  }
  instance.internal_event_queue = make([dynamic]Event(Trigger), 0, internal_event_capacity)
  instance.after_events = make([dynamic]Active_After(Trigger), 0, len(chart.def.after_events))
  instance.exited_scratch = make([dynamic]State, 0, trace_capacity)
  instance.entered_scratch = make([dynamic]State, 0, trace_capacity)
  instance.configuration_scratch = make([dynamic]State, 0, configuration_capacity)
  instance.path_scratch = make([dynamic]State_Index, 0, path_capacity)
  instance.exit_index_scratch = make([dynamic]State_Index, 0, trace_capacity)
  instance.candidate_transition_scratch = make([dynamic]Enabled_Transition, 0, transition_scratch_capacity)
  instance.enabled_transition_scratch = make([dynamic]Enabled_Transition, 0, transition_scratch_capacity)
  instance.preemption_scratch = make([dynamic]Preemption_Record, 0, transition_scratch_capacity)
  for _ in 0 ..< state_count {
    append(&instance.history_indices, INVALID_STATE_INDEX)
    append(&instance.deep_history_indices, INVALID_STATE_INDEX)
  }
  for _ in chart.regions {
    append(&instance.deep_history_region_indices, INVALID_STATE_INDEX)
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

enter_initial_run_to_completion :: proc(
  instance: ^Instance($State, $Trigger),
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
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

  clear(&instance.internal_event_queue)
  overflow := false
  runtime_ctx := Runtime_Context(Trigger){
    user = ctx,
    internal_events = &instance.internal_event_queue,
    overflow = &overflow,
  }

  entered_start := len(instance.entered_scratch)
  enter_from_index(instance, initial_idx, &runtime_ctx, nil, &result)
  raise_completion_events(instance, &runtime_ctx, entered_start)
  if overflow {
    result.status = .Error
    finalize_dispatch_result(instance, &result)
    return result
  }

  transitioned := true
  blocked_by_guard := false
  if !rtc_stabilize(instance, &runtime_ctx, &result, rtc_max_steps(instance, options), &overflow, &transitioned, &blocked_by_guard) {
    return result
  }
  rtc_finalize(instance, &result, transitioned, blocked_by_guard)
  return result
}

enter_initial_run_to_completion_with_trace :: proc(
  instance: ^Instance($State, $Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
  clear(transitions)
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

  clear(&instance.internal_event_queue)
  overflow := false
  runtime_ctx := Runtime_Context(Trigger){
    user = ctx,
    internal_events = &instance.internal_event_queue,
    overflow = &overflow,
  }

  entered_start := len(instance.entered_scratch)
  enter_from_index(instance, initial_idx, &runtime_ctx, nil, &result)
  raise_completion_events(instance, &runtime_ctx, entered_start)
  if overflow {
    result.status = .Error
    finalize_dispatch_result(instance, &result)
    return result
  }

  transitioned := true
  blocked_by_guard := false
  if !rtc_stabilize_with_trace(instance, &runtime_ctx, transitions, &result, rtc_max_steps(instance, options), &overflow, &transitioned, &blocked_by_guard) {
    return result
  }
  rtc_finalize(instance, &result, transitioned, blocked_by_guard)
  return result
}

enter_initial_run_to_completion_at :: proc(
  instance: ^Instance($State, $Trigger),
  now_ms: u64,
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
  instance.current_time_ms = now_ms
  return enter_initial_run_to_completion(instance, ctx, options)
}

enter_initial_run_to_completion_with_trace_at :: proc(
  instance: ^Instance($State, $Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  now_ms: u64,
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
  instance.current_time_ms = now_ms
  return enter_initial_run_to_completion_with_trace(instance, transitions, ctx, options)
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

  transitioned := false
  blocked_by_guard := false

  event_value := event
  entered_start := len(instance.entered_scratch)
  dispatch_event_step(instance, &event_value, &runtime_ctx, &result)
  if result.status == .Transitioned {
    raise_completion_events(instance, &runtime_ctx, entered_start)
  }
  if result.status == .Conflict {
    finalize_dispatch_result(instance, &result)
    return result
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

  if !rtc_stabilize(instance, &runtime_ctx, &result, rtc_max_steps(instance, options), &overflow, &transitioned, &blocked_by_guard) {
    return result
  }
  rtc_finalize(instance, &result, transitioned, blocked_by_guard)
  return result
}

dispatch_run_to_completion_with_trace :: proc(
  instance: ^Instance($State, $Trigger),
  event: Event(Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
  clear(transitions)
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

  transitioned := false
  blocked_by_guard := false

  event_value := event
  entered_start := len(instance.entered_scratch)
  dispatch_event_step_with_trace(instance, &event_value, transitions, &runtime_ctx, &result)
  if result.status == .Transitioned {
    raise_completion_events(instance, &runtime_ctx, entered_start)
  }
  if result.status == .Conflict {
    finalize_dispatch_result(instance, &result)
    return result
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

  if !rtc_stabilize_with_trace(instance, &runtime_ctx, transitions, &result, rtc_max_steps(instance, options), &overflow, &transitioned, &blocked_by_guard) {
    return result
  }
  rtc_finalize(instance, &result, transitioned, blocked_by_guard)
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

dispatch_run_to_completion_with_trace_at :: proc(
  instance: ^Instance($State, $Trigger),
  event: Event(Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  now_ms: u64,
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
  instance.current_time_ms = now_ms
  return dispatch_run_to_completion_with_trace(instance, event, transitions, ctx, options)
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
  if len(instance.internal_event_queue) == 0 && len(instance.chart.def.always_transitions) == 0 {
    result.status = .Ignored
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, &result)
    return result
  }

  transitioned := false
  blocked_by_guard := false
  if !rtc_stabilize_due(instance, &runtime_ctx, &result, rtc_max_steps(instance, options), now_ms, &overflow, &transitioned, &blocked_by_guard) {
    return result
  }
  rtc_finalize(instance, &result, transitioned, blocked_by_guard)
  return result
}

dispatch_due_events_with_trace :: proc(
  instance: ^Instance($State, $Trigger),
  now_ms: u64,
  transitions: ^[dynamic]Transition_Step(State),
  ctx: rawptr = nil,
  options := Run_To_Completion_Options{},
) -> Dispatch_Result(State) {
  clear(transitions)
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
  if len(instance.internal_event_queue) == 0 && len(instance.chart.def.always_transitions) == 0 {
    result.status = .Ignored
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, &result)
    return result
  }

  transitioned := false
  blocked_by_guard := false
  if !rtc_stabilize_due_with_trace(instance, &runtime_ctx, transitions, &result, rtc_max_steps(instance, options), now_ms, &overflow, &transitioned, &blocked_by_guard) {
    return result
  }
  rtc_finalize(instance, &result, transitioned, blocked_by_guard)
  return result
}

rtc_max_steps :: #force_inline proc(instance: ^Instance($State, $Trigger), options: Run_To_Completion_Options) -> int {
  if options.max_internal_events > 0 {
    return options.max_internal_events
  }
  return cap(instance.internal_event_queue)
}

rtc_finalize :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  result: ^Dispatch_Result(State),
  transitioned: bool,
  blocked_by_guard: bool,
) {
  clear(&instance.internal_event_queue)
  if transitioned {
    result.status = .Transitioned
  } else if blocked_by_guard {
    result.status = .Blocked_By_Guard
  } else {
    result.status = .Ignored
  }
  write_configuration_scratch(instance)
  finalize_dispatch_result(instance, result)
}

rtc_stabilize :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  runtime_ctx: ^Runtime_Context(Trigger),
  result: ^Dispatch_Result(State),
  max_steps: int,
  overflow: ^bool,
  transitioned: ^bool,
  blocked_by_guard: ^bool,
) -> bool {
  return rtc_stabilize_impl(instance, runtime_ctx, result, max_steps, 0, false, overflow, transitioned, blocked_by_guard)
}

rtc_stabilize_due :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  runtime_ctx: ^Runtime_Context(Trigger),
  result: ^Dispatch_Result(State),
  max_steps: int,
  now_ms: u64,
  overflow: ^bool,
  transitioned: ^bool,
  blocked_by_guard: ^bool,
) -> bool {
  return rtc_stabilize_impl(instance, runtime_ctx, result, max_steps, now_ms, true, overflow, transitioned, blocked_by_guard)
}

rtc_stabilize_impl :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  runtime_ctx: ^Runtime_Context(Trigger),
  result: ^Dispatch_Result(State),
  max_steps: int,
  now_ms: u64,
  include_due_events: bool,
  overflow: ^bool,
  transitioned: ^bool,
  blocked_by_guard: ^bool,
) -> bool {
  processed_steps := 0
  read_index := 0
  for {
    if read_index < len(instance.internal_event_queue) {
      if processed_steps >= max_steps {
	result.status = .Error
	finalize_dispatch_result(instance, result)
	return false
      }

      event_value := instance.internal_event_queue[read_index]
      read_index += 1
      processed_steps += 1

      entered_start := len(instance.entered_scratch)
      dispatch_event_step(instance, &event_value, runtime_ctx, result)
      if result.status == .Transitioned {
	raise_completion_events(instance, runtime_ctx, entered_start)
	if include_due_events {
	  enqueue_due_events(instance, runtime_ctx, now_ms)
	}
      }
      if result.status == .Conflict {
	finalize_dispatch_result(instance, result)
	return false
      }
      if result.status == .Error || overflow^ {
	result.status = .Error
	finalize_dispatch_result(instance, result)
	return false
      }
      if result.status == .Transitioned {
	transitioned^ = true
      } else if result.status == .Blocked_By_Guard {
	blocked_by_guard^ = true
      }
      continue
    }

    if len(instance.chart.def.always_transitions) == 0 {
      return true
    }
    if processed_steps >= max_steps {
      result.status = .Error
      finalize_dispatch_result(instance, result)
      return false
    }

    entered_start := len(instance.entered_scratch)
    dispatch_always_step(instance, runtime_ctx, result)
    if result.status == .Transitioned {
      processed_steps += 1
      raise_completion_events(instance, runtime_ctx, entered_start)
      if include_due_events {
	enqueue_due_events(instance, runtime_ctx, now_ms)
      }
      transitioned^ = true
      continue
    }
    if result.status == .Conflict {
      finalize_dispatch_result(instance, result)
      return false
    }
    if result.status == .Error || overflow^ {
      result.status = .Error
      finalize_dispatch_result(instance, result)
      return false
    }
    if result.status == .Blocked_By_Guard {
      blocked_by_guard^ = true
    }
    return true
  }
}

rtc_stabilize_with_trace :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  runtime_ctx: ^Runtime_Context(Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  result: ^Dispatch_Result(State),
  max_steps: int,
  overflow: ^bool,
  transitioned: ^bool,
  blocked_by_guard: ^bool,
) -> bool {
  return rtc_stabilize_with_trace_impl(instance, runtime_ctx, transitions, result, max_steps, 0, false, overflow, transitioned, blocked_by_guard)
}

rtc_stabilize_due_with_trace :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  runtime_ctx: ^Runtime_Context(Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  result: ^Dispatch_Result(State),
  max_steps: int,
  now_ms: u64,
  overflow: ^bool,
  transitioned: ^bool,
  blocked_by_guard: ^bool,
) -> bool {
  return rtc_stabilize_with_trace_impl(instance, runtime_ctx, transitions, result, max_steps, now_ms, true, overflow, transitioned, blocked_by_guard)
}

rtc_stabilize_with_trace_impl :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  runtime_ctx: ^Runtime_Context(Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  result: ^Dispatch_Result(State),
  max_steps: int,
  now_ms: u64,
  include_due_events: bool,
  overflow: ^bool,
  transitioned: ^bool,
  blocked_by_guard: ^bool,
) -> bool {
  processed_steps := 0
  read_index := 0
  for {
    if read_index < len(instance.internal_event_queue) {
      if processed_steps >= max_steps {
	result.status = .Error
	finalize_dispatch_result(instance, result)
	return false
      }

      event_value := instance.internal_event_queue[read_index]
      read_index += 1
      processed_steps += 1

      entered_start := len(instance.entered_scratch)
      dispatch_event_step_with_trace(instance, &event_value, transitions, runtime_ctx, result)
      if result.status == .Transitioned {
	raise_completion_events(instance, runtime_ctx, entered_start)
	if include_due_events {
	  enqueue_due_events(instance, runtime_ctx, now_ms)
	}
      }
      if result.status == .Conflict {
	finalize_dispatch_result(instance, result)
	return false
      }
      if result.status == .Error || overflow^ {
	result.status = .Error
	finalize_dispatch_result(instance, result)
	return false
      }
      if result.status == .Transitioned {
	transitioned^ = true
      } else if result.status == .Blocked_By_Guard {
	blocked_by_guard^ = true
      }
      continue
    }

    if len(instance.chart.def.always_transitions) == 0 {
      return true
    }
    if processed_steps >= max_steps {
      result.status = .Error
      finalize_dispatch_result(instance, result)
      return false
    }

    entered_start := len(instance.entered_scratch)
    dispatch_always_step_with_trace(instance, transitions, runtime_ctx, result)
    if result.status == .Transitioned {
      processed_steps += 1
      raise_completion_events(instance, runtime_ctx, entered_start)
      if include_due_events {
	enqueue_due_events(instance, runtime_ctx, now_ms)
      }
      transitioned^ = true
      continue
    }
    if result.status == .Conflict {
      finalize_dispatch_result(instance, result)
      return false
    }
    if result.status == .Error || overflow^ {
      result.status = .Error
      finalize_dispatch_result(instance, result)
      return false
    }
    if result.status == .Blocked_By_Guard {
      blocked_by_guard^ = true
    }
    return true
  }
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

dispatch_event_step_with_trace :: proc(
  instance: ^Instance($State, $Trigger),
  event: ^Event(Trigger),
  transitions: ^[dynamic]Transition_Step(State),
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
	append_transition_trace(transitions, transition)
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

  dispatch_multi_leaf_with_trace(instance, event, transitions, ctx, result)
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
  event_value := event
  dispatch_event_step_with_trace(instance, &event_value, transitions, ctx, &result)
  return result
}

dispatch_always_step :: proc(
  instance: ^Instance($State, $Trigger),
  ctx: rawptr,
  result: ^Dispatch_Result(State),
) {
  if instance.chart == nil || len(instance.active_leaf_indices) == 0 {
    result.status = .Error
    finalize_dispatch_result(instance, result)
    return
  }
  if len(instance.chart.def.always_transitions) == 0 {
    result.status = .Ignored
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, result)
    return
  }

  blocked_by_guard, conflict := collect_enabled_always_transitions(instance, ctx)
  if conflict.found {
    result.status = .Conflict
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, result)
    return
  }
  if len(instance.enabled_transition_scratch) > 0 {
    for enabled in instance.enabled_transition_scratch {
      transition_idx := Always_Index(enabled.transition_index)
      transition := instance.chart.def.always_transitions[transition_idx]
      apply_always_transition_step(instance, transition, transition_idx, enabled.leaf_index, ctx, result)
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

dispatch_always_step_with_trace :: proc(
  instance: ^Instance($State, $Trigger),
  transitions: ^[dynamic]Transition_Step(State),
  ctx: rawptr,
  result: ^Dispatch_Result(State),
) {
  if instance.chart == nil || len(instance.active_leaf_indices) == 0 {
    result.status = .Error
    finalize_dispatch_result(instance, result)
    return
  }
  if len(instance.chart.def.always_transitions) == 0 {
    result.status = .Ignored
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, result)
    return
  }

  blocked_by_guard, conflict := collect_enabled_always_transitions(instance, ctx)
  if conflict.found {
    result.status = .Conflict
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, result)
    return
  }
  if len(instance.enabled_transition_scratch) > 0 {
    for enabled in instance.enabled_transition_scratch {
      transition_idx := Always_Index(enabled.transition_index)
      transition := instance.chart.def.always_transitions[transition_idx]
      apply_always_transition_step(instance, transition, transition_idx, enabled.leaf_index, ctx, result)
      if result.status == .Error {
	finalize_dispatch_result(instance, result)
	return
      }
      append_always_transition_trace(transitions, transition)
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

dispatch_multi_leaf :: proc(
  instance: ^Instance($State, $Trigger),
  event: ^Event(Trigger),
  ctx: rawptr,
  result: ^Dispatch_Result(State),
) {
  blocked_by_guard, conflict := collect_enabled_transitions(instance, event, ctx)
  if conflict.found {
    result.status = .Conflict
    write_conflict_detail(instance, conflict)
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, result)
    return
  }
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
  blocked_by_guard, conflict := collect_enabled_transitions(instance, event, ctx)
  if conflict.found {
    result.status = .Conflict
    write_conflict_detail(instance, conflict)
    write_configuration_scratch(instance)
    finalize_dispatch_result(instance, result)
    return
  }
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

append_always_transition_trace :: proc(out: ^[dynamic]Transition_Step($State), transition: Always_Def(State)) {
  append(out, Transition_Step(State){
    source = transition.source,
    target = transition.target,
  })
}

write_conflict_detail :: proc(
  instance: ^Instance($State, $Trigger),
  conflict: Transition_Conflict,
) {
  if instance.chart == nil || !conflict.found {
    return
  }

  instance.conflict_first = conflict.first
  instance.conflict_second = conflict.second
}

last_conflict :: proc(instance: ^Instance($State, $Trigger)) -> (Transition_Step(State), Transition_Step(State), bool) {
  first_step: Transition_Step(State)
  second_step: Transition_Step(State)
  if instance.chart == nil ||
    instance.conflict_first == INVALID_TRANSITION_INDEX ||
    instance.conflict_second == INVALID_TRANSITION_INDEX {
      return first_step, second_step, false
    }

  first := instance.chart.def.transitions[instance.conflict_first]
  second := instance.chart.def.transitions[instance.conflict_second]
  first_step = Transition_Step(State){source = first.source, target = first.target}
  second_step = Transition_Step(State){source = second.source, target = second.target}
  return first_step, second_step, true
}

last_conflict_indices :: proc(instance: ^Instance($State, $Trigger)) -> (int, int, bool) {
  if instance.chart == nil ||
    instance.conflict_first == INVALID_TRANSITION_INDEX ||
    instance.conflict_second == INVALID_TRANSITION_INDEX {
      return -1, -1, false
    }
  return int(instance.conflict_first), int(instance.conflict_second), true
}

last_preemption :: proc(instance: ^Instance($State, $Trigger)) -> (Transition_Step(State), Transition_Step(State), bool) {
  preempted_step: Transition_Step(State)
  preempted_by_step: Transition_Step(State)
  if instance.chart == nil ||
    instance.preempted_transition == INVALID_TRANSITION_INDEX ||
    instance.preempted_by_transition == INVALID_TRANSITION_INDEX {
      return preempted_step, preempted_by_step, false
    }

  preempted := instance.chart.def.transitions[instance.preempted_transition]
  preempted_by := instance.chart.def.transitions[instance.preempted_by_transition]
  preempted_step = Transition_Step(State){source = preempted.source, target = preempted.target}
  preempted_by_step = Transition_Step(State){source = preempted_by.source, target = preempted_by.target}
  return preempted_step, preempted_by_step, true
}

last_preemption_indices :: proc(instance: ^Instance($State, $Trigger)) -> (int, int, bool) {
  if instance.chart == nil ||
    instance.preempted_transition == INVALID_TRANSITION_INDEX ||
    instance.preempted_by_transition == INVALID_TRANSITION_INDEX {
      return -1, -1, false
    }
  return int(instance.preempted_transition), int(instance.preempted_by_transition), true
}

last_preemptions :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]Transition_Preemption(State)) {
  clear(out)
  if instance.chart == nil {
    return
  }

  for preemption in instance.preemption_scratch {
    preempted := instance.chart.def.transitions[preemption.preempted]
    preempted_by := instance.chart.def.transitions[preemption.preempted_by]
    append(out, Transition_Preemption(State){
      preempted = Transition_Step(State){source = preempted.source, target = preempted.target},
      preempted_by = Transition_Step(State){source = preempted_by.source, target = preempted_by.target},
    })
  }
}

last_preemption_indices_all :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]Transition_Preemption_Index) {
  clear(out)
  if instance.chart == nil {
    return
  }

  for preemption in instance.preemption_scratch {
    append(out, Transition_Preemption_Index{
      preempted = int(preemption.preempted),
      preempted_by = int(preemption.preempted_by),
    })
  }
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

active_leaves :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]State) {
  clear(out)
  if instance.chart == nil {
    return
  }

  for leaf_idx in instance.active_leaf_indices {
    append(out, instance.chart.def.states[leaf_idx].id)
  }
}

user_context :: proc(ctx_raw: rawptr) -> rawptr {
  if ctx_raw == nil {
    return nil
  }
  runtime_ctx := cast(^Runtime_Context_Header)ctx_raw
  return runtime_ctx.user
}

context_as :: proc(ctx_raw: rawptr, $Data: typeid) -> ^Data {
  if ctx_raw == nil {
    return nil
  }
  return cast(^Data)ctx_raw
}

user_context_as :: proc(ctx_raw: rawptr, $Data: typeid) -> ^Data {
  user := user_context(ctx_raw)
  if user == nil {
    return nil
  }
  return cast(^Data)user
}

event_as :: proc(event_raw: rawptr, $Trigger: typeid) -> ^Event(Trigger) {
  if event_raw == nil {
    return nil
  }
  return cast(^Event(Trigger))event_raw
}

event_data_as :: proc(event_raw: rawptr, $Trigger: typeid, $Data: typeid) -> ^Data {
  event := event_as(event_raw, Trigger)
  if event == nil {
    return nil
  }
  return cast(^Data)event.data
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

region_handle :: proc(
  chart: ^Chart($State, $Trigger),
  superstate: State,
  region_name: string,
) -> (Region_Handle, bool) {
  if chart == nil {
    return INVALID_REGION_HANDLE, false
  }

  super_idx := state_index(chart, superstate)
  if super_idx == INVALID_STATE_INDEX {
    return INVALID_REGION_HANDLE, false
  }

  region_idx := region_index(chart, super_idx, region_name)
  if region_idx == INVALID_REGION_INDEX {
    return INVALID_REGION_HANDLE, false
  }

  return Region_Handle(region_idx), true
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

  return active_leaf_in_region_index(instance, region_idx)
}

active_leaf_in_region_handle :: proc(
  instance: ^Instance($State, $Trigger),
  handle: Region_Handle,
) -> (State, bool) {
  if handle == INVALID_REGION_HANDLE {
    state: State
    return state, false
  }
  return active_leaf_in_region_index(instance, Region_Index(handle))
}

restore_active_leaves :: proc(instance: ^Instance($State, $Trigger), leaves: []State) -> bool {
  if instance.chart == nil || len(leaves) == 0 || len(leaves) > cap(instance.active_leaf_indices) {
    return false
  }

  clear(&instance.active_leaf_indices)
  reset_dispatch_scratch(instance)
  reset_history(instance)
  reset_after_events(instance)

  for leaf in leaves {
    leaf_idx := state_index(instance.chart, leaf)
    if leaf_idx == INVALID_STATE_INDEX ||
      instance.chart.state_owned_region_ranges[leaf_idx].count != 0 ||
      active_leaf_index_contains(instance, leaf_idx) {
	clear(&instance.active_leaf_indices)
	return false
      }
    append(&instance.active_leaf_indices, leaf_idx)
  }

  if !active_leaf_configuration_is_valid(instance) {
    clear(&instance.active_leaf_indices)
    return false
  }

  write_configuration_scratch(instance)
  return true
}

active_history :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]History_Snapshot(State)) {
  clear(out)
  if instance.chart == nil {
    return
  }

  for history, history_idx in instance.chart.histories {
    if history.kind == .Deep && effective_state_kind(instance.chart, history.superstate) == .And {
      owned_regions := instance.chart.state_owned_region_ranges[history.superstate]
      for offset in 0 ..< owned_regions.count {
	region_idx := instance.chart.state_owned_region_indices[owned_regions.start + offset]
	target_idx := remembered_deep_leaf_for_region(instance, region_idx)
	if target_idx == INVALID_STATE_INDEX || !state_is_in_region(instance.chart, target_idx, region_idx) {
	  continue
	}
	append_history_snapshot(instance, out, History_Index(history_idx), region_idx, target_idx)
      }
      continue
    }

    target_idx := INVALID_STATE_INDEX
    if history.kind == .Deep {
      target_idx = instance.deep_history_indices[history.superstate]
      if target_idx == INVALID_STATE_INDEX ||
	!state_is_descendant_or_self(instance.chart, target_idx, history.superstate) {
	  continue
	}
    } else {
      target_idx = instance.history_indices[history.superstate]
      if target_idx == INVALID_STATE_INDEX ||
	instance.chart.parent_index[target_idx] != history.superstate {
	  continue
	}
    }

    append_history_snapshot(instance, out, History_Index(history_idx), INVALID_REGION_INDEX, target_idx)
  }
}

restore_history :: proc(
  instance: ^Instance($State, $Trigger),
  history_snapshots: []History_Snapshot(State),
) -> bool {
  if instance.chart == nil {
    return false
  }

  reset_history(instance)
  for snapshot in history_snapshots {
    if !restore_history_snapshot(instance, snapshot) {
      reset_history(instance)
      return false
    }
  }
  return true
}

active_timers :: proc(instance: ^Instance($State, $Trigger), out: ^[dynamic]Timer_Snapshot(State, Trigger)) {
  clear(out)
  if instance.chart == nil {
    return
  }

  for timer, i in instance.after_events {
    if !timer.active || !is_active_index(instance, timer.state_index) {
      continue
    }
    append(out, Timer_Snapshot(State, Trigger){
      after_index = i,
      state = instance.chart.def.states[timer.state_index].id,
      due_ms = timer.due_ms,
      trigger = timer.trigger,
    })
  }
}

restore_active_timers :: proc(
  instance: ^Instance($State, $Trigger),
  timers: []Timer_Snapshot(State, Trigger),
) -> bool {
  if instance.chart == nil || len(timers) > cap(instance.after_events) {
    return false
  }

  reset_after_events(instance)
  for timer in timers {
    if timer.after_index < 0 || timer.after_index >= len(instance.chart.def.after_events) {
      reset_after_events(instance)
      return false
    }
    if instance.after_events[timer.after_index].active {
      reset_after_events(instance)
      return false
    }

    after := instance.chart.def.after_events[timer.after_index]
    if after.state != timer.state || after.trigger != timer.trigger {
      reset_after_events(instance)
      return false
    }

    state_idx := state_index(instance.chart, timer.state)
    if state_idx == INVALID_STATE_INDEX || !is_active_index(instance, state_idx) {
      reset_after_events(instance)
      return false
    }

    instance.after_events[timer.after_index] = Active_After(Trigger){
      active = true,
      state_index = state_idx,
      due_ms = timer.due_ms,
      trigger = timer.trigger,
    }
  }
  return true
}

append_history_snapshot :: proc(
  instance: ^Instance($State, $Trigger),
  out: ^[dynamic]History_Snapshot(State),
  history_idx: History_Index,
  region_idx: Region_Index,
  target_idx: State_Index,
) {
  history := instance.chart.histories[history_idx]
  region_name := ""
  region_index := HISTORY_SNAPSHOT_NO_REGION
  if region_idx != INVALID_REGION_INDEX {
    region_index = int(region_idx)
    region_name = instance.chart.regions[region_idx].name
  }

  append(out, History_Snapshot(State){
    history_index = int(history_idx),
    superstate = instance.chart.def.states[history.superstate].id,
    kind = history.kind,
    region_index = region_index,
    region_name = region_name,
    target = instance.chart.def.states[target_idx].id,
  })
}

restore_history_snapshot :: proc(instance: ^Instance($State, $Trigger), snapshot: History_Snapshot(State)) -> bool {
  if snapshot.history_index < 0 || snapshot.history_index >= len(instance.chart.histories) {
    return false
  }

  history := instance.chart.histories[snapshot.history_index]
  if snapshot.superstate != instance.chart.def.states[history.superstate].id ||
    snapshot.kind != history.kind {
      return false
    }

  target_idx := state_index(instance.chart, snapshot.target)
  if target_idx == INVALID_STATE_INDEX {
    return false
  }

  if history.kind == .Shallow {
    if snapshot.region_index != HISTORY_SNAPSHOT_NO_REGION ||
      instance.chart.parent_index[target_idx] != history.superstate {
	return false
      }

    existing := instance.history_indices[history.superstate]
    if existing != INVALID_STATE_INDEX && existing != target_idx {
      return false
    }
    instance.history_indices[history.superstate] = target_idx
    return true
  }

  if effective_state_kind(instance.chart, history.superstate) == .And {
    if snapshot.region_index < 0 || snapshot.region_index >= len(instance.chart.regions) {
      return false
    }

    region_idx := Region_Index(snapshot.region_index)
    region := instance.chart.regions[region_idx]
    if region.superstate != history.superstate ||
      region.name != snapshot.region_name ||
      instance.chart.state_owned_region_ranges[target_idx].count != 0 ||
      !state_is_in_region(instance.chart, target_idx, region_idx) {
	return false
      }

    existing := instance.deep_history_region_indices[region_idx]
    if existing != INVALID_STATE_INDEX && existing != target_idx {
      return false
    }
    instance.deep_history_region_indices[region_idx] = target_idx
    return true
  }

  if snapshot.region_index != HISTORY_SNAPSHOT_NO_REGION ||
    instance.chart.state_owned_region_ranges[target_idx].count != 0 ||
    !state_is_descendant_or_self(instance.chart, target_idx, history.superstate) {
      return false
    }

  existing := instance.deep_history_indices[history.superstate]
  if existing != INVALID_STATE_INDEX && existing != target_idx {
    return false
  }
  instance.deep_history_indices[history.superstate] = target_idx
  return true
}

active_leaf_in_region_index :: proc(
  instance: ^Instance($State, $Trigger),
  region_idx: Region_Index,
) -> (State, bool) {
  state: State
  if instance.chart == nil {
    return state, false
  }
  if region_idx == INVALID_REGION_INDEX || int(region_idx) < 0 || int(region_idx) >= len(instance.chart.regions) {
    return state, false
  }

  for leaf_idx in instance.active_leaf_indices {
    if state_is_in_region(instance.chart, leaf_idx, region_idx) {
      return instance.chart.def.states[leaf_idx].id, true
    }
  }

  return state, false
}

active_leaf_index_contains :: proc(instance: ^Instance($State, $Trigger), leaf_idx: State_Index) -> bool {
  for active_idx in instance.active_leaf_indices {
    if active_idx == leaf_idx {
      return true
    }
  }
  return false
}

active_leaf_configuration_is_valid :: proc(instance: ^Instance($State, $Trigger)) -> bool {
  for region, region_idx in instance.chart.regions {
    super_active := region.superstate == INVALID_STATE_INDEX || is_active_index(instance, region.superstate)
    active_child := INVALID_STATE_INDEX

    for leaf_idx in instance.active_leaf_indices {
      child_idx, in_region := active_child_in_region(instance.chart, leaf_idx, Region_Index(region_idx))
      if !in_region {
	continue
      }
      if active_child == INVALID_STATE_INDEX {
	active_child = child_idx
	continue
      }
      if active_child != child_idx {
	return false
      }
    }

    if super_active && active_child == INVALID_STATE_INDEX {
      return false
    }
  }
  return true
}

active_child_in_region :: proc(
  chart: ^Chart($State, $Trigger),
  leaf_idx: State_Index,
  region_idx: Region_Index,
) -> (State_Index, bool) {
  if region_idx == INVALID_REGION_INDEX || int(region_idx) < 0 || int(region_idx) >= len(chart.regions) {
    return INVALID_STATE_INDEX, false
  }

  region := chart.regions[region_idx]
  if region.superstate == INVALID_STATE_INDEX {
    cursor := leaf_idx
    child := INVALID_STATE_INDEX
    for cursor != INVALID_STATE_INDEX {
      child = cursor
      cursor = chart.parent_index[cursor]
    }
    if child != INVALID_STATE_INDEX && state_is_in_region(chart, child, region_idx) {
      return child, true
    }
    return INVALID_STATE_INDEX, false
  }

  cursor := leaf_idx
  for cursor != INVALID_STATE_INDEX {
    parent := chart.parent_index[cursor]
    if parent == region.superstate {
      if state_is_in_region(chart, cursor, region_idx) {
	return cursor, true
      }
      return INVALID_STATE_INDEX, false
    }
    if cursor == region.superstate {
      return INVALID_STATE_INDEX, false
    }
    cursor = parent
  }

  return INVALID_STATE_INDEX, false
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

next_due_event_ms :: proc(instance: ^Instance($State, $Trigger)) -> (u64, bool) {
  if instance.chart == nil {
    return 0, false
  }

  found := false
  next_due: u64
  for timer in instance.after_events {
    if !timer.active || !is_active_index(instance, timer.state_index) {
      continue
    }
    if !found || timer.due_ms < next_due {
      found = true
      next_due = timer.due_ms
    }
  }

  return next_due, found
}

max_capacity :: proc(default_capacity: int, requested_capacity: int) -> int {
  if requested_capacity > default_capacity {
    return requested_capacity
  }
  return default_capacity
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

    lca_idx := transition_exit_stop_index(instance.chart, transition_idx, target_idx)

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
    if history_targets_deep_and(instance.chart, history_idx) {
      resolved_target_idx = instance.chart.histories[history_idx].superstate
    } else {
      resolved_target_idx = resolved_history_target_index(instance, history_idx)
    }
  }
  if source_leaf_idx == INVALID_STATE_INDEX ||
    source_idx == INVALID_STATE_INDEX ||
    target_entry_idx == INVALID_STATE_INDEX {
      result.status = .Error
      return
    }

  lca_idx := transition_exit_stop_index(instance.chart, transition_idx, target_entry_idx)

  exit_transition_source(instance, source_idx, source_leaf_idx, lca_idx, ctx, event, result)
  if transition.action != nil {
    transition.action(ctx, event)
  }
  if history_idx != INVALID_HISTORY_INDEX && history_targets_deep_and(instance.chart, history_idx) {
    enter_deep_and_history_index(instance, history_idx, ctx, event, result, stop_idx = lca_idx)
  } else {
    enter_from_index(instance, resolved_target_idx, ctx, event, result, stop_idx = lca_idx)
  }
}

transition_target_entry_index :: proc(chart: ^Chart($State, $Trigger), transition_idx: Transition_Index) -> State_Index {
  history_idx := chart.transition_target_history_indices[transition_idx]
  if history_idx != INVALID_HISTORY_INDEX {
    return chart.histories[history_idx].superstate
  }
  return chart.transition_target_indices[transition_idx]
}

apply_always_transition_step :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  transition: Always_Def(State),
  transition_idx: Always_Index,
  source_leaf_idx: State_Index,
  ctx: rawptr,
  result: ^Dispatch_Result(State),
) {
  result.source = transition.source
  result.target = transition.target

  if transition.kind == .Internal {
    if transition.action != nil {
      transition.action(ctx, nil)
    }
    return
  }

  source_idx := instance.chart.always_transition_source_indices[transition_idx]
  if len(instance.chart.histories) == 0 {
    target_idx := instance.chart.always_transition_target_indices[transition_idx]
    if source_leaf_idx == INVALID_STATE_INDEX ||
      source_idx == INVALID_STATE_INDEX ||
      target_idx == INVALID_STATE_INDEX {
	result.status = .Error
	return
      }

    lca_idx := always_transition_exit_stop_index(instance.chart, transition_idx, target_idx)

    exit_transition_source(instance, source_idx, source_leaf_idx, lca_idx, ctx, nil, result)
    if transition.action != nil {
      transition.action(ctx, nil)
    }
    enter_from_index(instance, target_idx, ctx, nil, result, stop_idx = lca_idx)
    return
  }

  target_idx := instance.chart.always_transition_target_indices[transition_idx]
  history_idx := instance.chart.always_transition_target_history_indices[transition_idx]
  target_entry_idx := always_transition_target_entry_index(instance.chart, transition_idx)
  resolved_target_idx := target_idx
  if history_idx != INVALID_HISTORY_INDEX {
    if history_targets_deep_and(instance.chart, history_idx) {
      resolved_target_idx = instance.chart.histories[history_idx].superstate
    } else {
      resolved_target_idx = resolved_history_target_index(instance, history_idx)
    }
  }
  if source_leaf_idx == INVALID_STATE_INDEX ||
    source_idx == INVALID_STATE_INDEX ||
    target_entry_idx == INVALID_STATE_INDEX {
      result.status = .Error
      return
    }

  lca_idx := always_transition_exit_stop_index(instance.chart, transition_idx, target_entry_idx)

  exit_transition_source(instance, source_idx, source_leaf_idx, lca_idx, ctx, nil, result)
  if transition.action != nil {
    transition.action(ctx, nil)
  }
  if history_idx != INVALID_HISTORY_INDEX && history_targets_deep_and(instance.chart, history_idx) {
    enter_deep_and_history_index(instance, history_idx, ctx, nil, result, stop_idx = lca_idx)
  } else {
    enter_from_index(instance, resolved_target_idx, ctx, nil, result, stop_idx = lca_idx)
  }
}

always_transition_target_entry_index :: proc(chart: ^Chart($State, $Trigger), transition_idx: Always_Index) -> State_Index {
  history_idx := chart.always_transition_target_history_indices[transition_idx]
  if history_idx != INVALID_HISTORY_INDEX {
    return chart.histories[history_idx].superstate
  }
  return chart.always_transition_target_indices[transition_idx]
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

  remember_deep_history_regions(instance, idx)

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
  for i in 0 ..< len(instance.deep_history_region_indices) {
    instance.deep_history_region_indices[i] = INVALID_STATE_INDEX
  }
}

remember_deep_history_regions :: proc(instance: ^Instance($State, $Trigger), leaf_idx: State_Index) {
  for region, region_idx in instance.chart.regions {
    if region.initial == INVALID_STATE_INDEX {
      continue
    }
    if state_is_in_region(instance.chart, leaf_idx, Region_Index(region_idx)) {
      instance.deep_history_region_indices[region_idx] = leaf_idx
    }
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

state_is_in_region :: proc(chart: ^Chart($State, $Trigger), state_idx: State_Index, region_idx: Region_Index) -> bool {
  if region_idx == INVALID_REGION_INDEX {
    return false
  }

  region := chart.regions[region_idx]
  cursor := state_idx
  for cursor != INVALID_STATE_INDEX {
    if chart.state_region_index[cursor] == region_idx {
      return true
    }
    if cursor == region.superstate {
      return false
    }
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
    if effective_state_kind(instance.chart, region.superstate) == .And {
      if state_is_in_region(instance.chart, leaf_idx, region_idx) &&
	effective_state_kind(instance.chart, leaf_idx) == .Final {
	  return true
	}
    } else {
      if state_is_descendant_or_self(instance.chart, leaf_idx, ancestor_idx) &&
	effective_state_kind(instance.chart, leaf_idx) == .Final {
	  return true
	}
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

enter_path_to_index :: proc(
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

history_targets_deep_and :: proc(chart: ^Chart($State, $Trigger), history_idx: History_Index) -> bool {
  history := chart.histories[history_idx]
  return history.kind == .Deep && effective_state_kind(chart, history.superstate) == .And
}

enter_deep_and_history_index :: proc(
  instance: ^Instance($State, $Trigger),
  history_idx: History_Index,
  ctx: rawptr,
  event: rawptr,
  result: ^Dispatch_Result(State),
  stop_idx := INVALID_STATE_INDEX,
) {
  history := instance.chart.histories[history_idx]
  owned_regions := instance.chart.state_owned_region_ranges[history.superstate]
  if owned_regions.count == 0 || !deep_and_history_is_complete(instance, history.superstate) {
    enter_from_index(instance, history.fallback, ctx, event, result, stop_idx = stop_idx)
    return
  }

  enter_path_to_index(instance, history.superstate, ctx, event, result, stop_idx)

  for offset in 0 ..< owned_regions.count {
    region_idx := instance.chart.state_owned_region_indices[owned_regions.start + offset]
    leaf_idx := remembered_deep_leaf_for_region(instance, region_idx)
    enter_from_index(instance, leaf_idx, ctx, event, result, stop_idx = history.superstate)
  }
}

deep_and_history_is_complete :: proc(instance: ^Instance($State, $Trigger), superstate_idx: State_Index) -> bool {
  owned_regions := instance.chart.state_owned_region_ranges[superstate_idx]
  for offset in 0 ..< owned_regions.count {
    region_idx := instance.chart.state_owned_region_indices[owned_regions.start + offset]
    leaf_idx := remembered_deep_leaf_for_region(instance, region_idx)
    if leaf_idx == INVALID_STATE_INDEX {
      return false
    }
    if !state_is_in_region(instance.chart, leaf_idx, region_idx) {
      return false
    }
  }
  return true
}

remembered_deep_leaf_for_region :: proc(instance: ^Instance($State, $Trigger), region_idx: Region_Index) -> State_Index {
  if region_idx == INVALID_REGION_INDEX || int(region_idx) >= len(instance.deep_history_region_indices) {
    return INVALID_STATE_INDEX
  }
  return instance.deep_history_region_indices[region_idx]
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
  clear(&instance.preemption_scratch)
  instance.conflict_first = INVALID_TRANSITION_INDEX
  instance.conflict_second = INVALID_TRANSITION_INDEX
  instance.preempted_transition = INVALID_TRANSITION_INDEX
  instance.preempted_by_transition = INVALID_TRANSITION_INDEX
}

write_configuration_scratch :: proc(instance: ^Instance($State, $Trigger)) {
  write_configuration(instance, &instance.configuration_scratch)
}

finalize_dispatch_result :: proc(instance: ^Instance($State, $Trigger), result: ^Dispatch_Result(State)) {
  result.exited = instance.exited_scratch[:]
  result.entered = instance.entered_scratch[:]
  result.configuration = instance.configuration_scratch[:]
}
