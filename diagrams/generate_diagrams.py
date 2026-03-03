"""
Generate architecture diagrams for marciobolsoni.cloud GitOps CI/CD Suite
Using the 'diagrams' Python library (Graphviz-based)
"""

import os
os.chdir("/home/ubuntu/marciobolsoni-cloud-devops/diagrams")

from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECS, Fargate, ECR
from diagrams.aws.network import ALB, Route53, CloudFront, NATGateway
from diagrams.aws.devtools import Codebuild, Codepipeline, Codedeploy, Codecommit
from diagrams.aws.storage import S3
from diagrams.aws.database import RDS, ElastiCache
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import IAM, SecretsManager, WAF, KMS
from diagrams.aws.integration import SNS
from diagrams.aws.general import User
from diagrams.onprem.vcs import Github
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.iac import Terraform
from diagrams.programming.flowchart import Decision, Action, StartEnd

# ─────────────────────────────────────────────
# Diagram 1: Full CI/CD Pipeline Overview
# ─────────────────────────────────────────────
graph_attr = {
    "fontsize": "14",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
    "nodesep": "0.8",
    "ranksep": "1.0",
}

with Diagram(
    "GitOps CI/CD Pipeline — marciobolsoni.cloud",
    filename="01-cicd-pipeline",
    outformat="png",
    show=False,
    graph_attr=graph_attr,
    direction="LR",
):
    dev = Github("Developer\nPush / PR")

    with Cluster("GitHub Actions — CI"):
        lint = GithubActions("Lint &\nStatic Analysis")
        test = GithubActions("Unit &\nIntegration Tests")
        scan = GithubActions("Security Scan\n(Trivy/Snyk)")
        build = GithubActions("Docker Build\n& Push to ECR")
        tf_plan = GithubActions("Terraform Plan\n(PR Comment)")

    with Cluster("AWS CodeSuite"):
        ecr = ECR("Amazon ECR\nContainer Registry")
        cb = Codebuild("CodeBuild\nArtifact Build")
        cp = Codepipeline("CodePipeline\nOrchestration")
        cd = Codedeploy("CodeDeploy\nCanary Controller")

    with Cluster("AWS Infrastructure"):
        with Cluster("ECS Fargate Cluster"):
            blue = Fargate("Blue\n(Stable)")
            green = Fargate("Green\n(Canary)")
        alb = ALB("Application\nLoad Balancer")
        cw = Cloudwatch("CloudWatch\nAlarms")
        s3 = S3("S3 Artifacts\n& TF State")

    with Cluster("Notifications"):
        sns = SNS("SNS Topic")

    dev >> lint >> test >> scan >> build >> ecr
    build >> tf_plan
    ecr >> cb >> cp >> cd
    cd >> Edge(label="10%→100%") >> green
    cd >> Edge(label="stable") >> blue
    blue >> alb
    green >> alb
    alb >> cw
    cw >> Edge(label="alarm breach", color="red") >> cd
    cd >> sns
    s3 >> cp

print("✅ Diagram 1: CI/CD Pipeline generated")

