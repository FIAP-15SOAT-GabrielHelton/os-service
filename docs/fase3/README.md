# 15SOAT - Fase 3 - Tech Challenge - Grupo 161

> Documentação da **Fase 3**, preservada como estava na entrega. O estado atual do projeto (Fase 4, microsserviços) está no [README da raiz](../../README.md).

Sistema de gestão de oficina mecânica: uma API Rails que cobre todo o ciclo de vida de uma Ordem de Serviço (OS), da abertura ao orçamento, aprovação e entrega do veículo. A Fase 1 entregou a aplicação em **Domain-Driven Design (DDD)**; a Fase 2 evoluiu código e infraestrutura (Kubernetes, Terraform, HPA); a **Fase 3** adiciona **autenticação de clientes via CPF**, **autorização por papéis (RBAC)** e uma **arquitetura serverless** (AWS API Gateway + Lambda) como porta de entrada única — e separa o projeto em **5 repositórios independentes**, conforme exigido pelo desafio.

> A documentação das fases anteriores foi preservada: [Fase 1](../fase1/README.md) (arquitetura DDD, bounded contexts, event storming) e [Fase 2](../fase2/README.md) (Clean Code, Kubernetes/Terraform, HPA).

## Tecnologias utilizadas

| Categoria | Tecnologia |
| :--- | :--- |
| Linguagem / Framework | Ruby 3.4, Rails 8.1 (API-only) |
| Banco de dados | PostgreSQL (RDS gerenciado, provisionado pelo repositório [`db-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/db-infra)) |
| Servidor de aplicação | Puma |
| Jobs assíncronos | Solid Queue (roda sobre o próprio Postgres, sem Redis) |
| Autenticação | JWT (`jwt`) — staff via e-mail/senha e clientes via CPF (bridge com o [`auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless)) |
| Documentação da API | OpenAPI/Swagger (`rswag`) |
| Testes | RSpec, FactoryBot, Faker, shoulda-matchers, SimpleCov (mínimo 80% linha/branch) |
| Qualidade / Segurança | RuboCop, Brakeman, bundler-audit, Trivy, Semgrep, SonarQube, OWASP ZAP |
| Deploy | Docker, Kubernetes (EKS, provisionado pelo [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra)), Terraform (ECR), Helm (metrics-server) |
| CI/CD | GitHub Actions |

## Objetivos desta fase

