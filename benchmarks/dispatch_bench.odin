package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"

import sc "local:statecharts"

Bench_State :: enum {
  A,
  B,
}

Bench_Event :: enum {
  Tick,
  Raised,
  Timeout,
}

Wide_State :: enum {
  S00,
  S01,
  S02,
  S03,
  S04,
  S05,
  S06,
  S07,
  S08,
  S09,
  S10,
  S11,
  S12,
  S13,
  S14,
  S15,
  S16,
  S17,
  S18,
  S19,
  S20,
  S21,
  S22,
  S23,
  S24,
  S25,
  S26,
  S27,
  S28,
  S29,
  S30,
  S31,
}

Wide_Event :: enum {
  Tick,
}

bench_states := [?]sc.State_Def(Bench_State){
  {id = .A},
  {id = .B},
}

bench_transitions := [?]sc.Transition_Def(Bench_State, Bench_Event){
  {source = .A, target = .B, trigger = .Tick},
  {source = .B, target = .A, trigger = .Tick},
}

raise_bench_event :: proc(ctx: rawptr, event: rawptr) {
  ok := sc.raise(ctx, sc.Event(Bench_Event){id = .Raised})
  assert(ok)
}

bench_rtc_transitions := [?]sc.Transition_Def(Bench_State, Bench_Event){
  {source = .A, target = .B, trigger = .Tick, action = raise_bench_event},
  {source = .B, target = .A, trigger = .Raised},
}

bench_timer_transitions := [?]sc.Transition_Def(Bench_State, Bench_Event){
  {source = .A, target = .B, trigger = .Timeout},
  {source = .B, target = .A, trigger = .Timeout},
}

bench_after_events := [?]sc.After_Def(Bench_State, Bench_Event){
  {state = .A, delay_ms = 1, trigger = .Timeout},
  {state = .B, delay_ms = 1, trigger = .Timeout},
}

wide_states := [?]sc.State_Def(Wide_State){
  {id = .S00},
  {id = .S01},
  {id = .S02},
  {id = .S03},
  {id = .S04},
  {id = .S05},
  {id = .S06},
  {id = .S07},
  {id = .S08},
  {id = .S09},
  {id = .S10},
  {id = .S11},
  {id = .S12},
  {id = .S13},
  {id = .S14},
  {id = .S15},
  {id = .S16},
  {id = .S17},
  {id = .S18},
  {id = .S19},
  {id = .S20},
  {id = .S21},
  {id = .S22},
  {id = .S23},
  {id = .S24},
  {id = .S25},
  {id = .S26},
  {id = .S27},
  {id = .S28},
  {id = .S29},
  {id = .S30},
  {id = .S31},
}

wide_transitions := [?]sc.Transition_Def(Wide_State, Wide_Event){
  {source = .S00, target = .S01, trigger = .Tick},
  {source = .S01, target = .S02, trigger = .Tick},
  {source = .S02, target = .S03, trigger = .Tick},
  {source = .S03, target = .S04, trigger = .Tick},
  {source = .S04, target = .S05, trigger = .Tick},
  {source = .S05, target = .S06, trigger = .Tick},
  {source = .S06, target = .S07, trigger = .Tick},
  {source = .S07, target = .S08, trigger = .Tick},
  {source = .S08, target = .S09, trigger = .Tick},
  {source = .S09, target = .S10, trigger = .Tick},
  {source = .S10, target = .S11, trigger = .Tick},
  {source = .S11, target = .S12, trigger = .Tick},
  {source = .S12, target = .S13, trigger = .Tick},
  {source = .S13, target = .S14, trigger = .Tick},
  {source = .S14, target = .S15, trigger = .Tick},
  {source = .S15, target = .S16, trigger = .Tick},
  {source = .S16, target = .S17, trigger = .Tick},
  {source = .S17, target = .S18, trigger = .Tick},
  {source = .S18, target = .S19, trigger = .Tick},
  {source = .S19, target = .S20, trigger = .Tick},
  {source = .S20, target = .S21, trigger = .Tick},
  {source = .S21, target = .S22, trigger = .Tick},
  {source = .S22, target = .S23, trigger = .Tick},
  {source = .S23, target = .S24, trigger = .Tick},
  {source = .S24, target = .S25, trigger = .Tick},
  {source = .S25, target = .S26, trigger = .Tick},
  {source = .S26, target = .S27, trigger = .Tick},
  {source = .S27, target = .S28, trigger = .Tick},
  {source = .S28, target = .S29, trigger = .Tick},
  {source = .S29, target = .S30, trigger = .Tick},
  {source = .S30, target = .S31, trigger = .Tick},
  {source = .S31, target = .S00, trigger = .Tick},
}