# ─────────────────────────────────────────────
# Diagram 2: AWS Infrastructure Architecture
# ─────────────────────────────────────────────
with Diagram(
    "AWS Infrastructure — marciobolsoni.cloud",
    filename="03-aws-infrastructure",
    outformat="png",
    show=False,
    graph_attr={**graph_attr, "splines": "curved"},
    direction="TB",
):
    users = User("End Users\nmarciobolsoni.cloud")

    with Cluster("Edge Layer"):
        cf = CloudFront("CloudFront CDN")
        waf = WAF("AWS WAF")
        r53 = Route53("Route 53\nDNS")

    with Cluster("AWS VPC — 10.0.0.0/16"):
        with Cluster("Public Subnets"):
            alb = ALB("Application\nLoad Balancer")
            nat = NATGateway("NAT Gateway")

        with Cluster("Private Subnets — ECS Fargate Cluster"):
            blue = Fargate("Blue Task Set\n(Production)")
            green = Fargate("Green Task Set\n(Canary)")

        with Cluster("Data Subnets"):
            rds = RDS("RDS PostgreSQL\nMulti-AZ")
            redis = ElastiCache("ElastiCache\nRedis")

    with Cluster("CI/CD Infrastructure"):
        ecr = ECR("ECR\nContainer Registry")
        cb = Codebuild("CodeBuild")
        cp = Codepipeline("CodePipeline")
        cd = Codedeploy("CodeDeploy")

    with Cluster("Observability"):
        cw_logs = Cloudwatch("CloudWatch\nLogs")
        cw_alarms = Cloudwatch("CloudWatch\nAlarms")

    with Cluster("Security"):
        iam = IAM("IAM Roles\n(OIDC)")
        sm = SecretsManager("Secrets\nManager")
        kms = KMS("KMS\nEncryption")

    with Cluster("Storage"):
        s3_art = S3("S3 Artifacts")
        s3_tf = S3("S3 TF State")

    sns = SNS("SNS\nNotifications")

    users >> cf >> waf >> r53 >> alb
    alb >> Edge(label="90%") >> blue
    alb >> Edge(label="10% canary", color="orange") >> green
    blue >> rds
    green >> rds
    blue >> redis
    blue >> sm
    green >> sm

    ecr >> cb >> cp >> cd >> alb
    cd >> cw_alarms
    cw_alarms >> Edge(label="rollback", color="red") >> cd
    cd >> sns

    blue >> cw_logs
    green >> cw_logs
    cw_logs >> cw_alarms

    iam >> [blue, green, cb, cp, cd]
    kms >> [ecr, s3_art, sm]

print("✅ Diagram 2: AWS Infrastructure generated")

# ─────────────────────────────────────────────
# Diagram 3: Canary Deployment Flow
# ─────────────────────────────────────────────
with Diagram(
    "Canary Deployment & Rollback Flow — marciobolsoni.cloud",
    filename="02-canary-deployment",
    outformat="png",
    show=False,
    graph_attr={**graph_attr, "splines": "ortho", "ranksep": "1.2"},
    direction="TB",
):
    trigger = GithubActions("Merge to\nmain/staging")

    with Cluster("Pre-Deployment"):
        health = GithubActions("Health Check\nProduction")
        smoke = GithubActions("Smoke Tests\nStaging")
        approve = GithubActions("Manual Approval\n(Prod only)")

    with Cluster("CodeDeploy — Deployment Init"):
        task_def = ECS("Register New\nTask Definition")
        create_set = Fargate("Create Green\nTask Set")

    with Cluster("Canary Traffic Shifting"):
        c10 = ALB("10% Traffic\nto Green")
        wait1 = Cloudwatch("Observe 5min\nWindow")
        c50 = ALB("50% Traffic\nto Green")
        wait2 = Cloudwatch("Observe 5min\nWindow")
        c100 = ALB("100% Traffic\nto Green")

    with Cluster("Validation"):
        e2e = GithubActions("E2E Tests\nSynthetic Canary")
        perf = Cloudwatch("Performance\nBaseline Check")

    with Cluster("Success Path"):
        terminate = Fargate("Terminate Blue\nTask Set")
        tag_rel = Github("Git Tag\nRelease v{semver}")
        notify_ok = SNS("Notify ✅\nSlack + Email")

    with Cluster("Rollback Path"):
        rb_trigger = Cloudwatch("Alarm BREACH\nDetected")
        shift_back = ALB("Shift 100%\nBack to Blue")
        stop_green = Fargate("Stop Green\nTask Set")
        rb_notify = SNS("Notify 🚨\nRollback Alert")
        rb_issue = Github("Create GitHub\nIncident Issue")

    trigger >> health >> smoke >> approve >> task_def >> create_set
    create_set >> c10 >> wait1 >> c50 >> wait2 >> c100
    c100 >> e2e >> perf >> terminate >> tag_rel >> notify_ok

    wait1 >> Edge(label="alarm breach", color="red", style="dashed") >> rb_trigger
    wait2 >> Edge(label="alarm breach", color="red", style="dashed") >> rb_trigger
    perf >> Edge(label="alarm breach", color="red", style="dashed") >> rb_trigger

    rb_trigger >> shift_back >> stop_green >> rb_notify >> rb_issue

print("✅ Diagram 3: Canary Deployment generated")
print("\n🎉 All diagrams generated successfully!")
