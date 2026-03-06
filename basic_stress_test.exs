defmodule BasicStressTest do
  @moduledoc """
  Teste de estresse básico usando httpc nativo do Erlang
  """

  def run do
    IO.puts("=== TESTE DE ESTRESSE BÁSICO ===")
    IO.puts("Testando servidor: https://voce-decide.fly.dev/")
    
    # Iniciar inets
    :inets.start()
    :ssl.start()
    
    # Executar diferentes tipos de teste
    IO.puts("\n1. Teste de conectividade básica...")
    test_basic_connectivity()
    
    IO.puts("\n2. Teste com 10 usuários simultâneos...")
    test_concurrent_load(10)
    
    IO.puts("\n3. Teste com 50 usuários simultâneos...")
    test_concurrent_load(50)
    
    IO.puts("\n4. Teste com 100 usuários simultâneos...")
    test_concurrent_load(100)
    
    IO.puts("\n5. Teste com 200 usuários simultâneos...")
    test_concurrent_load(200)
    
    IO.puts("\n6. Teste final com 300 usuários simultâneos...")
    test_concurrent_load(300)
    
    IO.puts("\n=== TESTE CONCLUÍDO ===")
    print_summary()
  end
  
  defp test_basic_connectivity do
    url = 'https://voce-decide.fly.dev/'
    
    case :httpc.request(:get, {url, []}, [{:timeout, 10000}], []) do
      {:ok, {{_version, 200, _reason}, _headers, _body}} ->
        IO.puts("✅ Conectividade OK - Status: 200")
      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        IO.puts("⚠️  Conectividade - Status: #{status}")
      {:error, reason} ->
        IO.puts("❌ Falha na conectividade: #{inspect(reason)}")
    end
  end
  
  defp test_concurrent_load(num_users) do
    url = 'https://voce-decide.fly.dev/'
    
    start_time = System.monotonic_time(:millisecond)
    
    # Criar processos para usuários simultâneos
    parent = self()
    
    Enum.each(1..num_users, fn user_id ->
      spawn(fn -> 
        result = simulate_user_requests(url, user_id)
        send(parent, {:result, user_id, result})
      end)
    end)
    
    # Coletar resultados
    results = collect_results(num_users, [])
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Analisar resultados
    analyze_load_test_results(results, duration, num_users)
  end
  
  defp collect_results(0, results), do: results
  defp collect_results(remaining, results) do
    receive do
      {:result, _user_id, result} ->
        collect_results(remaining - 1, [result | results])
    after
      60_000 -> # timeout de 60 segundos
        IO.puts("⚠️  Timeout aguardando #{remaining} usuários")
        results
    end
  end
  
  defp simulate_user_requests(base_url, user_id) do
    # Cada usuário faz algumas requisições
    requests = [
      base_url,
      '#{base_url}?t=#{System.system_time(:millisecond)}',
      '#{base_url}?user=#{user_id}'
    ]
    
    results = Enum.map(requests, fn url ->
      start_time = System.monotonic_time(:millisecond)
      
      result = case :httpc.request(:get, {url, []}, [{:timeout, 15000}], []) do
        {:ok, {{_version, status, _reason}, _headers, _body}} when status in [200, 301, 302, 304] ->
          end_time = System.monotonic_time(:millisecond)
          {:ok, end_time - start_time}
        
        {:ok, {{_version, status, _reason}, _headers, _body}} ->
          {:error, "HTTP #{status}"}
        
        {:error, reason} ->
          {:error, inspect(reason)}
      end
      
      # Pequeno delay entre requisições
      :timer.sleep(Enum.random(50..200))
      result
    end)
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    response_times = results
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, time} -> time end)
    
    %{
      user_id: user_id,
      successful: successful,
      failed: length(requests) - successful,
      response_times: response_times,
      errors: results
              |> Enum.filter(&match?({:error, _}, &1))
              |> Enum.map(fn {:error, err} -> err end)
    }
  end
  
  defp analyze_load_test_results(results, duration, num_users) do
    total_requests = num_users * 3  # 3 requests per user
    successful_requests = Enum.sum(Enum.map(results, & &1.successful))
    failed_requests = Enum.sum(Enum.map(results, & &1.failed))
    
    all_response_times = results
    |> Enum.flat_map(& &1.response_times)
    |> Enum.sort()
    
    avg_response_time = if length(all_response_times) > 0 do
      Enum.sum(all_response_times) / length(all_response_times)
    else
      0
    end
    
    success_rate = if total_requests > 0 do
      (successful_requests / total_requests * 100)
    else
      0
    end
    
    requests_per_second = if duration > 0 do
      successful_requests / (duration / 1000)
    else
      0
    end
    
    IO.puts("Usuários simultâneos: #{num_users}")
    IO.puts("Total de requests: #{total_requests}")
    IO.puts("Requests bem-sucedidos: #{successful_requests}")
    IO.puts("Requests falharam: #{failed_requests}")
    IO.puts("Taxa de sucesso: #{Float.round(success_rate, 1)}%")
    IO.puts("Requests/segundo: #{Float.round(requests_per_second, 1)}")
    IO.puts("Tempo médio de resposta: #{Float.round(avg_response_time, 0)} ms")
    IO.puts("Duração total: #{Float.round(duration / 1000, 1)}s")
    
    # Calcular percentis
    if length(all_response_times) > 0 do
      p50_index = round(length(all_response_times) * 0.5) - 1
      p95_index = round(length(all_response_times) * 0.95) - 1
      p50 = Enum.at(all_response_times, max(0, p50_index))
      p95 = Enum.at(all_response_times, max(0, p95_index))
      min_time = Enum.min(all_response_times)
      max_time = Enum.max(all_response_times)
      
      IO.puts("Tempo mín/máx: #{min_time}/#{max_time} ms")
      IO.puts("P50/P95: #{p50}/#{p95} ms")
    end
    
    # Avaliar performance
    status = cond do
      success_rate >= 99 and avg_response_time < 1000 ->
        "✅ EXCELENTE"
      
      success_rate >= 95 and avg_response_time < 2000 ->
        "✅ BOM"
      
      success_rate >= 90 and avg_response_time < 5000 ->
        "⚠️  ACEITÁVEL"
      
      success_rate >= 80 ->
        "⚠️  PROBLEMA"
      
      true ->
        "❌ FALHA"
    end
    
    IO.puts("Status: #{status}")
    
    # Armazenar resultado para resumo final
    Process.put({:test_result, num_users}, {success_rate, avg_response_time, status})
    
    # Mostrar erros se houver
    all_errors = results
    |> Enum.flat_map(& &1.errors)
    |> Enum.frequencies()
    
    if map_size(all_errors) > 0 do
      IO.puts("Principais erros:")
      all_errors
      |> Enum.sort_by(fn {_error, count} -> -count end)
      |> Enum.take(3)
      |> Enum.each(fn {error, count} ->
        IO.puts("  #{error}: #{count}x")
      end)
    end
  end
  
  defp print_summary do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("RESUMO FINAL DOS TESTES")
    IO.puts(String.duplicate("=", 60))
    
    test_results = [10, 50, 100, 200, 300]
    |> Enum.map(fn users ->
      case Process.get({:test_result, users}) do
        {success_rate, avg_time, status} -> {users, success_rate, avg_time, status}
        nil -> {users, 0, 0, "NÃO TESTADO"}
      end
    end)
    
    Enum.each(test_results, fn {users, success_rate, avg_time, status} ->
      IO.puts("#{users} usuários: #{Float.round(success_rate, 1)}% sucesso, #{Float.round(avg_time, 0)}ms avg - #{status}")
    end)
    
    # Determinar capacidade máxima suportada
    max_supported = test_results
    |> Enum.filter(fn {_users, success_rate, avg_time, _status} ->
      success_rate >= 95 and avg_time < 3000
    end)
    |> Enum.map(fn {users, _, _, _} -> users end)
    |> Enum.max(fn -> 0 end)
    
    IO.puts("\n🎯 CONCLUSÃO:")
    cond do
      max_supported >= 300 ->
        IO.puts("✅ Sistema APROVADO para 300 usuários simultâneos")
        IO.puts("   Servidor está bem dimensionado para a carga esperada")
      
      max_supported >= 200 ->
        IO.puts("⚠️  Sistema suporta #{max_supported} usuários com qualidade")
        IO.puts("   Para 300 usuários, considere otimizações ou mais recursos")
      
      max_supported >= 100 ->
        IO.puts("⚠️  Sistema limitado a #{max_supported} usuários simultâneos")
        IO.puts("   Necessário scaling para suportar 300 usuários")
      
      max_supported > 0 ->
        IO.puts("❌ Sistema suporta apenas #{max_supported} usuários")
        IO.puts("   Requer otimizações significativas")
      
      true ->
        IO.puts("🚨 Sistema não suporta carga concorrente")
        IO.puts("   Problemas críticos detectados")
    end
    
    IO.puts("\n📝 RECOMENDAÇÕES:")
    IO.puts("- Para votação real: implementar teste via WebSocket")
    IO.puts("- Monitorar métricas de CPU/memória durante picos")
    IO.puts("- Considerar cache para recursos estáticos")
    IO.puts("- Implementar rate limiting se não houver")
  end
