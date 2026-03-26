# Guia Completo de Testes - Hackaton FIAP Secure Systems

## Sistema de Analise Automatizada de Diagramas de Arquitetura com IA

Este guia foi escrito para que qualquer pessoa, mesmo sem experiencia previa com Docker, AWS ou este projeto, consiga executar e testar todo o sistema do zero. Siga cada passo na ordem exata.

---

## O que este sistema faz?

Antes de comecar, entenda o que voce vai testar:

1. Voce envia uma imagem de um diagrama de arquitetura de software (PNG, JPG ou PDF)
2. O sistema usa Inteligencia Artificial para analisar o diagrama
3. A IA identifica os componentes, detecta riscos arquiteturais e sugere melhorias
4. Voce consulta o relatorio gerado pela API

O sistema e composto por 4 microsservicos:

| Servico                | O que faz                                                               | Porta |
| ---------------------- | ----------------------------------------------------------------------- | ----- |
| **API Gateway**        | Ponto de entrada. Recebe sua requisicao e roteia para o servico correto | 3000  |
| **Upload Service**     | Recebe o arquivo, salva no storage, inicia o processo de analise        | 3001  |
| **Processing Service** | Baixa o diagrama, envia para a IA, valida a resposta                    | 3002  |
| **Report Service**     | Recebe o resultado da IA e gera o relatorio estruturado                 | 3003  |

A comunicacao entre eles e assincrona via filas de mensagens (RabbitMQ localmente, SQS na AWS).

---

# PARTE 1: TESTES LOCAIS (Docker Compose)

---

## 1.1 Pre-requisitos - Instalacao de Ferramentas

Voce precisa instalar algumas ferramentas antes de comecar. Escolha a secao do seu sistema operacional.

### macOS

#### 1.1.1 Instalar o Homebrew (gerenciador de pacotes do macOS)

Abra o Terminal (pressione `Cmd + Espaco`, digite "Terminal", pressione Enter) e execute:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

O instalador vai pedir sua senha de usuario do Mac (a mesma que voce usa para desbloquear o computador). Digite-a e pressione Enter. A senha nao aparece na tela enquanto voce digita -- isso e normal.

Aguarde a instalacao terminar (pode levar alguns minutos). Para verificar que funcionou:

```bash
brew --version
```

Deve mostrar algo como `Homebrew 4.x.x`.

#### 1.1.2 Instalar o Git

```bash
brew install git
```

Verifique:

```bash
git --version
# Deve mostrar: git version 2.x.x
```

#### 1.1.3 Instalar o Docker Desktop

1. Acesse https://www.docker.com/products/docker-desktop/
2. Clique no botao de download para macOS (escolha "Apple Chip" se seu Mac for M1/M2/M3/M4, ou "Intel Chip" se for mais antigo)
3. Abra o arquivo `.dmg` baixado
4. Arraste o icone do Docker para a pasta Applications
5. Abra o Docker Desktop pela pasta Applications (ou Spotlight: `Cmd + Espaco` e digite "Docker")
6. Na primeira vez, aceite os termos de uso
7. Aguarde ate o icone do Docker na barra de menu (topo da tela) parar de piscar e mostrar "Docker Desktop is running"

Verifique que o Docker esta funcionando:

```bash
docker --version
# Deve mostrar: Docker version 27.x.x

docker compose version
# Deve mostrar: Docker Compose version v2.x.x
```

**IMPORTANTE:** O Docker Desktop precisa estar aberto e rodando sempre que voce for usar este projeto. Se ao tentar rodar um comando Docker voce receber o erro "Cannot connect to the Docker daemon", abra o Docker Desktop e espere ele iniciar.

#### 1.1.4 Instalar o Node.js 20

Opcao A - Via Homebrew (mais simples):

```bash
brew install node@20
```

Opcao B - Via NVM (recomendado se voce trabalha com varios projetos Node.js):

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
```

Feche e reabra o Terminal, depois:

```bash
nvm install 20
nvm use 20
```

Verifique:

```bash
node --version
# Deve mostrar: v20.x.x

npm --version
# Deve mostrar: 10.x.x
```

#### 1.1.5 Instalar o GitHub CLI (opcional, para clonar repositorios privados)

```bash
brew install gh
```

Se os repositorios forem privados, faca login no GitHub:

```bash
gh auth login
```

Quando perguntado:

- "What account do you want to log into?" -> selecione **GitHub.com**
- "What is your preferred protocol for Git operations?" -> selecione **HTTPS**
- "Authenticate Git with your GitHub credentials?" -> selecione **Yes**
- "How would you like to authenticate GitHub CLI?" -> selecione **Login with a web browser**
- Copie o codigo exibido, pressione Enter, cole no navegador que abrir e autorize

#### 1.1.6 Make

O Make ja vem instalado no macOS. Verifique:

```bash
make --version
# Deve mostrar: GNU Make 3.x ou 4.x
```

---

### Windows (WSL2)

O projeto roda em Linux. No Windows, voce precisa do WSL2 (Windows Subsystem for Linux), que permite rodar um Linux real dentro do Windows.

#### 1.1.1 Instalar o WSL2

Abra o PowerShell como Administrador (clique com botao direito no menu Iniciar -> "Windows Terminal (Admin)" ou "PowerShell (Admin)"):

```powershell
wsl --install
```

Reinicie o computador quando solicitado. Apos reiniciar, o Ubuntu sera instalado automaticamente. Na primeira abertura, defina um usuario e senha para o Linux.

Para abrir o Ubuntu: pesquise "Ubuntu" no menu Iniciar.

#### 1.1.2 Instalar o Docker Desktop com WSL2

1. Baixe o Docker Desktop de https://www.docker.com/products/docker-desktop/
2. Execute o instalador (aceite os padroes)
3. Durante a instalacao, marque a opcao **"Use WSL 2 instead of Hyper-V"**
4. Apos instalar, abra o Docker Desktop
5. Va em Settings (engrenagem no topo) -> Resources -> WSL Integration
6. Ative a integracao com a distro Ubuntu
7. Clique "Apply & restart"

Agora abra o Ubuntu (terminal WSL) e verifique:

```bash
docker --version
docker compose version
```

#### 1.1.3 Instalar demais ferramentas (dentro do Ubuntu/WSL)

Todos os comandos daqui para frente devem ser executados dentro do terminal Ubuntu/WSL:

```bash
sudo apt update && sudo apt install -y git make curl

# Node.js 20 via NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20

# Verificar
node --version
npm --version
git --version
docker --version
```

---

### Linux (Ubuntu/Debian)

#### 1.1.1 Instalar pacotes basicos

```bash
sudo apt update
sudo apt install -y git make curl wget
```

#### 1.1.2 Instalar o Docker

```bash
# Instalar Docker
sudo apt install -y docker.io docker-compose-plugin

# Adicionar seu usuario ao grupo docker (para nao precisar de sudo)
sudo usermod -aG docker $USER

# IMPORTANTE: saia e entre novamente na sessao para a mudanca fazer efeito
# Ou execute:
newgrp docker
```

Verifique:

```bash
docker --version
docker compose version
```

#### 1.1.3 Instalar o Node.js 20

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20

# Verificar
node --version
npm --version
```

---

## 1.2 Clonar os Repositorios

O projeto e dividido em 5 repositorios. Todos precisam estar na mesma pasta pai.

Abra o terminal e execute:

```bash
# Crie uma pasta para o projeto e entre nela
mkdir -p ~/fiap-hackaton && cd ~/fiap-hackaton

# Clone todos os 5 repositorios
git clone https://github.com/fiap-tech-challenge-projects/hackaton-infra.git
git clone https://github.com/fiap-tech-challenge-projects/hackaton-upload-service.git
git clone https://github.com/fiap-tech-challenge-projects/hackaton-processing-service.git
git clone https://github.com/fiap-tech-challenge-projects/hackaton-report-service.git
git clone https://github.com/fiap-tech-challenge-projects/hackaton-api-gateway.git
```

Verifique que todos foram clonados:

```bash
ls -la ~/fiap-hackaton
```

Voce deve ver 5 pastas:

```
hackaton-infra/
hackaton-api-gateway/
hackaton-upload-service/
hackaton-processing-service/
hackaton-report-service/
```

**Se algum clone falhou** com erro de permissao, os repositorios podem ser privados. Nesse caso:

```bash
gh auth login   # faca login no GitHub (veja secao 1.1.5)
# depois tente clonar novamente
```

---

## 1.3 Configurar Variaveis de Ambiente

As variaveis de ambiente controlam qual provedor de IA o sistema vai usar. Ha 3 opcoes:

