#!/bin/sh
# prepare-vault-storage.sh
#
# Waits for the EBS volumes for Vault Raft data and audit logs to appear as
# NVMe devices, formats them with XFS if needed, mounts them at their final
# paths, and writes /etc/fstab entries so the mounts survive reboots. Then
# sets ownership on the mount points so the vault user can read/write.
# Runs on every node before vault.service starts.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_AUDIT_LOG_DIR="/var/log/vault"
readonly VAULT_RAFT_DATA_DIR="/var/opt/vault/data"

scan_ebs_nvme_block_device_path() (
  ebs_attachment_name_basename="$1"

  # Globbing is disabled by `set -f`; re-enable for the glob below. Safe to
  # leave unrestored since this is a ( ) subshell.
  set +f
  for nvme_block_device_path in /dev/nvme*n1; do
    [ -b "${nvme_block_device_path}" ] || continue

    reported_ebs_attachment_name="$(ebsnvme-id -b "${nvme_block_device_path}" 2>/dev/null)" || continue
    [ "${reported_ebs_attachment_name##*/}" = "${ebs_attachment_name_basename}" ] || continue

    printf '%s' "${nvme_block_device_path}"
    return 0
  done

  return 1
)

resolve_ebs_nvme_block_device_path() (
  ebs_attachment_name="$1"
  ebs_attachment_name_basename="${ebs_attachment_name##*/}"

  timeout_seconds=20
  if retry_for "${timeout_seconds}" \
    scan_ebs_nvme_block_device_path "${ebs_attachment_name_basename}"; then
    return 0
  fi

  log_error "NVMe device for attachment ${ebs_attachment_name} did not appear after ${timeout_seconds}s"
  return 1
)

validate_xfs_label() (
  filesystem_label="$1"

  [ "${#filesystem_label}" -le 12 ] && return 0

  log_error "XFS labels must be 12 characters or fewer: ${filesystem_label}"
  return 1
)

format_block_device() (
  block_device_path="$1"
  filesystem_label="$2"

  existing_filesystem_type="$(blkid -p -s TYPE -o value "${block_device_path}" 2>/dev/null)" || true

  if [ -z "${existing_filesystem_type}" ]; then
    mkfs.xfs -L "${filesystem_label}" "${block_device_path}" >/dev/null ||
      {
        log_error "mkfs.xfs failed on ${block_device_path}"
        return 1
      }
  elif [ "${existing_filesystem_type}" = "xfs" ]; then
    : # XFS filesystem already present, do nothing.
  else
    log_error "Refusing to format ${block_device_path}: unexpected content (type=${existing_filesystem_type})"
    return 1
  fi

  return 0
)

mount_block_device() (
  block_device_path="$1"
  mount_point="$2"

  if ! mountpoint -q "${mount_point}"; then
    mkdir -p "${mount_point}"
    mount -t xfs "${block_device_path}" "${mount_point}" ||
      {
        log_error "Failed to mount ${block_device_path} at ${mount_point}"
        return 1
      }
  fi

  mountpoint -q "${mount_point}" ||
    {
      log_error "${mount_point} is not a mountpoint after mount step"
      return 1
    }
)

ensure_fstab_entry() (
  block_device_path="$1"
  mount_point="$2"

  filesystem_uuid="$(blkid -s UUID -o value "${block_device_path}")" || true
  if [ -z "${filesystem_uuid}" ]; then
    log_error "Could not read UUID from ${block_device_path}"
    return 1
  fi

  if ! grep -qE "^UUID=${filesystem_uuid}[[:blank:]]" /etc/fstab; then
    printf 'UUID=%s  %s  xfs  defaults,nofail  0  2\n' \
      "${filesystem_uuid}" \
      "${mount_point}" \
      >>/etc/fstab
  fi
)

prepare_ebs_volume() (
  block_device_path="$1"
  mount_point="$2"
  filesystem_label="$3"

  validate_xfs_label "${filesystem_label}"
  format_block_device "${block_device_path}" "${filesystem_label}"
  mount_block_device "${block_device_path}" "${mount_point}"
  ensure_fstab_entry "${block_device_path}" "${mount_point}"
)

set_ownership_and_permissions() (
  mountpoint -q "${VAULT_RAFT_DATA_DIR}" ||
    {
      log_error "${VAULT_RAFT_DATA_DIR} not mounted; refusing to chown underlying directory"
      return 1
    }
  mountpoint -q "${VAULT_AUDIT_LOG_DIR}" ||
    {
      log_error "${VAULT_AUDIT_LOG_DIR} not mounted; refusing to chown underlying directory"
      return 1
    }

  chown vault:vault "${VAULT_RAFT_DATA_DIR}"
  chmod 700 "${VAULT_RAFT_DATA_DIR}"

  chown vault:vault "${VAULT_AUDIT_LOG_DIR}"
  chmod 755 "${VAULT_AUDIT_LOG_DIR}"
)

main() {
  # Vault Raft Data
  vault_raft_data_nvme_block_device_path="$(resolve_ebs_nvme_block_device_path "${VAULT_RAFT_DATA_EBS_ATTACHMENT_NAME}")"
  prepare_ebs_volume "${vault_raft_data_nvme_block_device_path}" "${VAULT_RAFT_DATA_DIR}" "vault-raft"

  # Vault Audit Log
  vault_audit_log_nvme_block_device_path="$(resolve_ebs_nvme_block_device_path "${VAULT_AUDIT_LOG_EBS_ATTACHMENT_NAME}")"
  prepare_ebs_volume "${vault_audit_log_nvme_block_device_path}" "${VAULT_AUDIT_LOG_DIR}" "vault-audit"

  set_ownership_and_permissions
}

main "$@"
