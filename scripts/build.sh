#!/bin/bash
set -euo pipefail

UPSTREAM_OWNER=elastic
UPSTREAM_REPO=elasticsearch
VERSION="${1}"
echo "   🏢 Org:   ${UPSTREAM_OWNER}"
echo "   📦 Proj:  ${UPSTREAM_REPO}"
echo "   🏷️  Ver:   ${VERSION}"

MAJOR_VER=$(echo "$VERSION" | cut -d. -f1)
MINOR_VER=$(echo "$VERSION" | cut -d. -f2)
PATCH_VER=$(echo "$VERSION" | cut -d. -f3)
VER_NUM=$(( 10#$MAJOR_VER * 1000000 + 10#$MINOR_VER * 1000 + 10#$PATCH_VER ))

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DISTS="${ROOT_DIR}/dists"
SRCS="${ROOT_DIR}/srcs"
PATCHES="${ROOT_DIR}/patches"

mkdir -p "${DISTS}/${VERSION}" "${SRCS}"

# ==========================================
# 👇 用户自定义构建逻辑 (示例)
# ==========================================

echo "🔧 Compiling ${UPSTREAM_OWNER}/${UPSTREAM_REPO} ${VERSION}..."

# 1. 准备阶段：安装依赖、下载代码、应用补丁等
prepare()
{
    echo "📦 [Prepare] Setting up build environment..."
    
    local TAR_FILE="${SRCS}/${VERSION}.tar.gz"
    local SRC_DIR="${SRCS}/${VERSION}"

    [ -d "${SRC_DIR}" ] && rm -rf "${SRC_DIR}"
    mkdir -p "${SRC_DIR}"
 
    if [ ! -f "${TAR_FILE}" ]; then
        wget -O "${TAR_FILE}" --quiet --show-progress \
            "https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/archive/refs/tags/v${VERSION}.tar.gz"
    fi
    tar -xzf "${TAR_FILE}" -C "${SRC_DIR}" --strip-components=1

    # patch
    "$PATCHES/patch.sh" "${SRC_DIR}" "${VERSION}" "${PATCHES}"

    echo "✅ [Prepare] Environment ready."
}

# 2. 编译阶段：核心构建命令
build()
{
    echo "🔨 [Build] Compiling source code..."

    # 构建时版本配置
    if [ "${VER_NUM}" -lt 8013000 ]; then
        JDK_BUILD=17
    elif [ "${VER_NUM}" -ge 8018000 ] && [ "${VER_NUM}" -lt 9000000 ]; then
        echo "jdk 18/19/20 are required to handle preview features in current version"
        exit 1
    else
        JDK_BUILD=21
    fi
    export PATH="/usr/lib/jvm/java-${JDK_BUILD}-openjdk/bin:${PATH}"

    # 运行时版本配置
    if [ "${VER_NUM}" -le 6006004 ]; then
        JDK_RUNTIME=1.8.0
    elif [ "${VER_NUM}" -le 7007014 ]; then
        JDK_RUNTIME=11
    elif [ "${VER_NUM}" -ge 7017014 ] && [ "${VER_NUM}" -lt 8000000 ]; then
        JDK_RUNTIME=21
    elif [ "${VER_NUM}" -le 8010002 ]; then
        JDK_RUNTIME=17
    elif [ "${VER_NUM}" -lt 8013000 ]; then
        JDK_RUNTIME=21
    elif [ "${VER_NUM}" -lt 8018000 ]; then # 8.13.* - 8.15.* 需要22，无可用，用23替代
        JDK_RUNTIME=23
    #elif [ "${VER_NUM}" -le 8018007 ]; then
    #   JDK_RUNTIME=24
    else
        # 配合 Entitlements system 回退到java安全管理器的补丁(后者在jdk24中已被移除)
        JDK_RUNTIME=23
    fi
    pcustomjavahome="/usr/lib/jvm/java-${JDK_RUNTIME}-openjdk"

    # 构建
    pushd "${SRCS}/${VERSION}"
    ./gradlew distribution:archives:linux-loongarch64-tar:assemble \
              --warning-mode=none \
              -PcustomJavaHome="${pcustomjavahome}"
    popd


    echo "✅ [Build] Compilation finished."
}

# 3. 后处理阶段：整理产物、清理临时文件、验证版本
post_build()
{
    echo "📦 [Post-Build] Organizing artifacts..."
    
    BUILD_OUT="${SRCS}/${VERSION}/distribution/archives/linux-loongarch64-tar/build/distributions/elasticsearch-${VERSION}-SNAPSHOT-linux-loongarch64.tar.gz"
    PRODUCT="${DISTS}/${VERSION}/elasticsearch-${VERSION}-linux-loongarch64.tar.gz"
    mv "${BUILD_OUT}" "${PRODUCT}"
    chown -R "${HOST_UID}:${HOST_GID}" "${DISTS}" "${SRCS}"
    
    echo "✅ [Post-Build] Artifacts ready in ./dists/${VERSION}."
}

# 主入口
main()
{
    prepare
    build
    post_build
}

main

# ==========================================
# 👆 自定义逻辑结束
# ==========================================

cat > "${DISTS}/${VERSION}/release.txt" <<EOF
Project: ${UPSTREAM_REPO}
Organization: ${UPSTREAM_OWNER}
Version: ${VERSION}
Build Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "✅ Compilation finished."
ls -lh "${DISTS}/${VERSION}"
