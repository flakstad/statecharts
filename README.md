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
  {source = .Closed, target = .Open, trigger = .Open},
  {source = .Open, target = .Closed, trigger = .Close},
}

main :: proc() {
  chart: sc.Chart(Door_State, Door_Event)
  result := sc.compile(&chart, sc.Chart_Def(Door_State, Door_Event){
    initial = .Closed,
    states = states[:],
    transitions = transitions[:],
  })
  defer sc.destroy_compile_result(&result)
  defer sc.destroy_chart(&chart)
  assert(result.ok)

  machine: sc.Instance(Door_State, Door_Event)
  ok := sc.init(&machine, &chart)
  defer sc.destroy_instance(&machine)
  assert(ok)

  entry := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&entry)

  dispatch := sc.dispatch(&machine, sc.Event(Door_Event){id = .Open})
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
