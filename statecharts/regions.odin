package statecharts

import "core:fmt"
import "core:strings"

Typed_Region_Def :: struct($State, $Region: typeid) {
  id: Region,
  superstate: State,
  initial: State,
}

Region_Substate_Def :: struct($State, $Region: typeid) {
  substate: State,
  region: Region,
}

typed_region_name :: proc(region: $Region) -> string {
  return fmt.tprintf("%v", region)
}

append_typed_region_defs :: proc(
  out: ^[dynamic]Region_Def($State),
  regions: []Typed_Region_Def(State, $Region),
) -> bool {
  if out == nil {
    return false
  }

  for region, i in regions {
    for other in regions[:i] {
      if region.id == other.id {
	return false
      }
    }
  }

  for region in regions {
    append(out, Region_Def(State){
      name = strings.clone(typed_region_name(region.id)),
      superstate = region.superstate,
      initial = region.initial,
    })
  }

  return true
}

append_typed_region_substate_defs :: proc(
  out: ^[dynamic]Substate_Def($State),
  regions: []Typed_Region_Def(State, $Region),
  substates: []Region_Substate_Def(State, Region),
) -> bool {
  if out == nil {
    return false
  }

  for region, i in regions {
    for other in regions[:i] {
      if region.id == other.id {
	return false
      }
    }
  }

  for substate in substates {
    _, ok := typed_region_def(regions, substate.region)
    if !ok {
      return false
    }
  }

  for substate in substates {
    region, _ := typed_region_def(regions, substate.region)
    append(out, Substate_Def(State){
      substate = substate.substate,
      superstate = region.superstate,
      region = strings.clone(typed_region_name(region.id)),
    })
  }

  return true
}

destroy_typed_region_defs :: proc(regions: ^[dynamic]Region_Def($State)) {
  if regions == nil || regions^ == nil {
    return
  }
  for region in regions^ {
    if region.name != "" {
      delete(region.name)
    }
  }
  delete(regions^)
  regions^ = nil
}

destroy_typed_region_substate_defs :: proc(substates: ^[dynamic]Substate_Def($State)) {
  if substates == nil || substates^ == nil {
    return
  }
  for substate in substates^ {
    if substate.region != "" {
      delete(substate.region)
    }
  }
  delete(substates^)
  substates^ = nil
}

typed_region_handle :: proc(
  chart: ^Chart($State, $Trigger),
  superstate: State,
  region: $Region,
) -> (Region_Handle, bool) {
  return region_handle(chart, superstate, typed_region_name(region))
}

active_leaf_in_typed_region :: proc(
  instance: ^Instance($State, $Trigger),
  superstate: State,
  region: $Region,
) -> (State, bool) {
  return active_leaf_in_region(instance, superstate, typed_region_name(region))
}

typed_region_def :: proc(
  regions: []Typed_Region_Def($State, $Region),
  id: Region,
) -> (Typed_Region_Def(State, Region), bool) {
  for region in regions {
    if region.id == id {
      return region, true
    }
  }
  return {}, false
}