| Provedor               | Custo            | Qualidade   | Precisa de API Key? |
| ---------------------- | ---------------- | ----------- | ------------------- |
| **Ollama** (padrao)    | Gratuito         | Boa (local) | Nao                 |
| **Claude (Anthropic)** | ~$0.003/diagrama | Excelente   | Sim                 |
| **OpenAI (GPT-4V)**    | ~$0.005/diagrama | Muito boa   | Sim                 |

### Criar o arquivo .env

```bash
cd ~/fiap-hackaton/hackaton-infra

# Copie o arquivo de exemplo
cp .env.example .env
```

O conteudo do `.env` sera:

```
# LLM Provider: claude | openai | ollama
LLM_PROVIDER=ollama

# Ollama (default for local dev - free, no API key needed)
OLLAMA_BASE_URL=http://host.docker.internal:11434

# Anthropic Claude (optional)
ANTHROPIC_API_KEY=

# OpenAI (optional)
OPENAI_API_KEY=
```

Vamos entender cada variavel:

| Variavel            | O que faz                                              | Quando mudar                             |
| ------------------- | ------------------------------------------------------ | ---------------------------------------- |
| `LLM_PROVIDER`      | Define qual IA usar: `ollama`, `anthropic` ou `openai` | Mude se quiser usar Claude ou OpenAI     |
| `OLLAMA_BASE_URL`   | Endereco do Ollama rodando na sua maquina              | Nao mexa nisso (o valor padrao funciona) |
| `ANTHROPIC_API_KEY` | Chave de API da Anthropic (para usar Claude)           | Preencha se `LLM_PROVIDER=anthropic`     |
| `OPENAI_API_KEY`    | Chave de API da OpenAI (para usar GPT-4)               | Preencha se `LLM_PROVIDER=openai`        |

Escolha UMA das opcoes abaixo e siga as instrucoes:

---

### Opcao A: Usar Ollama (GRATUITO - recomendado para testes)

O Ollama roda modelos de IA localmente na sua maquina, sem custo.

**Passo 1: Instalar o Ollama**

macOS/Linux:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

macOS via Homebrew:

```bash
brew install ollama
```

Windows: Baixe de https://ollama.com/download

**Passo 2: Baixar um modelo com capacidade de visao (entende imagens)**

```bash
ollama pull llava
```

Este download tem aproximadamente 4GB. Aguarde terminar.

**Passo 3: Verificar que o Ollama esta rodando**

```bash
# Listar modelos instalados
ollama list
# Deve mostrar "llava" na lista

# Testar a API do Ollama
curl http://localhost:11434/api/tags
# Deve retornar um JSON com os modelos
```

**Passo 4: O arquivo .env ja esta configurado para Ollama (padrao)**

Nao precisa mudar nada no `.env`.

**ATENCAO:** O Ollama precisa estar rodando antes de iniciar o sistema. Se voce reiniciou o computador, execute `ollama serve` em um terminal separado (no macOS ele inicia automaticamente).

---

### Opcao B: Usar Claude (Anthropic) - melhor qualidade

**Passo 1: Criar conta na Anthropic**

1. Acesse https://console.anthropic.com/
2. Clique em "Sign up" (ou "Log in" se ja tem conta)
3. Preencha email e senha, ou use login com Google
4. Confirme o email

**Passo 2: Adicionar creditos (necessario para usar a API)**

1. No console, va em "Plans & Billing" no menu lateral
2. Adicione um metodo de pagamento
3. Adicione pelo menos $5 de creditos (suficiente para centenas de analises)

**Passo 3: Criar uma API Key**

1. No console, va em "API Keys" no menu lateral
2. Clique em "Create Key"
3. De um nome como "hackaton-local"
4. Copie a chave gerada (comeca com `sk-ant-api03-...`)
5. **IMPORTANTE:** Salve esta chave em local seguro. Ela nao sera mostrada novamente.

**Passo 4: Configurar o .env**

Edite o arquivo `~/fiap-hackaton/hackaton-infra/.env`:

```bash
nano ~/fiap-hackaton/hackaton-infra/.env
# Ou use qualquer editor: vim, code, etc.
```

Altere para:

```
LLM_PROVIDER=anthropic
OLLAMA_BASE_URL=http://host.docker.internal:11434
ANTHROPIC_API_KEY=sk-ant-api03-SUA-CHAVE-AQUI
OPENAI_API_KEY=
```

Salve o arquivo (no nano: `Ctrl+O`, Enter, `Ctrl+X`).

---

### Opcao C: Usar OpenAI (GPT-4 Vision)

**Passo 1: Criar conta na OpenAI**

1. Acesse https://platform.openai.com/
2. Clique em "Sign up" (ou "Log in" se ja tem conta)
3. Preencha os dados

**Passo 2: Adicionar creditos**

1. Va em "Settings" -> "Billing" no menu lateral
2. Adicione um metodo de pagamento
3. Adicione pelo menos $5 de creditos

**Passo 3: Criar uma API Key**

