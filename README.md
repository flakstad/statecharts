# statecharts

Deterministic Harel-style statecharts for Odin.

The package uses application-defined enum types for states and events, validates chart definitions up front, compiles them into dense runtime tables, and keeps dispatch allocation-free after initialization.

## Features

- Hierarchical states
- Orthogonal regions
- External, local, and internal transitions
- Guards, transition actions, entry actions, and exit actions
- Shallow and deep history
- Run-to-completion event raising
- Eventless `Always_Def` transitions
- Final states and typed done events
- Delayed events with application-owned time
- Active-state, history, and timer snapshot/restore helpers
- DOT and SCXML export

## Authoring API

The `*_Def` structs are still the engine data model. For hand-written charts,
the package also provides small constructors:

```odin
sc.on(Door_State.Closed, Door_Event.Open, Door_State.Open)
sc.internal(Door_State.Open, Door_Event.Close, close_action)
sc.after(Door_State.Open, 500, Door_Event.Close)
sc.define(Door_State.Closed, states[:], transitions[:])
```

Use `define_full` when a chart needs substates, regions, history, always
transitions, done events, or delayed events.

## Layout

- `statecharts/`: library package
- `showcases/`: runnable examples
- `SPEC.md`: API and semantics notes
- `ROADMAP.md`: current status and design notes
- `BENCHMARKS.md`: benchmark results and guard notes

## Minimal Example

```odin
package main

import sc "local:statecharts"

Door_State :: enum {
  Closed,
  Open,
}

Door_Event :: enum {
  Open,
  Close,
}

states := [?]sc.State_Def(Door_State){
  {id = .Closed},
  {id = .Open},
}

transitions := [?]sc.Transition_Def(Door_State, Door_Event){
  sc.on(Door_State.Closed, Door_Event.Open, Door_State.Open),
  sc.on(Door_State.Open, Door_Event.Close, Door_State.Closed),
}

main :: proc() {
  chart: sc.Chart(Door_State, Door_Event)
  chart_def := sc.define(Door_State.Closed, states[:], transitions[:])
  result := sc.compile(&chart, chart_def)
  defer sc.destroy_compile_result(&result)
  defer sc.destroy_chart(&chart)
  assert(result.ok)

  machine: sc.Instance(Door_State, Door_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  entry := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&entry)

  dispatch := sc.dispatch(&machine, sc.event(Door_Event.Open))
  sc.destroy_dispatch_result(&dispatch)
  assert(sc.is_active(&machine, Door_State.Open))
}
```

## Commands

Run tests:

```sh
odin test ./statecharts
odin test ./statecharts -vet-unused
```

Build the library:

```sh
odin build ./statecharts -build-mode:lib -out:/tmp/statecharts.a
```

Run a showcase:

```sh
odin run showcases/drone_operations -collection:local=.
```

Run all showcases:

```sh
for dir in showcases/*; do name=${dir##*/}; odin run "showcases/$name" -collection:local=. || exit 1; done
```

Run the benchmark guard:

```sh
odin run benchmarks/dispatch_bench.odin -file -collection:local=. -o:speed
```
