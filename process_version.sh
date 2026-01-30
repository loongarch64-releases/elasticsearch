#!/bin/bash

set -euo pipefail

VERSION="$1"
MAJOR_VER=$(echo "${VERSION#v}" | cut -d. -f1)

ORG='elastic'
PROJ='elasticsearch'
WORKSPACE="/workspace"
SRCS="$WORKSPACE/srcs"
DISTS="$WORKSPACE/dists"
PATCHES="$WORKSPACE/patches"

mkdir -p "$SRCS" "$DISTS/$VERSION"

prepare()
{
    pushd "$SRCS" > /dev/null
    
    local ZIP_FILE="$VERSION.zip"
    if [ ! -f "$ZIP_FILE" ]; then
        wget -O "$ZIP_FILE" --quiet --show-progress \
            "https://github.com/$ORG/$PROJ/archive/refs/tags/v$VERSION.zip"
    fi
    
    local SRC_DIR="$PROJ-${VERSION#v}"
    if [ -d "$SRC_DIR" ]; then rm -rf "$SRC_DIR"; fi
    unzip -q "$ZIP_FILE"
    
    popd > /dev/null

    # 补丁
    "$PATCHES/patch.sh" "$SRCS/$SRC_DIR" "${VERSION#v}"
}

build()
{
    # 根据 es 需求切换 jdk 版本
    if [ "$MAJOR_VER" -lt 8 ]; then
        export JAVA_HOME="/usr/lib/jvm/java-1.8.0-openjdk"
    else
        export JAVA_HOME="/usr/lib/jvm/java-17-openjdk"
    fi
    export PATH=$JAVA_HOME/bin:$PATH

    pushd "$SRCS/$PROJ-${VERSION#v}" > /dev/null
    ./gradlew distribution:archives:linux-loongarch64-tar:assemble \
              --warning-mode=none \
              -PcustomJavaHome=$JAVA_HOME
    
    popd > /dev/null
}

post_build()
{
    local TARGET_BASE="$SRCS/$PROJ-${VERSION#v}/distribution/archives/linux-loongarch64-tar/build/install/"
    local TARGET="elasticsearch-${VERSION#v}-SNAPSHOT"
    TAR="elasticsearch-${VERSION#v}-linux-loongarch64.tar.gz"

    rm -rf "$TARGET_BASE/$TARGET/modules/x-pack-ml"
    tar -C "$TARGET_BASE" -czf "$DISTS/$VERSION/$TAR" "$TARGET"
}

main()
{
    prepare
    build
    post_build
}

main "$@"
