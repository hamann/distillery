defmodule Mix.Releases.Plugin do
  @moduledoc """
  This module provides a simple way to add additional processing to
  phases of the release assembly and archival.

  ## Implementing your own plugin

  To create a Distillery plugin, create a new module in which you
  `use Mix.Releases.Plugin`. Then write implentations for the following
  callbacks:

    - `c:before_assembly/1`
    - `c:after_assembly/1`
    - `c:before_package/1`
    - `c:after_package/1`
    - `c:after_cleanup/1`

  Currently, there are no default implementations. You are required to
  implement all callbacks yourself.

  When you `use Mix.Releases.Plugin`, the following happens:

    - Your module is marked with `@behaviour Mix.Releases.Plugin`.
    - The `Mix.Releases.Release` struct is aliased to `%Release{}`.
    - The functions `debug/1`, `info/1`, `warn/1`, `notice/1`, and `error/1`
      are imported from `Mix.Releases.Logger`. These should be used to present
      output to the user.

  The first four callbacks (`c:before_assembly/1`, `c:after_assembly/1`,
  `c:before_package/1`, and `c:after_package/1`) will each be passed the
  `%Release{}` struct. You can return a modified struct, or `nil`. Any other
  return value will lead to runtime errors.

  `c:after_cleanup/1` is only invoked on `mix release.clean`. It will be passed
  the command line arguments. The return value is not used.

  ## Example

      defmodule MyApp.PluginDemo do
        use Mix.Releases.Plugin

        def before_assembly(%Release{} = release) do
          info "This is executed just prior to assembling the release"
          release # or nil
        end

        def after_assembly(%Release{} = release) do
          info "This is executed just after assembling, and just prior to packaging the release"
          release # or nil
        end

        def before_package(%Release{} = release) do
          info "This is executed just before packaging the release"
          release # or nil
        end

        def after_package(%Release{} = release) do
          info "This is executed just after packaging the release"
          release # or nil
        end

        def after_cleanup(_args) do
          info "This is executed just after running cleanup"
          :ok # It doesn't matter what we return here
        end
      end
  """

  alias Mix.Releases.Release

  @doc """
  Called before assembling the release.

  Should return a modified `%Release{}` or `nil`.
  """
  @callback before_assembly(Release.t) :: Release.t | nil

  @doc """
  Called after assembling the release.

  Should return a modified `%Release{}` or `nil`.
  """
  @callback after_assembly(Release.t)  :: Release.t | nil

  @doc """
  Called before packaging the release.

  Should return a modified `%Release{}` or `nil`.

  When in `dev_mode`, the packaging phase is skipped.
  """
  @callback before_package(Release.t)  :: Release.t | nil

  @doc """
  Called after packaging the release.

  Should return a modified `%Release{}` or `nil`.

  When in `dev_mode`, the packaging phase is skipped.
  """
  @callback after_package(Release.t)   :: Release.t | nil

  @doc """
  Called when the user invokes the `mix release.clean` task.

  The callback will be passed the command line arguments to `mix release.clean`.
  It should clean up the files the plugin created. The return value of this
  callback is ignored.
  """
  @callback after_cleanup([String.t])  :: any

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour Mix.Releases.Plugin
      alias  Mix.Releases.Release
      alias  Mix.Releases.Logger
      import Mix.Releases.Logger, only: [debug: 1, info: 1, warn: 1, notice: 1, error: 1]

      Module.register_attribute __MODULE__, :name, accumulate: false, persist: true
      Module.register_attribute __MODULE__, :moduledoc, accumulate: false, persist: true
      Module.register_attribute __MODULE__, :shortdoc, accumulate: false, persist: true
    end
  end

  @doc """
  Run the `c:before_assembly/1` callback of all plugins of `release`.
  """
  @spec before_assembly(Release.t) :: {:ok, Release.t} | {:error, term}
  def before_assembly(release), do: call(:before_assembly, release)

  @doc """
  Run the `c:after_assembly/1` callback of all plugins of `release`.
  """
  @spec after_assembly(Release.t) :: {:ok, Release.t} | {:error, term}
  def after_assembly(release),  do: call(:after_assembly, release)

  @doc """
  Run the `c:before_package/1` callback of all plugins of `release`.
  """
  @spec before_package(Release.t) :: {:ok, Release.t} | {:error, term}
  def before_package(release),  do: call(:before_package, release)

  @doc """
  Run the `c:after_package/1` callback of all plugins of `release`.
  """
  @spec after_package(Release.t) :: {:ok, Release.t} | {:error, term}
  def after_package(release),   do: call(:after_package, release)

  @doc """
  Run the `c:after_cleanup/1` callback of all plugins of `release`.
  """
  @spec after_cleanup(Release.t, [String.t]) :: :ok | {:error, term}
  def after_cleanup(release, args), do: run(release.profile.plugins, :after_package, args)

  @spec call(atom(), Release.t) :: {:ok, term} | {:error, {:plugin_failed, term}}
  defp call(callback, release) do
    call(release.profile.plugins, callback, release)
  end
  defp call([], _, release), do: {:ok, release}
  defp call([plugin|plugins], callback, release) do
    try do
      case apply(plugin, callback, [release]) do
        nil ->
          call(plugins, callback, release)
        %Release{} = updated ->
          call(plugins, callback, updated)
        result ->
          {:error, {:plugin_failed, :bad_return_value, result}}
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  @spec run([atom()], atom, [String.t]) :: :ok | {:error, {:plugin_failed, term}}
  defp run([], _, _), do: :ok
  defp run([plugin|plugins], callback, args) do
    try do
      apply(plugin, callback, [args])
      run(plugins, callback, args)
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end
end
