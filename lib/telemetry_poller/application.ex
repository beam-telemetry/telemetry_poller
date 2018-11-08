defmodule Telemetry.Poller.Application do
  @moduledoc false

  def start(_type, _args) do
    import Supervisor.Spec, only: [worker: 2]

    default_poller_opts =
      Application.get_env(:telemetry_poller, :default, name: Telemetry.Poller.Default)

    children =
      if default_poller_opts do
        [worker(Telemetry.Poller, [default_poller_opts])]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Telemetry.Poller.Supervisor)
  end
end
