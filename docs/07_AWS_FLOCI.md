# 07 — AWS Deployment with Floci (local emulation) → real AWS (parcial)

> **Strategy:** develop and test against **Floci** (a local AWS emulator on `http://localhost:4566`),
> then deploy the *same code* to **real AWS** for the exam. The only difference is the
> `AWS_ENDPOINT_URL` env var (set to Floci locally, **unset** in real AWS).
> Reference: Floci Quick Start — https://floci.io/floci/getting-started/quick-start/

## 1. Why Floci

Floci exposes AWS-compatible APIs locally (S3, SNS, SQS, RDS, ElastiCache, ECR, ECS, Lambda,
EventBridge, CloudFront, Route53, …) on a single endpoint `:4566`, accepting dummy credentials.
Because the AWS SDK (`boto3`, `@aws-sdk`) only needs an endpoint override, your application code
is **identical** for local (Floci) and production (AWS). This lets you rehearse the full AWS
deployment before the parcial with zero cost.

## 2. Service mapping (our stack → AWS → Floci)

| Component | AWS service | Local (Floci) | Notes |
|-----------|-------------|---------------|-------|
| Relational DB | **RDS for PostgreSQL** | Floci RDS *or* the `db` container in compose | Run `database/*.sql` once. |
| Cache / WS pub-sub | **ElastiCache (Redis)** | Floci ElastiCache *or* `redis` container | `REDIS_URL`. |
| Evidence files (photos/audio) | **S3** | Floci S3 | Bucket `S3_BUCKET_EVIDENCIAS`; store key, serve via presigned URL. |
| Backend container image | **ECR** | Floci ECR | `docker push` to the ECR URI. |
| Backend runtime (FastAPI) | **ECS Fargate** (+ ALB) | Floci ECS | Task def with env vars. |
| Angular web (static) | **S3 + CloudFront** | Floci S3/CloudFront | `ng build` → upload `dist/`. |
| Push notifications | **SNS** (or keep FCM) | Floci SNS | Optional; FCM is simpler for mobile. |
| KPI refresh schedule | **EventBridge Scheduler → Lambda** | Floci EventBridge/Lambda | Or `pg_cron` on RDS. |
| Secrets | **Secrets Manager / SSM** | Floci SSM/Secrets | Store JWT secret, Stripe keys. |

> Keep PostgreSQL and Redis as **containers locally** if you prefer (simpler); use Floci for the
> AWS-specific pieces (S3, ECR/ECS, SNS, EventBridge). In real AWS they become RDS + ElastiCache.

## 3. Local environment with Floci

### 3.1 docker-compose.yml (root) — add Floci
```yaml
services:
  floci:
    image: floci/floci:latest
    ports: ["4566:4566"]
    volumes: ["./.floci-data:/app/data"]
  db:
    image: postgres:16
    environment: { POSTGRES_DB: emergencias_db, POSTGRES_PASSWORD: postgres }
    ports: ["5432:5432"]
    volumes:
      - ./database:/docker-entrypoint-initdb.d
      - pgdata:/var/lib/postgresql/data
  redis:
    image: redis:7
    ports: ["6379:6379"]
volumes:
  pgdata:
```

### 3.2 AWS CLI pointing at Floci (dummy creds)
```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
```

### 3.3 Provision local resources — `infra/floci-init.sh`
```bash
#!/usr/bin/env bash
set -e
EP=http://localhost:4566
# S3 bucket for evidence + web hosting
aws s3 mb s3://emergencias-evidencias --endpoint-url $EP
aws s3 mb s3://emergencias-web        --endpoint-url $EP
# SNS topic for push (optional)
aws sns create-topic --name emergencias-push --endpoint-url $EP
# SSM secrets
aws ssm put-parameter --name /emergencias/jwt_secret --type SecureString \
    --value "local-dev-secret" --endpoint-url $EP
echo "Floci resources ready."
```
Run: `bash infra/floci-init.sh`.

### 3.4 Smoke test (per Floci quick start)
```bash
aws s3 ls --endpoint-url http://localhost:4566
echo "hola" | aws s3 cp - s3://emergencias-evidencias/test.txt --endpoint-url http://localhost:4566
aws s3 ls s3://emergencias-evidencias --endpoint-url http://localhost:4566
```

## 4. Backend integration (boto3, endpoint-aware)

### 4.1 Extra deps — add to `backend/requirements.txt`
```
boto3==1.35.*
```

### 4.2 Config additions — `app/core/config.py`
```python
    aws_region: str = "us-east-1"
    aws_endpoint_url: str = ""            # http://localhost:4566 (Floci); "" in real AWS
    aws_access_key_id: str = ""           # "test" local; via IAM role in AWS
    aws_secret_access_key: str = ""
    s3_bucket_evidencias: str = "emergencias-evidencias"
    sns_topic_push: str = ""              # arn or name; optional
```

