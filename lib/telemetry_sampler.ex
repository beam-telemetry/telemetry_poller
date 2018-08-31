defmodule Telemetry.Sampler do
  @moduledoc """
  Allows to periodically collect measurements and publish them as `Telemetry` events.

  ## Measurement specifications

  Measurement specifications (later "specs") describe how the measurement should be performed and
  what event should be emitted once the mesured value is collected. There are two possible values
  for measurement spec:

  1. An MFA tuple which dispatches events using `Telemetry.execute/3` upon invokation;
  2. A tuple, where the first element is event name and the second element is an MFA returning a
     *number*. In this case, Sampler will dispatch an event with given name and value returned
     by the MFA invokation; event metadata will be always empty.

  If the invokation of MFA returns an invalid value (i.e. it should return a number but doesn't),
  the spec is removed from the list and the error is logged.

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

  ## GenServer callbacks

  @impl true
  def init(options) do
    state = %{
      specs: Keyword.fetch!(options, :measurements),
      period: Keyword.fetch!(options, :period)
    }

    schedule_measurement(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:collect, state) do
    new_specs = make_measurements_and_filter_misbehaving(state.specs)

    schedule_measurement(state.period)
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

  @spec schedule_measurement(collect_in_millis :: non_neg_integer()) :: :ok
  defp schedule_measurement(collect_in_millis) do
    Process.send_after(self(), :collect, collect_in_millis)
    :ok
  end

  @spec make_measurements_and_filter_misbehaving([measurement_spec()]) :: [measurement_spec()]
  defp make_measurements_and_filter_misbehaving(specs) do
    Enum.map(specs, fn spec ->
      result = make_measurement(spec)
      {spec, result}
    end)
    |> Enum.filter(fn {_spec, ok_or_error} -> ok_or_error == :ok end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec make_measurement(measurement_spec()) :: :ok | :error
  defp make_measurement({event, {m, f, a}} = measurement) do
    case apply(m, f, a) do
      result when is_number(result) ->
        Telemetry.execute(event, result)
        :ok

      result ->
        Logger.error(
          "Expected an MFA defined by measurement #{inspect(measurement)} to return " <>
            "a number, got #{inspect(result)}"
        )

        :error
    end
  catch
    kind, reason ->
      Logger.error(
        "Error when calling MFA defined by measurement #{inspect(measurement)}:\n" <>
          "#{Exception.format(kind, reason, System.stacktrace())}"
      )

      :error
  end

  defp make_measurement({m, f, a} = measurement) do
    apply(m, f, a)
    :ok
  catch
    kind, reason ->
      Logger.error(
        "Error when calling MFA defined by measurement #{inspect(measurement)}:\n" <>
          "#{Exception.format(kind, reason, System.stacktrace())}"
      )

      :error
  end
end
