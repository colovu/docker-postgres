# Ver: 1.2 by Endial Fang (endial@126.com)
#

# 预处理 =========================================================================
FROM colovu/dbuilder as builder

# sources.list 可使用版本：default / tencent / ustc / aliyun / huawei
ARG apt_source=default

# 编译镜像时指定用于加速的本地服务器地址
ARG local_url=""

ENV APP_NAME=postgresql \
	APP_VERSION=10.14

WORKDIR /usr/local

RUN select_source ${apt_source};
#RUN install_pkg bison coreutils flex libedit-dev libxml2-dev libxslt-dev util-linux-dev zlib-dev icu-dev \
RUN install_pkg bison flex libedit-dev libxml2-dev libxslt-dev zlib1g-dev libreadline-dev uuid-dev \
	libperl-dev 

# 下载并解压软件包
RUN set -eux; \
	appName="${APP_NAME}-${APP_VERSION}.tar.bz2"; \
	sha256="381cd8f491d8f77db2f4326974542a50095b5fa7709f24d7c5b760be2518b23b"; \
	[ ! -z ${local_url} ] && localURL=${local_url}/${APP_NAME}; \
	appUrls="${localURL:-} \
		https://ftp.postgresql.org/pub/source/v${APP_VERSION} \
		"; \
	download_pkg unpack ${appName} "${appUrls}" -s "${sha256}";

# 源码编译软件包
RUN set -eux; \
# 源码编译方式安装: 编译后将原始配置文件拷贝至 ${APP_DEF_DIR} 中
	APP_SRC="/usr/local/${APP_NAME}-${APP_VERSION}"; \
	mkdir -p /usr/local/${APP_NAME}/bin /usr/local/${APP_NAME}/lib; \
	cd ${APP_SRC}; \
	\
# update "DEFAULT_PGSOCKET_DIR" to "/var/run/postgresql" (matching Debian)
# see https://anonscm.debian.org/git/pkg-postgresql/postgresql.git/tree/debian/patches/51-default-sockets-in-var.patch?id=8b539fcb3e093a521c095e70bdfa76887217b89f
	awk '$1 == "#define" && $2 == "DEFAULT_PGSOCKET_DIR" && $3 == "\"/tmp\"" { $3 = "\"/var/run/postgresql\""; print; next } { print }' src/include/pg_config_manual.h > src/include/pg_config_manual.h.new; \
	grep '/var/run/postgresql' src/include/pg_config_manual.h.new; \
	mv src/include/pg_config_manual.h.new src/include/pg_config_manual.h; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
# explicitly update autoconf config.guess and config.sub so they support more arches/libcs
	wget -O config/config.guess 'https://git.savannah.gnu.org/cgit/config.git/plain/config.guess?id=7d3d27baf8107b630586c962c057e22149653deb'; \
	wget -O config/config.sub 'https://git.savannah.gnu.org/cgit/config.git/plain/config.sub?id=7d3d27baf8107b630586c962c057e22149653deb'; \
	\
# configure options taken from:
# https://anonscm.debian.org/cgit/pkg-postgresql/postgresql.git/tree/debian/rules?h=9.5
	./configure \
		--prefix=/usr/local/${APP_NAME} \
		--build="$gnuArch" \
		--enable-integer-datetimes \
		--enable-thread-safety \
#		--enable-tap-tests \
		--disable-rpath \
		--with-uuid=e2fs \
		--with-gnu-ld \
		--with-pgport=5432 \
		--with-system-tzdata=/usr/share/zoneinfo \
		--prefix=/usr/local \
		--with-includes=/usr/local/include \
		--with-libraries=/usr/local/lib \
		--with-openssl \
		--with-libxml \
		--with-libxslt \
		--with-icu \
		--with-libuuid \
