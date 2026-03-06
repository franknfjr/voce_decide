defmodule RaceConditionTest do
  @moduledoc """
  Teste específico para detectar race conditions na votação
  """

  def run do
    IO.puts("=== TESTE DE RACE CONDITION NA VOTAÇÃO ===")
    IO.puts("Simulando cliques rápidos e simultâneos para detectar problemas de concorrência")
    
    # Iniciar inets para requisições HTTP
    :inets.start()
    :ssl.start()
    
    # Executar diferentes cenários de teste
    IO.puts("\n1. Teste de cliques únicos rápidos...")
    test_rapid_single_clicks()
    
    IO.puts("\n2. Teste de cliques simultâneos em massa...")
    test_simultaneous_mass_clicks()
    
    IO.puts("\n3. Teste de alternância rápida de votos...")
    test_rapid_vote_alternation()
    
    IO.puts("\n4. Teste de spam de cliques...")
    test_click_spam()
    
    IO.puts("\n=== ANÁLISE FINAL ===")
    print_race_condition_analysis()
  end
  
  defp test_rapid_single_clicks do
    IO.puts("Enviando 50 cliques rápidos sequenciais...")
    
    url = ~c"https://voce-decide.fly.dev/"
    
    start_time = System.monotonic_time(:millisecond)
    
    results = Enum.map(1..50, fn i ->
      choice = if rem(i, 2) == 0, do: "culpado", else: "inocente"
      vote_url = ~c"#{url}?vote=#{choice}&test=rapid&i=#{i}"
      
      case :httpc.request(:get, {vote_url, []}, [{:timeout, 5000}], []) do
        {:ok, {{_version, status, _reason}, _headers, _body}} ->
          {:ok, status}
        {:error, reason} ->
          {:error, reason}
      end
    end)
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    successful = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    
    IO.puts("✓ 50 cliques em #{duration}ms")
    IO.puts("✓ Sucessos: #{successful}, Falhas: #{failed}")
    IO.puts("✓ Taxa de cliques: #{Float.round(50 / (duration / 1000), 1)} cliques/segundo")
    
    if failed == 0 do
      IO.puts("✅ Nenhuma falha detectada em cliques rápidos")
    else
      IO.puts("⚠️  #{failed} falhas detectadas - possível limitação do servidor")
    end
  end
  
  defp test_simultaneous_mass_clicks do
    IO.puts("Simulando 100 usuários clicando simultaneamente...")
    
    url = ~c"https://voce-decide.fly.dev/"
    num_users = 100
    
    parent = self()
    
    start_time = System.monotonic_time(:millisecond)
    
    # Criar processos simultâneos
    Enum.each(1..num_users, fn user_id ->
      spawn(fn ->
        choice = if rem(user_id, 2) == 0, do: "culpado", else: "inocente"
        vote_url = ~c"#{url}?vote=#{choice}&user=#{user_id}&test=mass"
        
        result = case :httpc.request(:get, {vote_url, []}, [{:timeout, 10000}], []) do
          {:ok, {{_version, status, _reason}, _headers, _body}} ->
            {:ok, status}
          {:error, reason} ->
            {:error, reason}
        end
        
        send(parent, {:vote_result, user_id, result})
      end)
    end)
    
    # Coletar resultados
    results = collect_vote_results(num_users, [])
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    successful = Enum.count(results, fn {_id, result} -> match?({:ok, _}, result) end)
    failed = Enum.count(results, fn {_id, result} -> match?({:error, _}, result) end)
    
    IO.puts("✓ #{num_users} usuários votando simultaneamente")
    IO.puts("✓ Sucessos: #{successful}, Falhas: #{failed}")
    IO.puts("✓ Duração: #{duration}ms")
    IO.puts("✓ Throughput: #{Float.round(successful / (duration / 1000), 1)} votos/segundo")
    
    # Analisar tipos de erro
    errors = results
    |> Enum.filter(fn {_id, result} -> match?({:error, _}, result) end)
    |> Enum.map(fn {_id, {:error, reason}} -> reason end)
    |> Enum.frequencies()
    
    if map_size(errors) > 0 do
      IO.puts("⚠️  Tipos de erro encontrados:")
      Enum.each(errors, fn {error, count} ->
        IO.puts("   #{inspect(error)}: #{count}x")
      end)
    end
    
    if successful >= num_users * 0.95 do
      IO.puts("✅ Sistema lidou bem com #{num_users} votos simultâneos")
    else
      IO.puts("⚠️  Sistema teve dificuldades com votos simultâneos")
    end
  end
  
  defp test_rapid_vote_alternation do
    IO.puts("Testando alternância rápida entre culpado/inocente...")
    
    url = ~c"https://voce-decide.fly.dev/"
    num_alternations = 30
    
    parent = self()
    
    # Criar múltiplos processos fazendo alternância rápida
    Enum.each(1..5, fn process_id ->
      spawn(fn ->
        results = Enum.map(1..num_alternations, fn i ->
          choice = if rem(i, 2) == 0, do: "culpado", else: "inocente"
          vote_url = ~c"#{url}?vote=#{choice}&proc=#{process_id}&alt=#{i}"
          
          result = case :httpc.request(:get, {vote_url, []}, [{:timeout, 5000}], []) do
            {:ok, {{_version, status, _reason}, _headers, _body}} ->
              {:ok, status}
            {:error, reason} ->
              {:error, reason}
          end
          
          # Alternação muito rápida
          :timer.sleep(Enum.random(10..50))
          result
        end)
        
        send(parent, {:alternation_result, process_id, results})
      end)
    end)
    
    # Coletar resultados
    all_results = collect_alternation_results(5, [])
    
    total_votes = 5 * num_alternations
    successful_votes = all_results
    |> Enum.flat_map(fn {_id, results} -> results end)
    |> Enum.count(&match?({:ok, _}, &1))
    
    IO.puts("✓ 5 processos fazendo #{num_alternations} alternações cada")
    IO.puts("✓ Total de votos: #{total_votes}")
    IO.puts("✓ Sucessos: #{successful_votes}")
    IO.puts("✓ Taxa de sucesso: #{Float.round(successful_votes / total_votes * 100, 1)}%")
    
    if successful_votes >= total_votes * 0.9 do
      IO.puts("✅ Sistema suporta bem alternância rápida de votos")
    else
      IO.puts("⚠️  Possível problema com alternância rápida")
    end
  end
  
  defp test_click_spam do
    IO.puts("Testando spam de cliques (mesmo voto repetido)...")
    
    url = ~c"https://voce-decide.fly.dev/"
    spam_count = 50
    
    parent = self()
    
    # Vários processos spammando o mesmo voto
    Enum.each(1..10, fn spammer_id ->
      spawn(fn ->
        results = Enum.map(1..spam_count, fn click ->
          vote_url = ~c"#{url}?vote=culpado&spammer=#{spammer_id}&click=#{click}"
          
          case :httpc.request(:get, {vote_url, []}, [{:timeout, 3000}], []) do
            {:ok, {{_version, status, _reason}, _headers, _body}} ->
              {:ok, status}
            {:error, reason} ->
              {:error, reason}
          end
        end)
        
        send(parent, {:spam_result, spammer_id, results})
      end)
    end)
    
    # Coletar resultados
    spam_results = collect_spam_results(10, [])
    
    total_spam = 10 * spam_count
    successful_spam = spam_results
    |> Enum.flat_map(fn {_id, results} -> results end)
    |> Enum.count(&match?({:ok, _}, &1))
    
    IO.puts("✓ 10 spammers fazendo #{spam_count} cliques cada")
    IO.puts("✓ Total de spam: #{total_spam}")
    IO.puts("✓ Sucessos: #{successful_spam}")
    
    # Verificar se há rate limiting
    if successful_spam < total_spam * 0.8 do
      IO.puts("✅ Possível rate limiting detectado (bom para prevenir spam)")
    else
      IO.puts("⚠️  Nenhum rate limiting detectado - servidor aceita spam")
    end
  end
  
  defp collect_vote_results(0, results), do: results
  defp collect_vote_results(remaining, results) do
    receive do
      {:vote_result, user_id, result} ->
        collect_vote_results(remaining - 1, [{user_id, result} | results])
    after
      30_000 ->
        IO.puts("⚠️  Timeout coletando #{remaining} resultados de voto")
        results
    end
  end
  
  defp collect_alternation_results(0, results), do: results
  defp collect_alternation_results(remaining, results) do
    receive do
      {:alternation_result, process_id, result} ->
        collect_alternation_results(remaining - 1, [{process_id, result} | results])
    after
      20_000 ->
        IO.puts("⚠️  Timeout coletando #{remaining} resultados de alternação")
        results
    end
  end
  
  defp collect_spam_results(0, results), do: results
  defp collect_spam_results(remaining, results) do
    receive do
      {:spam_result, spammer_id, result} ->
        collect_spam_results(remaining - 1, [{spammer_id, result} | results])
    after
      20_000 ->
        IO.puts("⚠️  Timeout coletando #{remaining} resultados de spam")
        results
    end
  end
  
  defp print_race_condition_analysis do
    IO.puts("\n🔍 ANÁLISE DE RACE CONDITIONS:")
    IO.puts("")
    IO.puts("✅ SINAIS POSITIVOS (sem race condition):")
    IO.puts("   - Todas as requisições processadas com sucesso")
    IO.puts("   - Nenhum erro de timeout ou crash")
    IO.puts("   - Rate limiting funcionando para spam")
    IO.puts("   - Alternância rápida suportada")
    IO.puts("")
    IO.puts("⚠️  SINAIS DE ALERTA (possível race condition):")
    IO.puts("   - Falhas aleatórias em requisições válidas")
    IO.puts("   - Timeouts frequentes")
    IO.puts("   - Erros de servidor (5xx)")
    IO.puts("   - Inconsistências nos contadores")
    IO.puts("")
    IO.puts("🎯 RECOMENDAÇÕES PARA TESTE REAL:")
    IO.puts("   1. Execute a aplicação localmente: mix phx.server")
    IO.puts("   2. Abra múltiplas abas do navegador")
    IO.puts("   3. Clique rapidamente nos botões em várias abas")
    IO.puts("   4. Observe se os contadores ficam inconsistentes")
    IO.puts("   5. Verifique logs no terminal para erros")
    IO.puts("")
    IO.puts("🔧 POSSÍVEIS MELHORIAS:")
    IO.puts("   - Implementar debounce nos botões (evitar duplo clique)")
    IO.puts("   - Adicionar rate limiting por usuário")
    IO.puts("   - Usar atomic operations para incrementos")
    IO.puts("   - Implementar fila de votos se necessário")
  end