1. Va em "API Keys" no menu lateral (https://platform.openai.com/api-keys)
2. Clique em "Create new secret key"
3. De um nome como "hackaton-local"
4. Copie a chave gerada (comeca com `sk-...`)
5. **IMPORTANTE:** Salve esta chave. Ela nao sera mostrada novamente.

**Passo 4: Configurar o .env**

Edite `~/fiap-hackaton/hackaton-infra/.env`:

```
LLM_PROVIDER=openai
OLLAMA_BASE_URL=http://host.docker.internal:11434
ANTHROPIC_API_KEY=
OPENAI_API_KEY=sk-SUA-CHAVE-AQUI
```

---

## 1.4 Subir a Infraestrutura

Existem duas formas de rodar o projeto localmente. Escolha a que faz mais sentido para voce:

| Opcao                         | Quando usar                                                                       | O que sobe                                  |
| ----------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------- |
| **A: Somente infraestrutura** | Voce quer desenvolver/debugar os servicos localmente (com `npm run start:dev`)    | PostgreSQL, DynamoDB, RabbitMQ, MinIO       |
| **B: Tudo junto**             | Voce quer testar o sistema completo rapidamente sem se preocupar com cada servico | Infraestrutura + os 4 servicos da aplicacao |

### Opcao A: Somente infraestrutura (para desenvolvimento)

```bash
cd ~/fiap-hackaton/hackaton-infra

# Sobe PostgreSQL, DynamoDB, RabbitMQ, MinIO
make dev
```

O que este comando faz nos bastidores:

- Executa `docker compose up -d` (o `-d` significa "detached" - roda em segundo plano)
- Baixa as imagens Docker de cada servico de infraestrutura (apenas na primeira vez)
- Cria e inicia os containers

Apos o comando terminar, voce vera uma mensagem como:

```
Infrastructure is running:
  PostgreSQL (upload):  localhost:5432
  PostgreSQL (report):  localhost:5433
  DynamoDB Local:       localhost:8000
  RabbitMQ:             localhost:5672 (mgmt: localhost:15672)
  MinIO:                localhost:9000 (console: localhost:9001)

Run each service with: cd ../hackaton-<service> && npm run start:dev
```

Cada servico de infraestrutura e o seguinte:

| Servico                 | Porta                    | O que faz                                                              | Credenciais                                                              |
| ----------------------- | ------------------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **PostgreSQL (upload)** | 5432                     | Banco de dados do Upload Service - armazena registros de analises      | user: `upload_user`, password: `upload_pass`, database: `upload_service` |
| **PostgreSQL (report)** | 5433                     | Banco de dados do Report Service - armazena relatorios                 | user: `report_user`, password: `report_pass`, database: `report_service` |
| **DynamoDB Local**      | 8000                     | Banco NoSQL do Processing Service - armazena resultados da IA          | access key: `local`, secret: `local`                                     |
| **RabbitMQ**            | 5672 (AMQP) / 15672 (UI) | Fila de mensagens entre os servicos                                    | user: `rabbit`, password: `rabbit`                                       |
| **MinIO**               | 9000 (API) / 9001 (UI)   | Storage de arquivos compativel com S3 - armazena os diagramas enviados | user: `minioadmin`, password: `minioadmin`                               |

Verifique que todos os containers estao rodando:

```bash
docker compose ps
```

Voce deve ver algo como (todos com "Up" ou "running"):

```
NAME                     STATUS
hackaton-infra-postgres-upload-1    Up (healthy)
hackaton-infra-postgres-report-1    Up (healthy)
hackaton-infra-dynamodb-local-1     Up
hackaton-infra-dynamodb-init-1      Exited (0)    <-- normal, e um container de inicializacao
hackaton-infra-rabbitmq-1           Up (healthy)
hackaton-infra-minio-1              Up (healthy)
hackaton-infra-minio-init-1         Exited (0)    <-- normal, e um container de inicializacao
```

Os containers `dynamodb-init` e `minio-init` com status "Exited (0)" estao corretos. Eles existem apenas para criar a tabela no DynamoDB e o bucket no MinIO, respectivamente. Apos executar sua tarefa, eles param.

---

### Opcao B: Tudo junto (infraestrutura + servicos)

**IMPORTANTE:** Para esta opcao funcionar, todos os 5 repositorios devem estar clonados na mesma pasta pai (como descrito na secao 1.2).

```bash
cd ~/fiap-hackaton/hackaton-infra

# Sobe tudo: infraestrutura + os 4 servicos da aplicacao
make up
```

Este comando:

1. Baixa todas as imagens Docker necessarias (primeira vez pode demorar alguns minutos)
2. Compila (build) os 4 servicos da aplicacao a partir do codigo fonte
3. Inicia tudo na ordem correta (primeiro infraestrutura, depois servicos)

Acompanhe os logs para saber quando tudo estiver pronto:

```bash
make logs
```

**O que esperar nos logs:**

Aguarde ate ver mensagens como estas (a ordem pode variar):

```
upload-service      | [Nest] LOG [NestApplication] Nest application successfully started
processing-service  | [Nest] LOG [NestApplication] Nest application successfully started
report-service      | [Nest] LOG [NestApplication] Nest application successfully started
api-gateway         | [Nest] LOG [NestApplication] Nest application successfully started
```

Isso significa que todos os servicos iniciaram com sucesso. Pressione `Ctrl+C` para sair dos logs (os servicos continuam rodando em segundo plano).

Verifique:

```bash
docker compose -f docker-compose.yml -f docker-compose.services.yml ps
```

Todos devem estar "Up" ou "running" (exceto os containers de init que mostram "Exited (0)").

---

## 1.5 Desenvolvimento Local (servicos fora do Docker)

**Esta secao so se aplica se voce escolheu a Opcao A na secao 1.4** (somente infraestrutura). Se voce escolheu a Opcao B (tudo junto), pule para a secao 1.6.

Quando voce quer desenvolver ou debugar os servicos, e mais pratico roda-los diretamente na sua maquina (fora do Docker) enquanto a infraestrutura (bancos, filas, storage) roda no Docker.

Voce precisara de **4 terminais abertos simultaneamente** (um para cada servico).

### Terminal 1: Upload Service

```bash
cd ~/fiap-hackaton/hackaton-upload-service

# Instalar dependencias
npm install

# Gerar o client Prisma (ORM para o banco de dados)
npx prisma generate

# Aplicar as migracoes do banco de dados (criar as tabelas)
npx prisma migrate deploy
# Se nao houver pasta de migracoes, use: npx prisma db push

# Definir variaveis de ambiente para conexao local
export DATABASE_URL="postgresql://upload_user:upload_pass@localhost:5432/upload_service"
export RABBITMQ_URL="amqp://rabbit:rabbit@localhost:5672"
export S3_ENDPOINT="http://localhost:9000"
export S3_BUCKET="diagrams"
export S3_ACCESS_KEY="minioadmin"
export S3_SECRET_KEY="minioadmin"
export S3_REGION="us-east-1"
export S3_FORCE_PATH_STYLE="true"
export PORT=3001

# Iniciar o servico em modo de desenvolvimento (com hot reload)
npm run start:dev
```

Aguarde ate ver: `Nest application successfully started`

O servico esta rodando em http://localhost:3001

### Terminal 2: Processing Service

```bash
cd ~/fiap-hackaton/hackaton-processing-service

# Instalar dependencias
npm install

# Definir variaveis de ambiente
export DYNAMODB_ENDPOINT="http://localhost:8000"
export DYNAMODB_TABLE_NAME="hackaton-analysis-results-development"
export RABBITMQ_URL="amqp://rabbit:rabbit@localhost:5672"
export S3_ENDPOINT="http://localhost:9000"
export S3_BUCKET="diagrams"
export S3_FORCE_PATH_STYLE="true"
export AWS_ACCESS_KEY_ID="local"
export AWS_SECRET_ACCESS_KEY="local"
export AWS_REGION="us-east-1"
export PORT=3002

# Configurar LLM (escolha um):
export LLM_PROVIDER="ollama"
export OLLAMA_BASE_URL="http://localhost:11434"
# OU:
# export LLM_PROVIDER="anthropic"
# export ANTHROPIC_API_KEY="sk-ant-..."
# OU:
# export LLM_PROVIDER="openai"
# export OPENAI_API_KEY="sk-..."

# Iniciar o servico
npm run start:dev
```

Aguarde ate ver: `Nest application successfully started`

O servico esta rodando em http://localhost:3002

### Terminal 3: Report Service

```bash
cd ~/fiap-hackaton/hackaton-report-service

# Instalar dependencias
npm install

# Gerar o client Prisma
npx prisma generate

# Aplicar migracoes
npx prisma migrate deploy
# Se nao houver pasta de migracoes, use: npx prisma db push

# Definir variaveis de ambiente
export DATABASE_URL="postgresql://report_user:report_pass@localhost:5433/report_service"
export RABBITMQ_URL="amqp://rabbit:rabbit@localhost:5672"
export PORT=3003

# Iniciar o servico
npm run start:dev
```

Aguarde ate ver: `Nest application successfully started`

O servico esta rodando em http://localhost:3003

### Terminal 4: API Gateway

```bash
cd ~/fiap-hackaton/hackaton-api-gateway

# Instalar dependencias
npm install

# Definir variaveis de ambiente
export UPLOAD_SERVICE_URL="http://localhost:3001"
export PROCESSING_SERVICE_URL="http://localhost:3002"
export REPORT_SERVICE_URL="http://localhost:3003"
export PORT=3000

# Iniciar o servico
npm run start:dev
```

Aguarde ate ver: `Nest application successfully started`

O servico esta rodando em http://localhost:3000

**Nota sobre DATABASE_URL:** Quando os servicos rodam dentro do Docker (Opcao B), eles usam nomes de rede Docker como `postgres-upload` e `postgres-report`. Quando rodam fora do Docker (esta opcao), eles usam `localhost` com as portas mapeadas (5432 e 5433).

---

## 1.6 Testar o Fluxo Completo

Agora que o sistema esta rodando (seja via Docker completo ou desenvolvimento local), vamos testa-lo passo a passo.

### Passo 1: Verificar a saude dos servicos

```bash
curl http://localhost:3000/api/v1/health | python3 -m json.tool
```

**O que este comando faz:** Envia um GET para o endpoint de health check do API Gateway. O `python3 -m json.tool` formata o JSON para ficar mais legivel.

**Resposta esperada:**

```json
{
  "status": "ok",
  "service": "api-gateway",
  "version": "1.0.0",
  "timestamp": "2026-03-26T10:00:00.000Z",
  "services": {
    "upload-service": "ok",
    "processing-service": "ok",
    "report-service": "ok"
  }
}
```

**O que cada campo significa:**

- `status`: "ok" = o API Gateway esta saudavel
- `services.upload-service`: "ok" = o Upload Service esta respondendo
- `services.processing-service`: "ok" = o Processing Service esta respondendo
- `services.report-service`: "ok" = o Report Service esta respondendo

**Se algum servico mostrar "error":** O servico correspondente nao esta rodando ou nao conseguiu conectar nas dependencias. Verifique os logs (secao 1.8).

---

### Passo 2: Preparar uma imagem de diagrama para teste

Voce precisa de uma imagem de um diagrama de arquitetura de software. Aqui estao algumas formas de conseguir uma:

**Opcao 1: Desenhar um diagrama (recomendado)**

1. Acesse https://app.diagrams.net/ (draw.io - gratuito, nao precisa de conta)
2. Clique em "Create New Diagram" -> "Blank Diagram"
3. Desenhe um diagrama simples. Exemplo: arraste retangulos e escreva "Frontend", "API Gateway", "Database", "Cache" e conecte-os com setas
4. Exporte: File -> Export as -> PNG -> Export -> Download

**Opcao 2: Usar uma imagem da internet**

- Pesquise no Google Imagens por "microservices architecture diagram" ou "software architecture diagram"
- Baixe qualquer imagem PNG ou JPG

**Opcao 3: Criar uma imagem de teste simples**

```bash
# Se voce tem o ImageMagick instalado:
convert -size 800x600 xc:white \
  -fill blue -draw "rectangle 50,50 200,120" \
  -fill black -pointsize 16 -draw "text 70,90 'Frontend'" \
  -fill green -draw "rectangle 300,50 450,120" \
  -fill black -draw "text 320,90 'API'" \
  -fill red -draw "rectangle 550,50 700,120" \
  -fill black -draw "text 570,90 'Database'" \
  test-diagram.png
```

Salve o arquivo em um local que voce lembre, por exemplo `~/fiap-hackaton/test-diagram.png`.

---

### Passo 3: Fazer upload do diagrama

```bash
curl -X POST http://localhost:3000/api/v1/analyses \
  -F "file=@/caminho/para/sua/imagem.png" \
  -v | python3 -m json.tool
```

**IMPORTANTE:** Substitua `/caminho/para/sua/imagem.png` pelo caminho real do seu arquivo. Exemplos:

- macOS: `-F "file=@/Users/seunome/Downloads/diagram.png"`
- Linux: `-F "file=@/home/seunome/Downloads/diagram.png"`
- WSL: `-F "file=@/mnt/c/Users/seunome/Downloads/diagram.png"`

**O que este comando faz:**

- `curl -X POST`: Envia uma requisicao HTTP POST
- `http://localhost:3000/api/v1/analyses`: Para o endpoint de criacao de analise no API Gateway
- `-F "file=@..."`: Envia o arquivo como multipart/form-data (como se fosse um formulario de upload)
- `-v`: Modo verbose (mostra detalhes da requisicao)

**Resposta esperada (HTTP 202 Accepted):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "fileName": "diagram.png",
  "fileType": "image/png",
  "fileSize": 102400,
  "status": "PROCESSING",
  "createdAt": "2026-03-26T10:00:00.000Z",
  "updatedAt": "2026-03-26T10:00:00.000Z"
}
```

**O que significa cada campo:**

- `id`: Identificador unico desta analise (UUID). **COPIE E SALVE ESTE ID!** Voce vai precisar dele nos proximos passos.
- `fileName`: Nome do arquivo enviado
- `fileType`: Tipo MIME do arquivo (image/png, image/jpeg, application/pdf)
- `fileSize`: Tamanho do arquivo em bytes
- `status`: "PROCESSING" indica que a analise foi iniciada e a IA esta trabalhando
- `createdAt`/`updatedAt`: Timestamps

**Erros possiveis:**

Se voce receber `400 Bad Request`:

```json
{
  "statusCode": 400,
  "error": "Bad Request",
  "message": "File type not allowed. Allowed: PNG, JPG, JPEG, PDF"
}
```

O arquivo enviado nao e de um tipo suportado. Use apenas PNG, JPG, JPEG ou PDF.

Se voce receber `413 Payload Too Large`:

```json
{
  "statusCode": 413,
  "error": "Payload Too Large",
  "message": "File size exceeds maximum of 10MB"
}
```

O arquivo e maior que 10MB. Reduza o tamanho ou use outra imagem.

---

### Passo 4: Consultar o status da analise

Substitua `{id}` pelo ID que voce copiou no passo anterior:

```bash
curl http://localhost:3000/api/v1/analyses/{id} | python3 -m json.tool
```

Exemplo real:

```bash
curl http://localhost:3000/api/v1/analyses/550e8400-e29b-41d4-a716-446655440000 | python3 -m json.tool
```

**Transicoes de status:**

O sistema e assincrono. A analise passa por estas etapas:

```
RECEIVED  ->  PROCESSING  ->  ANALYZED  (sucesso)
                           ->  ERROR     (falha)
