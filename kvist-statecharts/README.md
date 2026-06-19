# kvist-statecharts

Tiny Kvist authoring layer over the Odin `statecharts` package.

```clojure
(import chart "..")

(chart.defchart door
  :state Door-State
  :event Door-Event
  :initial Closed
  :states [Closed Open Locked]
  :on [[Closed Open Open]
       [Open Close Closed]])
```

`defchart` emits fixed top-level tables plus `door-chart` and `door-machine`
type aliases. Runtime work still goes through the Odin engine:

```clojure
(let [compiled: door-chart {}
      machine: door-machine {}]
  (let [compile-result (chart.compile! door compiled)]
    ...))
```

Run the example from the Kvist repo root for now:

```sh
./kvist run ../statecharts/kvist-statecharts/examples/door.kvist
```
