#!/bin/bash
set -euo pipefail

# Configuration
API_BASE="${API_BASE:-https://getsdk-dev.cpinnov.run/api/v1}"
TARGET_ARCH="${TARGET_ARCH:-aarch64}"
TARGET_OS="${TARGET_OS:-linux}"
MODULES=("cpbase" "cpcomm" "cpmedia" "cputils")
declare -A MODULE_VERSIONS

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >&2; }
error() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

# Fetch version for a module
get_version() {
    local module=$1
    local module_upper=$(echo "$module" | tr '[:lower:]' '[:upper:]')
    local env_var="CPSDK_${module_upper}_VERSION"

    if [ -n "${MODULE_VERSIONS[$module]:-}" ]; then
        echo "${MODULE_VERSIONS[$module]}"
        return 0
    fi

    if [ -n "${!env_var:-}" ]; then
        MODULE_VERSIONS["$module"]="${!env_var}"
        echo "${!env_var}"
        return 0
    fi

    log "Fetching latest version for $module..."
    local version
    version=$(curl -sSf "$API_BASE/latestversions" | \
        jq -r ".versions[] | select(.module == \"$module\") | .version")

    if [ -z "$version" ] || [ "$version" = "null" ]; then
        error "Failed to determine version for $module"
        return 1
    fi

    MODULE_VERSIONS["$module"]="$version"
    echo "$version"
}

# Download module tarball
download_module() {
    local module=$1
    local version=$2
    local crate_dir="crates/$(echo "$module" | sed 's/^cp/cp_/')"

    log "Downloading $module $version..."

    local tmp_dir=$(mktemp -d)
    curl -sSfL "$API_BASE/getversion?module=$module&version=$version" \
        -o "$tmp_dir/$module-$version.tar.gz"

    tar -xzf "$tmp_dir/$module-$version.tar.gz" -C "$tmp_dir"

    organize_files "$module" "$version" "$tmp_dir" "$crate_dir"

    rm -rf "$tmp_dir"
}

# Organize extracted files
organize_files() {
    local module=$1
    local version=$2
    local tmp_dir=$3
    local crate_dir=$4

    local lib_src="$tmp_dir/$module/linux/64bit"

    if [ ! -d "$lib_src" ]; then
        lib_src="$tmp_dir/linux/64bit"
    fi

    if [ ! -d "$lib_src" ]; then
        error "Expected directory structure not found: linux/64bit"
        return 1
    fi

    # Always use 'version' directory (not version-numbered directories)
    local lib_dest="$crate_dir/libs/$TARGET_OS-$TARGET_ARCH/version"
    local src_dest="$crate_dir/src_cpp/version"

    # Preserve bindings files tracked in repo to avoid losing them on refresh.
    local bindings_backup_dir="$tmp_dir/bindings_backup"
    local bindings_h="$src_dest/bindings.h"
    local bindings_cpp="$src_dest/bindings.cpp"
    mkdir -p "$bindings_backup_dir"
    if [ -f "$bindings_h" ]; then
        cp -f "$bindings_h" "$bindings_backup_dir/bindings.h"
    fi
    if [ -f "$bindings_cpp" ]; then
        cp -f "$bindings_cpp" "$bindings_backup_dir/bindings.cpp"
    fi

    # Clean and recreate version directories
    rm -rf "$lib_dest" "$src_dest"
    mkdir -p "$lib_dest" "$src_dest/include"

    log "Installing libraries to $lib_dest..."
    cp -f "$lib_src"/*.so "$lib_dest/" 2>/dev/null || true
    cp -f "$lib_src"/*.a "$lib_dest/" 2>/dev/null || true
    local lib_count=0
    for lib_file in "$lib_dest"/*.so "$lib_dest"/*.a; do
        if [ -e "$lib_file" ]; then
            lib_count=$((lib_count + 1))
        fi
    done
    if [ "$lib_count" -eq 0 ]; then
        error "No libraries installed to $lib_dest"
        return 1
    fi

    local include_src="$tmp_dir/$module/include"
    if [ ! -d "$include_src" ]; then
        include_src="$tmp_dir/include"
    fi

    if [ -d "$include_src" ]; then
        log "Installing headers to $src_dest/include..."
        cp -r "$include_src"/* "$src_dest/include/"
    else
        error "Expected include directory not found for $module"
        return 1
    fi

    if [ "$module" != "cpbase" ]; then
        ensure_cpbase_headers "$src_dest/include"
    fi

    if [ -f "$bindings_backup_dir/bindings.h" ]; then
        cp -f "$bindings_backup_dir/bindings.h" "$src_dest/bindings.h"
    fi
    if [ -f "$bindings_backup_dir/bindings.cpp" ]; then
        cp -f "$bindings_backup_dir/bindings.cpp" "$src_dest/bindings.cpp"
    fi

    generate_version_cpp "$module" "$version" "$src_dest"
}

# Generate version.cpp
generate_version_cpp() {
    local module=$1
    local version=$2
    local dest_dir=$3

    local header_prefix
    case "$module" in
        cpbase) header_prefix="CPBase" ;;
        cpcomm) header_prefix="CPComm" ;;
        cpmedia) header_prefix="CPMedia" ;;
        cputils) header_prefix="CPUtils" ;;
        *) error "Unknown module for header version: $module"; return 1 ;;
    esac
    local header_func="${header_prefix}_headerVersion"

    cat > "$dest_dir/version.cpp" <<EOF
#include "bindings.h"

const char* ${header_func}() {
    return "$version";
}
EOF
}

ensure_cpbase_headers() {
    local dest_root=$1
    local cpbase_include="crates/cp_base/src_cpp/version/include"
    local dest_dir="$dest_root/cpbase/include"

    if [ ! -d "$cpbase_include" ]; then
        error "cp_base headers not found at $cpbase_include"
        return 1
    fi

    log "Syncing cp_base headers to $dest_dir..."
    rm -rf "$dest_dir"
    mkdir -p "$dest_dir"
    cp -r "$cpbase_include/"* "$dest_dir/"
    if ! diff -qr "$cpbase_include" "$dest_dir" >/dev/null; then
        error "cp_base headers sync mismatch: $dest_dir"
        return 1
    fi
}

# Generate DEPENDENCIES.json
generate_dependencies_json() {
    local output_file="DEPENDENCIES.json"
    local deps=()

    log "Generating $output_file..."

    for module in "${MODULES[@]}"; do
        local version="${MODULE_VERSIONS[$module]:-}"
        if [ -z "$version" ]; then
            version=$(get_version "$module")
        fi
        local crate=$(echo "$module" | sed 's/^cp/cp_/')

        deps+=("{\"crate\":\"$crate\",\"module\":\"$module\",\"version\":\"$version\"}")
    done

    local deps_json=$(IFS=,; echo "${deps[*]}")

    cat > "$output_file" <<EOF
{
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET_OS-$TARGET_ARCH",
  "dependencies": [$deps_json]
}
EOF

    log "Created $output_file"
}

# Main execution
main() {
    cd "$(dirname "$0")/.."

    log "Starting dependency download for $TARGET_OS-$TARGET_ARCH..."

    for module in "${MODULES[@]}"; do
        version=$(get_version "$module")

        if [ -z "$version" ]; then
            error "Failed to determine version for $module"
            exit 1
        fi

        log "$module version: $version"
        download_module "$module" "$version"
    done

    generate_dependencies_json

    log "All dependencies downloaded successfully"
}

main "$@"