%% @private
-module(telemetry_poller_sup).

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-define(SERVER, ?MODULE).

-spec start_link([supervisor:child_spec()]) -> {ok, pid()}.
start_link(PollerChildSpec) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, PollerChildSpec).

-spec init([supervisor:child_spec()]) -> {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init(PollerChildSpec) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 1,
                 period => 5},
    {ok, {SupFlags, PollerChildSpec}}.
