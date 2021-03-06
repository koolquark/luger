-module(luger_test).

-include("src/luger.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(NOW, {{0, 0, 0}, {0, 0, 0}}).
-define(FACILITY, 23).

-define(assert_log_line(Logger, Source, ExpPriority, ExpChannel, ExpMessage),
        fun() ->
                [Line] = case logger_get(Logger, Source) of L when L /= undefined -> L end,
                ExpLine = format_log(Source, ExpPriority, ExpChannel, ExpMessage),
                ?assertEqual(iolist_to_binary(ExpLine), iolist_to_binary(Line))
        end()).

-define(assert_log_count(Logger, Source, ExpectedCount),
        fun() ->
                Count = logger_count(Logger, Source, 0),
                ?assert(Count == ExpectedCount)
        end()).


-define(assert_log_monitor(Logger, Source),
        fun() ->
                timer:sleep(100), % wait for asynchronous message to show up
                case logger_get(Logger, Source) of L when L /= undefined -> L end
        end()).

-define(assert_log_empty(Logger),
        begin
            ?assertMatch(undefined, logger_get(Logger, null)),
            ?assertMatch(undefined, logger_get(Logger, syslog)),
            ?assertMatch(undefined, logger_get(Logger, stderr))
        end).

% I f'n hate eunit...
-define(T(Name, Body),
        fun(Logger) ->
                {Name, ?_test(begin _ = Logger, Body end)}
        end).

no_start_test_() ->
    {foreach,
     fun () -> setup() end,
     fun (Logger) -> terminate(Logger) end,
     [
      ?T("luger not started",
         begin
             {error, _} = luger:alert("start.alert", "format: ~s", ["blah"]),
             ?assert_log_empty(Logger)
         end)
     ]}.

basics_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, type, stderr),
             application:start(luger),
             setup()

     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,

     [
      ?T("basics - channel",
         begin
             ok = luger:alert("channels.string", "blah"),
             ?assert_log_line(Logger, stderr, alert, "channels.string", "blah"),

             ok = luger:alert(<<"channels.bin">>, "blah"),
             ?assert_log_line(Logger, stderr, alert, "channels.bin", "blah"),

             ok = luger:alert(["channels", [$., <<"iolist">>]], "blah"),
             ?assert_log_line(Logger, stderr, alert, "channels.iolist", "blah"),

             ok = luger:alert([128 | ".channels.encoding.string"], "blah"),
             ?assert_log_line(Logger, stderr, alert, [128, ".channels.encoding.string"], "blah"),

             ok = luger:alert(<<128, ".channels.encoding.bin">>, "blah"),
             ?assert_log_line(Logger, stderr, alert, [128 | ".channels.encoding.bin"], "blah"),

             ?assert_log_empty(Logger)
         end),

      ?T("basics - message",
         begin
             ok = luger:alert("messages.string", "blah"),
             ?assert_log_line(Logger, stderr, alert, "messages.string", "blah"),

             ok = luger:alert("messages.bin", <<"blah">>),
             ?assert_log_line(Logger, stderr, alert, "messages.bin", "blah"),

             ok = luger:alert("messages.iolist", [<<"foo">>, $\s, "bar"]),
             ?assert_log_line(Logger, stderr, alert, "messages.iolist", "foo bar"),

             ok = luger:alert("messages.fmt", "~p ~s", [foo, "bar"]),
             ?assert_log_line(Logger, stderr, alert, "messages.fmt", "foo bar"),

             ok = luger:alert("messages.encoding.string", [128 | "blah"]),
             ?assert_log_line(Logger, stderr, alert, "messages.encoding.string", [128 | "blah"]),

             ok = luger:alert("messages.encoding.bin", <<128, "blah">>),
             ?assert_log_line(Logger, stderr, alert, "messages.encoding.bin", <<128, "blah">>),

             ?assert_log_empty(Logger)
         end)
     ]}.

