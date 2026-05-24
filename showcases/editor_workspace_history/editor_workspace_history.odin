package main

import "core:fmt"

import sc "local:statecharts"

Editor_State :: enum {
  Workspace,
  Select,
  Draw,
  Clean,
  Dirty,
  Suspended,

  Workspace_History,
}

Editor_Event :: enum {
  Choose_Draw,
  Edit,
  Focus_Lost,
  Focus_Restored,
}

states := [?]sc.State_Def(Editor_State){
  {id = .Workspace, kind = .And},
  {id = .Select},
  {id = .Draw},
  {id = .Clean},
  {id = .Dirty},
  {id = .Suspended},
}

substates := [?]sc.Substate_Def(Editor_State){
  {substate = .Select, superstate = .Workspace, region = "tool"},
  {substate = .Draw, superstate = .Workspace, region = "tool"},
  {substate = .Clean, superstate = .Workspace, region = "document"},
  {substate = .Dirty, superstate = .Workspace, region = "document"},
}

regions := [?]sc.Region_Def(Editor_State){
  {name = "tool", superstate = .Workspace, initial = .Select},
  {name = "document", superstate = .Workspace, initial = .Clean},
}

histories := [?]sc.History_Def(Editor_State){
  {id = .Workspace_History, superstate = .Workspace, fallback = .Workspace, kind = .Deep},
}

transitions := [?]sc.Transition_Def(Editor_State, Editor_Event){
  {source = .Select, target = .Draw, trigger = .Choose_Draw},
  {source = .Clean, target = .Dirty, trigger = .Edit},
  {source = .Workspace, target = .Suspended, trigger = .Focus_Lost},
  {source = .Suspended, target = .Workspace_History, trigger = .Focus_Restored},
}

chart_def :: proc() -> sc.Chart_Def(Editor_State, Editor_Event) {
  return sc.Chart_Def(Editor_State, Editor_Event){
    initial = .Workspace,
    states = states[:],
    substates = substates[:],
    regions = regions[:],
    histories = histories[:],
    transitions = transitions[:],
  }
}

print_region :: proc(machine: ^sc.Instance(Editor_State, Editor_Event), label: string, region: string) {
  leaf, ok := sc.active_leaf_in_region(machine, Editor_State.Workspace, region)
  if ok {
    fmt.printf("%s: %v\n", label, leaf)
  }
}

print_workspace :: proc(machine: ^sc.Instance(Editor_State, Editor_Event), label: string) {
  fmt.println(label)
  print_region(machine, "tool", "tool")
  print_region(machine, "document", "document")
}

dispatch :: proc(machine: ^sc.Instance(Editor_State, Editor_Event), event: Editor_Event) {
  result := sc.dispatch(machine, sc.Event(Editor_Event){id = event})
  defer sc.destroy_dispatch_result(&result)
  fmt.printf("event: %v status: %v\n", event, result.status)
}

main :: proc() {
  chart: sc.Chart(Editor_State, Editor_Event)
  compile_result := sc.compile(&chart, chart_def())
  defer sc.destroy_compile_result(&compile_result)
  defer sc.destroy_chart(&chart)
  assert(compile_result.ok)

  machine: sc.Instance(Editor_State, Editor_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  result := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&result)
  print_workspace(&machine, "initial")

  dispatch(&machine, .Choose_Draw)
  dispatch(&machine, .Edit)
  print_workspace(&machine, "before suspend")

  dispatch(&machine, .Focus_Lost)
  fmt.printf("suspended: %v\n", sc.is_active(&machine, Editor_State.Suspended))

  persisted_leaves := make([dynamic]Editor_State, 0, 1)
  defer delete(persisted_leaves)
  persisted_history := make([dynamic]sc.History_Snapshot(Editor_State), 0, 2)
  defer delete(persisted_history)
  sc.active_leaves(&machine, &persisted_leaves)
  sc.active_history(&machine, &persisted_history)

  restored: sc.Instance(Editor_State, Editor_Event)
  ok = sc.init(&restored, &chart)
  defer sc.destroy_instance(&restored)
  assert(ok)
  assert(sc.restore_active_leaves(&restored, persisted_leaves[:]))
  assert(sc.restore_history(&restored, persisted_history[:]))

  dispatch(&restored, .Focus_Restored)
  print_workspace(&restored, "after restore")
}
