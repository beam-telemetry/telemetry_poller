defmodule Telemetry.Poller.Application do
  @moduledoc false

  def start(_type, _args) do
    import Supervisor.Spec, only: [worker: 2]

    poller_opts = Application.get_env(:telemetry_poller, :default, [])

    children =
      if poller_opts do
        poller_opts =
          Keyword.merge([name: Telemetry.Poller.Default, vm_measurements: :default], poller_opts)

        [worker(Telemetry.Poller, [poller_opts])]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Telemetry.Poller.Supervisor)
  end
end
