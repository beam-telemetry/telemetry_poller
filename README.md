# Telemetry.Poller

[![CircleCI](https://circleci.com/gh/beam-telemetry/telemetry_poller.svg?style=svg)](https://circleci.com/gh/beam-telemetry/telemetry_poller)
[![Codecov](https://codecov.io/gh/beam-telemetry/telemetry_poller/branch/master/graphs/badge.svg)](https://codecov.io/gh/beam-telemetry/telemetry_poller/branch/master/graphs/badge.svg)

Allows to periodically collect measurements and dispatch them as Telemetry events.

`Telemetry.Poller` by default runs a poller to perform VM measurements:

  * `[:vm, :memory]` - contains the total memory, process memory, and all other keys in `:erlang.memory/0`
  * `[:vm, :total_run_queue_lengths]` - returns the run queue lengths for CPU and IO schedulers, as well as total

You can directly subscribe to those events after adding `:telemetry_poller` as a dependency.

Poller also provides a convenient API for running custom pollers. You only need to specify which functions are called periodically to dispatch measurements as Telemetry events:

```elixir
# define custom function dispatching event with value you're interested in
defmodule ExampleApp.Measurements do
  def dispatch_session_count() do
    :telemetry.execute([:example_app, :session_count], ExampleApp.session_count())
  end
end

Telemetry.Poller.start_link(
  # include custom measurement
  measurements: [
    {ExampleApp.Measurements, :dispatch_session_count, []}
  ],
  period: 10_000 # configure sampling period
)
```

See [documentation](https://hexdocs.pm/telemetry_poller/) for more concrete examples and usage
instructions.

## Copyright and License

Copyright (c) 2018, Chris McCord and Erlang Solutions.

Telemetry source code is licensed under the [Apache License, Version 2.0](LICENSE).
