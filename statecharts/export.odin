package statecharts

import "core:fmt"
import "core:strings"

write_dot :: proc(chart: ^Chart($State, $Trigger), out: ^strings.Builder) -> bool {
  if chart == nil {
    return false
  }

  strings.write_string(out, "digraph statechart {\n")
  strings.write_string(out, "  rankdir=LR;\n")
  strings.write_string(out, "  node [shape=box];\n")

  for state, i in chart.def.states {
    fmt.sbprintf(out, "  S%d [label=\"", i)
    dot_write_value(out, state.id)
    if effective_state_kind(chart, State_Index(i)) == .Final {
      strings.write_string(out, "\", peripheries=2")
    } else {
      strings.write_string(out, "\"")
    }
    strings.write_string(out, "];\n")
  }

  for parent_idx, child_idx in chart.parent_index {
    if parent_idx == INVALID_STATE_INDEX {
      continue
    }
    fmt.sbprintf(out, "  S%d -> S%d [style=dotted, arrowhead=none, label=\"contains\"];\n", int(parent_idx), child_idx)
  }

  for region, i in chart.regions {
    if region.superstate == INVALID_STATE_INDEX || region.initial == INVALID_STATE_INDEX {
      continue
    }
    fmt.sbprintf(out, "  R%d [shape=point, label=\"\"];\n", i)
    fmt.sbprintf(out, "  S%d -> R%d [style=dashed, arrowhead=none", int(region.superstate), i)
    if region.name != "" {
      strings.write_string(out, ", label=\"")
      dot_write_escaped(out, region.name)
      strings.write_string(out, "\"")
    }
    strings.write_string(out, "];\n")
    fmt.sbprintf(out, "  R%d -> S%d [style=dashed, label=\"initial\"];\n", i, int(region.initial))
  }

  for transition, i in chart.def.transitions {
    source_idx := chart.transition_source_indices[i]
    target_idx := chart.transition_target_indices[i]
    history_idx := chart.transition_target_history_indices[i]
    if source_idx == INVALID_STATE_INDEX {
      continue
    }
    if target_idx != INVALID_STATE_INDEX {
      fmt.sbprintf(out, "  S%d -> S%d [label=\"", int(source_idx), int(target_idx))
    } else if history_idx != INVALID_HISTORY_INDEX {
      fmt.sbprintf(out, "  S%d -> H%d [label=\"", int(source_idx), int(history_idx))
    } else {
      continue
    }

    dot_write_value(out, transition.trigger)
    if transition.kind == .Internal {
      strings.write_string(out, " / internal")
    } else if transition.kind == .Local {
      strings.write_string(out, " / local")
    }
    strings.write_string(out, "\"];\n")
  }

  for transition, i in chart.def.always_transitions {
    source_idx := chart.always_transition_source_indices[i]
    target_idx := chart.always_transition_target_indices[i]
    history_idx := chart.always_transition_target_history_indices[i]
    if source_idx == INVALID_STATE_INDEX {
      continue
    }
    if target_idx != INVALID_STATE_INDEX {
      fmt.sbprintf(out, "  S%d -> S%d [label=\"always", int(source_idx), int(target_idx))
    } else if history_idx != INVALID_HISTORY_INDEX {
      fmt.sbprintf(out, "  S%d -> H%d [label=\"always", int(source_idx), int(history_idx))
    } else {
      continue
    }

    if transition.kind == .Internal {
      strings.write_string(out, " / internal")
    } else if transition.kind == .Local {
      strings.write_string(out, " / local")
    }
    strings.write_string(out, "\"];\n")
  }

  for history, i in chart.histories {
    fmt.sbprintf(out, "  H%d [shape=circle, label=\"", i)
    dot_write_value(out, history.id)
    if history.kind == .Deep {
      strings.write_string(out, " (deep)")
    } else {
      strings.write_string(out, " (shallow)")
    }
    fmt.sbprintf(out, "\"];\n  H%d -> S%d [style=dashed, label=\"fallback\"];\n", i, int(history.fallback))
  }

  strings.write_string(out, "}\n")
  return true
}

