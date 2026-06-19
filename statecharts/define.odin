package statecharts

substate :: proc "contextless" (substate: $State, superstate: State, region: string = "") -> Substate_Def(State) {
	return {substate = substate, superstate = superstate, region = region}
}

region :: proc "contextless" (name: string, superstate: $State, initial: State) -> Region_Def(State) {
	return {name = name, superstate = superstate, initial = initial}
}

initial :: proc "contextless" (superstate: $State, initial: State) -> Initial_Def(State) {
	return {superstate = superstate, initial = initial}
}

history :: proc "contextless" (
	id: $State,
	superstate: State,
	fallback: State,
	kind: History_Kind = .Shallow,
) -> History_Def(State) {
	return {id = id, superstate = superstate, fallback = fallback, kind = kind}
}

on :: proc "contextless" (
	source: $State,
	trigger: $Trigger,
	target: State,
	kind: Transition_Kind = .External,
	guard: Guard = nil,
	action: Action = nil,
) -> Transition_Def(State, Trigger) {
	return {
		source = source,
		target = target,
		trigger = trigger,
		kind = kind,
		guard = guard,
		action = action,
	}
}

internal :: proc "contextless" (
	source: $State,
	trigger: $Trigger,
	action: Action,
	guard: Guard = nil,
) -> Transition_Def(State, Trigger) {
	return on(source, trigger, source, .Internal, guard, action)
}

always :: proc "contextless" (
	source: $State,
	target: State,
	kind: Transition_Kind = .External,
	guard: Guard = nil,
	action: Action = nil,
) -> Always_Def(State) {
	return {source = source, target = target, kind = kind, guard = guard, action = action}
}

done :: proc "contextless" (state: $State, trigger: $Trigger) -> Done_Def(State, Trigger) {
	return {state = state, trigger = trigger}
}

after :: proc "contextless" (state: $State, delay_ms: u64, trigger: $Trigger) -> After_Def(State, Trigger) {
	return {state = state, delay_ms = delay_ms, trigger = trigger}
}

event :: proc "contextless" (id: $Trigger, data: rawptr = nil) -> Event(Trigger) {
	return {id = id, data = data}
}

define :: proc "contextless" (
	initial: $State,
	states: []State_Def(State),
	transitions: []Transition_Def(State, $Trigger),
) -> Chart_Def(State, Trigger) {
	return {
		initial = initial,
		states = states,
		transitions = transitions,
	}
}

define_full :: proc "contextless" (
	initial: $State,
	states: []State_Def(State),
	substates: []Substate_Def(State),
	regions: []Region_Def(State),
	initials: []Initial_Def(State),
	histories: []History_Def(State),
	transitions: []Transition_Def(State, $Trigger),
	always_transitions: []Always_Def(State),
	done_events: []Done_Def(State, Trigger),
	after_events: []After_Def(State, Trigger),
) -> Chart_Def(State, Trigger) {
	return {
		initial = initial,
		states = states,
		substates = substates,
		regions = regions,
		initials = initials,
		histories = histories,
		transitions = transitions,
		always_transitions = always_transitions,
		done_events = done_events,
		after_events = after_events,
	}
}
