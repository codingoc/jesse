%%%=============================================================================
%% Copyright 2012- Klarna AB
%% Copyright 2015- AUTHORS
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% @doc JESSE (JSon Schema Erlang)
%%
%% This is an interface module which provides an access to the main
%% functionality of jesse, such as 1) updating of the schema definitions cache;
%% 2) validation json data against a schema.
%% @end
%%%=============================================================================

-module(jesse).

%% API
-export([ main/1
        , add_schema/2
        , add_schema/3
        , del_schema/1
        , load_schemas/2
        , load_schemas/4
        , validate/2
        , validate/3
        , validate_with_schema/2
        , validate_with_schema/3        
        , validate_with_accumulator/2
        , validate_with_accumulator/3
        , validate_with_accumulator/4
        , validate_with_accumulator/5
        , explain_errors/1
        ]).

-export_type([ json_term/0
             ]).

-type json_term() :: term().

-type accumulator() :: fun(( jesse_json_path:path()
                           , jesse_schema_validator:error()
                           , term() ) -> term()).
-type parser()      :: fun((binary()) -> json_term()).

-type error()       :: {error, jesse_schema_validator:error()}.

%%% API

%% @doc Run from CLI with arguments.
-spec main([string()]) -> ok.
main(Args) ->
  jesse_cli:main(Args).

%% @doc Adds a schema definition `Schema' to in-memory storage associated with
%% a key `Key'. It will overwrite an existing schema with the same key if
%% there is any.
-spec add_schema(Key :: any(), Schema :: json_term()) ->
                    ok | jesse_error:error().
add_schema(Key, Schema) ->
  ValidationFun = fun jesse_lib:is_json_object/1,
  MakeKeyFun    = fun(_) -> Key end,
  jesse_database:add(Schema, ValidationFun, MakeKeyFun).

%% @doc Equivalent to `add_schema/2', but `Schema' is a binary string, and
%% the third agument is a parse function to convert the binary string to
%% a supported internal representation of json.
-spec add_schema( Key       :: any()
                , Schema    :: binary()
                , Options   :: [{Key :: atom(), Data :: any()}]
                ) -> ok | jesse_error:error().
add_schema(Key, Schema, Options) ->
  try
    ParserFun    = proplists:get_value(parser_fun, Options, fun(X) -> X end),
    ParsedSchema = try_parse(schema, ParserFun, Schema),
    add_schema(Key, ParsedSchema)
  catch
    throw:Error -> {error, Error}
  end.


%% @doc Deletes a schema definition from in-memory storage associated with
%% the key `Key'.
-spec del_schema(Key :: any()) -> ok.
del_schema(Key) ->
  jesse_database:delete(Key).

%% @doc Loads schema definitions from filesystem to in-memory storage.
%%
%% Equivalent to `load_schemas(Path, ParserFun, ValidationFun, MakeKeyFun)'
%% where `ValidationFun' is `fun jesse_json:is_json_object/1' and
%% `MakeKeyFun' is `fun jesse_lib:get_schema_id/1'. In this case
%% the key will be the value of `id' attribute from the given schemas.
-spec load_schemas( Path      :: string()
                  , ParserFun :: fun((binary()) -> json_term())
                  ) -> jesse_database:update_result().
load_schemas(Path, ParserFun) ->
  load_schemas( Path
              , ParserFun
              , fun jesse_lib:is_json_object/1
              , fun jesse_lib:get_schema_id/1
              ).

%% @doc Loads schema definitions from filesystem to in-memory storage.
%% The function loads all the files from directory `Path', then each schema
%% entry will be checked for a validity by function `ValidationFun', and
%% will be stored in in-memory storage with a key returned by `MakeKeyFun'
%% function.
%%
%% In addition to a schema definition, a timestamp of the schema file will be
%% stored, so, during the next update timestamps will be compared to avoid
%% unnecessary updates.
%%
%% Schema definitions are stored in the format which json parsing function
%% `ParserFun' returns.
%%
%% NOTE: it's impossible to automatically update schema definitions added by
%%       add_schema/2, the only way to update them is to use add_schema/2
%%       again with the new definition.
-spec load_schemas( Path          :: string()
                  , ParserFun     :: fun((binary()) -> json_term())
                  , ValidationFun :: fun((any()) -> boolean())
                  , MakeKeyFun    :: fun((json_term()) -> any())
                  ) -> jesse_database:update_result().
load_schemas(Path, ParserFun, ValidationFun, MakeKeyFun) ->
  jesse_database:update(Path, ParserFun, ValidationFun, MakeKeyFun).

%% @doc Equivalent to {@link validate/3} where `Options' is an empty list.
-spec validate( Schema :: any()
              , Data   :: json_term() | binary()
              ) -> {ok, json_term()}
                 | jesse_error:error()
                 | jesse_database:error().
