#!/bin/bash
# docker entrypoint script

set -Eeo pipefail

echo "[i] Initial Container"

# allow the container to be started with `--user` or `-u`
# if [ "$1" = 'app-name' -a "$(id -u)" = '0' ]; then
# 	echo "[i] Restart container with user: user-name"
# 	echo ""
# 	exec gosu user-name "$0" "$@"
# fi

# TODO swap to -Eeuo pipefail above (after handling all potentially-unset variables)

# 检测"_FILE"文件，并从文件中读取信息作为参数值；环境变量不允许 VAR 与 VAR_FILE 方式并存
# 
#  usage: file_env VAR [DEFAULT]
#     ie: file_env 'XYZ_DB_PASSWORD' 'example'
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

# check to see if this file is being run or sourced from another script
_is_sourced() {
	# https://unix.stackexchange.com/a/215279
	[ "${#FUNCNAME[@]}" -ge 2 ] \
		&& [ "${FUNCNAME[0]}" = '_is_sourced' ] \
		&& [ "${FUNCNAME[1]}" = 'source' ]
}

# 使用root用户运行时，创建默认的数据库存储目录，并修改对应目录所属用户为"postgres"
docker_create_db_directories() {
	local user; user="$(id -u)"

	# default value: /srv/data/postgresql
	if [ ! -d "$PGDATA" ]; then
		mkdir -p "$PGDATA"
		chmod 755 "$PGDATA"
	fi

	if [ ! -d /var/run/postgresql ]; then
		mkdir -p /var/run/postgresql || :
		chmod 755 /var/run/postgresql || :
	fi

	if [ ! -d /var/log/postgresql ]; then
		mkdir -p /var/log/postgresql || :
		chmod 755 /var/log/postgresql || :
	fi

	if [ ! -d /srv/conf/postgresql/initdb.d ]; then
		mkdir -p /srv/conf/postgresql/initdb.d
		chmod -R 755 /srv/conf/postgresql
		cp -rf /usr/share/postgresql/postgresql.conf.sample /srv/conf/postgresql/postgresql.conf
	fi

	if [ ! -d /srv/conf/postgresql-common ]; then
		mkdir -p /srv/conf/postgresql-common
		chmod 755 /srv/conf/postgresql-common
		cp -rf /etc/postgresql-common/createcluster.conf /srv/conf/postgresql-common/createcluster.conf
	fi

	# 创建数据库日志存储目录，修改相应目录的所属用户信息
	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		if [ "$user" = '0' ]; then
			find "$POSTGRES_INITDB_WALDIR" \! -user postgres -exec chown postgres '{}' +
		fi
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	# 允许容器使用`--user`参数启动，修改相应目录的所属用户信息
	if [ "$user" = '0' ]; then
		find "$PGDATA" \! -user postgres -exec chown postgres '{}' +
		find /var/run/postgresql \! -user postgres -exec chown postgres '{}' +
		find /var/log/postgresql \! -user postgres -exec chown postgres '{}' +
		find /srv/conf/postgresql \! -user postgres -exec chown postgres '{}' +
		find /srv/conf/postgresql-common \! -user postgres -exec chown postgres '{}' +
	fi
}

# 针对 PGDATA 目录为空时，使用'initdb'初始化数据目录；同时创建 POSTGRES_USER 定义的同名数据库用户
# 用户需要传给`initdb`的参数，可通过环境变量 POSTGRES_INITDB_ARGS 传输，或直接使用命令行参数传输到当前函数
# `initdb`会自动创建以下数据库："postgres", "template0", "template1" 
docker_init_database_dir() {
	# "initdb" 需要当前用户UID在 "/etc/passwd" 中存在，因此，如果需要时， 我们使用"nss_wrapper"虚拟相关用户
	if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
		export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
		export NSS_WRAPPER_PASSWD="$(mktemp)"
		export NSS_WRAPPER_GROUP="$(mktemp)"
		echo "postgres:x:$(id -u):$(id -g):PostgreSQL:$PGDATA:/bin/false" > "$NSS_WRAPPER_PASSWD"
		echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
	fi

	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		set -- --waldir "$POSTGRES_INITDB_WALDIR" "$@"
	fi

	eval 'initdb --username="$POSTGRES_USER" --pwfile=<(echo "$POSTGRES_PASSWORD") '"$POSTGRES_INITDB_ARGS"' "$@"'

	# unset/cleanup "nss_wrapper" bits
	if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi
}

