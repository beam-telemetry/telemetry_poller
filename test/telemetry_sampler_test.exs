defmodule Telemetry.SamplerTest do
  use ExUnit.Case

  import Telemetry.Sampler.TestHelpers

  alias Telemetry.Sampler

  defmodule TestMeasure do
    def single_sample(event, value, metadata \\ %{}),
      do: Telemetry.execute(event, value, metadata)

    def raise(), do: raise("I'm raising because I can!")
  end

  test "sampler can be given a name" do
    name = MySampler

    {:ok, pid} = Sampler.start_link(name: name)

    assert pid == Process.whereis(name)
  end

  test "sampler can have a sampling period configured" do
    event = [:a, :test, :event]
    value = 1
    measurement = {TestMeasure, :single_sample, [event, value]}
    period = 500

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [measurement], period: period)

    ## We don't apply active wait here because we want to make sure that two events are dispatched
    ## *after* the period has passed, and not that at least two events are dispatched before one
    ## period passes.
    Process.sleep(period)
    assert_dispatched ^event, ^value, _, 0
    assert_dispatched ^event, ^value, _, 100
  end

  @tag :capture_log
  test "sampler doesn't start given invalid measurement" do
    assert_raise ArgumentError, fn ->
      Sampler.start_link(measurements: [:invalid_measurement])
    end
  end

  @tag :capture_log
  test "sampler doesn't start given invalid period" do
    assert_raise ArgumentError, fn ->
      Sampler.start_link(period: "not a period")
    end
  end

  test "sampler can be given an MFA dispatching a Telemetry event as measurement" do
    event = [:a, :test, :event]
    value = 1
    metadata = %{some: "metadata"}
    measurement = {TestMeasure, :single_sample, [event, value, metadata]}

    assert_dispatch event, ^value, ^metadata, fn ->
      {:ok, _} = Sampler.start_link(measurements: [measurement])
    end
  end

  test "sampler's measurements can be listed" do
    measurement1 = {Telemetry.Sampler.VM, :memory, []}
    measurement2 = {TestMeasure, :single_sample, [[:a, :second, :test, :event], 1, %{}]}

    {:ok, sampler} = Sampler.start_link(measurements: [measurement1, measurement2])
    measurements = Sampler.list_measurements(sampler)

    assert measurement1 in measurements
    assert measurement2 in measurements
    assert 2 == length(measurements)
  end

  @tag :capture_log
  test "measurement is removed from sampler if it raises" do
    invalid_measurement = {TestMeasure, :raise, []}

    {:ok, sampler} = Sampler.start_link(measurements: [invalid_measurement])

    assert eventually(fn -> [] == Sampler.list_measurements(sampler) end)
  end

  test "sampler can be started under supervisor using the old-style child spec" do
    measurements = [{Telemetry.Sampler.VM, :memory, []}]
    child_id = MySampler
    children = [Supervisor.Spec.worker(Sampler, [[measurements: measurements]], id: child_id)]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    assert [{^child_id, sampler, :worker, [Sampler]}] = Supervisor.which_children(sup)
    assert measurements == Sampler.list_measurements(sampler)
  end

  @tag :elixir_1_5_child_specs
  test "sampler can be started under supervisor using the new-style child spec" do
    measurements = [{Telemetry.Sampler.VM, :memory, []}]
    child_id = MySampler
    children = [Supervisor.child_spec({Sampler, measurements: measurements}, id: child_id)]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    assert [{^child_id, sampler, :worker, [Sampler]}] = Supervisor.which_children(sup)
    assert measurements == Sampler.list_measurements(sampler)
  end

  describe "vm_measurements/1" do
    for memory_type <- [
          :total_memory,
          :processes_memory,
          :processes_used_memory,
          :system_memory,
          :atom_memory,
          :atom_used_memory,
          :binary_memory,
          :code_memory,
          :ets_memory
        ] do
      test "translates #{inspect(memory_type)} atom to measurement" do
        assert [{_, _, _}] = Sampler.vm_measurements([unquote(memory_type)])
      end
    end

    test "raises when given unknown VM measurement" do
      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements([:cpu_usage])
      end

      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements([{:message_queue_length, [MyProcess]}])
      end
    end

    test "returns unique measurements" do
      assert [{_, _, _}] = Sampler.vm_measurements([:total_memory, :total_memory])
    end
  end
end