### 4.3 AWS client factory — `app/core/aws.py`
```python
import boto3
from .config import settings

def aws_client(service: str):
    kwargs = {"region_name": settings.aws_region}
    if settings.aws_endpoint_url:                 # Floci local
        kwargs["endpoint_url"] = settings.aws_endpoint_url
        kwargs["aws_access_key_id"] = settings.aws_access_key_id or "test"
        kwargs["aws_secret_access_key"] = settings.aws_secret_access_key or "test"
    # In real AWS, omit creds → boto3 uses the ECS task IAM role automatically.
    return boto3.client(service, **kwargs)

s3 = lambda: aws_client("s3")
sns = lambda: aws_client("sns")
```

### 4.4 Evidence upload to S3 — replaces local file storage (doc 01 §4.5)
```python
import uuid
from ..core.aws import s3
from ..core.config import settings

def upload_evidencia(tenant_id: str, incidente_id: str, file_bytes: bytes, content_type: str) -> str:
    key = f"{tenant_id}/{incidente_id}/{uuid.uuid4()}"
    s3().put_object(Bucket=settings.s3_bucket_evidencias, Key=key,
                    Body=file_bytes, ContentType=content_type)
    return key            # store this in evidencia.url

def presign(key: str, seconds: int = 3600) -> str:
    return s3().generate_presigned_url("get_object",
        Params={"Bucket": settings.s3_bucket_evidencias, "Key": key}, ExpiresIn=seconds)
```
`POST /incidentes/{id}/evidencias` now: read multipart `file` → `upload_evidencia(...)` → insert
`evidencia(url=key, tipo, mime_type, tamano_bytes)`. When returning evidence to clients, wrap the
key with `presign(key)`. The AI pipeline downloads via the presigned URL.

### 4.5 Push via SNS (optional alternative to FCM)
```python
from ..core.aws import sns
def push_sns(message: str, target_arn: str):
    sns().publish(TargetArn=target_arn, Message=message)
```

### 4.6 Env files
`backend/.env` (local with Floci):
```
AWS_ENDPOINT_URL=http://localhost:4566
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
S3_BUCKET_EVIDENCIAS=emergencias-evidencias
```
Production (real AWS) — **do not set `AWS_ENDPOINT_URL`**; provide region only and let the ECS task role supply credentials.

## 5. Deploy to real AWS for the parcial

Everything below also works against Floci by adding `--endpoint-url $AWS_ENDPOINT_URL` — rehearse locally first, then drop the flag for AWS.

### 5.1 Database — RDS PostgreSQL
```bash
aws rds create-db-instance \
  --db-instance-identifier emergencias-db \
  --engine postgres --engine-version 16 \
  --db-instance-class db.t3.micro --allocated-storage 20 \
  --master-username postgres --master-user-password '<STRONG_PW>' \
  --publicly-accessible
# wait until available, get endpoint:
aws rds describe-db-instances --db-instance-identifier emergencias-db \
  --query 'DBInstances[0].Endpoint.Address' --output text
# load schema:
psql "postgresql://postgres:<PW>@<rds-endpoint>:5432/postgres" -c "CREATE DATABASE emergencias_db;"
psql "postgresql://postgres:<PW>@<rds-endpoint>:5432/emergencias_db" -f database/01_schema.sql
psql ".../emergencias_db" -f database/02_views_kpi.sql
psql ".../emergencias_db" -f database/03_seed.sql
psql ".../emergencias_db" -c "CREATE ROLE app_admin LOGIN PASSWORD '<PW>' BYPASSRLS; GRANT ALL ON SCHEMA emergencias TO app_admin; GRANT ALL ON ALL TABLES IN SCHEMA emergencias TO app_admin;"
```
> RDS PostgreSQL supports `pg_cron` (enable in a custom parameter group) to schedule
> `SELECT emergencias.refrescar_kpis();` every 15 min — or use EventBridge + Lambda (§5.6).

### 5.2 Cache — ElastiCache Redis
```bash
aws elasticache create-cache-cluster --cache-cluster-id emergencias-redis \
  --engine redis --cache-node-type cache.t3.micro --num-cache-nodes 1
# REDIS_URL = redis://<elasticache-endpoint>:6379/0
```

### 5.3 S3 buckets
```bash
aws s3 mb s3://emergencias-evidencias
aws s3 mb s3://emergencias-web
```

### 5.4 Backend image → ECR
```bash
aws ecr create-repository --repository-name emergencias-api
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
URI=$ACCOUNT.dkr.ecr.$REGION.amazonaws.com/emergencias-api
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
docker build -t emergencias-api ./backend
docker tag emergencias-api:latest $URI:latest
docker push $URI:latest
```