Counting_Allocator :: struct {
  backing: runtime.Allocator,
  alloc_calls: int,
  resize_calls: int,
  free_calls: int,
  bytes_requested: int,
}

Bench_Sample :: struct {
  ns_total: i64,
  alloc_calls: int,
  resize_calls: int,
  free_calls: int,
  bytes_requested: int,
  checksum: int,
}

Bench_Summary :: struct {
  best: Bench_Sample,
  ns_total_sum: i64,
  alloc_calls_max: int,
  resize_calls_max: int,
  free_calls_max: int,
  bytes_requested_max: int,
  checksum: int,
}

Bench_Limit :: struct {
  label: string,
  max_best_ns: f64,
  max_avg_ns: f64,
  require_zero_allocs: bool,
}

counting_allocator :: proc(counter: ^Counting_Allocator) -> runtime.Allocator {
  return runtime.Allocator{
    procedure = counting_allocator_proc,
    data = counter,
  }
}

counting_allocator_proc :: proc(
  allocator_data: rawptr,
  mode: runtime.Allocator_Mode,
  size, alignment: int,
  old_memory: rawptr,
  old_size: int,
  location := #caller_location,
) -> ([]byte, runtime.Allocator_Error) {
  counter := cast(^Counting_Allocator)allocator_data
  #partial switch mode {
    case .Alloc, .Alloc_Non_Zeroed:
    counter.alloc_calls += 1
    counter.bytes_requested += size
    case .Resize, .Resize_Non_Zeroed:
    counter.resize_calls += 1
    counter.bytes_requested += size
    case .Free:
    counter.free_calls += 1
  }
  return counter.backing.procedure(
    counter.backing.data,
    mode,
    size,
    alignment,
    old_memory,
    old_size,
    location,
  )
}

setup_machine :: proc(chart: ^sc.Chart(Bench_State, Bench_Event), machine: ^sc.Instance(Bench_State, Bench_Event)) {
  chart_def := sc.Chart_Def(Bench_State, Bench_Event){
    initial = .A,
    states = bench_states[:],
    transitions = bench_transitions[:],
  }

  compile_result := sc.compile(chart, chart_def)
  defer sc.destroy_compile_result(&compile_result)
  assert(compile_result.ok)

  ok := sc.init(machine, chart)
  assert(ok)

  result := sc.enter_initial(machine)
  sc.destroy_dispatch_result(&result)
}

setup_rtc_machine :: proc(chart: ^sc.Chart(Bench_State, Bench_Event), machine: ^sc.Instance(Bench_State, Bench_Event)) {
  chart_def := sc.Chart_Def(Bench_State, Bench_Event){
    initial = .A,
    states = bench_states[:],
    transitions = bench_rtc_transitions[:],
  }

  compile_result := sc.compile(chart, chart_def)
  defer sc.destroy_compile_result(&compile_result)
  assert(compile_result.ok)

  ok := sc.init(machine, chart)
  assert(ok)

  result := sc.enter_initial(machine)
  sc.destroy_dispatch_result(&result)
}

setup_timer_machine :: proc(chart: ^sc.Chart(Bench_State, Bench_Event), machine: ^sc.Instance(Bench_State, Bench_Event)) {
  chart_def := sc.Chart_Def(Bench_State, Bench_Event){
    initial = .A,
    states = bench_states[:],
    transitions = bench_timer_transitions[:],
    after_events = bench_after_events[:],
  }

  compile_result := sc.compile(chart, chart_def)
  defer sc.destroy_compile_result(&compile_result)
  assert(compile_result.ok)

  ok := sc.init(machine, chart)
  assert(ok)

  result := sc.enter_initial_at(machine, 0)
  sc.destroy_dispatch_result(&result)
}

