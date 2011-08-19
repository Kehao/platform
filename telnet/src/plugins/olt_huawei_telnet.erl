-module(olt_huawei_telnet).

-author("hejin 2011-8-17").

-export([start/1,
        get_data/2, get_data/3,
        close/2
        ]).

-include("elog.hrl").

-define(CONN_TIMEOUT, 10000).
-define(CMD_TIMEOUT, 3000).

-define(username, "User name:").
-define(password, "User password:").
-define(termchar, "#$|>$").
-define(page, "-- More ").
-define(prx,"User name:|User password:|#$|>$|-- More ").

-define(keepalive, true).

-define(splite, "\n").

start(Opts) ->
    init(Opts).

%flow
get_data(Pid, Head) ->
    get_data(Pid, "enable", Head),
    {ok, Data1} = get_data(Pid, "display current-configuration", Head),
    ?INFO("get data1 :~p", [Data1]),
    {ok, Data2} = get_data(Pid, "", Head),
    ?INFO("get data2 :~p", [Data2]),
    {ok, {Data1 ++ Data2}}.

get_data(Pid, Cmd, Head) ->
    get_data(Pid, Cmd, Head, [], []).


get_data(Pid, Cmd, Head, Acc, LastLine) ->
    NewPrx = ?prx ++ "|" ++ Head,
    case telnet_gen_conn:teln_cmd(Pid, Cmd, NewPrx, ?CMD_TIMEOUT) of
        {ok, Data, ?page, Rest} ->
            Lastline1 = string:strip(lists:last(Data)),
            ?INFO("more: ~p, lastline: ~p, ~n, Rest : ~p", [Data, Lastline1, Rest]),
            Data1 =  string:join(Data, ?splite),
            get_data(Pid, " ", Head, [Data1|Acc], Lastline1);
        {ok, Data, PromptType, Rest} ->
            ?INFO("Return: ~p, PromptType : ~p, ~n, Rest :~p", [Data, PromptType, Rest]),
            Data1 =  string:join(Data, ?splite),
            AllData = string:join(lists:reverse([Data1|Acc]), ?splite),
            {ok, AllData};
        Error ->
            ?WARNING("Return error: ~p", [Error]),
            Data1 = io_lib:format("telnet send cmd error, cmd: ~p, reason:~p", [Cmd, Error]),
            AllData = string:join(lists:reverse([Data1|Acc]), ?splite),
            {ok, AllData}
    end.

close(Pid, Head) ->
    get_data(Pid, "quit", Head),
    get_data(Pid, "y", Head),
    telnet_client:close(Pid).

init(Opts) ->
    io:format("starting telnet conn ...~p",[Opts]),
    Host = proplists:get_value(host, Opts, "localhost"),
    Port = proplists:get_value(port, Opts, 23),
    Username = proplists:get_value(username, Opts),
    Password = proplists:get_value(password, Opts),
    case (catch connect(Host, Port, ?CONN_TIMEOUT, ?keepalive, Username, Password)) of
	{ok, Pid, Head} ->
	    {ok, Pid, Head};
	{error, Error} ->
	    {stop, Error};
    {'EXIT', Reason} ->
        {stop, Reason}
	end.

connect(Ip,Port,Timeout,KeepAlive,Username,Password) ->
    ?INFO("telnet:connect",[]),
    Result =case telnet_client:open(Ip,Port,Timeout,KeepAlive) of
                {ok,Pid} ->
                    ?INFO("open success...~p",[Pid]),
                    case telnet:silent_teln_expect(Pid,[],[prompt],?prx,[]) of
                        {ok,{prompt,?username},_} ->
                            ok = telnet_client:send_data(Pid,Username),
                            ?INFO("Username: ~s",[Username]),
                            case telnet:silent_teln_expect(Pid,[],prompt,?prx,[]) of
                                {ok,{prompt,?password},_} ->
                                    ok = telnet_client:send_data(Pid,Password),
%                                   Stars = lists:duplicate(length(Password),$*),
                                    ?INFO("Password: ~s",[Password]),
%                                   ok = telnet_client:send_data(Pid,""),
                                    case telnet:silent_teln_expect(Pid,[],prompt,
                                                                   ?termchar,[]) of
                                        {ok,{prompt,Prompt},Rest}  ->
                                            ?INFO("get login over.....propmpt:~p,~p", [Prompt, Rest]),
                                            case telnet_gen_conn:teln_cmd(Pid, "", ?termchar, ?CMD_TIMEOUT) of
                                                {ok, Data, PromptType, Rest} ->
                                                    ?INFO("get head data .....propmpt:~p,~p", [Data, PromptType]),
                                                    {ok, Pid, string:join(lists:reverse(Data), "")};
                                                Error ->
                                                    {error,Error}
                                            end;
                                        Error ->
                                            ?WARNING("Password failed\n~p\n",
                                                     [Error]),
                                            {error,Error}
                                    end;
                                Error ->
                                    ?WARNING("Login failed\n~p\n",[Error]),
                                    {error,Error}
                            end;
                        {ok,[{prompt,_OtherPrompt1},{prompt,_OtherPrompt2}],_} ->
                            {ok,Pid, "$"};
                        Error ->
                            ?WARNING("Did not get expected prompt\n~p\n",[Error]),
                            {error,Error}
                    end;
                Error ->
                    ?WARNING("Could not open telnet connection\n~p\n",[Error]),
                    {error, Error}
            end,
    Result.
