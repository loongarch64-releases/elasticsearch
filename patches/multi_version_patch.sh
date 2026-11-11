#!/bin/bash
# 不同版本的适配处理
set -euo pipefail

src=$1
version=$2
patches=$3
IFS=. read -r major_ver minor_ver patch_ver <<< "$version"
ver_num=$(( 10#$major_ver * 1000000 + 10#$minor_ver * 1000 + 10#$patch_ver ))

if [ "$ver_num" -ge 8005000 ] && [ "$ver_num" -le 8006001 ]; then
    sed -i "s/e335c10679f743207d822c5f7948e930319835492575a9dba6b94f8a3b96fcc8/ef501d3052f08e697cb2430d355975270b2882c76f95cc78ddb9f1c69526b66d/" "$src/gradle/verification-metadata.xml"
    sed -i "s/42e020705692eddbd285e2b72ef0ff468f51a926382569c45f4e9cea4602ad1e/8b3e544c3c6fd66beeeadb21c17a32ff49a91662499b88573948e6f28b152992/" "$src/gradle/verification-metadata.xml"
    sed -i "s/d74a3334fb35195009b338a951f918203d6bbca3d1d359033dc33edd1cadc9ef/91e99c60c7fdccefa84fa33a3145d63b2edd812e15955069b9e330e7442740d1/" "$src/gradle/verification-metadata.xml"
fi

if [ "$ver_num" -ge 8013000 ]; then
    ElasticsearchJavaBasePlugin="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/ElasticsearchJavaBasePlugin.java"
    # 禁用jdk 21引入的警告[this-escape]
    sed -i 's/compilerArgs.add("-Xlint:all/compilerArgs.add("-Xlint:all,-this-escape/' $ElasticsearchJavaBasePlugin
    if [ "$ver_num" -ge 8014000 ]; then
        # 使用 jna 5.13.0 (5.12.1是Glibc 2.35编的)
        sed -i "s/5.12.1/5.13.0/" "$src/build-tools-internal/version.properties"

        # 去掉一些"警告"错误
        sed -i 's/compilerArgs.add("-Werror");//' $ElasticsearchJavaBasePlugin
        sed -i "s/-Xdoclint:all/-Xdoclint:none/" $ElasticsearchJavaBasePlugin
    fi
fi

# SystemCallFilter 添加 loongarch 支持
if [ "$major_ver" -lt 8 ]; then
    sed -i '/0xC00000B7/a\
            m.put("loongarch64", new Arch(0xC0000102, 0xFFFFFFFF, 1079, 1071, 221, 281, 277));' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
elif [ "$ver_num" -ge 8000000 ] && [ "$ver_num" -lt 8016000 ]; then
    sed -i '/0xC00000B7/s/$/,/' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
    sed -i '/0xC00000B7/a\
            "loongarch64",\
            new Arch(0xC0000102, 0xFFFFFFFF, 1079, 1071, 221, 281, 277)' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
else
    sed -i '/new Arch(0xC000003E, 0x3FFFFFFF, 57, 58, 59, 322, 317),/a\
            "loongarch64",\
            new Arch(0xC0000102, 0xFFFFFFFF, 1079, 1071, 221, 281, 277),' "$src/libs/native/src/main/java/org/elasticsearch/nativeaccess/LinuxNativeAccess.java"
fi

# 运行时架构适配
if [ "$ver_num" -ge 9005000 ]; then
    LoaderHelper="$src/libs/foreign-library/src/main/java/org/elasticsearch/foreign/LoaderHelper.java"
    sed -i 's/archname.equals("aarch64")/archname.equals("aarch64") || archname.equals("loongarch64")/' "$LoaderHelper"
fi
if [ "$ver_num" -ge 9005006 ]; then
    ModulePlatforms="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/distribution/ModulePlatforms.java"
    ModulePlatformsTests="$src/build-tools-internal/src/test/java/org/elasticsearch/gradle/internal/distribution/ModulePlatformsTests.java"
    sed -i '/"linux-aarch64",/a\
        "linux-loongarch64",' $ModulePlatforms
    sed -i '/assertEquals("linux-aarch64"/a\
        assertEquals("linux-loongarch64", ModulePlatforms.directory("linux", "loongarch64"));' $ModulePlatformsTests
    sed -i 's/List.of("/List.of("linux-loongarch64", "/' $ModulePlatformsTests
    sed -i '/public void excludedDirectoriesKeepOnlyTargetPlatform() {/a\
        assertEquals(\
            List.of("linux-x86_64", "linux-aarch64", "windows-x86_64", "darwin-x86_64", "darwin-aarch64"),\
            ModulePlatforms.excludedDirectories("linux", "loongarch64")\
        );' $ModulePlatformsTests
fi

# 9.5.6 新增的构建工具类需要适配
# 删除 distribution/docker 项目不会阻止 build-tools-internal 编译这些类
if [ "$ver_num" -ge 9005006 ]; then
    for file in \
        "$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/docker/DockerVariant.java" \
        "$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/distribution/PackageMetadata.java"; do
        [ -f "$file" ] || continue
        sed -i '/case AARCH64 ->/{
   h
   p
   x
   s/AARCH64/LOONGARCH64/g
   s/Aarch64/Loongarch64/g
   s/aarch64/loongarch64/g
   s/arm64/loong64/g
}' "$file"
    done
fi

# 模拟 gradle java toolchain，以适应 es 的多版本 jdk 构建需求
$patches/java_toolchain.sh $src $ver_num
