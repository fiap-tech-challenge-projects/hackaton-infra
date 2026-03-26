# ADR-002: Stack Tecnologico

**Status:** Accepted
**Data:** 2026-03-26
**Contexto:** Hackaton FIAP Secure Systems - Analise de Diagramas com IA
**Relacionados:** [ADR-001](ADR-001-service-decomposition.md) (servicos), [ADR-004](ADR-004-ai-pipeline.md) (IA), [ADR-005](ADR-005-infrastructure.md) (infra)

---

## Contexto

Precisamos escolher tecnologias que:

1. Atendam os requisitos do hackaton (microsservicos, Clean Arch, testes, Docker, CI/CD)
2. Sejam consistentes com o projeto FIAP existente (ja entregue e funcional)
3. Permitam integracao com IA (LLM multimodal)
4. Sejam viaveis de implementar no prazo do hackaton

## Decisao

### Backend

| Tecnologia                   | Versao          | Uso                                                                    |
| ---------------------------- | --------------- | ---------------------------------------------------------------------- |
| **Node.js**                  | 20 LTS (Alpine) | Runtime para todos os servicos                                         |
| **NestJS**                   | 11.x            | Framework principal - DI, modulos, decorators                          |
| **TypeScript**               | 5.x             | Linguagem principal                                                    |
| **Prisma**                   | 6.x             | ORM para PostgreSQL (Upload + Report Service)                          |
| **@aws-sdk/client-dynamodb** | 3.x             | DynamoDB client (Processing Service)                                   |
| **@aws-sdk/util-dynamodb**   | 3.x             | marshall/unmarshall (mesmo padrao billing/execution-service existente) |
| **class-validator**          | 0.14.x          | Validacao de DTOs                                                      |
| **class-transformer**        | 0.5.x           | Transformacao de objetos                                               |
| **@nestjs/swagger**          | 8.x             | Documentacao OpenAPI automatica                                        |

### Bancos de Dados

| Banco          | Versao | Servico            | Justificativa                                                                                                                                                                          |
| -------------- | ------ | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **PostgreSQL** | 15     | Upload Service     | Dados estruturados, status, metadados. Ja usado no projeto existente (os-service)                                                                                                      |
| **PostgreSQL** | 15     | Report Service     | Relatorios estruturados, queries complexas, paginacao                                                                                                                                  |
| **DynamoDB**   | -      | Processing Service | Resultados de IA semi-estruturados. DocumentDB NAO funciona no AWS Academy/Free Tier. DynamoDB e PAY_PER_REQUEST, 25GB free. Mesmo padrao billing-service/execution-service existentes |

### Mensageria

| Tecnologia            | Ambiente               | Justificativa                                      |
| --------------------- | ---------------------- | -------------------------------------------------- |
| **RabbitMQ**          | Local (Docker Compose) | Simples de configurar, AMQP, suporte nativo NestJS |
| **SQS + EventBridge** | Cloud (AWS)            | Ja temos infra, consistente com projeto existente  |

**Por que RabbitMQ local em vez de SQS local?**

- RabbitMQ roda facilmente em Docker
- NestJS tem suporte nativo via `@nestjs/microservices`
- LocalStack para SQS adiciona complexidade desnecessaria no dev local
- Em cloud, migramos para SQS+EventBridge com minima mudanca (adapter pattern)

### Object Storage

| Tecnologia | Ambiente               | Justificativa                           |
| ---------- | ---------------------- | --------------------------------------- |
| **MinIO**  | Local (Docker Compose) | API compativel com S3, zero custo local |
| **S3**     | Cloud (AWS)            | Ja temos infra, integrado com IAM       |

### IA / LLM

| Tecnologia               | Uso                             | Justificativa                                                                           |
| ------------------------ | ------------------------------- | --------------------------------------------------------------------------------------- |
| **Anthropic Claude API** | Analise multimodal de diagramas | Melhor capacidade de visao para diagramas tecnicos, API simples, SDK TypeScript oficial |
| **@anthropic-ai/sdk**    | SDK oficial                     | TypeScript-first, tipagem completa                                                      |

**Por que Claude e nao OpenAI GPT-4V?**

- Claude tem excelente capacidade multimodal para diagramas tecnicos
- SDK TypeScript oficial bem mantido
- Pricing competitivo para o uso que faremos
- Estamos usando Claude Code no desenvolvimento, sinergia natural

### Infraestrutura

| Tecnologia           | Uso                | Justificativa                     |
| -------------------- | ------------------ | --------------------------------- |
| **Docker**           | Containerizacao    | Obrigatorio pelo hackaton         |
| **Docker Compose**   | Orquestracao local | Desenvolvimento e testes locais   |
| **Kubernetes (EKS)** | Orquestracao cloud | Ja temos cluster configurado      |
| **Terraform**        | IaC                | Consistente com projeto existente |
| **GitHub Actions**   | CI/CD              | Ja configurado na org             |

### Observabilidade

| Tecnologia  | Uso                 | Justificativa                                                          |
| ----------- | ------------------- | ---------------------------------------------------------------------- |
| **Winston** | Logging estruturado | JSON logs, niveis, contexto. Escolhido pela simplicidade e ecossistema |

### Testes

