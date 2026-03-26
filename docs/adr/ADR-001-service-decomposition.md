# ADR-001: Decomposicao em Microsservicos

**Status:** Accepted
**Data:** 2026-03-26
**Contexto:** Hackaton FIAP Secure Systems - Analise de Diagramas com IA
**Relacionados:** [ADR-002](ADR-002-tech-stack.md) (stack), [ADR-003](ADR-003-communication-patterns.md) (comunicacao), [ADR-005](ADR-005-infrastructure.md) (infra)

---

## Contexto

O PDF do hackaton exige:

- Arquitetura baseada em microsservicos
- Cada servico com responsabilidade clara
- Cada servico com banco de dados proprio
- Cada servico com testes automatizados
- Servicos minimos sugeridos: API Gateway/BFF, Upload e Orquestracao, Processamento, Relatorios

## Decisao

Decompomos o sistema em **4 servicos + 1 infra**:

### 1. API Gateway (`hackaton-api-gateway`)

**Responsabilidade:** Ponto unico de entrada para o sistema.

- Roteamento de requisicoes para servicos internos
- Validacao basica de entrada (tipo de arquivo, tamanho)
- Rate limiting (protecao contra abuso)
- Agregacao de health checks
- CORS e headers de seguranca

**Banco de dados:** Nenhum (stateless)

**Justificativa:** O PDF sugere "API Gateway ou BFF". Optamos por API Gateway puro para manter simplicidade e separacao clara. No NestJS, usamos HTTP proxy (`http-proxy-middleware` ou `@nestjs/axios`) para rotear requests para os servicos internos.

### 2. Upload Service (`hackaton-upload-service`)

**Responsabilidade:** Receber diagramas, gerenciar o ciclo de vida da analise.

- Receber upload de arquivos (multipart/form-data)
- Validar arquivo (tipo: PNG, JPG, JPEG, PDF; tamanho: max 10MB)
- Armazenar arquivo no Object Storage (MinIO/S3)
- Criar e gerenciar registro de Analysis (state machine)
- Publicar eventos para iniciar processamento
- Expor endpoints de consulta de status

**Banco de dados:** PostgreSQL (relacional - status, metadados da analise)

**Entidades principais:**

- `Analysis` (id, fileName, fileUrl, fileType, fileSize, status, createdAt, updatedAt)

**Justificativa:** Corresponde ao "Servico de Upload e Orquestracao" do PDF. Responsavel pelo ciclo de vida completo da analise, desde upload ate status final.

### 3. Processing Service (`hackaton-processing-service`)

**Responsabilidade:** Processar diagramas com IA e extrair informacoes.

- Consumir eventos de analise solicitada
- Baixar diagrama do Storage
- Executar pipeline de IA (pre-processamento, prompt, LLM, validacao)
- Aplicar guardrails de entrada e saida
- Persistir resultado da analise de IA
- Publicar eventos com resultado (sucesso ou falha)

**Banco de dados:** DynamoDB (PAY_PER_REQUEST, free tier eligible, semi-estruturado)

**Tabelas DynamoDB:**

- `hackaton-analysis-results-{env}` (hash: analysisId) - Armazena resultados da analise de IA com componentes, riscos, recomendacoes, resposta bruta do LLM e metadados de processamento

**Justificativa:** Corresponde ao "Servico de Processamento" + responsabilidades IADT. DynamoDB foi escolhido porque: (1) DocumentDB/MongoDB NAO funciona no AWS Academy/Free Tier (FreeTierRestrictionError), (2) DynamoDB PAY_PER_REQUEST e free tier eligible (25GB gratis), (3) mesmo padrao do execution-service e billing-service do projeto existente que migraram de DocumentDB para DynamoDB pelo mesmo motivo.

### 4. Report Service (`hackaton-report-service`)

**Responsabilidade:** Gerar, armazenar e servir relatorios tecnicos.

- Consumir eventos de analise processada
- Transformar dados brutos da IA em relatorio estruturado
- Persistir relatorio com formatacao
- Servir relatorios via API REST
- Listar relatorios com paginacao

**Banco de dados:** PostgreSQL (relacional - relatorios estruturados, consultas complexas)

**Entidades principais:**

- `Report` (id, analysisId, title, summary, components:Json, risks:Json, recommendations:Json, metadata:Json, createdAt)

Componentes, riscos e recomendacoes sao armazenados como colunas JSON (denormalizados).
Isso simplifica o schema e evita JOINs desnecessarios para o MVP, ja que esses dados
vem prontos do Processing Service e sao sempre lidos como um bloco unico.

**Justificativa:** Corresponde ao "Servico de Relatorios". PostgreSQL porque relatorios tem estrutura bem definida e precisamos de queries complexas (filtros, ordenacao, paginacao).

### 5. Infra (`hackaton-infra`)

**Responsabilidade:** Infraestrutura compartilhada.

- Docker Compose para desenvolvimento local
- Kubernetes manifests (Kustomize) para deploy cloud
- Terraform para provisionar recursos AWS
- Scripts de automacao
- GitHub Actions workflows

## Consequencias

### Positivas

- Cada servico pode escalar independentemente
- Falha em um servico nao derruba os outros
- Deploy independente por servico
- Banco de dados proprio garante isolamento
- Alinhado com os padroes ja funcionais do projeto FIAP

### Negativas

- Complexidade operacional maior que monolito
- Necessidade de mensageria para comunicacao
- Consistencia eventual entre servicos
- Mais repositorios para gerenciar

### Riscos

- Overhead de comunicacao entre servicos (mitigado por mensageria assincrona)
- Complexidade de debugging distribuido (mitigado por logs estruturados + correlation ID)
