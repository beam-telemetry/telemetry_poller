defmodule Telemetry.Poller.VMTest do
  use ExUnit.Case

  import Telemetry.Poller.TestHelpers

  alias Telemetry.Poller.VM

  test "memory/0 dispatches [:vm, :memory] event with memory measurements" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory],
                    %{
                      total: _,
                      processes: _,
                      processes_used: _,
                      system: _,
                      atom: _,
                      atom_used: _,
                      binary: _,
                      code: _,
                      ets: _
                    },
                    ^empty_metadata,
                    fn ->
                      VM.memory()
                    end
  end

  test "total_run_queue_lengths/0 dispatches [:vm, :run_queue_lengths, total] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :run_queue_lengths, :total], _, ^empty_metadata, fn ->
      VM.total_run_queue_lengths()
    end
  end

  test "run_queue_lengths/0 dispatches [:vm, :run_queue_lengths, :normal] event for each normal " <>
         "run queue" do
    normal_schedulers_count = :erlang.system_info(:schedulers)
    event = [:vm, :run_queue_lengths, :normal]
    handler_id = attach_to(event)

    VM.run_queue_lengths()

    for scheduler_id <- 1..normal_schedulers_count do
      metadata = %{scheduler_id: scheduler_id}
      assert_dispatched ^event, %{length: _}, ^metadata
    end

    :telemetry.detach(handler_id)
  end

  @tag :dirty_schedulers
  test "run_queue_lengths/0 dispatches a [:vm, :run_queue_lengths, :dirty_cpu] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :run_queue_lengths, :dirty_cpu], %{length: _}, ^empty_metadata, fn ->
      VM.run_queue_lengths()
    end
  end
end
