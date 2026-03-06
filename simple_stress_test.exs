defmodule SimpleStressTest do
  @moduledoc """
  Teste de estresse simplificado para verificar a capacidade do servidor
  """

  def run do
    IO.puts("=== TESTE DE ESTRESSE SIMPLES ===")
    IO.puts("Testando servidor: https://voce-decide.fly.dev/")
    
    # Iniciar Finch
    {:ok, _} = Finch.start_link(name: TestFinch)
    
    # Executar diferentes tipos de teste
    IO.puts("\n1. Teste de conectividade básica...")
    test_basic_connectivity()
    
    IO.puts("\n2. Teste de carga com 50 usuários simultâneos...")
    test_concurrent_load(50)
    
    IO.puts("\n3. Teste de carga com 100 usuários simultâneos...")
    test_concurrent_load(100)
    
    IO.puts("\n4. Teste de carga com 200 usuários simultâneos...")
    test_concurrent_load(200)
    
    IO.puts("\n5. Teste final com 300 usuários simultâneos...")
    test_concurrent_load(300)
    
    IO.puts("\n=== TESTE CONCLUÍDO ===")
  end
  
  defp test_basic_connectivity do
    url = "https://voce-decide.fly.dev/"
    
    case Finch.build(:get, url)
         |> Finch.request(TestFinch, receive_timeout: 10_000) do
      {:ok, response} ->
        IO.puts("✅ Conectividade OK - Status: #{response.status}")
      {:error, reason} ->
        IO.puts("❌ Falha na conectividade: #{inspect(reason)}")
    end
  end
  
  defp test_concurrent_load(num_users) do
    url = "https://voce-decide.fly.dev/"
    
    start_time = System.monotonic_time(:millisecond)
    
    # Criar tasks para usuários simultâneos
    tasks = Enum.map(1..num_users, fn user_id ->
      Task.async(fn -> simulate_user_requests(url, user_id) end)
    end)
    
    # Aguardar todas as tasks com timeout baseado no número de usuários
    timeout = max(30_000, num_users * 100)
    results = Task.await_all(tasks, timeout)
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Analisar resultados
    analyze_load_test_results(results, duration, num_users)
  end
  
  defp simulate_user_requests(base_url, user_id) do
    # Cada usuário faz algumas requisições para simular uso real
    requests = [
      # Carregar página inicial
      {:get, base_url},
      # Simular algumas interações (GET com parâmetros diferentes)
      {:get, "#{base_url}?t=#{System.system_time(:millisecond)}"},
      {:get, "#{base_url}?user=#{user_id}"}
    ]
    
    results = Enum.map(requests, fn {method, url} ->
      start_time = System.monotonic_time(:millisecond)
      
      result = case Finch.build(method, url)
                    |> Finch.request(TestFinch, receive_timeout: 15_000) do
        {:ok, response} when response.status in [200, 301, 302, 304] ->
          end_time = System.monotonic_time(:millisecond)
          {:ok, end_time - start_time}
        
        {:ok, response} ->
          {:error, "HTTP #{response.status}"}
        
        {:error, reason} ->
          {:error, inspect(reason)}
      end
      
      # Pequeno delay entre requisições do mesmo usuário
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
    
    success_rate = (successful_requests / total_requests * 100)
    requests_per_second = successful_requests / (duration / 1000)
    
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
    cond do
      success_rate >= 99 and avg_response_time < 1000 ->
        IO.puts("✅ EXCELENTE: Sistema muito estável")
      
      success_rate >= 95 and avg_response_time < 2000 ->
        IO.puts("✅ BOM: Sistema estável para esta carga")
      
      success_rate >= 90 and avg_response_time < 5000 ->
        IO.puts("⚠️  ACEITÁVEL: Sistema funciona mas com algumas limitações")
      
      success_rate >= 80 ->
        IO.puts("⚠️  PROBLEMA: Sistema tem dificuldades com esta carga")
      
      true ->
        IO.puts("❌ FALHA: Sistema não suporta esta carga")
    end
    
    # Mostrar erros mais comuns se houver
    all_errors = results
    |> Enum.flat_map(& &1.errors)
    |> Enum.frequencies()
    
    if map_size(all_errors) > 0 do
      IO.puts("Erros mais comuns:")
      all_errors
      |> Enum.sort_by(fn {_error, count} -> -count end)
      |> Enum.take(3)
      |> Enum.each(fn {error, count} ->
        IO.puts("  #{error}: #{count}x")
      end)
    end
  end
end

# Teste adicional para verificar rate limiting
defmodule RateLimitTest do
  def run do
    IO.puts("\n=== TESTE DE RATE LIMITING ===")
    IO.puts("Fazendo muitas requisições rápidas do mesmo IP...")
    
    {:ok, _} = Finch.start_link(name: RateTestFinch)
    
    url = "https://voce-decide.fly.dev/"
    num_requests = 50
    
    start_time = System.monotonic_time(:millisecond)
    
    # Fazer requisições sequenciais muito rápidas
    results = Enum.map(1..num_requests, fn i ->
      case Finch.build(:get, url)
           |> Finch.request(RateTestFinch, receive_timeout: 10_000) do
        {:ok, response} ->
          {i, response.status}
        {:error, reason} ->
          {i, {:error, reason}}
      end
    end)
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    successful = Enum.count(results, fn {_i, status} -> is_integer(status) and status in [200, 301, 302] end)
    rate_limited = Enum.count(results, fn {_i, status} -> status == 429 end)
    other_errors = num_requests - successful - rate_limited
    
    IO.puts("Requisições enviadas: #{num_requests}")
    IO.puts("Bem-sucedidas: #{successful}")
    IO.puts("Rate limited (429): #{rate_limited}")
    IO.puts("Outros erros: #{other_errors}")
    IO.puts("Tempo total: #{duration} ms")
    IO.puts("Requests/segundo: #{Float.round(num_requests / (duration / 1000), 1)}")
    
    if rate_limited > 0 do
      IO.puts("✅ Rate limiting detectado - servidor tem proteção")
    else
      IO.puts("⚠️  Nenhum rate limiting detectado")
    end
  end
end

# Executar os testes
IO.puts("Iniciando testes de estresse...")
IO.puts("Pressione Ctrl+C para interromper a qualquer momento")
IO.puts("")

try do
  SimpleStressTest.run()
  RateLimitTest.run()
  
  IO.puts("\n🎯 RESUMO FINAL:")
  IO.puts("- Se todos os testes com 300 usuários passaram: servidor está bem dimensionado")
  IO.puts("- Se houve falhas: considere otimizações ou scaling horizontal")
  IO.puts("- Para testes de votação real, implemente WebSocket stress testing")
  
rescue
  error ->
    IO.puts("❌ Erro durante execução: #{inspect(error)}")
end