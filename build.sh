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

openwrt_dir="$repo_root/openwrt"
patch_path="$repo_root/patches/openwrt/0001-mediatek-add-gl-mt3600be-support.patch"
config_path="$repo_root/configs/mt3600be"
files_path="$repo_root/files"
artifact_dir="$openwrt_dir/bin/targets/mediatek/filogic"

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

for command_name in cp git make nproc rm tee; do
    require_command "$command_name"
done

require_path "$openwrt_dir"
require_path "$patch_path"
require_path "$config_path"
require_path "$files_path"

cd "$openwrt_dir"

printf 'Applying local patch...\n'
if git apply --reverse --check "$patch_path" >/dev/null 2>&1; then
    printf 'Patch already applied, skipping.\n'
else
    git apply "$patch_path"
fi

printf 'Updating and installing feeds...\n'
./scripts/feeds update -a
./scripts/feeds install -a

printf 'Configuring GL-MT3600BE build...\n'
cp "$config_path" .config
make defconfig
./scripts/diffconfig.sh | tee diffconfig.txt

printf 'Copying custom files...\n'
rm -rf files
cp -r "$files_path" files

printf 'Building firmware...\n'
make -j8 download clean world

printf 'Build complete. Artifacts are under: %s\n' "$artifact_dir"
