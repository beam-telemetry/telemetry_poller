-module(telemetry_poller_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() -> [
  accepts_name_opt,
  accepts_global_name_opt,
  can_configure_sampling_period,
  dispatches_custom_mfa,
  dispatches_memory,
  dispatches_process_info,
  dispatches_system_counts,
  dispatches_total_run_queue_lengths,
  doesnt_start_given_invalid_measurements,
  doesnt_start_given_invalid_period,
  measurements_can_be_listed,
  measurement_removed_if_it_raises,
  multiple_unnamed
].

init_per_suite(Config) ->
    application:ensure_all_started(telemetry_poller),
    Config.

end_per_suite(_Config) ->
    application:stop(telemetry_poller).

accepts_name_opt(_Config) ->
  Name = my_poller,
  {ok, Pid} = telemetry_poller:start_link([{name, Name}]),
  FoundPid = erlang:whereis(Name),
  FoundPid = Pid.

accepts_global_name_opt(_Config) ->
  Name = my_poller,
  {ok, Pid} = telemetry_poller:start_link([{name, {global, Name}}]),
  FoundPid = global:whereis_name(Name),
  FoundPid = Pid.

multiple_unnamed(_Config) ->
  {ok, _} = telemetry_poller:start_link([]),
  {ok, _} = telemetry_poller:start_link([]),
  ok.

can_configure_sampling_period(_Config) ->
  Period = 500,
  {ok, Pid} = telemetry_poller:start_link([{measurements, []}, {period, Period}]),
  State = sys:get_state(Pid),
  Period = maps:get(period, State).

doesnt_start_given_invalid_period(_Config) ->
  ?assertError({badarg, "Expected period to be a positive integer"},  telemetry_poller:start_link([{measurements, []}, {period, "1"}])).

doesnt_start_given_invalid_measurements(_Config) ->
  ?assertError({badarg, "Expected measurement " ++ _}, telemetry_poller:start_link([{measurements, [invalid_measurement]}])),
  ?assertError({badarg, "Expected measurements to be a list"}, telemetry_poller:start_link([{measurements, {}}])).

measurements_can_be_listed(_Config) ->
  Measurement1 = {telemetry_poller_builtin, memory, []},
  Measurement2 = {test_measure, single_sample, [{a, second, test, event}, #{sample => 1}, #{}]},
  {ok, Poller} = telemetry_poller:start_link([{measurements, [memory, Measurement2]},{period, 100}]),
  ?assertMatch([Measurement1, Measurement2], telemetry_poller:list_measurements(Poller)).

measurement_removed_if_it_raises(_Config) ->
  InvalidMeasurement = {test_measure, raise, []},
  {ok, Poller} = telemetry_poller:start_link([{measurements, [InvalidMeasurement]},{period, 100}]),
  ct:sleep(200),
  ?assert([] =:= telemetry_poller:list_measurements(Poller)).

dispatches_custom_mfa(_Config) ->
  Event = [a, test, event],
  Measurements = #{sample => 1},
  Metadata = #{some => "metadata"},
  Measurement = {test_measure, single_sample, [Event, Measurements, Metadata]},
  HandlerId = attach_to(Event),
  {ok, _Pid} = telemetry_poller:start_link([{measurements, [Measurement]},{period, 100}]),
  receive
      {event, Event, Measurements, Metadata} ->
          ok
  after
      1000 ->
          ct:fail(timeout_receive_echo)
  end,
  telemetry:detach(HandlerId).

dispatches_memory(_Config) ->
  {ok, _Poller} = telemetry_poller:start_link([{measurements, [memory]},{period, 100}]),
  HandlerId = attach_to([vm, memory]),
  receive
    {event, [vm, memory], #{total := _}, _} ->
      telemetry:detach(HandlerId),
      ?assert(true)
  after
      1000 ->
          ct:fail(timeout_receive_echo)
  end.

dispatches_total_run_queue_lengths(_Config) ->
  {ok, _Poller} = telemetry_poller:start_link([{measurements, [total_run_queue_lengths]},{period, 100}]),
  HandlerId = attach_to([vm, total_run_queue_lengths]),
  receive
    {event, [vm, total_run_queue_lengths], #{total := _, cpu := _, io := _}, _} ->
      telemetry:detach(HandlerId),
      ?assert(true)
  after
      1000 ->
          ct:fail(timeout_receive_echo)
  end.

-ifdef(OTP19).
    -define(system_counts_pattern, #{process_count := _, port_count := _}).
-else.
    -define(system_counts_pattern, #{process_count := _, atom_count := _, port_count := _}).
-endif.

dispatches_system_counts(_Config) ->
  {ok, _Poller} = telemetry_poller:start_link([{measurements, [system_counts]},{period, 100}]),
  HandlerId = attach_to([vm, system_counts]),
  receive
    {event, [vm, system_counts], ?system_counts_pattern, _} ->
      telemetry:detach(HandlerId),
      ?assert(true)
  after
      1000 ->
          ct:fail(timeout_receive_echo)
  end.

dispatches_process_info(_Config) ->
  ProcessInfo = [{name, user}, {event, [my_app, user]}, {keys, [memory, message_queue_len]}],
  {ok, _Poller} = telemetry_poller:start_link([{measurements, [{process_info, ProcessInfo}]},{period, 100}]),
  HandlerId = attach_to([my_app, user]),
  receive
    {event, [my_app, user], #{memory := _, message_queue_len := _}, #{name := user}} ->
      telemetry:detach(HandlerId),
      ?assert(true)
  after
      1000 ->
          ct:fail(timeout_receive_echo)
  end.

attach_to(Event) ->
  HandlerId = make_ref(),
  telemetry:attach(HandlerId, Event, fun test_handler:echo_event/4, #{caller => erlang:self()}),
  HandlerId.

