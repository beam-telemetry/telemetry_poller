defmodule Telemetry.Sampler.VM do
  @moduledoc false

  @spec memory() :: :ok
  def memory() do
    :erlang.memory()
    |> Enum.each(fn {type, size} ->
      Telemetry.execute([:vm, :memory], size, %{type: type})
    end)
  end
end
