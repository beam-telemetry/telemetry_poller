defmodule Telemetry.Poller.ApplicationTest do
  use ExUnit.Case, async: false

  import Telemetry.Poller.TestHelpers

  alias Telemetry.Poller

  setup_all do
    poller_opts = Application.get_env(:telemetry_poller, :default)

    on_exit fn ->
      Application.put_env(:telemetry_poller, :default, poller_opts)
      Application.ensure_all_started(:telemetry_poller)
    end

    :ok
  end

  setup do
    Application.stop(:telemetry_poller)
    :ok
  end

  test "default poller is started with preconfigured name and VM measurements" do
    poller = Telemetry.Poller.Default

    Application.delete_env(:telemetry_poller, :default)
    Application.ensure_all_started(:telemetry_poller)

    assert eventually(fn -> not is_nil(Process.whereis(poller)) end)
    measurements = Poller.list_measurements(Telemetry.Poller.Default)
    assert Enum.all?(measurements, fn {mod, _, _} -> mod == Telemetry.Poller.VM end)
  end

  test "default poller can be configured using application environment" do
    poller = MyPoller

    Application.put_env(
      :telemetry_poller,
      :default,
      name: poller,
      vm_measurements: [],
      measurements: []
    )

    Application.ensure_all_started(:telemetry_poller)

    assert eventually(fn -> not is_nil(Process.whereis(poller)) end)
    assert [] == Poller.list_measurements(poller)
  end

  test "default poller can be disabled using application environment" do
    Application.put_env(:telemetry_poller, :default, false)
    Application.ensure_all_started(:telemetry_poller)

    refute Process.whereis(Telemetry.Poller.Default)
  end
end
