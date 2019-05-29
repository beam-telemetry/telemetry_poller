%%%---------------------------------------------------
%% @doc
%% A time-based poller to periodically dispatch Telemetry events.
%%
%% Poller comes with a built-in poller but also allows you to run
%% your own. Let's see how.
%%
%% == Built-in poller ==
%%
%% A single poller is started under the `telemetry_poller' application.
%% It is started with name `telemetry_poller_default' and its goal is
%% to perform common VM measurements.
%%
%% By default, it polls all default VM measurements, but you
%% may specify all VM measurements you want:
%%
%% `[{vm_measurements, [memory}] # measure only the memory'
%%
%% You can disable the default poller by setting it to `false' in
%% your config.
%%
%% Let's take a closer look at the available measurements.
%%
%% === Memory (default) ===
%%
%% An event emitted as `[vm, memory]'. The measurement includes all the key-value
%% pairs returned by {@link erlang:memory/0} function, e.g. `total' for total memory,
%% `processes_used' for memory used by all processes, etc.
%%
%% === Run queue lengths (default) ===
%%
%% On startup, the Erlang VM starts many schedulers to do both IO and CPU work. If a process
%% needs to do some work or wait on IO, it is allocated to the appropriate scheduler. The run
%% queue is a queue of tasks to be scheduled. A length of a run queue corresponds to the amount
%% of work accumulated in the system. If a run queue length is constantly growing, it means that
%% the BEAM is not keeping up with executing all the tasks.
%%
%% There are several run queue types in the Erlang VM. Each CPU scheduler (usually one per core)
%% has its own run queue, and since Erlang 20.0 there is one dirty CPU run queue, and one dirty
%% IO run queue.
%%
%% The run queue length event is emitted as `[vm, total_run_queue_lengths]'. The event contains
%% no metadata and three measurements:
%% <ul>
%% <li>`total' - a sum of all run queue lengths</li>
%% <li>`cpu' - a sum of CPU schedulers' run queue lengths, including dirty CPU run queue length on Erlang version 20 and greater</li>
%% <li>`io' - length of dirty IO run queue. It's always 0 if running on Erlang versions prior to 20.</li>
%% </ul>
%% Note that the method of making this measurement varies between different Erlang versions: for
%% Erlang 18 and 19, the implementation is less efficient than for version 20 and up.
%%
%% The length of all queues is not gathered atomically, so the event value does not represent
%% a consistent snapshot of the run queues' state. However, the value is accurate enough to help
%% to identify issues in a running system.
%%
%% === Custom pollers ===
%%
%% Telemetry poller also allows you to perform custom measurements by spawning
%% your own poller process:
%% ```
%% {measurements, [myapp_example, measure, []]}
%% '''
%%
%% For custom pollers, the measurements are given as MFAs. Those MFAs should
%% dispatch an event using `telemetry:execute/3' function. If the invokation
%% of the MFA fails, the measurement is removed from the Poller.
%%
%% For all options, see {@link start_link/1}. The options listed there can be given
%% to the default poller as well as to custom pollers.
%%
%% === Example - measuring message queue length of the process ===
%%
%% Measuring process' message queue length is a good way to find out if and when the
%% process becomes the bottleneck. If the length of the queue is growing, it means that
%% the process is not keeping up with the work it's been assigned and other processes
%% asking it to do the work will get timeouts. Let's try to simulate that situation
%% using the following gen_server:
%%
%% ```
%% -module(worker).
%% -behaviour(gen_server).
%%
%% start_link(Name) ->
%%    gen_server:start_link(?MODULE, [], [{name, Name}]).
%%
%% init([]) ->
%%    {ok, #{}}.
%%
%% do_work(Name) ->
%%    gen_server:call(Name, do_work, [{timeout, 5000}]).
%%
%% handle_call(do_work, _, State) ->
%%    timer:sleep(1000).
%%
%% ...
%% '''
%%
%% When assigned with work (`handle_call/3'), the worker will sleep for 1 second to
%% imitate long running task.
%% Now we need a measurement dispatching the process info so that we can
%% extract the message queue length of the worker:
%%
%% ```
%% -module(example_app_measurements).
%%
%% message_queue_length(Name) ->
%%    Pid = erlang:whereis(Name),
%%    ProcessInfo = erlang:process_info(Pid),
%%    telemetry:execute([example_app, process_info], ProcessInfo, #{name => Name}).
%% '''
%%
%% In order to observe the message queue length we can install the event handler printing it out to
%% the console:
%% ```
%% -module(message_length_handler).
%%
%% handle([example_app, process_info], #{message_queue_length => Length}, #{name => Name}) ->
%%    io:format("Process ~p~n message queue length: ~p", [Name, Length]).
%% '''
%%
%% Let's start the worker and poller with the just defined measurement:
%%
%% ```
%% # erl
%% > Name = my_worker.
%% > {ok, Pid} = worker:start_link(Name).
%% > telemetry_poller:start_link([{measurements, [{example_app_measurements, process_info}, [Name]}], {period, 2000}]).
%% > telemetry:attach(handler, [example_app, process_info], message_length_handler:handle/4, nil).
%% '''
%%
%% Now let's start assigning work to the worker:
%%
%% ```
%% #erl
%% > Name = my_worker.
%% > Iterations = lists:seq(1, 1000).
%% > lists:map(fun(I) -> erlang:spawn_link(fun() -> worker:do_work(Name) end.), timer:sleep(500) end.).
%% '''
%%  Here we start 1000 processes placing a work order, waiting 500 milliseconds after starting each
%% one. Given that the worker does its work in 1000 milliseconds, it means that new work orders come
%% twice as fast as the worker is able to complete them. In the console, you'll see something like
%% this:
%%
%% ```
%% Process MyWorker message queue length: 1
%% Process MyWorker message queue length: 3
%% Process MyWorker message queue length: 5
%% Process MyWorker message queue length: 7
%% '''
%%
%% and finally:
%%
%% ```
%% ** (EXIT from #PID<0.168.0>) shell process exited with reason: exited in: :gen_server.call(worker, do_work, 5000)
%% ** (EXIT) time out
%% '''
%%
%% The worker wasn't able to complete the work on time (we set the 5000 millisecond timeout) and
%% `worker:do_work/1' finally failed. Observing the message queue length metric allowed us to notice
%% that the worker is the system's bottleneck. In a healthy situation the message queue length would
%% be roughly constant.
%%
%% === Example - tracking number of active sessions in web application ===
%%
%% Let's imagine that you have a web application and you would like to periodically measure number
%% of active user sessions.
%%
%% ```
%% -module(example_app).
%%
%% session_count() ->
%%    % logic for calculating session count.
%% '''
%%
%% To achieve that, we need a measurement dispatching the value we're interested in:
%%
%% ```
%% -module(example_app_measurements).
%%
%% dispatch_session_count() ->
%%    telemetry:execute([example_app, session_count], example_app:session_count()).
%% '''
%%
%% and tell the Poller to invoke it periodically:
%%
%% ```
%% telemetry_poller:start_link([{measurements, [{example_app_measurements, dispatch_session_count, []}]).
%% '''
%%
%% If you find that you need to somehow label the event values, e.g. differentiate between number of
%% sessions of regular and admin users, you could use event metadata:
%%
%% ```
%% -module(example_app_measurements).
%%
%% dispatch_session_count() ->
%%    Regulars = example_app:regular_users_session_count(),
%%    Admins = example_app:admin_users_session_count(),
%%    telemetry:execute([example_app, session_count], #{count => Admins}, #{role => admin}),
%%    telemetry:execute([example_app, session_count], #{count => Regulars}, #{role => regular}).
%% '''
%%
%% <blockquote>Note: the other solution would be to dispatch two different events by hooking up
%% `example_app:regular_users_session_count/0' and `example_app:admin_users_session_count/0'
%% functions directly. However, if you add more and more user roles to your app, you'll find
%% yourself creating a new event for each one of them, which will force you to modify existing
%% event handlers. If you can break down event value by some feature, like user role in this
%% example, it's usually better to use event metadata than add new events.
%% </blockquote>
%%
%% This is a perfect use case for poller, because you don't need to write a dedicated process
%% which would call these functions periodically. Additionally, if you find that you need to collect
%% more statistics like this in the future, you can easily hook them up to the same poller process
%% and avoid creating lots of processes which would stay idle most of the time.
%% @end
%%%---------------------------------------------------
-module(telemetry_poller).

-behaviour(gen_server).

%% API
-export([
    child_spec/1,
    list_measurements/1,
    start_link/1
]).

-export([code_change/3, handle_call/3, handle_cast/2,
     handle_info/2, init/1, terminate/2]).

-define(DEFAULT_VM_MEASUREMENTS, [memory, total_run_queue_lengths]).

-ifdef('OTP_RELEASE').
-include_lib("kernel/include/logger.hrl").
-else.
-define(LOG_ERROR(Msg, Args), error_logger:error_msg(Msg, Args)).
-endif.

-ifdef('OTP_RELEASE').
-include_lib("kernel/include/logger.hrl").
-else.
-define(LOG_WARNING(Msg, Args), error_logger:warning_msg(Msg, Args)).
-endif.

-ifdef('OTP_RELEASE').
-define(WITH_STACKTRACE(T, R, S), T:R:S ->).
-else.
-define(WITH_STACKTRACE(T, R, S), T:R -> S = erlang:get_stacktrace(),).
-endif.

-type t() :: gen_server:server().
-type options() :: [option()].
-type option() ::
    {name, gen_server:name()
    | {period, period()}
    | {measurements, [measurement()]}
    | {vm_measurements, default | [vm_measurement()]}}.
-type measurement() :: {module(), atom(), []}.
-type period() :: pos_integer().
-type vm_measurement() ::
    memory
    | total_run_queue_lengths.
-type state() :: #{measurements => [measurement()], period => period()}.

%% @doc Starts a poller linked to the calling process.
%%
%% Useful for starting Pollers as a part of a supervision tree.
-spec start_link(options()) -> gen_server:on_start().
start_link(Opts) when is_list(Opts) ->
    Name = proplists:get_value(name, Opts, ?MODULE),
    Args = parse_args(Opts),
    gen_server:start_link({local, Name}, ?MODULE, Args, []).

%% @doc
%% Returns a list of measurements used by the poller.
-spec list_measurements(t()) -> [measurement()].
list_measurements(Poller) ->
    gen_server:call(Poller, get_measurements).

-spec init(map()) -> {ok, state()}.
init(Args) ->
    schedule_measurement(0),
    {ok, #{
        measurements => maps:get(measurements, Args),
        period => maps:get(period, Args)}}.

%% @doc
%% Returns a child spec for the poller for running under a supervisor.
child_spec(Opts) ->
    Id =
        case proplists:get_value(name, Opts, telemetry_poller_default) of
            Name when is_atom(Name) -> Name;
            {global, Name} -> Name;
            {via, _, Name} -> Name
        end,

    #{
        id => Id,
        start => {telemetry_poller, start_link, [Opts]}
    }.

