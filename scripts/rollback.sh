#!/usr/bin/env bash
###############################################################################
# rollback.sh — Automated & Manual Rollback Engine
# marciobolsoni.cloud GitOps CI/CD Suite
#
# Usage:
#   ./rollback.sh \
#     --environment <prod|staging> \
#     --cluster <ecs-cluster-name> \
#     --service <ecs-service-name> \
#     --codedeploy-app <app-name> \
#     --codedeploy-group <group-name> \
#     [--rollback-type <previous-deployment|specific-task-def|specific-image-tag>] \
#     [--target-value <task-def-arn|image-tag>] \
#     [--deployment-id <codedeploy-deployment-id>] \
#     [--reason <reason-string>]
###############################################################################

set -euo pipefail

# ─── Color Output ───────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }

# ─── Defaults ───────────────────────────────────────────────────────────────
ENVIRONMENT=""
ECS_CLUSTER=""
ECS_SERVICE=""
CODEDEPLOY_APP=""
CODEDEPLOY_GROUP=""
ROLLBACK_TYPE="previous-deployment"
TARGET_VALUE=""
DEPLOYMENT_ID=""
REASON="Automated rollback"
AWS_REGION="${AWS_REGION:-us-east-1}"

# ─── Argument Parsing ───────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment)       ENVIRONMENT="$2";       shift 2 ;;
    --cluster)           ECS_CLUSTER="$2";       shift 2 ;;
    --service)           ECS_SERVICE="$2";       shift 2 ;;
    --codedeploy-app)    CODEDEPLOY_APP="$2";    shift 2 ;;
    --codedeploy-group)  CODEDEPLOY_GROUP="$2";  shift 2 ;;
    --rollback-type)     ROLLBACK_TYPE="$2";     shift 2 ;;
    --target-value)      TARGET_VALUE="$2";      shift 2 ;;
    --deployment-id)     DEPLOYMENT_ID="$2";     shift 2 ;;
    --reason)            REASON="$2";            shift 2 ;;
    *) log_error "Unknown argument: $1"; exit 1 ;;
  esac
done

# ─── Validation ─────────────────────────────────────────────────────────────
[[ -z "$ENVIRONMENT" ]]    && { log_error "--environment is required"; exit 1; }
[[ -z "$ECS_CLUSTER" ]]    && { log_error "--cluster is required"; exit 1; }
[[ -z "$ECS_SERVICE" ]]    && { log_error "--service is required"; exit 1; }
[[ -z "$CODEDEPLOY_APP" ]] && { log_error "--codedeploy-app is required"; exit 1; }
[[ -z "$CODEDEPLOY_GROUP" ]] && { log_error "--codedeploy-group is required"; exit 1; }

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  🔄 ROLLBACK ENGINE — marciobolsoni.cloud"
echo "═══════════════════════════════════════════════════════════"
log_info "Environment  : ${ENVIRONMENT}"
log_info "ECS Cluster  : ${ECS_CLUSTER}"
log_info "ECS Service  : ${ECS_SERVICE}"
log_info "Rollback Type: ${ROLLBACK_TYPE}"
log_info "Reason       : ${REASON}"
log_info "Timestamp    : $(date -u)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ─── Step 1: Stop any in-progress CodeDeploy deployment ─────────────────────
log_info "Step 1: Checking for in-progress CodeDeploy deployments..."

IN_PROGRESS_DEPLOY=$(aws deploy list-deployments \
  --application-name "${CODEDEPLOY_APP}" \
  --deployment-group-name "${CODEDEPLOY_GROUP}" \
  --include-only-statuses InProgress \
  --query 'deployments[0]' \
  --output text \
  --region "${AWS_REGION}" 2>/dev/null || echo "None")

if [[ "${IN_PROGRESS_DEPLOY}" != "None" && "${IN_PROGRESS_DEPLOY}" != "null" && -n "${IN_PROGRESS_DEPLOY}" ]]; then
  log_warn "Found in-progress deployment: ${IN_PROGRESS_DEPLOY}"
  log_info "Stopping in-progress deployment..."
  aws deploy stop-deployment \
    --deployment-id "${IN_PROGRESS_DEPLOY}" \
    --auto-rollback-enabled \
    --region "${AWS_REGION}"
  log_success "In-progress deployment stopped with auto-rollback"
  
  # Wait for rollback to complete
  log_info "Waiting for CodeDeploy rollback to complete..."
  aws deploy wait deployment-successful \
    --deployment-id "${IN_PROGRESS_DEPLOY}" \
    --region "${AWS_REGION}" || true
else
  log_info "No in-progress deployments found"
fi

# ─── Step 2: Determine rollback target ──────────────────────────────────────
log_info "Step 2: Determining rollback target..."

