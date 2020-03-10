-module(telemetry_poller_builtin).

-export([
  memory/0,
  total_run_queue_lengths/0,
  system_counts/0,
  process_info/3
]).

-spec process_info([atom()], atom(), [atom()]) -> ok.
process_info(Event, Name, Measurements) ->
    case erlang:whereis(Name) of
        undefined -> ok;
        Pid ->
            case erlang:process_info(Pid, Measurements) of
                undefined -> ok;
                Info -> telemetry:execute(Event, maps:from_list(Info), #{name => Name})
            end
    end.

-spec memory() -> ok.
memory() ->
    Measurements = erlang:memory(),
    telemetry:execute([vm, memory], maps:from_list(Measurements), #{}).

-spec total_run_queue_lengths() -> ok.
total_run_queue_lengths() ->
    Total = erlang:statistics(total_run_queue_lengths_all),
    CPU = erlang:statistics(total_run_queue_lengths),
    telemetry:execute([vm, total_run_queue_lengths], #{
        total => Total,
        cpu => CPU,
        io => Total - CPU},
        #{}).

-spec system_counts() -> ok.
system_counts() ->
    ProcessCount = erlang:system_info(process_count),
    AtomCount = erlang:system_info(atom_count),
    PortCount = erlang:system_info(port_count),
    telemetry:execute([vm, system_counts], #{
        process_count => ProcessCount,
        atom_count => AtomCount,
        port_count => PortCount
    }).
