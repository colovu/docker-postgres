FROM endial/ubuntu:18.04

ENV PG_MAJOR=10 \
	PG_VERSION="10.12-2.pgdg18.04+1" \
	GPG_KEY='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
	PGDATA=/srv/data/postgresql \
	PATH=$PATH:/usr/lib/postgresql/10/bin

LABEL \
	"Version"="v${PG_MAJOR}" \
	"Description"="Docker image for PostgreSQL ${PG_MAJOR} based on Ubuntu 18.04." \
	"Dockerfile"="https://github.com/endial/docker-postgres" \
	"Vendor"="Endial Fang (endial@126.com)"

RUN set -eux; \
# 确保程序使用静默安装，而非交互模式
	export DEBIAN_FRONTEND=noninteractive; \
	groupadd -r postgres; \
	useradd -r -g postgres -s /usr/sbin/nologin -d /var/lib/postgresql postgres; \
	\
	mkdir -p /var/lib/postgresql /srv/conf/postgresql ${PGDATA} /var/log/postgresql /var/run/postgresql; \
	\
	fetchDeps=" \
		dirmngr \
		gnupg \
	"; \
	apt update; \
	apt install -y --no-install-recommends ${fetchDeps}; \
	\
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
	apt update; \
	\
	apt install -y --no-install-recommends \
		postgresql-${PG_MAJOR}=${PG_VERSION} \
		postgresql-common \
		libnss-wrapper \
		xz-utils \
		tzdata \
	; \
	\
# reconfigure tzdata for China
	ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
	dpkg-reconfigure -f noninteractive tzdata; \
	\
	chown -Rf postgres:postgres /var/lib/postgresql /srv/conf/postgresql ${PGDATA} /var/log/postgresql /var/run/postgresql; \
# this 777 will be replaced by 700 or 755 at runtime (allows semi-arbitrary "--user" values)
	chmod 777 /var/lib/postgresql /srv/conf/postgresql ${PGDATA} /var/log/postgresql /var/run/postgresql; \
	\
	apt purge -y --auto-remove ${fetchDeps}; \
	apt autoclean -y; \
	rm -rf /var/lib/apt/lists/*; \
	\
# make the sample config easier to munge (and "correct by default")
	dpkg-divert --add --rename --divert "/usr/share/postgresql/postgresql.conf.sample.dpkg" "/usr/share/postgresql/$PG_MAJOR/postgresql.conf.sample"; \
	cp -v /usr/share/postgresql/postgresql.conf.sample.dpkg /usr/share/postgresql/postgresql.conf.sample; \
	ln -sv ../postgresql.conf.sample "/usr/share/postgresql/$PG_MAJOR/";  


COPY ./entrypoint.sh /usr/local/bin/

VOLUME ["/srv/conf", "/srv/data", "/var/log", "/var/run"]

EXPOSE 5432

ENTRYPOINT ["entrypoint.sh"]

CMD ["postgres"]
