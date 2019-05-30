-module(telemetry_poller_vm).

-export([
  memory/0,
  total_run_queue_lengths/0
]).

-spec memory() -> ok.
memory() ->
  Measurements = erlang:memory(),
  telemetry:execute([vm, memory], maps:from_list(Measurements), #{}).

-spec total_run_queue_lengths() -> ok.
total_run_queue_lengths() ->
  Total = cpu_stats(total),
  CPU = cpu_stats(cpu),
  telemetry:execute([vm, total_run_queue_lengths], #{
    total => Total,
    cpu => CPU,
    io => Total - CPU},
    #{}).

-ifdef(OTP_RELEASE).
  -if(?OTP_RELEASE >= 20).
    -spec cpu_stats(total | cpu) -> non_neg_integer().
    cpu_stats(total) ->
      erlang:statistics(total_run_queue_lengths_all);
    cpu_stats(cpu) ->
      erlang:statistics(total_run_queue_lengths).
  -else.
    -spec cpu_stats(total | cpu) -> non_neg_integer().
    cpu_stats(_) ->
      lists:sum(erlang:statistics(run_queue_lengths)).
  -endif.
-endif.
