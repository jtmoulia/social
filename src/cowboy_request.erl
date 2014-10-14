-module(cowboy_request).
-author('Vladimir Dronnikov <dronnikov@gmail.com>').

-export([get_json/2]).
-export([post_for_json/2]).
-export([request/4]).
-export([urlencode/1]).
-export([make_uri/3]).


request(Method, URL, Headers, Body) when Method =:= <<"POST">> orelse
                                         Method =:= <<"GET">> orelse
                                         Method =:= <<"PUT">> ->
  Method1 = list_to_atom(strings:lower(binary_to_list(Method))),
  request(Method1, URL, Headers, Body);
request(Method, URL, Headers, Body) when is_binary(Method) ->
  request(Method, binary_to_list(URL), Headers, Body);
request(Method, URL, Headers, Body) ->
% pecypc_log:info({req, Method, URL, Body}),
  % NB: have to degrade protocol to not allow chunked responses
  Headers = [{<<"connection">>, <<"close">>},
             {<<"accept-encoding">>, <<"identity">>},
             % {<<"accept">>, <<"application/json, text/html">>},
             {<<"accept">>, <<"application/json">>},
             {<<"pragma">>, <<"no-cache">>},
             {<<"cache-control">>,
              <<"private, max-age: 0, no-cache, must-revalidate">>}
             | Headers],
  Req = {URL,
         headers_to_strings(Headers),
         <<"application/x-www-form-urlencoded">>,
         Body},
  Options = [{body_format, binary}, full_result, false],
  case httpc:request(Method, Req, [], Options) of
    {error, Reason} ->
      {error, Reason};
    {Status, RespBody} ->
      {ok, Status, RespBody}
  end.

make_uri(Scheme, Host, Path) ->
  << Scheme/binary, "://", Host/binary, Path/binary >>.

urlencode(Bin) when is_binary(Bin) ->
  cow_qs:urlencode(Bin);
urlencode(Atom) when is_atom(Atom) ->
  urlencode(atom_to_binary(Atom, latin1));
urlencode(Int) when is_integer(Int) ->
  urlencode(list_to_binary(integer_to_list(Int)));
urlencode({K, undefined}) ->
  << (urlencode(K))/binary, $= >>;
urlencode({K, V}) ->
  << (urlencode(K))/binary, $=, (urlencode(V))/binary >>;
urlencode(List) when is_list(List) ->
  binary_join([urlencode(X) || X <- List], << $& >>).

headers_to_strings(Headers) ->
  [{binary_to_list(Field), binary_to_list(Value)} || {Field, Value} <- Headers].

binary_join([], _Sep) ->
  <<>>;
binary_join([H], _Sep) ->
  << H/binary >>;
binary_join([H | T], Sep) ->
  << H/binary, Sep/binary, (binary_join(T, Sep))/binary >>.

parse(JSON) ->
  case jsx:decode(JSON, [{error_handler, fun(_, _, _) -> {error, badarg} end}])
  of
    {error, _} ->
      {ok, cowboy_http:x_www_form_urlencoded(JSON)};
    {incomplete, _} ->
      {ok, []};
    Hash ->
      {ok, Hash}
  end.

get_json(URL, Data) ->
  case request(<<"GET">>, <<
        URL/binary, $?, (urlencode(Data))/binary >>, [], <<>>)
  of
    {ok, 200, JSON} -> parse(JSON);
    _ -> {error, badarg}
  end.

post_for_json(URL, Data) ->
  case request(<<"POST">>, URL, [
      {<<"content-type">>, <<"application/x-www-form-urlencoded">>}
    ], urlencode(Data))
  of
    {ok, 200, JSON} -> parse(JSON);
    _Else -> {error, badarg}
  end.
