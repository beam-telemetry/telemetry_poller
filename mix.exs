defmodule Telemetry.Poller.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :telemetry_poller,
      name: "Telemetry.Poller",
      version: @version,
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib/", "test/support/"]
  defp elixirc_paths(_), do: ["lib/"]

  defp preferred_cli_env() do
    [
      docs: :docs,
      dialyzer: :test
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.2.0"},
      {:ex_doc, "~> 0.19", only: :docs},
      {:dialyxir, "~> 1.0.0-rc.1", only: :test, runtime: false}
    ]
  end

  defp dialyzer() do
    [ignore_warnings: ".dialyzer_ignore.exs"]
  end

  defp docs do
    [
      main: "Telemetry.Poller",
      canonical: "http://hexdocs.pm/telemetry_poller",
      source_url: "https://github.com/beam-telemetry/telemetry_poller",
      source_ref: "v#{@version}"
    ]
  end

  def description do
    """
    Allows to periodically collect measurements and dispatch them as Telemetry events
    """
  end

  defp package do
    [
      maintainers: ["Arkadiusz Gil", "José Valim"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_poller"}
    ]
  end
end
