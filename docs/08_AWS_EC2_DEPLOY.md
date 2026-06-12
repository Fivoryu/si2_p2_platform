# 08 — Despliegue AWS inmediato (EC2 + Docker Compose)

Stack completo en una instancia EC2: backend, web, AcquireMock, OSRM, PostgreSQL, Redis y S3 real.

Complementa [`07_AWS_FLOCI.md`](07_AWS_FLOCI.md) (ECS/RDS) para un despliegue rápido que replica el `docker-compose.yml` local.

## 1. Prerrequisitos

- Cuenta AWS con CLI configurada (`aws sts get-caller-identity`)
- Repos publicados en GitHub (4 repos — ver [`MULTI_REPO.md`](MULTI_REPO.md))
- Key pair EC2 para SSH

## 2. Infraestructura AWS

### 2.1 IAM role para EC2 (S3)

```bash
aws iam create-role --role-name emergencias-ec2-role \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

aws iam attach-role-policy --role-name emergencias-ec2-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam create-instance-profile --instance-profile-name emergencias-ec2-profile
aws iam add-role-to-instance-profile --instance-profile-name emergencias-ec2-profile \
  --role-name emergencias-ec2-role
```

### 2.2 Security group

```bash
aws ec2 create-security-group --group-name emergencias-sg --description "Emergencias stack"
# Reemplaza sg-XXX y tu IP
aws ec2 authorize-security-group-ingress --group-id sg-XXX --protocol tcp --port 22 --cidr TU_IP/32
aws ec2 authorize-security-group-ingress --group-id sg-XXX --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-XXX --protocol tcp --port 8000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-XXX --protocol tcp --port 8001 --cidr 0.0.0.0/0
```

### 2.3 EC2 + Elastic IP

```bash
# AMI Amazon Linux 2023 (ajusta según región)
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t3.large \
  --key-name TU_KEY \
  --security-group-ids sg-XXX \
  --iam-instance-profile Name=emergencias-ec2-profile \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]'

aws ec2 allocate-address --domain vpc
aws ec2 associate-address --instance-id i-XXX --allocation-id eipalloc-XXX
```

### 2.4 S3

```bash
aws s3 mb s3://emergencias-evidencias
```

## 3. Deploy en EC2

```bash
ssh -i tu-key.pem ec2-user@<ELASTIC_IP>

git clone --recurse-submodules https://github.com/Fivoryu/si2_p2_platform.git
cd si2_p2_platform
git clone https://github.com/ashfromsky/acquiremock.git infra/acquiremock

cp .env.aws.example .env.aws
nano .env.aws   # PUBLIC_HOST, JWT_SECRET, ACQUIREMOCK_WEBHOOK_SECRET

# Firebase (opcional, SCP desde tu máquina):
# scp -i tu-key.pem backend/secrets/firebase-service-account.json ec2-user@IP:~/si2_p2_platform/backend/secrets/

bash scripts/deploy-aws-ec2.sh
```

Para omitir descarga OSRM (usa fallback público):

```bash
SKIP_OSRM=1 bash scripts/deploy-aws-ec2.sh
```

## 4. URLs y verificación

| Servicio | URL |
|----------|-----|
| Web | `http://<ELASTIC_IP>` |
| API | `http://<ELASTIC_IP>:8000/docs` |
| AcquireMock | `http://<ELASTIC_IP>:8001` |

```bash
curl http://localhost:8000/health
curl http://localhost:8001/health
curl -I http://localhost:80
```

### Flujos integrados

- **Pagos:** registro plan → AcquireMock `:8001` → webhook interno → tenant creado
- **OSRM:** asignación con ruta real (mapa Bolivia en `osrm-data/`)
- **S3:** evidencias con presigned URLs (IAM role, sin `AWS_ENDPOINT_URL`)

## 5. Mobile APK

```powershell
cd mobile
flutter build apk --release `
  --dart-define=API_URL=http://<ELASTIC_IP>:8000 `
  --dart-define=WS_URL=ws://<ELASTIC_IP>:8000
```

## 6. Push de los 4 repos (desde Windows)

```powershell
.\scripts\push-all-repos.ps1 -Message "feat: despliegue AWS EC2"
```

## 7. Actualizar despliegue

```bash
cd ~/si2_p2_platform
git pull --recurse-submodules
docker compose -f docker-compose.yml -f docker-compose.aws.yml --env-file .env.aws up -d --build
```
