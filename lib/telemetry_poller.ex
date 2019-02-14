defmodule Telemetry.Poller do
  @moduledoc ~S"""
  A time-based poller to periodically dispatch Telemetry events.

  By default a single poller is started under `Telemetry.Poller` application.
  It is started with name `Telemetry.Poller.Default` and a default set of VM
  measurements. It polls all default VM measurements, which is equivalent to:

      config :telemetry_poller, :default,
        vm_measurements: :default # this is the default

  But you may specify all VM measurements you want:

      config :telemetry_poller, :default,
        vm_measurements: [:memory] # measure only the memory

  Measurements are MFAs called periodically by the poller process.
  You can disable the default poller by setting it to `false`:

      config :telemetry_poller, :default, false

  Telemetry poller also allows you perform custom measurements by spawning
  your own poller process:

      children = [
        {Telemetry.Poller,
         measurements: [{MyApp.Example, :measure, []}]}
      ]

  For custom pollers, the measurements are given as MFAs. Those MFAs should
  collect a value (if possible) and dispatch an event using `:telemetry.execute/3`
  function. If the invokation of the MFA fails, the measurement is removed
  from the Poller.

  For all options, see `start_link/1`. The options listed there can be given
  to the default poller as well as to custom pollers.

  Over the next sections, we will describe all built-in VM measurements and
  explore some concrete examples.

  ## VM measurements

  VM measurements need to be provided via `:vm_measurements` option. Below you
  can find a list of available measurements per category.

  ### Memory

  There is only one measurement related to memory - `:memory`. The emitted event includes all the
  key-value pairs returned by `:erlang.memory/0` function, e.g. `:total` for total memory,
  `:processes_used` for memory used by all processes etc.

  ### Run queue lengths

  On startup, the Erlang VM starts many schedulers to do both IO and CPU work. If a process
  needs to do some work or wait on IO, it is allocated to the appropriate scheduler. The run
  queue is a queue of tasks to be scheduled. A length of a run queue corresponds to the amount
  of work accumulated in the system. If a run queue length is constantly growing, it means that
  the BEAM is not keeping up with executing all the tasks.

  There are several run queue types in the Erlang VMe. Each CPU scheduler (usually one per core)
  has its own run queue, and since Erlang 20.0 there is one dirty CPU run queue, and one dirty
  IO run queue.

  The following VM measurements related to run queue lengths are available:

  * `:total_run_queue_lengths` - dispatches an event with a sum of schedulers' run queue lengths. The
    event name is `[:vm, :total_run_queue_lengths]`, event metadata is empty and it includes three
    measurements:
    * `:total` - a sum of all run queue lengths;
    * `:cpu` - a sum of CPU schedulers' run queue lengths, including dirty CPU run queue length
      on Erlang >= 20.0;
    * `:io` - length of dirty IO run queue. It's always 0 if running on Erlang < 20.0.


    Note that the method of making this measurement varies between different Erlang versions: for
    Erlang 18 and 19, the implementation is less efficient than for version 20 and up.

    The length of all queues is not gathered atomically, so the event value does not represent
    a consistent snapshot of the run queues' state. However, the value is accurate enough to help
    to identify issues in a running system.

  ### Default measurements

  When `:default` is provided as the value of `:vm_measurement` options, Poller uses `:memory` and
  `:total_run_queue_lengths` VM measurements.

  ## Example - measuring message queue length of the process

  Measuring process' message queue length is a good way to find out if and when the
  process becomes the bottleneck. If the length of the queue is growing, it means that
  the process is not keeping up with the work it's been assigned and other processes
  asking it to do the work will get timeouts. Let's try to simulate that situation
  using the following GenServer:

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

  When assigned with work (`handle_call/3`), the worker will sleep for 1 second to
  imitate long running task.

  Now we need a measurement dispatching the message queue length of the worker:

      defmodule ExampleApp.Measurements do
        def message_queue_length(name) do
          with pid when is_pid(pid) <- Process.whereis(name),
               {:message_queue_len, length} <- Process.info(pid, :message_queue_len) do
            :telemetry.execute([:example_app, :message_queue_length], length, %{name: name})
          end
        end
      end

  Let's start the worker and Poller with just defined measurement:

      iex> name = MyWorker
      iex> {:ok, pid} = Worker.start_link(name)
      iex> Telemetry.Poller.start_link(
      ...>   measurements: [{ExampleApp.Measurements, :message_queue_length, [MyWorker]}],
      ...>   period: 2000
      ...> )
      {:ok, _}

  In order to observe the message queue length we can install the event handler printing it out to
  the console:

      iex> defmodule Handler do
      ...>   def handle([:example_app, :message_queue_length], length, %{name: name}, _) do
      ...>     IO.puts("Process #{inspect(name)} message queue length: #{length}")
      ...>   end
      ...> end
      iex> :telemetry.attach(:handler, [:example_app, :message_queue_length], &Handler.handle/4, nil)
      :ok

  Now let's start assigning work to the worker:

      iex> for _ <- 1..1000 do
      ...>   spawn_link(fn -> Worker.do_work(name) end)
      ...>   Process.sleep(500)
      ...> end
      iex> :ok
      :ok

  Here we start 1000 processes placing a work order, waiting 500 milliseconds after starting each
  one. Given that the worker does its work in 1000 milliseconds, it means that new work orders come
  twice as fast as the worker is able to complete them. In the console, you'll see something like
  this:

  ```
  Process MyWorker message queue length: 1
  Process MyWorker message queue length: 3
  Process MyWorker message queue length: 5
  Process MyWorker message queue length: 7
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
          :telemetry.execute([:example_app, :session_count], ExampleApp.session_count())
        end
      end

  and tell the Poller to invoke it periodically:

      Telemetry.Poller.start_link(measurements: [
        {ExampleApp.Measurements, :dispatch_session_count, []}
      ])

  If you find that you need to somehow label the event values, e.g. differentiate between number of
  sessions of regular and admin users, you could use event metadata:

      defmodule ExampleApp.Measurements do
        def dispatch_session_count() do
          regulars = ExampleApp.regular_users_session_count()
          admins = ExampleApp.admin_users_session_count()
          :telemetry.execute([:example_app, :session_count], regulars, %{role: :regular})
          :telemetry.execute([:example_app, :session_count], admins, %{role: :admin})
        end
      end

  > Note: the other solution would be to dispatch two different events by hooking up
  > `ExampleApp.regular_users_session_count/0` and `ExampleApp.admin_users_session_count/0`
  > functions directly. However, if you add more and more user roles to your app, you'll find
  > yourself creating a new event for each one of them, which will force you to modify existing
  > event handlers. If you can break down event value by some feature, like user role in this
  > example, it's usually better to use event metadata than add new events.

  This is a perfect use case for Poller, because you don't need to write a dedicated process
  which would call these functions periodically. Additionally, if you find that you need to collect
  more statistics like this in the future, you can easily hook them up to the same Poller process
  and avoid creating lots of processes which would stay idle most of the time.
  """

  use GenServer

  require Logger

  @default_period 10_000
  @default_vm_measurements [
    :memory,
    :total_run_queue_lengths
  ]
  @vm_measurements [
    :memory,
    :total_run_queue_lengths
  ]

  @type t :: GenServer.server()
  @type options :: [option()]
  @type option ::
          {:name, GenServer.name()}
          | {:period, period()}
          | {:measurements, [measurement()]}
          | {:vm_measurements, :default | [vm_measurement()]}
  @type period :: pos_integer()
  @type measurement() :: {module(), function :: atom(), args :: list()}
  @type vm_measurement() ::
          :memory
          | :total_run_queue_lengths

  ## API

  @doc """
  Starts a Poller linked to the calling process.

  Useful for starting Pollers as a part of a supervision tree.

  ## Options

  * `:measurements` - a list of measurements used by Poller. For description of possible values
    see `Telemetry.Poller` module documentation;
  * `:vm_measurements` - a list of atoms describing measurements related to the Erlang VM, or an
    atom `:default`, in which case default VM measurements are used. See "VM measurements" section in
    the module documentation for more information. Default value is `[]`;
  * `:period` - time period before performing the same measurement again, in milliseconds. Default
    value is #{@default_period} ms;
  * `:name` - the name of the Poller process. See "Name Registragion" section of `GenServer`
    documentation for information about allowed values.

  """
  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options \\ []) when is_list(options) do
    {poller_opts, gen_server_opts} = parse_options!(options)
    GenServer.start_link(__MODULE__, poller_opts, gen_server_opts)
  end

  @doc """
  Stops the `poller` with specified `reason`.

  See documentation for `GenServer.stop/3` to learn more about the behaviour of this function.
  """
  @spec stop(t(), reason :: term(), timeout()) :: :ok
  def stop(poller, reason \\ :normal, timeout \\ :infinity) do
    GenServer.stop(poller, reason, timeout)
  end

  @doc """
  Returns a list of measurements used by the poller.
  """
  @spec list_measurements(t()) :: [measurement()]
  def list_measurements(poller) do
    GenServer.call(poller, :get_measurements)
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

    vm_measurements =
      options
      |> Keyword.get(:vm_measurements, [])
      |> parse_vm_measurements!()
      |> Enum.uniq()

    period = Keyword.get(options, :period, @default_period)
    validate_period!(period)
    {[measurements: measurements ++ vm_measurements, period: period], gen_server_opts}
  end

  @spec validate_measurements!(term()) :: :ok | no_return()
  defp validate_measurements!(measurements) when is_list(measurements) do
    Enum.each(measurements, &validate_measurement!/1)
    :ok
  end

  defp validate_measurements!(other) do
    raise ArgumentError, "expected :measurements to be a list, got #{inspect(other)}"
  end

  @spec validate_measurement!(term()) :: :ok | no_return()
  defp validate_measurement!({m, f, a})
       when is_atom(m) and is_atom(f) and is_list(a) do
    :ok
  end

  defp validate_measurement!(invalid_measurement) do
    raise ArgumentError,
          "expected measurement, got #{inspect(invalid_measurement)}"
  end

  @spec validate_period!(term()) :: :ok | no_return()
  defp validate_period!(period) when is_integer(period) and period > 0, do: :ok

  defp validate_period!(other),
    do: raise(ArgumentError, "expected :period to be a postivie integer, got #{inspect(other)}")

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

  @spec parse_vm_measurements!(term()) :: [measurement()] | no_return()
  defp parse_vm_measurements!(:default) do
    parse_vm_measurements!(@default_vm_measurements)
  end

  defp parse_vm_measurements!(vm_measurements) do
    Enum.map(vm_measurements, &parse_vm_measurement!/1)
  end

  @spec parse_vm_measurement!(term()) :: measurement() | no_return()
  defp parse_vm_measurement!(measurement) when measurement in @vm_measurements do
    vm_measurement(measurement)
  end

  defp parse_vm_measurement!(other) do
    raise ArgumentError, "unknown VM measurement #{inspect(other)}"
  end

  @spec vm_measurement(function :: atom()) :: measurement()
  @spec vm_measurement(function :: atom(), args :: list()) :: measurement()
  defp vm_measurement(function, args \\ []) do
    {Telemetry.Poller.VM, function, args}
  end
end
