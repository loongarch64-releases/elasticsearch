#!/bin/bash
set -euo pipefail

src=$1
ver_num=$2

# gradle java toolchain 适配
if [ "$ver_num" -ge 8013000 ]; then
    MrjarPlugin="$src/build-tools-internal/src/main/java/org/elasticsearch/gradle/internal/MrjarPlugin.java"

    #  禁止自动下载
    cat << 'EOF' >> "$src/gradle.properties"
org.gradle.java.installations.auto-download=false
EOF

    # 去掉对 temuirin jdk 的强制要求
    sed -i '/toolchainVendor=ADOPTIUM/d' "$src/gradle/gradle-daemon-jvm.properties"

    # 系统设置对应变量，指向本地 jdk
    sed -i 's/RUNTIME_JAVA_HOME/&,JDK17_HOME,JDK21_HOME,JDK23_HOME,JDK25_HOME,JDK26_HOME,JDK27_HOME/' "$src/gradle.properties"
    # 由于目前没有 jdk 22，所以让请求版本是 22 时返回 23
    sed -i 's/set(JavaLanguageVersion.of(javaVersion))/set(JavaLanguageVersion.of(toolchainVersionFor(javaVersion)))/' "$MrjarPlugin"
    sed -i '/private SourceSet addSourceSet/i\
    private static int toolchainVersionFor(int javaVersion) {\
        return javaVersion == 22 ? 23 : javaVersion;\
    }' "$MrjarPlugin"
    #  Java 22 源码关闭 preview
    sed -i '/compileOptions.getCompilerArgs().add("--enable-preview")/c\
            if (javaVersion != 22) {\
                compileOptions.getCompilerArgs().add("--enable-preview");\
            }' "$MrjarPlugin"
    sed -i '/options.addBooleanOption("-enable-preview", true)/c\
            if (javaVersion != 22) {\
                options.addBooleanOption("-enable-preview", true);\
            }' "$MrjarPlugin"
    sed -i 's/options.addStringOption("-release", String.valueOf(compileReleaseVersionFor(javaVersion)))/options.addStringOption("-release", String.valueOf(javaVersion))/' "$MrjarPlugin"

fi

