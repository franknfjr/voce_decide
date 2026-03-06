Mix.install([
  {:phoenix_playground, "~> 0.1.7"},
  {:replicate, "~> 1.1.1"},
  {:ex_aws, "~> 2.1"},
  {:ex_aws_s3, "~> 2.0"},
  {:req, "~> 0.4.0"},
  {:jason, "~> 1.4"},
  {:bumblebee, "~> 0.6.0"},
  {:nx, "~> 0.9.0"},
  {:exla, "~> 0.9.0"}
])

Application.put_env(
  :replicate,
  :replicate_api_token,
  System.get_env("REPLICATE_API_TOKEN")
)

Application.put_env(:nx, :default_backend, EXLA.Backend)

defmodule Storage do
  require Logger

  @storage_type System.get_env("STORAGE_TYPE", "local")
  @local_dir "tmp/stickers"

  def init do
    if @storage_type == "local" do
      File.mkdir_p!(@local_dir)
    end
  end

  def store(image_data, filename) do
    Logger.info("Armazenando arquivo #{filename}, tamanho: #{byte_size(image_data)} bytes")

    case System.get_env("STORAGE_TYPE", "local") do
      "s3" -> store_s3(image_data, filename)
      "local" -> store_local(image_data, filename)
    end
  end

  def list_recent do
    case @storage_type do
      "s3" -> list_recent_s3()
      "local" -> list_recent_local()
    end
  end

  defp store_s3(image_data, filename) do
    bucket = System.get_env("AWS_BUCKET_NAME")

    ExAws.S3.put_object(bucket, filename, image_data, [
      {:content_type, "image/webp"}
    ])
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, filename}
      error -> error
    end
  end

  defp store_local(image_data, filename) do
    path = Path.join(@local_dir, filename)
    IO.puts("Salvando arquivo em: #{path}")

    case File.write(path, image_data) do
      :ok ->
        IO.puts("Arquivo salvo com sucesso!")
        {:ok, filename}

      error ->
        IO.puts("Erro ao salvar arquivo: #{inspect(error)}")
        error
    end
  end

  defp list_recent_s3 do
    bucket = System.get_env("AWS_BUCKET_NAME")

    ExAws.S3.list_objects(bucket, max_keys: 3)
    |> ExAws.request()
    |> case do
      {:ok, %{body: %{contents: contents}}} ->
        contents
        |> Enum.sort_by(& &1.last_modified, {:desc, DateTime})
        |> Enum.take(3)
        |> Enum.map(& &1.key)

      _ ->
        []
    end
  end

  defp list_recent_local do
    case File.ls(@local_dir) do
      {:ok, files} ->
        IO.puts("Arquivos encontrados: #{inspect(files)}")

        files
        |> Enum.filter(&String.ends_with?(&1, ".webp"))
        |> Enum.take(3)

      {:error, reason} ->
        IO.puts("Erro ao listar arquivos: #{reason}")
        []
    end
  end
end

