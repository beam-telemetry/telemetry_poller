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

  test "total_run_queue_lengths/0 dispatches [:vm, :run_queue_lengths] event with total, cpu and io " <>
         "run queue lengths" do
    empty_metadata = %{}

    assert_dispatch [:vm, :total_run_queue_lengths], %{
      total: _,
      cpu: _,
      io: _
    }, ^empty_metadata, fn ->
      VM.total_run_queue_lengths()
    end
  end
end
