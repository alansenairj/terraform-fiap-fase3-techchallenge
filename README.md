# ToggleMaster — Infraestrutura (Terraform)

Infraestrutura AWS do ToggleMaster em Terraform. Base para a Fase 4.

Este repositório contém **só a infra**. O resto do sistema vive em outros repositórios:

| Peça | Repositório |
| --- | --- |
| Infra (este) | `alansenairj/terraform-fiap-fase3-techchallenge` |
| Microsserviços + CI | `alansenairj/{auth,flag,targeting,evaluation,analytics}-service` |
| CD (ArgoCD, charts Helm) | `alansenairj/togglemaster-gitops` |

## O que é criado

`environments/dev` (cluster `togglemaster-dev`):

- VPC com subnets públicas/privadas e NAT
- EKS + node group
- 3 RDS PostgreSQL (auth, flag, targeting), ElastiCache Redis, SQS, DynamoDB
- 5 repositórios ECR (tags `IMMUTABLE`)
- OIDC provider do GitHub + role `github-actions` (CI sem chave estática)
- Secrets Manager (4 secrets) + roles IRSA (`eso`, `analytics`, `evaluation`, `keda`)

## Estrutura

```
terraform/
├── bootstrap/            # bucket S3 do state (state local, gitignored)
├── environments/dev/     # composição dos módulos — onde se roda apply
├── modules/              # networking, eks, rds, elasticache, sqs, dynamodb,
│                         # ecr, github-oidc, external-secrets, secrets-manager
├── backend.hcl.example   # copiar para backend.hcl (gitignored)
└── .checkov.yaml         # scan de IaC
```

## Uso

Pré-requisitos: `terraform >= 1.11`, `aws` CLI autenticado, `jq`.

```bash
cd terraform

# 1. Bootstrap (uma vez por conta)
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply
printf 'bucket = "%s"\nregion = "us-east-1"\n' \
  "$(terraform -chdir=bootstrap output -raw state_bucket_name)" > backend.hcl

# 2. Ambiente dev
terraform -chdir=environments/dev init -backend-config=../../backend.hcl
terraform -chdir=environments/dev apply
```

Validação sem criar nada:

```bash
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev validate
uvx checkov -d terraform --compact --quiet
```

## Outputs consumidos fora deste repo

Renomear/remover qualquer um destes quebra o fluxo de deploy.

| Output | Consumidor |
| --- | --- |
| `bootstrap: state_bucket_name` | `backend.hcl`, destroy do bucket |
| `github_actions_role_arn` | variável `AWS_ROLE_ARN` nos 5 repos de serviço |
| `app_secret_arns` | conferência pós-apply |
| `keda_role_arn` | anotação IRSA do `keda-operator` |
| `vpc_id` | checagem de ELB/SG órfão antes do destroy |
| `eso_role_arn`, `analytics_role_arn`, `evaluation_role_arn`, `ecr_repository_urls`, `redis_url`, `sqs_queue_url`, `dynamodb_table_name` | `togglemaster-gitops/scripts/sync-infra-values.sh` |

A lista de repositórios autorizados a assumir a role do GitHub Actions fica em
`environments/dev/variables.tf` (`github_repositories`).

## Destroy

Ordem: recursos fora do Terraform (App of Apps, `ingress-nginx`, KEDA, metrics-server) →
`environments/dev` → `bootstrap` (esvaziar o bucket versionado antes). O `ingress-nginx`
cria ELB + Security Group fora do state; se o cluster sumir antes, o destroy trava na VPC
com `DependencyViolation`.
