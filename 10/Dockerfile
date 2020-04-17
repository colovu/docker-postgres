FROM endial/ubuntu:v18.04
# --platform=$BUILDPLATFORM linux/amd64, linux/arm64, or windows/amd64

LABEL \
	"Version"="v10.12" \
	"Description"="Docker image for PostgreSQL 10.12 based on Ubuntu 18.04." \
	"Dockerfile"="https://github.com/endial/docker-libs" \
	"Vendor"="Endial Fang (endial@126.com)"

ENV PG_MAJOR 		10
ENV PG_VERSION 		10.12-2.pgdg18.04+1
ENV PG_KEYS		B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

ENV PGDATA /srv/data/postgresql
ENV PATH $PATH:/usr/lib/postgresql/${PG_MAJOR}/bin

RUN set -eux; \
# add user after ningx docker
	groupadd -r -g 502 postgres; \
	useradd -r -g postgres -d /var/lib/postgresql -s /bin/bash -u 502 postgres; \
	mkdir -p /var/lib/postgresql; \
	chown -R postgres:postgres /var/lib/postgresql; \
	\
	fetchDeps=" \
		dirmngr \
		gnupg \
	"; \
	apt update; \
	apt install -y --no-install-recommends ${fetchDeps}; \
	\
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "${PG_KEYS}"; \
	gpg --batch --export "${PG_KEYS}" > /etc/apt/trusted.gpg.d/postgres.gpg; \
	command -v gpgconf > /dev/null && gpgconf --kill all; \
	rm -rf "$GNUPGHOME"; \
	apt-key list; \
	\
	echo "deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main ${PG_MAJOR}" >> /etc/apt/sources.list; \
	echo "deb-src http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main ${PG_MAJOR}" >> /etc/apt/sources.list; \
	apt update; \
	\
# set noninteractive for install tzdata
	export DEBIAN_FRONTEND=noninteractive; \
	\
	apt install -y --no-install-recommends \
		postgresql-${PG_MAJOR}=${PG_VERSION} \
		postgresql-common \
		libnss-wrapper \
		xz-utils \
	; \
	\
# reconfigure tzdata for China
	ln -fs /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
	dpkg-reconfigure -f noninteractive tzdata; \
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
