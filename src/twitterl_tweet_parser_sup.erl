%%%-------------------------------------------------------------------
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2012 Juan Jose Comellas, Mahesh Paolini-Subramanya
%%% @doc Main module for the twitterl_tweet_parser supervisor
%%% @end
%%%-------------------------------------------------------------------
-module(twitterl_tweet_parser_sup).
-author('Juan Jose Comellas <juanjo@comellas.org>').
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([start_tweet_parser/0]).

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

start_tweet_parser() ->
    supervisor:start_child(?MODULE, ?CHILD(make_ref(), worker, ?TWITTERL_TWEET_PARSER, [])).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    NumTweetParsers = twitterl:get_env(?TWITTERL_TWEET_PARSER_COUNT, 1),
    TweetParsers = lists:foldl(fun(_X, Acc) -> 
                    [?CHILD(make_ref(), worker, ?TWITTERL_TWEET_PARSER, []) | Acc]
            end, [], lists:seq(1, NumTweetParsers)),
    {ok, { {one_for_one, 5, 300}, TweetParsers} }.
