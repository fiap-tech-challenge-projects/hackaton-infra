# ADR-004: Pipeline de Inteligencia Artificial

**Status:** Accepted
**Data:** 2026-03-26
**Contexto:** Hackaton FIAP Secure Systems - Analise de Diagramas com IA
**Relacionados:** [ADR-003](ADR-003-communication-patterns.md) (eventos), [ADR-006](ADR-006-security.md) (guardrails)

---

## Contexto

O PDF exige que a IA:

- Implemente ao menos uma abordagem (deteccao de componentes, classificacao de riscos, LLM com guardrails, ou prompt engineering com validacao)
- Tenha pipeline claro
- Seja parte do fluxo do sistema (nao script isolado)
- Tenha tratamento de falhas
- Tenha justificativa da abordagem e discussao de limitacoes

## Decisao

### Abordagem Escolhida: LLM Multimodal + Prompt Engineering com Guardrails

Combinamos **todas as 4 abordagens** do PDF em uma pipeline unificada:

1. **Deteccao de componentes** - Via LLM multimodal (Claude Vision)
2. **Classificacao de riscos** - Via regras + output estruturado do LLM
3. **LLM com guardrails** - Validacao de entrada, saida, e mitigacao de alucinacoes
4. **Prompt engineering** - Prompts estruturados com restricoes de formato e validacao

### Pipeline de IA (5 Etapas)

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
│  3. CHAMADA LLM (Claude API)                                │
│     ├── Enviar imagem + prompt via API multimodal           │
│     ├── Timeout: 60 segundos                                │
│     ├── Retry: 3x com backoff exponencial                   │
│     └── Modelo: claude-sonnet-4-20250514 (custo/qualidade)  │
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

### Etapa 1: Pre-Processamento

```typescript
class DiagramPreProcessor {
  async process(file: Buffer, mimeType: string): Promise<ProcessedImage> {
    // 1. Validar tipo
    if (!ALLOWED_TYPES.includes(mimeType)) {
      throw new InvalidFileTypeError(mimeType);
    }

    // 2. Se PDF, converter primeira pagina para imagem
    if (mimeType === "application/pdf") {
      return this.convertPdfToImage(file);
    }

    // 3. Validar dimensoes (min 200x200, max 4096x4096)
    const dimensions = await this.getImageDimensions(file);
    if (dimensions.width < 200 || dimensions.height < 200) {
      throw new ImageTooSmallError(dimensions);
    }

    // 4. Redimensionar se necessario (max 2048x2048 para LLM)
    if (dimensions.width > 2048 || dimensions.height > 2048) {
      return this.resize(file, 2048);
    }

    return { buffer: file, mimeType, dimensions };
  }
}
```

### Etapa 2: Prompt Engineering

**Template principal:**

```
You are an expert software architect analyzing architecture diagrams.

TASK: Analyze the provided architecture diagram and extract:
1. All software components/services visible in the diagram
2. Architectural risks and potential issues
3. Improvement recommendations

OUTPUT FORMAT: You MUST respond with valid JSON matching this exact schema:
{
  "components": [
    {
      "name": "string (component name as shown in diagram)",
      "type": "string (one of: service, database, queue, gateway, cache, storage, external, load_balancer, cdn, other)",
      "description": "string (brief description of the component's role)",
      "connections": ["string (names of connected components)"]
    }
  ],
  "risks": [
    {
      "title": "string (risk title)",
      "description": "string (detailed description)",
      "severity": "string (one of: critical, high, medium, low)",
      "category": "string (one of: security, scalability, reliability, performance, maintainability, cost)",
      "affectedComponents": ["string (component names)"]
    }
  ],
  "recommendations": [
    {
      "title": "string (recommendation title)",
      "description": "string (detailed recommendation)",
      "priority": "string (one of: high, medium, low)",
      "effort": "string (one of: low, medium, high)",
      "relatedRisks": ["string (risk titles)"]
    }
  ],
  "summary": "string (2-3 sentence executive summary of the architecture)"
}

RULES:
- Only identify components that are VISIBLE in the diagram
- Do NOT invent or assume components that are not shown
- Base risks on what you can observe, not hypothetical scenarios
- Keep descriptions concise and technical
- If the image is not an architecture diagram, respond with:
  {"error": "NOT_ARCHITECTURE_DIAGRAM", "message": "The provided image does not appear to be a software architecture diagram"}
- If the image quality is too low to analyze, respond with:
  {"error": "LOW_QUALITY_IMAGE", "message": "The image quality is insufficient for reliable analysis"}
```

