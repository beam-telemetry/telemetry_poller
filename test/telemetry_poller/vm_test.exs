defmodule Telemetry.Poller.VMTest do
  use ExUnit.Case

  import Telemetry.Poller.TestHelpers

  alias Telemetry.Poller.VM

  test "total_memory/0 dispatches [:vm, :memory, :total] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :total], _, ^empty_metadata, fn ->
      VM.total_memory()
    end
  end

  test "processes_memory/0 dispatches [:vm, :memory, :processes] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :processes], _, ^empty_metadata, fn ->
      VM.processes_memory()
    end
  end

  test "processes_used_memory/0 dispatches [:vm, :memory, :processes_used] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :processes_used], _, ^empty_metadata, fn ->
      VM.processes_used_memory()
    end
  end

  test "system_memory/0 dispatches [:vm, :memory, :system] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :system], _, ^empty_metadata, fn ->
      VM.system_memory()
    end
  end

  test "atom_memory/0 dispatches [:vm, :memory, :atom] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :atom], _, ^empty_metadata, fn ->
      VM.atom_memory()
    end
  end

  test "atom_used_memory/0 dispatches [:vm, :memory, :atom_used] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :atom_used], _, ^empty_metadata, fn ->
      VM.atom_used_memory()
    end
  end

  test "binary_memory/0 dispatches [:vm, :memory, :binary] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :binary], _, ^empty_metadata, fn ->
      VM.binary_memory()
    end
  end

  test "code_memory/0 dispatches [:vm, :memory, :code] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :code], _, ^empty_metadata, fn ->
      VM.code_memory()
    end
  end

  test "ets_memory/0 dispatches [:vm, :memory, :ets] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :memory, :ets], _, ^empty_metadata, fn ->
      VM.ets_memory()
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
      assert_dispatched ^event, _, ^metadata
    end

    Telemetry.detach(handler_id)
  end

  test "run_queue_lengths/0 dispatches a [:vm, :run_queue_lengths, :dirty_cpu] event with empty metadata" do
    empty_metadata = %{}

    assert_dispatch [:vm, :run_queue_lengths, :dirty_cpu], _, ^empty_metadata, fn ->
      VM.run_queue_lengths()
    end
  end
end
