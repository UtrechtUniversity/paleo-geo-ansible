#!/bin/sh
# Build any local image not yet published to a registry.

set -e
cd "$(dirname "$0")/images"

# shellcheck disable=SC2043  # single image today; loop kept for when more are added
for image in wordpress
do  cd "$image"
    echo "Building image $image ..."
    ./build.sh "$@"
    cd ..
done

echo "Build complete."
