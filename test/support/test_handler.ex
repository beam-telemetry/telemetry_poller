defmodule Telemetry.Sampler.TestHandler do
  @moduledoc false

  def handle(event, value, metadata, config) do
    message = {:event, event, value, metadata}
    send(config.caller, message)
  end
end