case "${ROLLBACK_TYPE}" in
  previous-deployment)
    log_info "Finding last successful deployment..."
    LAST_SUCCESSFUL=$(aws deploy list-deployments \
      --application-name "${CODEDEPLOY_APP}" \
      --deployment-group-name "${CODEDEPLOY_GROUP}" \
      --include-only-statuses Succeeded \
      --query 'deployments[0]' \
      --output text \
      --region "${AWS_REGION}")
    
    if [[ -z "${LAST_SUCCESSFUL}" || "${LAST_SUCCESSFUL}" == "None" ]]; then
      log_error "No previous successful deployment found"
      exit 1
    fi
    
    log_info "Last successful deployment: ${LAST_SUCCESSFUL}"
    ROLLBACK_TASK_DEF=$(aws deploy get-deployment \
      --deployment-id "${LAST_SUCCESSFUL}" \
      --query 'deploymentInfo.revision.revisionType' \
      --output text \
      --region "${AWS_REGION}")
    log_info "Rollback target deployment: ${LAST_SUCCESSFUL}"
    ;;
    
  specific-task-def)
    [[ -z "${TARGET_VALUE}" ]] && { log_error "--target-value (task def ARN) is required for specific-task-def rollback"; exit 1; }
    log_info "Rolling back to task definition: ${TARGET_VALUE}"
    ROLLBACK_TASK_DEF="${TARGET_VALUE}"
    ;;
    
  specific-image-tag)
    [[ -z "${TARGET_VALUE}" ]] && { log_error "--target-value (image tag) is required for specific-image-tag rollback"; exit 1; }
    log_info "Rolling back to image tag: ${TARGET_VALUE}"
    ;;
esac

# ─── Step 3: Execute rollback via ECS service update ────────────────────────
log_info "Step 3: Executing rollback via ECS service force-new-deployment..."

if [[ "${ROLLBACK_TYPE}" == "specific-image-tag" ]]; then
  # Get current task definition and update image
  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --query 'services[0].taskDefinition' \
    --output text \
    --region "${AWS_REGION}")
  
  log_info "Current task definition: ${CURRENT_TASK_DEF}"
  
  # Get ECR repository URI
  ECR_REPO=$(aws ecs describe-task-definition \
    --task-definition "${CURRENT_TASK_DEF}" \
    --query 'taskDefinition.containerDefinitions[0].image' \
    --output text \
    --region "${AWS_REGION}" | cut -d: -f1)
  
  NEW_IMAGE="${ECR_REPO}:${TARGET_VALUE}"
  log_info "New image: ${NEW_IMAGE}"
fi

# Force new deployment to trigger ECS service stabilization
aws ecs update-service \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --force-new-deployment \
  --region "${AWS_REGION}" \
  --output text > /dev/null

log_success "ECS service update triggered"

# ─── Step 4: Wait for service stability ─────────────────────────────────────
log_info "Step 4: Waiting for ECS service to stabilize..."

aws ecs wait services-stable \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --region "${AWS_REGION}"

log_success "ECS service is stable"

# ─── Step 5: Health verification ────────────────────────────────────────────
log_info "Step 5: Verifying service health post-rollback..."

sleep 30

if [[ "${ENVIRONMENT}" == "production" ]]; then
  HEALTH_URL="https://marciobolsoni.cloud/health"
else
  HEALTH_URL="https://staging.marciobolsoni.cloud/health"
fi

MAX_RETRIES=5
RETRY_INTERVAL=15
HEALTH_STATUS="unknown"

for i in $(seq 1 ${MAX_RETRIES}); do
  log_info "Health check attempt ${i}/${MAX_RETRIES}..."
  HEALTH_STATUS=$(curl -sf --max-time 10 "${HEALTH_URL}" | jq -r '.status' 2>/dev/null || echo "unhealthy")
  
  if [[ "${HEALTH_STATUS}" == "healthy" ]]; then
    break
  fi
  
  log_warn "Health check failed (attempt ${i}). Retrying in ${RETRY_INTERVAL}s..."
  sleep ${RETRY_INTERVAL}
done

if [[ "${HEALTH_STATUS}" != "healthy" ]]; then
  log_error "Service is not healthy after rollback! Status: ${HEALTH_STATUS}"
  log_error "Manual intervention required!"
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
log_success "✅ ROLLBACK COMPLETED SUCCESSFULLY"
echo "═══════════════════════════════════════════════════════════"
log_info "Environment : ${ENVIRONMENT}"
log_info "Health      : ${HEALTH_STATUS}"
log_info "Completed at: $(date -u)"
echo "═══════════════════════════════════════════════════════════"
echo ""
