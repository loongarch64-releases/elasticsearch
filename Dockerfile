FROM lcr.loongnix.cn/openeuler/openeuler:24.03-LTS-SP2

RUN dnf install -y --nodocs git wget jq \
    java-21-openjdk-devel java-17-openjdk-devel \
    java-11-openjdk-devel java-1.8.0-openjdk-devel && \
    dnf clean all

ENV PATH=/usr/lib/jvm/java-17-openjdk/bin:$PATH

WORKDIR /workspace

CMD ["/bin/bash"]
