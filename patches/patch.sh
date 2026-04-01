#!/bin/bash

src=$1
version=$2
patches=$3
major_ver=$(echo "$version" | cut -d. -f1)
minor_ver=$(echo "$version" | cut -d. -f2)
patch_ver=$(echo "$version" | cut -d. -f3)
ver_num=$(( 10#$major_ver * 1000000 + 10#$minor_ver * 1000 + 10#$patch_ver ))

echo "patching ..."

# 配置 loongson MAVEN 环境
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

# 修改 server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java
sed -i 's#if (isSystemCallFilterInstalled() == false)#if(isSystemCallFilterInstalled() == false \&\& !"loongarch64".equals(System.getProperty("os.arch")))#' "$src/server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java"

# 修改 build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/Jdk.java
sed -i 's#private static final List<String> ALLOWED_ARCHITECTURES = List.of("aarch64", "x64");#private static final List<String> ALLOWED_ARCHITECTURES = List.of("aarch64", "x64", "loongarch64");#' "$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/Jdk.java"

# 修改 server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java
sed -i 's#if(isSystemCallFilterInstalled() == false)#if(isSystemCallFilterInstalled() == false \&\& !"loongarch64".equals(System.getProperty("os.arch")))#' "$src/server/src/main/java/org/elasticsearch/bootstrap/BootstrapChecks.java"

# 添加 loongarch 项目
sed -i "/'distribution:archives:linux-aarch64-tar',/a\\
  'distribution:archives:linux-loongarch64-tar'," "$src/settings.gradle"
cp -r "$src/distribution/archives/linux-aarch64-tar" "$src/distribution/archives/linux-loongarch64-tar"

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

# 去除 ml 相关模块
$patches/remove_ml.sh $src $ver_num

# 删除 dockerx 项目
sed -i "/'distribution:docker/d" "$src/settings.gradle"
rm -rf "$src/distribution/docker/"

# gradle toolchain 适配
if [ "$ver_num" -ge 8013000 ]; then
    ElasticsearchJavaBasePlugin="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/ElasticsearchJavaBasePlugin.java"
    MrjarPlugin="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/MrjarPlugin.java"

    # 禁用jdk 21引入的警告[this-escape]
    sed -i 's/compilerArgs.add("-Xlint:all/compilerArgs.add("-Xlint:all,-this-escape/' $ElasticsearchJavaBasePlugin
    
    # 对loongarch跳过toolchain的显式设置
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
    
    if [ "$ver_num" -ge 8014000 ]; then
	# 使用 jna 5.13.0 (5.12.1是Glibc 2.35编的)
	sed -i "s/5.12.1/5.13.0/" "$src/build-tools-internal/version.properties"

        # 去掉一些"警告"错误
        sed -i 's/compilerArgs.add("-Werror");//' $ElasticsearchJavaBasePlugin
        sed -i "s/-Xdoclint:all/-Xdoclint:none/" $ElasticsearchJavaBasePlugin 

	if [ "$ver_num" -lt 8018000 ] || [ "$ver_num" -ge 9000000 ]; then
	    # 模拟toolchain来处理使用预览特性的任务:解决--release 与 javac 版本不一致的问题(可用jdk限制，仅能处理部分版本)
            echo "org.elasticsearch.loongarch.jdk21=/usr/lib/jvm/java-21-openjdk" >> "$src/gradle.properties"
            echo "org.elasticsearch.loongarch.jdk23=/usr/lib/jvm/java-23-openjdk" >> "$src/gradle.properties"
            echo "org.elasticsearch.loongarch.jdk24=/usr/lib/jvm/java-24-openjdk" >> "$src/gradle.properties"
            echo "org.elasticsearch.loongarch.jdk25=/usr/lib/jvm/java-25-openjdk" >> "$src/gradle.properties"

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
                String jdk24 = (String) project.findProperty("org.elasticsearch.loongarch.jdk24");\
                String jdk25 = (String) project.findProperty("org.elasticsearch.loongarch.jdk25");\
		String taskName = compileTask.getName();\
                if (taskName.contains("Main22") || taskName.contains("Main23")) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk23));\
	        } else if (taskName.contains("Main25") || taskName.contains("Main26")) {\
		    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk25));\
	        } else if (taskName.contains("Main24")) {\
		    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk24));\
                } else {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk21));\
                }\
	}' $ElasticsearchJavaBasePlugin #根据任务名判断目标 jdk,Main21使用jdk21，Main22使用jdk23(后续有适配jdk可修改此步骤)
            sed -i 's/compileOptions.getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask));/compileOptions.getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask).map(v -> { \
        if (Architecture.current() == Architecture.LOONGARCH64) { \
	    if (v == 22) return 23; \
            else if (v == 26) return 25; \
            return v; \
        } \
        return v; \
    }));/' $ElasticsearchJavaBasePlugin # 延迟设置 Release，与编译器对齐，且避免触发循环依赖(后续有适配jdk可修改此步骤)
            sed -i 's/compileTask.getOptions().getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask));/compileTask.getOptions().getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask).map(v -> { \
	if (Architecture.current() == Architecture.LOONGARCH64) { \
	    if (v == 22) return 23; \
	    else if (v == 26) return 25; \
	    return v; \
	} \
        return v; \
    }));/' $ElasticsearchJavaBasePlugin # 同上

	    sed -i '/compileOptions.getRelease().set(javaVersion);/a\
            }' $MrjarPlugin
            sed -i '/compileOptions.getRelease().set(javaVersion);/i\
            if (Architecture.current() == Architecture.LOONGARCH64) {\
                compileOptions.setSourcepath(sourceSet.getJava().getSourceDirectories());\
                compileOptions.setFork(true);\
                String jdk21 = (String) project.findProperty("org.elasticsearch.loongarch.jdk21");\
                String jdk23 = (String) project.findProperty("org.elasticsearch.loongarch.jdk23");\
		String jdk24 = (String) project.findProperty("org.elasticsearch.loongarch.jdk24");\
                String jdk25 = (String) project.findProperty("org.elasticsearch.loongarch.jdk25");\
                if (javaVersion == 22) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk23));\
                    compileOptions.getRelease().set(23);\
	        } else if (javaVersion == 26) {\
	            compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk25));\
                    compileOptions.getRelease().set(25);\
                } else {\
                    compileOptions.getRelease().set(javaVersion);\
                }\
            } else {' $MrjarPlugin

	    if [ "$ver_num" -ge 8018008 ]; then
                sed -i '/package org.elasticsearch.gradle.internal;/a\
import org.gradle.api.tasks.SourceSet;' $ElasticsearchJavaBasePlugin
	    fi
    	fi

        # 避开 gradle-8.13 引入的守护进程 JVM 自动发现特性
        if [ "$ver_num" -eq 8016006 ] || [ "$ver_num" -ge 8017004 ]; then
            rm -f "$src/gradle/gradle-daemon-jvm.properties"
        fi

	# 继续使用java安全管理器，而不是entitlements system
        if [ "$ver_num" -ge 9000000 ] && [ "$ver_num" -lt 9001000 ]; then
            sed -i "s/final boolean useEntitlements = true/final boolean useEntitlements = false/" "$src/server/src/main/java/org/elasticsearch/bootstrap/Elasticsearch.java"
	fi
      
	# 满足jdk-api-extractor对jdk 25的需求
	if [ "$ver_num" -ge 9002000 ]; then
	    jdkApiExtractor="$src/libs/entitlement/tools/jdk-api-extractor/build.gradle"
            echo "org.elasticsearch.loongarch.jdk25=/usr/lib/jvm/java-25-openjdk" >> "$src/gradle.properties"
            sed -i '/def addIncubatorModules/i\
def loongarchJdk25 = project.findProperty("org.elasticsearch.loongarch.jdk25")' $jdkApiExtractor 
	    sed -i 's|"${buildParams.runtimeJavaHome.get()}/jmods"|jmodsPath|' $jdkApiExtractor
	    sed -i '/def addIncubatorModules = {/a\
  def jmodsPath = (org.elasticsearch.gradle.Architecture.current() == org.elasticsearch.gradle.Architecture.LOONGARCH64)\
                  ? "${loongarchJdk25}/jmods"\
                  : "${buildParams.runtimeJavaHome.get()}/jmods"' $jdkApiExtractor
	    sed -i '/executable = /a\
}' $jdkApiExtractor
            sed -i '/executable = /i\
  if (org.elasticsearch.gradle.Architecture.current() == org.elasticsearch.gradle.Architecture.LOONGARCH64) {\
      executable = "${loongarchJdk25}/bin/java"\
  } else {' $jdkApiExtractor
	fi
    fi
fi

echo "done"
