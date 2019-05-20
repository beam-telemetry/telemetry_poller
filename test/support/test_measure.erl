-module(test_measure).

-export([single_sample/3, raise/0]).

single_sample(Event, Measures, Metadata) ->
  telemetry:execute(Event, Measures, Metadata).

raise() ->
  erlang:raise(error, "I'm raising because I can!", [{?MODULE, raise, 0}]).