### 5.5 Backend runtime — ECS Fargate (+ ALB)
1. Create cluster: `aws ecs create-cluster --cluster-name emergencias`.
2. Register a **task definition** (`infra/ecs-taskdef.json`) with container `emergencias-api`, port 8000, and env vars: `DATABASE_URL`, `DATABASE_URL_ADMIN`, `REDIS_URL`, `JWT_SECRET`, `S3_BUCKET_EVIDENCIAS`, `STRIPE_*`, `AWS_REGION` (no `AWS_ENDPOINT_URL`). Attach a **task IAM role** allowing `s3:*` on the bucket and `sns:Publish`.
3. Create a **service** behind an **Application Load Balancer** (health check `/health`), desired count ≥1.
4. The ALB DNS becomes your public API URL → set web/mobile to `https://<alb>/...`.

`infra/ecs-taskdef.json` (skeleton):
```json
{
  "family": "emergencias-api",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512", "memory": "1024",
  "executionRoleArn": "arn:aws:iam::<acct>:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::<acct>:role/emergenciasTaskRole",
  "containerDefinitions": [{
    "name": "emergencias-api",
    "image": "<acct>.dkr.ecr.us-east-1.amazonaws.com/emergencias-api:latest",
    "portMappings": [{ "containerPort": 8000 }],
    "environment": [
      { "name": "DATABASE_URL", "value": "postgresql+psycopg2://postgres:<pw>@<rds>:5432/emergencias_db" },
      { "name": "REDIS_URL", "value": "redis://<elasticache>:6379/0" },
      { "name": "S3_BUCKET_EVIDENCIAS", "value": "emergencias-evidencias" },
      { "name": "AWS_REGION", "value": "us-east-1" }
    ]
  }]
}
```
Register + run:
```bash
aws ecs register-task-definition --cli-input-json file://infra/ecs-taskdef.json
aws ecs create-service --cluster emergencias --service-name api \
  --task-definition emergencias-api --desired-count 1 --launch-type FARGATE \
  --network-configuration '{"awsvpcConfiguration":{"subnets":["subnet-..."],"securityGroups":["sg-..."],"assignPublicIp":"ENABLED"}}'
```

### 5.6 KPI refresh — EventBridge Scheduler + Lambda (if not using pg_cron)
```bash
# Lambda that connects to RDS and runs SELECT emergencias.refrescar_kpis();
aws lambda create-function --function-name refrescar-kpis --runtime python3.12 \
  --handler app.handler --zip-file fileb://infra/lambda_kpis.zip --role arn:aws:iam::<acct>:role/lambdaRdsRole
aws scheduler create-schedule --name kpis-15min \
  --schedule-expression "rate(15 minutes)" \
  --target '{"Arn":"arn:aws:lambda:us-east-1:<acct>:function:refrescar-kpis","RoleArn":"arn:aws:iam::<acct>:role/schedulerRole"}' \
  --flexible-time-window '{"Mode":"OFF"}'
```

### 5.7 Web (Angular) — S3 static + CloudFront
```bash
cd web && ng build --configuration production
aws s3 sync dist/web/browser s3://emergencias-web --delete
aws s3 website s3://emergencias-web --index-document index.html
# Front with CloudFront for HTTPS; the CloudFront domain is the public web URL.
```
Set `environment.prod.ts` `apiUrl`/`wsUrl` to the ALB `https`/`wss` URL **before** building.

### 5.8 Mobile (Flutter) — APK against the ALB
```bash
cd mobile && flutter build apk --release \
  --dart-define=API_URL=https://<alb-dns> \
  --dart-define=WS_URL=wss://<alb-dns>
```
Upload the APK to S3 (`emergencias-web/app-release.apk`) or Drive → make a QR for the public link.

## 6. Local-vs-AWS parity checklist (rehearse before the parcial)
- [ ] `docker compose up -d` starts Floci, db, redis.
- [ ] `bash infra/floci-init.sh` creates S3 bucket + SNS topic on Floci.
- [ ] Backend with `AWS_ENDPOINT_URL=http://localhost:4566` uploads evidence to Floci S3 and serves presigned URLs.
- [ ] Same image pushed to Floci ECR runs on Floci ECS (`aws ecs ... --endpoint-url $AWS_ENDPOINT_URL`).
- [ ] Remove `AWS_ENDPOINT_URL` → identical code talks to real AWS (RDS, ElastiCache, S3, ECS).
- [ ] Public ALB `/health` returns 200; web (CloudFront) and APK point to it.

## 7. What goes in the PDF (AWS section)
- Architecture diagram annotated with AWS services (ECS Fargate, RDS, ElastiCache, S3, CloudFront, ALB, EventBridge).
- Note that local development uses **Floci** to emulate these services (cite the tool) and the same artifacts deploy to AWS by removing `AWS_ENDPOINT_URL`.
- Screenshots: S3 bucket with evidence objects, ECS service running, RDS instance, the public ALB/CloudFront URLs.
