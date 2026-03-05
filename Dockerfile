FROM mongo:latest

RUN echo "bXktc3VwZXItc2VjcmV0LWtleS0xMjM=" > /etc/mongo-keyfile && \
    chmod 400 /etc/mongo-keyfile && \
    chown 999:999 /etc/mongo-keyfile


CMD ["mongod"]