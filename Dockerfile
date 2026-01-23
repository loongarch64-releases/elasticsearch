FROM lcr.loongnix.cn/openeuler/openeuler:24.03-LTS-SP2

RUN dnf install -y --nodocs git wget jq \
    java-17-openjdk-devel java-1.8.0-openjdk-devel && \
    dnf clean all

RUN alternatives --install /usr/bin/java java /usr/lib/jvm/java-17-openjdk-17.*/bin/java 20000 && \
    alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-17-openjdk-17.*/bin/javac 20000 && \
    alternatives --set java /usr/lib/jvm/java-17-openjdk-17.*/bin/java && \
    alternatives --set javac /usr/lib/jvm/java-17-openjdk-17.*/bin/javac

WORKDIR /workspace


CMD ["bin/bash"]
