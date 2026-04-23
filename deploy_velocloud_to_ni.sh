#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${1:-ni}"
HOST_SRC_DIR="${2:-/tmp/Velo}"
SRC_DIR="/tmp/Velo"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$HOST_SRC_DIR" != /* ]]; then
  HOST_SRC_DIR="$SCRIPT_DIR/$HOST_SRC_DIR"
fi

# Vendor-specific files live under Files/VeloCloud/; shared files under Files/
VENDOR_DIR="VeloCloud"

REQUIRED_SRC_FILES=(
  "${VENDOR_DIR}/VeloCloud-Controller.pm"
  "${VENDOR_DIR}/VeloCloud-Client.pm"
  "${VENDOR_DIR}/SaveVeloCloudOrganizations.pm"
  "${VENDOR_DIR}/VeloCloudOrganization.sql"
  "ApiHelperFactory.pm"
  "getDeviceList.sql"
  "getDeviceList.debug.sql"
  "checkSdnConnection.pl"
  "Base.pm"
  "PropertyGroup.sql"
  "PropertyGroupDef.sql"
  "discoverNow.pl"
)

require_in_container() {
  local path="$1"
  docker exec "$CONTAINER_NAME" test -e "$path"
}

copy_into_container() {
  local src="$1"
  local dst="$2"
  docker exec "$CONTAINER_NAME" cp "$src" "$dst"
}

backup_file() {
  local dst="$1"
  local bak="${dst}.bak"

  if require_in_container "$dst"; then
    echo "[BACKUP] $dst -> $bak"
    copy_into_container "$dst" "$bak"
  else
    echo "[WARN] Target not found, skipping backup: $dst"
  fi
}

install_file() {
  local src="$1"
  local dst="$2"

  if ! require_in_container "$src"; then
    echo "[ERROR] Source not found in container: $src"
    return 1
  fi

  echo "[INSTALL] $src -> $dst"
  copy_into_container "$src" "$dst"
}

echo "Container: $CONTAINER_NAME"
echo "Host source directory: $HOST_SRC_DIR"
echo "Source directory in container: $SRC_DIR"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "[ERROR] Container '$CONTAINER_NAME' is not running."
  exit 1
fi

missing_in_container=0
for f in "${REQUIRED_SRC_FILES[@]}"; do
  if ! require_in_container "$SRC_DIR/$f"; then
    missing_in_container=1
    break
  fi
done

if [[ "$missing_in_container" -eq 0 ]]; then
  echo "Using files already present in container: $SRC_DIR"
else
  echo "Some required files are missing in $SRC_DIR; staging from host..."

  if [[ ! -d "$HOST_SRC_DIR" ]]; then
    echo "[ERROR] Host source directory not found: $HOST_SRC_DIR"
    echo "[HINT] Files are missing in container path: $SRC_DIR"
    echo "[HINT] Either place files in container at $SRC_DIR or pass host path as arg2."
    echo "[HINT] Example: $0 ni /path/to/SDN-Agent/Files"
    exit 1
  fi

  echo "Preparing container source directory: $SRC_DIR"
  docker exec "$CONTAINER_NAME" mkdir -p "$SRC_DIR"

  echo "Staging updated files from host to container..."
  for f in "${REQUIRED_SRC_FILES[@]}"; do
    host_file="$HOST_SRC_DIR/$f"
    if [[ ! -f "$host_file" ]]; then
      echo "[ERROR] Required host file missing: $host_file"
      exit 1
    fi

    docker cp "$host_file" "$CONTAINER_NAME:$SRC_DIR/$f"
  done
fi

# source_path_in_container|destination_path_in_container
MAPPINGS=(
  "$SRC_DIR/${VENDOR_DIR}/VeloCloud-Controller.pm|/usr/local/lib/site_perl/NetMRI/SDN/VeloCloud.pm"
  "$SRC_DIR/${VENDOR_DIR}/VeloCloud-Client.pm|/usr/local/lib/site_perl/NetMRI/HTTP/Client/VeloCloud.pm"
  "$SRC_DIR/${VENDOR_DIR}/SaveVeloCloudOrganizations.pm|/usr/local/lib/site_perl/NetMRI/SDN/Plugins/SaveVeloCloudOrganizations.pm"
  "$SRC_DIR/${VENDOR_DIR}/VeloCloudOrganization.sql|/infoblox/netmri/db/db-netmri/create/VeloCloudOrganization.sql"
  "$SRC_DIR/ApiHelperFactory.pm|/usr/local/lib/site_perl/NetMRI/SDN/ApiHelperFactory.pm"
  "$SRC_DIR/getDeviceList.sql|/infoblox/netmri/app/transaction/netmri/processors/discovery/getDeviceList.sql"
  "$SRC_DIR/getDeviceList.debug.sql|/infoblox/netmri/app/transaction/netmri/processors/discovery/getDeviceList.debug.sql"
  "$SRC_DIR/checkSdnConnection.pl|/infoblox/netmri/app/transaction/netmri/collectors/sdnEngine/checkSdnConnection.pl"
  "$SRC_DIR/Base.pm|/usr/local/lib/site_perl/NetMRI/SDN/Base.pm"
  "$SRC_DIR/PropertyGroup.sql|/infoblox/netmri/db/db-netmri/DeviceSupport/PropertyGroup.sql"
  "$SRC_DIR/PropertyGroupDef.sql|/infoblox/netmri/db/db-netmri/DeviceSupport/PropertyGroupDef.sql"
  "$SRC_DIR/discoverNow.pl|/infoblox/netmri/utilities/discovery/discoverNow.pl"
)

echo "Starting backup and deployment..."
for mapping in "${MAPPINGS[@]}"; do
  src="${mapping%%|*}"
  dst="${mapping##*|}"

  backup_file "$dst"
  install_file "$src" "$dst"
done

echo "Deployment completed successfully."