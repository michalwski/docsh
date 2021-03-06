-module(docsh_shell).

-export([h/1, h/3,
         s/1, s/3,
         t/3]).

-spec h(fun() | module()) -> ok.
h(Fun) when is_function(Fun) ->
    {M, F, A} = erlang:fun_info_mfa(Fun),
    h(M, F, A);

h(M) when is_atom(M) ->
    unchecked_lookup([M], [M]).

h(M, F, Arity) when is_atom(M), is_atom(F),
                    is_integer(Arity) orelse Arity =:= any ->
    unchecked_lookup([M, F, Arity], [M, F, Arity, [doc, spec]]).

s(Fun) when is_function(Fun) ->
    {M, F, A} = erlang:fun_info_mfa(Fun),
    s(M, F, A).

s(M, F, Arity) when is_atom(M), is_atom(F),
                    is_integer(Arity) orelse Arity =:= any ->
    unchecked_lookup([M, F, Arity], [M, F, Arity, [spec]]).

t(M, T, Arity) when is_atom(M), is_atom(T),
                    is_integer(Arity) orelse Arity =:= any ->
    unchecked_lookup([M, T, Arity], [M, T, Arity, [type]]).

%% MFA might actually be just [M].
unchecked_lookup([M | _] = MFA, Args) ->
    case get_beam(M) of
        {error, R} -> error(R, MFA);
        {ok, _} -> erlang:apply(docsh_embeddable, h, Args)
    end.

get_beam(M) -> get_beam(M, init).

get_beam(M, Attempt) when Attempt =:= init;
                          Attempt =:= retry ->
    case docsh_beam:from_loadable_module(M) of
        {error, _} = E -> E;
        {ok, B} ->
            case {Attempt, docsh_lib:has_exdc(docsh_beam:beam_file(B))} of
                {_, true} -> {ok, B};
                {init, false} ->
                    {ok, NewB} = cached_or_rebuilt(B, ensure_cache_dir()),
                    reload(NewB),
                    get_beam(M, retry)
            end
    end.

-spec cached_or_rebuilt(docsh_beam:t(), file:name()) -> {ok, docsh_beam:t()}.
cached_or_rebuilt(Beam, CacheDir) ->
    %% TODO: find the module in cache, don't rebuild every time
    {ok, _RebuiltBeam} = rebuild(Beam, CacheDir).

ensure_cache_dir() ->
    CacheDir = cache_dir(),
    IsFile = filelib:is_file(CacheDir),
    IsDir = filelib:is_dir(CacheDir),
    case {IsFile, IsDir} of
        {true, true} ->
            CacheDir;
        {true, false} ->
            error(cache_location_is_not_a_dir);
        _ ->
            ok = file:make_dir(CacheDir),
            CacheDir
    end.

cache_dir() ->
    case {os:getenv("XDG_CACHE_HOME"), os:getenv("HOME")} of
        {false, false} -> error(no_cache_dir);
        {false, Home} -> filename:join([Home, ".docsh"]);
        {XDGCache, _} -> filename:join([XDGCache, "docsh"])
    end.

-spec reload(docsh_beam:t()) -> ok.
reload(Beam) ->
    BEAMFile = docsh_beam:beam_file(Beam),
    Path = filename:join([filename:dirname(BEAMFile),
                          filename:basename(BEAMFile, ".beam")]),
    unstick_module(docsh_beam:name(Beam)),
    {module, _} = code:load_abs(Path),
    stick_module(docsh_beam:name(Beam)),
    ok.

-spec rebuild(docsh_beam:t(), string()) -> any().
rebuild(B, CacheDir) ->
    BEAMFile = docsh_beam:beam_file(B),
    {ok, NewBEAM} = docsh_lib:process_beam(BEAMFile),
    NewBEAMFile = filename:join([CacheDir, filename:basename(BEAMFile)]),
    ok = file:write_file(NewBEAMFile, NewBEAM),
    docsh_beam:from_beam_file(NewBEAMFile).

unstick_module(Module) -> unstick_module(Module, code:is_sticky(Module)).

unstick_module(Module, true) -> code:unstick_mod(Module);
unstick_module(_,_) -> false.

stick_module(Module) -> stick_module(Module, code:is_sticky(Module)).

stick_module(Module, false) -> code:stick_mod(Module);
stick_module(_,_) -> false.
