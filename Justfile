[private]
default:
    #!/usr/bin/env bash
    set -xeuo pipefail
    just --choose

_do-release stream:
    sudo HOME="${HOME}" CI="${CI:-}" bash -c ' \
    if [[ -n "${CI:-}" ]]; then touch mkosi.cache/.ci; fi && \
    just mkosi -B --debug --profile={{stream}} --force --workspace-directory=mkosi.workspace && \
    PROFILE={{stream}} SQUASHFS_LEVEL="${SQUASHFS_LEVEL:-}" ./assemble-iso.sh && \
    if [[ -z "${CI:-}" ]]; then rsync -av --ignore-existing --include="*.iso" --exclude="*" mkosi.output/ isos/; fi && \
    just compress-repo \
    '
# Built every day from the main branch
do-daily: (_do-release "daily")

# Built monthly from the main branch
do-stable: (_do-release "stable")

# Built from PRs
do-proposed: (_do-release "proposed")

_get_arch:
    @systemd-analyze architectures | awk '/native/ {print $1}'

_get_timestamp:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "$(cat ./mkosi.version)"

genkey:
    just mkosi genkey

[private]
mkosi +subcommand:
    podman run --rm \
        --network host \
        --dns 8.8.8.8 \
        --privileged \
        --security-opt label=disable \
        -v /dev:/dev \
        -v "{{invocation_directory()}}":/work \
        -w /work \
        ghcr.io/elementary/mkosi:tanit \
        mkosi {{subcommand}}

clean:
    sudo HOME="${HOME}" bash -c ' \
    just mkosi clean -ff && \
    rm -rf isos/* mkosi.cache/* mkosi.pkgcache/* \
    '

[private]
compress-repo:
    #!/usr/bin/env bash
    set -euo pipefail
    cd mkosi.output
    shopt -s nullglob
    split=(elementary_*.usr-*.*.raw)
    if [ ${#split[@]} -eq 0 ]; then
        echo "Fatal: No split OS partition artifacts found to compress." >&2
        exit 1
    fi
    drivers=(driver-*.raw)
    files=("${split[@]}" "${drivers[@]}")
    zstd -T0 --rm -f "${files[@]}"
    ls -l "${files[@]/%/.zst}"

[private]
checksum-repo:
    cd mkosi.output && \
    sha256sum elementary_*.efi \
        elementary_*.usr-*.*.raw.zst \
        > SHA256SUMS && \
    cat SHA256SUMS

[private]
checksum-ext:
    cd mkosi.output && \
    mkdir -p ext && \
    mv ext-*.raw.zst ext/ || true && \
    mv driver-*.raw.zst ext/ || true && \
    mv *addon.efi ext/ || true && \
    cd ext/ && \
    sha256sum ext-*.raw.zst > SHA256SUMS && \
    sha256sum driver-*.raw.zst >> SHA256SUMS && \
    sha256sum *addon.efi >> SHA256SUMS && \
    cat SHA256SUMS
