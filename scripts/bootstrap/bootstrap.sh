#!/usr/bin/env bash
# =============================================================================
# IDK Digital Solutions — Terraform Bootstrap Script (Bash)
# =============================================================================
#
# PURPOSE
# -------
#   Creates two things that must exist BEFORE Terraform can run:
#     1. S3 bucket       — stores the Terraform remote state file
#                          (also used for native S3 locking via use_lockfile = true)
#     2. AWS Organization — enables the governance plane (SCPs, Tag Policies)
#
#   NOTE: DynamoDB locking is NOT used. Terraform >= 1.10 supports native
#   S3 locking (use_lockfile = true), which writes a .tflock file to the
#   state bucket — no separate DynamoDB table needed.
#
#   This is the "chicken-and-egg" bootstrap: Terraform needs remote state
#   infrastructure to manage infrastructure, but that infrastructure must
#   exist first. This script is the one-time manual step that breaks the deadlock.
#
# WHEN TO RUN
# -----------
#   Once — during the initial setup of a new AWS management account.
#   The script is fully idempotent: re-running it is safe and skips
#   resources that already exist.
#
# =============================================================================
# PREREQUISITES — complete ALL steps before running
# =============================================================================
#
#   STEP 1 — Install AWS CLI v2
#   ----------------------------
#   The script uses AWS CLI commands directly.
#
#   Linux:   https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
#            or: curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
#                unzip awscliv2.zip && sudo ./aws/install
#
#   Verify:  aws --version   (should show aws-cli/2.x.x)
#
#   STEP 2 — Install jq (JSON parser)
#   -----------------------------------
#   Used to parse AWS CLI JSON responses.
#
#   Ubuntu/Debian:  sudo apt install jq
#   Amazon Linux:   sudo yum install jq
#   macOS:          brew install jq
#
#   Verify:  jq --version
#
#   STEP 3 — Configure AWS credentials profile
#   -------------------------------------------
#   The script uses the AWS profile named "idk-management" by default.
#   This profile must have credentials for your AWS management account
#   with sufficient permissions (IAM, S3, Organizations).
#
#   Configure:
#     aws configure --profile idk-management
#     # Enter: AWS Access Key ID, Secret Access Key, region, output format
#
#   Verify credentials work:
#     aws sts get-caller-identity --profile idk-management
#
#   Expected output:
#     {
#         "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#         "Account": "YOUR_ACCOUNT_ID",
#         "Arn": "arn:aws:iam::YOUR_ACCOUNT_ID:user/your-username"
#     }
#
#   STEP 4 — Find your AWS Account ID
#   ------------------------------------
#   Required as the --account-id argument. The script validates your
#   credentials match this account before creating anything.
#
#   Get it:  aws sts get-caller-identity --profile idk-management \
#              --query Account --output text
#
# =============================================================================
# HOW TO RUN
# =============================================================================
#
#   Basic usage (replace 123456789012 with your actual account ID):
#     bash scripts/bootstrap/bootstrap.sh --account-id 123456789012
#
#   With a custom profile:
#     bash scripts/bootstrap/bootstrap.sh --account-id 123456789012 --profile my-profile
#
#   All options:
#     --account-id ACCOUNT_ID   REQUIRED. Your 12-digit AWS management account ID.
#     --profile    PROFILE      AWS profile. Default: $AWS_PROFILE or "idk-management".
#     --region     REGION       AWS region. Default: ap-south-1.
#     --prefix     PREFIX       Resource name prefix. Default: idk.
#     --help                    Show this help and exit.
#
#   Examples:
#     bash scripts/bootstrap/bootstrap.sh --account-id 123456789012
#     bash scripts/bootstrap/bootstrap.sh --account-id 123456789012 --profile idk-management
#     bash scripts/bootstrap/bootstrap.sh --account-id 123456789012 --region ap-south-1 --prefix idk
#
# =============================================================================
# WHAT THE SCRIPT CREATES
# =============================================================================
#
#   S3 Bucket:  <prefix>-tfstate-management-<account-id>
#     - Versioning enabled       (recover state if a file is corrupted)
#     - AES-256 encryption       (state files contain sensitive resource data)
#     - Public access blocked    (state must never be publicly accessible)
#     - Lifecycle policy         (auto-expire noncurrent versions after 90 days)
#     - Enterprise tags          (all 12 mandatory tags applied)
#
#   AWS Organization:
#     - Feature set: ALL (enables SCPs, Tag Policies, Backup Policies)
#     - Policy types enabled: SERVICE_CONTROL_POLICY, TAG_POLICY, BACKUP_POLICY
#
# =============================================================================
# AFTER THIS SCRIPT — WHAT TO DO NEXT
# =============================================================================
#
#   1. Apply the organization layer (OUs and member accounts):
#        cd terraform/global/organization
#        terraform init && terraform plan && terraform apply
#
#   2. Apply Service Control Policies:
#        cd ../scps
#        terraform init && terraform plan && terraform apply
#
#   3. Apply Tag Policies:
#        cd ../tag-policies
#        terraform init && terraform plan && terraform apply
#
# =============================================================================

