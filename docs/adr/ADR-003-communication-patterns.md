# ADR-003: Padroes de Comunicacao

**Status:** Accepted
**Data:** 2026-03-26
**Contexto:** Hackaton FIAP Secure Systems - Analise de Diagramas com IA
**Relacionados:** [ADR-001](ADR-001-service-decomposition.md) (servicos), [ADR-005](ADR-005-infrastructure.md) (RabbitMQ/SQS)

---

## Contexto

O PDF exige:

- Comunicacao via REST
- Ao menos um fluxo assincrono (fila ou mensageria)
- Deve ficar claro como a IA e acionada e como falhas sao tratadas

## Decisao

### Comunicacao Sincrona (REST)

Usada para operacoes que requerem resposta imediata:

```
Cliente <--REST--> API Gateway <--REST--> Upload Service    (upload, status, listagem)
Cliente <--REST--> API Gateway <--REST--> Report Service    (consulta de relatorios)
```

**Padrao de API:**

- Versionamento: `/api/v1/...`
- Content-Type: `application/json` (respostas), `multipart/form-data` (upload)
- Codigos HTTP semanticos (201 Created, 202 Accepted, 404 Not Found, etc)
- Paginacao: `?page=1&limit=10`
- Erros padronizados: `{ error: string, message: string, statusCode: number }`

### Comunicacao Assincrona (Mensageria)

Usada para o fluxo principal de processamento (operacoes longas):

```
Upload Service --[analysis.requested]--> Processing Service
Processing Service --[analysis.processed]--> Report Service
Processing Service --[analysis.failed]--> Upload Service
Report Service --[report.generated]--> Upload Service
```

#### Eventos

**1. `analysis.requested`**

```json
{
  "eventType": "analysis.requested",
  "timestamp": "2026-03-26T10:00:00Z",
  "correlationId": "uuid-v4",
  "source": "upload-service",
  "version": "1.0",
  "payload": {
    "analysisId": "uuid",
    "fileName": "diagram.png",
    "fileUrl": "s3://diagrams/analyses/uuid/diagram.png",
    "fileType": "image/png",
    "fileSize": 1024000
  }
}
```

Nota: `fileUrl` e um S3 URI (nao presigned URL). O Processing Service usa o S3 SDK
para baixar o arquivo. Ja o `fileUrl` retornado na REST API (GET /analyses/:id) e uma
presigned HTTPS URL para acesso do cliente.

**2. `analysis.processed`**

```json
{
  "eventType": "analysis.processed",
  "timestamp": "2026-03-26T10:00:30Z",
  "correlationId": "uuid-v4",
  "source": "processing-service",
  "version": "1.0",
  "payload": {
    "analysisId": "uuid",
    "resultId": "uuid",
    "components": [],
    "risks": [],
    "recommendations": [],
    "summary": "Microservices architecture with 8 components...",
    "model": "claude-sonnet-4-20250514",
    "promptVersion": "v1",
    "confidence": 0.85,
    "processingTimeMs": 5200
  }
}
```

**3. `analysis.failed`**

```json
{
  "eventType": "analysis.failed",
  "timestamp": "2026-03-26T10:00:30Z",
  "correlationId": "uuid-v4",
  "source": "processing-service",
  "version": "1.0",
  "payload": {
    "analysisId": "uuid",
    "error": "LLM_RESPONSE_INVALID",
    "message": "LLM response failed schema validation after 3 retries",
    "retryCount": 3
  }
}
```

**4. `report.generated`**

```json
{
  "eventType": "report.generated",
  "timestamp": "2026-03-26T10:00:35Z",
  "correlationId": "uuid-v4",
  "source": "report-service",
  "version": "1.0",
  "payload": {
    "analysisId": "uuid",
    "reportId": "uuid"
  }
}
```

Ao receber `report.generated`, o Upload Service atualiza:

- `Analysis.status` -> `ANALYZED`
- `Analysis.reportId` -> `payload.reportId`

Ao receber `analysis.failed`, o Upload Service atualiza:

- `Analysis.status` -> `ERROR`
- `Analysis.errorMessage` -> `payload.message`

### Implementacao Local (RabbitMQ)

```typescript
// NestJS Microservice Transport
@Module({
  imports: [
    ClientsModule.register([{
      name: 'MESSAGING_SERVICE',
      transport: Transport.RMQ,
      options: {
        urls: [process.env.RABBITMQ_URL],
        queue: 'analysis_queue',
        queueOptions: { durable: true },
      },
    }]),
  ],
})
```

**Filas RabbitMQ:**

- `analysis.requested` - Upload -> Processing
- `analysis.processed` - Processing -> Report
- `analysis.failed` - Processing -> Upload (atualiza status para ERROR)
- `report.generated` - Report -> Upload (atualiza status para ANALYZED)

**Dead Letter Queue (DLQ):**

- `analysis.dlq` - Mensagens que falharam apos 3 tentativas
- Retencao: 14 dias
- Alerta via log quando mensagem vai para DLQ

### Implementacao Cloud (SQS + EventBridge)

Mesmo padrao do projeto existente:

- EventBridge custom event bus para roteamento
- SQS queues por servico
- DLQ por fila
- IAM policies por servico

### Correlation ID

Todas as mensagens e requests carregam um `correlationId` (UUID v4):

- Gerado no API Gateway quando chega a request
- Propagado em headers HTTP (`X-Correlation-ID`)
- Incluido em todos os eventos
- Logado em todas as operacoes
- Permite rastrear fluxo completo de uma analise

## Fluxo Completo com Correlation ID

```
1. Cliente POST /api/v1/analyses
   -> API Gateway gera correlationId: "abc-123"
   -> Header: X-Correlation-ID: abc-123

2. Upload Service recebe request
   -> Log: { correlationId: "abc-123", action: "analysis.created", analysisId: "xyz" }
   -> Publica evento: { correlationId: "abc-123", eventType: "analysis.requested" }

3. Processing Service consome evento
   -> Log: { correlationId: "abc-123", action: "processing.started" }
   -> Chama LLM API
   -> Log: { correlationId: "abc-123", action: "llm.response.received", durationMs: 5200 }
   -> Publica evento: { correlationId: "abc-123", eventType: "analysis.processed" }

4. Report Service consome evento
   -> Log: { correlationId: "abc-123", action: "report.generated", reportId: "def" }
   -> Publica evento: { correlationId: "abc-123", eventType: "report.generated" }

5. Upload Service consome evento
   -> Log: { correlationId: "abc-123", action: "status.updated", status: "ANALYZED" }
```

## Consequencias

### Positivas

- Desacoplamento total entre servicos
- Processamento assincrono (LLM pode demorar segundos)
- Retry automatico com DLQ
- Rastreabilidade completa via correlation ID

### Negativas

- Consistencia eventual (status pode demorar a atualizar)
- Complexidade de debugging (mitigado por correlation ID + logs estruturados)

### Tratamento de Falhas

| Cenario                    | Acao                                      |
| -------------------------- | ----------------------------------------- |
| LLM timeout                | Retry ate 3x com backoff exponencial      |
| LLM resposta invalida      | Retry com prompt ajustado, apos 3x -> DLQ |
| Servico offline            | Mensagem fica na fila ate servico voltar  |
| DLQ cheia                  | Alerta via log, intervencao manual        |
| Upload de arquivo invalido | Rejeicao sincrona (400 Bad Request)       |
