FROM altlinux/base:p10

RUN echo 'rpm http://simodo.ru/packages/rpm/alt/p10/repo x86_64 hasher' \
    > /etc/apt/sources.list.d/simodo.list

RUN apt-get update && \
    apt-get install -y simodo-loom simodo-loom-stellar && \
    apt-get clean

WORKDIR /workspace

CMD ["/bin/bash"]
