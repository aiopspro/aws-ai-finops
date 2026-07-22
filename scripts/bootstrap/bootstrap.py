#!/usr/bin/env python3
"""
IDK Digital Solutions — Terraform Bootstrap Script (Python)
=============================================================================

PURPOSE
-------
  Creates two things that must exist BEFORE Terraform can run:
    1. S3 bucket       — stores the Terraform remote state file
                         (also used for native S3 locking via use_lockfile = true)
    2. AWS Organization — enables the governance plane (SCPs, Tag Policies, etc.)

  NOTE: DynamoDB locking is NOT used. Terraform >= 1.10 supports native
  S3 locking (use_lockfile = true), which writes a .tflock file to the
  state bucket — no separate DynamoDB table needed.

  This is the classic "chicken-and-egg" problem: Terraform needs remote state
  infrastructure to manage infrastructure, but that infrastructure must exist
  first. This script is the one-time manual step that breaks the deadlock.

WHY A SCRIPT AND NOT TERRAFORM?
---------------------------------
  Terraform cannot manage the very S3 bucket and DynamoDB table it uses as its
  own backend. Doing so creates a circular dependency — Terraform would need
  state to create state. The script approach is the industry standard for this
  specific bootstrap problem.

WHEN TO RUN
-----------
  Once — during the initial setup of a new AWS management account.
  The script is fully idempotent: re-running it is safe and will skip
  resources that already exist.

=============================================================================
PREREQUISITES — complete ALL steps before running
=============================================================================

  STEP 1 — Python 3.8 or higher
  ------------------------------
  Check your version:
    python --version          (Windows)
    python3 --version         (Linux / macOS)

  If not installed:
    Windows : https://www.python.org/downloads/  (check "Add to PATH")
    Linux   : sudo apt install python3           (Debian/Ubuntu)
              sudo yum install python3           (RHEL/Amazon Linux)

  STEP 2 — Install boto3 (AWS SDK for Python)
  --------------------------------------------
  boto3 is the official AWS SDK. This script uses it instead of the AWS CLI.

    pip install -r scripts/bootstrap/requirements.txt

  Verify:
    python -c "import boto3; print(boto3.__version__)"

  STEP 3 — AWS CLI v2 (for credential configuration only)
  ---------------------------------------------------------
  You do not use the AWS CLI to RUN this script, but you need it to set up
  your AWS credentials profile.

  Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

  Verify:
    aws --version

  STEP 4 — Configure your AWS credentials profile
  -------------------------------------------------
  The script uses the AWS profile named "idk-management" by default.
  This profile must have credentials for your AWS management account.

  Option A — Named profile (recommended):
    aws configure --profile idk-management
    # Enter: AWS Access Key ID, Secret Access Key, region (ap-south-1), output (json)

  Option B — Environment variables (CI/CD pipelines):
    export AWS_ACCESS_KEY_ID=your_key
    export AWS_SECRET_ACCESS_KEY=your_secret
    export AWS_DEFAULT_REGION=ap-south-1
    # Then pass --profile default or omit --profile

  Verify your credentials work:
    aws sts get-caller-identity --profile idk-management

  Expected output:
    {
        "UserId": "AIDAXXXXXXXXXXXXXXXXX",
        "Account": "YOUR_ACCOUNT_ID",
        "Arn": "arn:aws:iam::YOUR_ACCOUNT_ID:user/your-username"
    }

  STEP 5 — Find your AWS Account ID
  ------------------------------------
  The script requires your management account ID as an argument.
  It validates that you are authenticated to the correct account before
  creating any resources — this prevents accidental runs against the wrong account.

  Get your account ID:
    aws sts get-caller-identity --profile idk-management --query Account --output text

  This is the value you pass as --account-id when running the script.

=============================================================================
HOW TO RUN
=============================================================================

  Basic usage (replace 123456789012 with your actual account ID):

    Windows (Command Prompt):
      python scripts\\bootstrap\\bootstrap.py --account-id 123456789012

    Windows (PowerShell):
      python scripts/bootstrap/bootstrap.py --account-id 123456789012

    Linux / macOS:
      python3 scripts/bootstrap/bootstrap.py --account-id 123456789012

  With a non-default AWS profile:

    Windows:
      set AWS_PROFILE=my-other-profile
      python scripts\\bootstrap\\bootstrap.py --account-id 123456789012

    Linux:
      AWS_PROFILE=my-other-profile python3 scripts/bootstrap/bootstrap.py --account-id 123456789012

  All available options:

    --account-id    REQUIRED. Your 12-digit AWS management account ID.
                    Example: --account-id 123456789012

    --profile       AWS credentials profile to use.
                    Default: value of AWS_PROFILE env var, or "idk-management".
                    Example: --profile my-profile

    --region        AWS region for the S3 state bucket.
                    Default: ap-south-1 (Mumbai)
                    Example: --region us-east-1

    --prefix        Company prefix used in resource names.
                    Default: idk
                    Example: --prefix mycompany

    --help          Show this help and exit.

=============================================================================
WHAT THE SCRIPT CREATES
=============================================================================

  S3 Bucket:  <prefix>-tfstate-management-<account-id>
    - Versioning enabled       (allows state file recovery if corrupted)
    - AES-256 encryption       (state files contain sensitive resource data)
    - Public access blocked    (state must never be publicly accessible)
    - Lifecycle policy         (auto-expire old versions after 90 days)
    - Enterprise tags          (all 12 mandatory tags applied)

  AWS Organization:
    - Feature set: ALL (enables SCPs, Tag Policies, Backup Policies)
    - Policy types enabled: SERVICE_CONTROL_POLICY, TAG_POLICY, BACKUP_POLICY

=============================================================================
AFTER THIS SCRIPT — WHAT TO DO NEXT
=============================================================================

  Once this script completes successfully, run Terraform:

    cd terraform/global/organization
    terraform init -backend-config=backend.hcl      # Downloads providers, connects to S3 backend
    terraform plan      # Shows what will be created (review before applying)
    terraform apply     # Creates OUs, member accounts, org structure

  Then:
    cd ../scps
    terraform init -backend-config=backend.hcl && terraform plan && terraform apply   # Service Control Policies

    cd ../tag-policies
    terraform init -backend-config=backend.hcl && terraform plan && terraform apply   # Tag Policies

=============================================================================
"""

