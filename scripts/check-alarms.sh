#!/usr/bin/env bash
###############################################################################
# check-alarms.sh — CloudWatch Alarm Checker for Canary Deployments
# marciobolsoni.cloud GitOps CI/CD Suite
#
# Usage: ./check-alarms.sh <environment>
# Returns: 0 if all alarms are OK, 1 if any alarm is in ALARM state
###############################################################################

set -euo pipefail

ENVIRONMENT="${1:-staging}"
AWS_REGION="${AWS_REGION:-us-east-1}"
PROJECT="marciobolsoni-cloud"
NAME_PREFIX="${PROJECT}-${ENVIRONMENT}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "\033[0;34m[INFO]\033[0m    $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ALARM]${NC}   $*" >&2; }

# Alarms that trigger canary rollback
ROLLBACK_ALARMS=(
  "${NAME_PREFIX}-http-5xx-rate"
  "${NAME_PREFIX}-p99-latency"
  "${NAME_PREFIX}-ecs-cpu"
  "${NAME_PREFIX}-ecs-memory"
  "${NAME_PREFIX}-ecs-running-tasks"
)

echo ""
log_info "Checking CloudWatch alarms for environment: ${ENVIRONMENT}"
echo "─────────────────────────────────────────────"

ALARM_BREACHED=false

for ALARM_NAME in "${ROLLBACK_ALARMS[@]}"; do
  STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "${ALARM_NAME}" \
    --query 'MetricAlarms[0].StateValue' \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")
  
  case "${STATE}" in
    "OK")
      log_success "${ALARM_NAME}: OK"
      ;;
    "ALARM")
      log_error "${ALARM_NAME}: ⚠️  IN ALARM STATE"
      ALARM_BREACHED=true
      ;;
    "INSUFFICIENT_DATA")
      log_warn "${ALARM_NAME}: INSUFFICIENT_DATA (treating as OK during initial deployment)"
      ;;
    "NOT_FOUND")
      log_warn "${ALARM_NAME}: Alarm not found — skipping"
      ;;
    *)
      log_warn "${ALARM_NAME}: Unknown state: ${STATE}"
      ;;
  esac
done

echo "─────────────────────────────────────────────"

if [[ "${ALARM_BREACHED}" == "true" ]]; then
  log_error "❌ One or more CloudWatch alarms are in ALARM state!"
  log_error "Canary deployment should be rolled back."
  exit 1
else
  log_success "✅ All CloudWatch alarms are in OK state. Canary deployment is healthy."
  exit 0
fi
