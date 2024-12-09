defmodule VoceDecideWeb.ResetLive do
  use VoceDecideWeb, :live_view

  @topic "game_state"

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(VoceDecide.PubSub, @topic)
    end

    scores = VoceDecide.GameState.get_scores()

    socket =
      assign(socket,
        score_culpado: scores.score_culpado,
        score_inocente: scores.score_inocente
      )

    {:ok, socket}
  end

  def handle_event("clear_scores", _params, socket) do
    VoceDecide.GameState.reset_scores()
    {:noreply, socket}
  end

  def handle_event("go_to_votacao", _params, socket) do
    {:noreply, push_navigate(socket, to: "/")}
  end

  def handle_info({:scores_updated, scores}, socket) do
    {:noreply,
     assign(socket,
       score_culpado: scores.score_culpado,
       score_inocente: scores.score_inocente
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <button id="clearBtn" phx-click="go_to_votacao">Votação</button>

      <button id="clearBtn" phx-click="clear_scores">Limpar Pontuações</button>
    </div>
    """
  end
end
