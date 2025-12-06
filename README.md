# 📘 DevSecOps CI/CD Project – Deployment Guide & Documentation

This document explains how to set up, deploy, and operate the provided **DevSecOps CI/CD pipeline** using:

* **GitHub Actions OIDC → AWS**
* **Terraform (ECR + IAM OIDC role)**
* **EKS Deployment (manifest templating with envsubst)**
* **End-to-end DevSecOps pipeline** including:
  * *SAST (Semgrep)*
  * *Secrets Scanning (Gitleaks)*
  * *Vulnerability Scanning (Trivy FS + Image)*
  * *Container Signing (Cosign)*
  * *Deployment to EKS*

## Project Structure

```
devops-test/
├── Dockerfile
├── main.py
├── run.sh
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── iac/
│   └── terraform/
│       ├── main.tf
│       ├── iam.tf
│       ├── providers.tf
│       ├── backend.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── dev.tfvars
│     
│   
├── scripts/
│   └── security-summary.sh
├── tests/
│   └── test_healthcheck.py
└── .github/workflows/
    └── ci-cd.yaml

```

#### Key Components

| Component                           | Purpose                                                        |
| ----------------------------------- | -------------------------------------------------------------- |
| **Terraform (iac/terraform)** | Creates ECR + IAM OIDC role for GitHub Actions                 |
| **CI/CD (GitHub Actions)**    | Full pipeline including build, test, scanning, signing, deploy |
| **k8s manifests**             | Deployment, Service, Ingress using envsubst variables          |
| **Python app**                | Simple FastAPI/Flask-style healthcheck app                     |
| **Security pipeline**         | SAST, SCA, Secret scan, Signing                                |

## AWS Prerequisites

You must have the following already provisioned:

* AWS Account
* EKS Cluster (public endpoint OK)
* kubectl installed (runner installs automatically)
* ECR & IAM OIDC Role (created automatically by Terraform)
* AWS credentials configured in GitHub Repository Secrets:
  * **AWS_OIDC_ROLE_ARN**
  * **EKS_CLUSTER_NAME**

## Infrastructure Provisioning (Terraform)

Edit `dev.tfvars`:

```
aws_region   = "us-east-1"
project_name = "devops-test"
github_owner  = "triethuynh1408"
github_repo   = "devops-test"
github_branch = "main"

```

Run Terraform:

```
cd iac/terraform

# Initialize
terraform init

# Validate
terraform validate

# Preview changes
terraform plan -var-file=dev.tfvars

# Apply
terraform apply -var-file=dev.tfvars

```

This creates:

- ECR Repository
- GitHub OIDC Identity Provider
- IAM Role for GitHub Actions
- IAM Policy for ECR Push/Pull + EKS Describe, Authentication

 **Note**: The requirement states AWS account and EKS cluster already exist. Terraform here only manages ECR + IAM for CI/CD

Outputs include:

* OIDC Role ARN → must be added to GitHub secret: **AWS_OIDC_ROLE_ARN**

## CI/CD Pipeline Overview

The GitHub Actions workflow is defined in:

`.github/workflows/ci-cd.yaml `

It contains **4 jobs**:

* **build job**
  * Checkout code
  * Install Python dependencies via Poetry
  * Run pytest
  * Build Docker image
  * Push to ECR
  * Export:
    * `image_uri`
    * `image_digest`
    * `image_repo`
* **security job**

    Includes full DevSecOps security workflow:

**
    Security Scanning:** Semgrep (SAST), Gitleaks (secrets scanning), Trivy filesystem scan, Trivy image scan

**
    Artifacts:** SARIF results uploaded to **GitHub Security tab** and **sarif-downloads artifacts**

**
    Container Signing (Cosign Keyless)**


* **summary-report job**

  * Download SARIF reports
  * Run `security-summary.sh`
  * Produce aggregated report
* **deploy job**

  - Configure AWS OIDC
  - Connect to EKS (`aws eks update-kubeconfig`)
  - Export env vars `IMAGE, DEPLOYMENT_NAME, K8S_NAMESPACE, APP_PORT, APP_REGION ... `
  - Namespace creation (if not exists)
  - Apply all manifests using `envsubst < k8s/deployment.yaml | kubectl apply -f - `
  - Wait for rollout `kubectl rollout status deployment/devops-test-app`

### Security Gates - Pipeline Fails on HIGH/CRITICAL Issues

This project strictly enforces security quality.

**HIGH/CRITICAL vulnerabilities cause the pipeline to FAIL.**

Exact steps in workflow:

```
- name: Trivy FS - Fail on HIGH/CRITICAL
  run: |
    trivy fs . \
      --severity HIGH,CRITICAL \
      --ignore-unfixed \
      --exit-code 1 \
      --format table

- name: Trivy Image - Fail on HIGH/CRITICAL
  run: |
    trivy image ${{ needs.build.outputs.image_uri }} \
      --severity HIGH,CRITICAL \
      --ignore-unfixed \
      --exit-code 1 \
      --format table

```

**If any HIGH or CRITICAL vulnerabilities are detected → the pipeline stops immediately** .

## Kubernetes Deployment Overview

**All Kubernetes manifests support dynamic variable injection:**

Example env vars used:

```
DEPLOYMENT_NAME=devops-test-app
K8S_NAMESPACE=dev
IMAGE=<ECR URI>
APP_PORT=3000
APP_REGION=us-east-1
APP_ENV=dev

```

**Deployment includes:**

* containerPort: `${APP_PORT}`
* readinessProbe & livenessProbe on `/healthcheck`
* proper labels & selectors
* imagePullPolicy: IfNotPresent

**Service routes:**

```
port: 80
targetPort: ${APP_PORT}

```

**Ingress (ALB) uses:**

* ACM certificate ARN
* Host: `${APP_HOST}`

## Running the Pipeline

Push code to `main`

This triggers:

1. **build**
2. **security**
3. **summary-report**
4. **deploy**

You can observe each stage in GitHub Actions.

## Verification After Deployment

Check pods:

`kubectl get pods -n dev`

Check service:

`kubectl get svc -n dev`

Check ingress:

`kubectl get ingress -n dev`

Verify application:

`curl https://devops-test-app.example.com/healthcheck`
