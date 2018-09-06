defmodule Telemetry.Sampler.VMTest do
  use ExUnit.Case

  import Telemetry.Sampler.TestHelpers

  alias Telemetry.Sampler.VM

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
end
