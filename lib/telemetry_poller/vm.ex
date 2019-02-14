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
        :erlang.statistics(:total_run_queue_lengths_all)
      end

    cpu =
      if otp_release < 20 do
        # Before OTP 20.0 there were only normal run queues.
        total
      else
        :erlang.statistics(:total_run_queue_lengths)
      end

    :telemetry.execute(
      [:vm, :total_run_queue_lengths],
      %{total: total, cpu: cpu, io: total - cpu},
      %{}
    )
  end
end
