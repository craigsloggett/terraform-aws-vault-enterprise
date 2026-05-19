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

retry_until() (
  interval="$1"
  max_attempts="$2"
  shift 2

  attempt=0
  while [ "${attempt}" -lt "${max_attempts}" ]; do
    attempt=$((attempt + 1))

    if "$@"; then
      return 0
    fi

    if [ "${attempt}" -lt "${max_attempts}" ]; then
      sleep "${interval}"
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

  interval=5
  max_attempts=5

  if retry_until "${interval}" "${max_attempts}" \
    fetch_secret_no_retry "${secret_id}"; then
    return 0
  fi

  log_error "Failed to retrieve secret ${secret_id} after ${max_attempts} attempts"
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
  )" || return 1

  [ -n "${result}" ] || return 1

  printf '%s' "${result}"
)

fetch_instance_ids_with_tag() (
  tag_key="$1"
  tag_value="$2"

  interval=5
  max_attempts=5

  if retry_until "${interval}" "${max_attempts}" \
    scan_instance_ids_with_tag "${tag_key}" "${tag_value}"; then
    return 0
  fi

  log_error "No instances found for tag ${tag_key}=${tag_value} after ${max_attempts} attempts"
  return 1
)
