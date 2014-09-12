%%%=============================================================================
%%% @author Ramon Lastres <ramon.lastres@erlang-solutions.com>
%%% @doc Code that parses a config file in JSON format and creates a LINC switch
%%% Erlang term part of the sys.config file
%%% Of course it needs to have JSX in the path to work!
%%% @end
%%%=============================================================================
-module(config_generator).

-export([parse/4]).

%%%=============================================================================
%%% Api functions
%%%=============================================================================

%%%=============================================================================
%%% @doc Takes a file name and returns the 'linc' element that is supposed to 
%%% be part of the sys.config file
%%% @end
%%%=============================================================================
-spec parse(Filename :: file:name_all(),
            FileTemplate :: file:name_all(),
            ControllerIP :: string(),
            Port :: integer()) -> {linc, [tuple()]}.
parse(Filename, FileTemplate, ControllerIP, Port) ->
    {ok, Binary} = file:read_file(Filename),
    {ok, [Config]} = file:consult(FileTemplate),
    Json = jsx:decode(Binary),
    SwitchConfig = proplists:get_value(<<"switchConfig">>, Json),
    LinkConfig = proplists:get_value(<<"linkConfig">>, Json),
    Linc = generate_linc_element(SwitchConfig, LinkConfig, ControllerIP, Port),
    FinalConfig = [Linc] ++ Config,
    ok = file:write_file("sys.config",io_lib:fwrite("~p.\n", [FinalConfig])).


%%%=============================================================================
%%% Internal Functions
%%%=============================================================================

packet2optical_links(LinkConfig) ->
    lists:filter(fun(X) -> lists:member({<<"type">>, <<"pktOptLink">>}, X) end,
                 LinkConfig).

optical_links(LinkConfig) ->
    lists:filter(fun(X) -> lists:member({<<"type">>, <<"wdmLink">>}, X) end,
                 LinkConfig).

get_logical_switches(SwitchConfig, LinkConfig, ControllerIP, Port) ->
    Dpids = get_switches_dpids(SwitchConfig),
    DpidsToNumber = get_dpids2number(SwitchConfig),
    OpticalLinks = get_optical_links(LinkConfig, SwitchConfig),
    OpticalLinkPorts = get_p2o_links_ports(LinkConfig, SwitchConfig),
    lists:map(fun(X) -> generate_switch_element(X, OpticalLinks,
                                                OpticalLinkPorts, ControllerIP,
                                                Port, DpidsToNumber)
        end, Dpids).

get_switches_dpids(SwitchConfig) ->
    lists:map(fun(X) -> proplists:get_value(<<"nodeDpid">>, X) end,
              SwitchConfig).

get_dpids2number(SwitchConfig) ->
    Dpids = get_switches_dpids(SwitchConfig),
    lists:zip(Dpids, lists:seq(1, length(Dpids))).

%We want the optical port and dpid.
parse_packet2optical_link(P2OLink, SwitchConfig) ->
    Dpids = get_switches_dpids(SwitchConfig),
    DpidsToNumber = get_dpids2number(SwitchConfig),
    Params = proplists:get_value(<<"params">>, P2OLink),
    Dpid1 = proplists:get_value(<<"nodeDpid1">>, P2OLink),
    Dpid2 = proplists:get_value(<<"nodeDpid2">>, P2OLink),
    case lists:member(Dpid1, Dpids) of
        true ->
            {proplists:get_value(Dpid1, DpidsToNumber),
             proplists:get_value(<<"port1">>, Params)};
        _ ->
            {proplists:get_value(Dpid2, DpidsToNumber),
             proplists:get_value(<<"port2">>, Params)}
    end.

parse_optical_link(OpticalLink, DpidsToNumber) ->
    Params = proplists:get_value(<<"params">>, OpticalLink),
    [{proplists:get_value(proplists:get_value(<<"nodeDpid1">>, OpticalLink),
                          DpidsToNumber),
      proplists:get_value(<<"port1">>, Params)},
     {proplists:get_value(proplists:get_value(<<"nodeDpid2">>, OpticalLink),
                          DpidsToNumber),
      proplists:get_value(<<"port2">>, Params)}].

get_p2o_links_ports(LinkConfig, SwitchConfig) ->
    lists:map(fun(X) -> parse_packet2optical_link(X, SwitchConfig) end,
              packet2optical_links(LinkConfig)).

get_optical_links(LinkConfig, SwitchConfig) ->
    DpidsToNumber = get_dpids2number(SwitchConfig),
    lists:map(fun(X) -> parse_optical_link(X, DpidsToNumber) end,
              optical_links(LinkConfig)).

optical_port_element([{_SwitchNum1, PortNumber1},
                      {_SwitchNum2, PortNumber2}]) ->
    [{port, PortNumber1, [{interface, "dummy"}, {type, optical}]},
     {port, PortNumber2, [{interface, "dummy"}, {type, optical}]}].

p2o_port_element({_Dpid, PortNumber}) ->
    {port, PortNumber, [{interface, "tap" ++ integer_to_list(PortNumber)}]}.

get_switch_ports(SwitchDpid, OpticalLinks, P2OLinkPorts) ->
    List = lists:flatten(OpticalLinks ++ P2OLinkPorts),
    [Port || {Dpid, Port} <- List, Dpid == SwitchDpid].

get_capable_switch_ports(LinkConfig, SwitchConfig) ->
    List = lists:flatten(lists:map(fun optical_port_element/1,
                          get_optical_links(LinkConfig, SwitchConfig)) ++
                lists:map(fun p2o_port_element/1,
                          get_p2o_links_ports(LinkConfig, SwitchConfig))),
    lists:usort(List).

generate_switch_element(SwitchDpid, OpticalLinks, OpticalLinkPorts,
                        ControllerIP, Port, DpidsToNumber) ->
    Ports = lists:usort(
            get_switch_ports(proplists:get_value(SwitchDpid, DpidsToNumber),
                                                 OpticalLinks, OpticalLinkPorts)),
    {switch, proplists:get_value(SwitchDpid, DpidsToNumber),
     [{backend,linc_us4_oe},
      {dpid, binary_to_list(SwitchDpid)},
      {controllers,[{"Switch0-Controller", ControllerIP, Port, tcp}]},
      {controllers_listener,disabled},
      {queues_status,disabled},
      {ports, lists:map(fun port_queue_element/1, Ports)}]}.

port_queue_element(PortNumber) ->
    {port, PortNumber, {queues, []}}.

generate_linc_element(SwitchConfig, LinkConfig, ControllerIP, Port) ->
    {linc,
     [{of_config, disabled},
      {capable_switch_ports,  get_capable_switch_ports(LinkConfig,
                                                       SwitchConfig)},
      {capable_switch_queues, []},
      {optical_links, get_optical_links(LinkConfig, SwitchConfig)},
      {logical_switches, get_logical_switches(SwitchConfig, LinkConfig,
                                              ControllerIP, Port)}]}.