setup_wide_machine :: proc(chart: ^sc.Chart(Wide_State, Wide_Event), machine: ^sc.Instance(Wide_State, Wide_Event)) {
  chart_def := sc.Chart_Def(Wide_State, Wide_Event){
    initial = .S00,
    states = wide_states[:],
    transitions = wide_transitions[:],
  }

  compile_result := sc.compile(chart, chart_def)
  defer sc.destroy_compile_result(&compile_result)
  assert(compile_result.ok)

  ok := sc.init(machine, chart)
  assert(ok)

  result := sc.enter_initial(machine)
  sc.destroy_dispatch_result(&result)
}

run_scratch_dispatch :: proc(machine: ^sc.Instance(Bench_State, Bench_Event), iterations: int) -> int {
  checksum := 0
  event := sc.Event(Bench_Event){id = .Tick}
  for _ in 0 ..< iterations {
    result := sc.dispatch(machine, event)
    checksum += int(result.status)
    checksum += len(result.exited)
    checksum += len(result.entered)
    checksum += len(result.configuration)
    sc.destroy_dispatch_result(&result)
  }
  return checksum
}

run_allocating_trace_dispatch :: proc(machine: ^sc.Instance(Bench_State, Bench_Event), iterations: int) -> int {
  checksum := 0
  event := sc.Event(Bench_Event){id = .Tick}
  for _ in 0 ..< iterations {
    result := sc.dispatch(machine, event)
    exited := make([dynamic]Bench_State)
    entered := make([dynamic]Bench_State)
    configuration := make([dynamic]Bench_State)
    path := make([dynamic]Bench_State)

    for state in result.exited do append(&exited, state)
    for state in result.entered do append(&entered, state)
    for state in result.configuration do append(&configuration, state)
    for state in result.configuration do append(&path, state)

    checksum += int(result.status)
    checksum += len(exited)
    checksum += len(entered)
    checksum += len(configuration)
    checksum += len(path)

    delete(exited)
    delete(entered)
    delete(configuration)
    delete(path)
    sc.destroy_dispatch_result(&result)
  }
  return checksum
}

run_caller_trace_dispatch :: proc(
  machine: ^sc.Instance(Bench_State, Bench_Event),
  iterations: int,
  transitions: ^[dynamic]sc.Transition_Step(Bench_State),
) -> int {
  checksum := 0
  event := sc.Event(Bench_Event){id = .Tick}

  for _ in 0 ..< iterations {
    result := sc.dispatch_with_trace(machine, event, transitions)
    checksum += int(result.status)
    checksum += len(result.exited)
    checksum += len(result.entered)
    checksum += len(result.configuration)
    checksum += len(transitions^)
    sc.destroy_dispatch_result(&result)
  }
  return checksum
}

run_rtc_dispatch :: proc(machine: ^sc.Instance(Bench_State, Bench_Event), iterations: int) -> int {
  checksum := 0
  event := sc.Event(Bench_Event){id = .Tick}

  for _ in 0 ..< iterations {
    result := sc.dispatch_run_to_completion(machine, event)
    checksum += int(result.status)
    checksum += len(result.exited)
    checksum += len(result.entered)
    checksum += len(result.configuration)
    sc.destroy_dispatch_result(&result)
  }
  return checksum
}

run_due_dispatch :: proc(machine: ^sc.Instance(Bench_State, Bench_Event), iterations: int) -> int {
  checksum := 0
  for i in 1 ..= iterations {
    result := sc.dispatch_due_events(machine, u64(i))
    checksum += int(result.status)
    checksum += len(result.exited)
    checksum += len(result.entered)
    checksum += len(result.configuration)
    sc.destroy_dispatch_result(&result)
  }
  return checksum
}

