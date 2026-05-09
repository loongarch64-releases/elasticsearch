#!/bin/bash

src=$1
ver_num=$2

# gradle java toolchain 适配
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
            echo "org.elasticsearch.loongarch.jdk26=/usr/lib/jvm/java-26-openjdk" >> "$src/gradle.properties"

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
                String jdk26 = (String) project.findProperty("org.elasticsearch.loongarch.jdk26");\
                String taskName = compileTask.getName();\
                if (taskName.contains("Main22") || taskName.contains("Main23")) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk23));\
                } else if (taskName.contains("Main26")) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk26));\
                } else if (taskName.contains("Main25")) {\
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
            return v; \
        } \
        return v; \
    }));/' $ElasticsearchJavaBasePlugin # 延迟设置 Release，与编译器对齐，且避免触发循环依赖(后续有适配jdk可修改此步骤)
            sed -i 's/compileTask.getOptions().getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask));/compileTask.getOptions().getRelease().set(releaseVersionProviderFromCompileTask(project, compileTask).map(v -> { \
        if (Architecture.current() == Architecture.LOONGARCH64) { \
            if (v == 22) return 23; \
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
                String jdk26 = (String) project.findProperty("org.elasticsearch.loongarch.jdk26");\
                if (javaVersion == 22) {\
                    compileOptions.getForkOptions().setJavaHome(new java.io.File(jdk23));\
                    compileOptions.getRelease().set(23);\
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

