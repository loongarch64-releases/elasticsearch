#!/bin/bash

src=$1
version=$2
patches=$3
major_ver=$(echo "$version" | cut -d. -f1)
minor_ver=$(echo "$version" | cut -d. -f2)
patch_ver=$(echo "$version" | cut -d. -f3)
ver_num=$(( 10#$major_ver * 1000000 + 10#$minor_ver * 1000 + 10#$patch_ver ))


# 配置 loongson MAVEN 环境
maven_config()
{
    cat > insert_block << 'EOF'
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
        sed -i "/repositories {/r insert_block" "$src/settings.gradle"
    fi
    sed -i "/repositories {/r insert_block" "$src/build-conventions/build.gradle"
    sed -i "/repositories {/r insert_block" "$src/.ci/init.gradle"
    sed -i "/repositories {/r insert_block" "$src/build-tools/build.gradle"
    sed -i "/mavenCentral()/i //INSERT HEAD" "$src/build-tools-internal/build.gradle"
    sed -i "/INSERT HEAD/r insert_block" "$src/build-tools-internal/build.gradle"
    sed -i "/INSERT HEAD/d" "$src/build-tools-internal/build.gradle"
    rm -f insert_block

    cat > insert_block << 'EOF'
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
    sed -i "/allprojects {/r insert_block" "$src/build.gradle"
    rm -f insert_block
}

# 各版本通用的处理步骤
universal_adaptation()
{
    # 添加 loongarch 项目
    sed -i "/'distribution:archives:linux-aarch64-tar',/a\\
  'distribution:archives:linux-loongarch64-tar'," "$src/settings.gradle"
    cp -r "$src/distribution/archives/linux-aarch64-tar" "$src/distribution/archives/linux-loongarch64-tar"

    # server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java
    sed -i 's#if (isSystemCallFilterInstalled() == false)#if(isSystemCallFilterInstalled() == false \&\& !"loongarch64".equals(System.getProperty("os.arch")))#' "$src/server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java"

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

    # 去掉 SHA 256 检查
    echo "org.gradle.dependency.verification=off" >> "$src/gradle.properties"

    # 删除 dockerx 项目
    sed -i "/'distribution:docker/d" "$src/settings.gradle"
    rm -rf "$src/distribution/docker/"

    # ml 插件处理
    ## 去掉 ml 插件以及 ml 相关模块
    #$patches/remove_ml.sh $src $ver_num
    ## 包含 ml 插件
    local deps_zip="$src/../ml-cpp-$version-deps.zip"
    local nodeps_zip="$src/../ml-cpp-$version-nodeps.zip"
    wget -O "$deps_zip" --quiet --show-progress "https://github.com/loongarch64-releases/ml-cpp/releases/download/v$version/ml-cpp-$version-deps.zip"
    wget -O "$nodeps_zip" --quiet --show-progress "https://github.com/loongarch64-releases/ml-cpp/releases/download/v$version/ml-cpp-$version-nodeps.zip"
    perl -i -0777 -pe 's/  nativeBundle\("org\.elasticsearch\.ml:ml-cpp:\$\{mlCppVersion\(\)\}:deps\@zip"\) \{\n    changing = true\n  \}\n  nativeBundle\("org\.elasticsearch\.ml:ml-cpp:\$\{mlCppVersion\(\)\}:nodeps\@zip"\) \{\n    changing = true\n  \}/  nativeBundle files("__ML_CPP_DEPS__")\n  nativeBundle files("__ML_CPP_NODEPS__")/g' "$src/x-pack/plugin/ml/build.gradle"
    sed -i "s|__ML_CPP_DEPS__|$deps_zip|" "$src/x-pack/plugin/ml/build.gradle"
    sed -i "s|__ML_CPP_NODEPS__|$nodeps_zip|" "$src/x-pack/plugin/ml/build.gradle"
}

# 不同版本的适配处理
multi_version_adaptation()
{
    if [ "$ver_num" -ge 8005000 ] && [ "$ver_num" -le 8006001 ]; then
        sed -i "s/e335c10679f743207d822c5f7948e930319835492575a9dba6b94f8a3b96fcc8/ef501d3052f08e697cb2430d355975270b2882c76f95cc78ddb9f1c69526b66d/" "$src/gradle/verification-metadata.xml"
        sed -i "s/42e020705692eddbd285e2b72ef0ff468f51a926382569c45f4e9cea4602ad1e/8b3e544c3c6fd66beeeadb21c17a32ff49a91662499b88573948e6f28b152992/" "$src/gradle/verification-metadata.xml"
        sed -i "s/d74a3334fb35195009b338a951f918203d6bbca3d1d359033dc33edd1cadc9ef/91e99c60c7fdccefa84fa33a3145d63b2edd812e15955069b9e330e7442740d1/" "$src/gradle/verification-metadata.xml"
    fi

    # SystemCallFilter 添加 loongarch 支持
    if [ "$ver_num" -ge 8000000 ] && [ "$ver_num" -lt 8016000 ]; then
        sed -i '/0xC00000B7/s/$/,/' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
        sed -i '/0xC00000B7/a\
            "loongarch64",\
            new Arch(0xC0000102, 0xFFFFFFFF, 1079, 1071, 221, 281, 277)' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
    fi

    if [ "$major_ver" -lt 8 ]; then
        sed -i '/0xC00000B7/a\
	    m.put("loongarch64", new Arch(0xC0000102, 0xFFFFFFFF, 1079, 1071, 221, 281, 277));' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
    fi

    # distribution/build.gradle
    if [ "$ver_num" -ge 8013000 ]; then
        sed -i '/if (os != null) {/{
    N
    /String platform/s/if (os != null)/if (os != null \&\& architecture != '\''loongarch64'\'')/
}' "$src/distribution/build.gradle"
    else
        sed -i 's#if (platform != null)#if (platform != null \&\& platform in excludePlatforms)#' "$src/distribution/build.gradle"
    fi

    cat > insert_block << 'EOF'
        if (architecture == 'loongarch64') {
          // use local JDK from JAVA_HOME
          def javaHome = project.findProperty('customJavaHome') ?: System.getenv('JAVA_HOME')
          if (!javaHome) {
            throw new GradleException("customJavaHome or JAVA_HOME must be set")
          }
          from(new File(javaHome)) {
            exclude "demo/**"
            eachFile { FileCopyDetails details ->
              if (details.relativePath.segments[-2] == 'bin' || details.relativePath.segments[-1] == 'jspawnhelper') {
                PERMISSION_SETTING
              }
              if (details.name == 'src.zip') {
                details.exclude()
              }
            }
          }
        } else {
EOF
    if [ $ver_num -ge 8014002 ]; then
        sed -i "s/PERMISSION_SETTING/details.permissions {\\
                  unix(0755)\\
                }\\
              } else {\\
                details.permissions {\\
                  unix(0644)\\
                }/" insert_block
    else
        sed -i "s/PERMISSION_SETTING/details.mode = 0755/" insert_block
    fi
    sed -i "/return copySpec {/r insert_block" "$src/distribution/build.gradle"
    rm -f insert_block

    tac "$src/distribution/build.gradle" | \
    sed "0,/if (details\\.name == 'src\\.zip') {/s//if (details.name == 'src.zip')/" | \
    tac > "$src/distribution/build.gradle.tmp" && \
    mv "$src/distribution/build.gradle.tmp" "$src/distribution/build.gradle"

    # 模拟 gradle java toolchain，以适应 es 的多版本 jdk 构建需求
    $patches/java_toolchain.sh $src $ver_num
}

patch()
{
    echo "patching ..."

    maven_config
    universal_adaptation
    multi_version_adaptation
    
    echo "done"
}

patch

