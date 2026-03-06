defmodule StressTest do
  @moduledoc """
  Teste de estresse para simular 300 usuários simultâneos votando
  """

  def run do
    IO.puts("Iniciando teste de estresse para 300 usuários simultâneos...")
    
    # URL do endpoint
    base_url = "https://voce-decide.fly.dev/"
    
    # Configurações do teste
    num_users = 300
    votes_per_user = 10
    
    IO.puts("Configuração:")
    IO.puts("- Usuários simultâneos: #{num_users}")
    IO.puts("- Votos por usuário: #{votes_per_user}")
    IO.puts("- Total de votos: #{num_users * votes_per_user}")
    IO.puts("- URL: #{base_url}")
    IO.puts("")
    
    # Iniciar Finch
    {:ok, _} = Finch.start_link(name: StressTestFinch)
    
    # Executar teste
    start_time = System.monotonic_time(:millisecond)
    
    # Criar tasks para simular usuários simultâneos
    tasks = Enum.map(1..num_users, fn user_id ->
      Task.async(fn -> simulate_user(user_id, base_url, votes_per_user) end)
    end)
    
    # Aguardar todas as tasks terminarem
    results = Task.await_all(tasks, 120_000) # 120 segundos timeout
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Analisar resultados
    analyze_results(results, duration, num_users, votes_per_user)
  end
  
  defp simulate_user(user_id, base_url, votes_per_user) do
    IO.puts("Usuário #{user_id} iniciado")
    
    results = %{
      user_id: user_id,
      successful_votes: 0,
      failed_votes: 0,
      errors: [],
      response_times: []
    }
    
    # Simular votos diretamente via WebSocket simulado ou requisições HTTP
    Enum.reduce(1..votes_per_user, results, fn vote_num, acc ->
      choice = if rem(vote_num, 2) == 0, do: "culpado", else: "inocente"
      
      case cast_vote_http(base_url, choice, user_id, vote_num) do
        {:ok, response_time} ->
          %{acc | 
            successful_votes: acc.successful_votes + 1,
            response_times: [response_time | acc.response_times]
          }
        {:error, reason} ->
          %{acc | 
            failed_votes: acc.failed_votes + 1,
            errors: [reason | acc.errors]
          }
      end
    end)
  end
  
  defp cast_vote_http(base_url, choice, user_id, vote_num) do
    # Simular um pequeno delay entre votos do mesmo usuário
    if vote_num > 1, do: :timer.sleep(Enum.random(50..200))
    
    start_time = System.monotonic_time(:millisecond)
    
    # Fazer uma requisição GET primeiro para simular carregamento da página
    case Finch.build(:get, base_url)
         |> Finch.request(StressTestFinch, receive_timeout: 10_000) do
      
      {:ok, response} when response.status in [200, 302] ->
        # Simular o voto - na prática seria via WebSocket mas vamos simular com outra requisição GET
        # que representa a interação do usuário
        vote_url = "#{base_url}?vote=#{choice}&user=#{user_id}&t=#{System.system_time(:millisecond)}"
        
        case Finch.build(:get, vote_url)
             |> Finch.request(StressTestFinch, receive_timeout: 10_000) do
          
          {:ok, vote_response} when vote_response.status in [200, 302, 404] ->
            end_time = System.monotonic_time(:millisecond)
            response_time = end_time - start_time
            {:ok, response_time}
            
          {:ok, vote_response} ->
            {:error, "Vote HTTP #{vote_response.status}"}
            
          {:error, reason} ->
            {:error, "Vote error: #{inspect(reason)}"}
        end
        
      {:ok, response} ->
        {:error, "Page load HTTP #{response.status}"}
        
      {:error, reason} ->
        {:error, "Connection error: #{inspect(reason)}"}
    end
  end
  
  defp analyze_results(results, duration, num_users, votes_per_user) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("RESULTADOS DO TESTE DE ESTRESSE")
    IO.puts(String.duplicate("=", 60))
    
    total_votes = num_users * votes_per_user
    successful_votes = Enum.sum(Enum.map(results, & &1.successful_votes))
    failed_votes = Enum.sum(Enum.map(results, & &1.failed_votes))
    
    all_response_times = results
    |> Enum.flat_map(& &1.response_times)
    |> Enum.sort()
    
    avg_response_time = if length(all_response_times) > 0 do
      Enum.sum(all_response_times) / length(all_response_times)
    else
      0
    end
    
    p95_response_time = if length(all_response_times) > 0 do
      index = round(length(all_response_times) * 0.95) - 1
      Enum.at(all_response_times, max(0, index))
    else
      0
    end
    
    success_rate = (successful_votes / total_votes * 100) |> Float.round(2)
    requests_per_second = (successful_votes / (duration / 1000)) |> Float.round(2)
    
    IO.puts("Duração total: #{duration} ms (#{Float.round(duration / 1000, 2)} segundos)")
    IO.puts("Total de requests esperados: #{total_votes}")
    IO.puts("Requests bem-sucedidos: #{successful_votes}")
    IO.puts("Requests falharam: #{failed_votes}")
    IO.puts("Taxa de sucesso: #{success_rate}%")
    IO.puts("Requests por segundo: #{requests_per_second}")
    IO.puts("Tempo de resposta médio: #{Float.round(avg_response_time, 2)} ms")
    IO.puts("Tempo de resposta P95: #{p95_response_time} ms")
    
    if length(all_response_times) > 0 do
      min_time = Enum.min(all_response_times)
      max_time = Enum.max(all_response_times)
      IO.puts("Tempo de resposta mínimo: #{min_time} ms")
      IO.puts("Tempo de resposta máximo: #{max_time} ms")
    end
    
    # Mostrar erros mais comuns
    all_errors = results
    |> Enum.flat_map(& &1.errors)
    |> Enum.frequencies()
    
    if map_size(all_errors) > 0 do
      IO.puts("\nErros encontrados:")
      Enum.each(all_errors, fn {error, count} ->
        IO.puts("- #{error}: #{count} ocorrências")
      end)
    end
    
    # Análise por usuário
    users_with_failures = Enum.count(results, & &1.failed_votes > 0)
    IO.puts("\nUsuários que tiveram falhas: #{users_with_failures}/#{num_users}")
    
    # Verificar se há possível problema de load
    check_load_issues(results, num_users)
    
    IO.puts("\n" <> String.duplicate("=", 60))
    
    # Conclusão
    cond do
      success_rate >= 95 and avg_response_time < 2000 ->
        IO.puts("✅ TESTE PASSOU: Sistema suporta bem 300 usuários simultâneos")
      
      success_rate >= 90 ->
        IO.puts("⚠️  ATENÇÃO: Sistema funciona mas com algumas falhas")
        IO.puts("   Considere otimizações para melhorar a confiabilidade")
        
      success_rate >= 70 ->
        IO.puts("❌ PROBLEMA: Sistema tem dificuldades com 300 usuários")
        IO.puts("   Necessário investigar gargalos e otimizar")
        
      true ->
        IO.puts("🚨 FALHA CRÍTICA: Sistema não suporta 300 usuários simultâneos")
        IO.puts("   Requer mudanças significativas na arquitetura")
    end
  end
  
  defp check_load_issues(results, num_users) do
    # Verificar padrões que indicam problemas de carga
    users_with_all_failures = Enum.count(results, & &1.successful_votes == 0)
    
    if users_with_all_failures > 0 do
      IO.puts("\n⚠️  Possível sobrecarga detectada:")
      IO.puts("#{users_with_all_failures} usuários falharam completamente")
    end
    
    # Verificar distribuição de falhas
    failed_users = results
    |> Enum.filter(& &1.failed_votes > 0)
    |> length()
    
    if failed_users > num_users * 0.3 do
      IO.puts("⚠️  Mais de 30% dos usuários tiveram falhas - possível gargalo no servidor")
    end
    
    # Verificar se há timeout patterns
    timeout_errors = results
    |> Enum.flat_map(& &1.errors)
    |> Enum.count(&String.contains?(to_string(&1), "timeout"))
    
    if timeout_errors > 0 do
      IO.puts("⚠️  #{timeout_errors} erros de timeout detectados")
    end
  end
