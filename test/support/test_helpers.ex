defmodule Telemetry.Sampler.TestHelpers do
  alias Telemetry.Sampler.TestHandler

  @doc """
  Assert `Telemetry` event matching the given pattern has been dispatched.

  THe caller first needs to attach an event handler to selected events using `attach_to/1`.
  """
  defmacro assert_dispatched(event_pattern, value_pattern, metadata_pattern, timeout \\ 1_000) do
    quote do
      assert_receive {:event, unquote(event_pattern), unquote(value_pattern),
                      unquote(metadata_pattern)},
                     unquote(timeout),
                     """
                     Event matching the pattern has not been dispatched.
                     Make sure to attach a test event handler using `attach_to/1`.
                     """
    end
  end

  @doc """
  Attaches an event handler sending a message to the caller whenever one of the selected events is
  dispatched.

  After attaching a handler you can assert the event has been dispatched using `assert_dispatched/4`.
  """
  def attach_to_many(events) when is_list(events) do
    Telemetry.attach_many(make_ref(), events, TestHandler, :handle, %{caller: self()})
  end

  @doc """
  Attaches an event handler sending a message to the caller whenever specified event is dispatched.

  After attaching a handler you can assert the event has been dispatched using `assert_dispatched/4`.
  """
  def attach_to(event) do
    Telemetry.attach(make_ref(), event, TestHandler, :handle, %{caller: self()})
  end

  @doc """
  Invokes given function until it returns a truthy value.

  Function is invoked `retries` times at maximum, sleeping `sleep` milliseconds between each
  invokation.
  """
  def eventually(f, retries \\ 300, sleep \\ 100)
  def eventually(_, 0, _), do: false

  def eventually(f, retries, sleep) do
    result =
      try do
        f.()
      catch
        kind, reason ->
          ExUnit.Assertions.flunk("""
          Error while waiting for function to return truthy value:
          #{Exception.format(kind, reason, System.stacktrace())}
          """)

          false
      end

    unless result do
      Process.sleep(sleep)
      eventually(f, retries - 1, sleep)
    else
      result
    end
  end
end
