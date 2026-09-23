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
    PROFILE={{stream}} ./assemble-iso.sh
    just compress-repo
    podman run --rm \
        --privileged \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        ghcr.io/elementary/mkosi:tanit \
        chown -R "$(id -u):$(id -g)" mkosi.output
    podman run --rm \
        --privileged \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        ghcr.io/elementary/mkosi:tanit \
        chmod -R u+rwX mkosi.output

do-daily: (_do-release "daily")

do-stable: (_do-release "stable")

_get_arch:
    @systemd-analyze architectures | awk '/native/ {print $1}'

_get_timestamp:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "$(cat ./mkosi.version)"

genkey:
    just mkosi genkey --force

mkosi +subcommand:
    mkdir -p {{env_var('HOME')}}/.cache/mkosi-workspace
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
        -v "{{env_var('HOME')}}/.cache/mkosi-workspace:/workspace" \
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
        echo "Fatal: No split partition artifacts found to compress." >&2
        exit 1
    fi
    zstd -T0 --rm -f "${split[@]}"
    ls -l elementary_*.usr-*.*.raw.zst

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

serve:
    #!/usr/bin/env bash
    cd mkosi.output
    echo "Sysupdate accessible in Gnome Boxes at http://10.0.2.2:7070"
    echo "Extensions accessible in Gnome Boxes at http://10.0.2.2:7070/ext/"
    python -m http.server 7070
