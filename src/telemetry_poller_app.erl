%% @private
-module(telemetry_poller_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    PollerOpts = application:get_env(telemetry_poller, default, []),
    Default = #{
        name => telemetry_poller_default,
        measurements => [memory, total_run_queue_lengths, system_counts]
    },
    FinalOpts = maps:merge(Default, maps:from_list(PollerOpts)),
    telemetry_poller_sup:start_link(maps:to_list(FinalOpts)).

stop(_State) ->
    ok.
