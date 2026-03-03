# Architecture Deep Dive — marciobolsoni.cloud

This document provides a detailed examination of the infrastructure, CI/CD pipelines, and design philosophy for the **marciobolsoni.cloud** GitOps project. 

## 1. Core Architectural Principles

The entire system is built upon a foundation of modern DevOps and cloud-native principles to ensure robustness, scalability, and maintainability.

| Principle | Description |
| :--- | :--- |
| **GitOps as the Source of Truth** | The Git repository is the single source of truth. All changes to infrastructure and application code are managed through pull requests, providing a complete audit trail and enabling declarative state management. |
| **Infrastructure as Code (IaC)** | The entire AWS infrastructure is defined declaratively using Terraform. This ensures consistency, repeatability, and prevents configuration drift across environments. |
| **Immutable Infrastructure** | Instead of modifying running containers, we deploy new, immutable Docker images. This simplifies deployments and rollbacks, and enhances security. |
| **Automation at Every Step** | From linting and testing to deployment and rollback, every possible step is automated. This reduces human error, increases deployment velocity, and frees up developers to focus on building features. |
| **Security by Design** | Security is integrated into every layer of the stack, from CI pipeline scans (SAST, DAST, IaC scanning) to runtime security (least-privilege IAM, encryption, network segmentation). |
| **Deep Observability** | The system is designed to be highly observable, with structured logging, detailed metrics, and pre-configured dashboards to provide immediate insight into application health and deployment status. |

## 2. CI/CD Pipeline Architecture

The pipeline is a hybrid model leveraging the strengths of both GitHub Actions for CI and pre-deployment stages, and AWS CodeSuite (CodeDeploy) for sophisticated deployment orchestration.

![CI/CD Pipeline](images/01-cicd-pipeline.png)

### Workflow Breakdown

1.  **Pull Request (CI)**: When a developer opens a pull request, the `ci.yml` workflow is triggered. This workflow is responsible for:
    *   **Linting & Static Analysis**: Running `ESLint` for code quality and `TFLint`/`Checkov` for IaC validation and security.
    *   **Testing**: Executing unit and integration tests.
    *   **Security Scanning**: Using `Trivy` and `Snyk` to scan for vulnerabilities in code and dependencies.
    *   **Docker Build**: Building the application's Docker image.
    *   **Terraform Plan**: Generating a Terraform plan for each environment and posting it as a comment on the PR for review.

2.  **Merge to `staging` (CD)**: Merging to the `staging` branch triggers the `cd-staging.yml` workflow. This pipeline automatically deploys the new version to the staging environment using the full canary process.

3.  **Merge to `main` (CD)**: Merging to the `main` branch triggers the `cd-production.yml` workflow. This is the path to production and includes a critical **manual approval gate** where a designated approver must authorize the deployment to proceed.

### GitHub Actions & AWS OIDC Integration

To avoid storing long-lived AWS access keys as GitHub secrets, we use OpenID Connect (OIDC). This allows GitHub Actions to assume a temporary, short-lived role in AWS.

-   An **IAM OIDC Identity Provider** is configured in AWS to trust GitHub's OIDC provider.
-   An **IAM Role** is created with a trust policy that allows the GitHub repository to assume it.
-   The GitHub Actions workflows use the `aws-actions/configure-aws-credentials` action to exchange a JWT from GitHub for temporary AWS credentials.

## 3. AWS Infrastructure Deep Dive

The infrastructure is designed for high availability, security, and scalability, using a modular approach with Terraform.

![AWS Infrastructure](images/03-aws-infrastructure.png)

### Networking (VPC)

-   **VPC**: A single VPC with a `/16` CIDR block provides the network boundary.
-   **Subnets**: The VPC is divided into three tiers of subnets across two Availability Zones (AZs) for high availability:
    *   **Public Subnets**: Contain the Application Load Balancer and NAT Gateways. Resources here are directly accessible from the internet.
    *   **Private Subnets**: Host the ECS Fargate tasks. These tasks are not directly accessible from the internet and route outbound traffic through the NAT Gateways.
    *   **Data Subnets**: Isolate the RDS database and ElastiCache instances, with strict network ACLs allowing traffic only from the private subnets.

### Container Orchestration (ECS Fargate)

-   **ECS Fargate**: We use Fargate as the launch type to run containers without managing the underlying EC2 instances. This reduces operational overhead.
-   **ECS Cluster**: A logical grouping for our services.
-   **ECS Service**: Maintains the desired number of tasks and handles service discovery. It is configured to use the `CODE_DEPLOY` deployment controller.
-   **Task Definition**: A blueprint for the application task, specifying the Docker image, CPU/memory, IAM roles, and logging configuration.
-   **Auto Scaling**: The ECS service is configured with target tracking policies to automatically scale the number of tasks based on CPU and memory utilization.

### Deployment Strategy (CodeDeploy)

We employ a blue/green deployment strategy orchestrated by AWS CodeDeploy, with a canary release pattern.

![Canary Deployment Flow](images/02-canary-deployment.png)

1.  **Deployment Start**: CodeDeploy creates a new "green" task set with the new application version.
2.  **Traffic Shifting**: The Application Load Balancer's test listener is used to route a small percentage of traffic (e.g., 10%) to the green task set.
3.  **Observation & Validation**: During this canary phase, automated tests run and CloudWatch alarms are monitored closely.
4.  **Automated Rollback**: If any of the pre-configured CloudWatch alarms (e.g., high error rate, increased latency) enter an `ALARM` state, CodeDeploy automatically and immediately shifts 100% of the traffic back to the stable "blue" task set and stops the deployment.
5.  **Full Rollout**: If the canary phase is successful, CodeDeploy proceeds to shift the remaining traffic until 100% is on the green task set. The old blue task set is then terminated.

### Observability (CloudWatch)

-   **Logs**: All application and ECS logs are sent to CloudWatch Logs for centralized storage and analysis.
-   **Metrics**: We use a combination of standard AWS metrics (ALB, ECS, RDS) and Container Insights for detailed performance data.
-   **Alarms**: A set of critical alarms are configured to monitor the health of the application. These alarms are the triggers for the automated rollback mechanism.
-   **Dashboard**: A dedicated CloudWatch Dashboard provides a single-pane-of-glass view of deployment health, showing key metrics and alarm statuses.

## 4. Security Posture

-   **IAM**: We follow the principle of least privilege. Specific IAM roles are created for the ECS task execution, the task itself, CodeDeploy, and GitHub Actions, each with narrowly defined permissions.
-   **Encryption**: All data is encrypted at rest and in transit. AWS KMS is used to manage encryption keys for S3, RDS, and ECR.
-   **Secrets Management**: Application secrets (e.g., database URLs) are stored in AWS Secrets Manager and injected into the container at runtime. They are never stored in the Git repository.
-   **Vulnerability Scanning**: The CI pipeline includes multiple scanning steps:
    *   **Snyk/npm audit**: Scans for vulnerabilities in third-party dependencies.
    *   **Trivy**: Scans the final Docker image for OS and library vulnerabilities.
    *   **Checkov**: Scans Terraform code for security misconfigurations.
