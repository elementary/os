default:
    just --choose


# Built every day from the main branch
do-daily: (_do-release "daily")

# Built monthly from the main branch
do-stable: (_do-release "stable")

# Built from PRs
do-proposed: (_do-release "proposed")

_do-release stream:
    #!/usr/bin/env bash
    sudo rm -rf mkosi.output/ && \
    just genkey
    just mkosi -B --debug --profile={{stream}} --force --workspace-directory=/workspace && \
    sudo PROFILE={{stream}} SQUASHFS_LEVEL="${SQUASHFS_LEVEL:-}" ./assemble-iso.sh
    sudo just compress-repo
    sudo chown -R "$(id -u):$(id -g)" mkosi.output
    sudo chmod -R u+rwX mkosi.output

# Get arch directly from systemd, to get the same format as mkosi
_get_arch:
    @systemd-analyze architectures | awk '/native/ {print $1}'

# Get current mkosi.version value
_get_timestamp:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "$(cat ./mkosi.version)"

# > Name: Owner of the key
# > Days: Days before the key expires
# Generate a new key if there are none
genkey name=`whoami` days="730":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "./mkosi.key" ] || [ ! -f "./mkosi.crt" ]; then
        # Drop exising keys
        rm -f mkosi.key mkosi.crt
        # Like `mkosi genkey`, but with a fixed-length serial so every build's verity signature is the same size.
        # A random serial is a byte shorter 1 in 256 times, and a shorter signature written over a longer one
        # by an installed system's sysupdate leaves the old tail behind and breaks boot.
        OPENSSL_CONF=/dev/null openssl req -new -x509 -newkey rsa:2048 -keyout mkosi.key -out mkosi.crt \
            -days "{{days}}" -subj "/CN={{name}}/" -nodes -set_serial "0x40$(openssl rand -hex 19)"
        echo "Done!"
    echo "Pair has been generated, owned by {{name}}, valid for {{days}} days"
    else
        echo "Existing key pair detected, will not generate a new one."
        echo "Delete mkosi.key and mkosi.crt and rerun to generate a new pair"
    fi

mkosi +subcommand:
    #!/usr/bin/env bash
    just genkey
    just _podman_mkosi {{subcommand}}

_podman_mkosi +args:
    mkdir -p {{env_var('HOME')}}/.cache/mkosi-workspace
    sudo mkdir -p ~/.cache/mkosi
    sudo podman run --rm \
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
        mkosi {{args}}


clean:
    just mkosi clean
    sudo rm -r mkosi.tools/ mkosi.cache/ ~/.cache/mkosi/*

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