run_wide_dispatch :: proc(machine: ^sc.Instance(Wide_State, Wide_Event), iterations: int) -> int {
  checksum := 0
  event := sc.Event(Wide_Event){id = .Tick}
  for _ in 0 ..< iterations {
    result := sc.dispatch(machine, event)
    checksum += int(result.status)
    checksum += len(result.exited)
    checksum += len(result.entered)
    checksum += len(result.configuration)
    sc.destroy_dispatch_result(&result)
  }
  return checksum
}

summarize_sample :: proc(summary: ^Bench_Summary, sample: Bench_Sample, sample_index: int) {
  if sample_index == 0 || sample.ns_total < summary.best.ns_total {
    summary.best = sample
  }
  summary.ns_total_sum += sample.ns_total
  if sample.alloc_calls > summary.alloc_calls_max do summary.alloc_calls_max = sample.alloc_calls
  if sample.resize_calls > summary.resize_calls_max do summary.resize_calls_max = sample.resize_calls
  if sample.free_calls > summary.free_calls_max do summary.free_calls_max = sample.free_calls
  if sample.bytes_requested > summary.bytes_requested_max do summary.bytes_requested_max = sample.bytes_requested
  summary.checksum += sample.checksum
}

print_summary :: proc(label: string, iterations: int, sample_count: int, summary: Bench_Summary) {
  best_ns_per_dispatch := sample_best_ns(summary, iterations)
  avg_ns_per_dispatch := sample_avg_ns(summary, iterations, sample_count)
  fmt.printf("%s\n", label)
  fmt.printf("  iterations/sample: %d\n", iterations)
  fmt.printf("  samples:           %d\n", sample_count)
  fmt.printf("  best ns/dispatch:  %.2f\n", best_ns_per_dispatch)
  fmt.printf("  avg ns/dispatch:   %.2f\n", avg_ns_per_dispatch)
  fmt.printf("  alloc calls max:   %d\n", summary.alloc_calls_max)
  fmt.printf("  resize calls max:  %d\n", summary.resize_calls_max)
  fmt.printf("  free calls max:    %d\n", summary.free_calls_max)
  fmt.printf("  bytes req max:     %d\n", summary.bytes_requested_max)
  fmt.printf("  checksum:          %d\n\n", summary.checksum)
}

sample_best_ns :: proc(summary: Bench_Summary, iterations: int) -> f64 {
  return f64(summary.best.ns_total) / f64(iterations)
}

sample_avg_ns :: proc(summary: Bench_Summary, iterations: int, sample_count: int) -> f64 {
  return f64(summary.ns_total_sum) / f64(iterations * sample_count)
}

check_limit :: proc(summary: Bench_Summary, iterations: int, sample_count: int, limit: Bench_Limit) -> bool {
  ok := true
  best_ns := sample_best_ns(summary, iterations)
  avg_ns := sample_avg_ns(summary, iterations, sample_count)

  if limit.max_best_ns > 0 && best_ns > limit.max_best_ns {
    fmt.printf(
      "REGRESSION: %s best %.2f ns exceeds %.2f ns\n",
      limit.label,
      best_ns,
      limit.max_best_ns,
    )
    ok = false
  }
  if limit.max_avg_ns > 0 && avg_ns > limit.max_avg_ns {
    fmt.printf(
      "REGRESSION: %s avg %.2f ns exceeds %.2f ns\n",
      limit.label,
      avg_ns,
      limit.max_avg_ns,
    )
    ok = false
  }
  if limit.require_zero_allocs &&
    (summary.alloc_calls_max != 0 || summary.resize_calls_max != 0 || summary.bytes_requested_max != 0) {
      fmt.printf(
	"REGRESSION: %s allocated: alloc=%d resize=%d bytes=%d\n",
	limit.label,
	summary.alloc_calls_max,
	summary.resize_calls_max,
	summary.bytes_requested_max,
      )
      ok = false
    }
  return ok
}

