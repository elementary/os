apt-get update
apt-get install -y live-build patch

patch -d /usr/lib/live/build/ < live-build-fix-syslinux.patch

./terraform.sh --config-path etc/terraform-azure.conf
cp tmp/amd64/*.iso /artifacts/
