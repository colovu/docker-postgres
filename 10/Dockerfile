FROM colovu/ubuntu:18.04

ARG app_ver=10
ARG LOCAL_SERVER=

ENV APP_NAME=postgresql \
	APP_EXEC=postgres \
	APP_USER=postgres \
	APP_GROUP=postgres \
	APP_VERSION=${app_ver}

ENV	APP_BASE_DIR=/usr/lib/${APP_NAME}/${APP_VERSION} \
	APP_DEF_DIR=/etc/${APP_NAME} \
	APP_CONF_DIR=/srv/conf/${APP_NAME} \
	APP_DATA_DIR=/srv/data/${APP_NAME} \
	APP_DATA_LOG_DIR=/srv/datalog/${APP_NAME} \
	APP_CACHE_DIR=/var/cache/${APP_NAME} \
	APP_RUN_DIR=/var/run/${APP_NAME} \
	APP_LOG_DIR=/var/log/${APP_NAME} \
	APP_CERT_DIR=/srv/cert/${APP_NAME} \
	APP_WWW_DIR=/srv/www

# PGDATA 用于指定默认配置文件路径
ENV PG_MAJOR=${APP_VERSION} \
	PGDATA=${APP_DATA_DIR}/${APP_VERSION} \
	PATH="${APP_BASE_DIR}/bin:${PATH}"

LABEL \
	"Version"="v${APP_VERSION}" \
	"Description"="Docker image for PostgreSQL ${APP_VERSION}." \
	"Dockerfile"="https://github.com/colovu/docker-${APP_NAME}" \
	"Vendor"="Endial Fang (endial@126.com)"

COPY prebuilds /

# 安装 locales 并修改默认编码
RUN set -eux; \
# 设置程序使用静默安装，而非交互模式；类似tzdata等程序需要使用静默安装
	export DEBIAN_FRONTEND=noninteractive; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends locales; \
	localedef -c -i en_US -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8; \
	echo 'en_GB.UTF-8 UTF-8\nen_US.UTF-8 UTF-8' >> /etc/locale.gen && locale-gen; \
	update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_MESSAGES=POSIX && dpkg-reconfigure locales;

ENV LANG=en_US.UTF-8 \
	LANGUAGE=en_US.UTF-8 \
	LC_ALL=en_US.UTF-8

RUN set -eux; \
# 设置程序使用静默安装，而非交互模式；类似tzdata等程序需要使用静默安装
	export DEBIAN_FRONTEND=noninteractive; \
	\
# 设置入口脚本的可执行权限
	chmod +x /usr/local/bin/entrypoint.sh; \
	\
# 为应用创建对应的组、用户、相关目录
	APP_DIRS="${APP_DEF_DIR:-} ${APP_CONF_DIR:-} ${APP_DATA_DIR:-} ${APP_CACHE_DIR:-} ${APP_RUN_DIR:-} ${APP_LOG_DIR:-} ${APP_CERT_DIR:-} ${APP_WWW_DIR:-} ${APP_DATA_LOG_DIR:-}"; \
	groupadd -r ${APP_GROUP}; \
	useradd -r -g ${APP_GROUP} -s /usr/sbin/nologin ${APP_USER}; \
	mkdir -p ${APP_DIRS}; \
	\
# 应用软件包及依赖
	appDeps=" \
		postgresql-${PG_MAJOR} \
		postgresql-common \
		libnss-wrapper \
		xz-utils \
		tzdata \
	"; \
	\
# 安装临时使用的软件包，在使用完后会进行删除
	fetchDeps=" \
		dirmngr \
		gnupg \
	"; \
	savedAptMark="$(apt-mark showmanual) ${appDeps}"; \
	apt-get update; \
	apt-get install -y --no-install-recommends ${fetchDeps}; \
	\
	GPG_KEY='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8'; \
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "${GPG_KEY}"|| \
	gpg --batch --keyserver pgp.mit.edu --recv-keys "$GPG_KEY" || \
	gpg --batch --keyserver keys.gnupg.net --recv-keys "$GPG_KEY" || \
    gpg --batch --keyserver keyserver.pgp.com --recv-keys "$GPG_KEY"; \
	gpg --batch --export "${GPG_KEY}" > /etc/apt/trusted.gpg.d/postgres.gpg; \
	command -v gpgconf > /dev/null && gpgconf --kill all; \
	rm -rf "$GNUPGHOME"; \
	apt-key list; \
	\
	echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main ${PG_MAJOR}" >> /etc/apt/sources.list; \
	echo "deb-src http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main ${PG_MAJOR}" >> /etc/apt/sources.list; \
	apt-get update; \
	apt-get install -y --no-install-recommends ${appDeps}; \
	\
# 为中国区使用重新配置tzdata信息
	ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
	dpkg-reconfigure -f noninteractive tzdata; \
	\
# 检测是否存在overrides脚本文件，如果存在，执行
	{ [ ! -e "/usr/local/overrides/overrides-${APP_VERSION}.sh" ] || /bin/bash "/usr/local/overrides/overrides-${APP_VERSION}.sh"; }; \
	\
# 设置临时目录的权限信息，设置为777是为了保证后续使用`--user`或`gosu`时，可以更改目录对应的用户属性信息；运行时会被更改为700或755
	chown -Rf ${APP_USER}:${APP_GROUP} ${APP_DIRS}; \
	chmod 777 ${APP_DIRS}; \
	\
# 查找新安装的应用及应用依赖软件包，并标识为'manual'，防止后续自动清理时被删除
	apt-mark auto '.*' > /dev/null; \
	{ [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; }; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { print $(NF-1) }' \
		| sort -u \
		| xargs -r dpkg-query --search \
		| cut -d: -f1 \
		| sort -u \
		| xargs -r apt-mark manual; \
	\
# 删除安装的临时依赖软件包，清理缓存
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false ${fetchDeps}; \
	apt-get autoclean -y; \
	rm -rf /var/lib/apt/lists/*; \
	\
# 验证安装的软件是否可以正常运行，常规情况下放置在命令行的最后
	gosu ${APP_USER} postgres --version;

VOLUME ["/srv/conf", "/srv/data", "/var/log", "/var/run"]

# 默认使用gosu切换为新建用户启动，必须保证端口在1024之上
EXPOSE 5432

# 容器初始化命令，默认存放在：/usr/local/bin/entrypoint.sh
ENTRYPOINT ["entrypoint.sh"]

# 应用程序的服务命令，必须使用非守护进程方式运行
CMD ["postgres", "--config-file=/srv/conf/postgresql/10/main/postgresql.conf"]
