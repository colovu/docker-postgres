# Ver: 1.8 by Endial Fang (endial@126.com)
#

# 可变参数 ========================================================================

# 设置当前应用名称及版本
ARG app_name=postgresql
ARG app_version=10.14

# 设置默认仓库地址，默认为 阿里云 仓库
ARG registry_url="registry.cn-shenzhen.aliyuncs.com"

# 设置 apt-get 源：default / tencent / ustc / aliyun / huawei
ARG apt_source=aliyun

# 编译镜像时指定用于加速的本地服务器地址
ARG local_url=""


# 0. 预处理 ======================================================================
FROM ${registry_url}/colovu/dbuilder as builder

# 声明需要使用的全局可变参数
ARG app_name
ARG app_version
ARG registry_url
ARG apt_source
ARG local_url

# 选择软件包源(Optional)，以加速后续软件包安装
RUN select_source ${apt_source};

# 安装依赖的软件包及库(Optional)
RUN install_pkg bison flex libedit-dev libxml2-dev libxslt-dev zlib1g-dev libreadline-dev uuid-dev \
	libperl-dev libicu-dev libxslt1-dev libssl-dev libldap2-dev libkrb5-dev libpam0g-dev libselinux1-dev;

# 设置工作目录
WORKDIR /tmp

# 下载并解压软件包
RUN set -eux; \
	appName="${app_name}-${app_version}.tar.bz2"; \
	sha256="381cd8f491d8f77db2f4326974542a50095b5fa7709f24d7c5b760be2518b23b"; \
	[ ! -z ${local_url} ] && localURL=${local_url}/${app_name}; \
	appUrls="${localURL:-} \
		https://ftp.postgresql.org/pub/source/v${app_version} \
		"; \
	download_pkg unpack ${appName} "${appUrls}" -s "${sha256}";

# 源码编译
RUN set -eux; \
	APP_SRC="/tmp/${app_name}-${app_version}"; \
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
		--prefix=/usr/local/${app_name} \
		--build="$gnuArch" \
		--enable-integer-datetimes \
		--enable-thread-safety \
		--disable-rpath \
		--with-uuid=e2fs \
		--with-gnu-ld \
		--with-pgport=5432 \
		--with-system-tzdata=/usr/share/zoneinfo \
		--with-includes=/usr/local/include \
		--with-libraries=/usr/local/lib \
		--with-openssl \
		--with-libxml \
		--with-libxslt \
		--with-icu \
		--with-krb5 \
		--with-ldap \
#		--enable-tap-tests \
# "/usr/src/postgresql/src/backend/access/common/tupconvert.c:105: undefined reference to `libintl_gettext'"
#		--enable-nls \
# these make our image abnormally large (at least 100MB larger), which seems uncouth for an "Alpine" (ie, "small") variant :)
#		--enable-debug \
#		--with-gssapi \
#		--with-tcl \
#		--with-perl \
#		--with-python \
#		--with-pam \
	; \
	make -j "$(nproc)" world; \
	make install-world; \
	make -C contrib install;

# 删除编译生成的多余文件
RUN set -eux; \
	find /usr/local -name '*.a' -delete; \
	rm -rf /usr/local/${app_name}/include;

# 检测并生成依赖文件记录
RUN set -eux; \
	find /usr/local/${app_name} -type f -executable -exec ldd '{}' ';' | \
		awk '/=>/ { print $(NF-1) }' | \
		sort -u | \
		xargs -r dpkg-query --search 2>/dev/null | \
		cut -d: -f1 | \
		sort -u >/usr/local/${app_name}/runDeps;


# 1. 生成镜像 =====================================================================
FROM ${registry_url}/colovu/debian:buster

# 声明需要使用的全局可变参数
ARG app_name
ARG app_version
ARG registry_url
ARG apt_source
ARG local_url

# 镜像所包含应用的基础信息，定义环境变量，供后续脚本使用
ENV APP_NAME=${app_name} \
	APP_EXEC=postgres \
	APP_VERSION=${app_version}

ENV	APP_HOME_DIR=/usr/local/${APP_NAME} \
	APP_DEF_DIR=/etc/${APP_NAME}

ENV PATH="${APP_HOME_DIR}/sbin:${APP_HOME_DIR}/bin:${PATH}" \
	LD_LIBRARY_PATH="${APP_HOME_DIR}/lib"

LABEL \
	"Version"="v${app_version}" \
	"Description"="Docker image for ${app_name}(v${app_version})." \
	"Dockerfile"="https://github.com/colovu/docker-${app_name}" \
	"Vendor"="Endial Fang (endial@126.com)"

# 从预处理过程中拷贝软件包(Optional)，可以使用阶段编号或阶段命名定义来源
COPY --from=0 /usr/local/${APP_NAME} /usr/local/${APP_NAME}

# 拷贝应用使用的客制化脚本，并创建对应的用户及数据存储目录
COPY customer /
RUN set -eux; \
	prepare_env;

# 选择软件包源(Optional)，以加速后续软件包安装
RUN select_source ${apt_source}

# 安装依赖的软件包及库(Optional)
RUN install_pkg `cat /usr/local/${APP_NAME}/runDeps`; 

# 执行预处理脚本，并验证安装的软件包
RUN set -eux; \
	override_file="/usr/local/overrides/overrides-${APP_VERSION}.sh"; \
	[ -e "${override_file}" ] && /bin/bash "${override_file}"; \
	${APP_EXEC} --version ;

# 默认提供的数据卷
VOLUME ["/srv/conf", "/srv/data", "/srv/datalog", "/srv/cert", "/var/log"]

# 默认non-root用户启动，必须保证端口在1024之上
EXPOSE 5432

# 关闭基础镜像的健康检查
#HEALTHCHECK NONE

# 应用健康状态检查
#HEALTHCHECK --interval=30s --timeout=30s --retries=3 \
#	CMD curl -fs http://localhost:8080/ || exit 1
#HEALTHCHECK --interval=10s --timeout=10s --retries=3 \
#	CMD netstat -ltun | grep 8080
HEALTHCHECK CMD PGPASSWORD="${PG_POSTGRES_PASSWORD:-${PG_PASSWORD}}" psql -h 127.0.0.1 -d postgres -U postgres -At -c "select version();" || exit 1

# 使用 non-root 用户运行后续的命令
USER 1001

# 设置工作目录
WORKDIR /srv/data

# 容器初始化命令
ENTRYPOINT ["/usr/local/bin/entry.sh"]

# 应用程序的启动命令，必须使用非守护进程方式运行
CMD ["/usr/local/bin/run.sh"]

