-module(test_handler).

-export([echo_event/4]).

echo_event(Event, Measurements, Metadata, Config) ->
  erlang:send(maps:get(caller, Config), {event, Event, Measurements, Metadata}).