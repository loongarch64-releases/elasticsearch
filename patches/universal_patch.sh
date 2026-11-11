#!/bin/bash
# 各版本通用的处理步骤
set -euo pipefail

src=$1
version=$2
patches=$3

# 添加 loongarch 项目
sed -i "/'distribution:archives:linux-aarch64-tar',/a\\
  'distribution:archives:linux-loongarch64-tar'," "$src/settings.gradle"
cp -r "$src/distribution/archives/linux-aarch64-tar" "$src/distribution/archives/linux-loongarch64-tar"

# build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/Jdk.java
sed -i 's#private static final List<String> ALLOWED_ARCHITECTURES = List.of("aarch64", "x64");#private static final List<String> ALLOWED_ARCHITECTURES = List.of("aarch64", "x64", "loongarch64");#' "$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/Jdk.java"

# build-tools/src/main/java/org/elasticsearch/gradle/Architecture.java
sed -i '/AARCH64(/{
   h
   s/;$/,/
   p
   x
   s/AARCH/LOONGARCH/g
   s/aarch/loongarch/g
   s/arm/loongarch/g
}' "$src/build-tools/src/main/java/org/elasticsearch/gradle/Architecture.java"

sed -i '/case "aarch64"/{
   h
   p
   x
   s/AARCH/LOONGARCH/g
   s/aarch/loongarch/g
   s/arm/loongarch/g
}' "$src/build-tools/src/main/java/org/elasticsearch/gradle/Architecture.java"

# distribution/archives/build.gradle
file="$src/distribution/archives/build.gradle"
start=$(grep -n "linuxAarch64Tar" "$file" | cut -d: -f1)
sed -n "${start},$((start+6))p" "$file" > block.tmp
sed -i \
    -e 's/Aarch/Loongarch/g' \
    -e 's/aarch/loongarch/g' \
    block.tmp
sed -i "$((start+6))r block.tmp" $file
rm block.tmp

# 准备 zstd 原生库
zstd_library=$(find /usr/lib -name libzstd.so.1 -print -quit)
if [ -z "$zstd_library" ]; then
    echo "Cannot find libzstd.so.1 under /usr/lib" >&2
    exit 1
fi
mkdir -p "$src/libs/native/libraries/loongarch64"
cp -L "$zstd_library" "$src/libs/native/libraries/loongarch64/libzstd.so"
sed -i '/from configurations.libs/a\
  from("loongarch64/libzstd.so") {\
    into "linux-loongarch64"\
  }' "$src/libs/native/libraries/build.gradle"

# 去掉 SHA 256 检查
echo "org.gradle.dependency.verification=off" >> "$src/gradle.properties"

# 删除 dockerx 项目
sed -i "/'distribution:docker/d" "$src/settings.gradle"
rm -rf "$src/distribution/docker/"

# ml 插件
deps_zip="$src/../ml-cpp-$version-deps.zip"
nodeps_zip="$src/../ml-cpp-$version-nodeps.zip"
wget -O "$deps_zip" --quiet --show-progress "https://github.com/loongarch64-releases/ml-cpp/releases/download/v$version/ml-cpp-$version-deps.zip"
wget -O "$nodeps_zip" --quiet --show-progress "https://github.com/loongarch64-releases/ml-cpp/releases/download/v$version/ml-cpp-$version-nodeps.zip"
perl -i -0777 -pe 's/  nativeBundle\("org\.elasticsearch\.ml:ml-cpp:\$\{mlCppVersion\(\)\}:deps\@zip"\) \{\n    changing = true\n  \}\n  nativeBundle\("org\.elasticsearch\.ml:ml-cpp:\$\{mlCppVersion\(\)\}:nodeps\@zip"\) \{\n    changing = true\n  \}/  nativeBundle files("__ML_CPP_DEPS__")\n  nativeBundle files("__ML_CPP_NODEPS__")/g' "$src/x-pack/plugin/ml/build.gradle"
sed -i "s|__ML_CPP_DEPS__|$deps_zip|" "$src/x-pack/plugin/ml/build.gradle"
sed -i "s|__ML_CPP_NODEPS__|$nodeps_zip|" "$src/x-pack/plugin/ml/build.gradle"

# bundled JKD：使用本地 jdk
"$patches/bundled_jdk.sh" "$src"

