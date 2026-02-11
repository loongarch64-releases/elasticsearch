#!/bin/bash

set -euo pipefail

VERSION="$1"
MAJOR_VER=$(echo "$VERSION" | cut -d. -f1)
MINOR_VER=$(echo "$VERSION" | cut -d. -f2)
PATCH_VER=$(echo "$VERSION" | cut -d. -f3)

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
    
    local ZIP_FILE="$PROJ-$VERSION.tar.gz"
    if [ ! -f "$ZIP_FILE" ]; then
        wget -O "$ZIP_FILE" --quiet --show-progress \
            "https://github.com/$ORG/$PROJ/archive/refs/tags/v$VERSION.tar.gz"
    fi
    
    local SRC_DIR="$PROJ-$VERSION"
    if [ -d "$SRC_DIR" ]; then rm -rf "$SRC_DIR"; fi
    mkdir -p "$SRC_DIR"
    tar -xzf "$ZIP_FILE" -C "$SRC_DIR" --strip-components=1
    
    popd > /dev/null

    # patch
    "$PATCHES/patch.sh" "$SRCS/$SRC_DIR" "$VERSION"
}

build()
{
    # 使用各版本支持的最高long-term运行时(ci目前最高支持到8.12.2，构建时均使用17)
    if [ "$MAJOR_VER" -lt 6 ] || ([ "$MAJOR_VER" -eq 6 ] && [ "$MINOR_VER" -le 4 ]); then
        JDK_VER=1.8.0
    elif [ "$MAJOR_VER" -lt 7 ] || ([ "$MAJOR_VER" -eq 7 ] && [ "$MINOR_VER" -le 14 ]); then
        JDK_VER=11
    elif [ "$MAJOR_VER" -eq 7 ] && [ "$MINOR_VER" -eq 17 ] && [ "$PATCH_VER" -ge 14 ]; then
        JDK_VER=21
    elif [ "$MAJOR_VER" -lt 8 ] || ([ "$MAJOR_VER" -eq 8 ] && [ "$MINOR_VER" -le 9 ]); then
        JDK_VER=17
    else
        JDK_VER=21
    fi

    pcustomjavahome="/usr/lib/jvm/java-$JDK_VER-openjdk"
    pushd "$SRCS/$PROJ-$VERSION" > /dev/null
    ./gradlew distribution:archives:linux-loongarch64-tar:assemble \
              --warning-mode=none \
              -PcustomJavaHome=$pcustomjavahome
    
    popd > /dev/null
}

post_build()
{
    local TARGET_BASE="$SRCS/$PROJ-$VERSION/distribution/archives/linux-loongarch64-tar/build/install/"
    local TARGET="elasticsearch-$VERSION-SNAPSHOT"
    TAR="elasticsearch-$VERSION-linux-loongarch64.tar.gz"

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
