# ADR-006: Estrategia de Seguranca

**Status:** Accepted
**Data:** 2026-03-26
**Contexto:** Hackaton FIAP Secure Systems - Analise de Diagramas com IA
**Relacionados:** [ADR-004](ADR-004-ai-pipeline.md) (guardrails IA), [ADR-003](ADR-003-communication-patterns.md) (comunicacao)

---

## Contexto

O PDF exige uma **secao obrigatoria de seguranca** cobrindo:

- Requisitos basicos de seguranca
- Validacao e tratamento de entradas nao confiaveis
- Uso controlado de modelos de IA
- Tratamento seguro de falhas da IA
- Seguranca na comunicacao entre servicos
- Identificacao de riscos e limitacoes

## Decisao

### 1. Validacao de Entradas

#### Upload de Arquivos

```typescript
// Validacoes no API Gateway + Upload Service
const FILE_CONSTRAINTS = {
  maxSize: 10 * 1024 * 1024, // 10MB
  allowedMimeTypes: [
    'image/png',
    'image/jpeg',
    'image/jpg',
    'application/pdf',
  ],
  allowedExtensions: ['.png', '.jpg', '.jpeg', '.pdf'],
  maxFileNameLength: 255,
};

// Validacao dupla: extensao + magic bytes
async validateFile(file: Express.Multer.File): Promise<void> {
  // 1. Extensao
  const ext = path.extname(file.originalname).toLowerCase();
  if (!FILE_CONSTRAINTS.allowedExtensions.includes(ext)) {
    throw new BadRequestException('File extension not allowed');
  }

  // 2. MIME type (magic bytes, nao confia no Content-Type do cliente)
  const fileType = await fileTypeFromBuffer(file.buffer);
  if (!fileType || !FILE_CONSTRAINTS.allowedMimeTypes.includes(fileType.mime)) {
    throw new BadRequestException('File type not allowed');
  }

  // 3. Tamanho
  if (file.size > FILE_CONSTRAINTS.maxSize) {
    throw new BadRequestException('File too large');
  }

  // 4. Nome (previne path traversal)
  const sanitizedName = this.sanitizeFileName(file.originalname);
  file.originalname = sanitizedName;
}
```

#### Inputs de API

- **class-validator** em todos os DTOs com whitelist
- **ValidationPipe** global com `transform: true, whitelist: true, forbidNonWhitelisted: true`
- UUIDs validados com regex
- Paginacao com limites (max 100 items por pagina)

### 2. Seguranca da IA

#### Guardrails de Entrada

- Prompt template fixo (nao aceita input do usuario no prompt)
- Arquivo processado como imagem binaria (nao como texto)
- Metadados EXIF removidos antes de enviar ao LLM
- Tamanho maximo de imagem validado

#### Guardrails de Saida

- Schema JSON estrito para output do LLM
- Validacao de tipos e valores enum
- Limite de tamanho da resposta (max 4096 tokens)
- Deteccao de alucinacoes (heuristicas)
- Sanitizacao: remover qualquer HTML/script do output

#### Escopo e Previsibilidade

- Temperature 0 para maximo determinismo
- Prompt explicita o que o modelo pode e nao pode fazer
- Output restrito a JSON com schema definido
- Modelo nao tem acesso a informacoes do sistema (apenas imagem)

#### Tratamento de Falhas da IA

```typescript
// Cenarios de falha e tratamento
const AI_ERROR_HANDLING = {
  // LLM retorna JSON invalido
  INVALID_JSON: {
    action: "retry",
    maxRetries: 3,
    fallback: "mark_as_error",
  },

  // LLM nao identifica diagrama
  NOT_DIAGRAM: {
    action: "return_error_report",
    message: "Image is not a recognizable architecture diagram",
  },

  // LLM timeout
  TIMEOUT: {
    action: "retry",
    maxRetries: 3,
    backoff: "exponential",
    fallback: "mark_as_error",
  },

  // LLM rate limited
  RATE_LIMITED: {
    action: "retry",
    delay: 60000,
    maxRetries: 2,
    fallback: "mark_as_error",
  },

  // Output falha na validacao
  VALIDATION_FAILED: {
    action: "retry_with_adjusted_prompt",
    maxRetries: 2,
    fallback: "mark_as_error",
  },
};
```

### 3. Comunicacao entre Servicos

#### Ambiente Local (Docker Compose)

- Servicos em rede Docker interna (nao expostos externamente)
- Somente API Gateway expoe porta para o host
- Credenciais de servicos via environment variables

#### Ambiente Cloud (Kubernetes)