- **Autenticação de clientes via CPF**: identificação sem senha, emitindo um JWT (`role: "customer"`) para acesso escopado aos próprios dados.
- **RBAC (Role-Based Access Control)**: papéis `admin`, `receptionist`, `mechanic` (staff) e `customer`, com regras de acesso por rota/ação (matriz completa na RFC-001).
- **Arquitetura serverless como porta de entrada única**: AWS API Gateway + AWS Lambda (função de autenticação + Lambda Authorizer), num repositório dedicado.
- **Separação em 5 repositórios independentes**, cada um com CI/CD próprio: [`api`](https://github.com/FIAP-15SOAT-GabrielHelton/api) (este), [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra), [`db-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/db-infra), [`auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless) e o auxiliar [`deploy-orchestrator`](https://github.com/FIAP-15SOAT-GabrielHelton/deploy-orchestrator).
- Documentar as decisões técnicas como **RFC** (com ADRs embutidos) — ver [`docs/fase3/RFC-001`](../fase3/RFC-001-authentication-authorization-serverless.md).

## Autenticação e RBAC

- **Staff** (`admin`/`receptionist`/`mechanic`): `POST /api/v1/auth/login` (e-mail/senha) → JWT `type: "access"`.
- **Cliente**: `POST /api/v1/auth/customer` (CPF) → JWT `type: "customer_access"`, `role: "customer"`. Em produção, essa rota é atendida pela Lambda `auth_customer` do [`auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless), que valida o formato do CPF e delega a este repositório (Single Source of Truth) a existência/status do cliente e a emissão do token.
- **Autorização**: o concern `JwtAuthenticatable` (`app/controllers/concerns/jwt_authenticatable.rb`) expõe `require_staff!`, `require_admin!`, `require_mechanic!`, `require_receptionist!`, `require_customer!` e o helper `forbidden_for_customer?` para checagem de ownership (cliente só acessa seus próprios veículos, OSs, orçamentos e cadastro).
- Matriz completa de permissões por rota: [RFC-001 §6](../fase3/RFC-001-authentication-authorization-serverless.md).

## Arquitetura

### Componentes da aplicação (neste repositório)

| Componente     | O que é                                                              | Onde roda                                                                |
| -------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **web**        | API Rails (Puma), exposta via `/up`, `/api/v1/*`, `/api-docs`        | `Deployment` `oficina-mecanica-web` + `Service` LoadBalancer             |
| **jobs**       | Worker do Solid Queue (e-mails via SendGrid, jobs assíncronos)       | `Deployment` `oficina-mecanica-jobs`                                     |
| **db-prepare** | `bin/rails db:prepare` (migrations + seed) — roda uma vez por deploy | `Job` do Kubernetes, com `kubectl wait` bloqueando o deploy até concluir |
| **HPA**        | Escala o `web` por CPU (70%) e memória (80%), 1 a 3 réplicas         | `HorizontalPodAutoscaler` + `metrics-server` (do `k8s-infra`)            |

### Visão dos 5 repositórios

```mermaid
flowchart LR
    Client["Cliente / Staff"]
    APIGW["API Gateway + Lambdas\n(auth-serverless)\núnica porta de entrada"]

    subgraph ThisRepo["api — este repositório"]
        Web["Rails (web/jobs)"]
        ECR[["ECR"]]
    end

    K8S["k8s-infra\nVPC + EKS"]
    DB["db-infra\nRDS PostgreSQL"]
    Orch["deploy-orchestrator\n(dispara os 4 repos em ordem)"]

    Client --> APIGW
    APIGW -- "HTTP_PROXY (rotas públicas + autorizadas)" --> Web
    Web --- K8S
    Web --> DB
    Orch -.-> K8S
    Orch -.-> DB
    Orch -.-> ThisRepo
    Orch -.-> APIGW

    classDef repo fill:#9bb8ff,stroke:#5470c6,color:#000
    classDef ext fill:#dddddd,stroke:#999999,color:#333,stroke-dasharray: 3 3
    class Web,ECR repo
    class APIGW,K8S,DB,Orch ext
```

Detalhes de cada repositório, o contrato de dados entre eles (AWS SSM Parameter Store) e a ordem de deploy: [RFC-001 §7.3](../fase3/RFC-001-authentication-authorization-serverless.md).

### Infraestrutura deste repositório (Terraform, `infra/`) e sua relação com os demais

> VPC, EKS e RDS deixaram de ser provisionados aqui — foram extraídos para os repositórios [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra) e [`db-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/db-infra), atendendo ao requisito do desafio de repositórios independentes. Este repositório provisiona só o **ECR** e faz o **deploy da aplicação** num cluster já existente. A troca de informação entre os 5 repositórios (cluster, banco, URL pública) acontece via **AWS SSM Parameter Store** — nenhum deles lê o `.tfstate` de outro.

```mermaid
flowchart TB
    subgraph ThisRepo["api — este repositório"]
        ECR[["ECR\nimagem Docker"]]
        Web["Deployment web (Puma)"]
        Jobs["Deployment jobs (Solid Queue)"]
        DbPrepare["Job db-prepare\n(migrations + seed)"]
        Svc["Service\nLoadBalancer"]
        HPA["HPA\n1 a 3 réplicas"]
    end

    subgraph Others["Provisionado por outros repositórios"]
        EKS[["Cluster EKS\n(k8s-infra)"]]
        RDS[("RDS PostgreSQL\n(db-infra)")]
        APIGW["API Gateway\n(auth-serverless)"]
    end

    SSM[("AWS SSM\nParameter Store")]

    SSM -. eks_cluster_name .-> Web
    SSM -. rds_address .-> Web
    ECR -- pull da imagem --> Web
    ECR -- pull da imagem --> Jobs
    Web & Jobs & DbPrepare --> RDS
    Web --- EKS
    HPA -. escala .-> Web
    Web --> Svc
    Svc -. publica rails_api_base_url .-> SSM
    APIGW -- HTTP_PROXY --> Svc

    classDef repo fill:#9bb8ff,stroke:#5470c6,color:#000
    classDef ext fill:#dddddd,stroke:#999999,color:#333,stroke-dasharray: 3 3
    classDef db fill:#a8e6a2,stroke:#2d8a1f,color:#000

    class ECR,Web,Jobs,DbPrepare,Svc,HPA repo
    class EKS,APIGW ext
    class RDS,SSM db
```

- **ECR** (`infra/ecr.tf`): registry da imagem Docker da aplicação — único recurso de Terraform que sobrou neste repositório.
- **Deploy no Kubernetes** (`k8s/`): `Deployment` web + jobs, `Job` de migrations/seed, `Service` LoadBalancer e `HPA` — aplicados via `kubectl` num cluster provisionado pelo `k8s-infra` (nome lido do SSM).
- **RDS**: endpoint lido do SSM, publicado pelo `db-infra`.
- **API Gateway**: mora no `auth-serverless` e acessa o `Service` deste repositório via `HTTP_PROXY` direto ao hostname público do ELB (publicado por este repositório no SSM).
- Detalhes completos da separação e do contrato de dados: [RFC-001](../fase3/RFC-001-authentication-authorization-serverless.md) (ADR 5, 6 e 7).

### Fluxo de CI

Roda em todo `push` na `main` e em toda `pull_request` ([`ci.yml`](../../.github/workflows/ci.yml)):

```mermaid
flowchart TB
    Trigger(["push (main) / pull_request"])

    Trigger --> Lint["lint\nRuboCop"]
    Trigger --> Test["test\nRSpec + Postgres (service container)"]
    Trigger -.-> ScanRuby["scan_ruby\nbrakeman + bundler-audit"]
    Trigger -.-> ScanExtra["scan_extra\nTrivy + Semgrep"]

    Test --> Coverage["Cobertura de linha/branch\n>= 80%, verificada pelo SimpleCov"]

    classDef active fill:#9bb8ff,stroke:#5470c6,color:#000
    classDef disabled fill:#dddddd,stroke:#999999,color:#555,stroke-dasharray: 5 5

    class Lint,Test,Coverage active
    class ScanRuby,ScanExtra disabled
```

> `scan_ruby` e `scan_extra` estão temporariamente desativados (`if: false` em `ci.yml`) — mantidos no workflow para reativação futura. Detalhes de cada scanner: [`docs/fase1/security.md`](../fase1/security.md).

### Fluxo de deploy (CD)

```mermaid
flowchart TB
    Trigger(["Disparo MANUAL (workflow_dispatch)\ncredenciais AWS Academy como input"]) --> Provision["Provisiona o ECR\nterraform apply"]
    Provision --> Read["Lê eks_cluster_name / rds_address\ndo SSM (k8s-infra / db-infra)"]
    Read --> Build["Build & push da imagem\nECR, tag = SHA do commit"]
    Build --> Deploy["Deploy no Kubernetes\nmigrations (Job) + web/jobs/service/hpa"]
    Deploy --> Publish["Publica rails_api_base_url no SSM\n(para o auth-serverless)"]
    Publish --> Destroy["Autodestruição de segurança\nsleep 2h → limpa workloads + ECR"]

    classDef manual fill:#ffd38c,stroke:#e58e00,color:#000
    classDef step fill:#9bb8ff,stroke:#5470c6,color:#000
    classDef danger fill:#ffcccc,stroke:#cc4444,color:#000
    class Trigger manual
    class Provision,Read,Build,Deploy,Publish step
    class Destroy danger
```

Este repositório é o **3º na ordem de deploy do projeto**: `k8s-infra → db-infra → api (este repo) → auth-serverless` — ou dispare todos de uma vez via o [`deploy-orchestrator`](https://github.com/FIAP-15SOAT-GabrielHelton/deploy-orchestrator). O deploy **nunca dispara sozinho**: é sempre acionado manualmente na aba **Actions → CD Deploy (App on EKS) → Run workflow**, informando as credenciais temporárias da sessão AWS Academy — mesma lógica do destroy manual imediato ([`cd_destroy.yml`](../../.github/workflows/cd_destroy.yml)). Detalhe de cada etapa: [`cd_deploy.yml`](../../.github/workflows/cd_deploy.yml) — ambos compartilham a lógica de destruição via a composite action [`infra-destroy`](../../.github/actions/infra-destroy/action.yml).

## Execução local

Apenas Docker é necessário:

```bash
git clone git@github.com:FIAP-15SOAT-GabrielHelton/api.git
cd api
cp .env.example .env
docker compose build
docker compose run --rm web bin/rails db:prepare
docker compose up
```

A API sobe em `http://localhost:3000` (Swagger em `/api-docs`). Detalhes de setup, credenciais de teste e troubleshooting: [`docs/fase1/README.md`](../fase1/README.md).

Para testar o fluxo completo de autenticação por CPF + API Gateway localmente (Lambdas do `auth-serverless` contra esta API Rails), veja o [README do `auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless#desenvolvimento-local).

## Deploy em Kubernetes

O deploy real acontece via GitHub Actions (aba **Actions → CD Deploy (App on EKS) → Run workflow**), informando as credenciais temporárias da sessão AWS Academy — **depois** que `k8s-infra` e `db-infra` já tiverem sido implantados. Para rodar manualmente contra um cluster já provisionado:

```bash
aws eks update-kubeconfig --name oficina-mecanica-cluster --region us-east-1

kubectl apply -f k8s/configmap.yaml -f k8s/secrets.yaml
kubectl apply -f k8s/db-prepare-job.yaml
kubectl wait --for=condition=complete --timeout=300s job/oficina-mecanica-db-prepare

kubectl apply -f k8s/web-deployment.yaml -f k8s/jobs-deployment.yaml -f k8s/service.yaml -f k8s/hpa.yaml

kubectl get svc oficina-mecanica-web-service   # EXTERNAL-IP é a URL pública (http://, porta 80)
```

> `k8s/configmap.yaml` e `k8s/secrets.yaml` contêm placeholders (`DATABASE_HOST_PLACEHOLDER`, `DATABASE_PASSWORD_PLACEHOLDER`, `SECRET_KEY_BASE_PLACEHOLDER`, `IMAGE_PLACEHOLDER`) — o workflow de CD os substitui automaticamente com `sed` a partir do SSM Parameter Store e dos GitHub Secrets. Para aplicar manualmente, substitua-os antes.

Em produção, a URL pública real do sistema é a do **API Gateway** (repositório `auth-serverless`), não a do `Service` acima — o ELB deste repositório é um destino interno do `HTTP_PROXY` do Gateway.

### Testando o autoscaling (HPA)

```bash
bin/test_hpa.sh start     # gera carga real contra o Service e acompanha o HPA em tempo real
bin/test_hpa.sh status    # snapshot único do HPA/pods/CPU, sem gerar carga
bin/test_hpa.sh stop      # remove o gerador de carga manualmente
```

O script sobe um `Deployment` auxiliar (`busybox`) batendo em `/up`, mostra `kubectl get hpa`/`top pods` em loop e remove tudo automaticamente ao encerrar com `Ctrl+C`.

### Gerando tráfego de demonstração (New Relic)

```bash
bin/generate_demo_traffic.sh <URL_DO_API_GATEWAY> [CICLOS]
```

**Por que existe:** os dashboards do New Relic (volume diário de OS, tempo médio por etapa, falhas de processamento) só mostram algo relevante depois que o sistema processa tráfego real. Sem esse script, seria preciso operar a aplicação manualmente por vários ciclos completos (autenticação → diagnóstico → orçamento → execução → entrega) só para gerar dados suficientes para o vídeo de demonstração.

**O que faz:** roda `CICLOS` ciclos completos (padrão: 4) do fluxo de negócio de ponta a ponta contra a URL informada — login de staff, autenticação de cliente por CPF, criação de OS, diagnóstico, orçamento, aprovação, execução, entrega e consulta de tracking público — alternando entre os dois clientes do seed padrão. A cada ciclo também dispara **uma falha proposital diferente** (OS inexistente, senha errada, CPF inválido, RBAC negado, transição de estado inválida), de forma determinística e rotativa, para popular o widget de "falhas/erros de integração" do dashboard sem exigir teste manual de cada cenário de erro. Ao final, faz algumas chamadas ao healthcheck público (`/up`).

**Como rodar:** requer `curl` e `jq`, e assume os dados do seed padrão (`db/seeds.rb`: usuários `admin`/`mechanic` e os clientes de exemplo, cada um com pelo menos um veículo). Deve ser apontado para a URL pública do **API Gateway** (não para o Service do Kubernetes diretamente), já que os cenários de autenticação de cliente por CPF passam pela Lambda do [`auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless):

```bash
bin/generate_demo_traffic.sh https://<api-id>.execute-api.us-east-1.amazonaws.com 5
```

Os dados levam de 1 a 3 minutos para aparecer no New Relic (APM/eventos de negócio) e cerca de 1 minuto para as métricas de Kubernetes (`nri-kubernetes`). Este script é independente do CI/CD — não é chamado por nenhum workflow, é uma ferramenta manual de preparação para a gravação do vídeo demonstrativo.

## Provisionamento da infraestrutura (Terraform)

Este repositório só provisiona o **ECR** — pré-requisito: os repositórios [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra) e [`db-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/db-infra) precisam ter sido implantados antes (publicam `eks_cluster_name`/`rds_address` no SSM, lidos em tempo de deploy).

```bash
cd infra/
terraform init \
  -backend-config="bucket=<nome-do-bucket-s3>" \
  -backend-config="key=oficina-mecanica/terraform.tfstate" \
  -backend-config="region=us-east-1"

terraform plan
terraform apply

terraform output ecr_repository_url
```

Ao final do uso, destrua os recursos para não consumir os créditos do AWS Academy:

```bash
terraform destroy
```

No pipeline de CI/CD, esses passos são automáticos — incluindo a limpeza de imagens do ECR e a espera pela liberação física do Load Balancer antes do `destroy`, feita na composite action [`infra-destroy`](../../.github/actions/infra-destroy/action.yml).

## Documentação da API

- **Swagger UI** (ambiente local): [`http://localhost:3000/api-docs`](http://localhost:3000/api-docs)
- **Swagger UI** (ambiente implantado): `http://<EXTERNAL-IP-do-Service>/api-docs` (ou, via o API Gateway em produção, `<url-do-api-gateway>/api-docs`)
- Spec OpenAPI versionada: [`swagger/v1/swagger.json`](../../swagger/v1/swagger.json)
- Walkthrough completo via `curl` cobrindo o ciclo de vida de uma OS: [`docs/fase1/demo.md`](../fase1/demo.md)
- Walkthrough via `curl` dos endpoints da Fase 2 (webhooks, rejeição direta, listagem priorizada): [`docs/fase2/demo.md`](../fase2/demo.md)
- Autenticação de cliente por CPF e RBAC: exemplos de request/response na [RFC-001 §5](../fase3/RFC-001-authentication-authorization-serverless.md)
- Walkthrough via `curl` da autenticação por CPF, geração de JWT e RBAC nas rotas protegidas: [`docs/fase3/demo-video-curl.md`](../fase3/demo-video-curl.md)

## Vídeo demonstrativo

_[Youtube](https://www.youtube.com/watch?v=uv2nZvj7HSk)_ — gravado na Fase 2 (deploy, CI/CD, consumo das APIs e HPA sob carga). Ainda não há um vídeo específico da Fase 3.

## Monitoramento e Observabilidade

Ferramenta: **New Relic** (APM + Infrastructure + dashboard/alertas como código). Cobertura:

- **APM na API Rails** (`newrelic_rpm`) — latência, throughput, erros e distributed tracing.
- **Extensão Lambda** nas duas funções do [`auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless) (`auth_customer`, `lambda_authorizer`).
- **New Relic Infrastructure** (`nri-kubernetes`, via Helm no [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra)) — CPU/memória do cluster EKS.
- **Logs estruturados em JSON** correlacionados por `request_id`/`trace.id`, do API Gateway até o banco (ver [nota técnica no diagrama de sequência](../fase3/architecture/sequence-diagrams.md)).
- **Eventos de negócio customizados** — duração da OS por etapa (diagnóstico, execução, finalização) e falhas de processamento de OS/orçamentos, usados no dashboard e nas condições de alerta.
- **Dashboard e policy de alertas** (latência elevada, falhas no processamento de OS, indisponibilidade do healthcheck) provisionados via Terraform (provider `newrelic`) no [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra).

Detalhes de arquitetura: [`docs/fase3/architecture/component-diagram.md`](../fase3/architecture/component-diagram.md#4-monitoramento). Justificativa da escolha da ferramenta: [ADR 11](../fase3/architecture/adr-log.md#adr-11-new-relic-como-ferramenta-de-observabilidade-e-monitoramento).

## Segurança

Mantido da Fase 1 sem alterações — bundler-audit, brakeman, Trivy, Semgrep, SonarQube e OWASP ZAP. Detalhes, exemplos de output e workflow de remediação: [`docs/fase1/security.md`](../fase1/security.md).

## Testes

RSpec com FactoryBot, Faker e shoulda-matchers:

```bash
docker compose exec web bundle exec rspec
```

Detalhes da estrutura de `spec/` e comandos por camada: [`docs/fase1/README.md`](../fase1/README.md#testes).

## Documentação adicional

| Documento | Conteúdo |
| :--- | :--- |
| [`docs/fase1/README.md`](../fase1/README.md) | README original da Fase 1: stack, arquitetura DDD, bounded contexts, comandos úteis, troubleshooting |
| [`docs/fase1/event_storming.md`](../fase1/event_storming.md) | Event Storming dos 4 bounded contexts (diagramas Mermaid) |
| [`docs/fase1/demo.md`](../fase1/demo.md) | Walkthrough via `curl` do ciclo de vida completo de uma OS |
| [`docs/fase1/security.md`](../fase1/security.md) | Scanners de segurança (SAST/DAST), como rodar e remediar achados |
| [`docs/fase2/README.md`](../fase2/README.md) | README original da Fase 2: Clean Code, infraestrutura Kubernetes/Terraform, HPA |
| [`docs/fase2/demo.md`](../fase2/demo.md) | Walkthrough via `curl` dos endpoints refatorados/adicionados na Fase 2 |
| [`docs/fase3/RFC-001`](../fase3/RFC-001-authentication-authorization-serverless.md) | Autenticação via CPF, RBAC, arquitetura serverless e separação em 5 repositórios (ADRs 1-7) |
| [`docs/fase3/RFC-002`](../fase3/RFC-002-escolha-da-nuvem.md) | Escolha do provedor de nuvem (AWS/AWS Academy) e suas implicações arquiteturais |
| [`docs/fase3/RFC-003`](../fase3/RFC-003-escolha-do-banco-e-modelo.md) | Escolha do banco de dados (PostgreSQL), diagrama ER completo e explicação dos relacionamentos |
| [`docs/fase3/RFC-004`](../fase3/RFC-004-escolha-da-observabilidade.md) | Escolha da ferramenta de observabilidade (New Relic vs. Datadog vs. Prometheus/Grafana vs. CloudWatch) |
| [`docs/fase3/architecture/component-diagram.md`](../fase3/architecture/component-diagram.md) | Diagrama de componentes completo: nuvem, APIs, banco e monitoramento (atravessa os 5 repositórios) |
| [`docs/fase3/architecture/sequence-diagrams.md`](../fase3/architecture/sequence-diagrams.md) | Diagramas de sequência: autenticação por CPF, rota protegida (RBAC) e abertura de Ordem de Serviço |
| [`docs/fase3/architecture/adr-log.md`](../fase3/architecture/adr-log.md) | ADRs 8-12: padrão de comunicação (REST síncrono), uso de HPA, Clean Architecture/DDD, escolha do New Relic, organização de logs/traces |

## Repositórios do projeto (Fase 3)

| Repositório | Responsabilidade |
| :--- | :--- |
| `api` (este repositório) | Aplicação Rails, ECR e deploy no cluster |
| [`k8s-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/k8s-infra) | VPC + EKS + node group |
| [`db-infra`](https://github.com/FIAP-15SOAT-GabrielHelton/db-infra) | RDS PostgreSQL |
| [`auth-serverless`](https://github.com/FIAP-15SOAT-GabrielHelton/auth-serverless) | API Gateway (porta de entrada única) + Lambdas de autenticação/RBAC |
| [`deploy-orchestrator`](https://github.com/FIAP-15SOAT-GabrielHelton/deploy-orchestrator) | Dispara e aguarda o deploy dos 4 repositórios acima, em ordem |