defmodule StickerService do
  require Logger

  def gen_sticker(prompt) do
    Logger.info("Iniciando geração do sticker com prompt: #{prompt}")

    case do_gen_sticker(prompt) do
      {:ok, prediction} ->
        Logger.info("Predição criada: #{prediction.id}")

        Task.await(
          Task.async(fn -> wait_for_prediction(prediction) end),
          # 30 segundos de timeout
          30_000
        )

      error ->
        Logger.error("Erro ao criar predição: #{inspect(error)}")
        error
    end
  end

  defp do_gen_sticker(prompt) do
    "fofr/sticker-maker"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_version!(
      "4acb778eb059772225ec213948f0660867b2e03f277448f18cf1800b96a65a1a"
    )
    |> Replicate.Predictions.create(%{
      prompt: prompt,
      output_format: "webp",
      steps: 17,
      output_quality: 100,
      negative_prompt: "racist, xenophobic, antisemitic, islamophobic, bigoted"
    })
  end

  defp wait_for_prediction(prediction) do
    Logger.info("Aguardando predição #{prediction.id}...")

    case Replicate.Predictions.get(prediction.id) do
      {:ok, %{status: "succeeded", output: output}} when not is_nil(output) ->
        url = if is_list(output), do: List.last(output), else: output
        Logger.info("Predição concluída com sucesso. URL: #{url}")
        {:ok, url}

      {:ok, %{status: "failed", error: error}} ->
        Logger.error("Predição falhou: #{error}")
        {:error, "Prediction failed: #{error}"}

      {:ok, %{status: status}} when status in ["starting", "processing"] ->
        Logger.info("Status atual: #{status}")
        # Adiciona um delay maior e tenta novamente
        Process.sleep(3000)
        wait_for_prediction(prediction)

      {:ok, prediction} ->
        Logger.error("Status inesperado: #{inspect(prediction)}")
        {:error, "Unexpected status"}

      error ->
        Logger.error("Erro inesperado: #{inspect(error)}")
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end

  def store_image(url) when is_binary(url) do
    filename = "#{:crypto.strong_rand_bytes(16) |> Base.encode16()}.webp"
    Logger.info("Tentando salvar imagem de #{url} como #{filename}")

    with {:ok, response} <- Req.get(url) do
      Logger.info("Download concluído, tamanho: #{byte_size(response.body)} bytes")
      image_data = response.body

      case Storage.store(image_data, filename) do
        {:ok, filename} ->
          Logger.info("Imagem salva com sucesso como #{filename}")

          case classify_image(image_data) do
            {:ok, label} ->
              Logger.info("Imagem classificada como: #{label}")
              {:ok, filename, label}

            {:error, class_error} ->
              Logger.error("Erro na classificação: #{class_error}")
              {:error, "Classification failed: #{class_error}"}
          end

        {:error, store_error} ->
          Logger.error("Erro ao salvar arquivo: #{inspect(store_error)}")
          {:error, "Storage failed: #{inspect(store_error)}"}
      end
    else
      error ->
        Logger.error("Erro ao baixar imagem: #{inspect(error)}")
        {:error, "Download failed: #{inspect(error)}"}
    end
  end

  def list_recent_files do
    Storage.list_recent() |> dbg()
  end

  defp classify_image(image_data) do
    try do
      tensor =
        image_data
        |> Nx.from_binary(:u8)
        |> Nx.reshape({-1, -1, 3})
        |> dbg()

      output = Nx.Serving.batched_run(StickerApp.Serving, tensor)
      {:ok, output.predictions |> List.first() |> Map.get(:label) |> dbg()}
    rescue
      _ -> {:error, "Classification failed"}
    end
  end
end

