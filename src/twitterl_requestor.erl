%%%-------------------------------------------------------------------
%%% @author Juan Jose Comellas <juanjo@comellas.org>
%%% @author Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>
%%% @copyright (C) 2011-2012 Juan Jose Comellas, Mahesh Paolini-Subramanya
%%% @doc Twitterl module that accepts requests
%%% @end
%%%
%%% This source file is subject to the New BSD License. You should have received
%%% a copy of the New BSD license with this software. If not, it can be
%%% retrieved from: http://www.opensource.org/licenses/bsd-license.php
%%%-------------------------------------------------------------------
-module(twitterl_requestor).

-author('Juan Jose Comellas <juanjo@comellas.org>').
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').


-author('Juan Jose Comellas <juanjo@comellas.org>').
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').
-behaviour(gen_server).

-compile([{parse_transform, lager_transform}]).

%% ------------------------------------------------------------------
%% API Function Exports
%% ------------------------------------------------------------------
-export([get_request/2, get_request/3, get_request/5, process_request/3, process_request/4,
         stop_request/1]).

% Authorization
-export([get_request_token/0, get_access_token/3]).
% Status
-export([update_status/3]).
%% ------------------------------------------------------------------
%% gen_server Function Exports
%% ------------------------------------------------------------------

-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ------------------------------------------------------------------
%% Includes & Defines
%% ------------------------------------------------------------------
-include("defaults.hrl").

%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------


%%% Viewing requests

%% @doc get the http Request associated with the URL
-spec get_request(method, url()) -> [{string(), string()}].
get_request(Method, URL) ->
    get_request(Method, URL, []).

%% @doc get the http Request associated with the URL and Params
-spec get_request(method(), url(), params()) -> [{string(), string()}].
get_request(Method, URL, Params) ->
    OAuthData = get_oauth_data(),
    create_request(OAuthData, Method, URL, Params).

%% @doc get the http Request associated with the URL and Params
-spec get_request(method(), url(), params(), token(), secret()) -> [{string(), string()}].
get_request(Method, URL, Params, Token, Secret) ->
    OAuthData = get_oauth_data(),
    create_request(OAuthData, Method, URL, Params, Token, Secret).


%%% Request processing

%% @doc Run the request on the URL in stream or REST mode. The result will be
%%          sent to Target
-spec process_request(Target::target(), URL::string(), RequestType::rest|stream) -> any().
process_request(Target, RequestType, URL) -> 
    process_request(Target, RequestType, URL, []).

%% @doc Run the request on the URL and Params in stream or REST mode. The result will be
%%          sent to Target
-spec process_request(Target::target(), RequestType::rest|stream, URL::string(), Params::list()) -> {ok, pid()} | error().
process_request(Target, RequestType, URL, Params) -> 
    twitterl_util:validate_request_type(RequestType),
    Request = get_request(URL, Params),
    twitterl_manager:safe_call({?TWITTERL_PROCESSOR, RequestType}, {request, Request, RequestType, Target}).

%% @doc Stop a given request gracefully
-spec stop_request(RequestId::request_id()) -> ok.
stop_request({ServerProcess, RequestPid}) ->
    gen_server:cast(ServerProcess, {stop_request, RequestPid}).

%%% Authorization

%% @doc Get a request token
-spec get_request_token() -> #twitter_token_data{} | error().
get_request_token() ->
    twitterl_manager:safe_call(?TWITTERL_REQUESTOR, {get_request_token}).

%% @doc Get a request token
-spec get_access_token(token(), secret(), verifier()) -> #twitter_access_data{} | error().
get_access_token(Token, Secret, Verifier) ->
    twitterl_manager:safe_call(?TWITTERL_REQUESTOR, {get_access_token, Token, Secret, Verifier}).

%% @doc Status
-spec update_status(token(), secret(), status()) -> #tweet{} | error().
update_status(Token, Secret, Status) ->
    twitterl_manager:safe_call(?TWITTERL_REQUESTOR, {update_status, Token, Secret, Status}).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------

start_link() ->
    gen_server:start_link(?MODULE, [], []).

