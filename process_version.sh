#!/bin/bash

set -euo pipefail

VERSION="$1"
MAJOR_VER=$(echo "$VERSION" | cut -d. -f1)
MINOR_VER=$(echo "$VERSION" | cut -d. -f2)
PATCH_VER=$(echo "$VERSION" | cut -d. -f3)
VER_NUM=$(( 10#$MAJOR_VER * 1000000 + 10#$MINOR_VER * 1000 + 10#$PATCH_VER ))

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
    "$PATCHES/patch.sh" "$SRCS/$SRC_DIR" "$VERSION" "$PATCHES"
}

process()
{
    # 构建时
    if [ "$VER_NUM" -lt 8013000 ]; then
        JDK_BUILD=17
    elif [ "$VER_NUM" -ge 8018000 ] && [ "$VER_NUM" -lt 9000000 ]; then
    	echo "jdk 18/19/20 are required to handle preview features in current version"
    	exit 1
    else
	JDK_BUILD=21
    fi
    export PATH="/usr/lib/jvm/java-$JDK_BUILD-openjdk/bin:$PATH"
    
    # 运行时
    if [ "$VER_NUM" -le 6006004 ]; then
        JDK_RUNTIME=1.8.0
    elif [ "$VER_NUM" -le 7007014 ]; then
        JDK_RUNTIME=11
    elif [ "$VER_NUM" -ge 7017014 ] && [ "$VER_NUM" -lt 8000000 ]; then
	JDK_RUNTIME=21
    elif [ "$VER_NUM" -le 8010002 ]; then
	JDK_RUNTIME=17
    elif [ "$VER_NUM" -lt 8013000 ]; then
        JDK_RUNTIME=21
    elif [ "$VER_NUM" -lt 8018000 ]; then # 8.13.* - 8.15.* 需要22，无可用，用23替代
	JDK_RUNTIME=23
    #elif [ "$VER_NUM" -le 8018007 ]; then
    #	JDK_RUNTIME=24
    else
	# 配合Entitlements system回退到java安全管理器的补丁(后者在jdk24中已被移除)
	JDK_RUNTIME=23
    fi
    pcustomjavahome="/usr/lib/jvm/java-$JDK_RUNTIME-openjdk"
    
    pushd "$SRCS/$PROJ-$VERSION" > /dev/null
    ./gradlew distribution:archives:linux-loongarch64-tar:assemble \
              --warning-mode=none \
              -PcustomJavaHome=$pcustomjavahome
    
    popd > /dev/null

    PRODUCT="$SRCS/$PROJ-$VERSION/distribution/archives/linux-loongarch64-tar/build/distributions/elasticsearch-$VERSION-SNAPSHOT-linux-loongarch64.tar.gz"
    TAR="$DISTS/$VERSION/elasticsearch-$VERSION-linux-loongarch64.tar.gz"
    mv $PRODUCT $TAR
}

main()
{
    prepare
    process
}

main "$@"