set -euo pipefail

# ── Argument parsing ───────────────────────────────────────────────────────────
usage() {
  echo "Usage: bash bootstrap.sh --account-id ACCOUNT_ID [options]"
  echo ""
  echo "Required:"
  echo "  --account-id ACCOUNT_ID   12-digit AWS management account ID"
  echo ""
  echo "Optional:"
  echo "  --profile    PROFILE      AWS credentials profile (default: \$AWS_PROFILE or idk-management)"
  echo "  --region     REGION       AWS region (default: ap-south-1)"
  echo "  --prefix     PREFIX       Resource name prefix (default: idk)"
  echo "  --help                    Show this help and exit"
  echo ""
  echo "Example:"
  echo "  bash scripts/bootstrap/bootstrap.sh --account-id 123456789012"
  exit 0
}

ACCOUNT_ID=""
AWS_PROFILE="${AWS_PROFILE:-idk-management}"
AWS_REGION="ap-south-1"
COMPANY_PREFIX="idk"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account-id) ACCOUNT_ID="$2";     shift 2 ;;
    --profile)    AWS_PROFILE="$2";    shift 2 ;;
    --region)     AWS_REGION="$2";     shift 2 ;;
    --prefix)     COMPANY_PREFIX="$2"; shift 2 ;;
    --help|-h)    usage ;;
    *) echo "[ERROR] Unknown argument: $1"; echo "Run with --help for usage."; exit 1 ;;
  esac
done

if [[ -z "${ACCOUNT_ID}" ]]; then
  echo "[ERROR] --account-id is required."
  echo "        Get yours with: aws sts get-caller-identity --query Account --output text"
  echo "        Run with --help for full usage."
  exit 1
fi

if ! [[ "${ACCOUNT_ID}" =~ ^[0-9]{12}$ ]]; then
  echo "[ERROR] --account-id must be a 12-digit number, got: '${ACCOUNT_ID}'"
  exit 1
fi

STATE_BUCKET="${COMPANY_PREFIX}-tfstate-management-${ACCOUNT_ID}"

# ── Colors for output ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── Startup banner ────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  IDK Digital Solutions — Terraform Bootstrap"
echo "============================================================"
log_info "Account ID  : ${ACCOUNT_ID}"
log_info "Profile     : ${AWS_PROFILE}"
log_info "Region      : ${AWS_REGION}"
log_info "State bucket: ${STATE_BUCKET}"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────────
log_info "Running pre-flight checks..."

command -v aws  >/dev/null 2>&1 || log_error "AWS CLI not found. Install from: https://aws.amazon.com/cli/"
command -v jq   >/dev/null 2>&1 || log_error "jq not found. Install: sudo apt install jq / brew install jq"

CALLER_IDENTITY=$(aws sts get-caller-identity --profile "${AWS_PROFILE}" --output json 2>/dev/null) \
  || log_error "Cannot authenticate with AWS. Check your profile: ${AWS_PROFILE}"

ACTUAL_ACCOUNT=$(echo "${CALLER_IDENTITY}" | jq -r '.Account')
CALLER_ARN=$(echo "${CALLER_IDENTITY}" | jq -r '.Arn')

if [[ "${ACTUAL_ACCOUNT}" != "${ACCOUNT_ID}" ]]; then
  log_error "Account mismatch!
        Expected : ${ACCOUNT_ID}  (from --account-id)
        Got      : ${ACTUAL_ACCOUNT}  (from AWS credentials)
        Fix      : Check you are using the correct --profile"
fi

log_success "Authenticated as: ${CALLER_ARN}"
log_success "Account ID:       ${ACTUAL_ACCOUNT}"
log_info    "Region:           ${AWS_REGION}"
echo ""

# ── Create S3 State Bucket ────────────────────────────────────────────────────
log_info "Creating Terraform state S3 bucket: ${STATE_BUCKET}"

if aws s3api head-bucket --bucket "${STATE_BUCKET}" --profile "${AWS_PROFILE}" 2>/dev/null; then
  log_warn "Bucket ${STATE_BUCKET} already exists. Skipping creation."
else
  # ap-south-1 requires LocationConstraint — us-east-1 does NOT (AWS quirk)
  aws s3api create-bucket \
    --bucket "${STATE_BUCKET}" \
    --region "${AWS_REGION}" \
    --create-bucket-configuration LocationConstraint="${AWS_REGION}" \
    --profile "${AWS_PROFILE}" \
    --output text > /dev/null

  log_success "Bucket created: ${STATE_BUCKET}"
fi

# Enable versioning — CRITICAL: allows state file recovery if corrupted
log_info "Enabling versioning on state bucket..."
aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --versioning-configuration Status=Enabled \
  --profile "${AWS_PROFILE}"
log_success "Versioning enabled"

# Enable server-side encryption (AES-256)
# WHY: Terraform state contains sensitive data — account IDs, resource ARNs,
#      sometimes secrets if you're not careful. Encryption at rest is mandatory.
log_info "Enabling server-side encryption..."
aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }' \
  --profile "${AWS_PROFILE}"
