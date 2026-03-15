require 'sinatra'
require 'pg'
require 'uri'
require 'json'
require 'bcrypt'

enable :sessions

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 4567)
set :session_secret, ENV.fetch('SESSION_SECRET', 'uma-chave-bem-secreta-troque-em-producao')

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

def usuario_logado
  return nil unless session[:usuario_id]

  with_db do |db|
    result = db.exec_params(
      'SELECT id, nome, email FROM usuarios WHERE id = $1 LIMIT 1',
      [session[:usuario_id]]
    )
    result.first
  end
end

def exigir_login!
  redirect '/login' unless usuario_logado
end

def init_db!
  with_db do |db|
    db.exec(<<~SQL)
      CREATE TABLE IF NOT EXISTS usuarios (
        id SERIAL PRIMARY KEY,
        nome TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        senha_digest TEXT NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    SQL

    db.exec(<<~SQL)
      CREATE TABLE IF NOT EXISTS tarefas (
        id SERIAL PRIMARY KEY,
        usuario_id INTEGER REFERENCES usuarios(id) ON DELETE CASCADE,
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
      CREATE UNIQUE INDEX IF NOT EXISTS usuarios_email_unico
      ON usuarios (LOWER(email));
    SQL

    db.exec(<<~SQL)
      CREATE UNIQUE INDEX IF NOT EXISTS tarefas_usuario_texto_categoria_unico
      ON tarefas (usuario_id, LOWER(texto), LOWER(categoria));
    SQL
  end
end

def carregar_tarefas(usuario_id)
  with_db do |db|
    tarefas_rows = db.exec_params(<<~SQL, [usuario_id])
      SELECT
        id,
        texto,
        categoria,
        prioridade,
        concluida
      FROM tarefas
      WHERE usuario_id = $1
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

    observacoes_rows = db.exec_params(<<~SQL, [usuario_id])
      SELECT
        o.id,
        o.tarefa_id,
        o.texto
      FROM observacoes o
      INNER JOIN tarefas t ON t.id = o.tarefa_id
      WHERE t.usuario_id = $1
      ORDER BY o.id;
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

before do
  @usuario_atual = usuario_logado
end

get '/' do
  exigir_login!

  tarefas = carregar_tarefas(@usuario_atual['id'])

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

get '/cadastro' do
  redirect '/' if @usuario_atual
  @mensagem = params[:mensagem].to_s
  erb :cadastro
end

post '/cadastro' do
  nome = params[:nome].to_s.strip
  email = params[:email].to_s.strip.downcase
  senha = params[:senha].to_s

  if nome.empty? || email.empty? || senha.empty?
    redirect "/cadastro?mensagem=#{mensagem_url('Preencha todos os campos')}"
  end

  if senha.length < 6
    redirect "/cadastro?mensagem=#{mensagem_url('A senha deve ter pelo menos 6 caracteres')}"
  end

  senha_digest = BCrypt::Password.create(senha)

  begin
    usuario = with_db do |db|
      result = db.exec_params(
        'INSERT INTO usuarios (nome, email, senha_digest) VALUES ($1, $2, $3) RETURNING id, nome, email',
        [nome, email, senha_digest]
      )
      result.first
    end

    session[:usuario_id] = usuario['id']
    redirect "/?mensagem=#{mensagem_url('Conta criada com sucesso')}"
  rescue PG::UniqueViolation
    redirect "/cadastro?mensagem=#{mensagem_url('Este e-mail já está cadastrado')}"
  end
end

get '/login' do
  redirect '/' if @usuario_atual
  @mensagem = params[:mensagem].to_s
  erb :login
end

post '/login' do
  email = params[:email].to_s.strip.downcase
  senha = params[:senha].to_s

  usuario = with_db do |db|
    result = db.exec_params(
      'SELECT id, nome, email, senha_digest FROM usuarios WHERE LOWER(email) = LOWER($1) LIMIT 1',
      [email]
    )
    result.first
  end

  if usuario && BCrypt::Password.new(usuario['senha_digest']) == senha
    session[:usuario_id] = usuario['id']
    redirect "/?mensagem=#{mensagem_url("Bem-vindo, #{usuario['nome']}")}"
  else
    redirect "/login?mensagem=#{mensagem_url('E-mail ou senha inválidos')}"
  end
end

post '/logout' do
  session.clear
  redirect '/login'
end

post '/tarefas' do
  exigir_login!

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
      'SELECT 1 FROM tarefas WHERE usuario_id = $1 AND LOWER(texto) = LOWER($2) AND LOWER(categoria) = LOWER($3) LIMIT 1',
      [@usuario_atual['id'], texto, categoria]
    )
    result.ntuples.positive?
  end

  if duplicada
    redirect "/?mensagem=#{mensagem_url("Essa tarefa já existe na categoria #{categoria}")}"
  end

  with_db do |db|
    db.exec_params(
      'INSERT INTO tarefas (usuario_id, texto, categoria, prioridade, concluida) VALUES ($1, $2, $3, $4, FALSE)',
      [@usuario_atual['id'], texto, categoria, prioridade]
    )
  end

  redirect "/?mensagem=#{mensagem_url('Tarefa adicionada com sucesso')}"
end

post '/tarefas/:id/concluir' do
  exigir_login!
  id = params[:id].to_i

  with_db do |db|
    db.exec_params(
      'UPDATE tarefas SET concluida = NOT concluida WHERE id = $1 AND usuario_id = $2',
      [id, @usuario_atual['id']]
    )
  end

  redirect '/'
end

post '/tarefas/:id/excluir' do
  exigir_login!
  id = params[:id].to_i

  with_db do |db|
    db.exec_params(
      'DELETE FROM tarefas WHERE id = $1 AND usuario_id = $2',
      [id, @usuario_atual['id']]
    )
  end

  redirect '/'
end

post '/limpar_concluidas' do
  exigir_login!

  with_db do |db|
    db.exec_params(
      'DELETE FROM tarefas WHERE concluida = TRUE AND usuario_id = $1',
      [@usuario_atual['id']]
    )
  end

  redirect '/'
end

post '/tarefas/:id/observacoes' do
  exigir_login!
  content_type :json

  tarefa_id = params[:id].to_i
  texto = params[:observacao].to_s.strip

  if texto.empty?
    status 422
    return({ sucesso: false, mensagem: 'Digite uma observação válida' }.to_json)
  end

  observacao = nil

  with_db do |db|
    existe = db.exec_params(
      'SELECT 1 FROM tarefas WHERE id = $1 AND usuario_id = $2 LIMIT 1',
      [tarefa_id, @usuario_atual['id']]
    )

    if existe.ntuples.zero?
      status 404
      return({ sucesso: false, mensagem: 'Tarefa não encontrada' }.to_json)
    end

    result = db.exec_params(
      'INSERT INTO observacoes (tarefa_id, texto) VALUES ($1, $2) RETURNING id, texto',
      [tarefa_id, texto]
    )

    row = result.first

    observacao = {
      id: row['id'],
      texto: row['texto']
    }
  end

  {
    sucesso: true,
    mensagem: 'Observação adicionada com sucesso',
    observacao: observacao
  }.to_json
end

post '/observacoes/:id/excluir' do
  exigir_login!
  content_type :json

  obs_id = params[:id].to_i

  excluida = with_db do |db|
    result = db.exec_params(<<~SQL, [obs_id, @usuario_atual['id']])
      DELETE FROM observacoes
      WHERE id = $1
      AND tarefa_id IN (
        SELECT id FROM tarefas WHERE usuario_id = $2
      )
      RETURNING id;
    SQL
    result.ntuples.positive?
  end

  unless excluida
    status 404
    return({ sucesso: false, mensagem: 'Observação não encontrada' }.to_json)
  end

  {
    sucesso: true,
    mensagem: 'Observação excluída com sucesso',
    id: obs_id
  }.to_json
end