stderr_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, type, stderr),
             application:start(luger),
             setup()
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [
      ?T("stderr - basics",
         begin
             ok = luger:alert("stderr.alert", "format: ~s", ["blah"]),
             ?assert_log_line(Logger, stderr, alert, "stderr.alert", "format: blah"),

             ok = luger:error("stderr.error", "format: ~B", [10]),
             ?assert_log_line(Logger, stderr, error, "stderr.error", "format: 10"),

             ok = luger:warning("stderr.warn", "format: ~p", [blah]),
             ?assert_log_line(Logger, stderr, warning, "stderr.warn", "format: blah"),

             % dropped due to log threshold
             ok = luger:info("stderr.info", "msg"),
             ok = luger:debug("stderr.debug", "msg"),
             ?assert_log_empty(Logger)
         end),

      ?T("stderr - truncation",
         begin
             ok = luger:alert(string:chars($a, 32, "b"), "msg"),
             ?assert_log_line(Logger, stderr, alert, string:chars($a, 32), "msg"),

             ok = luger:alert("stderr.trunc", string:chars($a, 2048, "b")),
             ?assert_log_line(Logger, stderr, alert, "stderr.trunc", string:chars($a, 2048)),

             ?assert_log_empty(Logger)
         end)
     ]}.


stderr_prio_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, type, stderr),
             application:set_env(luger, stderr_min_priority, debug),
             application:start(luger),
             setup()
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [
      ?T("stderr - min priority",
         begin
             ok = luger:alert("stderr.prio.alert", "format: ~s", ["blah"]),
             ?assert_log_line(Logger, stderr, alert, "stderr.prio.alert", "format: blah"),

             ok = luger:error("stderr.prio.error", "format: ~B", [10]),
             ?assert_log_line(Logger, stderr, error, "stderr.prio.error", "format: 10"),

             ok = luger:warning("stderr.prio.warn", "format: ~p", [blah]),
             ?assert_log_line(Logger, stderr, warning, "stderr.prio.warn", "format: blah"),

             ok = luger:info("stderr.prio.info", "msg"),
             ?assert_log_line(Logger, stderr, info, "stderr.prio.info", "msg"),

             ok = luger:debug("stderr.prio.debug", "msg"),
             ?assert_log_line(Logger, stderr, debug, "stderr.prio.debug", "msg"),

             ?assert_log_empty(Logger)
         end)
     ]}.

syslog_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, type, syslog_udp),
             application:set_env(luger, syslog_udp_host, {127, 0, 0, 1}),
             application:set_env(luger, syslog_udp_port, 514),
             application:set_env(luger, syslog_udp_facility, ?FACILITY),
             application:start(luger),
             setup()
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [
      ?T("syslog - basics",
         begin
             ok = luger:alert("syslog.alert", "format: ~s", ["blah"]),
             ?assert_log_line(Logger, syslog, alert, "syslog.alert", "format: blah"),

             ok = luger:error("syslog.error", "format: ~B", [10]),
             ?assert_log_line(Logger, syslog, error, "syslog.error", "format: 10"),

             ok = luger:warning("syslog.warn", "format: ~p", [blah]),
             ?assert_log_line(Logger, syslog, warning, "syslog.warn", "format: blah"),

             ok = luger:info("syslog.info", "msg"),
             ?assert_log_line(Logger, syslog, info, "syslog.info", "msg"),

             ok = luger:debug("syslog.debug", "msg"),
             ?assert_log_line(Logger, syslog, debug, "syslog.debug", "msg"),

             ?assert_log_empty(Logger)
         end),

      ?T("syslog - truncation",
         begin
             ok = luger:alert(string:chars($a, 32, "b"), "msg"),
             ?assert_log_line(Logger, syslog, alert, string:chars($a, 32), "msg"),

             ok = luger:alert("trunc", string:chars($a, 2048, "b")),
             ?assert_log_line(Logger, syslog, alert, "trunc", string:chars($a, 2048)),

             ?assert_log_empty(Logger)
         end)
     ]}.

error_logger_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, type, stderr),
             application:start(luger),
             setup()
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [

      %% Creates an unknown number of line and I can't be bothered to
      %% figure out what is what from where so we just check that we
      %% got something and walk away happy.
      ?T("error monitor - basics",
         begin
             error_logger:error_msg("error_msg: ~p ~p", [{blah, blah}, bleh]),
             ?assert_log_monitor(Logger, stderr),

             error_logger:error_report("error_report"),
             ?assert_log_monitor(Logger, stderr)
         end)
     ]}.


null_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_null_test"),
             application:set_env(luger, type, null),
             application:start(luger),
             setup()
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [
      ?T("log nothing",
         begin
             ok = luger:emergency("null.prio.emergency", "format: ~s", ["blah"]),
             ok = luger:alert("null.prio.alert", "format: ~s", ["blah"]),
             ok = luger:critical("null.prio.critical", "format: ~s", ["blah"]),
             ok = luger:error("null.prio.error", "format: ~B", [10]),
             ok = luger:warning("null.prio.warning", "format: ~p", [blah]),
             ok = luger:info("null.prio.info", "msg"),
             ok = luger:notice("null.prio.notice", "msg"),
             ok = luger:debug("null.prio.debug", "msg"),
             ?assert_log_empty(Logger)
         end)
     ]
    }.


