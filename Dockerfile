# muzso
#
# Based on:
# https://github.com/docker-library/php/blob/7deb69be16bf95dfd1f37183dc20e8fd21306bbc/8.4/bookworm/fpm/Dockerfile
#
# Replaced PHP with v5.6.40 from:
# https://github.com/docker-library/php/blob/fab49d4cb1c61e4f74c2dffe06961408212f054c/5.6/stretch/fpm/Dockerfile
FROM debian:bookworm-slim

# muzso: PHP 5.6.40 doesn't compile with a number of packages from Debian bookworm.
# We've to use the ones from stretch.
RUN set -eux; \
	{ \
		echo; \
		echo 'Types: deb'; \
		echo 'URIs: http://archive.debian.org/debian'; \
		echo 'Suites: stretch'; \
		echo 'Components: main'; \
		echo 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg'; \
	} >> /etc/apt/sources.list.d/debian.sources; \
	{ \
		echo; \
		echo 'Types: deb'; \
		echo 'URIs: http://archive.debian.org/debian-security'; \
		echo 'Suites: stretch/updates'; \
		echo 'Components: main'; \
		echo 'Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg'; \
	} >> /etc/apt/sources.list.d/debian.sources; \
	{ \
		echo 'Package: *curl* libssl* libicu* icu-* libmcrypt*'; \
		echo 'Pin: release n=stretch'; \
		echo 'Pin-Priority: 600'; \
	} > /etc/apt/preferences.d/stretch;

# prevent Debian's PHP packages from being installed
# https://github.com/docker-library/php/pull/542
RUN set -eux; \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# dependencies required for running "phpize"
# (see persistent deps below)
ENV PHPIZE_DEPS \
		autoconf \
		dpkg-dev \
		file \
		# muzso: with bookworm's GCC 11/12 we get 6 compilation errors on aarch64
		# platforms in /usr/src/php/Zend/zend_operators.c
		# e.g. "Error: operand 2 must be an integer register -- `mul x1,v0,v1'"
		# g++ \
		# gcc \
		g++-6 \
		gcc-6 \
		libc6-dev \
		make \
		pkg-config \
		re2c

# persistent / runtime deps
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		xz-utils \
	; \
	# muzso: set up symlinks for the alternative gcc
	ln -s /usr/bin/gcc-6 /usr/local/bin/gcc; \
	ln -s /usr/bin/g++-6 /usr/local/bin/g++;

ENV WWW_ROOT /var/www/html
ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
	[ ! -d "$WWW_ROOT" ]; \
	mkdir -p "$WWW_ROOT"; \
	chown www-data:www-data "$WWW_ROOT"; \
	chmod 1777 "$WWW_ROOT"

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)
# https://github.com/docker-library/php/issues/272
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

ENV GPG_KEYS 0BD78B5F97500D450838F95DFE857D9A90D90EC1 6E4F6AB321FDC07F2C332E3AC2BF0BC433CFC8B3

ENV PHP_VERSION 5.6.40
ENV PHP_URL="https://secure.php.net/get/php-5.6.40.tar.xz/from/this/mirror" PHP_ASC_URL="https://secure.php.net/get/php-5.6.40.tar.xz.asc/from/this/mirror"
ENV PHP_SHA256="1369a51eee3995d7fbd1c5342e5cc917760e276d561595b6052b21ace2656d1c"

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get install -y --no-install-recommends gnupg; \
	\
	mkdir -p /usr/src; \
	cd /usr/src; \
	\
	curl -fsSL -o php.tar.xz "$PHP_URL"; \
	\
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi; \
	\
	if [ -n "$PHP_ASC_URL" ]; then \
		curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
		export GNUPGHOME="$(mktemp -d)"; \
		for key in $GPG_KEYS; do \
			gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key"; \
		done; \
		gpg --batch --verify php.tar.xz.asc php.tar.xz; \
		gpgconf --kill all; \
		rm -rf "$GNUPGHOME"; \
	fi; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

# muzso
# PHP 5.6.40 depends on the `freetype-config` script, but freetype packages
# in bookworm (e.g. libfreetype-dev) don't provide it anymore
# since they depend on `pkgconfig`.
# Thus we've to provide `freetype-config` ourselves.
COPY freetype-config /usr/local/bin/
COPY docker-php-source docker-php-ext-* docker-php-entrypoint /usr/local/bin/

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	# muzso: curl (and libcurl4) was already installed, so we've to remove it first.
	apt-get -y purge curl; \
	apt-get -y --purge autoremove; \
	# muzso: dependencies for extra features
	apt-get install -y --no-install-recommends \
		curl \		
		libcurl4-openssl-dev \
		libedit-dev \
		libsqlite3-dev \
		libssl1.0-dev \
		libxml2-dev \
		zlib1g-dev \
		libbz2-dev \
		libdb-dev \
		libjpeg62-turbo-dev \
		libpng-dev \
		libxpm-dev \
		libvpx-dev \
		libfreetype-dev \
		libicu-dev \
		libmcrypt-dev \
		libexpat1-dev \
	; \
	\
	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
# https://github.com/php/php-src/blob/d6299206dd828382753453befd1b915491b741c6/configure.ac#L1496-L1511
		PHP_BUILD_PROVIDER='https://github.com/docker-library/php' \
		PHP_UNAME='Linux - Docker' \
	; \
	docker-php-source extract; \
	cd /usr/src/php; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
# https://bugs.php.net/bug.php?id=74125
	if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
	fi; \
	./configure \
		--build="$gnuArch" \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		\