defmodule StickerLive do
  require Logger
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(5000, self(), :update_recent_files)
      recent_files = StickerService.list_recent_files() |> dbg()

      files =
        File.ls!("tmp/stickers")
        |> Enum.filter(&String.ends_with?(&1, ".webp"))

      {:ok, assign(socket, prompt: "", generating: false, result: nil, recent_files: files)}
    else
      {:ok, assign(socket, prompt: "", generating: false, result: nil, recent_files: [])}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container">
      <h1>Sticker Generator ({System.get_env("STORAGE_TYPE", "local")})</h1>

      <form phx-submit="generate">
        <textarea name="prompt" placeholder="Describe your sticker..." rows="4"><%= @prompt %></textarea>

        <button type="submit" disabled={@generating}>
          <%= if @generating do %>
            <span>Gerando... Por favor aguarde</span>
          <% else %>
            <span>Generate Sticker</span>
          <% end %>
        </button>
      </form>

      <%= if @result do %>
        <div class="result">
          <p>Sticker generated and stored as: {elem(@result, 0)}</p>
          <p>Classification: {elem(@result, 1)}</p>
        </div>
      <% end %>

      <div class="recent-files">
        <h2>Recent Stickers ({length(@recent_files)} files)</h2>
        <p>Dir: tmp/stickers</p>
        <ul>
          <%= for {file, label} <- @recent_files do %>
            <li>
              <p>Arquivo: {file}</p>
              <p>Classificação: {label}</p>
              <img
                src={"data:image/webp;base64,#{Base.encode64(File.read!(Path.join("tmp/stickers", file)))}"}
                style="max-width: 150px; height: auto;"
              />
            </li>
          <% end %>
        </ul>
      </div>
    </div>

    <style type="text/css">
      .container {
        max-width: 600px;
        margin: 0 auto;
        padding: 2em;
      }

      h1, h2 {
        text-align: center;
        margin-bottom: 1em;
      }

      form {
        display: flex;
        flex-direction: column;
        gap: 1em;
      }

      textarea {
        padding: 0.5em;
        border: 1px solid #ccc;
        border-radius: 4px;
      }

      button {
        padding: 0.5em 1em;
        background: #4299e1;
        color: white;
        border: none;
        border-radius: 4px;
        cursor: pointer;
      }

      button:disabled {
        opacity: 0.7;
      }

      .result {
        margin-top: 1em;
        padding: 1em;
        background: #e6ffed;
        border-radius: 4px;
      }

      .recent-files {
        margin-top: 2em;
        padding: 1em;
        background: #f6f8fa;
        border-radius: 4px;
      }

      .recent-files ul {
        list-style: none;
        padding: 0;
      }

      .recent-files li {
        padding: 0.5em;
        border-bottom: 1px solid #eee;
      }
    </style>
    """
  end

  defp get_base64(filename) do
    path = Path.join("tmp/stickers", filename)
    IO.puts("Tentando ler arquivo: #{path}")

    case File.read(path) do
      {:ok, data} ->
        IO.puts("Arquivo lido com sucesso!")
        Base.encode64(data)

      {:error, reason} ->
        IO.puts("Erro ao ler arquivo: #{inspect(reason)}")
        ""
    end
  end

  def handle_event("generate", %{"prompt" => prompt}, socket) do
    Task.async(fn ->
      case StickerService.gen_sticker(prompt) do
        {:ok, url} ->
          case StickerService.store_image(url) do
            {:ok, filename, label} -> {:ok, {filename, label}}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end)

    {:noreply, assign(socket, generating: true, prompt: prompt)}
  end

  def handle_info({ref, {:ok, result}}, socket) do
    Process.demonitor(ref, [:flush])
    send(self(), :update_recent_files)
    {:noreply, assign(socket, generating: false, result: result)}
  end

  def handle_info({ref, {:error, reason}}, socket) do
    Process.demonitor(ref, [:flush])
    Logger.error("Erro na geração do sticker: #{inspect(reason)}")
    {:noreply, assign(socket, generating: false, result: {"Erro: #{reason}", ""})}
  end

  def handle_info({:timeout, _ref}, socket) do
    {:noreply, assign(socket, generating: false, result: {"Erro: Timeout na geração", ""})}
  end

  def handle_info(:update_recent_files, socket) do
    recent_files = StickerService.list_recent_files() |> dbg()
    {:noreply, assign(socket, recent_files: recent_files)}
  end
end

# Initialize storage
Storage.init()

# Initialize Bumblebee serving
{:ok, model_info} = Bumblebee.load_model({:hf, "microsoft/resnet-50"})
{:ok, featurizer} = Bumblebee.load_featurizer({:hf, "microsoft/resnet-50"})

serving =
  Bumblebee.Vision.image_classification(model_info, featurizer,
    top_k: 1,
    compile: [batch_size: 4],
    defn_options: [
      compiler: EXLA,
      cache: Path.join(System.tmp_dir!(), "bumblebee_examples/image_classification")
    ]
  )

Nx.Serving.start_link(serving: serving, name: StickerApp.Serving, batch_timeout: 100)

PhoenixPlayground.start(live: StickerLive)
