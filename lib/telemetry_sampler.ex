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

  See the "Example - (...)" sections for more concrete examples.

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

  `Telemetry.Sampler.VM` module contains a bunch of functions which can be used to collect
  measurements from the Erlang virtual machine. You can use `vm_measurements/1` function to make
  it easier to hook them up to the Sampler:

      Sampler.start_link(measurements:
        Sampler.vm_measurements([:memory, {:message_queue_length, MyProcess}])
      )

  ## Example - measuring message queue length of the process

  Measuring process' message queue length is a good way to find out if and when the process becomes
  the bottleneck. If the length of the queue is growing, it means that the process is not keeping
  up with the work it's been assigned and other processes asking it to do the work will get
  timeouts. Let's try to simulate that situation using the following GenServer:

      defmodule Worker do
        use GenServer

        def start_link(name) do
          GenServer.start_link(__MODULE__, [], name: name)
        end

        def do_work(name) do
          GenServer.call(name, :do_work, timeout = 5_000)
        end

        def init([]) do
          {:ok, %{}}
        end

        def handle_call(:do_work, _, state) do
          Process.sleep(1000)
          {:reply, :ok, state}
        end
      end

  When assigned with work (`handle_call/3`), the worker will sleep for 1 second to imitate long
  running task. Let's start the worker and Sampler measuring its message queue length:

      iex> alias Telemetry.Sampler
      iex> worker = Worker
      iex> Sampler.start_link(
      ...>   measurements: Sampler.vm_measurements([{:message_queue_length, [worker]}]),
      ...>   period: 2000)
      iex> Worker.start_link(worker)
      {:ok, _}

  In order to observe the message queue length we can install the event handler printing it out to
  the console:

      iex> defmodule Handler do
      ...>   def handle([:vm, :message_queue_length], length, %{process: worker}, _) do
      ...>     IO.puts("Process #\{inspect(worker)} message queue length: #\{length}")
      ...>   end
      ...> end
      iex> Telemetry.attach(:handler, [:vm, :message_queue_length], Handler, :handle)
      :ok

  Now start let's assigning work to the worker:

      iex> for _ <- 1..1000 do
      ...>   spawn_link(fn -> Worker.do_work(worker) end)
      ...>   Process.sleep(500)
      ...> end
      iex> :ok
      :ok

  Here we start 1000 processes placing a work order, waiting 500 milliseconds after starting each
  one. Given that the worker does its work in 1000 milliseconds, it means that new work orders come
  twice as fast as the worker is able to complete them. In the console, you'll see something like
  this:

  ```
  Process Worker message queue length: 1
  Process Worker message queue length: 3
  Process Worker message queue length: 5
  Process Worker message queue length: 7
  ```

  and finally:

  ```
  ** (EXIT from #PID<0.168.0>) shell process exited with reason: exited in: GenServer.call(Worker, :do_work, 5000)
    ** (EXIT) time out
  ```

  The worker wasn't able to complete the work on time (we set the 5000 millisecond timeout) and
  `Worker.do_work/1` finally failed. Observing the message queue length metric allowed us to notice
  that the worker is the system's bottleneck. In a healthy situation the message queue length would
  be roughly constant.

  ## Example - tracking number of active sessions in web application

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

  @doc """
  Helper function for building VM measurements.

  It accepts a list of two-element tuples where the first element is an atom corresponding to the
  function from the `Telemetry.Sampler.VM` module, and the second is a list of arguments applied
  to that function. Alternatively, instead of a tuple you can provide an atom, which is equivalent
  to a tuple with an empty list of arguments. The result is a list of measurements which can be fed
  to `start_link/1`'s `:measurements` option. Returned measurements are unique.

  Raises if the given function is not exported by `Telemetry.Sampler.VM` module or the length
  of argument list doesn't match the function's arity.

  ## Examples

      iex> Telemetry.Sampler.vm_measurements([:memory])
      [{Telemetry.Sampler.VM, :memory, []}]

      iex> Telemetry.Sampler.vm_measurements([:memory]) == Telemetry.Sampler.vm_measurements([{:memory, []}])
      true

      iex> Telemetry.Sampler.vm_measurements([:memory, {:message_queue_length, [MyProcess]}])
      [{Telemetry.Sampler.VM, :memory, []}, {Telemetry.Sampler.VM, :message_queue_length, [MyProcess]}]
  """
  @spec vm_measurements([function_name :: atom() | {function_name :: atom(), args :: list()}]) ::
          [measurement()]
  def vm_measurements(vm_measurements) when is_list(vm_measurements) do
    measurements = normalize_vm_measurements(vm_measurements)
    validate_vm_measurements!(measurements)
    Enum.uniq(measurements)
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

  @spec normalize_vm_measurements([atom() | {atom(), list()}]) :: [{module(), term(), term()}]
  defp normalize_vm_measurements(vm_measurements) do
    Enum.map(vm_measurements, &normalize_vm_measurement/1)
  end

  defp normalize_vm_measurement({function_name, args}) do
    {Telemetry.Sampler.VM, function_name, args}
  end

  defp normalize_vm_measurement(function_name) do
    normalize_vm_measurement({function_name, []})
  end

  @spec validate_vm_measurements!([{module(), term(), term()}]) :: :ok | no_return()
  defp validate_vm_measurements!(measurements) do
    {:module, _} = Code.ensure_loaded(Telemetry.Sampler.VM)
    Enum.each(measurements, &validate_vm_measurement!/1)
  end

  @spec validate_vm_measurement!({module(), term(), term()}) :: :ok | no_return()
  defp validate_vm_measurement!({_module, function_name, args})
       when is_atom(function_name) and is_list(args) do
    args_len = length(args)

    if function_exported?(Telemetry.Sampler.VM, function_name, args_len) do
      :ok
    else
      raise ArgumentError,
            "Function Telemetry.Sampler.VM.#{function_name}/#{args_len} is not exported"
    end
  end

  defp validate_vm_measurement!({_module, function_name, args}) when is_list(args) do
    raise ArgumentError, "Expected function name to be an atom, got #{inspect(function_name)}"
  end

  defp validate_vm_measurement!({_module, _function_name, args}) do
    raise ArgumentError, "Expected arguments to be a list, got #{inspect(args)}"
  end
end
