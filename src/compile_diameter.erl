-module(compile_diameter).

-behaviour(provider).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, compile).
-define(DEPS, [{default, app_discovery}]).

-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
            {name, ?PROVIDER},            % The 'user friendly' name of the task
            {module, ?MODULE},            % The module implementation of the task
            {namespace, diameter},
            {bare, true},                 % The task can be run by the user, always true
            {deps, ?DEPS},                % The list of dependencies
            {example, "rebar3 compile diameter"}, % How to use the plugin
            {opts, []},                   % list of options understood by the plugin
            {short_desc, short_desc()},
            {desc, desc()}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    rebar_api:info("Compiling diameter files...", []),
    Apps =
        case rebar_state:current_app(State) of
            undefined ->
                rebar_state:project_apps(State);
             AppInfo ->
                [AppInfo]
        end,
    [
        begin
            AppDir = rebar_app_info:dir(AppInfo),
            DiaDir = filename:join(AppDir, "dia"),
            SrcDir = filename:join(AppDir, "src"),
            EbinDir = rebar_app_info:ebin_dir(AppInfo),

            rebar_api:debug("AppDir: ~p~n", [AppDir]),
            rebar_api:debug("EbinDir: ~p~n", [AppDir]),

            DiaOpts = rebar_state:get(State, dia_opts, []),
            IncludeEbin = proplists:get_value(include, DiaOpts, []),

            ok = filelib:ensure_dir(filename:join(EbinDir, "dummy.beam")),

            code:add_pathsz([EbinDir | filename:join([AppDir, IncludeEbin])]),

            DiaFirst = case rebar_state:get(State, dia_first_files, []) of
                [] ->
                    [];
                CompileFirst ->
                    [filename:join(DiaDir, filename:basename(F)) || F <- CompileFirst]
            end,
            rebar_api:debug("Diameter first files: ~p", [DiaFirst]),

            rebar_base_compiler:run({State, AppDir, EbinDir},
                                DiaFirst,
                                DiaDir,
                                ".dia",
                                SrcDir,
                                ".erl",
                                fun compile_dia/3)
        end || AppInfo <- Apps
    ],
    {ok, State}.

-spec format_error(any()) ->  iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%% Internal functions
short_desc() ->
    "Build Diameter (*.dia) sources".

desc() ->
    short_desc() ++ "\n"
       "\n"
       "Valid rebar.config options:~n"
       "  {dia_opts, []} (options from diameter_make:codec/2 supported with~n"
       "                  exception of inherits)~n"
       "  {dia_first_files, []} (files in sequence to compile first)~n".

-spec compile_dia(file:filename(), file:filename(), rebar_config:config()) -> ok.
compile_dia(Source, Target, {State, AppDir, EbinDir}) ->
    rebar_api:debug("Source diameter file: ~p", [Source]),
    rebar_api:debug("Target diameter file: ~p", [Target]),
    rebar_api:info("Compiling diameter file: ~s", [filename:basename(Source)]),

    ok = filelib:ensure_dir(Target),
    ok = filelib:ensure_dir(filename:join([AppDir, "include", "dummy.hrl"])),

    OutDir = filename:join(AppDir, "src"),
    IncludeOutDir = filename:join(AppDir, "include"),

    Opts = [{outdir, OutDir}] ++ rebar_state:get(State, dia_opts, []),
    IncludeOpts = [{outdir, IncludeOutDir}] ++ rebar_state:get(State, dia_opts, []),
    case diameter_dict_util:parse({path, Source}, rebar_state:get(State, dia_opts, [])) of
        {ok, Spec} ->
            FileName = dia_filename(Source, Spec),
            _ = diameter_codegen:from_dict(FileName, Spec, Opts, erl),
            _ = diameter_codegen:from_dict(FileName, Spec, IncludeOpts, hrl),
            ErlCOpts = [{outdir, EbinDir}] ++ rebar_state:get(State, erl_opts, []),
            {Result, _} = compile:file(Target, ErlCOpts),
            Result;
        {error, Reason} ->
            rebar_api:error(
                "Compiling ~s failed: ~s",
                [Source, diameter_dict_util:format_error(Reason)]
            )
    end.

dia_filename(File, Spec) ->
    case proplists:get_value(name, Spec) of
        undefined ->
            filename:rootname(filename:basename(File));
        Name ->
            Name
    end.
