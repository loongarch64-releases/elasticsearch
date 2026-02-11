#!/bin/sh

src=$1
version=$2
major_ver=$(echo "$version" | cut -d. -f1)
minor_ver=$(echo "$version" | cut -d. -f2)
patch_ver=$(echo "$version" | cut -d. -f3)

echo "patching ..."

# 配置 loongson MAVEN 环境
cat > insert_block.txt << 'EOF'
    exclusiveContent {
      forRepository {
        maven {
          url "https://maven.loongnix.cn/loongarch/maven/"
        }
      }
      filter {
        includeModule "net.java.dev.jna", "jna"
        includeModule "net.java.dev.jna", "jna-platform"
        includeModule "org.lz4", "lz4-java"
      }
    }  
EOF
if !([ "$major_ver" -eq 7 ] && [ "$minor_ver" -eq 17 ] && [ "$patch_ver" -le 29 ] && [ "$patch_ver" -ge 20 ] ); then
  sed -i "/repositories {/r insert_block.txt" "$src/settings.gradle"
fi
sed -i "/repositories {/r insert_block.txt" "$src/build-conventions/build.gradle"
sed -i "/repositories {/r insert_block.txt" "$src/.ci/init.gradle"
sed -i "/repositories {/r insert_block.txt" "$src/build-tools/build.gradle"
sed -i "/mavenCentral()/i //INSERT HEAD" "$src/build-tools-internal/build.gradle"
sed -i "/INSERT HEAD/r insert_block.txt" "$src/build-tools-internal/build.gradle"
sed -i "/INSERT HEAD/d" "$src/build-tools-internal/build.gradle"
rm -f insert_block.txt

cat > insert_block.txt << 'EOF'
  repositories {
    exclusiveContent {
      forRepository {
        maven {
          url "https://maven.loongnix.cn/loongarch/maven/"
        }
      }
      filter {
        includeModule "net.java.dev.jna", "jna"
        includeModule "net.java.dev.jna", "jna-platform"
        includeModule "org.lz4", "lz4-java"
      }
    }
  }
EOF
sed -i "/allprojects {/r insert_block.txt" "$src/build.gradle"
rm -f insert_block.txt

if [[ "$major_ver" -eq 8 && ( "$minor_ver" -eq 5 || ( "$minor_ver" -eq 6 && "$patch_ver" -le 1 )) ]]; then
    sed -i "s/e335c10679f743207d822c5f7948e930319835492575a9dba6b94f8a3b96fcc8/ef501d3052f08e697cb2430d355975270b2882c76f95cc78ddb9f1c69526b66d/" "$src/gradle/verification-metadata.xml"
    sed -i "s/42e020705692eddbd285e2b72ef0ff468f51a926382569c45f4e9cea4602ad1e/8b3e544c3c6fd66beeeadb21c17a32ff49a91662499b88573948e6f28b152992/" "$src/gradle/verification-metadata.xml"
    sed -i "s/d74a3334fb35195009b338a951f918203d6bbca3d1d359033dc33edd1cadc9ef/91e99c60c7fdccefa84fa33a3145d63b2edd812e15955069b9e330e7442740d1/" "$src/gradle/verification-metadata.xml"
fi

# SystemCallFilter 添加 loongarch 支持
if [ "$major_ver" -eq 8 ] && [ "$minor_ver" -lt 16 ]; then
    sed -i '/0xC00000B7/s/$/,/' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
    sed -i '/0xC00000B7/a\
            "loongarch64",\
            new Arch(0xC0000102, 0xFFFFFFFF, 1079, 1071, 221, 281, 277)' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
fi

#if [ "$major_ver" -lt 8 ]; then
#    sed -i '/0xC00000B7/a\
#	    m.put("loongarch64", new Arch(0xC00000B7, 0xFFFFFFFF, 1079, 1071, 221, 281, 277));' "$src/server/src/main/java/org/elasticsearch/bootstrap/SystemCallFilter.java"
#fi

# 修改 server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java
sed -i 's#if (isSystemCallFilterInstalled() == false)#if(isSystemCallFilterInstalled() == false \&\& !"loongarch64".equals(System.getProperty("os.arch")))#' "$src/server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java"

# 修改 build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/Jdk.java
sed -i 's#private static final List<String> ALLOWED_ARCHITECTURES = List.of("aarch64", "x64");#private static final List<String> ALLOWED_ARCHITECTURES = List.of("aarch64", "x64", "loongarch64");#' "$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/Jdk.java"