end

# Teste local para verificar problemas de concorrência na aplicação
defmodule LocalConcurrencyTest do
  def run do
    IO.puts("\n=== TESTE LOCAL DE CONCORRÊNCIA ===")
    IO.puts("Este teste precisa ser executado com a aplicação rodando")
    IO.puts("Execute: mix phx.server")
    IO.puts("Em seguida rode: elixir -S mix run basic_stress_test.exs")
    IO.puts("\nPara testar concorrência local, abra o navegador e:")
    IO.puts("1. Abra várias abas em http://localhost:4000")
    IO.puts("2. Clique rapidamente nos botões de voto em todas as abas")
    IO.puts("3. Observe se os contadores ficam inconsistentes")
    IO.puts("4. Verifique no terminal se há erros de GenServer")
    
    IO.puts("\n🔍 SINAIS DE RACE CONDITION:")
    IO.puts("- Contadores não batem com número de cliques")
    IO.puts("- Erros de timeout no GenServer")
    IO.puts("- Valores negativos nos contadores")
    IO.puts("- Interface travando com muitos cliques")
  end
end

# Script principal
IO.puts("Escolha o teste a executar:")
IO.puts("1. Teste de estresse no servidor (recomendado)")
IO.puts("2. Instruções para teste local de concorrência")
IO.puts("3. Ambos")

choice = case IO.gets("Digite sua escolha (1, 2 ou 3): ") do
  nil -> "1"
  input -> String.trim(input)
end

case choice do
  "1" -> 
    BasicStressTest.run()
    
  "2" -> 
    LocalConcurrencyTest.run()
    
  "3" -> 
    BasicStressTest.run()
    LocalConcurrencyTest.run()
    
  _ -> 
    IO.puts("Executando teste padrão...")
    BasicStressTest.run()
end