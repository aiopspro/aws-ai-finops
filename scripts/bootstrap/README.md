# Terraform Bootstrap

> **Run once.** Creates the AWS infrastructure that Terraform needs before it can manage anything.

---

## What This Does

Terraform stores its state in an S3 bucket. That resource must exist **before** Terraform can run — but Terraform can't create it, because it needs it to already exist. That's the chicken-and-egg problem this bootstrap solves.

> **No DynamoDB required.** Terraform >= 1.10 supports native S3 locking (`use_lockfile = true`), which writes a `.tflock` file directly to the state bucket. There is no separate DynamoDB table to provision or pay for.

This folder contains two scripts that do the same thing — pick the one that matches your OS:

| Script | Platform |
|---|---|
| `bootstrap.py` | Windows **and** Linux (recommended) |
| `bootstrap.sh` | Linux / macOS only |

Both scripts are **idempotent** — safe to re-run. Resources that already exist are skipped.

---

## What Gets Created

| Resource | Name | Purpose |
|---|---|---|
| S3 Bucket | `<prefix>-tfstate-management-<account-id>` | Stores Terraform remote state files + native S3 lock files |
| AWS Organization | — | Governance plane — enables SCPs, Tag Policies, Backup Policies |

The S3 bucket is hardened automatically:
- Versioning enabled (recover state if a file is corrupted)
- AES-256 encryption (state files contain sensitive resource data)
- All public access blocked
- Lifecycle policy: noncurrent versions deleted after 90 days

---

## Prerequisites

Complete every step before running the script.

---

### Step 1 — Python 3.8+ (for `bootstrap.py`)

Check if you already have it:
```
python --version        # Windows
python3 --version       # Linux / macOS
```

Install if missing:
- **Windows:** https://www.python.org/downloads/ — check **"Add Python to PATH"** during install
- **Ubuntu/Debian:** `sudo apt install python3`
- **Amazon Linux / RHEL:** `sudo yum install python3`

---

### Step 2 — Install boto3 (Python only)

boto3 is the AWS SDK for Python. The script uses it instead of the AWS CLI.

```
pip install -r scripts/bootstrap/requirements.txt
```

Verify:
```
python -c "import boto3; print(boto3.__version__)"
```

---

### Step 3 — AWS CLI v2

You need the AWS CLI to configure your credentials profile. You don't use it to run the Python script, but it's needed for setup.

**Install:**
- **Windows:** https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html
- **Linux:** https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html

**Verify:**
```
aws --version    # should show aws-cli/2.x.x
```

> **Shell script only (`bootstrap.sh`) — also install `jq`:**
> ```
> sudo apt install jq        # Ubuntu/Debian
> sudo yum install jq        # Amazon Linux / RHEL
> brew install jq            # macOS
> ```

---

### Step 4 — Configure your AWS credentials profile

The script connects to AWS using a named credentials profile. The default profile name is `idk-management`.

```
aws configure --profile idk-management
```

You will be prompted for:

| Prompt | What to enter |
|---|---|
| AWS Access Key ID | Your IAM user access key |
| AWS Secret Access Key | Your IAM user secret key |
| Default region name | `ap-south-1` |
| Default output format | `json` |

Your credentials are stored in `~/.aws/credentials` (Linux) or `C:\Users\<you>\.aws\credentials` (Windows). They are never committed to Git — `.gitignore` excludes them.

**Verify the profile works:**
```
aws sts get-caller-identity --profile idk-management
```

Expected output:
```json
{
    "UserId": "AIDAXXXXXXXXXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-username"
}
```

---

### Step 5 — Find your AWS Account ID

The script requires your management account ID as a required argument. It validates that your credentials match this account before creating anything — this prevents accidental runs against the wrong account.

```
aws sts get-caller-identity --profile idk-management --query Account --output text
```

Copy this value — you will pass it as `--account-id` when running the script.

---

## Running the Script

### Python — Windows and Linux

