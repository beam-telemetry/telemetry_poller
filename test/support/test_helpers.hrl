-define(ASSERT_DISPATCH(Event, MeasurementsPattern, Timeout, Function),
(fun (__Event, __MeasurementsPattern, __Timeout, __Function) ->
  HandlerId = attach_to(__Event),
  __Function(),
  ?MODULE.?ASSERT_DISPATCHED(__Event, __MeasurementsPattern, __Timeout),
  telemetry:detach(HandlerId) end)(Event, MeasurementsPattern, Timeout, Function)).

-define(ASSERT_DISPATCHED(Event, MeasurementsPattern),(fun (__Event, __MeasurementsPattern) ->
  receive
        {event, Event, MeasurementsPattern, _} ->
            ok
    after
        1000 ->
            ct:fail(timeout_receive_echo)
    end)
end)(Event, MeasurementsPattern).

attach_to(Event) ->
  HandlerId = make_ref(),
  telemetry:attach(HandlerId, Event, fun test_handler:echo_event/4, #{caller => erlang:self()}),
  HandlerId.
