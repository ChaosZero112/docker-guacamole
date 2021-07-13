# https://fleet.linuxserver.io/image?name=lsiobase/alpine
FROM lsiobase/alpine:3.14

ENV ARCH=amd64 \
  GUAC_VER=1.3.0 \
  GUACAMOLE_HOME=/app/guacamole \
  PG_MAJOR=13 \
  PG_JDBC=42.2.23 \
  LIBJPEG=2.1.0 \
  LIBTELNET=0.23 \
  PGDATA=/config/postgres \
  POSTGRES_USER=guacamole \
  POSTGRES_DB=guacamole_db \
  TOMCAT=tomcat9 \
  CATALINA_HOME=/var/lib/${TOMCAT}

ARG PACKAGES="        \
  alpine-sdk          \
  build-base          \
  automake            \
  autoconf            \
  nasm                \
  clang               \
  wget                \
  unzip               \
  gnupg               \
  postgresql          \
  cairo               \
  cmake               \
  libjpeg-turbo-dev   \
  libpng              \
  libtool             \
  ffmpeg-dev          \
  freerdp-dev         \
  pango-dev           \
  libssh2-dev         \
  libvncserver-dev    \
  libwebsockets-dev   \
  pulseaudio-dev      \
  libvorbis-dev       \
  libwebp-dev         \
  ghostscript         \
  terminus-font       \
  openjdk11           \
  "

WORKDIR ${GUACAMOLE_HOME}

# Install dependencies
RUN apk update && apk add --no-cache -lu ${PACKAGES} \
    && apk add --no-cache -luX http://dl-cdn.alpinelinux.org/alpine/edge/testing ossp-uuid-dev ${TOMCAT} \
    && curl -sSLO https://github.com/seanmiddleditch/libtelnet/releases/download/${LIBTELNET}/libtelnet-${LIBTELNET}.tar.gz \
    && tar xvf libtelnet-${LIBTELNET}.tar.gz \
    && cd libtelnet-${LIBTELNET} \
    && ./configure \
    && make \
    && make install \
    && cd .. \
    && rm -r libtelnet-${LIBTELNET} libtelnet-${LIBTELNET}.tar.gz \
    && mkdir -p ${GUACAMOLE_HOME} \
    ${GUACAMOLE_HOME}/lib \
    ${GUACAMOLE_HOME}/extensions \
    && ln -s /usr/share/tomcat9/bin /var/lib/tomcat9/bin/

# Link FreeRDP to where guac expects it to be
RUN [ "$ARCH" = "amd64" ] && mkdir -p /usr/lib/x86_64-linux-gnu && ln -s /usr/lib/libfreerdp2.so /usr/lib/x86_64-linux-gnu/freerdp || exit 0

# Install guacamole-server from source
#RUN curl -SLO "https://github.com/apache/guacamole-server/archive/refs/heads/master.zip" \
#  && unzip master.zip \
#  && cd guacamole-server-master \
#  && libtoolize --force \
#  && autoheader \
#  && aclocal \
#  && automake --force-missing --add-missing \
#  && autoupdate \
#  && autoconf \
#  && ./configure --enable-allow-freerdp-snapshots \
#  && make -j$(getconf _NPROCESSORS_ONLN) \
#  && make install \
#  && cd .. \
#  && rm -rf master.zip guacamole-server-master \
#  && ldconfig

# Install guacamole-server
RUN curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/source/guacamole-server-${GUAC_VER}.tar.gz" \
  && tar -xzf guacamole-server-${GUAC_VER}.tar.gz \
  && cd guacamole-server-${GUAC_VER} \
  && CFLAGS=-Wno-error=deprecated-declarations ./configure --enable-allow-freerdp-snapshots \
  && make -j$(getconf _NPROCESSORS_ONLN) \
  && make install \
  && cd .. \
  && rm -rf guacamole-server-${GUAC_VER}.tar.gz guacamole-server-${GUAC_VER}

# Install guacamole-client and postgres auth adapter
RUN set -x \
  && rm -rf ${CATALINA_HOME}/webapps/ROOT \
  && curl -SLo ${CATALINA_HOME}/webapps/ROOT.war "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${GUAC_VER}.war" \
  && curl -SLo ${GUACAMOLE_HOME}/lib/postgresql-${PG_JDBC}.jar "https://jdbc.postgresql.org/download/postgresql-${PG_JDBC}.jar" \
  && curl -SLO "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-auth-jdbc-${GUAC_VER}.tar.gz" \
  && tar -xzf guacamole-auth-jdbc-${GUAC_VER}.tar.gz \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/guacamole-auth-jdbc-postgresql-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions/ \
  && cp -R guacamole-auth-jdbc-${GUAC_VER}/postgresql/schema ${GUACAMOLE_HOME}/ \
  && rm -rf guacamole-auth-jdbc-${GUAC_VER} guacamole-auth-jdbc-${GUAC_VER}.tar.gz

# Add optional extensions
RUN set -xe \
  && mkdir ${GUACAMOLE_HOME}/extensions-available \
  && for i in auth-ldap auth-duo auth-cas auth-openid auth-quickconnect auth-totp auth-saml; do \
    echo "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz" \
    && curl -SLO --connect-timeout 5 --retry 5 --retry-delay 0 --retry-max-time 60 \
    "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-${i}-${GUAC_VER}.tar.gz" \
    && tar -xzf guacamole-${i}-${GUAC_VER}.tar.gz \
    && cp guacamole-${i}-${GUAC_VER}/guacamole-${i}-${GUAC_VER}.jar ${GUACAMOLE_HOME}/extensions-available/ \
    && rm -rf guacamole-${i}-${GUAC_VER} guacamole-${i}-${GUAC_VER}.tar.gz \
    && sleep 8 \
  ;done \
  && echo "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-auth-header-1.2.0.tar.gz" \
    && curl -SLO --connect-timeout 5 --retry 5 --retry-delay 0 --retry-max-time 60 \
    "http://apache.org/dyn/closer.cgi?action=download&filename=guacamole/${GUAC_VER}/binary/guacamole-auth-header-1.2.0.tar.gz" \
    && tar -xzf guacamole-auth-header-1.2.0.tar.gz \
    && cp guacamole-auth-header-1.2.0/guacamole-auth-header-1.2.0.jar ${GUACAMOLE_HOME}/extensions-available/guacamole-auth-header-1.3.0.jar \
    && rm -rf guacamole-auth-header-1.2.0 guacamole-auth-header-1.2.0.tar.gz

ENV PATH=/usr/share/${TOMCAT}/bin:/usr/lib/postgresql/${PG_MAJOR}/bin:$PATH
ENV GUACAMOLE_HOME=/config/guacamole

WORKDIR /config

COPY root /

EXPOSE 8080

ENTRYPOINT [ "/init" ]
