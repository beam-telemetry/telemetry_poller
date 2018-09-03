defmodule Telemetry.SamplerTest do
  use ExUnit.Case
  doctest Telemetry.Sampler, except: [:moduledoc]

  import Telemetry.Sampler.TestHelpers

  alias Telemetry.Sampler

  defmodule TestMeasure do
    def single_value(value), do: value

    def single_sample(event, value, metadata),
      do: Telemetry.execute(event, value, metadata)

    def not_a_number(), do: :not_a_number

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
    measurement = {event, {TestMeasure, :single_value, [value]}}
    period = 500

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [measurement], period: period)

    ## We don't apply active wait here because we want to make sure that two events are dispatched
    ## *after* the period has passed, and not that at least two events are dispatched before one
    ## period passes.
    Process.sleep(period)
    assert_dispatched ^event, ^value, _
    assert_dispatched ^event, ^value, _
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

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [measurement])

    assert_dispatched ^event, ^value, ^metadata
  end

  test "sampler can be given an event name and an MFA returning a number as measurement" do
    event = [:a, :test, :event]
    value = 1
    empty_metadata = %{}
    measurement = {event, {TestMeasure, :single_value, [value]}}

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [measurement])

    assert_dispatched ^event, ^value, ^empty_metadata
  end

  test "sampler's measurements can be listed" do
    measurement1 = {Telemetry.Sampler.VM, :memory, []}
    measurement2 = {[:a, :first, :test, :event], {TestMeasure, :single_value, [1]}}
    measurement3 = {TestMeasure, :single_sample, [[:a, :second, :test, :event], 1, %{}]}

    {:ok, sampler} = Sampler.start_link(measurements: [measurement1, measurement2, measurement3])
    measurements = Sampler.list_measurements(sampler)

    assert measurement1 in measurements
    assert measurement2 in measurements
    assert measurement3 in measurements
    assert 3 == length(measurements)
  end

  @tag :capture_log
  test "measurement is removed from sampler if it returns incorrect value" do
    invalid_measurements = [
      {[:a, :test, :event], {TestMeasure, :not_a_number, []}}
    ]

    {:ok, sampler} = Sampler.start_link(measurements: invalid_measurements)

    assert eventually(fn -> [] == Sampler.list_measurements(sampler) end)
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
    test "translates atom to measurement" do
      assert [{Sampler.VM, :memory, []}] == Sampler.vm_measurements([:memory])
    end

    test "translates tuple to measurement" do
      assert [
               {Sampler.VM, :memory, []},
               {Sampler.VM, :message_queue_length, [MyProcess]}
             ] == Sampler.vm_measurements([{:memory, []}, {:message_queue_length, [MyProcess]}])
    end

    test "raises if function name is not an atom" do
      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements(["memory"])
      end

      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements([{"message_queue_length", [MyProcess]}])
      end
    end

    test "raises if function arguments are not a list" do
      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements([{:message_queue_length, MyProcess}])
      end
    end

    test "raises if Telemetry.Sampler.VM doesn't export a function with given arity" do
      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements([{:memory, [:total]}])
      end

      assert_raise ArgumentError, fn ->
        Sampler.vm_measurements([{:message_queue_length, []}])
      end
    end

    test "returns unique measurements" do
      assert [{Sampler.VM, :memory, []}] == Sampler.vm_measurements([:memory, :memory])
    end
  end
end