# 如果 POSTGRES_PASSWORD 超过100字节，打印警告信息
# 如果 POSTGRES_PASSWORD 为空且 POSTGRES_HOST_AUTH_METHOD 不为 'trust'，打印错误信息并退出
# 如果 POSTGRES_HOST_AUTH_METHOD 设置为 'trust'，打印警告信息
docker_verify_minimum_env() {
	if [ "${#POSTGRES_PASSWORD}" -ge 100 ]; then
		cat >&2 <<-'EOWARN'
			WARNING: The supplied POSTGRES_PASSWORD is 100+ characters.
			  This will not work if used via PGPASSWORD with "psql".
			  https://www.postgresql.org/message-id/flat/E1Rqxp2-0004Qt-PL%40wrigleys.postgresql.org (BUG #6412)
			  https://github.com/docker-library/postgres/issues/507
		EOWARN
	fi
	if [ -z "$POSTGRES_PASSWORD" ] && [ 'trust' != "$POSTGRES_HOST_AUTH_METHOD" ]; then
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOE'
			Error: Database is uninitialized and superuser password is not specified.
			       You must specify POSTGRES_PASSWORD to a non-empty value for the
			       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".
			       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
			       connections without a password. This is *not* recommended.
			       See PostgreSQL documentation about "trust":
			       https://www.postgresql.org/docs/current/auth-trust.html
		EOE
		exit 1
	fi
	if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOWARN'
			********************************************************************************
			WARNING: POSTGRES_HOST_AUTH_METHOD has been set to "trust". This will allow
			         anyone with access to the Postgres port to access your database without
			         a password, even if POSTGRES_PASSWORD is set. See PostgreSQL
			         documentation about "trust":
			         https://www.postgresql.org/docs/current/auth-trust.html
			         In Docker's default configuration, this is effectively any other
			         container on the same system.
			         It is not recommended to use POSTGRES_HOST_AUTH_METHOD=trust. Replace
			         it with "-e POSTGRES_PASSWORD=password" instead to set a password in
			         "docker run".
			********************************************************************************
		EOWARN
	fi
}

# usage: docker_process_init_files [file [file [...]]]
#    ie: docker_process_init_files /always-initdb.d/*
# process initializer files, based on file extensions and permissions
docker_process_init_files() {
	# psql here for backwards compatiblilty "${psql[@]}"
	psql=( docker_process_sql )

	echo
	local f
	for f; do
		case "$f" in
			*.sh)
				# https://github.com/docker-library/postgres/issues/450#issuecomment-393167936
				# https://github.com/docker-library/postgres/pull/452
				if [ -x "$f" ]; then
					echo "$0: running $f"
					"$f"
				else
					echo "$0: sourcing $f"
					. "$f"
				fi
				;;
			*.sql)    echo "$0: running $f"; docker_process_sql -f "$f"; echo ;;
			*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | docker_process_sql; echo ;;
			*.sql.xz) echo "$0: running $f"; xzcat "$f" | docker_process_sql; echo ;;
			*)        echo "$0: ignoring $f" ;;
		esac
		echo
	done
}

# Execute sql script, passed via stdin (or -f flag of pqsl)
# usage: docker_process_sql [psql-cli-args]
#    ie: docker_process_sql --dbname=mydb <<<'INSERT ...'
#    ie: docker_process_sql -f my-file.sql
#    ie: docker_process_sql <my-file.sql
docker_process_sql() {
	local query_runner=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password )
	if [ -n "$POSTGRES_DB" ]; then
		query_runner+=( --dbname "$POSTGRES_DB" )
	fi

	"${query_runner[@]}" "$@"
}

# create initial database
# uses environment variables for input: POSTGRES_DB
docker_setup_db() {
	if [ "$POSTGRES_DB" != 'postgres' ]; then
		POSTGRES_DB= docker_process_sql --dbname postgres --set db="$POSTGRES_DB" <<-'EOSQL'
			CREATE DATABASE :"db" ;
		EOSQL
		echo
	fi
}