init(_Args) ->
    twitterl_manager:register_process(?TWITTERL_REQUESTOR, ?TWITTERL_REQUESTOR),
    OAuthData = get_oauth_data(),
    State = #requestor_state{oauth_data = OAuthData},
    {ok, State}.

handle_call({get_request_token}, _From, State) ->
    OAuthData = State#requestor_state.oauth_data,
    Reply = case process_post(?TWITTER_REQUEST_TOKEN_URL, [{"oauth_callback", ?TWITTERL_CALLBACK_URL}], OAuthData) of
        {error, _} = Error ->
            Error;
        Response ->
            Data = oauth:params_decode(Response),
            validate_tokens(Data)
    end,
    {reply, Reply, State};

handle_call({get_access_token, Token, Secret, Verifier}, _From, State) ->
    OAuthData = State#requestor_state.oauth_data,
    SVerifier = twitterl_util:get_string(Verifier),
    SToken = twitterl_util:get_string(Token),
    SSecret = twitterl_util:get_string(Secret),
    Reply = case process_post(?TWITTER_ACCESS_TOKEN_URL, [{"oauth_verifier", SVerifier}], OAuthData, SToken, SSecret) of
        {error, _} = Error ->
            Error;
        Response ->
            Data = oauth:params_decode(Response),
            validate_access(Data)
    end,
    {reply, Reply, State};

handle_call({update_status, Token, Secret, Status}, _From, State) ->
    OAuthData = State#requestor_state.oauth_data,