import argparse
import os
import sys

try:
    import boto3
    from botocore.exceptions import ClientError, NoCredentialsError, ProfileNotFound
except ImportError:
    print(
        "[ERROR] boto3 is not installed.\n"
        "        Run: pip install -r scripts/bootstrap/requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)


# ── Colour support ─────────────────────────────────────────────────────────────
# Automatically disabled on Windows consoles that don't support ANSI escape codes.
# Enabled when running in Windows Terminal (WT_SESSION), ANSICON, or any modern
# terminal emulator that sets TERM_PROGRAM.
def _supports_colour() -> bool:
    if sys.platform == "win32":
        return (
            os.environ.get("ANSICON") is not None
            or os.environ.get("WT_SESSION") is not None
            or os.environ.get("TERM_PROGRAM") is not None
        )
    return sys.stdout.isatty()


if _supports_colour():
    BLUE   = "\033[0;34m"
    GREEN  = "\033[0;32m"
    YELLOW = "\033[1;33m"
    RED    = "\033[0;31m"
    NC     = "\033[0m"
else:
    BLUE = GREEN = YELLOW = RED = NC = ""


def log_info(msg: str)  -> None: print(f"{BLUE}[INFO]{NC}  {msg}")
def log_ok(msg: str)    -> None: print(f"{GREEN}[OK]{NC}    {msg}")
def log_warn(msg: str)  -> None: print(f"{YELLOW}[WARN]{NC}  {msg}")
def log_error(msg: str) -> None: print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr); sys.exit(1)


