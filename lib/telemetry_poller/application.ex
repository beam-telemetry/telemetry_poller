defmodule Telemetry.Poller.Application do
  @moduledoc false

  def start(_type, _args) do
    poller_opts = Application.get_env(:telemetry_poller, :default, [])

    children =
      if poller_opts do
        defaults = [name: Telemetry.Poller.Default, vm_measurements: :default]
        [{Telemetry.Poller, Keyword.merge(defaults, poller_opts)}]
      else
        []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: Telemetry.Poller.Supervisor)
  end
end
