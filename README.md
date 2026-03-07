# Sinatra Task Manager

Uma aplicação web simples de **gerenciamento de tarefas** construída com **Ruby + Sinatra**.
O sistema permite criar, organizar e acompanhar tarefas de forma rápida e intuitiva.

---

## 📌 Funcionalidades

* Criar novas tarefas
* Definir **prioridade** (Alta, Média, Baixa)
* Marcar tarefas como **concluídas**
* **Excluir tarefas**
* **Limpar todas as tarefas concluídas**
* **Filtros de visualização**

  * Todas
  * Pendentes
  * Concluídas
* **Contadores automáticos** de tarefas
* Interface simples e responsiva
* Armazenamento local em **JSON**

---

## 🖼 Interface

A aplicação apresenta:

* Campo para adicionar tarefas
* Seleção de prioridade
* Filtros de visualização
* Indicadores de quantidade de tarefas
* Botões para concluir e excluir tarefas

---

## 🛠 Tecnologias utilizadas

* **Ruby**
* **Sinatra**
* **HTML5**
* **CSS3**
* **JSON** (armazenamento local)

---

## 📂 Estrutura do projeto

```
todo_app/
│
├── app.rb
├── Gemfile
├── tarefas.json
│
├── public/
│   └── style.css
│
└── views/
    └── index.erb
```

---

## 🚀 Como executar o projeto

### 1. Clonar o repositório

```
git clone https://github.com/SEU-USUARIO/sinatra-task-manager.git
```

### 2. Entrar na pasta

```
cd sinatra-task-manager
```

### 3. Instalar as dependências

```
bundle install
```

### 4. Executar a aplicação

```
ruby app.rb
```

### 5. Abrir no navegador

```
http://localhost:4567
```

---

## 📦 Deploy

A aplicação pode ser hospedada em serviços como:

* Railway
* Render
* Fly.io

O deploy pode ser feito conectando o repositório do GitHub e executando:

```
bundle exec ruby app.rb
```

---

## 📈 Melhorias futuras

Possíveis melhorias para o projeto:

* editar tarefas existentes
* adicionar data limite
* autenticação de usuários
* armazenamento em banco de dados
* drag and drop de tarefas
* notificações

---

## 👨‍💻 Autor

Desenvolvido por **Davy Braga**

Projeto criado para prática de desenvolvimento web utilizando Ruby e Sinatra.
