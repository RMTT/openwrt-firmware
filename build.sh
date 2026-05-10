#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if ! repo_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null); then
    printf 'unable to locate repository root from %s\n' "$script_dir" >&2
    exit 1
fi

if [[ "$PWD" != "$repo_root" ]]; then
    printf 'run this script from the repository root: %s\n' "$repo_root" >&2
    exit 1
fi

if [[ $# -lt 1 ]]; then
    printf 'usage: %s <arch/subtarget>\n' "${BASH_SOURCE[0]}" >&2
    exit 1
fi

target="$1"

openwrt_dir="$repo_root/openwrt"
patches_dir="$repo_root/patches"
target_config_dir="$repo_root/configs/$target"
common_packages="$repo_root/configs/common-packages"
files_path="$repo_root/files"
toolchain_dir="$repo_root/toolchain"

config_file="$target_config_dir/config"
toolchain_url_file="$target_config_dir/toolchain_url"

require_path() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        printf 'missing required path: %s\n' "$path" >&2
        exit 1
    fi
}

require_command() {
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'missing required command: %s\n' "$command_name" >&2
        exit 1
    fi
}

for command_name in cp curl git make nproc rm tar tee; do
    require_command "$command_name"
done

require_path "$openwrt_dir"
require_path "$target_config_dir"
require_path "$config_file"
require_path "$toolchain_url_file"

toolchain_url=$(head -1 "$toolchain_url_file")
artifact_dir="$openwrt_dir/bin/targets/$target"

if [[ -d "$toolchain_dir" ]]; then
    printf 'Toolchain directory exists, skipping download.\n'
else
    printf 'Downloading OpenWrt toolchain...\n'
    toolchain_file=$(basename "$toolchain_url")
    curl -fL -o "$toolchain_file" "$toolchain_url"

    printf 'Extracting toolchain...\n'
    mkdir -p "$toolchain_dir"
    tar -xf "$toolchain_file" -C "$toolchain_dir" --strip-components=1
    rm -f "$toolchain_file"

    printf 'Toolchain ready at %s\n' "$toolchain_dir"
fi

cd "$openwrt_dir"

if [[ -d "$patches_dir" ]]; then
    patch_count=0
    while IFS= read -r -d '' patch; do
        patch_count=$((patch_count + 1))
        printf 'Applying patch: %s\n' "$(basename "$patch")"
        if git apply --reverse --check "$patch" >/dev/null 2>&1; then
            printf '  Already applied, skipping.\n'
        else
            git apply "$patch"
        fi
    done < <(find "$patches_dir" -name '*.patch' -print0 | sort -z)
    printf 'Applied %d patch(es).\n' "$patch_count"
else
    printf 'No patches directory found, skipping.\n'
fi

printf 'Updating and installing feeds...\n'
./scripts/feeds update -a
./scripts/feeds install -a

printf 'Configuring %s build...\n' "$target"
cp "$config_file" .config

if [[ -f "$common_packages" ]]; then
    pkg_count=0
    while IFS= read -r pkg; do
        [[ -z "$pkg" || "$pkg" == \#* ]] && continue
        printf 'CONFIG_PACKAGE_%s=y\n' "$pkg" >> .config
        pkg_count=$((pkg_count + 1))
    done < "$common_packages"
    printf 'Added %d common package(s) to config.\n' "$pkg_count"
fi

make defconfig
./scripts/diffconfig.sh | tee diffconfig.txt

printf 'setup external toolchain...\n'
./scripts/ext-toolchain.sh \
         --toolchain "$toolchain_dir"/toolchain-* \
         --overwrite-config \
         --config "$target"

printf 'Copying custom files...\n'
rm -rf files
cp -r "$files_path" files

printf 'Building firmware...\n'
make -j8 download world

printf 'Build complete. Artifacts are under: %s\n' "$artifact_dir"
