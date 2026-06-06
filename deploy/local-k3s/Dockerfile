FROM altlinux/base:p10

RUN echo 'rpm http://simodo.ru/packages/rpm/alt/p10/repo x86_64 hasher' \
    > /etc/apt/sources.list.d/simodo.list

RUN apt-get update && \
    apt-get install -y curl simodo-loom simodo-loom-stellar && \
    apt-get clean

RUN useradd --uid 10001 --gid 0 --create-home --home-dir /home/simodo simodo

WORKDIR /app

COPY . /app

RUN chmod +x /app/deploy/local-k3s/run-simodo.sh && \
    chown -R simodo:0 /app /home/simodo && \
    chmod -R g=u /app

EXPOSE 8081 8082 8083

USER simodo

CMD ["/app/deploy/local-k3s/run-simodo.sh"]