# ── Argument parsing ───────────────────────────────────────────────────────────
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="bootstrap.py",
        description="IDK Digital Solutions — Terraform Bootstrap Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python bootstrap.py --account-id 123456789012\n"
            "  python bootstrap.py --account-id 123456789012 --profile my-profile\n"
            "  python bootstrap.py --account-id 123456789012 --region ap-south-1 --prefix idk\n"
        ),
    )

    parser.add_argument(
        "--account-id",
        required=True,
        metavar="ACCOUNT_ID",
        help=(
            "12-digit AWS management account ID (required). "
            "The script validates that your credentials match this account "
            "before creating any resources. "
            "Find yours with: aws sts get-caller-identity --query Account --output text"
        ),
    )
    parser.add_argument(
        "--profile",
        default=os.environ.get("AWS_PROFILE", "idk-management"),
        metavar="PROFILE",
        help=(
            "AWS credentials profile to use. "
            "Default: value of AWS_PROFILE environment variable, or 'idk-management'. "
            "Configure profiles with: aws configure --profile <name>"
        ),
    )
    parser.add_argument(
        "--region",
        default="ap-south-1",
        metavar="REGION",
        help=(
            "AWS region for the S3 state bucket. "
            "Default: ap-south-1 (Mumbai). "
            "Note: us-east-1 does NOT require LocationConstraint — all other regions do."
        ),
    )
    parser.add_argument(
        "--prefix",
        default="idk",
        metavar="PREFIX",
        help=(
            "Company prefix used in resource names. "
            "Default: idk. "
            "Produces: <prefix>-tfstate-management-<account-id>"
        ),
    )

    args = parser.parse_args()

    # Validate account ID format: must be exactly 12 digits
    if not args.account_id.isdigit() or len(args.account_id) != 12:
        parser.error(
            f"--account-id must be a 12-digit number, got: '{args.account_id}'\n"
            "  Find yours with: aws sts get-caller-identity --query Account --output text"
        )

    return args


# ── AWS session helper ─────────────────────────────────────────────────────────
def get_session(profile: str, region: str) -> boto3.Session:
    try:
        return boto3.Session(profile_name=profile, region_name=region)
    except ProfileNotFound:
        log_error(
            f"AWS profile '{profile}' not found.\n"
            f"        Configure it with: aws configure --profile {profile}\n"
            f"        Or set a different profile with: --profile <name>"
        )


# ── Pre-flight checks ──────────────────────────────────────────────────────────
def preflight(session: boto3.Session, account_id: str, profile: str, region: str) -> None:
    log_info("Running pre-flight checks...")
    try:
        sts      = session.client("sts")
        identity = sts.get_caller_identity()
    except NoCredentialsError:
        log_error(
            f"No credentials found for profile '{profile}'.\n"
            f"        Configure with: aws configure --profile {profile}"
        )
    except ClientError as e:
        log_error(f"Cannot authenticate with AWS: {e}")
    except Exception as e:
        log_error(f"Unexpected error during authentication: {e}")

    actual_account = identity["Account"]
    caller_arn     = identity["Arn"]

    if actual_account != account_id:
        log_error(
            f"Account mismatch!\n"
            f"        Expected : {account_id}  (from --account-id)\n"
            f"        Got      : {actual_account}  (from AWS credentials)\n"
            f"        Fix      : Check you are using the correct --profile"
        )

    log_ok(f"Authenticated as: {caller_arn}")
    log_ok(f"Account ID:       {actual_account}")
    log_info(f"Profile:          {profile}")
    log_info(f"Region:           {region}")
    print()