| Tecnologia    | Uso                      |
| ------------- | ------------------------ |
| **Jest**      | Unit + Integration tests |
| **Supertest** | E2E / HTTP tests         |
| **ts-jest**   | TypeScript support       |

## Consequencias

### Positivas

- Stack 100% consistente com projeto ja entregue e funcional
- Time-to-market rapido (reuso de patterns e boilerplate)
- TypeScript end-to-end garante type safety
- Ecossistema NestJS rico em modulos prontos

### Negativas

- Node.js single-threaded pode ser gargalo para processamento pesado de imagens (mitigado: processamento e delegado para LLM API)
- DynamoDB requer modelagem cuidadosa de chaves (mitigado: single-table design simples, apenas 1 tabela)

## Alternativas Consideradas

| Alternativa            | Motivo da rejeicao                                                                               |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| **MongoDB/DocumentDB** | NAO funciona no AWS Academy/Free Tier (FreeTierRestrictionError). db.t3.medium custa ~$50-70/mes |
| **Python/FastAPI**     | Quebraria consistencia com projeto existente                                                     |
| **Go**                 | Curva de aprendizado, sem necessidade de performance extrema                                     |
| **OpenAI GPT-4V**      | Claude tem melhor custo-beneficio para nosso caso                                                |
| **Redis/ElastiCache**  | NAO testado no AWS Academy, provavelmente nao funciona. Custo adicional desnecessario            |
| **Kafka**              | Overkill para o volume do MVP                                                                    |

## Estrategia AWS: Free Tier (primario) + Academy (fallback)

**Contexto:** Na ultima etapa do projeto FIAP, o acesso ao AWS Academy foi perdido e creditos
acabaram rapido. A estrategia agora e usar o **Free Tier como primeira opcao**. Se necessario,
migramos para o AWS Academy como fallback. A arquitetura DEVE funcionar nos dois.

### Principio: Local = Cloud

O ambiente local (Docker Compose) DEVE usar as mesmas tecnologias do cloud.
Se usa DynamoDB na AWS, usa DynamoDB Local no Docker Compose. Sem excecoes.

### Compatibilidade por Servico AWS

| Servico AWS                      | Free Tier                                  | Academy          | Notas                                      |
| -------------------------------- | ------------------------------------------ | ---------------- | ------------------------------------------ |
| **EKS**                          | Funciona (control plane gratis 12 meses)   | Funciona         | Nodes cobram EC2                           |
| **EC2 (t3.micro)**               | 750h/mes gratis (12 meses)                 | Funciona         | t3.micro no Free Tier, t3.small no Academy |
| **RDS PostgreSQL (db.t3.micro)** | 750h/mes gratis (12 meses)                 | Funciona         | Single-AZ                                  |
| **DynamoDB**                     | 25GB + 25 WCU + 25 RCU gratis (permanente) | Funciona         | PAY_PER_REQUEST                            |
| **S3**                           | 5GB gratis (12 meses)                      | Funciona         | Suficiente para diagramas                  |
| **SQS**                          | 1M requests/mes gratis (permanente)        | Funciona         | Standard queues                            |
| **EventBridge**                  | Free tier incluso                          | Funciona         | Custom event bus                           |
| **ECR**                          | 500MB/mes gratis (12 meses)                | Funciona         | Container images                           |
| **Lambda**                       | 1M requests/mes gratis (permanente)        | Funciona         | Auth handler                               |
| **Secrets Manager**              | $0.40/secret/mes                           | Funciona         | 3-4 secrets = ~$1.60/mes                   |
| **NAT Gateway**                  | $0.045/h (~$32/mes)                        | Funciona         | NAO e free tier - considerar alternativas  |
| **DocumentDB/MongoDB**           | **NAO FUNCIONA**                           | **NAO FUNCIONA** | FreeTierRestrictionError                   |
| **ElastiCache/Redis**            | **NAO TESTADO**                            | **NAO TESTADO**  | Provavelmente nao funciona no Free Tier    |

### Diferenca na Gestao de IAM

| Aspecto           | Free Tier                        | Academy                       |
| ----------------- | -------------------------------- | ----------------------------- |
| **IAM Roles**     | Criamos roles customizadas       | Somente LabRole pre-existente |
| **IRSA**          | Funciona (OIDC provider)         | NAO funciona (sem OIDC)       |
| **Policies**      | Criamos e anexamos               | Nao pode criar/anexar         |
| **Session Token** | Nao expira (credenciais normais) | Expira a cada 4h              |

### Solucao: Terraform com Flag `use_lab_role`

```hcl
variable "use_lab_role" {
  description = "Use LabRole (AWS Academy) instead of custom IAM roles"
  type        = bool
  default     = false  # Free Tier por padrao
}

# Free Tier: cria role customizada
resource "aws_iam_role" "eks_service_role" {
  count = var.use_lab_role ? 0 : 1
  name  = "${var.project_name}-eks-role"
  # ...
}

# Academy: usa LabRole existente
data "aws_iam_role" "lab_role" {
  count = var.use_lab_role ? 1 : 0
  name  = "LabRole"
}

# Referencia condicional
locals {
  eks_role_arn = var.use_lab_role ? data.aws_iam_role.lab_role[0].arn : aws_iam_role.eks_service_role[0].arn
}
```

Para trocar de Free Tier para Academy:

```bash
terraform apply -var="use_lab_role=true"
```