validate(Schema, Data) ->
  validate(Schema, Data, []).

%% @doc Validates json `Data' against a schema with the same key as `Schema'
%% in the internal storage, using `Options'. If the given json is valid,
%% then it is returned to the caller, otherwise an error with an appropriate
%% error reason is returned. If the `parser_fun' option is provided, then
%% `Data' is considered to be a binary string, so `parser_fun' is used
%% to convert the binary string to a supported internal representation of json.
%% If `parser_fun' is not provided, then `Data' is considered to already be a
%% supported internal representation of json.
-spec validate( Schema   :: any()
              , Data     :: json_term() | binary()
              , Options  :: [{Key :: atom(), Data :: any()}]
              ) -> {ok, json_term()}
                 | jesse_error:error()
                 | jesse_database:error().
validate(Schema, Data, Options) ->
  try
    ParserFun  = proplists:get_value(parser_fun, Options, fun(X) -> X end),
    ParsedData = try_parse(data, ParserFun, Data),
    JsonSchema = jesse_database:read(Schema),
    jesse_schema_validator:validate(JsonSchema, ParsedData, Options)
  catch
    throw:Error -> {error, Error}
  end.

%% @doc Equivalent to {@link validate_with_schema/3} where `Options'
%% is an empty list.
-spec validate_with_schema( Schema :: json_term() | binary()
                          , Data   :: json_term() | binary()
                          ) -> {ok, json_term()}
                             | jesse_error:error().
validate_with_schema(Schema, Data) ->
  validate_with_schema(Schema, Data, []).

%% @doc Validates json `Data' agains the given schema `Schema', using `Options'.
%% If the given json is valid, then it is returned to the caller, otherwise
%% an error with an appropriate error reason is returned. If the `parser_fun'
%% option is provided, then both `Schema' and `Data' are considered to be a
%% binary string, so `parser_fun' is used to convert both binary strings to a
%% supported internal representation of json.
%% If `parser_fun' is not provided, then both `Schema' and `Data' are considered
%% to already be a supported internal representation of json.
-spec validate_with_schema( Schema   :: json_term() | binary()
                          , Data     :: json_term() | binary()
                          , Options  :: [{Key :: atom(), Data :: any()}]
                          ) -> {ok, json_term()}
                             | jesse_error:error().
validate_with_schema(Schema, Data, Options) ->
  try
    ParserFun    = proplists:get_value(parser_fun, Options, fun(X) -> X end),
    ParsedSchema = try_parse(schema, ParserFun, Schema),
    ParsedData   = try_parse(data, ParserFun, Data),
    jesse_schema_validator:validate(ParsedSchema, ParsedData, Options)
  catch
    throw:Error -> {error, Error}
  end.

%%% Internal functions
%% @doc Wraps up calls to a third party json parser.
%% @private
try_parse(Type, ParserFun, JsonBin) ->
  try
    ParserFun(JsonBin)
  catch
    _:Error ->
      case Type of
        data   -> throw({data_error, {parse_error, Error}});
        schema -> throw({schema_error, {parse_error, Error}})
      end
  end.


%% @doc Equivalent to {@link validate_with_accumulator/4} where both
%%      <code>Schema</code> and <code>Data</code> are parsed json terms.
-spec validate_with_accumulator( Schema   :: json_term(),
                                 Data     :: json_term()
                               ) ->
    {ok, json_term()} | {error, [error()]}.
validate_with_accumulator(Schema, Data) ->
    validate_with_accumulator(Schema, Data, fun collect_errors/3, []).


%% @doc Equivalent to {@link validate_with_schema/3} but with the additional
%%      argument fun to collect errors. This function will return the original
%%      JSON in case it is fully correspond to the schema or a list of all
%%      collected errors, if they are not critical.
-spec validate_with_accumulator( Schema   :: binary(),
                                 Data     :: binary(),
                                 ParseFun :: parser()
                               ) ->
    {ok, json_term()} | {error, [error()]}.
validate_with_accumulator(Schema, Data, ParseFun) ->
    case try_parse(schema, ParseFun, Schema) of
        {parse_error, _} = SError ->
            {error, {schema_error, SError}};
        ParsedSchema ->
            case try_parse(data, ParseFun, Data) of
                {parse_error, _} = DError ->
                    {error, {data_error, DError}};
                ParsedData ->
                    validate_with_accumulator(ParsedSchema, ParsedData)
            end
    end.


%% @doc Equivalent to {@link validate_with_accumulator/4} where both
%%      <code>Schema</code> and <code>Data</code> are parsed json terms.
-spec validate_with_accumulator( Schema      :: json_term(),
                                 Data        :: json_term(),
                                 Accumulator :: accumulator(),
                                 Initial     :: term()
                               ) ->
    {ok, json_term()} | {error, term()}.
validate_with_accumulator(Schema, Data, Accumulator, Initial) ->
    try
        jesse_schema_validator:validate(Schema, Data,
                                        {Accumulator, Initial})
    catch
        throw:Error ->
            {error, Error}
    end.


%% @doc Equivalent to {@link validate_with_accumulator/4} where both
%%      <code>Schema</code> and <code>Data</code> are parsed json terms.
-spec validate_with_accumulator( Schema      :: json_term(),
                                 Data        :: json_term(),
                                 ParseFun    :: parser(),
                                 Accumulator :: accumulator(),
                                 Initial     :: term()
                               ) ->
    {ok, json_term()} | {error, term()}.
validate_with_accumulator(Schema, Data, ParseFun, Accumulator, Initial) ->
    case try_parse(schema, ParseFun, Schema) of
        {parse_error, _} = SError ->
            {error, {schema_error, SError}};
        ParsedSchema ->
            case try_parse(data, ParseFun, Data) of
                {parse_error, _} = DError ->
                    {error, {data_error, DError}};
                ParsedData ->
                    validate_with_accumulator(ParsedSchema, ParsedData,
                                              Accumulator, Initial)
            end
    end.


%% @doc Explain list of errors in the internal format and return
%%      <code>iolist()</code> in human-readable format.
explain_errors(Errors) ->
    [ [format_error(Error), io_lib:nl()] || Error <- Errors ].


%%% ----------------------------------------------------------------------------
%%% Internal functions
%%% ----------------------------------------------------------------------------

format_error({data_invalid, Schema, wrong_type, Value}) ->
    case json_path("type", Schema) of
        UniounType when is_list(UniounType) ->
            Args = [get_desc(Schema), encode(Value)],
            print_tabbed_line("~s: ~s [bad type (check schema)]", Args);
        Type ->
            Args = [get_desc(Schema), encode(Value), Type],
            print_tabbed_line("~s: ~s [should be ~s]", Args)
    end;
format_error({data_invalid, Schema, no_extra_properties_allowed, Value}) ->
    Allowed  = get_props(json_path("properties", Schema)),
    ValProps = get_props(Value),
    Props = string:join(lists:map(fun encode/1, ValProps -- Allowed), ", "),
    print_tabbed_line("~s has unknown properties: [~s]", [get_desc(Schema), Props]);

format_error({data_invalid, Schema, {missing_required_property, Prop}, _}) ->
    print_tabbed_line("~s missing property: ~s", [get_desc(Schema), encode(Prop)]);

format_error({data_invalid, Schema, {not_unique, Item}, _Value}) ->
    print_tabbed_line("~s: ~s [should be unique]", [get_desc(Schema), encode(Item)]);

format_error({data_invalid, Schema, no_extra_items_allowed, _Value}) ->
    print_tabbed_line("~s has unexpected items", [get_desc(Schema)]);

format_error({data_invalid, Schema, not_enought_items, _Value}) ->
    print_tabbed_line("~s doesn't have required items", [get_desc(Schema)]);

format_error({data_invalid, Schema, {no_match, Pattern}, Value}) ->
    Args = [get_desc(Schema), encode(Value), encode(Pattern)],
    print_tabbed_line("~s: ~s [should match ~s]", Args);

format_error({data_invalid, Schema, wrong_format, Value}) ->
    Format = json_path("format", Schema),
    Args = [get_desc(Schema), encode(Value), encode(Format)],
    print_tabbed_line("~s: ~s [should be of format: ~s]", Args);

format_error({data_invalid, Schema, not_allowed, Value}) ->
    Disallowed = json_path("disallow", Schema),
    Args = [get_desc(Schema), encode(Value), encode(Disallowed)],
    print_tabbed_line("~s: ~s [should not be any of: ~s]", Args);

format_error({data_invalid, Schema, not_divisible, Value}) ->
    DivisibleBy = json_path("divisibleBy", Schema),
    Args = [get_desc(Schema), encode(Value), encode(DivisibleBy)],
    print_tabbed_line("~s: ~s [should be divisible by: ~s]", Args);

format_error({data_invalid, Schema, {missing_dependency, Dependency}, _Val}) ->
    Args = [get_desc(Schema), encode(Dependency)],
    print_tabbed_line("~s missing dependency: ~s", Args);

format_error({data_invalid, Schema, not_in_range, Value}) ->
    case json_path("enum", Schema, undefined) of
        undefined ->
            Min = json_path("minimum", Schema, '-inf'),
            Max = json_path("maximum", Schema, 'inf+'),
            Args = [get_desc(Schema), encode(Value), Min, Max],
            print_tabbed_line("~s: ~s [should be from ~p to ~p]", Args);
        Enum ->
            S = string:join(lists:map(fun erlang:binary_to_list/1, Enum), ", "),
            Args = [get_desc(Schema), encode(Value), S],
            print_tabbed_line("~s: ~s [should be in [~s]]", Args)
    end;

format_error({data_invalid, Schema, wrong_length, Value}) ->
    Min = json_path("minLength", Schema, 0),
    Max = json_path("maxLength", Schema, inf),
    Len = length(binary_to_list(Value)),
    Args = [get_desc(Schema), encode(Value), Len, Min, Max],
    print_tabbed_line("~s: ~s has wrong length: ~p [should be from ~p to ~p]", Args);

format_error({data_invalid, Schema, wrong_size, Value}) ->
    Min = json_path("minItems", Schema, 0),
    Max = json_path("maxItems", Schema, inf),
    Len = length(Value),
    Args = [get_desc(Schema), Len, Min, Max],
    print_tabbed_line("~s has wrong items num: ~p [should be from ~p to ~p]", Args).

print_tabbed_line(Format, Args) ->
    io_lib:format(Format, Args).

get_desc(Schema) ->
    encode(json_path("description", Schema)).

get_props({struct, Value}) when is_list(Value) ->
    proplists:get_keys(Value);
get_props(Value) when is_list(Value) ->
    proplists:get_keys(Value).

encode(Binary)  when is_binary(Binary)   -> binary_to_list(Binary);
encode(List)    when is_list(List)       -> List;
encode(Integer) when is_integer(Integer) -> integer_to_list(Integer).

json_path(K, Json, Default) ->
    case json_path(K, Json) of
        [] -> Default;
        Value -> Value
    end.

json_path(K, Json) when is_list(K) ->
    json_path(list_to_binary(K), Json);
json_path(K, Json) ->
    jesse_json_path:path(K, Json).

%% @doc Utility function to accumulate errors found during validation.
%% @private
collect_errors(_StringPath, Error, List) ->
    [Error | List].