# ── S3 State Bucket ────────────────────────────────────────────────────────────
def create_state_bucket(session: boto3.Session, bucket_name: str, region: str) -> None:
    s3 = session.client("s3", region_name=region)

    log_info(f"Creating Terraform state S3 bucket: {bucket_name}")

    bucket_exists = False
    try:
        s3.head_bucket(Bucket=bucket_name)
        bucket_exists = True
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "403":
            log_error(
                f"Bucket '{bucket_name}' exists but is owned by a different AWS account.\n"
                f"        Choose a different --prefix or --account-id."
            )
        elif code not in ("404", "NoSuchBucket"):
            log_error(f"Unexpected error checking bucket: {e}")

    if bucket_exists:
        log_warn(f"Bucket {bucket_name} already exists. Skipping creation.")
    else:
        # us-east-1 is the only region that must NOT specify LocationConstraint.
        # Every other region requires it — this is an AWS API quirk.
        if region == "us-east-1":
            s3.create_bucket(Bucket=bucket_name)
        else:
            s3.create_bucket(
                Bucket=bucket_name,
                CreateBucketConfiguration={"LocationConstraint": region},
            )
        log_ok(f"Bucket created: {bucket_name}")

    # Versioning — allows recovery of previous state if a file is corrupted or
    # accidentally overwritten. Without this, a bad Terraform run can permanently
    # destroy your state file and leave your infrastructure unmanageable.
    log_info("Enabling versioning on state bucket...")
    s3.put_bucket_versioning(
        Bucket=bucket_name,
        VersioningConfiguration={"Status": "Enabled"},
    )
    log_ok("Versioning enabled")

    # AES-256 encryption — Terraform state files contain resource ARNs, account IDs,
    # and sometimes secrets. Encryption at rest is mandatory for enterprise compliance.
    log_info("Enabling server-side encryption (AES-256)...")
    s3.put_bucket_encryption(
        Bucket=bucket_name,
        ServerSideEncryptionConfiguration={
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"},
                    "BucketKeyEnabled": True,
                }
            ]
        },
    )
    log_ok("Encryption enabled (AES-256)")

    # Block all public access — Terraform state must never be publicly readable.
    # Public state exposes your entire infrastructure topology to attackers.
    log_info("Blocking public access on state bucket...")
    s3.put_public_access_block(
        Bucket=bucket_name,
        PublicAccessBlockConfiguration={
            "BlockPublicAcls":       True,
            "IgnorePublicAcls":      True,
            "BlockPublicPolicy":     True,
            "RestrictPublicBuckets": True,
        },
    )
    log_ok("Public access blocked")

    # Lifecycle policy — each Terraform run creates a new S3 object version.
    # Over months/years, this accumulates thousands of versions and non-trivial
    # storage cost. This policy automatically deletes versions older than 90 days.
    # Filter: {} means the rule applies to all objects in the bucket.
    log_info("Setting lifecycle policy (retain 90 days of noncurrent versions)...")
    s3.put_bucket_lifecycle_configuration(
        Bucket=bucket_name,
        LifecycleConfiguration={
            "Rules": [
                {
                    "ID":     "expire-old-state-versions",
                    "Status": "Enabled",
                    "Filter": {},
                    "NoncurrentVersionExpiration": {"NoncurrentDays": 90},
                    "AbortIncompleteMultipartUpload": {"DaysAfterInitiation": 7},
                }
            ]
        },
    )
    log_ok("Lifecycle policy applied (90-day noncurrent version expiry)")

    log_info("Tagging state bucket...")
    s3.put_bucket_tagging(
        Bucket=bucket_name,
        Tagging={
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
                {"Key": "Criticality",        "Value": "critical"},
            ]
        },
    )
    log_ok("Bucket tagged with enterprise tags")
    print()