```
# Windows (Command Prompt)
python scripts\bootstrap\bootstrap.py --account-id 123456789012

# Windows (PowerShell)
python scripts/bootstrap/bootstrap.py --account-id 123456789012

# Linux / macOS
python3 scripts/bootstrap/bootstrap.py --account-id 123456789012
```

### Bash — Linux / macOS only

```
bash scripts/bootstrap/bootstrap.sh --account-id 123456789012
```

---

## All Options

| Flag | Required | Default | Description |
|---|---|---|---|
| `--account-id` | **Yes** | — | Your 12-digit AWS management account ID |
| `--profile` | No | `$AWS_PROFILE` or `idk-management` | AWS credentials profile to use |
| `--region` | No | `ap-south-1` | AWS region for the S3 state bucket |
| `--prefix` | No | `idk` | Company prefix used in resource names |

**Examples:**

```
# Minimal — just the required argument
python bootstrap.py --account-id 123456789012

# Custom profile
python bootstrap.py --account-id 123456789012 --profile my-profile

# All options explicit
python bootstrap.py --account-id 123456789012 --profile idk-management --region ap-south-1 --prefix idk

# Built-in help
python bootstrap.py --help
```

---

## What the Output Looks Like

```
============================================================
  IDK Digital Solutions — Terraform Bootstrap
============================================================
[INFO]  Account ID  : 123456789012
[INFO]  Profile     : idk-management
[INFO]  Region      : ap-south-1
[INFO]  State bucket: idk-tfstate-management-123456789012

[INFO]  Running pre-flight checks...
[OK]    Authenticated as: arn:aws:iam::123456789012:user/terraform-bootstrap
[OK]    Account ID:       123456789012
[INFO]  Profile:          idk-management
[INFO]  Region:           ap-south-1

[INFO]  Creating Terraform state S3 bucket: idk-tfstate-management-123456789012
[OK]    Bucket created: idk-tfstate-management-123456789012
[OK]    Versioning enabled
[OK]    Encryption enabled (AES-256)
[OK]    Public access blocked
[OK]    Lifecycle policy applied (90-day noncurrent version expiry)
[OK]    Bucket tagged with enterprise tags

[INFO]  Checking AWS Organizations status...
[OK]    AWS Organization created with ALL features
[OK]    Service Control Policies (SCP) enabled
[OK]    Tag Policies enabled
[OK]    Backup Policies enabled

============================================================
[OK]    Bootstrap complete!
============================================================
```

If a resource already exists from a previous run, you will see `[WARN]  ... already exists. Skipping.` — this is expected and safe.

---

## After This Script — What to Do Next

Once the script finishes, run Terraform in this order:

**1. Organization layer** — creates OUs and member accounts:
```
cd terraform/global/organization
terraform init
terraform plan        # review the plan before applying
terraform apply
```

**2. Service Control Policies** — attaches governance guardrails:
```
cd ../scps
terraform init && terraform plan && terraform apply
```

**3. Tag Policies** — enforces mandatory tagging standards:
```
cd ../tag-policies
terraform init && terraform plan && terraform apply
```

---

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `boto3 is not installed` | Missing dependency | `pip install -r scripts/bootstrap/requirements.txt` |
| `AWS profile 'idk-management' not found` | Profile not configured | `aws configure --profile idk-management` |
| `Account mismatch! Expected X, got Y` | Wrong profile active | Pass `--profile` with the correct profile name |
| `Bucket exists but owned by a different account` | Bucket name collision | Choose a different `--prefix` |
| `Cannot authenticate with AWS` | Expired or invalid credentials | Re-run `aws configure --profile idk-management` |
| `AWS CLI not found` (shell script) | AWS CLI not installed | Install from https://aws.amazon.com/cli/ |
| `jq not found` (shell script) | jq not installed | `sudo apt install jq` |

---

## File Reference

```
scripts/bootstrap/
├── bootstrap.py       # Cross-platform bootstrap (Windows + Linux) — uses boto3
├── bootstrap.sh       # Linux/macOS bootstrap — uses AWS CLI + jq
├── requirements.txt   # Python dependencies (boto3)
└── README.md          # This file
```
