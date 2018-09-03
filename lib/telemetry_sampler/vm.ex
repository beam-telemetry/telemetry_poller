defmodule Telemetry.Sampler.VM do
  @moduledoc """
  Collection of functions dispatching `Telemetry` events with Erlang VM metrics.

  See documentation for `Telemetry.Sampler` to learn how to use these functions.
  """

  alias Telemetry.Sampler

  @doc """
  Dispatches events with amount of memory dynamically allocated by the VM.

  A single event is dispatched for each type of memory measured. Event name is always
  `[:vm, :memory]`. Event metadata includes only a single key, `:type`, which corresponds to the
  type of memory measured. Event value is the amount of memory of type given in metadata allocated
  by the VM, in bytes.

  The set of memory types may vary: see documentation for `:erlang.memory/0` to learn about possible
  values.
  """
  @spec memory() :: [Sampler.sample()]
  def memory() do
    :erlang.memory()
    |> Enum.map(fn {type, size} ->
      Telemetry.execute([:vm, :memory], size, %{type: type})
    end)
  end
end