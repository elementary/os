default:
    #!/usr/bin/env bash
    set -xeuo pipefail
    just --choose

_do-release stream:
    #!/usr/bin/env bash
    podman run --rm \
        --privileged \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        ghcr.io/elementary/mkosi:tanit \
        rm -rf mkosi.output/
    just mkosi -B --debug --profile={{stream}} --force --workspace-directory=/workspace && \
    PROFILE={{stream}} \
    podman run --rm \
        --privileged \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        -e PROFILE \
        ghcr.io/elementary/mkosi:tanit \
        ./assemble-iso.sh
    just compress-repo

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
    just mkosi genkey --force

mkosi +subcommand:
    mkdir -p ~/.cache/mkosi-workspace
    mkdir -p ~/.cache/mkosi

    podman run --rm \
        --network host \
        --dns 8.8.8.8 \
        --privileged \
        --security-opt label=disable \
        -v ~/.cache/mkosi:/var/cache/mkosi \
        -v /dev:/dev \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        -v ~/.cache/mkosi-workspace:/workspace \
        ghcr.io/elementary/mkosi:tanit \
        mkosi {{subcommand}}



clean:
    just mkosi clean
    podman run --rm \
        --privileged \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        ghcr.io/elementary/mkosi:tanit \
        rm -rf mkosi.tools mkosi.cache mkosi.output
    rm -rf ~/.cache/mkosi ~/.cache/mkosi-workspace

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

checksum-repo:
    #!/usr/bin/env bash
    set -euo pipefail
    cd mkosi.output
    sha256sum elementary_*.efi \
        elementary_*.usr-*.*.raw.zst \
        > SHA256SUMS
    cat SHA256SUMS

checksum-ext:
    #!/usr/bin/env bash
    cd mkosi.output
    mkdir ext
    mv {ext,driver}-*.raw.zst ext/
    mv *addon.efi ext/
    cd ext/
    sha256sum {ext,driver}-*.raw.zst > SHA256SUMS
    sha256sum *addon.efi >> SHA256SUMS
    cat SHA256SUMS
