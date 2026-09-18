default:
    #!/usr/bin/env bash
    set -xeuo pipefail
    just --choose

_do-release profile:
    #!/usr/bin/env bash
    sudo rm -rf mkosi.output/ && \
    just run-in-podman mkosi -B --debug --profile={{profile}} --profile=$(uname -m | tr '_' '-') --force --workspace-directory=/workspace && \
    sudo PROFILE={{profile}} ./assemble-iso.sh
    sudo chown -R "$(id -u):$(id -g)" mkosi.output
    sudo chmod -R u+rwX mkosi.output

do-daily: (_do-release "daily")

do-stable: (_do-release "stable")

_get_arch:
    @uname -m | sed -e 's/x86_64/x86-64/' -e 's/aarch64/arm64/'


_get_timestamp:
    #!/usr/bin/env bash
    set -euo pipefail
    FILE_PATH=$(ls -d mkosi.output/base_* 2>/dev/null | head -n 1 || true)
    TIMESTAMP=$(basename "$FILE_PATH" | grep -oE '[0-9]{14}' | head -n 1 || true)
    if [ -z "$TIMESTAMP" ]; then
        echo "Fatal: No timestamped file found."
        exit 1
    fi
    echo "$TIMESTAMP"

genkey:
    just run-in-podman mkosi genkey

run-in-podman +command:
    mkdir -p {{env_var('HOME')}}/.cache/mkosi-workspace
    sudo mkdir -p ~/.cache/mkosi

    sudo podman run --rm -it \
        --network host \
        --dns 8.8.8.8 \
        --privileged \
        --platform linux/$(arch) \
        --security-opt label=disable \
        -v ~/.cache/mkosi:/var/cache/mkosi \
        -v /dev:/dev \
        -v "{{invocation_directory()}}:/work" \
        -w /work \
        -v "{{env_var('HOME')}}/.cache/mkosi-workspace:/workspace" \
        ghcr.io/elementary/mkosi:tanit \
        {{command}}



clean:
    just run-in-podman mkosi clean
    sudo rm -r mkosi.tools/ mkosi.cache/ ~/.cache/mkosi/*

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