measure :: proc(
  label: string,
  iterations: int,
  sample_count: int,
  runner: proc(^sc.Instance(Bench_State, Bench_Event), int) -> int,
) -> Bench_Summary {
  chart: sc.Chart(Bench_State, Bench_Event)
  defer sc.destroy_chart(&chart)
  machine: sc.Instance(Bench_State, Bench_Event)
  defer sc.destroy_instance(&machine)
  setup_machine(&chart, &machine)

  summary := Bench_Summary{}
  for sample_index in 0 ..< sample_count {
    counter := Counting_Allocator{backing = context.allocator}
    old_allocator := context.allocator
    context.allocator = counting_allocator(&counter)

    start := time.tick_now()
    checksum := runner(&machine, iterations)
    duration := time.tick_diff(start, time.tick_now())

    context.allocator = old_allocator

    summarize_sample(&summary, Bench_Sample{
      ns_total = time.duration_nanoseconds(duration),
      alloc_calls = counter.alloc_calls,
      resize_calls = counter.resize_calls,
      free_calls = counter.free_calls,
      bytes_requested = counter.bytes_requested,
      checksum = checksum,
    }, sample_index)
  }

  print_summary(label, iterations, sample_count, summary)
  return summary
}

measure_trace :: proc(label: string, iterations: int, sample_count: int) -> Bench_Summary {
  chart: sc.Chart(Bench_State, Bench_Event)
  defer sc.destroy_chart(&chart)
  machine: sc.Instance(Bench_State, Bench_Event)
  defer sc.destroy_instance(&machine)
  setup_machine(&chart, &machine)

  transitions := make([dynamic]sc.Transition_Step(Bench_State), 0, 1)
  defer delete(transitions)

  summary := Bench_Summary{}
  for sample_index in 0 ..< sample_count {
    counter := Counting_Allocator{backing = context.allocator}
    old_allocator := context.allocator
    context.allocator = counting_allocator(&counter)

    start := time.tick_now()
    checksum := run_caller_trace_dispatch(&machine, iterations, &transitions)
    duration := time.tick_diff(start, time.tick_now())

    context.allocator = old_allocator

    summarize_sample(&summary, Bench_Sample{
      ns_total = time.duration_nanoseconds(duration),
      alloc_calls = counter.alloc_calls,
      resize_calls = counter.resize_calls,
      free_calls = counter.free_calls,
      bytes_requested = counter.bytes_requested,
      checksum = checksum,
    }, sample_index)
  }

  print_summary(label, iterations, sample_count, summary)
  return summary
}

measure_rtc :: proc(label: string, iterations: int, sample_count: int) -> Bench_Summary {
  chart: sc.Chart(Bench_State, Bench_Event)
  defer sc.destroy_chart(&chart)
  machine: sc.Instance(Bench_State, Bench_Event)
  defer sc.destroy_instance(&machine)
  setup_rtc_machine(&chart, &machine)

  summary := Bench_Summary{}
  for sample_index in 0 ..< sample_count {
    counter := Counting_Allocator{backing = context.allocator}
    old_allocator := context.allocator
    context.allocator = counting_allocator(&counter)

    start := time.tick_now()
    checksum := run_rtc_dispatch(&machine, iterations)
    duration := time.tick_diff(start, time.tick_now())

    context.allocator = old_allocator

    summarize_sample(&summary, Bench_Sample{
      ns_total = time.duration_nanoseconds(duration),
      alloc_calls = counter.alloc_calls,
      resize_calls = counter.resize_calls,
      free_calls = counter.free_calls,
      bytes_requested = counter.bytes_requested,
      checksum = checksum,
    }, sample_index)
  }

  print_summary(label, iterations, sample_count, summary)
  return summary
}