# make sure invalid --configure-flags are fatal errors instead of just warnings
		--enable-option-checking=fatal \
		\
# https://github.com/docker-library/php/issues/439
		--with-mhash \
		\
# --enable-ftp is included here because ftp_ssl_connect() needs ftp to be compiled statically (see https://github.com/docker-library/php/issues/236)
		--enable-ftp \
# --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
		--enable-mbstring \
# --enable-mysqlnd is included here because it's harder to compile after the fact than extensions are (since it's a plugin for several extensions, not an extension in itself)
		--enable-mysqlnd \
# always build against system sqlite3 (https://github.com/php/php-src/commit/6083a387a81dbbd66d6316a3a12a63f06d5f7109)
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		\
		--with-curl \
		--with-libedit \
		--with-openssl \
		--with-zlib \
		# muzso: extra features
		--with-bz2 \
		--enable-calendar \
		--enable-bcmath \
		--enable-flatfile \
		--enable-inifile \
		--with-db4 \
		--enable-exif \
		--with-gd \
		--with-png-dir \
		--with-jpeg-dir \
		--with-xpm-dir \
		--with-vpx-dir \
		--with-freetype-dir \
		--with-gettext \
		--enable-intl \
		--with-mcrypt \
		--with-pdo-mysql \
		--with-mysql \
		--with-mysqli \
		--enable-shmop \
		--enable-soap \
		--enable-sockets \
		--enable-sysvsem \
		--enable-sysvshm \
		--enable-sysvmsg \
		--enable-wddx \
		--enable-opcache \
		\
# bundled pcre does not support JIT on s390x
# https://manpages.debian.org/stretch/libpcre3-dev/pcrejit.3.en.html#AVAILABILITY_OF_JIT_SUPPORT
		$(test "$gnuArch" = 's390x-linux-gnu' && echo '--without-pcre-jit') \
		--with-libdir="lib/$debMultiarch" \
		\
		--disable-cgi \
		\
		--enable-fpm \
		--with-fpm-user=www-data \
		--with-fpm-group=www-data \
	; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
# update pecl channel definitions https://github.com/docker-library/php/issues/443
	pecl update-channels; \
# muzso: additional extensions
	apt-get install -y --no-install-recommends \
			libmagickwand-dev \
		&& pecl install imagick \
		&& docker-php-ext-enable imagick.so \
	; \
	docker-php-ext-enable opcache.so; \
	find \
		/usr/local \
		-type f \
		-perm '/0111' \
		-exec sh -euxc ' \
			strip --strip-all "$@" || : \
		' -- '{}' + \
	; \
	make clean; \
	\
# https://github.com/docker-library/php/issues/692 (copy default example "php.ini" files somewhere easily discoverable)
	cp -v php.ini-* "$PHP_INI_DIR/"; \
	ln -s php.ini-production "$PHP_INI_DIR/php.ini"; \
	\
	cd /; \
	docker-php-source delete; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
# muzso: the original cleanup logic was buggy because shared object files are
#        not necessarily marked as executable and thus were missed and their
#        library dependencies (packages) removed
	find /usr/local -type f -print0 \
		| xargs -r -0 file \
		| egrep -ia '^[^:]+:.*(executable|shared object)' \
		| cut -d: -f1 \
		| xargs -r -d '\n' ldd \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	# this was the last APT operation, we can get rid of the package lists to make the image smaller
	rm -rf /var/lib/apt/lists/*; \
	\
	rm -rf /tmp/pear ~/.pearrc; \
	\
# smoke test
	php --version

ENTRYPOINT ["docker-php-entrypoint"]
WORKDIR "$WWW_ROOT"

RUN set -eux; \
	cd /usr/local/etc; \
	if [ -d php-fpm.d ]; then \
		# for some reason, upstream's php-fpm.conf.default has "include=NONE/etc/php-fpm.d/*.conf"
		sed 's!=NONE/!=!g' php-fpm.conf.default | tee php-fpm.conf > /dev/null; \
		cp php-fpm.d/www.conf.default php-fpm.d/www.conf; \
	else \
		# PHP 5.x doesn't use "include=" by default, so we'll create our own simple config that mimics PHP 7+ for consistency
		mkdir php-fpm.d; \
		cp php-fpm.conf.default php-fpm.d/www.conf; \
		{ \
			echo '[global]'; \
			echo 'include=etc/php-fpm.d/*.conf'; \
		} | tee php-fpm.conf; \
	fi; \
	{ \
		echo '[global]'; \
		echo 'error_log = /proc/self/fd/2'; \
		echo; \
		echo '[www]'; \
		echo '; php-fpm closes STDOUT on startup, so sending logs to /proc/self/fd/1 does not work.'; \
		echo '; https://bugs.php.net/bug.php?id=73886'; \
		echo 'access.log = /proc/self/fd/2'; \
		echo; \
		echo 'clear_env = no'; \
		echo; \
		echo '; Ensure worker stdout and stderr are sent to the main error log.'; \
		echo 'catch_workers_output = yes'; \
	} | tee php-fpm.d/docker.conf; \
	{ \
		echo '[global]'; \
		echo 'daemonize = no'; \
		echo; \
		echo '[www]'; \
		echo 'listen = 9000'; \
	} | tee php-fpm.d/zz-docker.conf; \
	chmod -R a+r /usr/local; \
	find /usr/local -type d -print0 | xargs -r -0 chmod a+x; \
	find /usr/local -type f -perm /a+x -print0 | xargs -r -0 chmod a+x;

EXPOSE 9000
CMD ["php-fpm"]
