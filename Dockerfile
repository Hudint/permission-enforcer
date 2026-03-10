FROM alpine:3.23

RUN apk add --no-cache inotify-tools && \
    rm -rf /var/cache/apk/*

COPY fix-permissions.sh /fix-permissions.sh
RUN chmod +x /fix-permissions.sh

ENTRYPOINT ["/fix-permissions.sh"]