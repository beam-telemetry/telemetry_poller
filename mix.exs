defmodule Telemetry.Sampler.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_sampler,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      dialyzer: dialyzer()
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
      {:telemetry, "~> 0.1.0"},
      {:ex_doc, "~> 0.19", only: :docs},
      {:dialyxir, "~> 1.0.0-rc.1", only: :test, runtime: false}
    ]
  end

  defp dialyzer() do
    [ignore_warnings: ".dialyzer_ignore.exs"]
  end
end
