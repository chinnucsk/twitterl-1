%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012 Juan Jose Comellas, Mahesh Paolini-Subramanya
%%% @doc Main module for the twitterl_processor supervisor
%%% @end
%%%-------------------------------------------------------------------
-module(twitterl_processor_sup).
-author('Juan Jose Comellas <juanjo@comellas.org>').
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_processor/1]).

%% Supervisor callbacks
-export([init/1]).

%% ------------------------------------------------------------------
%% Includes & Defines
%% ------------------------------------------------------------------
-include("defaults.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(Id, Type, Module, Args), {Id, {Module, start_link, Args}, permanent, 5000, Type, [Module]}).

%% ===================================================================
%% API functions
%% ===================================================================

-spec start_processor(RequestType::request_type) -> any().
start_processor(RequestType) ->
    supervisor:start_child(?MODULE, [RequestType]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    TwitterProcessor = ?CHILD(?TWITTERL_PROCESSOR_SUP, worker, ?TWITTERL_PROCESSOR, []),
    {ok, { {simple_one_for_one, 5, 300}, [TwitterProcessor]} }.
