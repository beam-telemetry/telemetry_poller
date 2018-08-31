defmodule Telemetry.Sampler do
  @moduledoc """
  Allows to periodically collect measurements and publish them as `Telemetry` events.

  ## Measurement specifications

  Measurement specifications (later "specs") describe how the measurement should be performed and
  what event should be emitted once the mesured value is collected. There are two possible values
  for measurement spec:

  1. An MFA tuple returning a single sample or a list of samples. Sample is an opaque data structure
     which consists of event name, collected measurement value and event metadata. Samples can
     be constructed using the `sample/3` function. Sampler will dispatch a `Telemetry` event
     for each sample returned by the MFA invokation.
  2. A tuple, where the first element is event name and the second element is an MFA returning a
     *number*. In this case, Sampler will dispatch an event with given name and value returned
     by the MFA invokation; event metadata will be always empty.

  If the invokation of MFA returns an invalid value (i.e. it should return a sample but doesn't,
  or it should return a number but doesn't), the spec is removed from the list and the error
  is logged.

  ## Starting and stopping

  You can start the Sampler using the `start_link/1` function. Sampler can be alaso started as a
  part of your supervision tree, using both the old-style and the new-style child specifications:

      # pre Elixir 1.5.0
      children = [Supervisor.Spec.worker(Telemetry.Sampler, [[period: 5000]])]

      # post Elixir 1.5.0
      children = [{Telemetry.Sampler, [period: 5000]}]

      Supervisor.start_link(children, [strategy: :one_for_one]

  You can start as many Samplers as you wish, but generally you shouldn't need to do it, unless
  you know that it's not keeping up with collecting all specified measurements.

  Measurement specs need to be provided via `:measurements` option.

  ## VM measurements

  See `Telemetry.Sampler.VM` module for functions which can be used as measurement specs for
  metrics related to the Erlang virtual machine.
  """

  use GenServer

  require Logger

  @default_period 10_000

  @type t :: GenServer.server()
  @type options :: [option()]
  @type option ::
          {:name, GenServer.name()}
          | {:period, period()}
          | {:measurements, [measurement_spec()]}
  @type period :: pos_integer()
  @type measurement_spec :: mfa() | {Telemetry.event_name(), mfa()}
  @opaque sample() ::
            {:sample, Telemetry.event_name(), Telemetry.event_value(), Telemetry.event_metadata()}

  ## API
  @doc """
  Returns a child specifiction for Sampler.

  It accepts `t:options/0` as an argument, meaning that it's valid to start it under the supervisor
  as follows:

      alias Telemetry.Sampler
      # use default options
      Supervisor.start_link([Sampler], supervisor_opts) # use default options
      # customize options
      Supervisor.start_link([{Sampler, period: 10_000}], supervisor_opts)
      # modify the child spec
      Supervisor.start_link(Supervisor.child_spec(Sampler, id: MySampler), supervisor_opts)
  """
  # Uncomment when dropping support for 1.4.x releases.
  # @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(term)

  def child_spec(options) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [options]}
    }
  end

  @doc """
  Starts a Sampler linked to the calling process.

  Useful for starting Samplers as a part of a supervision tree.

  ### Options

  * `:measurements` - a list of measurements specs used by Sampler. For description of possible values
    see "Measurement specifications" section of `Sampler` module documentation;
  * `:period` - time period before performing the same measurement again, in milliseconds. Default
    value is #{@default_period} ms;
  * `:name` - the name of the Sampler process. See "Name Registragion" section of `GenServer`
    documentation for information about allowed values.
  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options \\ []) when is_list(options) do
    {sampler_opts, gen_server_opts} = parse_options!(options)
    GenServer.start_link(__MODULE__, sampler_opts, gen_server_opts)
  end

  @doc """
  Stops the `sampler` with specified `reason`.

  See documentation for `GenServer.stop/3` to learn more about the behaviour of this function.
  """
  @spec stop(t(), reason :: term(), timeout()) :: :ok
  def stop(sampler, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(sampler, reason, timeout)
  end

  @doc """
  Returns a list of measurement specs used by the sampler.
  """
  @spec list_specs(t()) :: [measurement_spec()]
  def list_specs(sampler) do
    GenServer.call(sampler, :get_specs)
  end

  @doc """
  Returns a single measurement sample.

  This function should be used by measurement spec MFAs.
  """
  @spec sample(Telemetry.event_name(), Telemetry.event_value(), Telemetry.event_metadata()) ::
          sample()
  def sample(event, value, metadata) do
    {:sample, event, value, metadata}
  end

  ## GenServer callbacks

  @impl true
  def init(options) do
    state = %{
      specs: Keyword.fetch!(options, :measurements),
      period: Keyword.fetch!(options, :period)
    }

    schedule_collection(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:collect, state) do
    new_specs =
      state.specs
      |> collect_measurements()
      |> dispatch_events_and_filter_misbehaving()

    schedule_collection(state.period)
    {:noreply, %{state | specs: new_specs}}
  end

  @impl true
  def handle_call(:get_specs, _, state) do
    {:reply, state.specs, state}
  end

  ## Helpers

  @spec parse_options!(list()) :: {Keyword.t(), Keyword.t()} | no_return()
  defp parse_options!(options) do
    gen_server_opts = Keyword.take(options, [:name])
    measurement_specs = Keyword.get(options, :measurements, [])
    validate_measurement_specs!(measurement_specs)
    period = Keyword.get(options, :period, @default_period)
    validate_period!(period)
    {[measurements: measurement_specs, period: period], gen_server_opts}
  end

  @spec validate_measurement_specs!(term()) :: :ok | no_return()
  defp validate_measurement_specs!(measurement_specs) when is_list(measurement_specs) do
    Enum.each(measurement_specs, &validate_measurement_spec!/1)
    :ok
  end

  defp validate_measurement_specs!(other) do
    raise ArgumentError, "Expected :measurements to be a list, got #{inspect(other)}"
  end

  @spec validate_measurement_spec!(term()) :: measurement_spec() | no_return()
  defp validate_measurement_spec!({m, f, a})
       when is_atom(m) and is_atom(f) and is_list(a) do
    :ok
  end

  defp validate_measurement_spec!({_, _, _} = invalid_spec) do
    raise ArgumentError, "Expected MFA measurement spec, got #{inspect(invalid_spec)}"
  end

  defp validate_measurement_spec!({event, {m, f, a}})
       when is_list(event) and is_atom(m) and is_atom(f) and is_list(a) do
    :ok
  end

  defp validate_measurement_spec!({_, {_, _, _}} = invalid_spec) do
    raise ArgumentError,
          "Expected event name with MFA measurement spec, got #{inspect(invalid_spec)}"
  end

  defp validate_measurement_spec!(invalid_spec) do
    raise ArgumentError,
          "Expected measurement spec, got #{inspect(invalid_spec)}"
  end

  @spec validate_period!(term()) :: :ok | no_return()
  defp validate_period!(period) when is_integer(period) and period > 0, do: :ok

  defp validate_period!(other),
    do: raise(ArgumentError, "Expected :period to be a postivie integer, got #{inspect(other)}")

  @spec schedule_collection(collect_in_millis :: non_neg_integer()) :: :ok
  defp schedule_collection(collect_in_millis) do
    Process.send_after(self(), :collect, collect_in_millis)
    :ok
  end

  @spec collect_measurements([measurement_spec()]) :: [
          {measurement_spec(),
           {:ok, term()} | {:error, Exception.kind(), reason :: term(), Exception.stacktrace()}}
        ]
  defp collect_measurements(specs) do
    Enum.map(specs, fn spec ->
      value = collect_measurement(spec)
      {spec, value}
    end)
  end

  @spec collect_measurement(measurement_spec()) ::
          {:ok, term()} | {:error, Exception.kind(), reason :: term(), Exception.stacktrace()}
  defp collect_measurement({_event, {_m, _f, _a} = mfa}) do
    collect_measurement(mfa)
  end

  defp collect_measurement({m, f, a}) do
    try do
      {:ok, apply(m, f, a)}
    catch
      kind, reason ->
        {:error, kind, reason, System.stacktrace()}
    end
  end

  @spec dispatch_events_and_filter_misbehaving([
          {measurement_spec(),
           {:ok, term()} | {:error, Exception.kind(), reason :: term(), Exception.stacktrace()}}
        ]) :: [measurement_spec()]
  defp dispatch_events_and_filter_misbehaving(specs_with_values) do
    specs_with_values
    |> Enum.map(fn {spec, value} -> {spec, maybe_dispatch_events({spec, value})} end)
    |> Enum.filter(fn {_spec, ok_or_error} -> ok_or_error == :ok end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec maybe_dispatch_events(
          {measurement_spec(),
           {:ok, term()} | {:error, Exception.kind(), reason :: term(), Exception.stacktrace()}}
        ) :: :ok | :error
  defp maybe_dispatch_events({spec, {:error, kind, reason, stack}}) do
    formatted_error = Exception.format(kind, reason, stack)

    Logger.error("""
    Failed to collect measurement defined by spec #{inspect(spec)}:
    #{formatted_error}
    """)

    :error
  end

  defp maybe_dispatch_events({{_m, _f, _a} = spec, {:ok, sample_or_samples}}) do
    case maybe_dispatch_samples(sample_or_samples) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to dispatch values returned by invoking spec #{inspect(spec)}: #{reason}"
        )

        :error
    end
  end

  defp maybe_dispatch_events({{event, {_m, _f, _a}}, {:ok, value}}) when is_number(value) do
    sample = sample(event, value, %{})
    :ok = maybe_dispatch_samples(sample)
  end

  defp maybe_dispatch_events({{_event, {_, _f, _a}} = spec, {:ok, other}}) do
    Logger.error(
      "Failed to dispatch the value returned by invoking spec #{inspect(spec)}: " <>
        "expected a number, got #{inspect(other)}"
    )

    :error
  end

  @spec maybe_dispatch_samples(term()) :: :ok | {:error, String.t()}
  defp maybe_dispatch_samples(maybe_samples) when is_list(maybe_samples) do
    if Enum.all?(maybe_samples, &valid_sample?/1) do
      for {:sample, event, value, metadata} <- maybe_samples do
        Telemetry.execute(event, value, metadata)
      end

      :ok
    else
      {:error, "expected a list of samples, got #{inspect(maybe_samples)}"}
    end
  end

  defp maybe_dispatch_samples(maybe_sample) do
    if valid_sample?(maybe_sample) do
      {:sample, event, value, metadata} = maybe_sample
      Telemetry.execute(event, value, metadata)
      :ok
    else
      {:error, "expected a sample, got #{inspect(maybe_sample)}"}
    end
  end

  @spec valid_sample?(term()) :: boolean()
  defp valid_sample?({:sample, event, value, metadata})
       when is_list(event) and is_number(value) and is_map(metadata) do
    true
  end

  defp valid_sample?(_) do
    false
  end
end