**Guardrails de entrada do prompt:**

- Prompt template versionado (v1, v2, etc) para rastreabilidade
- Nao inclui dados do usuario no prompt (previne injection)
- Instrucoes explicitas de formato (JSON schema)
- Restricoes claras do que o LLM pode/nao pode fazer
- Casos de erro definidos no prompt

### Etapa 3: Chamada LLM

```typescript
class LlmService {
  async analyzeImage(
    image: ProcessedImage,
    promptVersion: string,
  ): Promise<LlmResponse> {
    const prompt = this.promptService.getPrompt(promptVersion);

    const response = await this.retryWithBackoff(
      async () => {
        return this.anthropic.messages.create({
          model: "claude-sonnet-4-20250514",
          max_tokens: 4096,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "image",
                  source: {
                    type: "base64",
                    media_type: image.mimeType,
                    data: image.buffer.toString("base64"),
                  },
                },
                { type: "text", text: prompt },
              ],
            },
          ],
        });
      },
      { maxRetries: 3, baseDelay: 1000 },
    );

    return this.parseResponse(response);
  }
}
```

**Configuracao do modelo:**

- Modelo: `claude-sonnet-4-20250514` (equilibrio custo/qualidade)
- Max tokens: 4096 (suficiente para analise detalhada)
- Temperature: 0 (maximo determinismo, respostas consistentes)
- Timeout: 60s por chamada
- Retry: 3x com backoff exponencial (1s, 2s, 4s)

### Etapa 4: Validacao de Saida (Guardrails)

```typescript
class OutputValidator {
  validate(response: unknown): ValidationResult {
    const checks: ValidationCheck[] = [
      // 1. JSON valido?
      this.validateJsonSchema(response),

      // 2. Tem campos obrigatorios?
      this.validateRequiredFields(response),

      // 3. Componentes tem nomes unicos?
      this.validateUniqueComponents(response),

      // 4. Riscos referenciam componentes existentes?
      this.validateRiskReferences(response),

      // 5. Severidades sao valores validos?
      this.validateEnumValues(response),

      // 6. Nao tem conteudo potencialmente alucinado?
      this.detectHallucinations(response),
    ];

    return {
      isValid: checks.every((c) => c.passed),
      checks,
      confidence: this.calculateConfidence(checks),
    };
  }

  private detectHallucinations(response: AnalysisOutput): ValidationCheck {
    // Heuristica: se tem componentes demais (>50) provavelmente alucinando
    // Se recomendacoes nao se relacionam com riscos detectados
    // Se descricoes sao genericas demais (cosine similarity com templates)
    const componentCount = response.components?.length ?? 0;
    const hasGenericDescriptions = this.checkGenericDescriptions(response);

    return {
      name: "hallucination_check",
      passed: componentCount <= 50 && !hasGenericDescriptions,
      details: { componentCount, hasGenericDescriptions },
    };
  }
}
```

### Etapa 5: Pos-Processamento

```typescript
class PostProcessor {
  process(
    validatedOutput: AnalysisOutput,
    metadata: ProcessingMetadata,
  ): AnalysisResult {
    return {
      // Dados da analise
      components: validatedOutput.components,
      risks: this.classifyRisks(validatedOutput.risks),
      recommendations: this.prioritizeRecommendations(
        validatedOutput.recommendations,
      ),
      summary: validatedOutput.summary,

      // Metadados de processamento
      metadata: {
        model: metadata.model,
        promptVersion: metadata.promptVersion,
        processingTimeMs: metadata.processingTimeMs,
        confidence: metadata.confidence,
        timestamp: new Date().toISOString(),
      },
    };
  }

  private classifyRisks(risks: Risk[]): ClassifiedRisk[] {
    // Regras de classificacao complementares ao LLM:
    // - Single point of failure sem redundancia -> severity: critical
    // - Sem autenticacao entre servicos -> severity: high
    // - Sem cache em queries frequentes -> severity: medium
    return risks.map((risk) => ({
      ...risk,
      // Re-classificar baseado em regras de negocio
      severity: this.applyBusinessRules(risk),
    }));
  }
}
```