- Servicos comunicam via ClusterIP (rede interna K8s)
- Ingress expoe somente o API Gateway
- Network Policies para isolar namespaces
- Secrets via AWS Secrets Manager + External Secrets Operator
- IAM roles por servico (principle of least privilege)
- Comunicacao com AWS services via VPC endpoints (sem internet publica)

#### Mensageria

- Filas com acesso restrito por servico (IAM policies)
- Mensagens com correlation ID para rastreabilidade
- DLQ para mensagens que falharam (nao perdem dados)

### 4. Armazenamento Seguro

- **Senhas de banco:** Environment variables (local), Secrets Manager (cloud)
- **API Key do Anthropic:** Environment variable (local), Secrets Manager (cloud)
- **Arquivos uploadados:** Object Storage com acesso restrito
  - Presigned URLs para download (expiracao 1h)
  - Sem acesso publico ao bucket
- **Dados no banco:** Sem dados sensiveis do usuario (MVP nao tem autenticacao)

### 5. Rate Limiting e Protecao

```typescript
// API Gateway
@UseGuards(ThrottlerGuard)
@Throttle({ default: { limit: 10, ttl: 60000 } }) // 10 requests/min
@Controller("analyses")
export class AnalysesController {}
```

- Rate limiting por IP no API Gateway
- Limite de upload: 10 por minuto por IP
- Limite de consulta: 60 por minuto por IP
- Tamanho maximo de request body: 10MB

### 6. Headers de Seguranca

```typescript
// API Gateway - Helmet middleware
app.use(
  helmet({
    contentSecurityPolicy: true,
    crossOriginEmbedderPolicy: true,
    crossOriginOpenerPolicy: true,
    crossOriginResourcePolicy: true,
    dnsPrefetchControl: true,
    frameguard: true,
    hidePoweredBy: true,
    hsts: true,
    ieNoOpen: true,
    noSniff: true,
    referrerPolicy: true,
    xssFilter: true,
  }),
);
```

### 7. Logs de Seguranca

```typescript
// Eventos de seguranca logados
const SECURITY_EVENTS = {
  FILE_REJECTED: "file.rejected", // Arquivo invalido rejeitado
  RATE_LIMITED: "rate.limited", // IP atingiu rate limit
  AI_GUARDRAIL_TRIGGERED: "ai.guardrail", // Guardrail de IA acionado
  AI_HALLUCINATION_DETECTED: "ai.hallucination", // Possivel alucinacao detectada
  DLQ_MESSAGE: "dlq.message", // Mensagem enviada para DLQ
};

// Formato
logger.warn({
  event: "file.rejected",
  correlationId: "abc-123",
  reason: "invalid_mime_type",
  detectedType: "application/x-executable",
  claimedType: "image/png",
  ip: "192.168.1.1",
});
```

## Riscos e Limitacoes Identificados

| Risco                                  | Severidade | Mitigacao                                               | Status                |
| -------------------------------------- | ---------- | ------------------------------------------------------- | --------------------- |
| Prompt injection via texto no diagrama | Media      | Prompt fixo, output validado                            | Mitigado              |
| LLM alucina componentes inexistentes   | Media      | Guardrails de saida, confidence score                   | Mitigado parcialmente |
| Upload de arquivo malicioso            | Alta       | Validacao magic bytes, sandbox de processamento         | Mitigado              |
| DDoS via uploads grandes               | Alta       | Rate limiting, tamanho max 10MB                         | Mitigado              |
| Vazamento de API key                   | Critica    | Secrets Manager, env vars, nao commitado                | Mitigado              |
| Acesso nao autorizado a relatorios     | Media      | MVP sem auth, risco aceito                              | Aceito (MVP)          |
| Man-in-the-middle entre servicos       | Baixa      | Rede interna Docker/K8s                                 | Mitigado              |
| Dados sensiveis em diagramas           | Media      | Diagrama nao e armazenado apos processamento (opcional) | Mitigado parcialmente |

### Limitacoes aceitas para o MVP

1. **Sem autenticacao/autorizacao** - MVP nao requer login (risco aceito)
2. **Sem HTTPS local** - Docker Compose nao configura TLS (cloud tem via ALB)
3. **Sem auditoria completa** - Logs estruturados como substituto basico
4. **Sem WAF** - Somente rate limiting basico

## Consequencias

### Positivas

- Validacao multi-camada (entrada, processamento, saida)
- IA controlada com guardrails e escopo definido
- Falhas tratadas graciosamente sem perda de dados
- Rastreabilidade completa via correlation ID

### Negativas

- Overhead de validacao em cada camada (aceitavel para seguranca)
- Complexidade adicional no pipeline de IA
