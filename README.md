# Telemetry.Poller

Allows to periodically collect measurements and dispatch them as Telemetry events.

Poller provides a convenient API for specifying functions called periodically to dispatch
measurements as Telemetry events. It also includes helpers for measuring Erlang virtual machine
metrics:

```elixir
# define custom function dispatching event with value you're interested in
defmodule ExampleApp.Measurements do
  def dispatch_session_count() do
    Telemetry.execute([:example_app, :session_count], ExampleApp.session_count())
  end
end

Telemetry.Poller.start_link(
  measurements: [
    # include custom measurement
    {ExampleApp.Measurements, :dispatch_session_count, []}
    # include default VM measurements
    | Telemetry.Poller.vm_measurements()
  ],
  period: 10_000 # configure sampling period
)
```

See [documentation](https://hexdocs.pm/telemetry_poller) for more concrete examples and usage
instructions.

## Copyright and License

Copyright (c) 2018, Chris McCord and Erlang Solutions.

Telemetry source code is licensed under the [Apache License, Version 2.0](LICENSE).
