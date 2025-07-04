#!/bin/bash

set -e

CONFIG_FILE="$1"
KEY="$2"
SECRET="$3"
ENDPOINT="$4"
BUCKET="$5"

./build-arm64.sh "$CONFIG_FILE"
./upload.sh "$CONFIG_FILE" "$KEY" "$SECRET" "$ENDPOINT" "$BUCKET"
