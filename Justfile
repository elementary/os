default:
    #!/usr/bin/env bash
    set -xeuo pipefail
    just --choose

_do-release profile:
    #!/usr/bin/env bash
    sudo rm -rf mkosi.output/ && \
    just run-in-podman mkosi -B --debug --profile={{profile}} --profile=$(uname -m | tr '_' '-') --force --workspace-directory=/workspace && \
    sudo ./assemble-iso.sh
    sudo chown -R "$(id -u):$(id -g)" mkosi.output
    sudo chmod -R u+rwX mkosi.output

do-daily: (_do-release "daily")

do-stable: (_do-release "stable")


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
        ghcr.io/jumpyvi/mkosi:tanit \
        {{command}}



clean:
    just run-in-podman mkosi clean
    sudo rm -r mkosi.tools/ mkosi.cache/ ~/.cache/mkosi/*

checksum-repo:
    #!/usr/bin/env bash
    cd mkosi.output
    sha256sum elementary_*.efi \
        elementary_*.usr-*.*.raw.zst \
        elementary_*.usr-*-verity.*.raw.zst \
        elementary_*.usr-*-verity-sig.*.raw.zst \
        > SHA256SUMS
    cat SHA256SUMS

checksum-ext:
    #!/usr/bin/env bash
    cd mkosi.output
    mkdir ext
    mv ext-*.raw.zst ext/
    cd ext/
    sha256sum ext-*.raw.zst > SHA256SUMS
    cat SHA256SUMS

serve:
    #!/usr/bin/env bash
    cd mkosi.output
    echo "Sysupdate accessible in Gnome Boxes at http://10.0.2.2:7070"
    echo "Extensions accessible in Gnome Boxes at http://10.0.2.2:7070/ext/"
    python -m http.server 7070
