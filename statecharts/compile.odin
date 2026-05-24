package statecharts

import "core:fmt"
import "core:strings"

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
  if chart.transition_trigger_group_ranges != nil {
    delete(chart.transition_trigger_group_ranges)
    chart.transition_trigger_group_ranges = nil
  }
  if chart.transition_trigger_ranges != nil {
    delete(chart.transition_trigger_ranges)
    chart.transition_trigger_ranges = nil
  }
  if chart.transition_trigger_indices != nil {
    delete(chart.transition_trigger_indices)
    chart.transition_trigger_indices = nil
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
  if chart.always_transition_ranges != nil {
    delete(chart.always_transition_ranges)
    chart.always_transition_ranges = nil
  }
  if chart.always_transition_indices != nil {
    delete(chart.always_transition_indices)
    chart.always_transition_indices = nil
  }
  if chart.always_transition_source_indices != nil {
    delete(chart.always_transition_source_indices)
    chart.always_transition_source_indices = nil
  }
  if chart.always_transition_target_indices != nil {
    delete(chart.always_transition_target_indices)
    chart.always_transition_target_indices = nil
  }
  if chart.always_transition_target_history_indices != nil {
    delete(chart.always_transition_target_history_indices)
    chart.always_transition_target_history_indices = nil
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
  if instance.deep_history_region_indices != nil {
    delete(instance.deep_history_region_indices)
    instance.deep_history_region_indices = nil
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
  if instance.preemption_scratch != nil {
    delete(instance.preemption_scratch)
    instance.preemption_scratch = nil
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
  out.transition_trigger_group_ranges = make([dynamic]Transition_Range, 0, len(def.states))
  out.transition_trigger_ranges = make([dynamic]Transition_Trigger_Range(Trigger), 0, len(def.transitions))
  out.transition_trigger_indices = make([dynamic]Transition_Index, 0, len(def.transitions))
  out.transition_source_indices = make([dynamic]State_Index, 0, len(def.transitions))
  out.transition_target_indices = make([dynamic]State_Index, 0, len(def.transitions))
  out.transition_target_history_indices = make([dynamic]History_Index, 0, len(def.transitions))
  out.always_transition_ranges = make([dynamic]Transition_Range, 0, len(def.states))
  out.always_transition_indices = make([dynamic]Always_Index, 0, len(def.always_transitions))
  out.always_transition_source_indices = make([dynamic]State_Index, 0, len(def.always_transitions))
  out.always_transition_target_indices = make([dynamic]State_Index, 0, len(def.always_transitions))
  out.always_transition_target_history_indices = make([dynamic]History_Index, 0, len(def.always_transitions))

  for _ in def.states {
    append(&out.parent_index, INVALID_STATE_INDEX)
    append(&out.initial_index, INVALID_STATE_INDEX)
    append(&out.state_region_index, INVALID_REGION_INDEX)
    append(&out.state_owned_region_index, INVALID_REGION_INDEX)
    append(&out.state_owned_region_ranges, Region_Range{})
    append(&out.transition_ranges, Transition_Range{})
    append(&out.transition_trigger_group_ranges, Transition_Range{})
    append(&out.always_transition_ranges, Transition_Range{})
  }
  for _ in def.transitions {
    append(&out.transition_indices, INVALID_TRANSITION_INDEX)
    append(&out.transition_trigger_indices, INVALID_TRANSITION_INDEX)
    append(&out.transition_source_indices, INVALID_STATE_INDEX)
    append(&out.transition_target_indices, INVALID_STATE_INDEX)
    append(&out.transition_target_history_indices, INVALID_HISTORY_INDEX)
  }
  for _ in def.always_transitions {
    append(&out.always_transition_indices, INVALID_ALWAYS_INDEX)
    append(&out.always_transition_source_indices, INVALID_STATE_INDEX)
    append(&out.always_transition_target_indices, INVALID_STATE_INDEX)
    append(&out.always_transition_target_history_indices, INVALID_HISTORY_INDEX)
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
  validate_substate_regions(out, &result)
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
      if effective_state_kind(out, source_idx) == .Final {
	add_error(&result, .Final_State_Has_Outgoing_Transition, transition_index = i)
      }
    }
    if target_idx == INVALID_STATE_INDEX && history_idx == INVALID_HISTORY_INDEX {
      add_error(&result, .Missing_Transition_Target, transition_index = i)
    } else if history_idx != INVALID_HISTORY_INDEX {
      out.transition_target_history_indices[i] = history_idx
    } else {
      out.transition_target_indices[i] = target_idx
    }
    if source_idx != INVALID_STATE_INDEX &&
      transition.kind == .Internal &&
      target_idx != source_idx {
	add_error(&result, .Internal_Transition_Target_Not_Source, transition_index = i)
      }
  }

  for transition, i in def.always_transitions {
    source_idx := state_index(out, transition.source)
    target_idx := state_index(out, transition.target)
    history_idx := history_index(out, transition.target)
    if source_idx == INVALID_STATE_INDEX {
      add_error(&result, .Missing_Always_Source, initial_index = i)
    } else {
      out.always_transition_source_indices[i] = source_idx
      if effective_state_kind(out, source_idx) == .Final {
	add_error(&result, .Final_State_Has_Outgoing_Transition, initial_index = i)
      }
    }
    if target_idx == INVALID_STATE_INDEX && history_idx == INVALID_HISTORY_INDEX {
      add_error(&result, .Missing_Always_Target, initial_index = i)
    } else if history_idx != INVALID_HISTORY_INDEX {
      out.always_transition_target_history_indices[i] = history_idx
    } else {
      out.always_transition_target_indices[i] = target_idx
    }
    if source_idx != INVALID_STATE_INDEX &&
      transition.kind == .Internal &&
      target_idx != source_idx {
	add_error(&result, .Internal_Always_Target_Not_Source, initial_index = i)
      }
  }

  for done, i in def.done_events {
    done_idx := state_index(out, done.state)
    if done_idx == INVALID_STATE_INDEX {
      add_error(&result, .Missing_Done_State, initial_index = i)
    } else if effective_state_kind(out, done_idx) != .Final && !state_has_child(out, done_idx) {
      add_error(&result, .Done_State_Not_Completable, initial_index = i)
    }
    for other, j in def.done_events {
      if j <= i {
	continue
      }
      if done.state == other.state && done.trigger == other.trigger {
	add_error(&result, .Duplicate_Done, initial_index = j)
      }
    }
  }

  for after, i in def.after_events {
    after_idx := state_index(out, after.state)
    if after_idx == INVALID_STATE_INDEX {
      add_error(&result, .Missing_After_State, initial_index = i)
    }
    for other, j in def.after_events {
      if j <= i {
	continue
      }
      if after.state == other.state &&
	after.delay_ms == other.delay_ms &&
	after.trigger == other.trigger {
	  add_error(&result, .Duplicate_After, initial_index = j)
	}
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
    for i in 0 ..< len(def.always_transitions) {
      for j in i + 1 ..< len(def.always_transitions) {
	if def.always_transitions[i].source == def.always_transitions[j].source {
	  add_error(&result, .Duplicate_Always, initial_index = j)
	}
      }
    }
  }

  build_transition_adjacency(out)
  build_transition_trigger_adjacency(out)
  build_always_transition_adjacency(out)
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

validate_substate_regions :: proc(chart: ^Chart($State, $Trigger), result: ^Compile_Result) {
  for substate, i in chart.def.substates {
    if substate.region == "" {
      continue
    }

    super_idx := state_index(chart, substate.superstate)
    if super_idx == INVALID_STATE_INDEX {
      continue
    }

    if effective_state_kind(chart, super_idx) != .And {
      add_error(result, .Substate_Region_On_Non_And_State, substate_index = i)
      continue
    }

    if !region_name_exists(chart, substate.superstate, substate.region) {
      add_error(result, .Missing_Substate_Region, substate_index = i)
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

  for substate in chart.def.substates {
    if substate.superstate != superstate || substate.substate != child || substate.region == "" {
      continue
    }

    if region_name_exists(chart, superstate, substate.region) {
      return 1
    }

    return 0
  }

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

region_name_exists :: proc(chart: ^Chart($State, $Trigger), superstate: State, name: string) -> bool {
  for region in chart.def.regions {
    if region.superstate == superstate && region.name == name {
      return true
    }
  }
  return false
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

write_validation_error :: proc(
  def: Chart_Def($State, $Trigger),
  error: Validation_Error,
  out: ^strings.Builder,
) {
  strings.write_string(out, validation_error_kind_text(error.kind))

  if error.state_index >= 0 {
    fmt.sbprintf(out, " state[%d]", error.state_index)
    if error.state_index < len(def.states) {
      strings.write_string(out, " ")
      write_plain_value(out, def.states[error.state_index].id)
    }
  }
  if error.substate_index >= 0 {
    fmt.sbprintf(out, " substate[%d]", error.substate_index)
    if error.substate_index < len(def.substates) {
      substate := def.substates[error.substate_index]
      strings.write_string(out, " ")
      write_plain_value(out, substate.substate)
      strings.write_string(out, " under ")
      write_plain_value(out, substate.superstate)
      if substate.region != "" {
	strings.write_string(out, " in region ")
	strings.write_string(out, substate.region)
      }
    }
  }
  if error.initial_index >= 0 {
    write_validation_index_detail(def, error, out)
  }
  if error.transition_index >= 0 {
    fmt.sbprintf(out, " transition[%d]", error.transition_index)
    if error.transition_index < len(def.transitions) {
      transition := def.transitions[error.transition_index]
      strings.write_string(out, " ")
      write_plain_value(out, transition.source)
      strings.write_string(out, " --")
      write_plain_value(out, transition.trigger)
      strings.write_string(out, "--> ")
      write_plain_value(out, transition.target)
    }
  }
}

write_validation_index_detail :: proc(
  def: Chart_Def($State, $Trigger),
  error: Validation_Error,
  out: ^strings.Builder,
) {
  index := error.initial_index
  #partial switch error.kind {
    case .Missing_Always_Source, .Missing_Always_Target, .Internal_Always_Target_Not_Source, .Duplicate_Always:
    fmt.sbprintf(out, " always[%d]", index)
    if index < len(def.always_transitions) {
      transition := def.always_transitions[index]
      strings.write_string(out, " ")
      write_plain_value(out, transition.source)
      strings.write_string(out, " --> ")
      write_plain_value(out, transition.target)
    }
    case .Missing_Done_State, .Done_State_Not_Completable, .Duplicate_Done:
    fmt.sbprintf(out, " done[%d]", index)
    if index < len(def.done_events) {
      strings.write_string(out, " ")
      write_plain_value(out, def.done_events[index].state)
    }
    case .Missing_After_State, .Duplicate_After:
    fmt.sbprintf(out, " after[%d]", index)
    if index < len(def.after_events) {
      strings.write_string(out, " ")
      write_plain_value(out, def.after_events[index].state)
    }
    case .Duplicate_History, .History_Id_Conflicts_With_State, .Missing_History_Superstate, .Missing_History_Fallback, .History_Fallback_Not_Direct_Substate:
    fmt.sbprintf(out, " history[%d]", index)
    if index < len(def.histories) {
      history := def.histories[index]
      strings.write_string(out, " ")
      write_plain_value(out, history.id)
      strings.write_string(out, " for ")
      write_plain_value(out, history.superstate)
    }
    case .Missing_Initial_Superstate, .Missing_Initial_Substate, .Initial_Not_Direct_Substate, .Duplicate_Initial, .Duplicate_Region_Name:
    if index < len(def.regions) {
      region := def.regions[index]
      fmt.sbprintf(out, " region[%d]", index)
      if region.name != "" {
	strings.write_string(out, " ")
	strings.write_string(out, region.name)
      }
      strings.write_string(out, " ")
      write_plain_value(out, region.superstate)
      strings.write_string(out, " -> ")
      write_plain_value(out, region.initial)
    } else {
      initial_index := index - len(def.regions)
      fmt.sbprintf(out, " initial[%d]", initial_index)
      if initial_index >= 0 && initial_index < len(def.initials) {
	initial := def.initials[initial_index]
	strings.write_string(out, " ")
	write_plain_value(out, initial.superstate)
	strings.write_string(out, " -> ")
	write_plain_value(out, initial.initial)
      }
    }
    case:
    fmt.sbprintf(out, " index[%d]", index)
  }
}

validation_error_kind_text :: proc(kind: Validation_Error_Kind) -> string {
  switch kind {
  case .Duplicate_State:
    return "duplicate state"
  case .Missing_Initial_State:
    return "missing initial state"
  case .Initial_Not_Top_Level:
    return "initial state is not top-level"
  case .Missing_Substate:
    return "missing substate"
  case .Missing_Superstate:
    return "missing superstate"
  case .Duplicate_Substate:
    return "duplicate substate"
  case .Self_Substate:
    return "state cannot be its own substate"
  case .Superstate_Cycle:
    return "superstate cycle"
  case .Missing_Initial_Superstate:
    return "missing initial superstate"
  case .Missing_Initial_Substate:
    return "missing initial substate"
  case .Initial_Not_Direct_Substate:
    return "initial is not a direct substate"
  case .Duplicate_Initial:
    return "duplicate initial"
  case .Superstate_Missing_Initial:
    return "superstate missing initial"
  case .Leaf_Has_Initial:
    return "leaf has initial"
  case .Missing_Transition_Source:
    return "missing transition source"
  case .Missing_Transition_Target:
    return "missing transition target"
  case .Internal_Transition_Target_Not_Source:
    return "internal transition target is not source"
  case .Missing_Always_Source:
    return "missing always transition source"
  case .Missing_Always_Target:
    return "missing always transition target"
  case .Internal_Always_Target_Not_Source:
    return "internal always transition target is not source"
  case .Duplicate_Always:
    return "duplicate always transition"
  case .Missing_Done_State:
    return "missing done state"
  case .Done_State_Not_Completable:
    return "done state is not completable"
  case .Duplicate_Done:
    return "duplicate done"
  case .Missing_After_State:
    return "missing after state"
  case .Duplicate_After:
    return "duplicate after"
  case .Ambiguous_Transition:
    return "ambiguous transition"
  case .Atomic_State_Has_Substates:
    return "atomic state has substates"
  case .Final_State_Has_Substates:
    return "final state has substates"
  case .Final_State_Has_Outgoing_Transition:
    return "final state has outgoing transition"
  case .And_State_Missing_Region:
    return "and state missing region"
  case .Duplicate_Region_Name:
    return "duplicate region name"
  case .Missing_Substate_Region:
    return "missing substate region"
  case .Substate_Region_On_Non_And_State:
    return "substate region on non-and state"
  case .Duplicate_History:
    return "duplicate history"
  case .History_Id_Conflicts_With_State:
    return "history id conflicts with state"
  case .Missing_History_Superstate:
    return "missing history superstate"
  case .Missing_History_Fallback:
    return "missing history fallback"
  case .History_Fallback_Not_Direct_Substate:
    return "history fallback is invalid"
  case .Deep_History_On_And_State:
    return "deep history on and state"
  }
  return "validation error"
}

write_plain_value :: proc(out: ^strings.Builder, value: $T) {
  fmt.sbprintf(out, "%v", value)
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
) -> (bool, Transition_Conflict) {
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

  conflict := select_enabled_transitions(instance)
  return blocked_by_guard, conflict
}

collect_enabled_always_transitions :: proc(
  instance: ^Instance($State, $Trigger),
  ctx: rawptr,
) -> (bool, Always_Transition_Conflict) {
  clear(&instance.candidate_transition_scratch)
  clear(&instance.enabled_transition_scratch)
  blocked_by_guard := false

  for leaf_idx in instance.active_leaf_indices {
    enabled := find_enabled_always_transition_from_leaf(instance, leaf_idx, ctx)
    if enabled.blocked_by_guard {
      blocked_by_guard = true
    }
    if !enabled.found {
      continue
    }

    append(&instance.candidate_transition_scratch, Enabled_Transition{
      found = true,
      leaf_index = enabled.leaf_index,
      transition_index = Transition_Index(enabled.transition_index),
    })
  }

  conflict := select_enabled_always_transitions(instance)
  return blocked_by_guard, conflict
}

select_enabled_transitions :: proc(instance: ^Instance($State, $Trigger)) -> Transition_Conflict {
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

      if candidate.transition_index == selected.transition_index {
	should_select = false
	break
      }

      if candidate_source_idx != selected_source_idx &&
	state_is_descendant_or_self(instance.chart, candidate_source_idx, selected_source_idx) {
	  record_preemption(instance, selected.transition_index, candidate.transition_index)
	  ordered_remove(&instance.enabled_transition_scratch, i)
	  continue
	}

      if selected_source_idx != candidate_source_idx &&
	state_is_descendant_or_self(instance.chart, selected_source_idx, candidate_source_idx) {
	  record_preemption(instance, candidate.transition_index, selected.transition_index)
	  should_select = false
	  break
	}

      return Transition_Conflict{
	found = true,
	first = selected.transition_index,
	second = candidate.transition_index,
      }
    }

    if should_select {
      append(&instance.enabled_transition_scratch, candidate)
    }
  }
  return Transition_Conflict{}
}

select_enabled_always_transitions :: proc(instance: ^Instance($State, $Trigger)) -> Always_Transition_Conflict {
  for candidate in instance.candidate_transition_scratch {
    candidate_idx := Always_Index(candidate.transition_index)
    candidate_source_idx := instance.chart.always_transition_source_indices[candidate_idx]
    candidate_exit_root_idx := always_transition_exit_root(instance.chart, candidate_idx)

    should_select := true
    for i := len(instance.enabled_transition_scratch) - 1; i >= 0; i -= 1 {
      selected := instance.enabled_transition_scratch[i]
      selected_idx := Always_Index(selected.transition_index)
      selected_source_idx := instance.chart.always_transition_source_indices[selected_idx]
      selected_exit_root_idx := always_transition_exit_root(instance.chart, selected_idx)

      if !exit_roots_conflict(instance.chart, candidate_exit_root_idx, selected_exit_root_idx) {
	continue
      }

      if candidate_idx == selected_idx {
	should_select = false
	break
      }

      if candidate_source_idx != selected_source_idx &&
	state_is_descendant_or_self(instance.chart, candidate_source_idx, selected_source_idx) {
	  ordered_remove(&instance.enabled_transition_scratch, i)
	  continue
	}

      if selected_source_idx != candidate_source_idx &&
	state_is_descendant_or_self(instance.chart, selected_source_idx, candidate_source_idx) {
	  should_select = false
	  break
	}

      return Always_Transition_Conflict{
	found = true,
	first = selected_idx,
	second = candidate_idx,
      }
    }

    if should_select {
      append(&instance.enabled_transition_scratch, candidate)
    }
  }
  return Always_Transition_Conflict{}
}

record_preemption :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  preempted: Transition_Index,
  preempted_by: Transition_Index,
) {
  instance.preempted_transition = preempted
  instance.preempted_by_transition = preempted_by
  append(&instance.preemption_scratch, Preemption_Record{
    preempted = preempted,
    preempted_by = preempted_by,
  })
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
    if transition_range.count <= 2 {
      for offset in 0 ..< transition_range.count {
	transition_idx := instance.chart.transition_indices[transition_range.start + offset]
	if transition_idx == INVALID_TRANSITION_INDEX do continue

	transition := &instance.chart.def.transitions[transition_idx]
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
    } else {
      group_range := instance.chart.transition_trigger_group_ranges[cursor]
      group_idx := transition_trigger_group_index(
	instance.chart,
	group_range.start,
	group_range.start + group_range.count,
	event.id,
      )
      if group_idx != -1 {
	trigger_range := instance.chart.transition_trigger_ranges[group_idx]
	for offset in 0 ..< trigger_range.count {
	  transition_idx := instance.chart.transition_trigger_indices[trigger_range.start + offset]
	  if transition_idx == INVALID_TRANSITION_INDEX do continue

	  transition := &instance.chart.def.transitions[transition_idx]
	  if transition.guard != nil && !transition.guard(ctx, event) {
	    result.blocked_by_guard = true
	    continue
	  }

	  result.found = true
	  result.leaf_index = leaf_idx
	  result.transition_index = transition_idx
	  return result
	}
      }
    }
    cursor = instance.chart.parent_index[cursor]
  }

  return result
}

find_enabled_always_transition_from_leaf :: #force_inline proc(
  instance: ^Instance($State, $Trigger),
  leaf_idx: State_Index,
  ctx: rawptr,
) -> Enabled_Always_Transition {
  result := Enabled_Always_Transition{
    leaf_index = INVALID_STATE_INDEX,
    transition_index = INVALID_ALWAYS_INDEX,
  }
  if leaf_idx == INVALID_STATE_INDEX do return result

  cursor := leaf_idx
  for cursor != INVALID_STATE_INDEX {
    transition_range := instance.chart.always_transition_ranges[cursor]
    for offset in 0 ..< transition_range.count {
      transition_idx := instance.chart.always_transition_indices[transition_range.start + offset]
      if transition_idx == INVALID_ALWAYS_INDEX do continue

      transition := &instance.chart.def.always_transitions[transition_idx]
      if transition.guard != nil && !transition.guard(ctx, nil) {
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
  lca_idx := transition_exit_stop_index(chart, transition_idx, target_idx)
  return highest_exited_state(chart, source_idx, lca_idx)
}

always_transition_exit_root :: proc(chart: ^Chart($State, $Trigger), transition_idx: Always_Index) -> State_Index {
  source_idx := chart.always_transition_source_indices[transition_idx]
  target_idx := always_transition_target_entry_index(chart, transition_idx)
  if target_idx == INVALID_STATE_INDEX {
    return source_idx
  }
  lca_idx := always_transition_exit_stop_index(chart, transition_idx, target_idx)
  return highest_exited_state(chart, source_idx, lca_idx)
}

transition_exit_stop_index :: proc(
  chart: ^Chart($State, $Trigger),
  transition_idx: Transition_Index,
  target_idx: State_Index,
) -> State_Index {
  source_idx := chart.transition_source_indices[transition_idx]
  lca_idx := least_common_superstate(chart, source_idx, target_idx)
  transition := chart.def.transitions[transition_idx]
  if transition.kind != .Local &&
    (chart.transition_target_history_indices[transition_idx] == INVALID_HISTORY_INDEX && source_idx == target_idx ||
     source_idx != target_idx && state_is_descendant_or_self(chart, target_idx, source_idx)) {
      lca_idx = chart.parent_index[source_idx]
    }
  return lca_idx
}

always_transition_exit_stop_index :: proc(
  chart: ^Chart($State, $Trigger),
  transition_idx: Always_Index,
  target_idx: State_Index,
) -> State_Index {
  source_idx := chart.always_transition_source_indices[transition_idx]
  lca_idx := least_common_superstate(chart, source_idx, target_idx)
  transition := chart.def.always_transitions[transition_idx]
  if transition.kind != .Local &&
    (chart.always_transition_target_history_indices[transition_idx] == INVALID_HISTORY_INDEX && source_idx == target_idx ||
     source_idx != target_idx && state_is_descendant_or_self(chart, target_idx, source_idx)) {
      lca_idx = chart.parent_index[source_idx]
    }
  return lca_idx
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

build_transition_trigger_adjacency :: proc(chart: ^Chart($State, $Trigger)) {
  for i in 0 ..< len(chart.transition_trigger_group_ranges) {
    chart.transition_trigger_group_ranges[i] = Transition_Range{}
  }
  for i in 0 ..< len(chart.transition_trigger_indices) {
    chart.transition_trigger_indices[i] = INVALID_TRANSITION_INDEX
  }
  clear(&chart.transition_trigger_ranges)

  for state_idx in 0 ..< len(chart.transition_ranges) {
    source_range := chart.transition_ranges[state_idx]
    group_start := len(chart.transition_trigger_ranges)
    chart.transition_trigger_group_ranges[state_idx].start = group_start

    for offset in 0 ..< source_range.count {
      transition_idx := chart.transition_indices[source_range.start + offset]
      if transition_idx == INVALID_TRANSITION_INDEX do continue

      trigger := chart.def.transitions[transition_idx].trigger
      group_idx := transition_trigger_group_index(chart, group_start, len(chart.transition_trigger_ranges), trigger)
      if group_idx == -1 {
	group_idx = len(chart.transition_trigger_ranges)
	append(&chart.transition_trigger_ranges, Transition_Trigger_Range(Trigger){trigger = trigger})
	chart.transition_trigger_group_ranges[state_idx].count += 1
      }
      chart.transition_trigger_ranges[group_idx].count += 1
    }
  }

  write_offsets := make([dynamic]int, 0, len(chart.transition_trigger_ranges))
  defer delete(write_offsets)
  start := 0
  for &group in chart.transition_trigger_ranges {
    group.start = start
    append(&write_offsets, start)
    start += group.count
  }

  for state_idx in 0 ..< len(chart.transition_ranges) {
    source_range := chart.transition_ranges[state_idx]
    group_range := chart.transition_trigger_group_ranges[state_idx]
    for offset in 0 ..< source_range.count {
      transition_idx := chart.transition_indices[source_range.start + offset]
      if transition_idx == INVALID_TRANSITION_INDEX do continue

      trigger := chart.def.transitions[transition_idx].trigger
      group_idx := transition_trigger_group_index(
	chart,
	group_range.start,
	group_range.start + group_range.count,
	trigger,
      )
      if group_idx == -1 do continue

      write_idx := write_offsets[group_idx]
      chart.transition_trigger_indices[write_idx] = transition_idx
      write_offsets[group_idx] += 1
    }
  }
}

build_always_transition_adjacency :: proc(chart: ^Chart($State, $Trigger)) {
  for i in 0 ..< len(chart.always_transition_ranges) {
    chart.always_transition_ranges[i] = Transition_Range{}
  }
  for i in 0 ..< len(chart.always_transition_indices) {
    chart.always_transition_indices[i] = INVALID_ALWAYS_INDEX
  }

  for _, transition_index in chart.def.always_transitions {
    source_idx := chart.always_transition_source_indices[transition_index]
    if source_idx != INVALID_STATE_INDEX {
      chart.always_transition_ranges[source_idx].count += 1
    }
  }

  start := 0
  write_offsets := make([dynamic]State_Index, 0, len(chart.def.states))
  defer delete(write_offsets)
  for i in 0 ..< len(chart.always_transition_ranges) {
    chart.always_transition_ranges[i].start = start
    append(&write_offsets, State_Index(start))
    start += chart.always_transition_ranges[i].count
  }

  for _, transition_idx in chart.def.always_transitions {
    source_idx := chart.always_transition_source_indices[transition_idx]
    if source_idx == INVALID_STATE_INDEX do continue

    write_idx := write_offsets[source_idx]
    chart.always_transition_indices[int(write_idx)] = Always_Index(transition_idx)
    write_offsets[source_idx] += 1
  }
}

transition_trigger_group_index :: proc(
  chart: ^Chart($State, $Trigger),
  start: int,
  end: int,
  trigger: Trigger,
) -> int {
  for group_idx in start ..< end {
    if chart.transition_trigger_ranges[group_idx].trigger == trigger {
      return group_idx
    }
  }
  return -1
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
    if name != "" {
      superstate := chart.def.states[superstate_idx].id
      for substate in chart.def.substates {
	if substate.superstate != superstate || substate.region != name {
	  continue
	}

	substate_idx := state_index(chart, substate.substate)
	if substate_idx != INVALID_STATE_INDEX {
	  chart.state_region_index[substate_idx] = region_idx
	}
      }
    }
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
