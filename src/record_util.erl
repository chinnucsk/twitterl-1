%% Copyright (c) 2011 Mahesh Paolini-Subramanya (mahesh@dieswaytoofast.com),
-module(record_util).
-author('Mahesh Paolini-Subramanya <mahesh@dieswaytoofast.com>').

-compile({parse_transform,dynarec}).

-include("defaults.hrl").

-export([update_record/2]).

%% @doc Sets the parameters in the (provided) Record with the values from List
update_record(Record, List) ->
    lists:foldl(fun update_value/2, Record, List).


%% Need to add additional functions when the records get nested or more
%% complicated
update_value({Key, Value}, Record) when is_atom(Key) ->
    set_value(Key, Value, Record).
