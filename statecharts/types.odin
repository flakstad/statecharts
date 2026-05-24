package statecharts

Action :: proc(ctx: rawptr, event: rawptr)
Guard :: proc(ctx: rawptr, event: rawptr) -> bool

State_Index :: distinct int
Transition_Index :: distinct int
Always_Index :: distinct int
Region_Index :: distinct int
History_Index :: distinct int
Region_Handle :: distinct int

INVALID_STATE_INDEX :: State_Index(-1)
INVALID_TRANSITION_INDEX :: Transition_Index(-1)
INVALID_ALWAYS_INDEX :: Always_Index(-1)
INVALID_REGION_INDEX :: Region_Index(-1)
INVALID_HISTORY_INDEX :: History_Index(-1)
INVALID_REGION_HANDLE :: Region_Handle(-1)
HISTORY_SNAPSHOT_NO_REGION :: -1

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
  region: string,
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
  Local,
}

Transition_Def :: struct($State, $Trigger: typeid) {
  source: State,
  target: State,
  trigger: Trigger,

  kind: Transition_Kind,
  guard: Guard,
  action: Action,
}

Always_Def :: struct($State: typeid) {
  source: State,
  target: State,

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
  always_transitions: []Always_Def(State),
  done_events: []Done_Def(State, Trigger),
  after_events: []After_Def(State, Trigger),
}

Transition_Range :: struct {
  start: int,
  count: int,
}

Transition_Trigger_Range :: struct($Trigger: typeid) {
  trigger: Trigger,
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

Timer_Snapshot :: struct($State, $Trigger: typeid) {
  after_index: int,
  state: State,
  due_ms: u64,
  trigger: Trigger,
}

History_Snapshot :: struct($State: typeid) {
  history_index: int,
  superstate: State,
  kind: History_Kind,
  region_index: int,
  region_name: string,
  target: State,
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
  transition_trigger_group_ranges: [dynamic]Transition_Range,
  transition_trigger_ranges: [dynamic]Transition_Trigger_Range(Trigger),
  transition_trigger_indices: [dynamic]Transition_Index,
  transition_source_indices: [dynamic]State_Index,
  transition_target_indices: [dynamic]State_Index,
  transition_target_history_indices: [dynamic]History_Index,
  always_transition_ranges: [dynamic]Transition_Range,
  always_transition_indices: [dynamic]Always_Index,
  always_transition_source_indices: [dynamic]State_Index,
  always_transition_target_indices: [dynamic]State_Index,
  always_transition_target_history_indices: [dynamic]History_Index,
}

Compile_Options :: struct {
  allow_ambiguous_transitions: bool,
}

Init_Options :: struct {
  internal_event_capacity: int,
  active_leaf_capacity: int,
  trace_capacity: int,
  configuration_capacity: int,
  path_capacity: int,
  transition_scratch_capacity: int,
}

Instance :: struct($State, $Trigger: typeid) {
  chart: ^Chart(State, Trigger),
  active_leaf_indices: [dynamic]State_Index,
  history_indices: [dynamic]State_Index,
  deep_history_indices: [dynamic]State_Index,
  deep_history_region_indices: [dynamic]State_Index,
  internal_event_queue: [dynamic]Event(Trigger),
  after_events: [dynamic]Active_After(Trigger),
  current_time_ms: u64,
  conflict_first: Transition_Index,
  conflict_second: Transition_Index,
  preempted_transition: Transition_Index,
  preempted_by_transition: Transition_Index,

  exited_scratch: [dynamic]State,
  entered_scratch: [dynamic]State,
  configuration_scratch: [dynamic]State,
  path_scratch: [dynamic]State_Index,
  exit_index_scratch: [dynamic]State_Index,
  candidate_transition_scratch: [dynamic]Enabled_Transition,
  enabled_transition_scratch: [dynamic]Enabled_Transition,
  preemption_scratch: [dynamic]Preemption_Record,
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
  Internal_Transition_Target_Not_Source,
  Missing_Always_Source,
  Missing_Always_Target,
  Internal_Always_Target_Not_Source,
  Duplicate_Always,
  Missing_Done_State,
  Done_State_Not_Completable,
  Duplicate_Done,
  Missing_After_State,
  Duplicate_After,
  Ambiguous_Transition,
  Atomic_State_Has_Substates,
  Final_State_Has_Substates,
  Final_State_Has_Outgoing_Transition,
  And_State_Missing_Region,
  Duplicate_Region_Name,
  Missing_Substate_Region,
  Substate_Region_On_Non_And_State,
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
  Conflict,
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

Transition_Preemption :: struct($State: typeid) {
  preempted: Transition_Step(State),
  preempted_by: Transition_Step(State),
}

Transition_Preemption_Index :: struct {
  preempted: int,
  preempted_by: int,
}

Enabled_Transition :: struct {
  found: bool,
  blocked_by_guard: bool,
  leaf_index: State_Index,
  transition_index: Transition_Index,
}

Enabled_Always_Transition :: struct {
  found: bool,
  blocked_by_guard: bool,
  leaf_index: State_Index,
  transition_index: Always_Index,
}

Transition_Conflict :: struct {
  found: bool,
  first: Transition_Index,
  second: Transition_Index,
}

Always_Transition_Conflict :: struct {
  found: bool,
  first: Always_Index,
  second: Always_Index,
}

Preemption_Record :: struct {
  preempted: Transition_Index,
  preempted_by: Transition_Index,
}
