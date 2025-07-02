ARG EXIST_VERSION=6.2.0
ARG BUILD=local

FROM ghcr.io/eeditiones/builder:latest AS builder

WORKDIR /tmp

COPY . /tmp/jinks-templates
RUN cd /tmp/jinks-templates \
    && ant

RUN cd /tmp/jinks-templates/test/app \
    && ant

FROM ghcr.io/jinntec/base:${EXIST_VERSION}

ARG USR=nonroot:nonroot
USER ${USR}

COPY --from=builder /tmp/jinks-templates/test/app/build/*.xar /exist/autodeploy/
COPY --from=builder /tmp/jinks-templates/build/*.xar /exist/autodeploy/

ARG HTTP_PORT=8080
ARG HTTPS_PORT=8443

ENV JDK_JAVA_OPTIONS="\
    -Dteipublisher.context-path=${CONTEXT_PATH} \
    -Dteipublisher.proxy-caching=${PROXY_CACHING}"

# pre-populate the database by launching it once and change default pw
RUN [ "java", "org.exist.start.Main", "client", "--no-gui",  "-l", "-u", "admin", "-P", "" ]

EXPOSE ${HTTP_PORT} ${HTTPS_PORT}