log_success "Encryption enabled (AES-256)"

# Block ALL public access — state files must never be public
log_info "Blocking public access on state bucket..."
aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile "${AWS_PROFILE}"
log_success "Public access blocked"

# Enable lifecycle policy — delete old state versions after 90 days
# WHY: Without this, every Terraform run creates a new version. Over years,
#      this accumulates thousands of versions and significant storage cost.
log_info "Setting lifecycle policy (retain 90 days of versions)..."
aws s3api put-bucket-lifecycle-configuration \
  --bucket "${STATE_BUCKET}" \
  --lifecycle-configuration '{
    "Rules": [{
      "ID": "expire-old-state-versions",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      },
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }]
  }' \
  --profile "${AWS_PROFILE}"
log_success "Lifecycle policy applied"

# Tag the state bucket
log_info "Tagging state bucket..."
aws s3api put-bucket-tagging \
  --bucket "${STATE_BUCKET}" \
  --tagging '{
    "TagSet": [
      {"Key": "Department",         "Value": "Platform Engineering"},
      {"Key": "CostCenter",         "Value": "CC1001"},
      {"Key": "Project",            "Value": "landing-zone"},
      {"Key": "Application",        "Value": "terraform-state"},
      {"Key": "Environment",        "Value": "management"},
      {"Key": "Owner",              "Value": "platform-team"},
      {"Key": "BusinessUnit",       "Value": "Technology"},
      {"Key": "ManagedBy",          "Value": "bootstrap-script"},
      {"Key": "DataClassification", "Value": "confidential"},
      {"Key": "Compliance",         "Value": "none"},
      {"Key": "Backup",             "Value": "not-required"},
      {"Key": "Criticality",        "Value": "critical"}
    ]
  }' \
  --profile "${AWS_PROFILE}"
log_success "Bucket tagged with enterprise tags"

echo ""

# ── Enable AWS Organizations ──────────────────────────────────────────────────
log_info "Checking AWS Organizations status..."

ORG_STATUS=$(aws organizations describe-organization \
  --profile "${AWS_PROFILE}" \
  --output json 2>/dev/null || echo '{"Organization": null}')

if echo "${ORG_STATUS}" | jq -e '.Organization' > /dev/null 2>&1; then
  ORG_ID=$(echo "${ORG_STATUS}" | jq -r '.Organization.Id')
  log_warn "AWS Organization already exists: ${ORG_ID}. Skipping creation."
else
  log_info "Creating AWS Organization (ALL features enabled)..."
  aws organizations create-organization \
    --feature-set ALL \
    --profile "${AWS_PROFILE}" \
    --output text > /dev/null
  log_success "AWS Organization created with ALL features"
fi

# Enable AWS Organization policy types needed for Phase 1
# Fetch root ID once and reuse — avoids three separate API calls
ROOT_ID="$(aws organizations list-roots --profile "${AWS_PROFILE}" --query 'Roots[0].Id' --output text)"

log_info "Enabling Service Control Policies (SCP)..."
aws organizations enable-policy-type \
  --root-id "${ROOT_ID}" \
  --policy-type SERVICE_CONTROL_POLICY \
  --profile "${AWS_PROFILE}" \
  --output text > /dev/null 2>&1 || log_warn "SCP policy type already enabled"
log_success "SCP enabled"

log_info "Enabling Tag Policies..."
aws organizations enable-policy-type \
  --root-id "${ROOT_ID}" \
  --policy-type TAG_POLICY \
  --profile "${AWS_PROFILE}" \
  --output text > /dev/null 2>&1 || log_warn "Tag policy type already enabled"
log_success "Tag Policies enabled"

log_info "Enabling Backup Policies..."
aws organizations enable-policy-type \
  --root-id "${ROOT_ID}" \
  --policy-type BACKUP_POLICY \
  --profile "${AWS_PROFILE}" \
  --output text > /dev/null 2>&1 || log_warn "Backup policy type already enabled"
log_success "Backup Policies enabled"

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "============================================================"
log_success "Bootstrap complete!"
echo "============================================================"
echo ""
echo "Resources ready:"
echo "  S3 State Bucket : s3://${STATE_BUCKET}"
echo "  AWS Organization: Enabled with ALL features"
echo "  Policy Types    : SCP, Tag Policies, Backup Policies"
echo "  State locking   : S3 native (use_lockfile = true) — no DynamoDB needed"
echo ""
echo "Next steps — run in this order:"
echo ""
echo "  1. Initialize and apply the organization layer:"
echo "       cd terraform/global/organization"
echo "       terraform init -backend-config=backend.hcl"
echo "       terraform plan    # review before applying"
echo "       terraform apply"
echo ""
echo "  2. Apply Service Control Policies:"
echo "       cd ../scps"
echo "       terraform init -backend-config=backend.hcl && terraform plan && terraform apply"
echo ""
echo "  3. Apply Tag Policies:"
echo "       cd ../tag-policies"
echo "       terraform init -backend-config=backend.hcl && terraform plan && terraform apply"
echo "============================================================"
