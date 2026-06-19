# statecharts

Deterministic Harel-style statecharts for Odin.

Use it for state machines that need nested states, orthogonal regions, history,
delayed events, run-to-completion, snapshots, or exportable diagrams.

Charts are defined with typed tables, compiled once, and then dispatched at
runtime. After initialization, normal dispatch does not allocate.

## Example

```odin
package main

import sc "local:statecharts"

Door_State :: enum {Closed, Open}
Door_Event :: enum {Open, Close}

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
  compiled := sc.compile(&chart, sc.define(Door_State.Closed, states[:], transitions[:]))
  defer sc.destroy_compile_result(&compiled)
  defer sc.destroy_chart(&chart)
  assert(compiled.ok)

  machine: sc.Instance(Door_State, Door_Event)
  assert(sc.init(&machine, &chart))
  defer sc.destroy_instance(&machine)

  entry := sc.enter_initial(&machine)
  sc.destroy_dispatch_result(&entry)

  result := sc.dispatch(&machine, sc.event(Door_Event.Open))
  sc.destroy_dispatch_result(&result)
  assert(sc.is_active(&machine, Door_State.Open))
}
```

For larger charts, keep the same table style and add the pieces you need:
`substates`, `regions`, `histories`, `always_transitions`, `done_events`, and
`after_events`. Use `sc.define_full` when the chart needs those advanced tables.

## Kvist Authoring

The repo also includes `kvist-statecharts`, a Kvist layer over the same
Odin runtime:

```clojure
(import chart "..")

(chart.defchart door
  :state Door-State
  :event Door-Event
  :initial Closed
  :states [Closed Open Locked]
  :on [[Closed Open Open]
       [Open Close Closed]
       [Closed Lock Locked]
       [Locked Unlock Closed]])
```

The macro emits ordinary typed Odin tables. Runtime behavior is still the Odin
engine. See [kvist-statecharts/README.md](kvist-statecharts/README.md).

## Features

- Hierarchical `Or` states and orthogonal `And` regions
- External, local, and internal transitions
- Guards, transition actions, entry actions, and exit actions
- Shallow and deep history
- Run-to-completion event raising
- Final states and typed done events
- Delayed events with application-owned time
- Snapshot/restore helpers for active states, history, and timers
- DOT and SCXML export

## Layout

- `statecharts/` - Odin package
- `showcases/` - runnable examples
- `kvist-statecharts/` - Kvist authoring layer
- `SPEC.md` - semantics and API details
- `DRONE_EXAMPLE.md` - larger annotated example
- `BENCHMARKS.md` - benchmark commands and results

## Commands

```sh
odin test ./statecharts
odin test ./statecharts -vet-unused

odin run showcases/drone_operations -collection:local=.
for dir in showcases/*; do odin run "$dir" -collection:local=. || exit 1; done

odin run benchmarks/dispatch_bench.odin -file -collection:local=. -o:speed
```
