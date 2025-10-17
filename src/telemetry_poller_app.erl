%% @private
-module(telemetry_poller_app).

-behaviour(application).

-export([start/2, stop/1]).

-spec start(application:start_type(), term()) -> {ok, pid()}.
start(_StartType, _StartArgs) ->
    PollerChildSpec =
        case application:get_env(telemetry_poller, default, []) of
            false ->
                [];
            PollerOpts ->
                Default = #{
                            name => telemetry_poller_default,
                            measurements => [
                                memory,
                                total_run_queue_lengths,
                                system_counts,
                                persistent_term
                            ]
                           },
                FinalOpts = maps:to_list(maps:merge(Default, maps:from_list(PollerOpts))),
                [telemetry_poller:child_spec(FinalOpts)]
        end,
    telemetry_poller_sup:start_link(PollerChildSpec).

-spec stop(term()) -> ok.
stop(_State) ->
    ok.
