defmodule VoceDecide.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VoceDecideWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:voce_decide, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VoceDecide.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: VoceDecide.Finch},
      # Start a worker by calling: VoceDecide.Worker.start_link(arg)
      # {VoceDecide.Worker, arg},
      # Start to serve requests, typically the last entry
      VoceDecideWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VoceDecide.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VoceDecideWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
