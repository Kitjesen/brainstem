#!/usr/bin/env bash
set -euo pipefail

RULES_FILE="/etc/udev/rules.d/99-han_dog.rules"
DEFAULT_HINT="YUNZHUO"
CONTROLLER_NAME="yunzhuo"
HINT="$DEFAULT_HINT"
DRY_RUN=0
LIST_ONLY=0

usage() {
  cat <<'EOF'
Usage: tools/setup_udev.sh [options]

Options:
  --list                 List candidate tty devices and properties
  --dry-run              Print rule only, do not write or reload
  --controller-name NAME Symlink name (default: yunzhuo)
  --hint TEXT            Match hint (default: YUNZHUO)
  -h, --help             Show this help

Examples:
  sudo tools/setup_udev.sh
  tools/setup_udev.sh --list
  sudo tools/setup_udev.sh --hint "YUNZHUO"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) LIST_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --controller-name) CONTROLLER_NAME="${2:-}"; shift 2 ;;
    --hint) HINT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

list_devices() {
  for dev in /dev/ttyUSB* /dev/ttyACM*; do
    [[ -e "$dev" ]] || continue
    echo "$dev"
  done
}

device_props() {
  local dev="$1"
  udevadm info -q property -n "$dev" 2>/dev/null || true
}

print_device() {
  local dev="$1"
  local props
  props="$(device_props "$dev")"
  local vendor model vendor_id product_id serial
  vendor="$(echo "$props" | awk -F= '/^ID_VENDOR=/{print $2; exit}')"
  model="$(echo "$props" | awk -F= '/^ID_MODEL=/{print $2; exit}')"
  vendor_id="$(echo "$props" | awk -F= '/^ID_VENDOR_ID=/{print $2; exit}')"
  product_id="$(echo "$props" | awk -F= '/^ID_MODEL_ID=/{print $2; exit}')"
  serial="$(echo "$props" | awk -F= '/^ID_SERIAL_SHORT=/{print $2; exit}')"
  echo "  $dev  vendor=${vendor:-?} model=${model:-?} vid=${vendor_id:-?} pid=${product_id:-?} serial=${serial:-?}"
}

pick_device() {
  local hint="$1"
  local -a all=()
  local -a hits=()
  local dev props

  while IFS= read -r dev; do
    all+=("$dev")
    props="$(device_props "$dev")"
    if echo "$props" | grep -qi "$hint"; then
      hits+=("$dev")
    fi
  done < <(list_devices)

  if [[ ${#all[@]} -eq 0 ]]; then
    echo "No ttyUSB/ttyACM devices found." >&2
    exit 1
  fi

  if [[ ${#hits[@]} -eq 1 ]]; then
    echo "${hits[0]}"
    return
  fi

  echo "Candidate devices:"
  local i=0
  for dev in "${all[@]}"; do
    printf "  [%d] " "$i"
    print_device "$dev"
    i=$((i + 1))
  done

  local index
  read -r -p "Select device index for controller: " index
  if ! [[ "$index" =~ ^[0-9]+$ ]] || [[ "$index" -ge ${#all[@]} ]]; then
    echo "Invalid index." >&2
    exit 1
  fi
  echo "${all[$index]}"
}

build_rule() {
  local dev="$1"
  local name="$2"
  local props vendor_id product_id serial
  props="$(device_props "$dev")"
  vendor_id="$(echo "$props" | awk -F= '/^ID_VENDOR_ID=/{print $2; exit}')"
  product_id="$(echo "$props" | awk -F= '/^ID_MODEL_ID=/{print $2; exit}')"
  serial="$(echo "$props" | awk -F= '/^ID_SERIAL_SHORT=/{print $2; exit}')"

  if [[ -z "$vendor_id" || -z "$product_id" ]]; then
    echo "Missing ID_VENDOR_ID or ID_MODEL_ID for $dev." >&2
    exit 1
  fi

  local rule
  rule='SUBSYSTEM=="tty", ATTRS{idVendor}=="'"$vendor_id"'", ATTRS{idProduct}=="'"$product_id"'"'
  if [[ -n "$serial" ]]; then
    rule+=', ATTRS{serial}=="'"$serial"'"'
  fi
  rule+=', SYMLINK+="'"$name"'"'
  echo "$rule"
}

if [[ $LIST_ONLY -eq 1 ]]; then
  echo "Detected tty devices:"
  while IFS= read -r dev; do
    print_device "$dev"
  done < <(list_devices)
  exit 0
fi

dev="$(pick_device "$HINT")"
rule="$(build_rule "$dev" "$CONTROLLER_NAME")"

echo "Selected device: $dev"
echo "Rule to write:"
echo "  $rule"

if [[ $DRY_RUN -eq 1 ]]; then
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Need root to write $RULES_FILE. Re-run with sudo." >&2
  exit 1
fi

printf "%s\n" "$rule" > "$RULES_FILE"
udevadm control --reload-rules
udevadm trigger

echo "Done. Check symlink: ls -l /dev/$CONTROLLER_NAME"
