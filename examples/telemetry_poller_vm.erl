-module(telemetry_poller_vm).

-export([attach/0]).
-export([handle/4]).

attach() ->
    lists:foreach(
        fun([vm, Namespace] = EventName) ->
            NamespaceBin = atom_to_binary(Namespace),
            HandlerId = <<"vm.", NamespaceBin/binary>>,
            telemetry:attach(HandlerId, EventName, fun telemetry_poller_vm:handle/4, _Config = [])
        end,
        [
            [vm, memory],
            [vm, total_run_queue_lengths],
            [vm, system_counts]
        ]
    ).

handle([vm, memory], EventMeasurements, _EventMetadata, _HandlerConfig) ->
    #{
        atom := Atom,
        atom_used := AtomUser,
        binary := Binary,
        code := Code,
        ets := ETS,
        processes := Processes,
        processes_used := ProcessesUsed,
        system := System,
        total := Total
    } = EventMeasurements,
    % Do something with the measurements
    io:format(
        "memory~n"
        "------~n"
        "  atom: ~p~n"
        "  atom_used: ~p~n"
        "  binary: ~p~n"
        "  code: ~p~n"
        "  ets: ~p~n"
        "  processes: ~p~n"
        "  processes_used: ~p~n"
        "  system: ~p~n"
        "  total: ~p~n~n",
        [
            Atom,
            AtomUser,
            Binary,
            Code,
            ETS,
            Processes,
            ProcessesUsed,
            System,
            Total
        ]
    );
handle([vm, total_run_queue_lengths], EventMeasurements, _EventMetadata, _HandlerConfig) ->
    #{
        cpu := CPU,
        io := IO,
        total := Total
    } = EventMeasurements,
    % Do something with the measurements
    io:format(
        "total_run_queue_lengths~n"
        "-----------------------~n"
        "  cpu: ~p~n"
        "  io: ~p~n"
        "  total: ~p~n~n",
        [
            CPU,
            IO,
            Total
        ]
    );
handle([vm, system_counts], EventMeasurements, _EventMetadata, _HandlerConfig) ->
    #{
        atom_count := AtomCount,
        port_count := PortCount,
        process_count := ProcessCount,
        atom_limit := AtomLimit,
        port_limit := PortLimit,
        process_limit := ProcessLimit
    } = EventMeasurements,
    % Do something with the measurements
    io:format(
        "system_counts~n"
        "-------------~n"
        "  atom_count: ~p~n"
        "  port_count: ~p~n"
        "  process_count: ~p~n"
        "  atom_limit: ~p~n"
        "  port_limit: ~p~n"
        "  process_limit: ~p~n~n",
        [
            AtomCount,
            PortCount,
            ProcessCount,
            AtomLimit,
            PortLimit,
            ProcessLimit
        ]
    ).