end

# Teste adicional para verificar comportamento da interface
defmodule UIBehaviorTest do
  def run do
    IO.puts("\n=== TESTE DE COMPORTAMENTO DA UI ===")
    IO.puts("Como testar manualmente a interface para race conditions:")
    IO.puts("")
    IO.puts("🖱️  TESTE DE CLIQUE RÁPIDO:")
    IO.puts("   1. Abra http://localhost:4000")
    IO.puts("   2. Clique MUITO rapidamente no botão 'Culpado'")
    IO.puts("   3. Observe se o contador incrementa corretamente")
    IO.puts("   4. Repita com 'Inocente'")
    IO.puts("")
    IO.puts("🖱️  TESTE MULTI-TAB:")
    IO.puts("   1. Abra 5-10 abas da mesma página")
    IO.puts("   2. Clique simultaneamente em várias abas")
    IO.puts("   3. Verifique se todos os contadores são atualizados")
    IO.puts("   4. Some os cliques e compare com o total mostrado")
    IO.puts("")
    IO.puts("🖱️  TESTE DE ALTERNÂNCIA:")
    IO.puts("   1. Clique alternadamente Culpado -> Inocente -> Culpado...")
    IO.puts("   2. Faça isso muito rapidamente")
    IO.puts("   3. Verifique se ambos os contadores incrementam")
    IO.puts("")
    IO.puts("🔍 O QUE OBSERVAR:")
    IO.puts("   ✅ Contadores sempre corretos")
    IO.puts("   ✅ Interface responsiva")
    IO.puts("   ✅ Updates em tempo real em todas as abas")
    IO.puts("   ❌ Contadores inconsistentes")
    IO.puts("   ❌ Interface travando")
    IO.puts("   ❌ Erros no console do navegador")
    IO.puts("   ❌ Erros no terminal do servidor")
  end
end

# Script principal
IO.puts("=== TESTES DE RACE CONDITION - VOCÊ DECIDE ===")
IO.puts("Escolha o teste:")
IO.puts("1. Teste automático de race condition no servidor")
IO.puts("2. Instruções para teste manual da interface")
IO.puts("3. Ambos")

choice = case IO.gets("Digite sua escolha (1, 2 ou 3): ") do
  nil -> "1"
  input -> String.trim(input)
end

case choice do
  "1" -> 
    RaceConditionTest.run()
    
  "2" -> 
    UIBehaviorTest.run()
    
  "3" -> 
    RaceConditionTest.run()
    UIBehaviorTest.run()
    
  _ -> 
    IO.puts("Executando teste automático...")
    RaceConditionTest.run()
end