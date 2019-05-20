-module(telemetry_poller_vm).

-export([
  memory/0,
  total_run_queue_lengths/0
]).

-spec memory() -> ok.
memory() ->
  Measurements = erlang:memory(),
  telemetry:execute([vm, memory], maps:from_list(Measurements), #{}).

%% Need to figure out how to find OTP release version in erlang
-spec total_run_queue_lengths() -> ok.
total_run_queue_lengths() ->
  OTPRelease = otp_version(),
  Total = cpu_stats(total, OTPRelease),
  CPU = cpu_stats(cpu, OTPRelease),
  telemetry:execute([vm, total_run_queue_lengths], #{
    total => Total,
    cpu => CPU,
    io => Total - CPU},
    #{}).

-spec otp_version() -> non_neg_integer().
otp_version() ->
  __Version = erlang:system_info(otp_release),
  {Version, _} = string:to_integer(__Version),
  Version.

-spec cpu_stats(total | cpu, non_neg_integer()) -> non_neg_integer().
cpu_stats(total, OTPVersion) when OTPVersion < 20 ->
  lists:sum(erlang:statistics(run_queue_lengths));
cpu_stats(total, _) ->
  erlang:statistics(total_run_queue_lengths_all);
cpu_stats(cpu, OTPVersion) when OTPVersion < 20 ->
  lists:sum(erlang:statistics(run_queue_lengths));
cpu_stats(cpu, _) ->
  erlang:statistics(total_run_queue_lengths).