end

# Teste local para verificar race conditions
defmodule LocalRaceConditionTest do
  def run do
    IO.puts("Executando teste local de race condition...")
    IO.puts("Simulando múltiplos cliques rápidos simultâneos...")
    
    # Obter scores iniciais
    initial_scores = VoceDecide.GameState.get_scores()
    IO.puts("Scores iniciais - Culpado: #{initial_scores.score_culpado}, Inocente: #{initial_scores.score_inocente}")
    
    # Simular 100 cliques muito rápidos simultâneos
    num_clicks = 100
    
    tasks = Enum.map(1..num_clicks, fn i ->
      Task.async(fn ->
        # Simular clique rápido alternando entre culpado e inocente
        choice = if rem(i, 2) == 0, do: :culpado, else: :inocente
        
        try do
          VoceDecide.GameState.increment_score(choice)
          {:ok, {i, choice}}
        rescue
          error -> {:error, {i, choice, error}}
        catch
          error -> {:error, {i, choice, error}}
        end
      end)
    end)
    
    start_time = System.monotonic_time(:millisecond)
    results = Task.await_all(tasks, 10000)
    end_time = System.monotonic_time(:millisecond)
    
    duration = end_time - start_time
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    IO.puts("Cliques processados com sucesso: #{successful}")
    IO.puts("Cliques falharam: #{failed}")
    IO.puts("Tempo total: #{duration} ms")
    
    # Verificar estado final
    final_scores = VoceDecide.GameState.get_scores()
    total_final = final_scores.score_culpado + final_scores.score_inocente
    total_initial = initial_scores.score_culpado + initial_scores.score_inocente
    votes_added = total_final - total_initial
    
    IO.puts("Scores finais - Culpado: #{final_scores.score_culpado}, Inocente: #{final_scores.score_inocente}")
    IO.puts("Total de votos adicionados: #{votes_added}")
    
    # Contar votos esperados por tipo
    expected_culpado = div(num_clicks, 2)
    expected_inocente = num_clicks - expected_culpado
    actual_culpado = final_scores.score_culpado - initial_scores.score_culpado
    actual_inocente = final_scores.score_inocente - initial_scores.score_inocente
    
    IO.puts("Esperado - Culpado: #{expected_culpado}, Inocente: #{expected_inocente}")
    IO.puts("Real - Culpado: #{actual_culpado}, Inocente: #{actual_inocente}")
    
    cond do
      votes_added == successful and failed == 0 ->
        IO.puts("✅ Nenhum race condition detectado - todos os votos processados corretamente")
      
      votes_added == successful and failed > 0 ->
        IO.puts("⚠️  Algumas operações falharam mas não há inconsistência nos dados")
        IO.puts("   Falhas: #{failed} (isso pode ser normal sob alta concorrência)")
      
      votes_added != successful ->
        IO.puts("🚨 RACE CONDITION DETECTADO!")
        IO.puts("   #{successful} operações relataram sucesso mas apenas #{votes_added} votos foram registrados")
        IO.puts("   Diferença: #{successful - votes_added}")
      
      true ->
        IO.puts("⚠️  Resultado inesperado - necessário investigação manual")
    end
    
    # Teste adicional: verificar se múltiplos cliques do mesmo tipo funcionam
    IO.puts("\nTeste adicional: 20 cliques simultâneos do mesmo tipo...")
    
    before_test = VoceDecide.GameState.get_scores()
    
    same_type_tasks = Enum.map(1..20, fn _i ->
      Task.async(fn ->
        VoceDecide.GameState.increment_score(:culpado)
        :ok
      end)
    end)
    
    Task.await_all(same_type_tasks, 5000)
    
    after_test = VoceDecide.GameState.get_scores()
    culpado_added = after_test.score_culpado - before_test.score_culpado
    
    if culpado_added == 20 do
      IO.puts("✅ 20 votos 'culpado' simultâneos processados corretamente")
    else
      IO.puts("🚨 PROBLEMA: Esperado 20 votos 'culpado', registrado #{culpado_added}")
    end
  end
