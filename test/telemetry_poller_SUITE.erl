-module(telemetry_poller_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("stdlib/include/assert.hrl").

all() -> [
  accepts_mfa_for_dispatching_measurement_as_telemetry_event,
  accepts_name_opt,
  can_be_given_default_vm_measurements,
  can_be_given_default_list_of_vm_measurements,
  can_configure_sampling_period,
  default_vm_measurements_emit_as_expected,
  doesnt_start_given_invalid_measurements,
  doesnt_start_given_invalid_period,
  doesnt_start_given_invalid_vm_measurement,
  measurements_can_be_listed,
  measurement_removed_if_it_raises,
  registers_unique_vm_measurements
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

can_configure_sampling_period(_Config) ->
  Period = 500,
  {ok, Pid} = telemetry_poller:start_link([{measurements, []}, {period, Period}]),
  State = sys:get_state(Pid),
  Period = maps:get(period, State).

doesnt_start_given_invalid_period(_Config) ->
  ?assertError({badarg, "Expected period to be a positive integer"},  telemetry_poller:start_link([{measurements, []}, {period, "1"}])).

doesnt_start_given_invalid_measurements(_Config) ->
  ?assertError({badarg, "Expected measurement to be a valid MFA tuple"}, telemetry_poller:start_link([{measurements, [invalid_measurement]}])),
  ?assertError({badarg, "Expected measurements to be a list"}, telemetry_poller:start_link([{measurements, {}}])).

accepts_mfa_for_dispatching_measurement_as_telemetry_event(_Config) ->
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

measurements_can_be_listed(_Config) ->
  Measurement1 = {telemetry_poller_vm, memory, []},
  Measurement2 = {test_measure, single_sample, [{a, second, test, event}, #{sample => 1}, #{}]},
  {ok, Poller} = telemetry_poller:start_link([{measurements, [Measurement1, Measurement2]},{period, 100}]),
  ?assertMatch([Measurement1, Measurement2], telemetry_poller:list_measurements(Poller)).

measurement_removed_if_it_raises(_Config) ->
  InvalidMeasurement = {test_measure, raise, []},
  {ok, Poller} = telemetry_poller:start_link([{measurements, [InvalidMeasurement]},{period, 100}]),
  ct:sleep(200),
  ?assert([] =:= telemetry_poller:list_measurements(Poller)).

can_be_given_default_vm_measurements(_Config) ->
  MeasurementFuns = [memory, total_run_queue_lengths],
  {ok, Poller} = telemetry_poller:start_link([{vm_measurements, default}]),
  Measurements = telemetry_poller:list_measurements(Poller),
  ?assert(lists:all(fun(F) -> lists:member({telemetry_poller_vm, F, []}, Measurements) end, MeasurementFuns)).

can_be_given_default_list_of_vm_measurements(_Config) ->
  VMMeasurements = [memory, total_run_queue_lengths],
  {ok, Poller} = telemetry_poller:start_link([{vm_measurements,VMMeasurements}]),
  Measurements = telemetry_poller:list_measurements(Poller),
  ?assert(2 =:= erlang:length(Measurements)).

doesnt_start_given_invalid_vm_measurement(_Config) ->
  ?assertError({badarg, "The specified measurement is not currently supported. Consider implementing a custom measurement."}, telemetry_poller:start_link([{vm_measurements, [cpu_usage]}])).

registers_unique_vm_measurements(_Config) ->
  {ok, Poller} = telemetry_poller:start_link([{vm_measurements, [memory, memory]}]),
  ?assert(1 =:= erlang:length(telemetry_poller:list_measurements(Poller))).

default_vm_measurements_emit_as_expected(_Config) ->
  MemoryEvent = [vm, memory],
  RunQueueLengthsEvent = [vm, total_run_queue_lengths],
  {ok, _Poller} = telemetry_poller:start_link([{vm_measurements, default}, {period, 100}]),
  lists:foreach(fun(Event) ->
      HandlerId = attach_to(Event),
      receive
        {event, Event, Measurements, _} when is_map(Measurements) ->
          telemetry:detach(HandlerId),
          ?assert(true)
      after
          1000 ->
              ct:fail(timeout_receive_echo)
      end
    end,
  [MemoryEvent, RunQueueLengthsEvent]).

attach_to(Event) ->
  HandlerId = make_ref(),
  telemetry:attach(HandlerId, Event, fun test_handler:echo_event/4, #{caller => erlang:self()}),
  HandlerId.