# "/usr/src/postgresql/src/backend/access/common/tupconvert.c:105: undefined reference to `libintl_gettext'"
#		--enable-nls \
# these make our image abnormally large (at least 100MB larger), which seems uncouth for an "Alpine" (ie, "small") variant :)
#		--enable-debug \
#		--with-krb5 \
#		--with-gssapi \
#		--with-ldap \
#		--with-tcl \
#		--with-perl \
#		--with-python \
#		--with-pam \
	; \
	make PG_SYSROOT=/usr/local/${APP_NAME} -j "$(nproc)" world; \
	make PREFIX=/usr/local/${APP_NAME} install-world; \
	make PREFIX=/usr/local/${APP_NAME} -C contrib install; \
	runDeps="$( \
#		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
#			| tr ',' '\n' \
#			| sort -u \
#			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
		find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u; \
	)"; \
	echo "${runDeps}" >/usr/local/${APP_NAME}/runDeps; \
	mv /usr/local/lib/* /usr/local/${APP_NAME}/lib/; \
	mv /usr/local/bin/* /usr/local/${APP_NAME}/bin/; \
	mkdir -p /usr/local/${APP_NAME}/share; \
	mv /usr/local/share/${APP_NAME} /usr/local/${APP_NAME}/share; \
	find /usr/local -name '*.a' -delete; 


#ENV LD_LIBRARY_PATH=/usr/local/${APP_NAME}/lib

# 镜像生成 ========================================================================
FROM colovu/debian:10

ARG apt_source=default
ARG local_url=""

ENV APP_NAME=postgresql \
	APP_USER=postgres \
	APP_EXEC=postgres \
	APP_VERSION=10.14

ENV	APP_HOME_DIR=/usr/local/${APP_NAME} \
	APP_DEF_DIR=/etc/${APP_NAME} \
	APP_CONF_DIR=/srv/conf/${APP_NAME} \
	APP_DATA_DIR=/srv/data/${APP_NAME} \
	APP_DATA_LOG_DIR=/srv/datalog/${APP_NAME} \
	APP_CACHE_DIR=/var/cache/${APP_NAME} \
	APP_RUN_DIR=/var/run/${APP_NAME} \
	APP_LOG_DIR=/var/log/${APP_NAME} \
	APP_CERT_DIR=/srv/cert/${APP_NAME}

ENV \
	PATH="${APP_HOME_DIR}/bin:${PATH}" \
	LD_LIBRARY_PATH=${APP_HOME_DIR}/lib

LABEL \
	"Version"="v${APP_VERSION}" \
	"Description"="Docker image for ${APP_NAME}(v${APP_VERSION})." \
	"Dockerfile"="https://github.com/colovu/docker-${APP_NAME}" \
	"Vendor"="Endial Fang (endial@126.com)"

COPY customer /

# 以包管理方式安装软件包(Optional)
RUN select_source ${apt_source}
RUN install_pkg uuid
#RUN install_pkg bash tini sudo libssl1.1

RUN create_user && prepare_env

# 从预处理过程中拷贝软件包(Optional)
#COPY --from=0 /usr/local/bin/gosu-amd64 /usr/local/bin/gosu
#COPY --from=builder /usr/local/bin /usr/local/postgresql/bin
#COPY --from=builder /usr/local/lib /usr/local/lib
COPY --from=builder ${APP_HOME_DIR} ${APP_HOME_DIR}

RUN install_pkg `cat ${APP_HOME_DIR}/runDeps`; 

# 执行预处理脚本，并验证安装的软件包
RUN set -eux; \
	override_file="/usr/local/overrides/overrides-${APP_VERSION}.sh"; \
	[ -e "${override_file}" ] && /bin/bash "${override_file}"; \
#	cp -rf ${APP_HOME_DIR}/share/${APP_NAME} /etc/; \
#	mkdir -p ${APP_DEF_DIR}/conf.d; \
	export LD_LIBRARY_PATH=${APP_HOME_DIR}/lib; \
	gosu ${APP_USER} ${APP_EXEC} --version ; \
	:;

# 默认提供的数据卷
VOLUME ["/srv/conf", "/srv/data", "/srv/datalog", "/srv/cert", "/var/log"]

# 默认使用gosu切换为新建用户启动，必须保证端口在1024之上
EXPOSE 5432

# 容器初始化命令，默认存放在：/usr/local/bin/entry.sh
ENTRYPOINT ["entry.sh"]

# 应用程序的服务命令，必须使用非守护进程方式运行。如果使用变量，则该变量必须在运行环境中存在（ENV可以获取）
CMD ["${APP_EXEC}", "-D", "${PGDATA}"]