parse_args(Args) ->
    Measurements = proplists:get_value(measurements, Args, []),
    validate_measurements(Measurements),
    Period = proplists:get_value(period, Args, 5000),
    validate_period(Period),
    VMMeasurements = parse_vm_measurements(proplists:get_value(vm_measurements, Args, [])),

    #{measurements => Measurements ++ VMMeasurements, period => Period}.

-spec parse_vm_measurements([] | default) -> [vm_measurement()].
parse_vm_measurements([]) ->
    [];
parse_vm_measurements(default) ->
    parse_vm_measurements(?DEFAULT_VM_MEASUREMENTS);
parse_vm_measurements(Measurements) ->
    __Measurements = sets:from_list(Measurements),
    lists:map(fun parse_vm_measurement/1, sets:to_list(__Measurements)).

-spec parse_vm_measurement(measurement()) -> {telemetry_poller_vm, measurement(), list()} | no_return().
parse_vm_measurement(Measurement) ->
    case lists:member(Measurement, ?DEFAULT_VM_MEASUREMENTS) of
        true -> vm_measurement(Measurement);
        false -> erlang:error(badarg, Measurement)
    end.

-spec vm_measurement(atom()) -> measurement().
vm_measurement(Function) ->
    {telemetry_poller_vm, Function, []}.

