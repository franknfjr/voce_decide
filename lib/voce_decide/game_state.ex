defmodule VoceDecide.GameState do
  use GenServer

  @topic "game_state"

  # API Pública
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{score_culpado: 0, score_inocente: 0}, name: __MODULE__)
  end

  def get_scores do
    GenServer.call(__MODULE__, :get_scores)
  end

  def increment_score(type) when type in [:culpado, :inocente] do
    GenServer.cast(__MODULE__, {:increment, type})
  end

  def reset_scores do
    GenServer.cast(__MODULE__, :reset)
  end

  # Callbacks
  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call(:get_scores, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:increment, type}, state) do
    new_state = Map.update!(state, :"score_#{type}", &(&1 + 1))
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset, _state) do
    new_state = %{score_culpado: 0, score_inocente: 0}
    broadcast_update(new_state)
    {:noreply, new_state}
  end

  defp broadcast_update(state) do
    Phoenix.PubSub.broadcast(VoceDecide.PubSub, @topic, {:scores_updated, state})
  end
end