# ── AWS Organizations ──────────────────────────────────────────────────────────
def setup_organizations(session: boto3.Session) -> None:
    # The AWS Organizations API endpoint is a global service — its SDK endpoint
    # always resolves through us-east-1 regardless of your working region.
    orgs = session.client("organizations", region_name="us-east-1")

    log_info("Checking AWS Organizations status...")

    org_exists = False
    try:
        org_info   = orgs.describe_organization()
        org_id     = org_info["Organization"]["Id"]
        org_exists = True
        log_warn(f"AWS Organization already exists: {org_id}. Skipping creation.")
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "AWSOrganizationsNotInUseException":
            pass  # Not yet created — proceed to create
        else:
            log_error(f"Unexpected error checking Organizations: {e}")

    if not org_exists:
        log_info("Creating AWS Organization (ALL features enabled)...")
        # "ALL features" enables SCPs, Tag Policies, and Backup Policies.
        # "CONSOLIDATED_BILLING" only enables billing consolidation — no governance.
        # Always use ALL for an enterprise landing zone.
        orgs.create_organization(FeatureSet="ALL")
        log_ok("AWS Organization created with ALL features")

    # Fetch the organization root ID — required for attaching policy types.
    # Every organization has exactly one root. Nested OUs sit below the root.
    roots = orgs.list_roots()
    if not roots.get("Roots"):
        log_error(
            "AWS Organization has no roots — the organization may be in an "
            "inconsistent state. Check the AWS Organizations console."
        )
    root_id = roots["Roots"][0]["Id"]

    # Enable the three policy types that Phase 1 Terraform requires.
    # These must be enabled at the root level before any policy of that type
    # can be created or attached anywhere in the organization.
    for policy_type, label in [
        ("SERVICE_CONTROL_POLICY", "Service Control Policies (SCP)"),
        ("TAG_POLICY",             "Tag Policies"),
        ("BACKUP_POLICY",          "Backup Policies"),
    ]:
        log_info(f"Enabling {label}...")
        try:
            orgs.enable_policy_type(RootId=root_id, PolicyType=policy_type)
            log_ok(f"{label} enabled")
        except ClientError as e:
            if e.response["Error"]["Code"] == "PolicyTypeAlreadyEnabledException":
                log_warn(f"{label} already enabled")
            else:
                log_error(f"Failed to enable {label}: {e}")

    print()


# ── Summary ────────────────────────────────────────────────────────────────────
def print_summary(bucket_name: str, region: str) -> None:
    sep = "=" * 60
    print(sep)
    log_ok("Bootstrap complete!")
    print(sep)
    print()
    print("Resources ready:")
    print(f"  S3 State Bucket : s3://{bucket_name}")
    print( "  AWS Organization: Enabled with ALL features")
    print( "  Policy Types    : SCP, Tag Policies, Backup Policies")
    print( "  State locking   : S3 native (use_lockfile = true) — no DynamoDB needed")
    print()
    print("Next steps — run in this order:")
    print()
    print("  1. Initialize and apply the organization layer:")
    print("       cd terraform/global/organization")
    print("       terraform init -backend-config=backend.hcl")
    print("       terraform plan    # review before applying")
    print("       terraform apply")
    print()
    print("  2. Apply Service Control Policies:")
    print("       cd ../scps")
    print("       terraform init -backend-config=backend.hcl && terraform plan && terraform apply")
    print()
    print("  3. Apply Tag Policies:")
    print("       cd ../tag-policies")
    print("       terraform init -backend-config=backend.hcl && terraform plan && terraform apply")
    print(sep)


# ── Entry point ────────────────────────────────────────────────────────────────
def main() -> None:
    args = parse_args()

    account_id   = args.account_id
    profile      = args.profile
    region       = args.region
    prefix       = args.prefix
    bucket_name  = f"{prefix}-tfstate-management-{account_id}"

    print()
    print("=" * 60)
    print("  IDK Digital Solutions — Terraform Bootstrap")
    print("=" * 60)
    log_info(f"Account ID  : {account_id}")
    log_info(f"Profile     : {profile}")
    log_info(f"Region      : {region}")
    log_info(f"State bucket: {bucket_name}")
    print()

    session = get_session(profile, region)
    preflight(session, account_id, profile, region)
    create_state_bucket(session, bucket_name, region)
    setup_organizations(session)
    print_summary(bucket_name, region)


if __name__ == "__main__":
    main()
