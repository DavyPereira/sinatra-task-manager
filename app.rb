require 'sinatra'
require 'pg'
require 'uri'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 4567)

def with_db
  db = PG.connect(ENV.fetch('DATABASE_URL'))
  db.type_map_for_results = PG::BasicTypeMapForResults.new(db)
  yield db
ensure
  db&.close
end

def mensagem_url(texto)
  URI.encode_www_form_component(texto)
end

def init_db!
  with_db do |db|
    db.exec(<<~SQL)
      CREATE TABLE IF NOT EXISTS tarefas (
        id SERIAL PRIMARY KEY,
        texto TEXT NOT NULL,
        categoria TEXT NOT NULL DEFAULT 'Geral',
        prioridade TEXT NOT NULL DEFAULT 'media',
        concluida BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    db.exec(<<~SQL)
      CREATE TABLE IF NOT EXISTS observacoes (
        id SERIAL PRIMARY KEY,
        tarefa_id INTEGER NOT NULL REFERENCES tarefas(id) ON DELETE CASCADE,
        texto TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    db.exec(<<~SQL)
      CREATE UNIQUE INDEX IF NOT EXISTS tarefas_texto_categoria_unico
      ON tarefas (LOWER(texto), LOWER(categoria));
    SQL
  end
end

def carregar_tarefas
  with_db do |db|
    tarefas_rows = db.exec(<<~SQL)
      SELECT
        id,
        texto,
        categoria,
        prioridade,
        concluida
      FROM tarefas
      ORDER BY
        LOWER(categoria),
        concluida ASC,
        CASE prioridade
          WHEN 'alta' THEN 0
          WHEN 'media' THEN 1
          WHEN 'baixa' THEN 2
          ELSE 3
        END,
        id;
    SQL

    observacoes_rows = db.exec(<<~SQL)
      SELECT
        id,
        tarefa_id,
        texto
      FROM observacoes
      ORDER BY id;
    SQL

    tarefas = tarefas_rows.map do |row|
      {
        id: row['id'],
        texto: row['texto'],
        categoria: row['categoria'],
        prioridade: row['prioridade'],
        concluida: row['concluida'],
        observacoes: []
      }
    end

    tarefas_por_id = tarefas.each_with_object({}) do |tarefa, hash|
      hash[tarefa[:id]] = tarefa
    end

    observacoes_rows.each do |row|
      tarefa = tarefas_por_id[row['tarefa_id']]
      next unless tarefa

      tarefa[:observacoes] << {
        id: row['id'],
        texto: row['texto']
      }
    end

    tarefas
  end
end

init_db!

get '/' do
  tarefas = carregar_tarefas

  @filtro = params[:filtro].to_s
  @mensagem = params[:mensagem].to_s

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
  texto = params[:texto].to_s.strip
  categoria = params[:categoria].to_s.strip
  prioridade = params[:prioridade].to_s.strip.downcase

  categoria = 'Geral' if categoria.empty?
  prioridade = 'media' unless %w[alta media baixa].include?(prioridade)

  if texto.empty?
    redirect "/?mensagem=#{mensagem_url('Digite uma tarefa válida')}"
  end

  duplicada = with_db do |db|
    result = db.exec_params(
      'SELECT 1 FROM tarefas WHERE LOWER(texto) = LOWER($1) AND LOWER(categoria) = LOWER($2) LIMIT 1',
      [texto, categoria]
    )
    result.ntuples.positive?
  end

  if duplicada
    redirect "/?mensagem=#{mensagem_url("Essa tarefa já existe na categoria #{categoria}")}"
  end

  with_db do |db|
    db.exec_params(
      'INSERT INTO tarefas (texto, categoria, prioridade, concluida) VALUES ($1, $2, $3, FALSE)',
      [texto, categoria, prioridade]
    )
  end

  redirect "/?mensagem=#{mensagem_url('Tarefa adicionada com sucesso')}"
end

post '/tarefas/:id/concluir' do
  id = params[:id].to_i

  with_db do |db|
    db.exec_params(
      'UPDATE tarefas SET concluida = NOT concluida WHERE id = $1',
      [id]
    )
  end

  redirect '/'
end

post '/tarefas/:id/excluir' do
  id = params[:id].to_i

  with_db do |db|
    db.exec_params('DELETE FROM tarefas WHERE id = $1', [id])
  end

  redirect '/'
end

post '/limpar_concluidas' do
  with_db do |db|
    db.exec('DELETE FROM tarefas WHERE concluida = TRUE')
  end

  redirect '/'
end

post '/tarefas/:id/observacoes' do
  tarefa_id = params[:id].to_i
  texto = params[:observacao].to_s.strip

  if texto.empty?
    redirect "/?mensagem=#{mensagem_url('Digite uma observação válida')}"
  end

  with_db do |db|
    existe = db.exec_params('SELECT 1 FROM tarefas WHERE id = $1 LIMIT 1', [tarefa_id])

    if existe.ntuples.zero?
      redirect "/?mensagem=#{mensagem_url('Tarefa não encontrada')}"
    end

    db.exec_params(
      'INSERT INTO observacoes (tarefa_id, texto) VALUES ($1, $2)',
      [tarefa_id, texto]
    )
  end

  redirect "/?mensagem=#{mensagem_url('Observação adicionada com sucesso')}"
end

post '/observacoes/:id/excluir' do
  obs_id = params[:id].to_i

  with_db do |db|
    db.exec_params('DELETE FROM observacoes WHERE id = $1', [obs_id])
  end

  redirect "/?mensagem=#{mensagem_url('Observação excluída com sucesso')}"
end