write_scxml :: proc(
  chart: ^Chart($State, $Trigger),
  out: ^strings.Builder,
  name: string = "statechart",
) -> bool {
  if chart == nil {
    return false
  }

  strings.write_string(out, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  strings.write_string(out, "<scxml xmlns=\"http://www.w3.org/2005/07/scxml\" version=\"1.0\" name=\"")
  xml_write_escaped(out, name)
  strings.write_string(out, "\" initial=\"")
  xml_write_value(out, chart.def.initial)
  strings.write_string(out, "\">\n")

  for parent_idx, state_idx in chart.parent_index {
    if parent_idx != INVALID_STATE_INDEX {
      continue
    }
    scxml_write_state(chart, State_Index(state_idx), out, 1)
  }

  strings.write_string(out, "</scxml>\n")
  return true
}

scxml_write_state :: proc(
  chart: ^Chart($State, $Trigger),
  state_idx: State_Index,
  out: ^strings.Builder,
  indent: int,
) {
  kind := effective_state_kind(chart, state_idx)
  if kind == .Final {
    scxml_write_indent(out, indent)
    strings.write_string(out, "<final id=\"")
    xml_write_value(out, chart.def.states[state_idx].id)
    strings.write_string(out, "\"/>\n")
    return
  }

  if kind == .And {
    scxml_write_indent(out, indent)
    strings.write_string(out, "<parallel id=\"")
    xml_write_value(out, chart.def.states[state_idx].id)
    strings.write_string(out, "\">\n")

    scxml_write_histories_for_state(chart, state_idx, out, indent + 1)

    owned_regions := chart.state_owned_region_ranges[state_idx]
    for offset in 0 ..< owned_regions.count {
      region_idx := chart.state_owned_region_indices[owned_regions.start + offset]
      if region_idx == INVALID_REGION_INDEX do continue
      scxml_write_region_state(chart, state_idx, region_idx, out, indent + 1)
    }

    scxml_write_transitions_for_state(chart, state_idx, out, indent + 1)
    scxml_write_indent(out, indent)
    strings.write_string(out, "</parallel>\n")
    return
  }

  has_children := state_has_child(chart, state_idx)
  has_transitions := chart.transition_ranges[state_idx].count > 0 || chart.always_transition_ranges[state_idx].count > 0
  has_histories := scxml_state_has_histories(chart, state_idx)

  scxml_write_indent(out, indent)
  strings.write_string(out, "<state id=\"")
  xml_write_value(out, chart.def.states[state_idx].id)
  strings.write_string(out, "\"")
  if has_children {
    initial_idx := chart.initial_index[state_idx]
    if initial_idx != INVALID_STATE_INDEX {
      strings.write_string(out, " initial=\"")
      xml_write_value(out, chart.def.states[initial_idx].id)
      strings.write_string(out, "\"")
    }
  }
  if !has_children && !has_transitions && !has_histories {
    strings.write_string(out, "/>\n")
    return
  }

  strings.write_string(out, ">\n")
  scxml_write_histories_for_state(chart, state_idx, out, indent + 1)

  for parent_idx, child_idx in chart.parent_index {
    if parent_idx == state_idx {
      scxml_write_state(chart, State_Index(child_idx), out, indent + 1)
    }
  }

  scxml_write_transitions_for_state(chart, state_idx, out, indent + 1)
  scxml_write_indent(out, indent)
  strings.write_string(out, "</state>\n")
}

scxml_write_region_state :: proc(
  chart: ^Chart($State, $Trigger),
  superstate_idx: State_Index,
  region_idx: Region_Index,
  out: ^strings.Builder,
  indent: int,
) {
  region := chart.regions[region_idx]
  scxml_write_indent(out, indent)
  strings.write_string(out, "<state id=\"")
  xml_write_value(out, chart.def.states[superstate_idx].id)
  strings.write_string(out, "__")
  if region.name != "" {
    xml_write_escaped(out, region.name)
  } else {
    fmt.sbprintf(out, "region_%d", int(region_idx))
  }
  strings.write_string(out, "\" initial=\"")
  xml_write_value(out, chart.def.states[region.initial].id)
  strings.write_string(out, "\">\n")

  for parent_idx, child_idx in chart.parent_index {
    if parent_idx != superstate_idx {
      continue
    }
    if chart.state_region_index[child_idx] == region_idx {
      scxml_write_state(chart, State_Index(child_idx), out, indent + 1)
    }
  }

  scxml_write_indent(out, indent)
  strings.write_string(out, "</state>\n")
}

scxml_write_histories_for_state :: proc(
  chart: ^Chart($State, $Trigger),
  state_idx: State_Index,
  out: ^strings.Builder,
  indent: int,
) {
  for history in chart.histories {
    if history.superstate != state_idx {
      continue
    }

    scxml_write_indent(out, indent)
    strings.write_string(out, "<history id=\"")
    xml_write_value(out, history.id)
    if history.kind == .Deep {
      strings.write_string(out, "\" type=\"deep\">\n")
    } else {
      strings.write_string(out, "\" type=\"shallow\">\n")
    }
    scxml_write_indent(out, indent + 1)
    strings.write_string(out, "<transition target=\"")
    xml_write_value(out, chart.def.states[history.fallback].id)
    strings.write_string(out, "\"/>\n")
    scxml_write_indent(out, indent)
    strings.write_string(out, "</history>\n")
  }
}

scxml_write_transitions_for_state :: proc(
  chart: ^Chart($State, $Trigger),
  state_idx: State_Index,
  out: ^strings.Builder,
  indent: int,
) {
  transition_range := chart.transition_ranges[state_idx]
  for offset in 0 ..< transition_range.count {
    transition_idx := chart.transition_indices[transition_range.start + offset]
    if transition_idx == INVALID_TRANSITION_INDEX do continue

    transition := chart.def.transitions[transition_idx]
    target_idx := chart.transition_target_indices[transition_idx]
    history_idx := chart.transition_target_history_indices[transition_idx]
    if target_idx == INVALID_STATE_INDEX && history_idx == INVALID_HISTORY_INDEX {
      continue
    }

    scxml_write_indent(out, indent)
    strings.write_string(out, "<transition event=\"")
    xml_write_value(out, transition.trigger)
    strings.write_string(out, "\" target=\"")
    if target_idx != INVALID_STATE_INDEX {
      xml_write_value(out, chart.def.states[target_idx].id)
    } else {
      xml_write_value(out, chart.histories[history_idx].id)
    }
    strings.write_string(out, "\"")
    if transition.kind == .Internal {
      strings.write_string(out, " type=\"internal\"")
    }
    strings.write_string(out, "/>\n")
  }

  always_range := chart.always_transition_ranges[state_idx]
  for offset in 0 ..< always_range.count {
    transition_idx := chart.always_transition_indices[always_range.start + offset]
    if transition_idx == INVALID_ALWAYS_INDEX do continue

    transition := chart.def.always_transitions[transition_idx]
    target_idx := chart.always_transition_target_indices[transition_idx]
    history_idx := chart.always_transition_target_history_indices[transition_idx]
    if target_idx == INVALID_STATE_INDEX && history_idx == INVALID_HISTORY_INDEX {
      continue
    }

    scxml_write_indent(out, indent)
    strings.write_string(out, "<transition target=\"")
    if target_idx != INVALID_STATE_INDEX {
      xml_write_value(out, chart.def.states[target_idx].id)
    } else {
      xml_write_value(out, chart.histories[history_idx].id)
    }
    strings.write_string(out, "\"")
    if transition.kind == .Internal {
      strings.write_string(out, " type=\"internal\"")
    }
    strings.write_string(out, "/>\n")
  }
}

scxml_state_has_histories :: proc(chart: ^Chart($State, $Trigger), state_idx: State_Index) -> bool {
  for history in chart.histories {
    if history.superstate == state_idx {
      return true
    }
  }
  return false
}

scxml_write_indent :: proc(out: ^strings.Builder, indent: int) {
  for _ in 0 ..< indent {
    strings.write_string(out, "  ")
  }
}

dot_write_value :: proc(out: ^strings.Builder, value: $T) {
  text := fmt.tprintf("%v", value)
  dot_write_escaped(out, text)
}

dot_write_escaped :: proc(out: ^strings.Builder, text: string) {
  for ch in text {
    if ch == '"' || ch == '\\' {
      strings.write_byte(out, '\\')
      strings.write_rune(out, ch)
    } else if ch == '\n' {
      strings.write_string(out, "\\n")
    } else {
      strings.write_rune(out, ch)
    }
  }
}

xml_write_value :: proc(out: ^strings.Builder, value: $T) {
  text := fmt.tprintf("%v", value)
  xml_write_escaped(out, text)
}

xml_write_escaped :: proc(out: ^strings.Builder, text: string) {
  for ch in text {
    switch ch {
    case '&':
      strings.write_string(out, "&amp;")
    case '<':
      strings.write_string(out, "&lt;")
    case '>':
      strings.write_string(out, "&gt;")
    case '"':
      strings.write_string(out, "&quot;")
    case '\'':
      strings.write_string(out, "&apos;")
      case:
      strings.write_rune(out, ch)
    }
  }
}
