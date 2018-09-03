defmodule Telemetry.Sampler do
  @moduledoc """
  Allows to periodically collect measurements and publish them as `Telemetry` events.

  Measurements can be described in two ways:

  1. As an MFA tuple which dispatches events using `Telemetry.execute/3` upon invokation;
  2. As a tuple, where the first element is event name and the second element is an MFA returning a
     **number**. In this case, Sampler will dispatch an event with given name and value returned
     by the MFA invokation; event metadata will be always empty.

  If the invokation of MFA returns an invalid value (i.e. it should return a number but doesn't),
  the measurement is removed from the list and the error is logged.

  See the "Examples" section for more concrete examples.

  ## Starting and stopping

  You can start the Sampler using the `start_link/1` function. Sampler can be alaso started as a
  part of your supervision tree, using both the old-style and the new-style child specifications:

      # pre Elixir 1.5.0
      children = [Supervisor.Spec.worker(Telemetry.Sampler, [[period: 5000]])]

      # post Elixir 1.5.0
      children = [{Telemetry.Sampler, [period: 5000]}]

      Supervisor.start_link(children, [strategy: :one_for_one])

  You can start as many Samplers as you wish, but generally you shouldn't need to do it, unless
  you know that it's not keeping up with collecting all specified measurements.

  Measurements need to be provided via `:measurements` option.

  ## VM measurements

  See `Telemetry.Sampler.VM` module for functions which can be used as measurements for metrics
  related to the Erlang virtual machine.

  ## Examples

  Let's imagine that you have a web application and you would like to periodically measure number
  of active user sessions.

      defmodule ExampleApp do
        def session_count() do
          # logic for calculating session count
          ...
        end
      end

  There are two ways in which you can hook this measurement up to a Sampler. The first approach is
  to write your own dispatching function:

      defmodule ExampleApp.Measurements do
        def dispatch_session_count() do
          Telemetry.execute([:example_app, :session_count], ExampleApp.session_count())
        end
      end

  and tell the Sampler to invoke it periodically:

      Telemetry.Sampler.start_link(measurements: [
        {ExampleApp.Measurements, :dispatch_session_count, []}
      ])

  However, given that the event does not carry any metadata, it's easier to wire the
  `ExampleApp.session_count/0` function directly:

      Telemetry.Sampler.start_link(measurements: [
        {[:example_app, :session_count], {ExampleApp, :session_count, []}}
      ])

  Both solutions are equivalent, but only because the event metadata is empty. If you find that you
  need to somehow label the event values, e.g. differentiate between number of sessions of regular
  and admin users, then only the first approach is a viable choice:

      defmodule ExampleApp.Measurements do
        def dispatch_session_count() do
          regulars = ExampleApp.regular_users_session_count()
          admins = ExampleApp.admin_users_session_count()
          Telemetry.execute([:example_app, :session_count], regulars, %{role: :regular})
          Telemetry.execute([:example_app, :session_count], admins, %{role: :admin})
        end
      end

  > Note: the other solution would be to dispatch two different events by hooking up
  > `ExampleApp.regular_users_session_count/0` and `ExampleApp.admin_users_session_count/0`
  > functions directly. However, if you add more and more user roles to your app, you'll find
  > yourself creating a new event for each one of them, which will force you to modify existing
  > event handlers. If you can break down event value by some feature, like user role in this
  > example, it's usually better to use event metadata than add new events.

  This is a perfect use case for Sampler, because you don't need to write a dedicated process
  which would call these functions periodically. Additionally, if you find that you need to collect
  more statistics like this in the future, you can easily hook them up to the same Sampler process
  and avoid creating lots of processes which would stay idle most of the time.
  """

  use GenServer

  require Logger

  @default_period 10_000

  @type t :: GenServer.server()
  @type options :: [option()]
  @type option ::
          {:name, GenServer.name()}
          | {:period, period()}
          | {:measurements, [measurement()]}
  @type period :: pos_integer()
  @type measurement() :: mfa() | {Telemetry.event_name(), mfa()}

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

  * `:measurements` - a list of measurements used by Sampler. For description of possible values
    see `Telemetry.Sampler` module documentation;
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
  Returns a list of measurements used by the sampler.
  """
  @spec list_measurements(t()) :: [measurement()]
  def list_measurements(sampler) do
    GenServer.call(sampler, :get_measurements)
  end

  ## GenServer callbacks

  @impl true
  def init(options) do
    state = %{
      measurements: Keyword.fetch!(options, :measurements),
      period: Keyword.fetch!(options, :period)
    }

    schedule_measurement(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:collect, state) do
    new_measurements = make_measurements_and_filter_misbehaving(state.measurements)

    schedule_measurement(state.period)
    {:noreply, %{state | measurements: new_measurements}}
  end

  @impl true
  def handle_call(:get_measurements, _, state) do
    {:reply, state.measurements, state}
  end

  ## Helpers

  @spec parse_options!(list()) :: {Keyword.t(), Keyword.t()} | no_return()
  defp parse_options!(options) do
    gen_server_opts = Keyword.take(options, [:name])
    measurements = Keyword.get(options, :measurements, [])
    validate_measurements!(measurements)
    period = Keyword.get(options, :period, @default_period)
    validate_period!(period)
    {[measurements: measurements, period: period], gen_server_opts}
  end

  @spec validate_measurements!(term()) :: :ok | no_return()
  defp validate_measurements!(measurements) when is_list(measurements) do
    Enum.each(measurements, &validate_measurement!/1)
    :ok
  end

  defp validate_measurements!(other) do
    raise ArgumentError, "Expected :measurements to be a list, got #{inspect(other)}"
  end

  @spec validate_measurement!(term()) :: measurement() | no_return()
  defp validate_measurement!({m, f, a})
       when is_atom(m) and is_atom(f) and is_list(a) do
    :ok
  end

  defp validate_measurement!({_, _, _} = invalid_measurement) do
    raise ArgumentError, "Expected MFA measurement, got #{inspect(invalid_measurement)}"
  end

  defp validate_measurement!({event, {m, f, a}})
       when is_list(event) and is_atom(m) and is_atom(f) and is_list(a) do
    :ok
  end

  defp validate_measurement!({_, {_, _, _}} = invalid_measurement) do
    raise ArgumentError,
          "Expected event name with MFA measurement, got #{inspect(invalid_measurement)}"
  end

  defp validate_measurement!(invalid_measurement) do
    raise ArgumentError,
          "Expected measurement, got #{inspect(invalid_measurement)}"
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

  @spec make_measurements_and_filter_misbehaving([measurement()]) :: [measurement()]
  defp make_measurements_and_filter_misbehaving(measurements) do
    Enum.map(measurements, fn measurement ->
      result = make_measurement(measurement)
      {measurement, result}
    end)
    |> Enum.filter(fn {_measurement, ok_or_error} -> ok_or_error == :ok end)
    |> Enum.map(&elem(&1, 0))
  end

  @spec make_measurement(measurement()) :: :ok | :error
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
