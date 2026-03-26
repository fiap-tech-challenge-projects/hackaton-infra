# Hackaton FIAP Secure Systems - Analise Automatizada de Diagramas com IA

Sistema de microsservicos que recebe diagramas de arquitetura de software (imagem ou PDF), processa-os com Inteligencia Artificial (LLM multimodal) e gera relatorios tecnicos estruturados contendo componentes identificados, riscos arquiteturais e recomendacoes de melhoria.

---

## Indice

1. [Descricao do Problema](#1-descricao-do-problema)
2. [Arquitetura Proposta](#2-arquitetura-proposta)
3. [Fluxo da Solucao](#3-fluxo-da-solucao)
4. [Servicos e Repositorios](#4-servicos-e-repositorios)
5. [Stack Tecnologico](#5-stack-tecnologico)
6. [Pipeline de IA](#6-pipeline-de-ia)
7. [Instrucoes de Execucao](#7-instrucoes-de-execucao)
8. [Variaveis de Ambiente](#8-variaveis-de-ambiente)
9. [Seguranca](#9-seguranca)
10. [Decisoes Arquiteturais (ADRs)](#10-decisoes-arquiteturais-adrs)
11. [Estrategia AWS](#11-estrategia-aws)
12. [Estrutura dos Repositorios](#12-estrutura-dos-repositorios)

---

## 1. Descricao do Problema

Empresas de tecnologia frequentemente possuem diagramas de arquitetura de software que sao revisados e analisados manualmente por engenheiros e arquitetos. Esse processo manual e demorado, sujeito a inconsistencias e depende fortemente da experiencia individual do revisor.

A **FIAP Secure Systems** deseja um **MVP (Minimum Viable Product)** que automatize essa analise utilizando Inteligencia Artificial. O sistema deve:

- Receber diagramas de arquitetura (PNG, JPG, PDF)
- Processar a imagem com IA para identificar componentes, riscos e melhorias
- Gerar relatorios tecnicos estruturados com os resultados da analise
- Funcionar de forma assincrona (o processamento com IA pode levar segundos)
- Ser construido com arquitetura de microsservicos, Clean Architecture e event-driven

---

## 2. Arquitetura Proposta

### Diagrama de Arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│                          CLIENTE (HTTP)                             │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               v
┌──────────────────────────────────────────────────────────────────────┐
│                        API GATEWAY (NestJS)                          │
│  - Roteamento para servicos internos                                 │
│  - Validacao de entrada (file type, file size)                       │
│  - Rate limiting                                                     │
│  - Health check aggregation                                          │
│  Port: 3000                                                          │
└──────┬────────────────────────────────────────────┬─────────────────┘
       │ REST                                        │ REST
       v                                             v
┌──────────────┐                          ┌────────────────────┐
│ UPLOAD       │                          │ REPORT             │
│ SERVICE      │                          │ SERVICE            │
│              │                          │                    │
│ - Upload de  │   ┌──────────────────┐   │ - Gerar relatorio  │
│   diagrama   │   │ PROCESSING       │   │ - Armazenar        │
│ - Armazenar  │   │ SERVICE          │   │ - Consultar        │
│   arquivo    │   │ (event-driven)   │   │ - Listar           │
│ - Criar      │   │                  │   │                    │
│   analise    │   │ - Analise com IA │   │                    │
│ - Status     │   │ - Guardrails     │   │                    │
│              │   │                  │   │                    │
│ DB: Postgres │   │ DB: DynamoDB     │   │ DB: PostgreSQL     │
│ Port: 3001   │   │ Port: 3002       │   │ Port: 3003         │
└──────┬───────┘   └────────┬─────────┘   └──────────┬─────────┘
       │                    │                         │
       │     ┌──────────────────────────────┐         │
       └────>│     MESSAGE BROKER           │<────────┘
             │   (RabbitMQ / SQS)           │
             │                              │
             │  Queues:                     │
             │  - analysis.requested        │
             │  - analysis.processed        │
             │  - analysis.failed           │
             │  - report.generated          │
             └──────────────────────────────┘
                          │
                          v
             ┌──────────────────────┐
             │   FILE STORAGE       │
             │   (S3 / MinIO)       │
             │                      │
             │  - Diagramas         │
             │  - Relatorios PDF    │
             └──────────────────────┘
```

### Tabela de Servicos

| Servico                | Responsabilidade                                                                             | Banco de Dados     | Porta |
| ---------------------- | -------------------------------------------------------------------------------------------- | ------------------ | ----- |
| **API Gateway**        | Roteamento, rate limiting, validacao de entrada, CORS, headers de seguranca                  | Nenhum (stateless) | 3000  |
| **Upload Service**     | Receber diagramas, armazenar em S3/MinIO, orquestrar analise, gerenciar status               | PostgreSQL 15      | 3001  |
| **Processing Service** | Processar diagrama com IA (LLM multimodal), aplicar guardrails, extrair componentes e riscos | DynamoDB           | 3002  |
| **Report Service**     | Gerar relatorios tecnicos estruturados, armazenar e servir via API                           | PostgreSQL 15      | 3003  |

### Principios Arquiteturais

- **Clean Architecture (DDD)**: Domain -> Application -> Infrastructure -> Interfaces. Cada servico segue a mesma organizacao interna com separacao clara de camadas.
- **Database per Service**: Cada servico tem seu proprio banco de dados, garantindo isolamento e independencia de deploy.
- **Event-Driven (Assincrono)**: Comunicacao entre servicos via mensageria (RabbitMQ local / SQS+EventBridge cloud). O fluxo principal de analise e totalmente assincrono.
- **12-Factor App**: Configuracao via environment variables, stateless, logs como streams.

---

## 3. Fluxo da Solucao

### Fluxo Passo a Passo

```
1. Cliente envia POST /api/v1/analyses (multipart/form-data com arquivo)

2. API Gateway valida entrada (tipo, tamanho) e roteia para Upload Service

3. Upload Service:
   a. Valida o arquivo (tipo: PNG, JPG, JPEG, PDF; tamanho max: 10MB)
   b. Armazena o arquivo no Storage (S3/MinIO)
   c. Cria registro de Analysis com status "RECEIVED"
   d. Atualiza status para "PROCESSING"
   e. Publica evento "analysis.requested" na fila
   f. Retorna 202 Accepted com analysisId e status "PROCESSING"

4. Processing Service consome evento "analysis.requested":
   a. Baixa o diagrama do Storage
   b. Executa pipeline de IA (5 etapas - ver secao 6)
   c. Persiste resultado da analise no DynamoDB
   d. Publica evento "analysis.processed" (sucesso) ou "analysis.failed" (erro)

5. Report Service consome evento "analysis.processed":
   a. Gera relatorio tecnico estruturado (resumo, componentes, riscos, recomendacoes)
   b. Persiste relatorio no PostgreSQL
   c. Publica evento "report.generated"

6. Upload Service consome evento "report.generated":
   a. Atualiza status da Analysis para "ANALYZED"

7. Cliente consulta GET /api/v1/analyses/:id -> status ANALYZED
8. Cliente consulta GET /api/v1/analyses/:id/report -> relatorio completo
```

### Maquina de Estados (Status da Analise)

```
                    ┌──────────┐
       Upload  ---->│ RECEIVED │
                    └────┬─────┘
                         │ evento: analysis.requested
                         v
                    ┌──────────────┐
                    │ PROCESSING   │
                    └──┬───────┬───┘
                       │       │
          sucesso      │       │  falha
                       v       v
              ┌──────────┐  ┌───────┐
              │ ANALYZED │  │ ERROR │
              └──────────┘  └───────┘
```

| Status       | Descricao                                                              |
| ------------ | ---------------------------------------------------------------------- |
| `RECEIVED`   | Arquivo recebido e armazenado. Transitorio (dura milissegundos).       |
| `PROCESSING` | Analise de IA em andamento. Pode levar 5-15 segundos.                  |
| `ANALYZED`   | Analise concluida com sucesso. Relatorio disponivel.                   |
| `ERROR`      | Falha no processamento apos 3 tentativas. Mensagem de erro disponivel. |

---

## 4. Servicos e Repositorios

| Repositorio                                                                                                  | Descricao                                                                        |
| ------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------- |
| [`hackaton-infra`](https://github.com/fiap-tech-challenge-projects/hackaton-infra)                           | Infraestrutura: Docker Compose, Makefile, Terraform, K8s manifests, documentacao |
| [`hackaton-api-gateway`](https://github.com/fiap-tech-challenge-projects/hackaton-api-gateway)               | API Gateway - Ponto unico de entrada, roteamento, rate limiting, seguranca       |
| [`hackaton-upload-service`](https://github.com/fiap-tech-challenge-projects/hackaton-upload-service)         | Servico de Upload e Orquestracao - Upload de diagramas, gerenciamento de status  |
| [`hackaton-processing-service`](https://github.com/fiap-tech-challenge-projects/hackaton-processing-service) | Servico de Processamento com IA - Pipeline de analise com LLM multimodal         |
| [`hackaton-report-service`](https://github.com/fiap-tech-challenge-projects/hackaton-report-service)         | Servico de Relatorios - Geracao e consulta de relatorios tecnicos                |

---

## 5. Stack Tecnologico

| Camada            | Tecnologia                                 | Versao | Justificativa                                   |
| ----------------- | ------------------------------------------ | ------ | ----------------------------------------------- |
| **Runtime**       | Node.js (Alpine)                           | 20 LTS | Consistencia com projeto FIAP existente         |
| **Framework**     | NestJS                                     | 11.x   | DI nativo, modular, TypeScript-first            |
| **Linguagem**     | TypeScript                                 | 5.x    | Type safety, DDD-friendly                       |
| **ORM**           | Prisma                                     | 6.x    | Upload + Report Service (PostgreSQL)            |
| **DB Relacional** | PostgreSQL                                 | 15     | Upload Service + Report Service                 |
| **DB NoSQL**      | DynamoDB                                   | -      | Processing Service (PAY_PER_REQUEST, free tier) |
| **Mensageria**    | RabbitMQ (local) / SQS+EventBridge (cloud) | 3.x    | Fluxo assincrono obrigatorio                    |
| **Storage**       | MinIO (local) / S3 (cloud)                 | -      | Armazenamento de diagramas                      |
| **IA/LLM**        | Claude (Anthropic) / OpenAI / Ollama       | -      | LLM agnostico via env var `LLM_PROVIDER`        |
| **Container**     | Docker + Docker Compose                    | -      | Obrigatorio pelo hackaton                       |
| **Orquestracao**  | Kubernetes (EKS)                           | -      | Deploy cloud                                    |
| **IaC**           | Terraform                                  | -      | Consistencia com projeto existente              |
| **CI/CD**         | GitHub Actions                             | -      | Ja configurado na org                           |
| **Testes**        | Jest + Supertest                           | -      | Unit, integration, E2E                          |
| **Logs**          | Winston                                    | -      | Logs estruturados (JSON)                        |

---

## 6. Pipeline de IA

O Processing Service implementa uma pipeline de 5 etapas que combina **todas as 4 abordagens** sugeridas pelo PDF: deteccao de componentes, classificacao de riscos, LLM com guardrails e prompt engineering com validacao.

### Visao Geral da Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    PIPELINE DE IA                            │
│                                                             │
│  1. PRE-PROCESSAMENTO                                       │
│     ├── Validar tipo de arquivo (PNG, JPG, PDF)             │
│     ├── Converter PDF para imagem (se necessario)           │
│     ├── Validar dimensoes e qualidade da imagem             │
│     └── Sanitizar metadados (remover EXIF, etc)             │
│                                                             │
│  2. PROMPT ENGINEERING                                      │
│     ├── Selecionar template de prompt baseado no tipo       │
│     ├── Montar prompt com instrucoes estruturadas           │
│     ├── Incluir restricoes de formato (JSON schema)         │
│     ├── Incluir few-shot examples                           │
│     └── Aplicar guardrails de entrada                       │
│                                                             │
│  3. CHAMADA LLM                                             │
│     ├── Enviar imagem + prompt via API multimodal           │
│     ├── Timeout: 60 segundos                                │
│     ├── Retry: 3x com backoff exponencial                   │
│     └── Temperature: 0 (maximo determinismo)                │
│                                                             │
│  4. VALIDACAO DE SAIDA (Guardrails)                         │
│     ├── Validar JSON schema da resposta                     │
│     ├── Verificar campos obrigatorios                       │
│     ├── Validar consistencia (componentes x riscos)         │
│     ├── Detectar alucinacoes (score de confianca)           │
│     └── Sanitizar output (remover dados sensiveis)          │
│                                                             │
│  5. POS-PROCESSAMENTO                                       │
│     ├── Classificar riscos por severidade (regras)          │
│     ├── Enriquecer com metadados (modelo, versao, tempo)    │
│     ├── Calcular score de confianca agregado                │
│     └── Persistir resultado                                 │
└─────────────────────────────────────────────────────────────┘
```

### LLM Agnostico

O sistema suporta multiplos provedores de LLM, selecionaveis via variavel de ambiente `LLM_PROVIDER`:

| Provider               | Variavel                 | Custo            | Uso                                        |
| ---------------------- | ------------------------ | ---------------- | ------------------------------------------ |
| **Ollama** (default)   | `LLM_PROVIDER=ollama`    | Gratuito (local) | Desenvolvimento local sem API key          |
| **Claude (Anthropic)** | `LLM_PROVIDER=anthropic` | ~$0.003/diagrama | Producao (melhor qualidade para diagramas) |
| **OpenAI**             | `LLM_PROVIDER=openai`    | ~$0.005/diagrama | Alternativa                                |

### Guardrails de IA

**Entrada:**

- Prompt template fixo e versionado (nao aceita input do usuario no prompt)
- Instrucoes explicitas de formato (JSON schema no prompt)
- Restricoes claras do que o LLM pode/nao pode fazer
- Casos de erro definidos no prompt (NOT_ARCHITECTURE_DIAGRAM, LOW_QUALITY_IMAGE)

**Saida:**

- Validacao de JSON schema estrito
- Verificacao de campos obrigatorios e tipos enum
- Validacao de consistencia (riscos referenciam componentes existentes)
- Deteccao de alucinacoes: limite de componentes (>50 = suspeito), descricoes genericas
- Score de confianca agregado por analise
- Sanitizacao de output (remover HTML/script)

**Pos-processamento com regras:**

- Classificacao de riscos por severidade usando regras de negocio (complementar ao LLM)
- Priorizacao de recomendacoes
- Enriquecimento com metadados (modelo usado, tempo de processamento, versao do prompt)

### Limitacoes Conhecidas

| Limitacao                                       | Impacto                     | Mitigacao                                 |
| ----------------------------------------------- | --------------------------- | ----------------------------------------- |
| LLM pode alucinar componentes                   | Falso positivo no relatorio | Validacao de saida + confidence score     |
| Diagramas complexos podem ser mal interpretados | Analise incompleta          | Guardrail que detecta baixa confianca     |
| Latencia (5-15s por analise)                    | UX                          | Processamento assincrono + status polling |
| Diagramas manuscritos ou de baixa qualidade     | Analise imprecisa           | Pre-processamento + erro gracioso         |
| Variabilidade entre chamadas                    | Resultados inconsistentes   | Temperature 0, prompt deterministico      |
| Prompt injection via texto no diagrama          | Seguranca                   | Prompt fixo, guardrails de saida          |

---

## 7. Instrucoes de Execucao

### Pre-requisitos

- Docker e Docker Compose instalados
- Git
- (Opcional) Para usar Ollama localmente: [Ollama](https://ollama.ai) instalado com modelo `llava` ou `llama3.2-vision`

### Clone dos Repositorios

```bash
# Clone todos os repos na mesma pasta
git clone https://github.com/fiap-tech-challenge-projects/hackaton-infra
git clone https://github.com/fiap-tech-challenge-projects/hackaton-upload-service
git clone https://github.com/fiap-tech-challenge-projects/hackaton-processing-service
git clone https://github.com/fiap-tech-challenge-projects/hackaton-report-service
git clone https://github.com/fiap-tech-challenge-projects/hackaton-api-gateway
```

A estrutura de pastas esperada:

```
fiap-hackaton/
├── hackaton-infra/                 # Este repositorio
├── hackaton-api-gateway/
├── hackaton-upload-service/
├── hackaton-processing-service/
└── hackaton-report-service/
```

### Opcao 1: Subir tudo com Docker Compose (recomendado)

```bash
cd hackaton-infra

# Subir infraestrutura + todos os servicos
make up

# Acompanhar logs
make logs
```

### Opcao 2: Infraestrutura apenas (para dev local com npm)

```bash
cd hackaton-infra

# Subir apenas infraestrutura (PostgreSQL, DynamoDB, RabbitMQ, MinIO)
make dev

# Em terminais separados, rodar cada servico:
cd ../hackaton-upload-service && npm run start:dev
cd ../hackaton-processing-service && npm run start:dev
cd ../hackaton-report-service && npm run start:dev
cd ../hackaton-api-gateway && npm run start:dev
```

### Testar o Fluxo

```bash
# 1. Enviar diagrama para analise
curl -X POST http://localhost:3000/api/v1/analyses \
  -F "file=@diagram.png"

# Resposta: { "id": "uuid", "status": "PROCESSING", ... }

# 2. Consultar status da analise
curl http://localhost:3000/api/v1/analyses/{id}

# Resposta: { "id": "uuid", "status": "ANALYZED", ... }

# 3. Consultar relatorio completo
curl http://localhost:3000/api/v1/analyses/{id}/report

# Resposta: { "id": "uuid", "summary": "...", "components": [...], "risks": [...], "recommendations": [...] }

# 4. Listar todas as analises
curl http://localhost:3000/api/v1/analyses
```

### Comandos Make Disponiveis

| Comando      | Descricao                                    |
| ------------ | -------------------------------------------- |
| `make up`    | Subir infraestrutura + servicos              |
| `make down`  | Parar tudo                                   |
| `make dev`   | Subir apenas infraestrutura (para dev local) |
| `make logs`  | Ver logs de todos os containers              |
| `make build` | Rebuildar imagens dos servicos               |
| `make reset` | Destruir volumes e reiniciar infraestrutura  |

### Portas e Interfaces

| Servico             | Porta | URL                                           |
| ------------------- | ----- | --------------------------------------------- |
| API Gateway         | 3000  | http://localhost:3000                         |
| Upload Service      | 3001  | http://localhost:3001                         |
| Processing Service  | 3002  | http://localhost:3002                         |
| Report Service      | 3003  | http://localhost:3003                         |
| RabbitMQ Management | 15672 | http://localhost:15672 (rabbit/rabbit)        |
| MinIO Console       | 9001  | http://localhost:9001 (minioadmin/minioadmin) |
| DynamoDB Local      | 8000  | http://localhost:8000                         |

---

## 8. Variaveis de Ambiente

### Processing Service (LLM)

| Variavel              | Descricao               | Default                                 | Opcoes                                 |
| --------------------- | ----------------------- | --------------------------------------- | -------------------------------------- |
| `LLM_PROVIDER`        | Provedor de LLM         | `ollama`                                | `ollama`, `anthropic`, `openai`        |
| `OLLAMA_BASE_URL`     | URL do Ollama           | `http://host.docker.internal:11434`     | -                                      |
| `ANTHROPIC_API_KEY`   | API key do Anthropic    | -                                       | Necessario se `LLM_PROVIDER=anthropic` |
| `OPENAI_API_KEY`      | API key da OpenAI       | -                                       | Necessario se `LLM_PROVIDER=openai`    |
| `DYNAMODB_ENDPOINT`   | Endpoint DynamoDB       | `http://dynamodb-local:8000`            | -                                      |
| `DYNAMODB_TABLE_NAME` | Nome da tabela DynamoDB | `hackaton-analysis-results-development` | -                                      |

### Upload Service

| Variavel              | Descricao                             | Default                                                                    |
| --------------------- | ------------------------------------- | -------------------------------------------------------------------------- |
| `DATABASE_URL`        | URL do PostgreSQL                     | `postgresql://upload_user:upload_pass@postgres-upload:5432/upload_service` |
| `RABBITMQ_URL`        | URL do RabbitMQ                       | `amqp://rabbit:rabbit@rabbitmq:5672`                                       |
| `S3_ENDPOINT`         | Endpoint do MinIO/S3                  | `http://minio:9000`                                                        |
| `S3_BUCKET`           | Nome do bucket                        | `diagrams`                                                                 |
| `S3_ACCESS_KEY`       | Access key MinIO/S3                   | `minioadmin`                                                               |
| `S3_SECRET_KEY`       | Secret key MinIO/S3                   | `minioadmin`                                                               |
| `S3_FORCE_PATH_STYLE` | Path style S3 (necessario para MinIO) | `true`                                                                     |

### Report Service

| Variavel       | Descricao         | Default                                                                    |
| -------------- | ----------------- | -------------------------------------------------------------------------- |
| `DATABASE_URL` | URL do PostgreSQL | `postgresql://report_user:report_pass@postgres-report:5432/report_service` |
| `RABBITMQ_URL` | URL do RabbitMQ   | `amqp://rabbit:rabbit@rabbitmq:5672`                                       |

### API Gateway

| Variavel                 | Descricao                 | Default                          |
| ------------------------ | ------------------------- | -------------------------------- |
| `UPLOAD_SERVICE_URL`     | URL do Upload Service     | `http://upload-service:3001`     |
| `PROCESSING_SERVICE_URL` | URL do Processing Service | `http://processing-service:3002` |
| `REPORT_SERVICE_URL`     | URL do Report Service     | `http://report-service:3003`     |

### Uso com Ollama (gratuito, sem API key)

Para desenvolvimento local sem custo:

```bash
# 1. Instalar Ollama (https://ollama.ai)
# 2. Baixar modelo com visao
ollama pull llava

# 3. Subir o sistema (LLM_PROVIDER=ollama e o default)
cd hackaton-infra
make up
```

### Uso com Claude (melhor qualidade)

```bash
# Exportar API key antes de subir
export ANTHROPIC_API_KEY=sk-ant-...
export LLM_PROVIDER=anthropic

cd hackaton-infra
make up
```

---

## 9. Seguranca

> **Secao obrigatoria conforme PDF do hackaton.**

### 9.1 Validacao de Entradas

**Upload de arquivos:**

- Validacao dupla: extensao do arquivo + magic bytes (nao confia no Content-Type do cliente)
- Tipos permitidos: PNG, JPG, JPEG, PDF
- Tamanho maximo: 10MB
- Nome do arquivo sanitizado (previne path traversal)
- `class-validator` em todos os DTOs com whitelist (`forbidNonWhitelisted: true`)
- UUIDs validados com regex
- Paginacao com limites (max 100 items por pagina)

### 9.2 Rate Limiting no API Gateway

- Rate limiting por IP usando `@nestjs/throttler`
- Upload: 10 requests/minuto por IP
- Consulta: 60 requests/minuto por IP
- Tamanho maximo de request body: 10MB

### 9.3 Headers de Seguranca

- **Helmet** middleware com todas as protecoes ativadas:
  - Content-Security-Policy
  - X-Content-Type-Options: nosniff
  - X-Frame-Options
  - Strict-Transport-Security (HSTS)
  - Hide X-Powered-By
  - Referrer-Policy
  - XSS Filter

### 9.4 Rastreabilidade (Correlation ID)

- Correlation ID (UUID v4) gerado no API Gateway para cada request
- Propagado em headers HTTP (`X-Correlation-ID`) e em todos os eventos de mensageria
- Logado em todas as operacoes de todos os servicos
- Permite rastrear o fluxo completo de uma analise de ponta a ponta

### 9.5 IA Controlada

| Medida                      | Descricao                                                                   |
| --------------------------- | --------------------------------------------------------------------------- |
| **Temperature 0**           | Maximo determinismo nas respostas do LLM                                    |
| **Prompt fixo**             | Template versionado, nao inclui dados do usuario (previne prompt injection) |
| **JSON schema no output**   | LLM obrigado a responder em formato estruturado                             |
| **Guardrails de saida**     | Validacao de schema, tipos, enums, referencias entre dados                  |
| **Deteccao de alucinacoes** | Heuristicas: limite de componentes, descricoes genericas                    |
| **Score de confianca**      | Calculado por analise, permite filtrar resultados de baixa qualidade        |
| **Sanitizacao**             | Output do LLM sanitizado (remove HTML/script)                               |

### 9.6 Tratamento de Falhas da IA

| Cenario                   | Acao                                          | Fallback     |
| ------------------------- | --------------------------------------------- | ------------ |
| LLM retorna JSON invalido | Retry ate 3x                                  | Status ERROR |
| LLM timeout (60s)         | Retry 3x com backoff exponencial (1s, 2s, 4s) | Status ERROR |
| LLM rate limited          | Retry com delay de 60s, max 2x                | Status ERROR |
| Output falha na validacao | Retry com prompt ajustado, max 2x             | Status ERROR |
| Imagem nao e diagrama     | Retorna erro especifico                       | Status ERROR |

- **Dead Letter Queue (DLQ)**: Mensagens que falharam apos todas as tentativas vao para `analysis.dlq` com retencao de 14 dias
- **Status ERROR**: Analise marcada com erro, mensagem de erro disponivel para o cliente
- **Logs de seguranca**: Todos os guardrails acionados sao logados com correlation ID

### 9.7 Comunicacao entre Servicos

**Ambiente Local (Docker Compose):**

- Servicos em rede Docker interna, nao expostos externamente
- Somente API Gateway expoe porta para o host (3000)
- Credenciais de servicos via environment variables

**Ambiente Cloud (Kubernetes):**

- Servicos comunicam via ClusterIP (rede interna K8s)
- Ingress expoe somente o API Gateway
- Network Policies para isolar namespaces
- Secrets via AWS Secrets Manager + External Secrets Operator
- IAM roles por servico (principle of least privilege)

### 9.8 Riscos e Limitacoes Identificados

| Risco                                  | Severidade | Mitigacao                                             | Status                |
| -------------------------------------- | ---------- | ----------------------------------------------------- | --------------------- |
| Prompt injection via texto no diagrama | Media      | Prompt fixo, output validado                          | Mitigado              |
| LLM alucina componentes inexistentes   | Media      | Guardrails de saida, confidence score                 | Mitigado parcialmente |
| Upload de arquivo malicioso            | Alta       | Validacao magic bytes, sandbox de processamento       | Mitigado              |
| DDoS via uploads grandes               | Alta       | Rate limiting, tamanho max 10MB                       | Mitigado              |
| Vazamento de API key                   | Critica    | Secrets Manager, env vars, nao commitado              | Mitigado              |
| Acesso nao autorizado a relatorios     | Media      | MVP sem auth, risco aceito                            | Aceito (MVP)          |
| Man-in-the-middle entre servicos       | Baixa      | Rede interna Docker/K8s                               | Mitigado              |
| Dados sensiveis em diagramas           | Media      | Diagrama nao armazenado apos processamento (opcional) | Mitigado parcialmente |

**Limitacoes aceitas para o MVP:**

1. **Sem autenticacao/autorizacao** - MVP nao requer login (risco aceito, escopo do hackaton)
2. **Sem HTTPS local** - Docker Compose nao configura TLS (cloud tem via ALB/Ingress)
3. **Sem auditoria completa** - Logs estruturados como substituto basico
4. **Sem WAF** - Somente rate limiting basico no API Gateway

---

## 10. Decisoes Arquiteturais (ADRs)

Todas as decisoes arquiteturais estao documentadas no formato ADR (Architecture Decision Record) em [`docs/adr/`](docs/adr/).

| ADR                                                   | Titulo                         | Resumo                                                                   |
| ----------------------------------------------------- | ------------------------------ | ------------------------------------------------------------------------ |
| [ADR-001](docs/adr/ADR-001-service-decomposition.md)  | Decomposicao em Microsservicos | 4 servicos + 1 infra, cada um com banco proprio e responsabilidade clara |
| [ADR-002](docs/adr/ADR-002-tech-stack.md)             | Stack Tecnologico              | NestJS 11, TypeScript 5, Prisma 6, PostgreSQL 15, DynamoDB, RabbitMQ     |
| [ADR-003](docs/adr/ADR-003-communication-patterns.md) | Padroes de Comunicacao         | REST sincrono + mensageria assincrona, correlation ID, DLQ               |
| [ADR-004](docs/adr/ADR-004-ai-pipeline.md)            | Pipeline de IA                 | LLM multimodal + prompt engineering + guardrails em 5 etapas             |
| [ADR-005](docs/adr/ADR-005-infrastructure.md)         | Infraestrutura e DevOps        | Docker Compose local, EKS cloud, Terraform, GitHub Actions CI/CD         |
| [ADR-006](docs/adr/ADR-006-security.md)               | Estrategia de Seguranca        | Validacao multi-camada, IA controlada, tratamento de falhas, DLQ         |

---

## 11. Estrategia AWS

### Dual Compatibility: Free Tier + Academy

**Primeira opcao:** AWS Free Tier (conta propria, IAM roles customizadas, sem expiracao de credenciais)
**Fallback:** AWS Academy (LabRole, session token 4h, creditos limitados)

A arquitetura funciona nos dois ambientes via flag Terraform `use_lab_role`:

```bash
# Free Tier (padrao)
terraform apply

# Academy (fallback)
terraform apply -var="use_lab_role=true"
```

| Flag                           | Ambiente  | IAM                       | OIDC/IRSA    |
| ------------------------------ | --------- | ------------------------- | ------------ |
| `use_lab_role=false` (default) | Free Tier | Cria roles customizadas   | Funciona     |
| `use_lab_role=true`            | Academy   | Usa LabRole pre-existente | Nao funciona |

### Servicos AWS Utilizados

| Servico            | Free Tier                         | Academy  | Uso                        |
| ------------------ | --------------------------------- | -------- | -------------------------- |
| **EKS**            | Control plane gratis 12 meses     | Funciona | Orquestracao de containers |
| **EC2 (t3.micro)** | 750h/mes gratis 12 meses          | Funciona | Worker nodes               |
| **RDS PostgreSQL** | 750h/mes gratis 12 meses          | Funciona | Upload + Report Service    |
| **DynamoDB**       | 25GB gratis permanente            | Funciona | Processing Service         |
| **SQS**            | 1M requests/mes gratis permanente | Funciona | Mensageria                 |
| **EventBridge**    | Free tier incluso                 | Funciona | Roteamento de eventos      |
| **S3**             | 5GB gratis 12 meses               | Funciona | Armazenamento de diagramas |
| **ECR**            | 500MB/mes gratis 12 meses         | Funciona | Container images           |

### Principio: Local = Cloud

O ambiente local (Docker Compose) usa as **mesmas tecnologias** do cloud:

| Servico        | Local                 | Cloud                        |
| -------------- | --------------------- | ---------------------------- |
| PostgreSQL     | postgres:15-alpine    | RDS PostgreSQL (db.t3.micro) |
| DynamoDB       | amazon/dynamodb-local | DynamoDB (PAY_PER_REQUEST)   |
| Message Broker | RabbitMQ              | SQS + EventBridge            |
| Object Storage | MinIO (S3-compatible) | S3                           |

---

## 12. Estrutura dos Repositorios

```
hackaton-infra/                         # Este repositorio
├── docker-compose.yml                  # Infraestrutura (PostgreSQL, DynamoDB, RabbitMQ, MinIO)
├── docker-compose.services.yml         # Servicos da aplicacao (Gateway, Upload, Processing, Report)
├── Makefile                            # Comandos utilitarios (make up, make dev, make logs...)
├── docs/
│   └── adr/                            # Architecture Decision Records
│       ├── ADR-001-service-decomposition.md
│       ├── ADR-002-tech-stack.md
│       ├── ADR-003-communication-patterns.md
│       ├── ADR-004-ai-pipeline.md
│       ├── ADR-005-infrastructure.md
│       └── ADR-006-security.md
├── terraform/                          # IaC para AWS
└── k8s/                                # Kubernetes manifests (Kustomize)

hackaton-api-gateway/                   # API Gateway (port 3000)
├── src/
│   ├── domain/                         # Clean Architecture - Domain layer
│   ├── application/                    # Clean Architecture - Application layer
│   ├── infrastructure/                 # Clean Architecture - Infrastructure layer
│   └── interfaces/                     # Clean Architecture - Interfaces layer
├── test/
├── Dockerfile
└── package.json

hackaton-upload-service/                # Upload + Orquestracao (port 3001)
├── src/                                # Mesma estrutura Clean Architecture
├── prisma/                             # Prisma schema (PostgreSQL)
├── test/
├── Dockerfile
└── package.json

hackaton-processing-service/            # Processamento com IA (port 3002)
├── src/                                # Mesma estrutura Clean Architecture
│   ├── domain/
│   │   └── services/
│   │       ├── llm.service.ts          # Chamada LLM (agnostico)
│   │       ├── prompt.service.ts       # Prompt engineering
│   │       └── output-validator.ts     # Guardrails de saida
│   └── ...
├── test/
├── Dockerfile
└── package.json

hackaton-report-service/                # Relatorios (port 3003)
├── src/                                # Mesma estrutura Clean Architecture
├── prisma/                             # Prisma schema (PostgreSQL)
├── test/
├── Dockerfile
└── package.json
```

---

## Autores

Grupo FIAP - Pos-Graduacao em Software Architecture
