#!/bin/sh

src=$1
version=$2
major_ver=$(echo "$version" | cut -d. -f1)
minor_ver=$(echo "$version" | cut -d. -f2)
patch_ver=$(echo "$version" | cut -d. -f3)

echo "patching ..."

# 配置 loongson MAVEN 环境
cat > insert_block.txt << 'EOF'
    maven {
      url "https://maven.loongnix.cn/loongarch/maven/"
      content {
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
    maven {
      url "https://maven.loongnix.cn/loongarch/maven/"
      content {
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

# >= 8.13.0适配
if [ "$major_ver" -gt 8 ] || ([ "$major_ver" -eq 8 ] && [ "$minor_ver" -ge 13 ]); then
    ElasticsearchJavaBasePlugin="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/ElasticsearchJavaBasePlugin.java"
    MrjarPlugin="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/MrjarPlugin.java"

    # 禁用jdk 21引入的警告[this-escape]
    sed -i 's/compilerArgs.add("-Xlint:all/compilerArgs.add("-Xlint:all,-this-escape/' $ElasticsearchJavaBasePlugin
    
    # 对loongarch绕过gradle的java toolchain
    sed -i "/package org.elasticsearch.gradle.internal;/a \\
import org.elasticsearch.gradle.Architecture;" $ElasticsearchJavaBasePlugin
    sed -i "/compileTask.getJavaCompiler/i \\
            if (Architecture.current() != Architecture.LOONGARCH64) {" $ElasticsearchJavaBasePlugin
    sed -i "/CompileOptions compileOptions/i \\
            }" $ElasticsearchJavaBasePlugin

    sed -i "/package org.elasticsearch.gradle.internal;/a \\
import org.elasticsearch.gradle.Architecture;" $MrjarPlugin
    sed -i "/compileTask.getJavaCompiler/i \\
            if (Architecture.current() != Architecture.LOONGARCH64) {" $MrjarPlugin
    sed -i "/set(javaToolchains.compilerFor/a \\
            }" $MrjarPlugin
    
    # >= 8.14.0 适配
    if [ "$major_ver" -eq 8 ] && [ "$minor_ver" -ge 14 ]; then
	# 使用 jna 5.13.0 (5.12.1需要Glibc 2.35)
        sed -i "s/5.12.1/5.13.0/" "$src/build-tools-internal/version.properties"

        # 去掉一些"警告"报错
        sed -i 's/compilerArgs.add("-Werror");//' $ElasticsearchJavaBasePlugin
        sed -i "s/-Xdoclint:all/-Xdoclint:none/" $ElasticsearchJavaBasePlugin 

        # 模拟toolchain，处理使用了预览特性的任务:解决--release 与 javac 版本不一致的问题
	echo "org.elasticsearch.loongarch.jdk21=/usr/lib/jvm/java-21-openjdk" >> "$src/gradle.properties"
	echo "org.elasticsearch.loongarch.jdk23=/usr/lib/jvm/java-23-openjdk" >> "$src/gradle.properties"

        sed -i '/compileOptions.getRelease()/i\
            if (Architecture.current() == Architecture.LOONGARCH64) {\
                JavaPluginExtension javaExt = project.getExtensions().getByType(JavaPluginExtension.class);\
                for (SourceSet s : javaExt.getSourceSets()) {\
                    if (s.getCompileJavaTaskName().equals(compileTask.getName())) {\
                        compileOptions.setSourcepath(s.getJava().getSourceDirectories());\
                        break;\
                    }\
                }\
                compileOptions.setFork(true);\
                String jdk21 = (String) project.findProperty("org.elasticsearch.loongarch.jdk21");\
                String jdk23 = (String) project.findProperty("org.elasticsearch.loongarch.jdk23");\
                if (compileTask.getName().contains("Main21")) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk21));\
                } else {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk23));\
                }\
            }' $ElasticsearchJavaBasePlugin #根据任务名判断目标 jdk,Main21使用jdk21，Main22使用jdk23(后续若有可用jdk22可去掉此步骤)
	sed -i "s/compileOptions.getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask));/compileOptions.getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask).map(v -> { if (Architecture.current() == Architecture.LOONGARCH64) { if (v == 22) return 23; return v; } return v; }));/" $ElasticsearchJavaBasePlugin # 延迟设置 Release，将22改为23，且避免触发循环依赖(后续有可用jdk22可去掉此步骤)
        sed -i "s/compileTask.getOptions().getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask));/compileTask.getOptions().getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask).map(v -> { if (Architecture.current() == Architecture.LOONGARCH64 \&\& v == 22) return 23; return v; }));/" $ElasticsearchJavaBasePlugin # 同上
       
	sed -i '/compileOptions.getRelease().set(javaVersion);/a\
            }' $MrjarPlugin
	sed -i '/compileOptions.getRelease().set(javaVersion);/i\
            if (Architecture.current() == Architecture.LOONGARCH64) {\
                compileOptions.setSourcepath(sourceSet.getJava().getSourceDirectories());\
                compileOptions.setFork(true);\
                String jdk21 = (String) project.findProperty("org.elasticsearch.loongarch.jdk21");\
                String jdk23 = (String) project.findProperty("org.elasticsearch.loongarch.jdk23");\
                if (javaVersion == 21) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk21));\
                    compileOptions.getRelease().set(21);\
                } else if (javaVersion == 22) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk23));\
                    compileOptions.getRelease().set(23);\
                } else {\
                    compileOptions.getRelease().set(javaVersion);\
                }\
            } else {' $MrjarPlugin

    fi
fi

echo "done"
