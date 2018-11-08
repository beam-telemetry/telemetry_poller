defmodule Telemetry.Poller.ApplicationTest do
  use ExUnit.Case, async: false

  alias Telemetry.Poller

  setup do
    Application.stop(:telemetry_poller)

    on_exit fn ->
      Application.ensure_all_started(:telemetry_poller)
    end
  end

  test "default poller is started with preconfigured name" do
    Application.ensure_all_started(:telemetry_poller)

    assert Poller.list_measurements(Telemetry.Poller.Default)
  end

  test "default poller can be configured using application environment" do
    name = MyPoller

    Application.put_env(
      :telemetry_poller,
      :default,
      name: name,
      vm_measurements: [],
      measurements: []
    )

    Application.ensure_all_started(:telemetry_poller)

    assert [] == Poller.list_measurements(name)
  end

  test "default poller can be disabled using application environment" do
    Application.put_env(:telemetry_poller, :default, false)

    Application.ensure_all_started(:telemetry_poller)

    refute Process.whereis(Telemetry.Poller.Default)
  end
end