# 加载在后续脚本命令中使用的参数信息，包括从"*_FILE"文件中导入的配置
# 必须在其他函数使用前调用
docker_setup_env() {
	file_env 'POSTGRES_PASSWORD'

	file_env 'POSTGRES_USER' 'postgres'
	file_env 'POSTGRES_DB' "$POSTGRES_USER"
	file_env 'POSTGRES_INITDB_ARGS'
	# 变量 POSTGRES_HOST_AUTH_METHOD 不存在或值为空，赋值为默认值：md5
	: "${POSTGRES_HOST_AUTH_METHOD:=md5}"

	declare -g DATABASE_ALREADY_EXISTS
	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ -s "$PGDATA/PG_VERSION" ]; then
		DATABASE_ALREADY_EXISTS='true'
	fi
}

# 将环境变量 POSTGRES_HOST_AUTH_METHOD 定义的信息增加至配置文件 pg_hba.conf，保证允许本地连接
pg_setup_hba_conf() {
	{
		echo
		if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
			echo '# warning trust is enabled for all connections'
			echo '# see https://www.postgresql.org/docs/12/auth-trust.html'
		fi
		echo "host all all all $POSTGRES_HOST_AUTH_METHOD"
	} >> "$PGDATA/pg_hba.conf"
}

# start socket-only postgresql server for setting up or running scripts
# all arguments will be passed along as arguments to `postgres` (via pg_ctl)
docker_temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	# internal start of server in order to allow setup using psql client
	# does not listen on external TCP/IP and waits until start finishes
	set -- "$@" -c listen_addresses='' -p "${PGPORT:-5432}"

	PGUSER="${PGUSER:-$POSTGRES_USER}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

# stop postgresql server after done setting up user and running scripts
docker_temp_server_stop() {
	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" -m fast -w stop
}

# 检测可能导致postgres执行后直接退出的命令，如"--help"；如果存在，直接返回 0
_pg_want_help() {
	local arg
	for arg; do
		case "$arg" in
			-'?'|--help|--describe-config|-V|--version)
				return 0
				;;
		esac
	done
	return 1
}

_main() {
	# 如果命令行参数是以配置参数("-")开始，修改执行命令，确保使用postgres命令启动服务器
	if [ "${1:0:1}" = '-' ]; then
		set -- postgres "$@"
	fi

	# 命令行参数以postgres起始，且不包含直接返回的命令(如：-V、--version、--help)时，执行初始化操作
	if [ "$1" = 'postgres' ] && ! _pg_want_help "$@"; then
		docker_setup_env

		# 以root用户运行时，设置数据存储目录与权限；设置完成后，会使用gosu重新以"postgres"用户运行当前脚本
		docker_create_db_directories
		if [ "$(id -u)" = '0' ]; then
			echo "[i] Restart container with user: postgres"
			echo ""
			exec gosu postgres "$0" "$@"
		fi

		# 检测数据库存储目录是否为空；如果为空，进行初始化操作
		if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
			docker_verify_minimum_env

			# 检测目录权限，防止初始化失败
			ls /srv/conf/postgresql/initdb.d/ > /dev/null

			docker_init_database_dir
			pg_setup_hba_conf

			# PGPASSWORD is required for psql when authentication is required for 'local' connections via pg_hba.conf and is otherwise harmless
			# e.g. when '--auth=md5' or '--auth-local=md5' is used in POSTGRES_INITDB_ARGS
			export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
			docker_temp_server_start "$@"

			docker_setup_db
			docker_process_init_files /srv/conf/postgresql/initdb.d/*

			docker_temp_server_stop
			unset PGPASSWORD

			echo
			echo "[i] PostgreSQL init process complete; ready for start up."
			echo
		else
			echo
			echo "[i] PostgreSQL Database directory appears to contain a database; Skipping initialization"
			echo
		fi

		echo "[i] Start Application."
	fi

	# 执行命令行
	exec "$@"
}

if ! _is_sourced; then
	_main "$@"
fi
