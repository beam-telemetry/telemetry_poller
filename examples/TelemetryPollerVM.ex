defmodule TelemetryPollerVM do
  def attach do
    Enum.each(
      [
        [:vm, :memory],
        [:vm, :total_run_queue_lengths],
        [:vm, :system_counts]
      ],
      fn [:vm, namespace] = event_name ->
        handler_id = "vm.#{Atom.to_string(namespace)}"

        :telemetry.attach(handler_id, event_name, &TelemetryPollerVM.handle/4, _config = [])
      end
    )
  end

  def handle(
        [:vm, :memory],
        event_measurements,
        _event_metadata,
        _handler_config
      ) do
    # Do something with the measurements
    IO.puts(
      "memory\n" <>
        "------\n" <>
        "  atom: #{event_measurements.atom}\n" <>
        "  atom_used: #{event_measurements.atom_used}\n" <>
        "  binary: #{event_measurements.binary}\n" <>
        "  code: #{event_measurements.code}\n" <>
        "  ets: #{event_measurements.ets}\n" <>
        "  processes: #{event_measurements.processes}\n" <>
        "  processes_used: #{event_measurements.processes_used}\n" <>
        "  system: #{event_measurements.system}\n" <>
        "  total: #{event_measurements.total}\n"
    )
  end

  def handle(
        [:vm, :total_run_queue_lengths],
        event_measurements,
        _event_metadata,
        _handler_config
      ) do
    # Do something with the measurements
    IO.puts(
      "total_run_queue_lengths\n" <>
        "-----------------------\n" <>
        "  cpu: #{event_measurements.cpu}\n" <>
        "  io: #{event_measurements.io}\n" <>
        "  total: #{event_measurements.total}\n"
    )
  end

  def handle(
        [:vm, :system_counts],
        event_measurements,
        _event_metadata,
        _handler_config
      ) do
    # Do something with the measurements
    IO.puts(
      "system_counts\n" <>
        "-------------\n" <>
        "  atom_count: #{event_measurements.atom_count}\n" <>
        "  port_count: #{event_measurements.port_count}\n" <>
        "  process_count: #{event_measurements.process_count}\n" <>
        "  atom_limit: #{event_measurements.atom_limit}\n" <>
        "  port_limit: #{event_measurements.port_limit}\n" <>
        "  process_limit: #{event_measurements.process_limit}\n"
    )
  end
end
