# shellcheck shell=sh
# aws-helpers.sh — AWS API helper functions.

fetch_secret() {
  region="${1}"
  secret_arn="${2}"

  for attempt in 1 2 3 4 5; do
    if result=$(aws secretsmanager get-secret-value \
      --region "${region}" \
      --secret-id "${secret_arn}" \
      --query SecretString --output text 2>/dev/null); then
      printf '%s' "${result}"
      return 0
    fi
    sleep 5
  done

  log_error "Failed to retrieve secret after ${attempt} attempts, failing bootstrap"
  return 1
}
