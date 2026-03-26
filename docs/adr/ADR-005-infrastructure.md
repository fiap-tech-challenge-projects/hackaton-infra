# ADR-005: Infraestrutura e DevOps

**Status:** Accepted
**Data:** 2026-03-26
**Contexto:** Hackaton FIAP Secure Systems - Analise de Diagramas com IA
**Relacionados:** [ADR-001](ADR-001-service-decomposition.md) (servicos), [ADR-002](ADR-002-tech-stack.md) (stack), [ADR-003](ADR-003-communication-patterns.md) (mensageria)

---

## Contexto

O PDF exige:

- Docker
- Docker Compose ou Kubernetes
- Pipeline CI/CD (build, testes, deploy)

Temos infraestrutura AWS ja funcional do projeto anterior.

## Decisao

### Estrategia Dual: Local + Cloud

| Ambiente  | Stack                        | Uso                           |
| --------- | ---------------------------- | ----------------------------- |
| **Local** | Docker Compose               | Desenvolvimento, testes, demo |
| **Cloud** | Kubernetes (EKS) + Terraform | Deploy producao               |

### Docker Compose (Desenvolvimento Local)

```yaml
# docker-compose.yml (no repo hackaton-infra)
services:
  # === INFRASTRUCTURE ===
  postgres-upload:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: upload_service
      POSTGRES_USER: upload_user
      POSTGRES_PASSWORD: upload_pass
    ports: ["5432:5432"]
    volumes: ["postgres-upload-data:/var/lib/postgresql/data"]

  postgres-report:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: report_service
      POSTGRES_USER: report_user
      POSTGRES_PASSWORD: report_pass
    ports: ["5433:5432"]
    volumes: ["postgres-report-data:/var/lib/postgresql/data"]

  dynamodb-local:
    image: amazon/dynamodb-local:latest
    command: "-jar DynamoDBLocal.jar -sharedDb"
    ports: ["8000:8000"]
    volumes: ["dynamodb-data:/home/dynamodblocal/data"]

  dynamodb-init:
    image: amazon/aws-cli:latest
    depends_on: [dynamodb-local]
    environment:
      AWS_ACCESS_KEY_ID: local
      AWS_SECRET_ACCESS_KEY: local
      AWS_DEFAULT_REGION: us-east-1
    entrypoint: /bin/sh -c
    command: >
      "aws dynamodb create-table
        --table-name hackaton-analysis-results-development
        --attribute-definitions AttributeName=analysisId,AttributeType=S AttributeName=createdAt,AttributeType=S
        --key-schema AttributeName=analysisId,KeyType=HASH AttributeName=createdAt,KeyType=RANGE
        --billing-mode PAY_PER_REQUEST
        --endpoint-url http://dynamodb-local:8000 || true"

  rabbitmq:
    image: rabbitmq:3-management-alpine
    ports:
      - "5672:5672" # AMQP
      - "15672:15672" # Management UI
    environment:
      RABBITMQ_DEFAULT_USER: rabbit
      RABBITMQ_DEFAULT_PASS: rabbit

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000" # S3 API
      - "9001:9001" # Console
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    volumes: ["minio-data:/data"]

  # === APPLICATION SERVICES ===
  api-gateway:
    build: ../hackaton-api-gateway
    ports: ["3000:3000"]
    environment:
      UPLOAD_SERVICE_URL: http://upload-service:3001
      PROCESSING_SERVICE_URL: http://processing-service:3002
      REPORT_SERVICE_URL: http://report-service:3003
    depends_on: [upload-service, processing-service, report-service]

  upload-service:
    build: ../hackaton-upload-service
    ports: ["3001:3001"]
    environment:
      DATABASE_URL: postgresql://upload_user:upload_pass@postgres-upload:5432/upload_service
      RABBITMQ_URL: amqp://rabbit:rabbit@rabbitmq:5672
      S3_ENDPOINT: http://minio:9000
      S3_BUCKET: diagrams
      S3_ACCESS_KEY: minioadmin
      S3_SECRET_KEY: minioadmin
    depends_on: [postgres-upload, rabbitmq, minio]

  processing-service:
    build: ../hackaton-processing-service
    ports: ["3002:3002"]
    environment:
      DYNAMODB_ENDPOINT: http://dynamodb-local:8000
      DYNAMODB_TABLE_NAME: hackaton-analysis-results-development
      RABBITMQ_URL: amqp://rabbit:rabbit@rabbitmq:5672
      S3_ENDPOINT: http://minio:9000
      S3_BUCKET: diagrams
      S3_ACCESS_KEY: minioadmin
      S3_SECRET_KEY: minioadmin
      AWS_ACCESS_KEY_ID: local
      AWS_SECRET_ACCESS_KEY: local
      AWS_REGION: us-east-1
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    depends_on: [dynamodb-local, rabbitmq, minio]

  report-service:
    build: ../hackaton-report-service
    ports: ["3003:3003"]
    environment:
      DATABASE_URL: postgresql://report_user:report_pass@postgres-report:5432/report_service
      RABBITMQ_URL: amqp://rabbit:rabbit@rabbitmq:5672
    depends_on: [postgres-report, rabbitmq]

volumes:
  postgres-upload-data:
  postgres-report-data:
  dynamodb-data:
  minio-data:
```

