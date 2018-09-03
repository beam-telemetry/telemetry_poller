defmodule Telemetry.Sampler.VM do
  @moduledoc """
  Collection of functions dispatching `Telemetry` events with Erlang VM metrics.

  See documentation for `Telemetry.Sampler` to learn how to use these functions.
  """

  @doc """
  Dispatches events with amount of memory dynamically allocated by the VM.

  A single event is dispatched for each type of memory measured. Event name is always
  `[:vm, :memory]`. Event metadata includes only a single key, `:type`, which corresponds to the
  type of memory measured. Event value is the amount of memory of type given in metadata allocated
  by the VM, in bytes.

  The set of memory types may vary: see documentation for `:erlang.memory/0` to learn about possible
  values.
  """
  @spec memory() :: :ok
  def memory() do
    :erlang.memory()
    |> Enum.each(fn {type, size} ->
      Telemetry.execute([:vm, :memory], size, %{type: type})
    end)
  end

  @doc """
  Dispatches an event with message queue length of the given process.

  `process` can be a pid, atom, `{:global, term}` tuple or `{:via, module, term}` tuple. The event
  is not dispatched if the `process`'s pid can't be resolved or the pid is not alive.

  Event name is `[:vm, :message_queue_length]`. Event value is the measured message queue length.
  Event metadata includes two keys: `:process`, which maps to `process` argument given to this
  function, and `:pid`, which maps to the pid of the `process`.
  """
  @spec message_queue_length(pid() | atom() | {:global, term()} | {:via, module(), term()}) :: :ok
  def message_queue_length(process) do
    with {:ok, pid} <- resolve_pid(process),
         {:message_queue_len, message_queue_length} <- Process.info(pid, :message_queue_len) do
      metadata = %{process: process, pid: pid}
      Telemetry.execute([:vm, :message_queue_length], message_queue_length, metadata)
    else
      _ ->
        :ok
    end
  end

  ## Helpers

  @spec resolve_pid(pid() | atom() | {:global, term()} | {:via, module(), term()}) ::
          {:ok, pid()} | :error
  defp resolve_pid(process) when is_pid(process) do
    {:ok, process}
  end

  defp resolve_pid(process) do
    case GenServer.whereis(process) do
      pid when is_pid(pid) ->
        {:ok, pid}

      _ ->
        :error
    end
  end
end
