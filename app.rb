require 'sinatra'
require 'json'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 4567)

ARQUIVO_TAREFAS = ENV.fetch('ARQUIVO_TAREFAS', File.expand_path('tarefas.json', __dir__))

def garantir_arquivo
  return if File.exist?(ARQUIVO_TAREFAS)

  File.write(ARQUIVO_TAREFAS, '[]')
end

def carregar_tarefas
  garantir_arquivo

  conteudo = File.read(ARQUIVO_TAREFAS).strip
  return [] if conteudo.empty?

  JSON.parse(conteudo, symbolize_names: true)
rescue JSON::ParserError
  []
end

def salvar_tarefas(tarefas)
  File.write(ARQUIVO_TAREFAS, JSON.pretty_generate(tarefas))
end

def proximo_id(tarefas)
  return 1 if tarefas.empty?
  tarefas.map { |t| t[:id] }.max + 1
end

get '/' do
  tarefas = carregar_tarefas

  ordem_prioridade = { "alta" => 0, "media" => 1, "baixa" => 2 }

  tarefas = tarefas.map do |tarefa|
    tarefa[:categoria] = tarefa[:categoria].to_s.strip.empty? ? 'Geral' : tarefa[:categoria]
    tarefa[:prioridade] = tarefa[:prioridade].to_s.strip.empty? ? 'media' : tarefa[:prioridade]
    tarefa
  end

  tarefas = tarefas.sort_by do |tarefa|
    [
      tarefa[:categoria].downcase,
      tarefa[:concluida] ? 1 : 0,
      ordem_prioridade[tarefa[:prioridade].to_s] || 3,
      tarefa[:id]
    ]
  end

  @filtro = params[:filtro].to_s

  @tarefas_filtradas =
    case @filtro
    when 'pendentes'
      tarefas.select { |t| !t[:concluida] }
    when 'concluidas'
      tarefas.select { |t| t[:concluida] }
    else
      @filtro = 'todas'
      tarefas
    end

  @tarefas_por_categoria = @tarefas_filtradas.group_by { |t| t[:categoria] }

  @total_tarefas = tarefas.length
  @total_pendentes = tarefas.count { |t| !t[:concluida] }
  @total_concluidas = tarefas.count { |t| t[:concluida] }

  erb :index
end

post '/tarefas' do
  tarefas = carregar_tarefas

  texto = params[:texto].to_s.strip
  prioridade = params[:prioridade].to_s.strip.downcase
  categoria = params[:categoria].to_s.strip

  prioridades_validas = %w[alta media baixa]
  prioridade = 'media' unless prioridades_validas.include?(prioridade)
  categoria = 'Geral' if categoria.empty?

  unless texto.empty?
    tarefas << {
      id: proximo_id(tarefas),
      texto: texto,
      categoria: categoria,
      prioridade: prioridade,
      concluida: false
    }

    salvar_tarefas(tarefas)
  end

  redirect '/'
end

post '/tarefas/:id/concluir' do
  tarefas = carregar_tarefas
  id = params[:id].to_i

  tarefa = tarefas.find { |t| t[:id] == id }

  if tarefa
    tarefa[:concluida] = !tarefa[:concluida]
    salvar_tarefas(tarefas)
  end

  redirect '/'
end

post '/tarefas/:id/excluir' do
  tarefas = carregar_tarefas
  id = params[:id].to_i

  tarefas.reject! { |t| t[:id] == id }
  salvar_tarefas(tarefas)

  redirect '/'
end

post '/limpar_concluidas' do
  tarefas = carregar_tarefas
  tarefas.reject! { |t| t[:concluida] }
  salvar_tarefas(tarefas)

  redirect '/'
end