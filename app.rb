require 'sinatra'
require 'pg'
require 'uri'

set :bind, '0.0.0.0'
set :port, ENV.fetch('PORT', 4567)

def db
  @db ||= PG.connect(ENV['DATABASE_URL'])
end

def init_db
  db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS tarefas (
    id SERIAL PRIMARY KEY,
    texto TEXT NOT NULL,
    categoria TEXT,
    prioridade TEXT,
    concluida BOOLEAN DEFAULT FALSE
  );
  SQL

  db.exec <<-SQL
  CREATE TABLE IF NOT EXISTS observacoes (
    id SERIAL PRIMARY KEY,
    tarefa_id INTEGER REFERENCES tarefas(id) ON DELETE CASCADE,
    texto TEXT
  );
  SQL
end

init_db

get '/' do
  tarefas = db.exec("SELECT * FROM tarefas ORDER BY id DESC")

  tarefas.each do |t|
    obs = db.exec_params("SELECT * FROM observacoes WHERE tarefa_id=$1", [t['id']])
    t['observacoes'] = obs
  end

  @tarefas = tarefas
  erb :index
end

post '/tarefas' do
  texto = params[:texto]
  categoria = params[:categoria]
  prioridade = params[:prioridade]

  db.exec_params(
    "INSERT INTO tarefas (texto,categoria,prioridade) VALUES ($1,$2,$3)",
    [texto,categoria,prioridade]
  )

  redirect '/'
end

post '/tarefas/:id/concluir' do
  db.exec_params(
    "UPDATE tarefas SET concluida = NOT concluida WHERE id=$1",
    [params[:id]]
  )

  redirect '/'
end

post '/tarefas/:id/excluir' do
  db.exec_params(
    "DELETE FROM tarefas WHERE id=$1",
    [params[:id]]
  )

  redirect '/'
end

post '/tarefas/:id/observacoes' do
  db.exec_params(
    "INSERT INTO observacoes (tarefa_id,texto) VALUES ($1,$2)",
    [params[:id],params[:observacao]]
  )

  redirect '/'
end

post '/observacoes/:id/excluir' do
  db.exec_params(
    "DELETE FROM observacoes WHERE id=$1",
    [params[:id]]
  )

  redirect '/'
end