### Modelo de Dados (DynamoDB - Processing Service)

**Tabela:** `hackaton-analysis-results-{env}`

| Atributo          | Tipo              | Chave                |
| ----------------- | ----------------- | -------------------- |
| `analysisId`      | String            | Partition Key (hash) |
| `createdAt`       | String (ISO 8601) | Sort Key (range)     |
| `components`      | List/Map          | -                    |
| `risks`           | List/Map          | -                    |
| `recommendations` | List/Map          | -                    |
| `summary`         | String            | -                    |
| `rawLlmResponse`  | String            | -                    |
| `metadata`        | Map               | -                    |
| `validation`      | Map               | -                    |

**GSIs:**

- Nenhum necessario (acesso sempre por analysisId)

**Config:**

- Billing: PAY_PER_REQUEST (on-demand, free tier eligible)
- TTL: opcional (expiresAt para limpeza automatica)

```typescript
// DynamoDB Document Client usage
const analysisResult = {
    analysisId: 'uuid',
    createdAt: new Date().toISOString(),
    components: [...],
    risks: [...],
    recommendations: [...],
    summary: 'string',
    rawLlmResponse: 'string', // Resposta bruta para auditoria
    metadata: {
      model: 'string',
      promptVersion: 'string',
      processingTimeMs: 5200,
      confidence: 0.85,
      temperature: 0,
      maxTokens: 4096,
    },
    validation: {
      isValid: true,
      checks: [{ name: 'json_schema', passed: true, details: {} }],
    },
};

// PutItem via DynamoDB client + marshall (mesmo padrao billing/execution-service)
import { PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall } from '@aws-sdk/util-dynamodb';

await dynamoClient.send(new PutItemCommand({
  TableName: `hackaton-analysis-results-${env}`,
  Item: marshall(analysisResult, { removeUndefinedValues: true }),
}));
```

## Justificativa da Abordagem

1. **LLM Multimodal (Claude Vision):** Capacidade nativa de interpretar diagramas visuais sem necessidade de OCR ou modelos de deteccao de objetos dedicados
2. **Prompt Engineering estruturado:** JSON schema no prompt garante output previsivel e parseavel
3. **Guardrails multi-camada:** Validacao em cada etapa previne propagacao de erros
4. **Regras complementares:** Classificacao de riscos nao depende 100% do LLM

## Limitacoes Conhecidas

| Limitacao                                       | Impacto                     | Mitigacao                                               |
| ----------------------------------------------- | --------------------------- | ------------------------------------------------------- |
| LLM pode alucinar componentes                   | Falso positivo no relatorio | Validacao de saida + confidence score                   |
| Diagramas complexos podem ser mal interpretados | Analise incompleta          | Guardrail que detecta baixa confianca                   |
| Custo por chamada de API (~$0.003 por diagrama) | Custo operacional           | Cache de resultados, rate limiting                      |
| Latencia (5-15s por analise)                    | UX                          | Processamento assincrono + status polling               |
| Diagramas manuscritos ou de baixa qualidade     | Analise imprecisa           | Pre-processamento + erro gracioso                       |
| Variabilidade entre chamadas                    | Resultados inconsistentes   | Temperature 0, prompt deterministico                    |
| Prompt injection via texto no diagrama          | Seguranca                   | Prompt nao inclui dados do usuario, guardrails de saida |

## Consequencias

### Positivas

- Pipeline clara e auditavel (cada etapa logada)
- Guardrails previnem propagacao de erros do LLM
- Resultado persistido com metadados para avaliacao posterior
- Facil evoluir (trocar modelo, ajustar prompt, adicionar regras)

### Negativas

- Dependencia de API externa (Claude/Anthropic)
- Custo por chamada (mitigado: MVP com volume baixo)
- Latencia da API (mitigado: processamento assincrono)