%% These tests might be a bit flaky due to their reliance on
%% time. They were design to reduce this flakyness though at the cost
%% of potential false-positives. Should iron out over many executions.
throttling_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, type, stderr),
             application:set_env(luger, throttle_threshold, 3),
             application:start(luger),
             Logger = setup(),
             meck:expect(luger_utils, get_time,
                fun () -> luger_test_server:get_time() end),
             Logger
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [
      ?T("throttling",
         begin
             [luger:alert("throttling.main", "msg") || _ <- lists:seq(0, 100)],
             ?assert_log_count(Logger, stderr, 3),
             ?assert_log_empty(Logger),

             luger:alert("throttling.other", "msg"),
             ?assert_log_count(Logger, stderr, 1),
             ?assert_log_empty(Logger),

             sleep(1000),
             luger:alert("throttling.main", "msg"),
             % ensure luger emitted "dropped N messages", which will also call
             % luger:record_metrics/3 one extra time
             ?assert_log_count(Logger, stderr, 1 + 1),
             ?assert_log_empty(Logger),

             sleep(1000),
             [luger:alert("throttling.main", "msg") || _ <- lists:seq(0, 100)],
             ?assert_log_count(Logger, stderr, 3),
             ?assert_log_empty(Logger)
         end)
     ]}.

single_line_test_() ->
    {foreach,
     fun() ->
             application:load(luger),
             application:set_env(luger, app_name, "luger_test"),
             application:set_env(luger, single_line, true),
             application:set_env(luger, type, stderr),
             application:start(luger),
             setup()
     end,
     fun(Logger) ->
             terminate(Logger),
             application:stop(luger)
     end,
     [

      ?T("single line",
         begin
             luger:alert("topic", "blah \n   blah\n\n\n blah   \n   "),
             ?assert_log_line(Logger, stderr, alert, "topic", "blah blah blah"),

             luger:alert("topic", "blah     blah blah      "),
             ?assert_log_line(Logger, stderr, alert, "topic", "blah blah blah")
         end)
     ]}.


format_log(stderr, Priority, Channel, Message) ->
    io_lib:format(
      "<~p> 0000-00-00T00:00:00 ~s luger_test ~p ~s  ~s~n",
      [Priority, luger_utils:hostname(), self(), Channel, Message]);
format_log(syslog, Priority, Channel, Message) ->
    PriorityNum = ?FACILITY * 8 +  case Priority of
                                       alert -> ?ALERT;
                                       error -> ?ERROR;
                                       warning -> ?WARNING;
                                       info -> ?INFO;
                                       debug -> ?DEBUG
                                   end,
    io_lib:format(
      "<~p>1 0000-00-00T00:00:00 ~s luger_test ~p ~s  ~s",
      [PriorityNum, luger_utils:hostname(), self(), Channel, Message]).

logger_get(Logger, Source) ->
    gen_server:call(Logger, {get, Source}).

logger_count(Logger, Source, Acc) ->
    case logger_get(Logger, Source) of
        undefined -> Acc;
        Msgs -> logger_count(Logger, Source, Acc + length(Msgs))
    end.

sleep(Ms) ->
    luger_test_server:inc_time(Ms).

setup() ->
    {ok, Logger} = luger_test_server:start_link(),

    % This file handle intentionally gets leaked.
    {ok, SinkHole} = file:open("/dev/null", write),

    meck:new(luger_utils, [passthrough]),
    meck:expect(luger_utils, send_syslog,
                fun (_, _, _, Line) -> luger_test_server:log(syslog, Line) end),
    meck:expect(luger_utils, send_stderr,
                fun (Line) ->
                        % Forwarding to /dev/null tests for encoding
                        % issues.
                        luger_utils:send_stderr(SinkHole, Line),
                        luger_test_server:log(stderr, Line)
                end),

    meck:new(calendar, [unstick]),
    meck:expect(calendar, local_time, fun () -> ?NOW end),

    Logger.

terminate(Logger) ->
    meck:unload(calendar),
    meck:unload(luger_utils),
    Logger ! close.