-spec schedule_measurement(non_neg_integer()) -> ok.
schedule_measurement(CollectInMillis) ->
    erlang:send_after(CollectInMillis, self(), collect), ok.

-spec validate_period(term()) -> ok | no_return().
validate_period(Period) when is_integer(Period), Period > 0 ->
    ok;
validate_period(Term) ->
    erlang:error(badarg, Term).

-spec validate_measurements(term()) -> ok | no_return().
validate_measurements(Measurements) when is_list(Measurements) ->
    lists:map(fun validate_measurement/1, Measurements);
validate_measurements(Term) ->
    erlang:error(badarg, Term).

-spec validate_measurement(term()) -> ok | no_return().
validate_measurement({M, F, A}) when is_atom(M), is_atom(F), is_list(A) ->
    ok;
validate_measurement(Term) ->
    erlang:error(badarg, Term).

-spec make_measurements_and_filter_misbehaving([measurement()]) -> [measurement()].
make_measurements_and_filter_misbehaving(Measurements) ->
    Results = lists:map(fun make_measurement/1, Measurements),
    lists:filter(fun(error) -> false; (_) -> true end, Results).

-spec make_measurement(measurement()) -> measurement() | no_return().
make_measurement(Measurement = {M, F, A}) ->
    try erlang:apply(M, F, A) of
        _ -> Measurement
    catch
        ?WITH_STACKTRACE(Class, Reason, Stacktrace)
            ?LOG_ERROR("Error when calling MFA defined by measurement: ~p ~p ~p ."
                        "Exception: class=~p reason=~p stacktrace=~p",
                        [M, F, A, Class, Reason, Stacktrace]),
                               error
    end.

handle_call(get_measurements, _From, State = #{measurements := Measurements}) ->
    {reply, Measurements, State};
handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) -> {noreply, State}.

handle_info(collect, State) ->
    GoodMeasurements = make_measurements_and_filter_misbehaving(maps:get(measurements, State)),
    schedule_measurement(maps:get(period, State)),
    {noreply, State#{measurements := GoodMeasurements}};
handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
