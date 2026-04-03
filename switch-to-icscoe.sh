#!/usr/bin/env bash
set -euo pipefail

ICSCOE_UBUNTU="https://ftp.udx.icscoe.jp/Linux/ubuntu/"
ICSCOE_DEBIAN="https://ftp.udx.icscoe.jp/Linux/debian/"
BACKUP_SUFFIX=".bak.$(date +%Y%m%d%H%M%S)"

DRY_RUN=0
DO_APT_UPDATE=1
VERBOSE=0

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  switch-to-icscoe.sh [options]

Options:
  -n, --dry-run       変更内容を表示するだけでファイルは更新しない
  --no-apt-update     apt update を実行しない
  -v, --verbose       詳細表示
  -h, --help          このヘルプを表示

Behavior:
  - Ubuntu / Debian を自動判定
  - /etc/apt/sources.list を対象
  - /etc/apt/sources.list.d/*.list を対象
  - /etc/apt/sources.list.d/*.sources を対象
  - security 系リポジトリは変更しない
  - Ubuntu/Debian 以外のディストリビューションは変更しない
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--dry-run)
        DRY_RUN=1
        shift
        ;;
      --no-apt-update)
        DO_APT_UPDATE=0
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
  done
}

require_root() {
  [[ "$EUID" -eq 0 ]] || die "rootで実行してください: sudo $0"
}

detect_distro() {
  local id="" id_like=""

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  else
    die "/etc/os-release が読めません"
  fi

  case "$id" in
    ubuntu)
      echo "ubuntu"
      return
      ;;
    debian)
      echo "debian"
      return
      ;;
  esac

  case " $id_like " in
    *" ubuntu "*)
      echo "ubuntu"
      return
      ;;
    *" debian "*)
      echo "debian"
      return
      ;;
  esac

  echo "unknown"
}

backup_file() {
  local f="$1"
  cp -a "$f" "$f$BACKUP_SUFFIX"
}

show_diff() {
  local oldf="$1"
  local newf="$2"

  if command -v diff >/dev/null 2>&1; then
    diff -u "$oldf" "$newf" || true
  else
    warn "diff コマンドがないため差分を表示できません"
  fi
}

process_legacy_file() {
  local f="$1"
  local distro="$2"
  local tmp
  tmp="$(mktemp)"

  case "$distro" in
    ubuntu)
      # security.ubuntu.com を含む行は完全にスキップ
      sed -E \
        -e '/security\.ubuntu\.com/! s@https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?@'"$ICSCOE_UBUNTU"'@g' \
        "$f" > "$tmp"
      ;;
    debian)
      # security.debian.org を含む行は完全にスキップ
      sed -E \
        -e '/security\.debian\.org/! s@https?://deb\.debian\.org/debian/?@'"$ICSCOE_DEBIAN"'@g' \
        -e '/security\.debian\.org/! s@https?://ftp\.[^[:space:]]+/debian/?@'"$ICSCOE_DEBIAN"'@g' \
        "$f" > "$tmp"
      ;;
    *)
      rm -f "$tmp"
      die "unsupported distro: $distro"
      ;;
  esac

  if cmp -s "$f" "$tmp"; then
    [[ "$VERBOSE" -eq 1 ]] && log "No change: $f"
    rm -f "$tmp"
    return 1
  fi

  log "Changed: $f"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    show_diff "$f" "$tmp"
    rm -f "$tmp"
  else
    backup_file "$f"
    cat "$tmp" > "$f"
    rm -f "$tmp"
  fi

  return 0
}

process_deb822_file() {
  local f="$1"
  local distro="$2"
  local tmp
  tmp="$(mktemp)"

  awk -v distro="$distro" \
      -v ubuntu_uri="$ICSCOE_UBUNTU" \
      -v debian_uri="$ICSCOE_DEBIAN" '
    BEGIN { IGNORECASE=1 }

    # URIs: 行だけを書き換える
    /^URIs:[[:space:]]*/ {
      line = $0

      # security 系は完全スキップ
      if (line ~ /security\.ubuntu\.com/ || line ~ /security\.debian\.org/) {
        print line
        next
      }

      if (distro == "ubuntu") {
        if (line ~ /archive\.ubuntu\.com\/ubuntu\/?$/) {
          print "URIs: " ubuntu_uri
          next
        }
      } else if (distro == "debian") {
        if (line ~ /deb\.debian\.org\/debian\/?$/ || line ~ /ftp\..*\/debian\/?$/) {
          print "URIs: " debian_uri
          next
        }
      }

      print line
      next
    }

    { print }
  ' "$f" > "$tmp"

  if cmp -s "$f" "$tmp"; then
    [[ "$VERBOSE" -eq 1 ]] && log "No change: $f"
    rm -f "$tmp"
    return 1
  fi

  log "Changed: $f"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    show_diff "$f" "$tmp"
    rm -f "$tmp"
  else
    backup_file "$f"
    cat "$tmp" > "$f"
    rm -f "$tmp"
  fi

  return 0
}

collect_target_files() {
  local files=()

  [[ -f /etc/apt/sources.list ]] && files+=("/etc/apt/sources.list")

  shopt -s nullglob
  local f
  for f in /etc/apt/sources.list.d/*.list; do
    files+=("$f")
  done
  for f in /etc/apt/sources.list.d/*.sources; do
    files+=("$f")
  done
  shopt -u nullglob

  printf '%s\n' "${files[@]:-}"
}

main() {
  parse_args "$@"
  require_root

  local distro
  distro="$(detect_distro)"

  case "$distro" in
    ubuntu)
      log "Detected distro: Ubuntu"
      ;;
    debian)
      log "Detected distro: Debian"
      ;;
    *)
      die "Ubuntu/Debian 以外は対象外です"
      ;;
  esac

  local changed=0
  local files=()
  mapfile -t files < <(collect_target_files)

  [[ "${#files[@]}" -gt 0 ]] || die "対象ファイルが見つかりません"

  local f
  for f in "${files[@]}"; do
    if [[ "$f" == *.sources ]]; then
      process_deb822_file "$f" "$distro" && changed=1 || true
    else
      process_legacy_file "$f" "$distro" && changed=1 || true
    fi
  done

  echo
  log "Current repository entries:"
  grep -RHiE '^(deb|deb-src|URIs:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || true

  echo
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run のためファイル更新と apt update は実行していません"
    exit 0
  fi

  if [[ "$changed" -eq 0 ]]; then
    log "変更はありませんでした"
    exit 0
  fi

  if [[ "$DO_APT_UPDATE" -eq 1 ]]; then
    log "Running: apt update"
    apt update
  else
    log "--no-apt-update のため apt update はスキップしました"
  fi
}

main "$@"
