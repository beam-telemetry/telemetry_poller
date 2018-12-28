defmodule Telemetry.Poller.VM do
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

  @spec total_run_queue_lengths() :: :ok
  def total_run_queue_lengths() do
    {otp_release, _} = Integer.parse(System.otp_release())

    total =
      if otp_release < 20 do
        Enum.sum(:erlang.statistics(:run_queue_lengths))
      else
        :erlang.statistics(:total_run_queue_lengths)
      end

    Telemetry.execute(
      [:vm, :run_queue_lengths, :total],
      total,
      %{}
    )
  end

  @spec run_queue_lengths() :: :ok
  def run_queue_lengths() do
    individual_lengths = :erlang.statistics(:run_queue_lengths)
    normal_schedulers_count = :erlang.system_info(:schedulers)

    {normal_run_queue_lengths, dirty_run_queue_lengths} =
      Enum.split(individual_lengths, normal_schedulers_count)

    for {run_queue_length, scheduler_id} <- Enum.with_index(normal_run_queue_lengths, 1) do
      Telemetry.execute([:vm, :run_queue_lengths, :normal], run_queue_length, %{
        scheduler_id: scheduler_id
      })
    end

    case dirty_run_queue_lengths do
      [dirty_cpu_run_queue_length] ->
        Telemetry.execute([:vm, :run_queue_lengths, :dirty_cpu], dirty_cpu_run_queue_length)

      _ ->
        :ok
    end
  end
end
