#!/bin/bash
set -euo pipefail

src=$1
version=$2
patches=$3
IFS=. read -r major_ver minor_ver patch_ver <<< "$version"
ver_num=$((10#$major_ver * 1000000 + 10#$minor_ver * 1000 + 10#$patch_ver))

# 配置 loongson MAVEN 环境
maven_config()
{
    cat > $patches/insert_block << 'EOF'
    maven {
      url "https://maven.loongnix.cn/loongarch/maven/"
      content {
        includeModule "net.java.dev.jna", "jna"
        includeModule "net.java.dev.jna", "jna-platform"
        includeModule "org.lz4", "lz4-java"
        includeModule "com.google.protobuf", "protoc"
      }
    }
EOF
    if [ "$ver_num" -lt 7017020 ] || [ "$ver_num" -gt 7017029 ]; then
        sed -i "/repositories {/r $patches/insert_block" "$src/settings.gradle"
    fi
    sed -i "/repositories {/r $patches/insert_block" "$src/build-conventions/build.gradle"
    sed -i "/repositories {/r $patches/insert_block" "$src/.ci/init.gradle"
    sed -i "/repositories {/r $patches/insert_block" "$src/build-tools/build.gradle"
    sed -i "/mavenCentral()/i //INSERT HEAD" "$src/build-tools-internal/build.gradle"
    sed -i "/INSERT HEAD/r $patches/insert_block" "$src/build-tools-internal/build.gradle"
    sed -i "/INSERT HEAD/d" "$src/build-tools-internal/build.gradle"

    cat > $patches/insert_block << 'EOF'
  repositories {
    maven {
      url "https://maven.loongnix.cn/loongarch/maven/"
      content {
        includeModule "net.java.dev.jna", "jna"
        includeModule "net.java.dev.jna", "jna-platform"
        includeModule "org.lz4", "lz4-java"
        includeModule "com.google.protobuf", "protoc"
      }
    }
  }
EOF
    sed -i "/allprojects {/r $patches/insert_block" "$src/build.gradle"
}

patch()
{
    echo "patching ..."

    maven_config
    # 多版本通用补丁
    "$patches/universal_patch.sh" "$src" "$version" "$patches"
    # 不同版本的适配处理
    "$patches/multi_version_patch.sh" "$src" "$version" "$patches"
    
    rm $patches/insert_block
    echo "done"
}

patch

