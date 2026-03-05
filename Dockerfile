FROM lcr.loongnix.cn/openeuler/openeuler:24.03-LTS-SP2

RUN dnf install -y --nodocs git wget jq \
    java-21-openjdk-devel java-17-openjdk-devel \
    java-11-openjdk-devel java-1.8.0-openjdk-devel && \
    dnf clean all
 
WORKDIR /workspace

RUN wget -O java-23-openjdk.tar.gz https://ftp.loongnix.cn/Java/openjdk23/loongson23.1.17-fx-jdk23_37-linux-loongarch64-glibc2.34.tar.gz && \
    wget -O java-24-openjdk.tar.gz https://ftp.loongnix.cn/Java/openjdk24/loongson24.1.26-fx-jdk24_36-linux-loongarch64-glibc2.34.tar.gz && \
    wget -O java-25-openjdk.tar.gz https://ftp.loongnix.cn/Java/openjdk25/loongson25.1.5-fx-jdk25_36-linux-loongarch64-glibc2.34.tar.gz && \
    mkdir -p /usr/lib/jvm/java-23-openjdk /usr/lib/jvm/java-24-openjdk /usr/lib/jvm/java-25-openjdk && \
    tar -xzf java-23-openjdk.tar.gz -C /usr/lib/jvm/java-23-openjdk --strip-components=1 && \
    tar -xzf java-24-openjdk.tar.gz -C /usr/lib/jvm/java-24-openjdk --strip-components=1 && \
    tar -xzf java-25-openjdk.tar.gz -C /usr/lib/jvm/java-25-openjdk --strip-components=1 && \
    rm -rf java-23-openjdk.tar.gz java-24-openjdk.tar.gz java-25-openjdk.tar.gz
    

CMD ["/bin/bash"]