```

| Status       | Significado                                | O que fazer                                    |
| ------------ | ------------------------------------------ | ---------------------------------------------- |
| `RECEIVED`   | Arquivo recebido, aguardando processamento | Aguarde (transitorio, dura milissegundos)      |
| `PROCESSING` | A IA esta analisando o diagrama            | Aguarde 5-30 segundos e consulte novamente     |
| `ANALYZED`   | Analise concluida com sucesso!             | Consulte o relatorio (passo 5)                 |
| `ERROR`      | Algo deu errado no processamento           | Verifique `errorMessage` na resposta e os logs |

**Script para verificar automaticamente a cada 5 segundos:**

```bash
# Substitua o ID abaixo pelo seu
ANALYSIS_ID="550e8400-e29b-41d4-a716-446655440000"

while true; do
  RESPONSE=$(curl -s http://localhost:3000/api/v1/analyses/$ANALYSIS_ID)
  STATUS=$(echo $RESPONSE | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  echo "$(date +%H:%M:%S) - Status: $STATUS"

  if [ "$STATUS" = "ANALYZED" ]; then
    echo "Analise concluida com sucesso!"
    break
  fi

  if [ "$STATUS" = "ERROR" ]; then
    echo "Erro na analise. Resposta completa:"
    echo $RESPONSE | python3 -m json.tool
    break
  fi

  sleep 5
done
```

---

### Passo 5: Consultar o relatorio

Quando o status for `ANALYZED`, o relatorio esta pronto:

```bash
curl http://localhost:3000/api/v1/analyses/{id}/report | python3 -m json.tool
```

**Resposta esperada:**

```json
{
  "id": "660e8400-e29b-41d4-a716-446655440000",
  "analysisId": "550e8400-e29b-41d4-a716-446655440000",
  "title": "Architecture Analysis Report",
  "summary": "The diagram shows a microservices architecture with 8 components. 3 critical risks were identified related to security and scalability.",
  "components": [
    {
      "id": "comp-1",
      "name": "API Gateway",
      "type": "gateway",
      "description": "Entry point for all client requests, handles routing and authentication",
      "connections": ["User Service", "Order Service", "Payment Service"]
    },
    {
      "id": "comp-2",
      "name": "User Service",
      "type": "service",
      "description": "Manages user registration, authentication, and profile data",
      "connections": ["PostgreSQL Users DB", "Redis Cache"]
    }
  ],
  "risks": [
    {
      "id": "risk-1",
      "title": "Single Point of Failure - API Gateway",
      "description": "The API Gateway has no redundancy. If it fails, all services become unreachable.",
      "severity": "critical",
      "category": "reliability",
      "affectedComponents": ["API Gateway"]
    }
  ],
  "recommendations": [
    {
      "id": "rec-1",
      "title": "Add API Gateway Redundancy",
      "description": "Deploy multiple instances of the API Gateway behind a load balancer to eliminate the single point of failure.",
      "priority": "high",
      "effort": "medium",
      "relatedRisks": ["Single Point of Failure - API Gateway"]
    }
  ],
  "metadata": {
    "model": "claude-sonnet-4-20250514",
    "promptVersion": "v1",
    "processingTimeMs": 5200,
    "confidence": 0.85,
    "analyzedAt": "2026-03-26T10:00:30.000Z"
  },
  "createdAt": "2026-03-26T10:00:35.000Z"
}
```

**Entendendo cada secao do relatorio:**

**`summary`** - Resumo executivo da analise. Uma ou duas frases descrevendo o que a IA encontrou no diagrama.

**`components`** - Lista de componentes identificados no diagrama:

- `name`: Nome do componente (ex: "API Gateway", "Database")
- `type`: Tipo do componente (ex: "gateway", "service", "database", "cache", "queue")
- `description`: O que a IA entende que este componente faz
- `connections`: Com quais outros componentes ele se conecta

**`risks`** - Riscos arquiteturais detectados:

- `title`: Nome curto do risco
- `description`: Explicacao detalhada do risco
- `severity`: Gravidade - `critical` (critica), `high` (alta), `medium` (media), `low` (baixa)
- `category`: Categoria - `security`, `reliability`, `scalability`, `maintainability`, `performance`
- `affectedComponents`: Quais componentes sao afetados

**`recommendations`** - Sugestoes de melhoria:

- `title`: Nome curto da recomendacao
- `description`: Explicacao detalhada do que fazer
- `priority`: Prioridade - `high`, `medium`, `low`
- `effort`: Esforco estimado - `low`, `medium`, `high`
- `relatedRisks`: Quais riscos esta recomendacao mitiga

**`metadata`** - Metadados do processamento:

- `model`: Qual modelo de IA foi usado (ex: "claude-sonnet-4-20250514", "llava", "gpt-4-vision")
- `promptVersion`: Versao do prompt template usado
- `processingTimeMs`: Tempo de processamento em milissegundos
- `confidence`: Score de confianca de 0 a 1 (quanto mais perto de 1, mais confiavel)
- `analyzedAt`: Quando a analise foi feita

---

### Passo 6: Listar todas as analises

```bash
curl "http://localhost:3000/api/v1/analyses?page=1&limit=10" | python3 -m json.tool
```

**Parametros de query disponiveis:**

| Parametro   | Tipo   | Padrao      | Descricao                                                         |
| ----------- | ------ | ----------- | ----------------------------------------------------------------- |
| `page`      | numero | 1           | Numero da pagina                                                  |
| `limit`     | numero | 10          | Quantidade de items por pagina (maximo 100)                       |
| `status`    | texto  | -           | Filtrar por status: `RECEIVED`, `PROCESSING`, `ANALYZED`, `ERROR` |
| `sortBy`    | texto  | `createdAt` | Campo para ordenacao                                              |
| `sortOrder` | texto  | `desc`      | Ordem: `asc` (crescente) ou `desc` (decrescente)                  |

Exemplos:

```bash
# Listar apenas analises concluidas
curl "http://localhost:3000/api/v1/analyses?status=ANALYZED" | python3 -m json.tool

# Listar as 5 mais recentes
curl "http://localhost:3000/api/v1/analyses?limit=5&sortOrder=desc" | python3 -m json.tool

# Listar analises com erro
curl "http://localhost:3000/api/v1/analyses?status=ERROR" | python3 -m json.tool
```

**Resposta esperada:**

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "fileName": "architecture-diagram.png",
      "fileType": "image/png",
      "fileSize": 1024000,
      "status": "ANALYZED",
      "createdAt": "2026-03-26T10:00:00.000Z",
      "updatedAt": "2026-03-26T10:00:35.000Z"
    }
  ],
  "meta": {
    "page": 1,
    "limit": 10,
    "total": 42,
    "totalPages": 5
  }
}
```

---

### Passo 7: Listar todos os relatorios

```bash
curl "http://localhost:3000/api/v1/reports?page=1&limit=10" | python3 -m json.tool
```

**Resposta esperada:**

```json
{
  "data": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440000",
      "analysisId": "550e8400-e29b-41d4-a716-446655440000",
      "title": "Architecture Analysis Report",
      "summary": "The diagram shows a microservices architecture...",
      "componentCount": 8,
      "riskCount": 3,
      "recommendationCount": 5,
      "createdAt": "2026-03-26T10:00:35.000Z"
    }
  ],
  "meta": {
    "page": 1,
    "limit": 10,
    "total": 15,
    "totalPages": 2
  }
}
```

Voce tambem pode consultar um relatorio especifico por ID:

```bash
curl http://localhost:3000/api/v1/reports/{reportId} | python3 -m json.tool
```

---

## 1.7 Testar com Arquivo PDF

O sistema tambem aceita arquivos PDF contendo diagramas de arquitetura:

```bash
curl -X POST http://localhost:3000/api/v1/analyses \
  -F "file=@/caminho/para/architecture.pdf" | python3 -m json.tool
```

O fluxo e identico ao de imagens. O Processing Service converte o PDF para imagem antes de enviar para a IA.

---

## 1.8 Verificar Logs

Os logs sao essenciais para debugar problemas e entender o que esta acontecendo internamente.

### Se voce subiu tudo com Docker (Opcao B da secao 1.4):

```bash
cd ~/fiap-hackaton/hackaton-infra

# Logs de TODOS os servicos (em tempo real)
make logs

# Pressione Ctrl+C para sair (os servicos continuam rodando)
```

Para ver logs de um servico especifico:

```bash
# Logs do Processing Service (onde a IA roda)
docker compose -f docker-compose.yml -f docker-compose.services.yml logs -f processing-service

# Logs do Upload Service
docker compose -f docker-compose.yml -f docker-compose.services.yml logs -f upload-service

# Logs do Report Service
docker compose -f docker-compose.yml -f docker-compose.services.yml logs -f report-service

# Logs do API Gateway
docker compose -f docker-compose.yml -f docker-compose.services.yml logs -f api-gateway

# Logs do RabbitMQ
docker compose logs -f rabbitmq
```

### Se voce subiu os servicos localmente (Opcao A):

Os logs aparecem diretamente no terminal de cada servico.

### O que procurar nos logs:

**Fluxo normal de uma analise bem-sucedida:**

1. **API Gateway**: `Proxying POST /api/v1/analyses to upload-service`
2. **Upload Service**: `File uploaded to S3: diagrams/uuid/diagram.png`
3. **Upload Service**: `Analysis created: {id}` e `Publishing event: analysis.requested`
4. **Processing Service**: `Consuming event: analysis.requested for analysis {id}`
5. **Processing Service**: `Downloading file from S3...`
6. **Processing Service**: `Sending to LLM provider: ollama/anthropic/openai`
7. **Processing Service**: `LLM response received. Processing time: XXXms`
8. **Processing Service**: `Output validation passed. Confidence: 0.85`
9. **Processing Service**: `Publishing event: analysis.processed`
10. **Report Service**: `Consuming event: analysis.processed for analysis {id}`
11. **Report Service**: `Report generated: {reportId}`
12. **Report Service**: `Publishing event: report.generated`
13. **Upload Service**: `Analysis {id} status updated to ANALYZED`

**Correlation ID:** Cada requisicao tem um `correlationId` (UUID) que aparece em todos os logs de todos os servicos. Use-o para rastrear o fluxo completo de uma analise:

```bash
# Procurar logs de uma analise especifica pelo correlation ID
docker compose -f docker-compose.yml -f docker-compose.services.yml logs | grep "CORRELATION_ID_AQUI"
```

---

## 1.9 Acessar UIs de Administracao

Alem da API, o sistema expoe interfaces web para administracao:

### RabbitMQ Management UI

**URL:** http://localhost:15672
**Usuario:** `rabbit`
**Senha:** `rabbit`

O que voce pode ver:

- **Queues**: Filas de mensagens. Voce deve ver `analysis.requested`, `analysis.processed`, `analysis.failed`, `report.generated`
- **Connections**: Conexoes ativas (cada servico que consome/publica mensagens aparece aqui)
- **Messages**: Quantidade de mensagens pendentes em cada fila (se tudo estiver funcionando, devem estar zeradas)

### MinIO Console

**URL:** http://localhost:9001
**Usuario:** `minioadmin`
**Senha:** `minioadmin`

O que voce pode ver:

- **Buckets**: Deve ter um bucket chamado `diagrams`
- **Object Browser**: Dentro do bucket `diagrams`, voce vera os arquivos de diagramas enviados, organizados por ID da analise

### Swagger UI (Documentacao da API do Upload Service)

**URL:** http://localhost:3001/api/v1/docs

Interface interativa para testar a API do Upload Service diretamente no navegador. Voce pode enviar requisicoes sem usar curl.

---

## 1.10 Rodar Testes Unitarios

Cada servico tem sua propria suite de testes. Voce pode roda-los independentemente:

```bash
# Upload Service
cd ~/fiap-hackaton/hackaton-upload-service
npm install
npx prisma generate   # necessario para gerar os tipos do Prisma
npm test

# Processing Service
cd ~/fiap-hackaton/hackaton-processing-service
npm install
npm test

# Report Service
cd ~/fiap-hackaton/hackaton-report-service
npm install
npx prisma generate   # necessario para gerar os tipos do Prisma
npm test

# API Gateway
cd ~/fiap-hackaton/hackaton-api-gateway
npm install
npm test
```

Para ver a cobertura de testes:

```bash
npm test -- --coverage
```

---

## 1.11 Parar Tudo

### Parar servicos (mantendo os dados)

```bash
cd ~/fiap-hackaton/hackaton-infra

# Se usou Opcao B (tudo junto):
make down

# Se usou Opcao A (somente infraestrutura):
docker compose down
```

Os dados (bancos de dados, arquivos no MinIO) sao preservados em volumes Docker. Na proxima vez que voce subir os servicos, os dados estarao la.

### Parar e apagar TODOS os dados (reset completo)

```bash
cd ~/fiap-hackaton/hackaton-infra
make reset
```

Isso destroi todos os volumes Docker (apaga bancos de dados, arquivos, filas) e reinicia a infraestrutura limpa. Use quando quiser comecar do zero.

---

## 1.12 Troubleshooting (Resolucao de Problemas)

### "Cannot connect to the Docker daemon" ou "docker: command not found"

**Causa:** Docker Desktop nao esta rodando.
**Solucao:** Abra o Docker Desktop e espere ate ele mostrar "running" no icone da barra de tarefas/menu.

### "Port already in use" ou "address already in use"

**Causa:** Outra aplicacao esta usando a porta (3000, 3001, 5432, etc.).
**Solucao:**

```bash
# Descobrir o que esta usando a porta (exemplo: porta 3000)
lsof -i :3000

# Matar o processo (substitua PID pelo numero mostrado)
kill -9 PID

# OU: mudar a porta no docker-compose.yml ou na variavel PORT
```

### "Prisma migrate failed" ou erro de conexao com banco

**Causa:** O PostgreSQL ainda nao esta pronto ou a DATABASE_URL esta errada.
**Solucao:**

```bash
# Verificar se o PostgreSQL esta rodando
docker compose ps | grep postgres

# Esperar ate estar healthy
docker compose ps
# postgres-upload deve mostrar "Up (healthy)"

# Testar conexao diretamente
docker exec -it hackaton-infra-postgres-upload-1 psql -U upload_user -d upload_service -c "SELECT 1"
```

### "RabbitMQ connection refused" ou "ECONNREFUSED"

**Causa:** O RabbitMQ ainda nao terminou de iniciar (demora ~15-20 segundos).
**Solucao:**

```bash
# Esperar o RabbitMQ ficar healthy
docker compose ps | grep rabbitmq
# Deve mostrar "Up (healthy)"

# Se precisar reiniciar:
docker compose restart rabbitmq
```

### "LLM timeout" ou erro no Processing Service ao analisar

**Causa 1 (Ollama):** O Ollama nao esta rodando ou o modelo nao foi baixado.
**Solucao:**

```bash
# Verificar se o Ollama esta rodando
curl http://localhost:11434/api/tags
# Se der erro: iniciar o Ollama
ollama serve &

# Verificar se o modelo esta instalado
ollama list
# Se llava nao estiver na lista:
ollama pull llava
```

**Causa 2 (Claude/OpenAI):** A API key esta invalida ou sem creditos.
**Solucao:** Verifique o `.env` e confirme que a chave esta correta e sua conta tem creditos.

### "File type not allowed"

**Causa:** Voce enviou um arquivo que nao e PNG, JPG, JPEG ou PDF.
**Solucao:** Converta seu arquivo para um dos formatos aceitos.

### "File too large" (413 Payload Too Large)

**Causa:** O arquivo excede o limite de 10MB.
**Solucao:** Reduza o tamanho da imagem/PDF. Para imagens, voce pode comprimir online em sites como https://tinypng.com/.

### "MinIO bucket not found" ou erro ao fazer upload

**Causa:** O container `minio-init` nao conseguiu criar o bucket `diagrams`.
**Solucao:**

```bash
# Reset completo
cd ~/fiap-hackaton/hackaton-infra
make reset
```

### "ImagePullBackOff" ou "Error pulling image" no Docker

**Causa:** Problema de rede ou imagem Docker nao existe.
**Solucao:**

```bash
# Tentar baixar a imagem manualmente
docker pull postgres:15-alpine
docker pull rabbitmq:3-management-alpine
docker pull minio/minio
docker pull amazon/dynamodb-local:latest
```

### Os servicos iniciam mas a analise fica presa em "PROCESSING"

**Causa possivel:** A mensagem na fila nao esta sendo consumida pelo Processing Service.
**Solucao:**

1. Acesse o RabbitMQ em http://localhost:15672 (rabbit/rabbit)
2. Va em "Queues" e verifique se ha mensagens acumuladas em `analysis.requested`
3. Verifique os logs do Processing Service para ver se ele esta conectado ao RabbitMQ

```bash
docker compose -f docker-compose.yml -f docker-compose.services.yml logs processing-service | tail -50
```

### Preciso recomecar tudo do zero

```bash
cd ~/fiap-hackaton/hackaton-infra

# Parar tudo e destruir volumes
make reset

# Se quiser limpar TUDO do Docker (imagens, containers parados, volumes orfaos):
docker system prune -a --volumes
# CUIDADO: isso apaga TODAS as imagens Docker do seu computador, nao apenas deste projeto
```

---

# PARTE 2: DEPLOY NA AWS

---

## 2.1 Pre-requisitos AWS

### 2.1.1 Criar uma Conta AWS

**Se voce esta usando o AWS Academy da FIAP**, pule esta etapa e va direto para a secao 2.1.5.

1. Acesse https://aws.amazon.com/free/
2. Clique em "Create a Free Account"
3. Preencha:
   - Email (use um email que voce acessa)
   - Nome da conta AWS (ex: "hackaton-fiap")
4. Verifique seu email (AWS envia um codigo de verificacao)
5. Crie uma senha para o root user
6. Escolha "Personal" como tipo de conta
7. Preencha seus dados pessoais
8. **Informacoes de pagamento**: Voce precisa informar um cartao de credito/debito. A AWS NAO vai cobrar nada enquanto voce estiver dentro do Free Tier. O cartao e apenas para verificacao de identidade.
9. Verifique seu numero de telefone (SMS ou ligacao)
10. Selecione o plano **"Basic Support - Free"**
11. Aguarde a ativacao da conta (pode levar ate 24 horas, mas geralmente e instantaneo)

### 2.1.2 Instalar o AWS CLI

O AWS CLI e a ferramenta de linha de comando para interagir com a AWS.

**macOS:**

```bash
brew install awscli
```

**Linux:**

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf awscliv2.zip aws/
```

**Verificar:**

```bash
aws --version
# Deve mostrar: aws-cli/2.x.x
```

### 2.1.3 Criar um Usuario IAM (necessario para configurar o CLI)

O "root user" da AWS e como a conta de administrador do seu computador. Por seguranca, voce NAO deve usa-lo no dia a dia. Em vez disso, crie um usuario IAM:

1. Acesse https://console.aws.amazon.com/ e faca login com o root user
2. No campo de busca no topo, digite "IAM" e clique no servico
3. No menu lateral, clique em "Users"
4. Clique em "Create user"
5. **User name**: `hackaton-admin`
6. Clique em "Next"
7. **Set permissions**: Selecione "Attach policies directly"
8. Na lista de politicas, procure e marque **`AdministratorAccess`**
   (Para o escopo do hackaton, isso simplifica. Em producao real, voce usaria permissoes minimas.)
9. Clique em "Next" e depois em "Create user"
10. Clique no nome do usuario recem-criado (`hackaton-admin`)
11. Va na aba "Security credentials"
12. Em "Access keys", clique em "Create access key"
13. Selecione "Command Line Interface (CLI)"
14. Marque o checkbox de confirmacao e clique em "Next"
15. Clique em "Create access key"
16. **IMPORTANTE:** Copie o "Access key ID" e o "Secret access key" (ou clique em "Download .csv file"). Voce NAO vai conseguir ver o Secret access key novamente depois de fechar esta pagina!

### 2.1.4 Configurar o AWS CLI

```bash
aws configure
```

Quando perguntado:

```
AWS Access Key ID [None]: COLE_SEU_ACCESS_KEY_ID_AQUI
AWS Secret Access Key [None]: COLE_SEU_SECRET_ACCESS_KEY_AQUI
Default region name [None]: us-east-1
Default output format [None]: json
```

Verifique que funcionou:

```bash
aws sts get-caller-identity
```

Deve retornar algo como:

```json
{
  "UserId": "AIDA...",
  "Account": "123456789012",
  "Arn": "arn:aws:iam::123456789012:user/hackaton-admin"
}
```

### 2.1.5 Configurar AWS CLI (alternativa para AWS Academy)

Se voce esta usando o AWS Academy ao inves de uma conta propria:

1. Acesse o Learner Lab no AWS Academy
2. Clique em "Start Lab" e aguarde o indicador ficar verde
3. Clique em "AWS Details" (ao lado do botao "Start Lab")
4. Clique em "Show" ao lado de "AWS CLI"
5. Copie todo o bloco de credenciais exibido
6. Cole no arquivo `~/.aws/credentials`:

```bash
nano ~/.aws/credentials
```

Cole o conteudo (sera algo como):

```ini
[default]
aws_access_key_id=ASIA...
aws_secret_access_key=abc123...
aws_session_token=LONGO_TOKEN_AQUI...
```

Salve o arquivo.

**IMPORTANTE:** As credenciais do AWS Academy expiram a cada 4 horas. Quando expirarem, voce precisara repetir este processo (parar e reiniciar o lab, copiar novas credenciais).

### 2.1.6 Instalar o Terraform

O Terraform e a ferramenta de Infrastructure as Code (IaC) que usamos para provisionar recursos na AWS.

**macOS:**

```bash
brew install terraform
```

**Linux:**

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**Verificar:**

```bash
terraform --version
# Deve mostrar: Terraform v1.x.x
```

### 2.1.7 Instalar o kubectl

O kubectl e a ferramenta de linha de comando para interagir com clusters Kubernetes.

**macOS:**

```bash
brew install kubectl
```

**Linux:**

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Verificar:**

```bash
kubectl version --client
# Deve mostrar a versao do client
```

---

## 2.2 Provisionar Infraestrutura com Terraform

O Terraform cria todos os recursos necessarios na AWS de forma automatizada e reproduzivel.

### 2.2.1 Criar o Backend do Terraform

O Terraform precisa de um lugar para armazenar seu "estado" (registro de quais recursos ele criou). Usamos um bucket S3 e uma tabela DynamoDB:

```bash
# Obter seu Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Criar bucket S3 para o estado do Terraform
aws s3 mb s3://hackaton-tf-state-${ACCOUNT_ID} --region us-east-1

# Criar tabela DynamoDB para locks (evita modificacoes simultaneas)
aws dynamodb create-table \
  --table-name hackaton-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### 2.2.2 O que o Terraform vai criar

Ao executar `terraform apply`, os seguintes recursos serao provisionados na AWS:

| Recurso AWS                      | Tipo               | Free Tier?                  | Descricao                                              |
| -------------------------------- | ------------------ | --------------------------- | ------------------------------------------------------ |
| **VPC**                          | Rede               | Sim                         | Rede virtual privada com subnets publicas e privadas   |
| **EKS Cluster**                  | Kubernetes         | Sim (12 meses)              | Cluster Kubernetes gerenciado para rodar os containers |
| **EC2 Instances** (t3.micro)     | Compute            | Sim (750h/mes, 12 meses)    | Maquinas que rodam os containers dentro do EKS         |
| **RDS PostgreSQL** (db.t3.micro) | Database           | Sim (750h/mes, 12 meses)    | Bancos de dados para Upload Service e Report Service   |
| **DynamoDB Table**               | Database           | Sim (25GB permanente)       | Banco NoSQL para o Processing Service                  |
| **SQS Queues**                   | Messaging          | Sim (1M req/mes permanente) | Filas de mensagens (substitui o RabbitMQ)              |
| **EventBridge**                  | Events             | Sim                         | Roteamento de eventos entre servicos                   |
| **S3 Bucket**                    | Storage            | Sim (5GB, 12 meses)         | Armazenamento dos diagramas enviados                   |
| **ECR Repositories**             | Container Registry | Sim (500MB/mes, 12 meses)   | Repositorios para as imagens Docker dos servicos       |
| **Secrets Manager**              | Security           | $0.40/secret/mes            | Armazenamento seguro de chaves e senhas                |

### 2.2.3 Executar o Terraform

```bash
cd ~/fiap-hackaton/hackaton-infra/terraform

# Inicializar o Terraform (baixa providers e configura backend)
terraform init

# Ver o plano (quais recursos serao criados - NAO cria nada ainda)
terraform plan

# Aplicar (criar os recursos - CONFIRME digitando "yes")
terraform apply
```

**Se voce esta usando AWS Academy, use a flag `use_lab_role`:**

```bash
terraform plan -var="use_lab_role=true"
terraform apply -var="use_lab_role=true"
```

A diferenca entre Free Tier e Academy:

| Aspecto       | Free Tier (`use_lab_role=false`)         | Academy (`use_lab_role=true`) |
| ------------- | ---------------------------------------- | ----------------------------- |
| IAM Roles     | Cria roles customizadas por servico      | Usa a LabRole pre-existente   |
| OIDC/IRSA     | Configura para associar roles a pods K8s | Nao suportado                 |
| Session Token | Nao expira (credenciais permanentes)     | Expira a cada 4 horas         |
| Limites       | Free Tier AWS (12 meses para a maioria)  | Creditos do Academy           |

O Terraform vai levar 15-25 minutos para criar tudo (o EKS cluster e o que demora mais). Aguarde ate ver:

```
Apply complete! Resources: XX added, 0 changed, 0 destroyed.

Outputs:

cluster_name = "hackaton-cluster"
cluster_endpoint = "https://XXXXXXXX.gr7.us-east-1.eks.amazonaws.com"
ecr_repositories = {
  "api-gateway" = "123456789012.dkr.ecr.us-east-1.amazonaws.com/hackaton-api-gateway"
  ...
}
```

### 2.2.4 Configurar kubectl para o cluster EKS

```bash
aws eks update-kubeconfig --name hackaton-cluster --region us-east-1
```

Verifique que funciona:

```bash
kubectl get nodes
```

Deve mostrar os nodes do cluster com status "Ready":

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-1-123.ec2.internal   Ready    <none>   5m    v1.28.x
ip-10-0-2-456.ec2.internal   Ready    <none>   5m    v1.28.x
```

---

## 2.3 Configurar Secrets na AWS

Antes de fazer deploy dos servicos, configure as chaves secretas no AWS Secrets Manager.

### Via AWS Console (interface web)

1. Acesse https://console.aws.amazon.com/secretsmanager/
2. Clique em "Store a new secret"
3. Tipo: "Other type of secret"
4. Adicione os pares chave-valor:

**Secret 1: `hackaton/development/app/env`**

| Chave               | Valor                     | Descricao                              |
| ------------------- | ------------------------- | -------------------------------------- |
| `LLM_PROVIDER`      | `anthropic` (ou `openai`) | Provedor de IA                         |
| `ANTHROPIC_API_KEY` | `sk-ant-...`              | Chave API Anthropic (se usando Claude) |
| `OPENAI_API_KEY`    | `sk-...`                  | Chave API OpenAI (se usando GPT-4)     |

5. Nome do secret: `hackaton/development/app/env`
6. Clique em "Next" ate o final e "Store"

### Via AWS CLI

```bash
aws secretsmanager create-secret \
  --name "hackaton/development/app/env" \
  --secret-string '{"LLM_PROVIDER":"anthropic","ANTHROPIC_API_KEY":"sk-ant-SUA-CHAVE","OPENAI_API_KEY":""}' \
  --region us-east-1
```

---

## 2.4 Build e Push das Imagens Docker

Os servicos precisam ser empacotados como imagens Docker e enviados para o ECR (Elastic Container Registry) da AWS.

### 2.4.1 Login no ECR

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
```

Deve mostrar: `Login Succeeded`

### 2.4.2 Build e Push de cada servico

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
ECR_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# API Gateway
cd ~/fiap-hackaton/hackaton-api-gateway
docker build --platform linux/amd64 -t hackaton-api-gateway .
docker tag hackaton-api-gateway:latest ${ECR_BASE}/hackaton-api-gateway:latest
docker push ${ECR_BASE}/hackaton-api-gateway:latest
echo "API Gateway pushed!"

# Upload Service
cd ~/fiap-hackaton/hackaton-upload-service
docker build --platform linux/amd64 -t hackaton-upload-service .
docker tag hackaton-upload-service:latest ${ECR_BASE}/hackaton-upload-service:latest
docker push ${ECR_BASE}/hackaton-upload-service:latest
echo "Upload Service pushed!"

# Processing Service
cd ~/fiap-hackaton/hackaton-processing-service
docker build --platform linux/amd64 -t hackaton-processing-service .
docker tag hackaton-processing-service:latest ${ECR_BASE}/hackaton-processing-service:latest
docker push ${ECR_BASE}/hackaton-processing-service:latest
echo "Processing Service pushed!"

# Report Service
cd ~/fiap-hackaton/hackaton-report-service
docker build --platform linux/amd64 -t hackaton-report-service .
docker tag hackaton-report-service:latest ${ECR_BASE}/hackaton-report-service:latest
docker push ${ECR_BASE}/hackaton-report-service:latest
echo "Report Service pushed!"
```

**NOTA sobre `--platform linux/amd64`:** Se voce esta em um Mac com chip Apple Silicon (M1/M2/M3/M4), esta flag e obrigatoria. Os nodes EKS usam arquitetura AMD64. Sem esta flag, a imagem sera ARM64 e nao funcionara no EKS.

### 2.4.3 Verificar que as imagens foram enviadas

```bash
for repo in hackaton-api-gateway hackaton-upload-service hackaton-processing-service hackaton-report-service; do
  echo "=== $repo ==="
  aws ecr list-images --repository-name $repo --region us-east-1 --query 'imageIds[*].imageTag' --output text
done
```

Deve mostrar "latest" para cada repositorio.

---

## 2.5 Deploy no Kubernetes (EKS)

### 2.5.1 Aplicar os manifests Kubernetes

```bash
cd ~/fiap-hackaton/hackaton-infra

# Aplicar os manifests usando Kustomize
kubectl apply -k k8s/overlays/development/
```

### 2.5.2 Verificar o deploy

```bash
# Ver os pods (containers rodando no cluster)
kubectl get pods -n hackaton

# Acompanhar em tempo real ate todos estarem "Running"
kubectl get pods -n hackaton -w
```

Todos os pods devem estar com STATUS "Running" e READY "1/1":

```
NAME                                    READY   STATUS    RESTARTS   AGE
api-gateway-abc123-xyz                  1/1     Running   0          2m
upload-service-def456-uvw               1/1     Running   0          2m
processing-service-ghi789-rst           1/1     Running   0          2m
report-service-jkl012-opq               1/1     Running   0          2m
```

### 2.5.3 Obter a URL publica

```bash
# Ver o Ingress (onde o ALB URL esta)
kubectl get ingress -n hackaton
```

A coluna "ADDRESS" mostra o endereco do Application Load Balancer:

```
NAME          CLASS   HOSTS   ADDRESS                                                               PORTS
api-gateway   alb     *       k8s-hackaton-abc123-1234567890.us-east-1.elb.amazonaws.com            80
```

Copie o endereco da coluna ADDRESS. Este e o ponto de entrada do sistema na AWS.

**NOTA:** O ALB pode levar 3-5 minutos para ficar disponivel apos a criacao.

---

## 2.6 Testar na AWS

Os comandos sao identicos aos testes locais (secao 1.6), mas substituindo `http://localhost:3000` pela URL do ALB.

```bash
# Defina a variavel com a URL do ALB
ALB_URL="http://k8s-hackaton-abc123-1234567890.us-east-1.elb.amazonaws.com"

# Health check
curl ${ALB_URL}/api/v1/health | python3 -m json.tool

# Upload de diagrama
curl -X POST ${ALB_URL}/api/v1/analyses \
  -F "file=@/caminho/para/diagram.png" | python3 -m json.tool

# Consultar status (substitua {id})
curl ${ALB_URL}/api/v1/analyses/{id} | python3 -m json.tool

# Consultar relatorio
curl ${ALB_URL}/api/v1/analyses/{id}/report | python3 -m json.tool

# Listar analises
curl "${ALB_URL}/api/v1/analyses?page=1&limit=10" | python3 -m json.tool

# Listar relatorios
curl "${ALB_URL}/api/v1/reports?page=1&limit=10" | python3 -m json.tool
```

---

## 2.7 Monitorar na AWS

### Ver logs dos pods

```bash
# Logs de um pod especifico
kubectl logs -n hackaton deployment/api-gateway
kubectl logs -n hackaton deployment/upload-service
kubectl logs -n hackaton deployment/processing-service
kubectl logs -n hackaton deployment/report-service

# Logs em tempo real (follow)
kubectl logs -n hackaton deployment/processing-service -f

# Logs das ultimas 100 linhas
kubectl logs -n hackaton deployment/processing-service --tail=100
```

### Ver status dos servicos

```bash
# Pods
kubectl get pods -n hackaton

# Services
kubectl get svc -n hackaton

# Deployments
kubectl get deployments -n hackaton

# Ver detalhes de um pod com problema
kubectl describe pod -n hackaton <nome-do-pod>
```

---

## 2.8 Gestao de Custos

### Limites do Free Tier para ficar atento

| Servico           | Limite Free Tier                        | O que acontece se exceder |
| ----------------- | --------------------------------------- | ------------------------- |
| EC2 (t3.micro)    | 750 horas/mes (12 meses)                | ~$0.0104/hora             |
| RDS (db.t3.micro) | 750 horas/mes (12 meses)                | ~$0.017/hora              |
| S3                | 5GB storage, 20k GET, 2k PUT (12 meses) | ~$0.023/GB                |
| DynamoDB          | 25GB, 25 WCU, 25 RCU (permanente)       | ~$1.25/1M writes          |
| EKS               | Control plane gratis (12 meses)         | $0.10/hora                |
| SQS               | 1M requests/mes (permanente)            | $0.40/1M requests         |

### Verificar custos atuais

1. Acesse https://console.aws.amazon.com/billing/
2. Clique em "Bills" no menu lateral
3. Veja o detalhamento por servico

### IMPORTANTE: Destruir tudo quando terminar

Para evitar custos inesperados, destrua todos os recursos quando nao precisar mais:

```bash
# Remover deployments do Kubernetes primeiro
kubectl delete -k ~/fiap-hackaton/hackaton-infra/k8s/overlays/development/

# Destruir infraestrutura AWS com Terraform
cd ~/fiap-hackaton/hackaton-infra/terraform
terraform destroy
# OU, para AWS Academy:
terraform destroy -var="use_lab_role=true"

# Confirme digitando "yes"
```

Tambem limpe o backend do Terraform:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Esvaziar e deletar o bucket S3
aws s3 rm s3://hackaton-tf-state-${ACCOUNT_ID} --recursive
aws s3 rb s3://hackaton-tf-state-${ACCOUNT_ID}

# Deletar a tabela DynamoDB de locks
aws dynamodb delete-table --table-name hackaton-terraform-locks --region us-east-1
```

---

## 2.9 Troubleshooting AWS

### "AccessDenied" ou "is not authorized to perform"

**Causa:** O usuario IAM nao tem permissao para a acao.
**Solucao:** Verifique que o usuario tem a policy `AdministratorAccess` anexada (secao 2.1.3). Se estiver usando Academy, verifique que o lab esta ativo (indicador verde).

### "The security token included in the request is expired"

**Causa:** Credenciais do AWS Academy expiraram (duram 4 horas).
**Solucao:**

1. Va ao AWS Academy -> Learner Lab
2. Clique em "Start Lab" (ou "Stop Lab" e depois "Start Lab" se ja estiver rodando)
3. Aguarde o indicador ficar verde
4. Copie as novas credenciais de "AWS Details"
5. Atualize `~/.aws/credentials`

### "ImagePullBackOff" no Kubernetes

**Causa:** O pod nao consegue baixar a imagem Docker do ECR.
**Solucao:**

```bash
# Verificar se a imagem existe no ECR
aws ecr list-images --repository-name hackaton-api-gateway --region us-east-1

# Se a imagem nao existe, faca build e push novamente (secao 2.4)

# Verificar detalhes do erro
kubectl describe pod -n hackaton <nome-do-pod-com-erro>
```

### "CrashLoopBackOff" no Kubernetes

**Causa:** O container esta iniciando e falhando repetidamente.
**Solucao:**

```bash
# Ver os logs do pod para entender o erro
kubectl logs -n hackaton <nome-do-pod> --previous

# Causas comuns:
# - DATABASE_URL incorreta (RDS endpoint errado)
# - Secret nao encontrado (Secrets Manager)
# - Porta ja em uso
```

### "ALB not creating" ou Ingress sem ADDRESS

**Causa:** O AWS Load Balancer Controller nao esta instalado ou configurado.
**Solucao:**

```bash
# Verificar se o controller esta rodando
kubectl get pods -n kube-system | grep aws-load-balancer

# Se nao estiver, o Terraform deveria ter instalado. Verifique:
terraform output
```

### "Database connection refused" no Kubernetes

**Causa:** Os pods nao conseguem acessar o RDS.
**Solucao:**

```bash
# Verificar o Security Group do RDS (deve permitir trafego dos nodes EKS)
# No console AWS: RDS -> Databases -> hackaton-db -> Connectivity & security -> Security Groups

# Verificar se o pod consegue resolver o DNS do RDS
kubectl exec -n hackaton <pod-name> -- nslookup <rds-endpoint>
```

### Erro generico: como debugar

```bash
# 1. Ver status de todos os recursos
kubectl get all -n hackaton

# 2. Descrever um recurso com problema
kubectl describe pod -n hackaton <nome-do-pod>
kubectl describe svc -n hackaton <nome-do-servico>

# 3. Executar um shell dentro de um pod (para testes de rede)
kubectl exec -it -n hackaton <nome-do-pod> -- /bin/sh

# 4. Ver eventos recentes do namespace
kubectl get events -n hackaton --sort-by='.metadata.creationTimestamp'
```

---

## Resumo dos Endpoints da API

Tabela de referencia rapida para todos os endpoints disponiveis:

| Metodo | Endpoint                      | Descricao                                | Exemplo                                                                 |
| ------ | ----------------------------- | ---------------------------------------- | ----------------------------------------------------------------------- |
| `GET`  | `/api/v1/health`              | Health check agregado                    | `curl http://localhost:3000/api/v1/health`                              |
| `POST` | `/api/v1/analyses`            | Upload de diagrama (multipart/form-data) | `curl -X POST -F "file=@img.png" http://localhost:3000/api/v1/analyses` |
| `GET`  | `/api/v1/analyses`            | Listar analises (paginado)               | `curl "http://localhost:3000/api/v1/analyses?page=1&limit=10"`          |
| `GET`  | `/api/v1/analyses/:id`        | Consultar status de uma analise          | `curl http://localhost:3000/api/v1/analyses/{id}`                       |
| `GET`  | `/api/v1/analyses/:id/report` | Consultar relatorio de uma analise       | `curl http://localhost:3000/api/v1/analyses/{id}/report`                |
| `GET`  | `/api/v1/reports`             | Listar relatorios (paginado)             | `curl "http://localhost:3000/api/v1/reports?page=1&limit=10"`           |
| `GET`  | `/api/v1/reports/:id`         | Consultar relatorio por ID               | `curl http://localhost:3000/api/v1/reports/{id}`                        |
| `GET`  | `/api/v1/docs`                | Swagger UI (documentacao interativa)     | Abrir no navegador                                                      |

---

## Resumo dos Comandos Make

| Comando      | O que faz                                                           |
| ------------ | ------------------------------------------------------------------- |
| `make dev`   | Sobe somente infraestrutura (PostgreSQL, DynamoDB, RabbitMQ, MinIO) |
| `make up`    | Sobe infraestrutura + todos os 4 servicos da aplicacao              |
| `make down`  | Para tudo (mantendo dados)                                          |
| `make logs`  | Mostra logs de todos os containers em tempo real                    |
| `make build` | Reconstroi as imagens Docker dos servicos                           |
| `make reset` | Destroi tudo (volumes inclusos) e reinicia infraestrutura limpa     |
