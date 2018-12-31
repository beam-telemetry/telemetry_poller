defmodule Telemetry.PollerTest do
  use ExUnit.Case

  import Telemetry.Poller.TestHelpers

  alias Telemetry.Poller

  defmodule TestMeasure do
    def single_sample(event, value, metadata \\ %{}),
      do: Telemetry.execute(event, value, metadata)

    def raise(), do: raise("I'm raising because I can!")
  end

  test "poller can be given a name" do
    name = MyPoller

    {:ok, pid} = Poller.start_link(name: name)

    assert pid == Process.whereis(name)
  end

  test "poller can have a sampling period configured" do
    event = [:a, :test, :event]
    value = 1
    measurement = {TestMeasure, :single_sample, [event, value]}
    period = 500

    attach_to(event)
    {:ok, _} = Poller.start_link(measurements: [measurement], period: period)

    ## We don't apply active wait here because we want to make sure that two events are dispatched
    ## *after* the period has passed, and not that at least two events are dispatched before one
    ## period passes.
    Process.sleep(period)
    assert_dispatched ^event, ^value, _, 0
    assert_dispatched ^event, ^value, _, 100
  end

  @tag :capture_log
  test "poller doesn't start given invalid measurement" do
    assert_raise ArgumentError, fn ->
      Poller.start_link(measurements: [:invalid_measurement])
    end
  end

  @tag :capture_log
  test "poller doesn't start given invalid period" do
    assert_raise ArgumentError, fn ->
      Poller.start_link(period: "not a period")
    end
  end

  test "poller can be given an MFA dispatching a Telemetry event as measurement" do
    event = [:a, :test, :event]
    value = 1
    metadata = %{some: "metadata"}
    measurement = {TestMeasure, :single_sample, [event, value, metadata]}

    assert_dispatch event, ^value, ^metadata, fn ->
      {:ok, _} = Poller.start_link(measurements: [measurement])
    end
  end

  test "poller's measurements can be listed" do
    measurement1 = {Telemetry.Poller.VM, :memory, []}
    measurement2 = {TestMeasure, :single_sample, [[:a, :second, :test, :event], 1, %{}]}

    {:ok, poller} = Poller.start_link(measurements: [measurement1, measurement2])

    measurements = Poller.list_measurements(poller)

    assert measurement1 in measurements
    assert measurement2 in measurements
    assert 2 == length(measurements)
  end

  @tag :capture_log
  test "measurement is removed from poller if it raises" do
    invalid_measurement = {TestMeasure, :raise, []}

    {:ok, poller} = Poller.start_link(measurements: [invalid_measurement])

    assert eventually(fn -> [] == Poller.list_measurements(poller) end)
  end

  test "poller can be started under supervisor using the old-style child spec" do
    measurement = {Telemetry.Poller.VM, :memory, []}
    child_id = MyPoller
    children = [Supervisor.child_spec({Poller, measurements: [measurement]}, id: child_id)]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    assert [{^child_id, poller, :worker, [Poller]}] = Supervisor.which_children(sup)
    assert measurement in Poller.list_measurements(poller)
  end

  @tag :elixir_1_5_child_specs
  test "poller can be started under supervisor using the new-style child spec" do
    measurement = {Telemetry.Poller.VM, :memory, []}
    child_id = MyPoller
    children = [Supervisor.child_spec({Poller, measurements: [measurement]}, id: child_id)]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    assert [{^child_id, poller, :worker, [Poller]}] = Supervisor.which_children(sup)
    assert measurement in Poller.list_measurements(poller)
  end

  test "poller can be given :default VM measurements" do
    measurement_funs = [
      :total_memory,
      :processes_memory,
      :processes_used_memory,
      :ets_memory,
      :binary_memory,
      :total_run_queue_lengths
    ]

    {:ok, poller} = Poller.start_link(vm_measurements: :default)
    measurements = Poller.list_measurements(poller)

    assert length(measurement_funs) == length(measurements)

    for measurement_fun <- measurement_funs do
      assert {Telemetry.Poller.VM, measurement_fun, []} in measurements
    end
  end

  test "poller can be given a list of VM measurements" do
    vm_measurements = [
      :total_memory,
      :processes_memory,
      :processes_used_memory,
      :system_memory,
      :atom_memory,
      :atom_used_memory,
      :binary_memory,
      :code_memory,
      :ets_memory,
      :total_run_queue_lengths,
      :run_queue_lengths
    ]

    {:ok, poller} = Poller.start_link(vm_measurements: vm_measurements)

    assert length(vm_measurements) == length(Poller.list_measurements(poller))
  end

  @tag :capture_log
  test "poller doesn't start given invalid VM measurement" do
    assert_raise ArgumentError, fn ->
      Poller.start_link(vm_measurements: [:cpu_usage])
    end
  end

  test "poller registers unique VM measurements" do
    {:ok, poller} = Poller.start_link(vm_measurements: [:total_memory, :total_memory])

    assert 1 == length(Poller.list_measurements(poller))
  end
end