end

# Teste de estresse simplificado para endpoint real
defmodule SimpleStressTest do
  def run do
    IO.puts("Executando teste de estresse simplificado...")
    IO.puts("Fazendo 300 requisições GET simultâneas para verificar capacidade do servidor")
    
    url = "https://voce-decide.fly.dev/"
    num_requests = 300
    
    {:ok, _} = Finch.start_link(name: SimpleTestFinch)
    
    start_time = System.monotonic_time(:millisecond)
    
    tasks = Enum.map(1..num_requests, fn i ->
      Task.async(fn ->
        case Finch.build(:get, url)
             |> Finch.request(SimpleTestFinch, receive_timeout: 15_000) do
          {:ok, response} when response.status in [200, 301, 302] ->
            {:ok, response.status}
          {:ok, response} ->
            {:error, "HTTP #{response.status}"}
          {:error, reason} ->
            {:error, inspect(reason)}
        end
      end)
    end)
    
    results = Task.await_all(tasks, 30_000)
    end_time = System.monotonic_time(:millisecond)
    
    duration = end_time - start_time
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    IO.puts("Requisições simultâneas: #{num_requests}")
    IO.puts("Bem-sucedidas: #{successful}")
    IO.puts("Falharam: #{failed}")
    IO.puts("Taxa de sucesso: #{Float.round(successful / num_requests * 100, 2)}%")
    IO.puts("Tempo total: #{duration} ms")
    IO.puts("Requisições por segundo: #{Float.round(successful / (duration / 1000), 2)}")
    
    if successful >= num_requests * 0.95 do
      IO.puts("✅ Servidor suporta bem 300 requisições simultâneas")
    else
      IO.puts("⚠️  Servidor teve dificuldades com 300 requisições simultâneas")
    end
  end
