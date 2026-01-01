FROM fedora:rawhide
RUN dnf install -y gcc-c++ llvm-devel clang tar boost-devel && dnf clean all
RUN curl -sSL https://github.com/koka-lang/koka/releases/download/v3.2.2/koka-v3.2.2-linux-x64.tar.gz | tar xz -C /usr/local
