defmodule Telemetry.SamplerTest do
  use ExUnit.Case

  import Telemetry.Sampler.TestHelpers

  alias Telemetry.Sampler

  defmodule TestMeasure do
    def single_value(value), do: value

    def single_sample(event, value, metadata),
      do: Telemetry.Sampler.sample(event, value, metadata)

    def multi_samples(events, value, metadata),
      do: Enum.map(events, &Telemetry.Sampler.sample(&1, value, metadata))
  end

  test "sampler can be given a name" do
    name = MySampler

    {:ok, pid} = Sampler.start_link(name: name)

    assert pid == Process.whereis(name)
  end

  test "sampler can have a sampling period configured" do
    event = [:a, :test, :event]
    value = 1
    spec = {event, {TestMeasure, :single_value, [value]}}
    period = 500

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [spec], period: period)

    ## We don't apply active wait here because we want to make sure that two events are dispatched
    ## *after* the period has passed, and not that at least two events are dispatched before one
    ## period passes.
    Process.sleep(period)
    assert_dispatched ^event, ^value, _
    assert_dispatched ^event, ^value, _
  end

  @tag :capture_log
  test "sampler doesn't start given invalid measurement spec" do
    assert_raise ArgumentError, fn ->
      Sampler.start(measurements: [:made_up_spec])
    end
  end

  @tag :capture_log
  test "sampler doesn't start given invalid period" do
    assert_raise ArgumentError, fn ->
      Sampler.start(period: "not a period")
    end
  end

  test "sampler can be given an MFA returning a single sample as measurement spec" do
    event = [:a, :test, :event]
    value = 1
    metadata = %{some: "metadata"}
    spec = {TestMeasure, :single_sample, [event, value, metadata]}

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [spec])

    assert_dispatched ^event, ^value, ^metadata
  end

  test "sampler can be given an MFA returning a list of samples as measurement spec" do
    event1 = [:a, :first, :test, :event]
    event2 = [:a, :second, :test, :event]
    value = 1
    metadata = %{some: "metadata"}
    spec = {TestMeasure, :multi_samples, [[event1, event2], value, metadata]}

    attach_to_many([event1, event2])
    {:ok, _} = Sampler.start_link(measurements: [spec])

    assert_dispatched ^event1, ^value, ^metadata
    assert_dispatched ^event2, ^value, ^metadata
  end

  test "sampler can be given an event name and an MFA returning a number as measurement spec" do
    event = [:a, :test, :event]
    value = 1
    empty_metadata = %{}
    spec = {event, {TestMeasure, :single_value, [value]}}

    attach_to(event)
    {:ok, _} = Sampler.start_link(measurements: [spec])

    assert_dispatched ^event, ^value, ^empty_metadata
  end

  test "sampler's measurement specs can be listed" do
    spec1 = {Telemetry.Sampler.VM, :memory, []}
    spec2 = {[:a, :first, :test, :event], {TestMeasure, :single_value, [1]}}
    spec3 = {TestMeasure, :single_sample, [[:a, :second, :test, :event], 1, %{}]}

    {:ok, sampler} = Sampler.start_link(measurements: [spec1, spec2, spec3])
    specs = Sampler.list_specs(sampler)

    assert spec1 in specs
    assert spec2 in specs
    assert spec3 in specs
    assert 3 == length(specs)
  end

  @tag :capture_log
  test "measurement spec is removed from sampler if it returns incorrect value" do
    invalid_specs = [
      {TestMeasure, :not_a_sample, []},
      {[:a, :test, :event], {TestMeasure, :not_a_number, []}}
    ]

    {:ok, sampler} = Sampler.start_link(measurements: invalid_specs)

    assert eventually(fn -> [] == Sampler.list_specs(sampler) end)
  end

  @tag :capture_log
  test "measurement spec is removed from sampler if it raises" do
    invalid_spec = {TestMeasure, :raise, []}

    {:ok, sampler} = Sampler.start_link(measurements: [invalid_spec])

    assert eventually(fn -> [] == Sampler.list_specs(sampler) end)
  end

  test "sampler can be started without linking" do
    {:ok, pid} = Sampler.start()

    assert {:links, []} == Process.info(self(), :links)

    Sampler.stop(pid)
  end

  test "sampler can be started under supervisor using the old-style child spec" do
    specs = [{Telemetry.Sampler.VM, :memory, []}]
    child_id = MySampler
    children = [Supervisor.Spec.worker(Sampler, [[measurements: specs]], id: child_id)]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    assert [{^child_id, sampler, :worker, [Sampler]}] = Supervisor.which_children(sup)
    assert specs == Sampler.list_specs(sampler)
  end

  @tag :elixir_1_5_child_specs
  test "sampler can be started under supervisor using the new-style child spec" do
    specs = [{Telemetry.Sampler.VM, :memory, []}]
    child_id = MySampler
    children = [Supervisor.child_spec({Sampler, measurements: specs}, id: child_id)]

    {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

    assert [{^child_id, sampler, :worker, [Sampler]}] = Supervisor.which_children(sup)
    assert specs == Sampler.list_specs(sampler)
  end
end
