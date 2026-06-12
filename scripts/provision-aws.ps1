# Provisiona EC2 + EIP + SG + S3 + IAM para despliegue emergencias.
# Uso: .\scripts\provision-aws.ps1
# Salida: infra/aws-deploy.env con IDs y IP publica.

$ErrorActionPreference = "Stop"
$PrevEap = $ErrorActionPreference
$Region = "us-east-1"
$KeyName = "sw1-examen"
$InstanceType = "m7i-flex.large"
$AmiId = "ami-0c374876b6fc67b33"
$OutFile = Join-Path (Split-Path $PSScriptRoot -Parent) "infra/aws-deploy.env"

function Invoke-Aws {
    param([string[]]$AwsArgs)
    $ErrorActionPreference = "Continue"
    $out = & aws @AwsArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    return @{ Code = $code; Out = $out }
}

function Ensure-Role {
    $roleName = "emergencias-ec2-role"
    $trustFile = (Join-Path (Split-Path $PSScriptRoot -Parent) "infra/ec2-trust-policy.json") -replace '\\', '/'
    $r = Invoke-Aws @("iam", "get-role", "--role-name", $roleName)
    if ($r.Code -ne 0) {
        $c = Invoke-Aws @("iam", "create-role", "--role-name", $roleName, "--assume-role-policy-document", "file://$trustFile")
        if ($c.Code -ne 0) { throw "No se pudo crear IAM role $roleName" }
        Write-Host "IAM role $roleName creado"
    } else {
        Write-Host "IAM role $roleName ya existe"
    }
    Invoke-Aws @("iam", "attach-role-policy", "--role-name", $roleName, "--policy-arn", "arn:aws:iam::aws:policy/AmazonS3FullAccess") | Out-Null
    $profileName = "emergencias-ec2-profile"
    $p = Invoke-Aws @("iam", "get-instance-profile", "--instance-profile-name", $profileName)
    if ($p.Code -ne 0) {
        Invoke-Aws @("iam", "create-instance-profile", "--instance-profile-name", $profileName) | Out-Null
        Start-Sleep -Seconds 10
    }
    Invoke-Aws @("iam", "add-role-to-instance-profile", "--instance-profile-name", $profileName, "--role-name", $roleName) | Out-Null
    return $profileName
}

$VpcId = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text
$ProfileName = Ensure-Role

# Security group
$SgId = aws ec2 describe-security-groups --filters "Name=group-name,Values=emergencias-sg" "Name=vpc-id,Values=$VpcId" --query "SecurityGroups[0].GroupId" --output text
if ($SgId -eq "None" -or -not $SgId) {
    $SgId = aws ec2 create-security-group --group-name emergencias-sg --description "Emergencias Docker stack" --vpc-id $VpcId --query "GroupId" --output text
    foreach ($port in @(22, 80, 8000, 8001)) {
        aws ec2 authorize-security-group-ingress --group-id $SgId --protocol tcp --port $port --cidr 0.0.0.0/0 | Out-Null
    }
    Write-Host "Security group creado: $SgId"
} else {
    Write-Host "Security group existente: $SgId"
}

# S3
try {
    aws s3api head-bucket --bucket emergencias-evidencias 2>$null
    Write-Host "Bucket S3 ya existe"
} catch {
    aws s3 mb "s3://emergencias-evidencias" --region $Region
    Write-Host "Bucket S3 creado"
}

# EC2 existente?
$Existing = aws ec2 describe-instances --filters "Name=tag:Name,Values=emergencias-stack" "Name=instance-state-name,Values=running,pending" --query "Reservations[0].Instances[0].InstanceId" --output text
if ($Existing -and $Existing -ne "None") {
    $InstanceId = $Existing
    Write-Host "Instancia existente: $InstanceId"
} else {
    $UserData = @"
#!/bin/bash
dnf install -y git
"@
    $UserDataB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($UserData))
    $InstanceId = aws ec2 run-instances `
        --image-id $AmiId `
        --instance-type $InstanceType `
        --key-name $KeyName `
        --security-group-ids $SgId `
        --iam-instance-profile "Name=$ProfileName" `
        --block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=30,VolumeType=gp3}" `
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=emergencias-stack}]" `
        --user-data $UserDataB64 `
        --query "Instances[0].InstanceId" --output text
    Write-Host "Instancia lanzada: $InstanceId"
    aws ec2 wait instance-running --instance-ids $InstanceId
}

# Elastic IP
$EipAlloc = aws ec2 describe-addresses --filters "Name=instance-id,Values=$InstanceId" --query "Addresses[0].AllocationId" --output text
if (-not $EipAlloc -or $EipAlloc -eq "None") {
    $EipAlloc = aws ec2 allocate-address --domain vpc --query "AllocationId" --output text
    aws ec2 associate-address --instance-id $InstanceId --allocation-id $EipAlloc | Out-Null
    Write-Host "Elastic IP asociada"
}
$PublicIp = aws ec2 describe-addresses --allocation-ids $EipAlloc --query "Addresses[0].PublicIp" --output text

$envContent = @"
AWS_REGION=$Region
INSTANCE_ID=$InstanceId
SECURITY_GROUP_ID=$SgId
ELASTIC_IP=$PublicIp
KEY_NAME=$KeyName
S3_BUCKET=emergencias-evidencias
"@
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
Set-Content -Path $OutFile -Value $envContent -Encoding UTF8

Write-Host ""
Write-Host "=== Despliegue AWS listo ===" -ForegroundColor Green
Write-Host "Elastic IP: $PublicIp"
Write-Host "Instance:   $InstanceId"
Write-Host "SSH:        ssh -i ~/.ssh/$KeyName.pem ec2-user@$PublicIp"
Write-Host "Config:     $OutFile"