### Dockerfile (Padrao para todos os servicos)

Mesmo padrao multi-stage do projeto existente (os-service).

**Servicos com Prisma** (Upload Service, Report Service):

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
COPY prisma/ ./prisma/
RUN npm ci
RUN npx prisma generate
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:20-alpine AS production
RUN apk add --no-cache dumb-init
WORKDIR /app
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
COPY --from=builder /app/package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
USER nodejs
EXPOSE 3001
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3001/api/v1/health || exit 1
CMD ["dumb-init", "--", "node", "dist/main.js"]
```

**Servicos sem Prisma** (API Gateway, Processing Service):

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Production
FROM node:20-alpine AS production
RUN apk add --no-cache dumb-init
WORKDIR /app
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
COPY --from=builder /app/package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/dist ./dist
USER nodejs
EXPOSE 3002
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3002/api/v1/health || exit 1
CMD ["dumb-init", "--", "node", "dist/main.js"]
```

**Portas por servico:** API Gateway=3000, Upload=3001, Processing=3002, Report=3003.
Cada Dockerfile ajusta o `EXPOSE` e `HEALTHCHECK` para sua porta.

### Kubernetes (Deploy Cloud)

Mesma estrutura Kustomize do projeto existente:

```
hackaton-infra/
├── k8s/
│   ├── base/
│   │   ├── namespace.yaml
│   │   ├── api-gateway/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── ingress.yaml
│   │   │   └── configmap.yaml
│   │   ├── upload-service/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── configmap.yaml
│   │   │   └── external-secret.yaml
│   │   ├── processing-service/
│   │   │   └── ...
│   │   └── report-service/
│   │       └── ...
│   └── overlays/
│       ├── development/
│       └── production/
```

### Terraform (AWS Resources)

```
hackaton-infra/
├── terraform/
│   ├── main.tf           # Provider, backend
│   ├── variables.tf      # Input variables
│   ├── outputs.tf        # Outputs
│   ├── ecr.tf            # ECR repos (4 services)
│   ├── rds.tf            # PostgreSQL (db.t3.micro - free tier)
│   ├── dynamodb.tf       # DynamoDB table (PAY_PER_REQUEST - free tier)
│   ├── sqs.tf            # SQS queues + DLQ
│   ├── eventbridge.tf    # Event bus + rules
│   ├── s3.tf             # Bucket para diagramas
│   ├── secrets.tf        # Secrets Manager
│   └── iam.tf            # IAM roles e policies
```

### CI/CD Pipeline (GitHub Actions)

**Workflow por servico** (em cada repo de servico):

```yaml
# .github/workflows/ci.yml
name: CI/CD
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm test -- --coverage
      - uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/

  build:
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t ${{ github.repository }}:${{ github.sha }} .

  deploy:
    needs: [build]
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2
      - name: Build and push
        run: |
          docker build -t $ECR_REGISTRY/$SERVICE_NAME:${{ github.sha }} .
          docker push $ECR_REGISTRY/$SERVICE_NAME:${{ github.sha }}
      - name: Deploy to EKS
        run: |
          aws eks update-kubeconfig --name fiap-tech-challenge-cluster
          kubectl set image deployment/$SERVICE_NAME $SERVICE_NAME=$ECR_REGISTRY/$SERVICE_NAME:${{ github.sha }} -n hackaton
```

## Principio: Local = Cloud

O ambiente local (Docker Compose) usa as **mesmas tecnologias** do cloud:

| Servico        | Local (Docker Compose) | Cloud (AWS)                  |
| -------------- | ---------------------- | ---------------------------- |
| PostgreSQL     | postgres:15-alpine     | RDS PostgreSQL (db.t3.micro) |
| DynamoDB       | amazon/dynamodb-local  | DynamoDB (PAY_PER_REQUEST)   |
| Message Broker | RabbitMQ               | SQS + EventBridge            |
| Object Storage | MinIO (S3-compatible)  | S3                           |

**Nota sobre mensageria:** RabbitMQ local vs SQS cloud e a unica diferenca.
Mitigado pelo adapter pattern (interface `IEventPublisher` com implementacoes
`RabbitMQPublisher` e `EventBridgePublisher`). A selecao e feita via env var.

## Estrategia IAM: Free Tier + Academy

O Terraform usa flag `use_lab_role` para alternar entre os dois ambientes:

- `use_lab_role=false` (default): Cria IAM roles customizadas, OIDC provider, IRSA. Funciona no Free Tier.
- `use_lab_role=true`: Usa LabRole pre-existente, sem OIDC. Funciona no Academy.

```bash
# Free Tier (padrao)
terraform apply

# Academy (fallback)
terraform apply -var="use_lab_role=true"
```

## Consequencias

### Positivas

- Desenvolvimento local simples (`docker compose up`)
- Deploy cloud funciona em Free Tier E Academy (flag toggle)
- Local usa mesmas tecnologias do cloud (DynamoDB Local, MinIO/S3)
- CI/CD automatizado por servico
- Mesmos patterns do projeto entregue

### Negativas

- RabbitMQ local vs SQS cloud (mitigado: adapter pattern na camada de mensageria)
- DynamoDB Local tem algumas diferencas de comportamento vs cloud (mitigado: testes E2E no cloud)
