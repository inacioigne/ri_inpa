ARG DSPACE_VERSION=dspace-8.1
ARG JDK_VERSION=17

ARG DOCKER_REGISTRY=docker.io

# Step 1 - Run Maven Build
FROM ${DOCKER_REGISTRY}/dspace/dspace-dependencies:${DSPACE_VERSION} AS build
ARG TARGET_DIR=dspace-installer

WORKDIR /app

RUN mkdir /install \
    && chown -Rv dspace: /install \
    && chown -Rv dspace: /app

USER dspace

ADD --chown=dspace /api/ /app/

# RUN mvn -U package && \
#     mv /app/dspace/target/dspace-installer/* /install && \
#     mvn clean
RUN mvn --no-transfer-progress package && \
    mv /app/dspace/target/${TARGET_DIR}/* /install && \
    mvn clean

RUN rm -rf /install/webapps/server/

# Step 2 - Run Ant Deploy
FROM docker.io/eclipse-temurin:${JDK_VERSION} AS ant_build

COPY --from=build /install /dspace-src
WORKDIR /dspace-src

ENV ANT_VERSION 1.10.13
ENV ANT_HOME /tmp/ant-$ANT_VERSION
ENV PATH $ANT_HOME/bin:$PATH

# RUN apt-get update \
#     && apt-get install -y --no-install-recommends wget \
#     && apt-get purge -y --auto-remove \
#     && rm -rf /var/lib/apt/lists/*

RUN mkdir $ANT_HOME && \
    curl --silent --show-error --location --fail --retry 5 --output /tmp/apache-ant.tar.gz \
      https://archive.apache.org/dist/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz && \
    tar -zx --strip-components=1 -f /tmp/apache-ant.tar.gz -C $ANT_HOME && \
    rm /tmp/apache-ant.tar.gz

# RUN mkdir $ANT_HOME && \
#     wget -qO- "https://archive.apache.org/dist/ant/binaries/apache-ant-$ANT_VERSION-bin.tar.gz" | tar -zx --strip-components=1 -C $ANT_HOME

RUN ant init_installation update_configs update_code update_webapps

# Step 3 - Start up DSpace via Runnable JAR
# FROM eclipse-temurin:${JDK_VERSION}
FROM docker.io/eclipse-temurin:${JDK_VERSION}

ENV DSPACE_INSTALL=/dspace

COPY --from=ant_build /dspace $DSPACE_INSTALL
ADD /GeoLite2-City/GeoLite2-City.mmdb $DSPACE_INSTALL
WORKDIR $DSPACE_INSTALL
RUN apt-get update \
    && apt-get install -y --no-install-recommends host \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/lib/apt/lists/*
EXPOSE 8080 8000
ENV JAVA_OPTS=-Xmx2000m
ENV JAVA_TOOL_OPTIONS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:8000

ENTRYPOINT ["java", "-jar", "webapps/server-boot.jar", "--dspace.dir=$DSPACE_INSTALL"]