%    SStatus = twitterl_util:get_string(bstr:urlencode(Status)),
    SStatus = twitterl_util:get_string(Status),
    SToken = twitterl_util:get_string(Token),
    SSecret = twitterl_util:get_string(Secret),
    Reply = case process_post(?TWITTER_STATUS_UPDATE_URL, [{"status", SStatus}], OAuthData, SToken, SSecret) of
        {error, _} = Error ->
            Error;
        Response ->
            validate_tweet(Response)
    end,
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    lager:debug("3, ~p~n", [_Request]),
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    lager:debug("Message:~p~n~n~n", [_Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------

%% @doc Get the OAuth credentials for the account
-spec get_oauth_data() -> #twitter_oauth_data{}.
get_oauth_data() ->
    #twitter_oauth_data{
        consumer_key = twitterl:get_env(oauth_consumer_key),
        consumer_secret = twitterl:get_env(oauth_consumer_secret),
        access_token = twitterl:get_env(oauth_access_token),
        access_token_secret = twitterl:get_env(oauth_access_token_secret)
        }.

%% @doc Get the consumer credentials for the account
-spec get_consumer(#twitter_oauth_data{}) -> consumer().
get_consumer(OAuthData) ->
    {OAuthData#twitter_oauth_data.consumer_key,
     OAuthData#twitter_oauth_data.consumer_secret,
     hmac_sha1}.

%% @doc Sign the Request
-spec sign_request(#twitter_oauth_data{}, string_method(), url(), params()) -> [{string(), string()}].
sign_request(OAuthData, StringMethod, URL, Params) -> 
    Token = OAuthData#twitter_oauth_data.access_token, 
    Secret = OAuthData#twitter_oauth_data.access_token_secret, 
    sign_request(OAuthData, StringMethod, URL, Params, Token, Secret).

-spec sign_request(#twitter_oauth_data{}, string_method(), url(), params(), token(), secret()) -> [{string(), string()}].
sign_request(OAuthData, StringMethod, URL, Params, Token, Secret) -> 
    Consumer = get_consumer(OAuthData),
    oauth:sign(StringMethod, URL, Params, Consumer, Token, Secret).

%% @doc Create the Request
-spec create_request(#twitter_oauth_data{}, method(), url(), params()) -> [{string(), string()}].
create_request(OAuthData, Method, URL, Params) -> 
    StringMethod = twitterl_util:get_string_method(Method),
    SignedRequest = sign_request(OAuthData, StringMethod, URL, Params),
    build_request(URL, SignedRequest).

-spec create_request(#twitter_oauth_data{}, method(), url(), params(), token(), secret()) -> [{string(), string()}].
create_request(OAuthData, Method, URL, Params, Token, Secret) -> 
    StringMethod = twitterl_util:get_string_method(Method),
    SignedRequest = sign_request(OAuthData, StringMethod, URL, Params, Token, Secret),
    build_request(URL, SignedRequest).

build_request(URL, SignedRequest) ->
    {AuthorizationParams, QueryParams} = lists:partition(fun({K, _}) -> lists:prefix("oauth_", K) end, SignedRequest),
    lager:debug("A:~p~n, Q:~p~n", [AuthorizationParams, QueryParams]),
    {oauth:uri(URL, QueryParams), [oauth:header(AuthorizationParams)]}.

validate_tokens(Tokens) ->
    case proplists:get_value("oauth_callback_confirmed", Tokens) of
        "true" ->
            extract_tokens(Tokens);
        _ ->
            {error, ?INVALID_REQUEST_TYPE}
    end.

extract_tokens(Tokens) ->
    try
        Token = get_token(Tokens),
        Secret = get_secret(Tokens),
        #twitter_token_data{
            access_token = Token,
            access_token_secret = Secret}
    catch
        _:Error ->
            {error, Error}
    end.

validate_access(Data) ->
    try
        Token = get_token(Data),
        Secret = get_secret(Data),
        UserId = get_user_id(Data),
        ScreenName = get_screen_name(Data),
        #twitter_access_data{
            access_token = Token,
            access_token_secret = Secret,
            user_id = UserId,
            screen_name = ScreenName}
    catch
        _:Error ->
            {error, Error}
    end.

validate_tweet(Data) ->
    try
        case Data of
            {_, _, Body} ->
                JsonBody = ejson:decode(Body),
                twitterl_tweet_parser:parse_one_tweet(JsonBody);
            Error ->
                {error, Error}
        end
    catch
        _:Error1 ->
            {error, Error1}
    end.


get_token(Tokens) ->
    case twitterl_util:keysearch("oauth_token", 1, undefined, Tokens) of
        undefined ->
            throw(?AUTH_ERROR);
        Token -> twitterl_util:get_binary(Token)
    end.

get_secret(Tokens) ->
    case twitterl_util:keysearch("oauth_token_secret", 1, undefined, Tokens) of
        undefined ->
            throw(?AUTH_ERROR);
        Token -> twitterl_util:get_binary(Token)
    end.

get_user_id(Tokens) ->
    case twitterl_util:keysearch("user_id", 1, undefined, Tokens) of
        undefined ->
            throw(?AUTH_ERROR);
        Token -> twitterl_util:get_binary(Token)
    end.

get_screen_name(Tokens) ->
    case twitterl_util:keysearch("screen_name", 1, undefined, Tokens) of
        undefined ->
            throw(?AUTH_ERROR);
        Token -> twitterl_util:get_binary(Token)
    end.

%% @doc post to the URL
-spec process_post(url(), params(), #twitter_oauth_data{}) -> list().
process_post(URL, Params, OAuthData) ->
    Consumer = get_consumer(OAuthData),
    check_response(oauth:post(URL, Params, Consumer)).

-spec process_post(url(), params(), #twitter_oauth_data{}, token(), secret()) -> list().
process_post(URL, Params, OAuthData, Token, Secret) ->
    Consumer = get_consumer(OAuthData),
    check_response(oauth:post(URL, Params, Consumer, Token, Secret)).

%% @doc Check the http request for errors
-spec check_response(any()) -> any().
check_response(Response) ->
    lager:debug("Response:~p~n", [Response]),
    try
        case Response of
            {ok, {{_, 401, _} = _Status, _Headers, _Body} = _Response} ->
                lager:debug("Response:~p~n", [Response]),
                {error, ?AUTH_ERROR};
            {ok, {{_, 403, _} = _Status, _Headers, Body} = _Response} ->
                lager:debug("Response:~p~n", [Response]),
                {error, Body};
            {ok, {{_, 200, _} = _Status, _Headers, _Body} = Result} ->
                Result;
            {ok, Result} ->
                Result;
            Other ->
                {error, Other}
        end
    catch
        _:Error ->
            {error, Error}
    end.