# 修改 server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java
sed -i 's#if(isSystemCallFilterInstalled() == false)#if(isSystemCallFilterInstalled() == false \&\& !"loongarch64".equals(System.getProperty("os.arch")))#' "$src/server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java"

# 修改 settings.gradle
sed -i "/'distribution:archives:linux-aarch64-tar',/a\\
  'distribution:archives:linux-loongarch64-tar'," "$src/settings.gradle"

# 修改 build-tools/src/main/java/org/elasticsearch/gradle/Architecture.java
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

# 修改 distribution/build.gradle
if [ "$major_ver" -gt 8 ] || { [ "$major_ver" -eq 8 ] && [ "$minor_ver" -ge 13 ]; }; then
    sed -i '/if (os != null) {/{
    N
    /String platform/s/if (os != null)/if (os != null \&\& architecture != '\''loongarch64'\'')/
}' "$src/distribution/build.gradle"
else
    sed -i 's#if (platform != null)#if (platform != null \&\& platform in excludePlatforms)#' "$src/distribution/build.gradle"
fi

cat > insert_block.txt << 'EOF'
        if (architecture == 'loongarch64') {
          // use local JDK from JAVA_HOME
          def javaHome = project.findProperty('customJavaHome') ?: System.getenv('JAVA_HOME')
          if (!javaHome) {
            throw new GradleException("JAVA_HOME must be set when building for loongarch64")
          }
          from(new File(javaHome)) {
            exclude "demo/**"
            eachFile { FileCopyDetails details ->
              if (details.relativePath.segments[-2] == 'bin' || details.relativePath.segments[-1] == 'jspawnhelper') {
                details.mode = 0755
              }
              if (details.name == 'src.zip') {
                details.exclude()
              }
            }
          }
        } else {
EOF
sed -i "/return copySpec {/r insert_block.txt" "$src/distribution/build.gradle"
rm -f insert_block.txt

tac "$src/distribution/build.gradle" | \
sed "0,/if (details\\.name == 'src\\.zip') {/s//if (details.name == 'src.zip')/" | \
tac > "$src/distribution/build.gradle.tmp" && \
mv "$src/distribution/build.gradle.tmp" "$src/distribution/build.gradle"

# 修改 distribution/archives/build.gradle
file="$src/distribution/archives/build.gradle"
start=$(grep -n "linuxAarch64Tar" "$file" | cut -d: -f1)
sed -n "${start},$((start+6))p" "$file" > block.tmp
sed -i \
    -e 's/Aarch/Loongarch/g' \
    -e 's/aarch/loongarch/g' \
    block.tmp
sed -i "$((start+6))r block.tmp" $file
rm block.tmp

# 删除直接或间接依赖 ml 的插件
cat > insert_block.txt << 'EOF'
  if (dir.name == 'ml' && path.startsWith(':x-pack:plugin')) return
EOF

if [ "$major_ver" -gt 8 ] || { [ "$major_ver" -eq 8 ] && [ "$minor_ver" -ge 11 ]; }; then
    echo "  if (dir.name == 'inference' && path.startsWith(':x-pack:plugin')) return" >> insert_block.txt
fi

if [ "$major_ver" -gt 8 ] || { [ "$major_ver" -eq 8 ] && [ "$minor_ver" -ge 13 ]; }; then
   echo "  if (dir.name == 'consistency-checks' && path.startsWith(':x-pack:plugin:security:qa')) return" >> insert_block.txt
fi

if [ "$major_ver" -gt 8 ] || { [ "$major_ver" -eq 8 ] && [ "$minor_ver" -ge 16 ]; }; then
    echo "  if (dir.name == 'esql' && path.startsWith(':x-pack:plugin')) return
  if (dir.name == 'rank-rrf' && path.startsWith(':x-pack:plugin')) return
  if (dir.name == 'amazon-ec2' && path.startsWith(':plugins:discovery-ec2:qa')) return
  if (dir.name == 'multi-cluster' && path.startsWith(':x-pack:plugin:security:qa')) return" >> insert_block.txt
    sed -i "s|'benchmarks',|//'benchmarks',|" "$src/settings.gradle"
fi

sed -i "/void addSubProjects(String path, File dir) {/r insert_block.txt" "$src/settings.gradle"
rm -f insert_block.txt

echo "org.gradle.dependency.verification=off" >> "$src/gradle.properties"

# 删除 dockerx 项目
rm -rf "$src/distribution/docker/"

echo "done"