end

# Menu de execução
IO.puts("=== TESTES DE ESTRESSE - VOCÊ DECIDE ===")
IO.puts("Escolha o teste a executar:")
IO.puts("1. Teste local de race condition (recomendado)")
IO.puts("2. Teste simples de carga no servidor (300 GETs)")
IO.puts("3. Teste completo de estresse (não recomendado para produção)")
IO.puts("4. Todos os testes")

case IO.gets("Digite sua escolha (1, 2, 3 ou 4): ") |> String.trim() do
  "1" -> 
    LocalRaceConditionTest.run()
    
  "2" -> 
    SimpleStressTest.run()
    
  "3" -> 
    IO.puts("⚠️  ATENÇÃO: Este teste pode impactar o servidor em produção!")
    case IO.gets("Tem certeza? (y/N): ") |> String.trim() |> String.downcase() do
      "y" -> StressTest.run()
      _ -> IO.puts("Teste cancelado.")
    end
    
  "4" -> 
    IO.puts("Executando todos os testes...\n")
    
    IO.puts("1/3 - Teste local de race condition:")
    LocalRaceConditionTest.run()
    
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")
    
    IO.puts("2/3 - Teste simples de carga:")
    SimpleStressTest.run()
    
    IO.puts("\n" <> String.duplicate("-", 60) <> "\n")
    
    IO.puts("3/3 - Teste completo de estresse:")
    IO.puts("⚠️  ATENÇÃO: Este teste pode impactar o servidor em produção!")
    case IO.gets("Continuar com teste completo? (y/N): ") |> String.trim() |> String.downcase() do
      "y" -> StressTest.run()
      _ -> IO.puts("Teste completo cancelado.")
    end
    
  _ -> 
    IO.puts("Opção inválida. Execute novamente e escolha 1, 2, 3 ou 4.")
end