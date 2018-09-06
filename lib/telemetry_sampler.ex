defmodule Telemetry.Sampler do
  @moduledoc """
  Allows to periodically collect measurements and publish them as `Telemetry` events.

  Measurements are MFAs called periodically by the Sampler process. These MFAs should collect
  a value (if possible) and dispatch an event using `Telemetry.execute/3` function.

  If the invokation of the MFA fails, the measurement is removed from the Sampler.

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

  The `vm_measurements/1` function returns common measurements related to Erlang virtual machine
  metrics. See its documentation for more information.

  ## Example - measuring message queue length of the process

  Measuring process' message queue length is a good way to find out if and when the process becomes
  the bottleneck. If the length of the queue is growing, it means that the process is not keeping
  up with the work it's been assigned and other processes asking it to do the work will get
  timeouts. Let's try to simulate that situation using the following GenServer:

      defmodule Worker do
        use GenServer

        def start_link() do
          GenServer.start_link(__MODULE__, [])
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
  running task.

  Now we need a measurement dispatching the message queue length of the worker:

      defmodule ExampleApp.Measurements do
        def message_queue_length(pid) do
          {:message_queue_len, length} = Process.info(pid, :message_queue_len)
          Telemetry.execute([:example_app, :message_queue_length], length, %{pid: pid})
        end
      end

  Let's start the worker and Sampler with just defined measurement:

      iex> {:ok, pid} = Worker.start_link()
      iex> Telemetry.Sampler.start_link(
      ...>   measurements: [{ExampleApp.Measurements, :message_queue_length, [pid]}],
      ...>   period: 2000)
      {:ok, _}

  In order to observe the message queue length we can install the event handler printing it out to
  the console:

      iex> defmodule Handler do
      ...>   def handle([:example_app, :message_queue_length], length, %{pid: pid}, _) do
      ...>     IO.puts("Process #\{inspect(pid)} message queue length: #\{length}")
      ...>   end
      ...> end
      iex> Telemetry.attach(:handler, [:example_app, :message_queue_length], Handler, :handle)
      :ok

  Now start let's assigning work to the worker:

      iex> for _ <- 1..1000 do
      ...>   spawn_link(fn -> Worker.do_work(pid) end)
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

  To achieve that, we need a measurement dispatching the value we're interested in:

      defmodule ExampleApp.Measurements do
        def dispatch_session_count() do
          Telemetry.execute([:example_app, :session_count], ExampleApp.session_count())
        end
      end

  and tell the Sampler to invoke it periodically:

      Telemetry.Sampler.start_link(measurements: [
        {ExampleApp.Measurements, :dispatch_session_count, []}
      ])

  If you find that you need to somehow label the event values, e.g. differentiate between number of
  sessions of regular and admin users, you could use event metadata:

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
  @default_vm_measurements [
    :total_memory,
    :processes_memory,
    :processes_used_memory,
    :binary_memory,
    :ets_memory
  ]
  @vm_memory_measurements [
    :total_memory,
    :processes_memory,
    :processes_used_memory,
    :system_memory,
    :atom_memory,
    :atom_used_memory,
    :binary_memory,
    :code_memory,
    :ets_memory
  ]

  @type t :: GenServer.server()
  @type options :: [option()]
  @type option ::
          {:name, GenServer.name()}
          | {:period, period()}
          | {:measurements, [measurement()]}
  @type period :: pos_integer()
  @type measurement() :: mfa()
  @type vm_measurement() ::
          :total_memory
          | :processes_memory
          | :processes_used_memory
          | :system_memory
          | :atom_memory
          | :atom_used_memory
          | :binary_memory
          | :code_memory
          | :ets_memory

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
  Returns measurements dispatching events with Erlang virtual machine metrics

  It accepts a list `t:vm_measurement/0`s and returns a list of `t:measurement/0`s which can
  be provided to `start_link/1`'s `:measurements` option.

  Do not rely on the exact values returned by this function - the only guarantee is that they
  are of type `t:measurement/0` and their modification will not be considered a breaking change,
  unless the shape of events dispatched by returned measurements changes.

  Returned measurements are unique.

  ## Available measurements

  ### Memory

  See documentation for `:erlang.memory/0` function for more information about each type of memory
  measured.

  * `:total_memory` - dispatches an event with total amount of currently allocated memory, in bytes.
  Event name is `[:vm, :memory, :total]` and event metadata is empty;
  * `:processes_memory` - dispatches an event with amount of memory cyrrently allocated for
    processes, in bytes. Event name is `[:vm, :memory, :processes]` and event metadata is empty;
  * `:processes_used_memory` - dispatches an event with amount of memory currently used for
    processes, in bytes. Event name is `[:vm, :memory, :processes_used]` and event metadata is empty.
    Memory measured is a fraction of value collected by `:processes_memory` measurement;
  * `:binary_memory` - dispatches an event with amount of memory currently allocated for binaries.
    Event name is `[:vm, :memory, :binary]` and event metadata is empty;
  * `:ets_memory` - dispatches an event with amount of memory currently allocated for ETS tables.
    Event name is `[:vm, :memory, :ets]` and event metadata is empty;
  * `:system_memory` - dispatches an event with amount of currently allocated memory not directly
    related to any process running in the VM, in bytes. Event name is `[:vm, :memory, :system]` and
    event metadata is empty;
  * `:atom_memory` - dispatches an event with amount of memory currently allocated for atoms. Event
    name is `[:vm, :memory, :atom]` and event metadata is empty;
  * `:atom_used_memory` - dispatches an event with amount of memory currently used for atoms. Event
    name is `[:vm, :memory, :atom_used]` and event metadata is empty;
  * `:code_memory` - dispatches an event with amount of memory currently allocated for code. Event
    name is `[:vm, :memory, :code]` and event metadata is empty;

  ## Default measurements

  The 0-arity version of this function includes `:total_memory`, `:processes_memory`,
  `:processes_used_memory`, `:binary_memory` and `:ets_memory` measurements by default.

  ## Examples

      alias Telemetry.Sampler
      Sampler.start_link(
        measurements: Sampler.vm_measurements() ++ Sampler.vm_measurements(:atom_memory)
      )
  """
  @spec vm_measurements([vm_measurement()]) :: [measurement()]
  def vm_measurements(vm_measurements \\ @default_vm_measurements)
      when is_list(vm_measurements) do
    measurements = parse_vm_measurements!(vm_measurements)
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

  @spec parse_vm_measurements!([term()]) :: [measurement()] | no_return()
  defp parse_vm_measurements!(vm_measurements) do
    Enum.map(vm_measurements, &parse_vm_measurement!/1)
  end

  @spec parse_vm_measurement!(term()) :: [measurement()] | no_return()
  defp parse_vm_measurement!(memory) when memory in @vm_memory_measurements do
    vm_measurement(memory)
  end

  defp parse_vm_measurement!(other) do
    raise ArgumentError, "Expected VM measurement, got #{inspect(other)}"
  end

  @spec vm_measurement(function :: atom(), args :: list()) :: measurement()
  defp vm_measurement(function, args \\ []) do
    {Telemetry.Sampler.VM, function, args}
  end
end
