defmodule Telemetry.Poller.VM do
  @moduledoc false

  @spec memory() :: :ok
  def memory() do
    measurements = :erlang.memory() |> Map.new()
    :telemetry.execute([:vm, :memory], measurements)
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

    :telemetry.execute(
      [:vm, :run_queue_lengths, :total],
      %{length: total},
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
      :telemetry.execute([:vm, :run_queue_lengths, :normal], %{length: run_queue_length}, %{
        scheduler_id: scheduler_id
      })
    end

    case dirty_run_queue_lengths do
      [dirty_cpu_run_queue_length] ->
        :telemetry.execute([:vm, :run_queue_lengths, :dirty_cpu], %{
          length: dirty_cpu_run_queue_length
        })

      _ ->
        :ok
    end
  end
end
