defmodule VoceDecideWeb.VoceDecideLive do
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
        score_inocente: scores.score_inocente,
        result: nil
      )

    {:ok, socket}
  end

  def handle_event("choose", %{"choice" => choice}, socket) do
    VoceDecide.GameState.increment_score(String.to_atom(choice))
    {:noreply, socket}
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
      <h1>Você Decide!</h1>

      <div id="story">
        <p id="story-text">Neste caso, o usuário foi: culpado ou inocente?</p>
      </div>

      <div id="choices">
        <div class="images-container">
          <div class="main-image">
            <img src="/images/logo.jpeg" alt="Imagem do usuário" id="userImage" />
          </div>
          <div class="qr-code-container">
            <img src="/images/qr-code.png" alt="QR Code" class="qr-code" />
          </div>
        </div>

        <div class="button-container">
          <button class="culpado" phx-click="choose" phx-value-choice="culpado">
            Culpado
          </button>
          <button class="inocente" phx-click="choose" phx-value-choice="inocente">
            Inocente
          </button>
        </div>
      </div>

      <div id="score">
        <div class="score-row">
          <p>Culpado: <span id="scoreCulpado">{@score_culpado}</span></p>
          <div class="progress-bar">
            <div
              class="progress culpado-progress"
              style={"width: #{progress_width(@score_culpado, @score_culpado + @score_inocente)}%"}
            >
            </div>
          </div>
        </div>
        <div class="score-row">
          <p>Inocente: <span id="scoreInocente">{@score_inocente}</span></p>
          <div class="progress-bar">
            <div
              class="progress inocente-progress"
              style={"width: #{progress_width(@score_inocente, @score_culpado + @score_inocente)}%"}
            >
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp progress_width(value, total) do
    if total > 0 do
      value / total * 100
    else
      0
    end
  end
end