measure_due :: proc(label: string, iterations: int, sample_count: int) -> Bench_Summary {
  chart: sc.Chart(Bench_State, Bench_Event)
  defer sc.destroy_chart(&chart)

  summary := Bench_Summary{}
  for sample_index in 0 ..< sample_count {
    machine: sc.Instance(Bench_State, Bench_Event)
    setup_timer_machine(&chart, &machine)

    counter := Counting_Allocator{backing = context.allocator}
    old_allocator := context.allocator
    context.allocator = counting_allocator(&counter)

    start := time.tick_now()
    checksum := run_due_dispatch(&machine, iterations)
    duration := time.tick_diff(start, time.tick_now())

    context.allocator = old_allocator

    summarize_sample(&summary, Bench_Sample{
      ns_total = time.duration_nanoseconds(duration),
      alloc_calls = counter.alloc_calls,
      resize_calls = counter.resize_calls,
      free_calls = counter.free_calls,
      bytes_requested = counter.bytes_requested,
      checksum = checksum,
    }, sample_index)

    sc.destroy_instance(&machine)
  }

  print_summary(label, iterations, sample_count, summary)
  return summary
}

measure_wide :: proc(
  label: string,
  iterations: int,
  sample_count: int,
  runner: proc(^sc.Instance(Wide_State, Wide_Event), int) -> int,
) -> Bench_Summary {
  chart: sc.Chart(Wide_State, Wide_Event)
  defer sc.destroy_chart(&chart)
  machine: sc.Instance(Wide_State, Wide_Event)
  defer sc.destroy_instance(&machine)
  setup_wide_machine(&chart, &machine)

  summary := Bench_Summary{}
  for sample_index in 0 ..< sample_count {
    counter := Counting_Allocator{backing = context.allocator}
    old_allocator := context.allocator
    context.allocator = counting_allocator(&counter)

    start := time.tick_now()
    checksum := runner(&machine, iterations)
    duration := time.tick_diff(start, time.tick_now())

    context.allocator = old_allocator

    summarize_sample(&summary, Bench_Sample{
      ns_total = time.duration_nanoseconds(duration),
      alloc_calls = counter.alloc_calls,
      resize_calls = counter.resize_calls,
      free_calls = counter.free_calls,
      bytes_requested = counter.bytes_requested,
      checksum = checksum,
    }, sample_index)
  }

  print_summary(label, iterations, sample_count, summary)
  return summary
}

main :: proc() {
  iterations := 2_000_000
  samples := 5
  fmt.println("dispatch benchmark")
  fmt.println("note: allocating mode simulates the previous owned-result/path allocation model")
  fmt.println()

  scratch := measure("scratch-buffer dispatch", iterations, samples, run_scratch_dispatch)
  trace := measure_trace("caller-owned transition trace dispatch", iterations, samples)
  rtc := measure_rtc("run-to-completion dispatch with one raised event", iterations, samples)
  due := measure_due("due timer dispatch", iterations, samples)
  allocating := measure("allocating trace/path dispatch", iterations, samples, run_allocating_trace_dispatch)
  wide := measure_wide("wide transition lookup dispatch", iterations, samples, run_wide_dispatch)

  ok := true
  ok = check_limit(scratch, iterations, samples, Bench_Limit{
    label = "scratch-buffer dispatch",
    max_best_ns = 45,
    max_avg_ns = 55,
    require_zero_allocs = true,
  }) && ok
  ok = check_limit(trace, iterations, samples, Bench_Limit{
    label = "caller-owned transition trace dispatch",
    max_best_ns = 55,
    max_avg_ns = 65,
    require_zero_allocs = true,
  }) && ok
  ok = check_limit(rtc, iterations, samples, Bench_Limit{
    label = "run-to-completion dispatch with one raised event",
    max_best_ns = 115,
    max_avg_ns = 130,
    require_zero_allocs = true,
  }) && ok
  ok = check_limit(due, iterations, samples, Bench_Limit{
    label = "due timer dispatch",
    max_best_ns = 80,
    max_avg_ns = 95,
    require_zero_allocs = true,
  }) && ok
  ok = check_limit(wide, iterations, samples, Bench_Limit{
    label = "wide transition lookup dispatch",
    max_best_ns = 50,
    max_avg_ns = 60,
    require_zero_allocs = true,
  }) && ok

  _ = allocating
  if ok {
    fmt.println("benchmark guard: PASS")
  } else {
    fmt.println("benchmark guard: FAIL")
    os.exit(1)
  }
}
