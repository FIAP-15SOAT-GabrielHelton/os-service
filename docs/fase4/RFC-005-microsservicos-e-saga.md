# RFC-005: Divisão em Microsserviços e Saga Pattern

| Metadado | Detalhe |
| :--- | :--- |
| **Título** | Divisão do monolito em 3 microsserviços com Saga coreografada |
| **Status** | `PROPOSTO` |
| **Autor(es)** | FIAP 15SOAT - Grupo 161 |
| **Data** | 12 de Novembro de 2026 |
| **Contexto** | Tech Challenge - Fase 4 (microsserviços, Saga Pattern, CI/CD por serviço) |
| **Repositórios afetados** | `os-service` (cópia do `api` da Fase 3), `billing-service` (novo), `execution-service` (novo), `k8s-infra-fase4`, `db-infra-fase4`, `deploy-orchestrator-fase4`, `auth-serverless-fase4` |

> Os repositórios da Fase 3 (`api`, `db-infra`, `k8s-infra`, `auth-serverless`, `deploy-orchestrator`) ficam intactos. A Fase 4 trabalha em cópias com o histórico preservado.

---

## 1. Resumo

O monolito `api` é dividido em três serviços, cada um com repositório, banco e pipeline próprios. Eles se comunicam por eventos no RabbitMQ, e o fluxo da ordem de serviço é coordenado por uma Saga coreografada. Nenhum serviço acessa o banco de outro.

## 2. Divisão dos serviços

| Serviço | Banco | Responsabilidade | Origem no monolito |
| :--- | :--- | :--- | :--- |
| **OS Service** | PostgreSQL | Clientes, veículos, serviços, estoque, usuários, abertura e diagnóstico da OS, atribuição de mecânico, status, acompanhamento por protocolo, entrega | `registrations`, `inventory`, `accounts`, parte de `work_orders` |
| **Billing Service** | PostgreSQL | Orçamento, aprovação ou rejeição, cobrança via Mercado Pago | `quotes` + pagamento (novo) |
| **Execution Service** | MongoDB | Fila de execução, início e fim de cada item, conclusão | `execute`, `start/finish_line_item`, `complete`, `ready_to_execute` |

A divisão segue os contextos que o monolito já separava em pastas (`app/domains/*`), o que reduz o trabalho a mover código em vez de reescrever. O estoque fica no OS Service para não criar um quarto serviço.

## 3. Saga

```mermaid
sequenceDiagram
    autonumber
    participant OS as OS Service
    participant B as Billing Service
    participant E as Execution Service
    participant MP as Mercado Pago

    OS->>B: work_order.diagnosed (itens e valores)
    Note over B: gera e envia o orçamento
    B->>OS: quote.approved
    Note over OS: baixa o estoque
    OS->>E: work_order.approved
    Note over E: enfileira
    E->>OS: execution.started
    Note over E: executa
    E->>OS: execution.completed
    E->>B: execution.completed
    B->>MP: cria a cobrança
    MP-->>B: webhook de pagamento
    B->>OS: payment.approved
    Note over OS: libera a entrega
```

### Compensações

| Falha | Evento | Compensação |
| :--- | :--- | :--- |
| Cliente rejeita o orçamento | `quote.rejected` (Billing) | OS marca a ordem como rejeitada |
| Estoque insuficiente na aprovação | `work_order.cancelled` (OS) | OS cancela a ordem em vez de aprová-la; Billing cancela o orçamento aprovado; a execução não é criada |
| Execução falha | `execution.failed` (Execution) → `work_order.cancelled` (OS) | OS cancela a ordem e devolve as peças ao estoque; Billing cancela o orçamento |
| Pagamento falha | — | Nada a desfazer: a OS permanece aguardando pagamento e o cliente tenta de novo |

## 4. Decisões

| Decisão | Escolha | Motivo |
| :--- | :--- | :--- |
| Linguagem | Rails nos três serviços | Reaproveita código, testes, Dockerfile, manifestos e pipeline do `api` |
| Bancos | PostgreSQL (OS, Billing) e MongoDB (Execution) | Cumpre a exigência de SQL + NoSQL; a fila de execução é um documento por OS, sem joins |
| Mensageria | RabbitMQ | Roteamento por tópico atende à coreografia; roda no próprio cluster, sem depender de serviço extra na conta AWS Academy |
| Tipo de Saga | Coreografada | São só três serviços e um fluxo linear; dispensa manter um orquestrador |
| Momento do pagamento | Na entrega, após a execução | É como uma oficina cobra; uma falha na execução não exige estorno em dinheiro |
| Autenticação | Mantém o `auth-serverless`; os três serviços validam o mesmo JWT (segredo compartilhado) | Sem mudança em relação à Fase 3 |
| Leitura entre serviços | API Composition: o detalhe da OS busca o orçamento no Billing por REST, repassando o token do usuário | Única chamada síncrona; se o Billing estiver fora, a OS responde sem o orçamento |
| Observabilidade | Mantém o New Relic (RFC-004), com rastreamento distribuído entre os serviços | Exigência do enunciado |

## 5. Mudanças por repositório

| Repositório | Mudança |
| :--- | :--- |
| `os-service` | Remove `quotes` e os casos de uso de execução; publica e consome eventos; novos estados da OS (cancelada, aguardando pagamento) |
| `billing-service` (novo) | Recebe `quotes`; integra o Mercado Pago |
| `execution-service` (novo) | Recebe a execução; persiste em MongoDB |
| `k8s-infra-fase4` | Adiciona RabbitMQ e MongoDB ao cluster |
| `db-infra-fase4` | Adiciona o banco do Billing |
| `deploy-orchestrator-fase4` | Inclui os dois serviços novos na sequência de deploy |
| `auth-serverless-fase4` | Sem mudança |

## 6. Etapas

- [x] 1. RabbitMQ no `os-service` e publicação de `work_order.diagnosed`
- [x] 2. `billing-service`: orçamento por eventos
- [x] 3. `execution-service`: fila em MongoDB por eventos
- [x] 4. Compensações da Saga
- [x] 5. Mercado Pago no `billing-service`
- [x] 6. Remover do `os-service` o que migrou para os outros serviços
- [ ] 7. Por serviço: cobertura de 80%, um fluxo em BDD, Sonar, CI/CD, `main` protegida
- [ ] 8. Infra: RabbitMQ, MongoDB, banco do Billing, orquestrador
- [ ] 9. READMEs, diagrama final, PDF e vídeo
