%% @private
-module(telemetry_poller_sup).

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link(Opts) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Opts).

init(Opts) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    PollerChildSpec = telemetry_poller:child_spec(Opts),
    {ok, {SupFlags, [PollerChildSpec]}}.
