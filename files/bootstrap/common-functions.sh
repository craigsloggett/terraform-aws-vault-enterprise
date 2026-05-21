# shellcheck shell=sh
# common-functions.sh
#
# Shared shell helpers for the bootstrap scripts. Sourced by scripts in
# /var/lib/cloud/scripts/.

log_info() (
  printf '[INFO]  %s\n' "$1" >&2
)

log_warn() (
  printf '[WARN]  %s\n' "$1" >&2
)

log_error() (
  printf '[ERROR] %s\n' "$1" >&2
)

retry_for() (
  timeout_seconds="$1"
  predicate="$2"
  shift 1

  if ! command -v "${predicate}" >/dev/null 2>&1; then
    log_error "retry_for: '${predicate}' is not a defined command or function"
    return 2
  fi

  interval=5
  elapsed=0

  while [ "${elapsed}" -lt "${timeout_seconds}" ]; do
    if "$@"; then
      return 0
    else
      sleep "${interval}"
      elapsed=$((elapsed + interval))
    fi
  done

  return 1
)

# AWS Systems Manager Parameter Store

fetch_parameter() (
  parameter_name="$1"

  aws ssm get-parameter \
    --name "${parameter_name}" \
    --query "Parameter.Value" \
    --output text
)

put_parameter() (
  parameter_name="$1"
  parameter_value="$2"

  aws ssm put-parameter \
    --name "${parameter_name}" \
    --value "${parameter_value}" \
    --type String \
    --overwrite \
    >/dev/null
)

# AWS Secrets Manager

fetch_secret_no_retry() (
  secret_id="$1"

  aws secretsmanager get-secret-value \
    --secret-id "${secret_id}" \
    --query SecretString --output text 2>/dev/null
)

fetch_secret() (
  secret_id="$1"

  timeout_seconds=1200
  if retry_for "${timeout_seconds}" \
    fetch_secret_no_retry "${secret_id}"; then
    return 0
  fi

  log_error "Failed to retrieve secret ${secret_id} after ${timeout_seconds}s"
  return 1
)

put_secret() (
  secret_id="$1"
  secret_string="$2"

  aws secretsmanager put-secret-value \
    --secret-id "${secret_id}" \
    --secret-string "${secret_string}" \
    >/dev/null
)

# Amazon Elastic Compute Cloud

scan_instance_ids_with_tag() (
  tag_key="$1"
  tag_value="$2"

  result="$(
    aws ec2 describe-instances \
      --filters \
      "Name=tag:${tag_key},Values=${tag_value}" \
      "Name=instance-state-name,Values=running" \
      --query "Reservations[].Instances[].InstanceId" \
      --output text 2>/dev/null
  )" ||
    return 1

  [ -n "${result}" ] ||
    return 1

  printf '%s' "${result}"
)

fetch_instance_ids_with_tag() (
  tag_key="$1"
  tag_value="$2"

  timeout_seconds=1200
  if retry_for "${timeout_seconds}" \
    scan_instance_ids_with_tag "${tag_key}" "${tag_value}"; then
    return 0
  fi

  log_error "No instances found for tag ${tag_key}=${tag_value} after ${timeout_seconds}s"
  return 1
)
