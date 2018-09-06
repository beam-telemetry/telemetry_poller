defmodule Telemetry.Sampler.VM do
  @moduledoc false

  @spec total_memory() :: :ok
  def total_memory() do
    Telemetry.execute([:vm, :memory, :total], :erlang.memory(:total))
  end

  @spec processes_memory() :: :ok
  def processes_memory() do
    Telemetry.execute([:vm, :memory, :processes], :erlang.memory(:processes))
  end

  @spec processes_used_memory() :: :ok
  def processes_used_memory() do
    Telemetry.execute([:vm, :memory, :processes_used], :erlang.memory(:processes_used))
  end

  @spec system_memory() :: :ok
  def system_memory() do
    Telemetry.execute([:vm, :memory, :system], :erlang.memory(:system))
  end

  @spec atom_memory() :: :ok
  def atom_memory() do
    Telemetry.execute([:vm, :memory, :atom], :erlang.memory(:atom))
  end

  @spec atom_used_memory() :: :ok
  def atom_used_memory() do
    Telemetry.execute([:vm, :memory, :atom_used], :erlang.memory(:atom_used))
  end

  @spec binary_memory() :: :ok
  def binary_memory() do
    Telemetry.execute([:vm, :memory, :binary], :erlang.memory(:binary))
  end

  @spec code_memory() :: :ok
  def code_memory() do
    Telemetry.execute([:vm, :memory, :code], :erlang.memory(:code))
  end

  @spec ets_memory() :: :ok
  def ets_memory() do
    Telemetry.execute([:vm, :memory, :ets], :erlang.memory(:ets))
  end
end
