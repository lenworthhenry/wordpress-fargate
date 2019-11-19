FROM php:7.2-apache as builder
LABEL maintainer="Len Henry <awshenry@amazon.com>"

RUN a2enmod rewrite

ENV DEBIAN_FRONTEND noninteractive

# install the PHP extensions we need
RUN apt-get update && apt-get install -y libpng-dev libjpeg-dev unzip && rm -rf /var/lib/apt/lists/* \
	&& docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
	&& docker-php-ext-install gd
RUN docker-php-ext-install mysqli

# install the awscli
RUN apt-get update -q
RUN apt-get install -qy python-pip groff-base
RUN pip install awscli

# install fluent bit 

# Fluent Bit version
ENV FLB_MAJOR 1
ENV FLB_MINOR 3
ENV FLB_PATCH 2
ENV FLB_VERSION 1.3.2

ENV DEBIAN_FRONTEND noninteractive

ENV FLB_TARBALL http://github.com/fluent/fluent-bit/archive/v$FLB_VERSION.zip
RUN mkdir -p /fluent-bit/bin /fluent-bit/etc /fluent-bit/log /tmp/fluent-bit-master/

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      make \
      wget \
      unzip \
      libssl-dev \
      libasl-dev \
      libsasl2-dev \
      pkg-config \
      libsystemd-dev \
      zlib1g-dev \
      ca-certificates \
      flex \
      bison \
    && wget -O "/tmp/fluent-bit-${FLB_VERSION}.zip" ${FLB_TARBALL} \
    && cd /tmp && unzip "fluent-bit-$FLB_VERSION.zip" \
    && cd "fluent-bit-$FLB_VERSION"/build/ \
    && rm -rf /tmp/fluent-bit-$FLB_VERSION/build/*

WORKDIR /tmp/fluent-bit-$FLB_VERSION/build/
RUN cmake -DFLB_DEBUG=On \
          -DFLB_TRACE=Off \
          -DFLB_JEMALLOC=On \
          -DFLB_TLS=On \
          -DFLB_SHARED_LIB=Off \
          -DFLB_EXAMPLES=Off \
          -DFLB_HTTP_SERVER=On \
          -DFLB_IN_SYSTEMD=On \
          -DFLB_OUT_KAFKA=On ..

RUN make -j $(getconf _NPROCESSORS_ONLN)
RUN install bin/fluent-bit /fluent-bit/bin/

# Configuration files
COPY fluent-bit.conf \
     parsers.conf \
     parsers_java.conf \
     parsers_extra.conf \
     parsers_openstack.conf \
     parsers_cinder.conf \
     plugins.conf \
     /fluent-bit/etc/


COPY fluent-bit.conf /fluent-bit/etc/

WORKDIR /var/www/html
VOLUME /var/www/html

ENV WORDPRESS_VERSION 4.9.5
ENV WORDPRESS_UPSTREAM_VERSION 4.9.5
ENV WORDPRESS_SHA1 6992f19163e21720b5693bed71ffe1ab17a4533a
ENV PLUGIN_S3_CLOUDFRONT_VERSION 1.3.2
ENV WORDPRESS_CONFIG_EXTRA 'define('WP_DEBUG', true);'

# upstream tarballs include ./wordpress/ so this gives us /usr/src/wordpress
RUN curl -o wordpress.tar.gz -SL https://wordpress.org/wordpress-${WORDPRESS_UPSTREAM_VERSION}.tar.gz \
	&& echo "$WORDPRESS_SHA1 *wordpress.tar.gz" | sha1sum -c - \
	&& tar -xzf wordpress.tar.gz -C /usr/src/ \
	&& rm wordpress.tar.gz \
	&& chown -R www-data:www-data /usr/src/wordpress

# Download S3 and CloudFront plugin
RUN curl -o amazon-s3-and-cloudfront.zip https://downloads.wordpress.org/plugin/amazon-s3-and-cloudfront.${PLUGIN_S3_CLOUDFRONT_VERSION}.zip \
  && unzip amazon-s3-and-cloudfront.zip -d /usr/src/wordpress/wp-content/plugins \
	&& rm amazon-s3-and-cloudfront.zip

COPY docker-entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
