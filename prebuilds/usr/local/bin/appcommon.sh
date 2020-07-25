#!/bin/bash
# Ver: 1.0 by Endial Fang (endial@126.com)
# 
# 应用通用业务处理函数

# 加载依赖脚本
#. /usr/local/scripts/liblog.sh          # 日志输出函数库
. /usr/local/scripts/libcommon.sh       # 通用函数库
. /usr/local/scripts/libfile.sh
. /usr/local/scripts/libfs.sh
. /usr/local/scripts/libos.sh
. /usr/local/scripts/libservice.sh
. /usr/local/scripts/libvalidations.sh

# 函数列表

# 加载应用使用的环境变量初始值，该函数在相关脚本中以 eval 方式调用
# 全局变量:
#   ENV_* : 容器使用的全局变量
#   APP_* : 在镜像创建时定义的全局变量
#   *_* : 应用配置文件使用的全局变量，变量名根据配置项定义
# 返回值:
#   可以被 'eval' 使用的序列化输出
docker_app_env() {
    cat <<"EOF"
# Common Settings
export ENV_DEBUG=${ENV_DEBUG:-false}
export ALLOW_EMPTY_PASSWORD="${ALLOW_EMPTY_PASSWORD:-no}"

# Paths
export APP_DATA_LOG_DIR="${PG_INITDB_WAL_DIR:-${APP_DATA_LOG_DIR}}"
export PG_DATA_DIR="${PG_DATA_DIR:-${APP_DATA_DIR}/${APP_VERSION}}"
export PGDATA="${PG_DATA_DIR}"

export PG_CONF_FILE="${APP_CONF_DIR}/${APP_VERSION}/main/postgresql.conf"
export PG_HBA_FILE="${APP_CONF_DIR}/${APP_VERSION}/main/pg_hba.conf"
export PG_IDENT_FILE="${APP_CONF_DIR}/${APP_VERSION}/main/pg_ident.conf"
export PG_RECOVERY_FILE="${PG_DATA_DIR}/recovery.conf"
export PG_PID_FILE="${APP_RUN_DIR}/postgresql.pid"
export PG_LOG_FILE="${APP_LOG_DIR}/postgresql.log"

# Users
export APP_USER="${PG_DAEMON_USER:-${APP_USER}}"
export APP_GROUP="${PG_DAEMON_GROUP:-${APP_GROUP}}"

# Cluster configuration
export PG_CLUSTER_APP_NAME=${PG_CLUSTER_APP_NAME:-cvreceiver}
export PG_REPLICATION_MODE="${PG_REPLICATION_MODE:-master}"

export PG_MASTER_HOST="${PG_MASTER_HOST:-}"
export PG_MASTER_PORT_NUMBER="${PG_MASTER_PORT_NUMBER:-5432}"
export PG_NUM_SYNCHRONOUS_REPLICAS="${PG_NUM_SYNCHRONOUS_REPLICAS:-0}"
export PG_REPLICATION_USER="${PG_REPLICATION_USER:-}"
export PG_REPLICATION_PASSWORD="${PG_REPLICATION_PASSWORD:-}"

export PG_SYNCHRONOUS_COMMIT_MODE="${PG_SYNCHRONOUS_COMMIT_MODE:-on}"
export PG_FSYNC="${PG_FSYNC:-on}"

# PostgreSQL settings
export PG_INIT_MAX_TIMEOUT=${PG_INIT_MAX_TIMEOUT:-60}
export PG_INITDB_ARGS="${PG_INITDB_ARGS:-}"
export PG_PORT_NUMBER="${PG_PORT_NUMBER:-5432}"

# PostgreSQL TLS Settings

# PostgreSQL LDAP Settings
export PG_ENABLE_LDAP="${PG_ENABLE_LDAP:-no}"
export PG_LDAP_URL="${PG_LDAP_URL:-}"
export PG_LDAP_PREFIX="${PG_LDAP_PREFIX:-}"
export PG_LDAP_SUFFIX="${PG_LDAP_SUFFIX:-}"
export PG_LDAP_SERVER="${PG_LDAP_SERVER:-}"
export PG_LDAP_PORT="${PG_LDAP_PORT:-}"
export PG_LDAP_SCHEME="${PG_LDAP_SCHEME:-}"
export PG_LDAP_TLS="${PG_LDAP_TLS:-}"
export PG_LDAP_BASE_DN="${PG_LDAP_BASE_DN:-}"
export PG_LDAP_BIND_DN="${PG_LDAP_BIND_DN:-}"
export PG_LDAP_BIND_PASSWORD="${PG_LDAP_BIND_PASSWORD:-}"
export PG_LDAP_SEARCH_ATTR="${PG_LDAP_SEARCH_ATTR:-}"
export PG_LDAP_SEARCH_FILTER="${PG_LDAP_SEARCH_FILTER:-}"

# Authentication
export PG_USERNAME="${PG_USERNAME:-postgres}"
export PG_PASSWORD="${PG_PASSWORD:-}"
export PG_DATABASE="${PG_DATABASE:-postgres}"

export PG_INITSCRIPTS_USERNAME="${PG_INITSCRIPTS_USERNAME:-${PG_USERNAME}}"
export PG_INITSCRIPTS_PASSWORD="${PG_INITSCRIPTS_PASSWORD:-${PG_PASSWORD}}"
EOF

    # 利用 *_FILE 设置密码，不在配置命令中设置密码，增强安全性
    if [[ -f "${PG_POSTGRES_PASSWORD_FILE:-}" ]]; then
        cat <<"EOF"
export PG_POSTGRES_PASSWORD="$(< "${PG_POSTGRES_PASSWORD_FILE}")"
EOF
    else
        cat <<"EOF"
export PG_POSTGRES_PASSWORD="${PG_POSTGRES_PASSWORD:-}"
EOF
    fi

    if [[ -f "${PG_PASSWORD_FILE:-}" ]]; then
        cat <<"EOF"
export PG_PASSWORD="$(< "${PG_PASSWORD_FILE}")"
EOF
    fi
    
    if [[ -f "${PG_REPLICATION_PASSWORD_FILE:-}" ]]; then
        cat <<"EOF"
export PG_REPLICATION_PASSWORD="$(< "${PG_REPLICATION_PASSWORD_FILE}")"
EOF
    fi
}

# 配置 libnss_wrapper 以使得 PostgreSQL 命令可以以任意用户身份执行
# 全局变量:
#   PG_*
postgresql_enable_nss_wrapper() {
    if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
        LOG_D "Configuring libnss_wrapper..."
        export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
        export NSS_WRAPPER_PASSWD="$(mktemp)"
        export NSS_WRAPPER_GROUP="$(mktemp)"
        echo "postgres:x:$(id -u):$(id -g):PostgreSQL:${PG_DATA_DIR}:/bin/false" > "$NSS_WRAPPER_PASSWD"
        echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
    fi
}

postgresql_disable_nss_wrapper() {
    # unset/cleanup "nss_wrapper" bits
    if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
        rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
        unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
    fi
}

# 将变量配置更新至配置文件
# 参数:
#   $1 - 文件
#   $2 - 变量
#   $3 - 值（列表）
postgresql_common_conf_set() {
    local file="${1:?missing file}"
    local key="${2:?missing key}"
    shift
    shift
    local values=("$@")

    if [[ "${#values[@]}" -eq 0 ]]; then
        LOG_E "missing value"
        return 1
    elif [[ "${#values[@]}" -ne 1 ]]; then
        for i in "${!values[@]}"; do
            postgresql_common_conf_set "$file" "${key[$i]}" "${values[$i]}"
        done
    else
        value="${values[0]}"
        # Check if the value was set before
        if grep -q "^[#\\s]*$key\s*=.*" "$file"; then
            # Update the existing key
            replace_in_file "$file" "^[#\\s]*${key}\s*=.*" "${key} = \'${value}\'" false
        else
            # 增加一个新的配置项；如果在其他位置有类似操作，需要注意换行
            printf "%s = %s" "$key" "$value" >>"$file"
        fi
    fi
}

# 更新 postgresql.conf 配置文件中指定变量值
# 全局变量:
#   PG_CONF_FILE
# 变量:
#   $1 - 变量
#   $2 - 值（列表）
postgresql_conf_set() {
    postgresql_common_conf_set "${PG_CONF_FILE}" "$@"
}

# 更新 pg_hba.conf 配置文件中指定变量值
# 全局变量:
#   PG_HBA_FILE
# 变量:
#   $1 - 变量
#   $2 - 值（列表）
postgresql_hba_set() {
    replace_in_file "${PG_HBA_FILE}" "${1}" "${2}" false
}

# 更新 pg_ident.conf 配置文件中指定变量值
# 全局变量:
#   PG_IDENT_FILE
# 变量:
#   $1 - 变量
#   $2 - 值（列表）
postgresql_ident_set() {
    postgresql_common_conf_set "${PG_IDENT_FILE}" "$@"
}

# 更新 recover.conf 配置文件中指定变量值
# 全局变量:
#   PG_CONF_FILE
# 变量:
#   $1 - 变量
#   $2 - 值（列表）
postgresql_recover_set() {
    postgresql_common_conf_set "${PG_RECOVERY_FILE}" "$@"
}

# 初始化 pg_hba.conf 文件，增加 LDAP 配置；同时保留本地认证
# 全局变量:
#   PG_*
postgresql_ldap_auth_configuration() {
    LOG_I "Generating LDAP authentication configuration"
    local ldap_configuration=""

    if [[ -n "$PG_LDAP_URL" ]]; then
        ldap_configuration="ldapurl=\"${PG_LDAP_URL}\""
    else
        ldap_configuration="ldapserver=${PG_LDAP_SERVER}"

        [[ -n "$PG_LDAP_PREFIX" ]] && ldap_configuration+=" ldapprefix=\"${PG_LDAP_PREFIX}\""
        [[ -n "$PG_LDAP_SUFFIX" ]] && ldap_configuration+=" ldapsuffix=\"${PG_LDAP_SUFFIX}\""
        [[ -n "$PG_LDAP_PORT" ]] && ldap_configuration+=" ldapport=${PG_LDAP_PORT}"
        [[ -n "$PG_LDAP_BASE_DN" ]] && ldap_configuration+=" ldapbasedn=\"${PG_LDAP_BASE_DN}\""
        [[ -n "$PG_LDAP_BIND_DN" ]] && ldap_configuration+=" ldapbinddn=\"${PG_LDAP_BIND_DN}\""
        [[ -n "$PG_LDAP_BIND_PASSWORD" ]] && ldap_configuration+=" ldapbindpasswd=${PG_LDAP_BIND_PASSWORD}"
        [[ -n "$PG_LDAP_SEARCH_ATTR" ]] && ldap_configuration+=" ldapsearchattribute=${PG_LDAP_SEARCH_ATTR}"
        [[ -n "$PG_LDAP_SEARCH_FILTER" ]] && ldap_configuration+=" ldapsearchfilter=\"${PG_LDAP_SEARCH_FILTER}\""
        [[ -n "$PG_LDAP_TLS" ]] && ldap_configuration+=" ldaptls=${PG_LDAP_TLS}"
        [[ -n "$PG_LDAP_SCHEME" ]] && ldap_configuration+=" ldapscheme=${PG_LDAP_SCHEME}"
    fi

    cat << EOF > "$PG_HBA_FILE"
local    all             all                                     trust
host     all             postgres        0.0.0.0/0               trust
host     all             postgres        ::/0                    trust
host     all             all             0.0.0.0/0               ldap $ldap_configuration
host     all             all             ::/0                    ldap $ldap_configuration
EOF
}

# 修改 pg_hba.conf 文件，增加主从复制从服务器认证许可
# 全局变量:
#   PG_*
postgresql_add_replication_to_pghba() {
    local replication_auth="trust"
    if [[ -n "$PG_REPLICATION_PASSWORD" ]]; then
        replication_auth="md5"
    fi
    cat << EOF >> "$PG_HBA_FILE"
host      replication     all             0.0.0.0/0              ${replication_auth}
host      replication     all             ::/0                   ${replication_auth}
EOF
}

# 初始化 pg_hba.conf 文件
# 全局变量:
#   PG_*
postgresql_password_auth_configuration() {
    LOG_I "Generating local authentication configuration"
    cat << EOF > "$PG_HBA_FILE"
local    all             all                                     trust
host     all             all             0.0.0.0/0               trust
host     all             all             ::/0                    trust
EOF
}

# 使用运行中的 PostgreSQL 服务执行 SQL 操作
# 全局变量:
#   ENV_DEBUG
#   PG_*
# 参数:
#   $1 - 需要操作的数据库名
#   $2 - 操作使用的用户名
#   $3 - 操作用户密码
#   $4 - 主机
#   $5 - 端口
#   $6 - 扩展参数 (如: -tA)
postgresql_execute() {
    local -r db="${1:-}"
    local -r user="${2:-postgres}"
    local -r pass="${3:-}"
    local -r host="${4:-localhost}"
    local -r port="${5:-${PG_PORT_NUMBER}}"
    local -r opts="${6:-}"

    local args=( "-h" "$host" "-p" "$port" "-U" "$user" )
    local cmd=("psql")
    [[ -n "$db" ]] && args+=( "-d" "$db" )
    [[ -n "$opts" ]] && args+=( "$opts" )
    LOG_D "Execute args: ${args[@]}"
    if is_boolean_yes "${ENV_DEBUG}"; then
        PGPASSWORD=$pass "${cmd[@]}" "${args[@]}"
    else
        PGPASSWORD=$pass "${cmd[@]}" "${args[@]}" >/dev/null 2>&1
    fi
}

# 生成初始 postgres.conf 配置
# 全局变量:
#   PG_*
postgresql_default_postgresql_config() {
    LOG_I "Modify postgresql.conf with default values..."
    postgresql_conf_set "wal_level" "hot_standby"
    postgresql_conf_set "max_wal_size" "400MB"
    postgresql_conf_set "max_wal_senders" "16"
    postgresql_conf_set "wal_keep_segments" "12"
    postgresql_conf_set "hot_standby" "on"
    if (( PG_NUM_SYNCHRONOUS_REPLICAS > 0 )); then
        postgresql_conf_set "synchronous_commit" "$PG_SYNCHRONOUS_COMMIT_MODE"
        postgresql_conf_set "synchronous_standby_names" "${PG_NUM_SYNCHRONOUS_REPLICAS} (\"${PG_CLUSTER_APP_NAME}\")"
    fi
    postgresql_conf_set "fsync" "$PG_FSYNC"
}

# 生成初始 pg_hba.conf 配置
# 全局变量:
#   PG_*
postgresql_default_hba_config() {
    LOG_I "Modify pg_hba.conf with default values..."

    if is_boolean_yes "$PG_ENABLE_LDAP"; then
        postgresql_ldap_auth_configuration
    else
        postgresql_password_auth_configuration
    fi
}

# 生成初始 pg_hba.conf 配置
# 全局变量:
#   PG_*
postgresql_restrict_hba_config() {
    LOG_I "Modify pg_hba.conf for restrict configs..."

    if [[ -n "$PG_PASSWORD" ]]; then
        LOG_I "Configuring md5 encrypt"
        postgresql_hba_set "trust" "md5"
    fi
}

# 为 Slava 模式工作的节点创建 recovery.conf 文件
# 全局变量:
#   PG_*
postgresql_configure_recovery() {
    LOG_I "Setting up streaming replication slave..."
    if (( APP_VERSION >= 12 )); then
        # 版本为12以上时， Slave 节点配置保存在 postgresql.conf 文件中
        postgresql_conf_set "primary_conninfo" "host=${PG_MASTER_HOST} port=${PG_MASTER_PORT_NUMBER} user=${PG_REPLICATION_USER} password=${PG_REPLICATION_PASSWORD} application_name=${PG_CLUSTER_APP_NAME}"
        postgresql_conf_set "promote_trigger_file" "/tmp/postgresql.trigger.${PG_MASTER_PORT_NUMBER}"
        touch "$PG_DATA_DIR"/standby.signal
    else
        # 版本低于12时， Slave 节点配置保存在 recover.conf 文件中
        cp -f "/usr/share/postgresql/${APP_VERSION}/recovery.conf.sample" "$PG_RECOVERY_FILE"
        chmod 600 "$PG_RECOVERY_FILE"
        postgresql_recover_set "standby_mode" "on"
        postgresql_recover_set "primary_conninfo" "host=${PG_MASTER_HOST} port=${PG_MASTER_PORT_NUMBER} user=${PG_REPLICATION_USER} password=${PG_REPLICATION_PASSWORD} application_name=${PG_CLUSTER_APP_NAME}"
        postgresql_recover_set "trigger_file" "/tmp/postgresql.trigger.${PG_MASTER_PORT_NUMBER}"
    fi
}

# 为默认的数据库用户 postgres 设置密码
# 全局变量:
#   PG_*
# 参数:
#   $1 - 用户密码
postgresql_alter_postgres_user() {
    local -r escaped_password="${1//\'/\'\'}"
    LOG_I "Changing password of postgres"
    echo "ALTER ROLE postgres WITH PASSWORD '$escaped_password';" | postgresql_execute
}

# 为数据库 $PG_DATABASE 创建管理员账户
# 全局变量:
#   PG_*
postgresql_create_admin_user() {
    local -r escaped_password="${PG_PASSWORD//\'/\'\'}"
    LOG_I "Creating user ${PG_USERNAME}"
    echo "CREATE ROLE \"${PG_USERNAME}\" WITH LOGIN CREATEDB PASSWORD '${escaped_password}';" | postgresql_execute
    
    LOG_I "Granting access to \"${PG_USERNAME}\" to the database \"${PG_DATABASE}\""
    echo "GRANT ALL PRIVILEGES ON DATABASE \"${PG_DATABASE}\" TO \"${PG_USERNAME}\"\;" | postgresql_execute "" "postgres" "$PG_POSTGRES_PASSWORD"
}

# 为 master-slave 复制模式创建用户
# 全局变量:
#   PG_*
postgresql_create_replication_user() {
    local -r escaped_password="${PG_REPLICATION_PASSWORD//\'/\'\'}"
    LOG_I "Creating replication user $PG_REPLICATION_USER"
    echo "CREATE ROLE \"$PG_REPLICATION_USER\" REPLICATION LOGIN ENCRYPTED PASSWORD '$escaped_password'" | postgresql_execute
}

# 创建用户自定义数据库 $PG_DATABASE
# 全局变量:
#   PG_*
postgresql_create_custom_database() {
    echo "CREATE DATABASE \"$PG_DATABASE\"" | postgresql_execute "" "postgres" "" "localhost"
}

# 检测用户参数信息是否满足条件; 针对部分权限过于开放情况，打印提示信息
# 全局变量：
#   PG_*
app_verify_minimum_env() {
    local error_code=0
    LOG_D "Validating settings in PG_* env vars..."

    # Auxiliary functions
    print_validation_error() {
        LOG_E "$1"
        error_code=1
    }

    empty_password_enabled_warn() {
        LOG_W "You set the environment variable ALLOW_EMPTY_PASSWORD=${ALLOW_EMPTY_PASSWORD}. For safety reasons, do not use this flag in a production environment."
    }
    empty_password_error() {
        print_validation_error "The $1 environment variable is empty or not set. Set the environment variable ALLOW_EMPTY_PASSWORD=yes to allow the container to be started with blank passwords. This is recommended only for development."
    }
    if is_boolean_yes "$ALLOW_EMPTY_PASSWORD"; then
        empty_password_enabled_warn
    else
        if [[ -z "$PG_PASSWORD" ]]; then
            empty_password_error "PG_PASSWORD"
        fi
        if (( ${#PG_PASSWORD} > 100 )); then
            print_validation_error "The password cannot be longer than 100 characters. Set the environment variable PG_PASSWORD with a shorter value"
        fi
        if [[ -n "$PG_USERNAME" ]] && [[ -z "$PG_PASSWORD" ]]; then
            empty_password_error "PG_PASSWORD"
        fi
        if [[ -n "$PG_USERNAME" ]] && [[ "$PG_USERNAME" != "postgres" ]] && [[ -n "$PG_PASSWORD" ]] && [[ -z "$PG_DATABASE" ]]; then
            print_validation_error "In order to use a custom PostgreSQL user you need to set the environment variable PG_DATABASE as well"
        fi
    fi

    if [[ -n "$PG_REPLICATION_MODE" ]]; then
        if [[ "$PG_REPLICATION_MODE" = "master" ]]; then
            if (( PG_NUM_SYNCHRONOUS_REPLICAS < 0 )); then
                print_validation_error "The number of synchronous replicas cannot be less than 0. Set the environment variable PG_NUM_SYNCHRONOUS_REPLICAS"
            fi
        elif [[ "$PG_REPLICATION_MODE" = "slave" ]]; then
            if [[ -z "$PG_MASTER_HOST" ]]; then
                print_validation_error "Slave replication mode chosen without setting the environment variable PG_MASTER_HOST. Use it to indicate where the Master node is running"
            fi
            if [[ -z "$PG_REPLICATION_USER" ]]; then
                print_validation_error "Slave replication mode chosen without setting the environment variable PG_REPLICATION_USER. Make sure that the master also has this parameter set"
            fi
        else
            print_validation_error "Invalid replication mode. Available options are 'master/slave'"
        fi
        # Common replication checks
        if [[ -n "$PG_REPLICATION_USER" ]] && [[ -z "$PG_REPLICATION_PASSWORD" ]]; then
            empty_password_error "PG_REPLICATION_PASSWORD"
        fi
    else
        if is_boolean_yes "$ALLOW_EMPTY_PASSWORD"; then
            empty_password_enabled_warn
        else
            if [[ -z "$PG_PASSWORD" ]]; then
                empty_password_error "PG_PASSWORD"
            fi
            if [[ -n "$PG_USERNAME" ]] && [[ -z "$PG_PASSWORD" ]]; then
                empty_password_error "PG_PASSWORD"
            fi
        fi
    fi

    if ! is_yes_no_value "$PG_ENABLE_LDAP"; then
        empty_password_error "The values allowed for PG_ENABLE_LDAP are: yes or no"
    fi

    if is_boolean_yes "$PG_ENABLE_LDAP" && [[ -n "$PG_LDAP_URL" ]] && [[ -n "$PG_LDAP_SERVER" ]]; then
        empty_password_error "You can not set PG_LDAP_URL and PG_LDAP_SERVER at the same time. Check your LDAP configuration."
    fi

    [[ "$error_code" -eq 0 ]] || exit "$error_code"
}

# 更改默认监听地址为 "*" 或 "0.0.0.0"，以对容器外提供服务；默认配置文件应当为仅监听 localhost(127.0.0.1)
app_enable_remote_connections() {
    LOG_D "Modify default config to enable all IP access"
    postgresql_conf_set "listen_addresses" "*"
}

# 以后台方式启动应用服务，并等待启动就绪
# 全局变量:
#   PG_*
#   ENV_DEBUG
app_start_server_bg() {
    is_app_server_running && return

    # -w wait until operation completes (default)
    # -W don't wait until operation completes
    # -D location of the database storage area
    # -l write (or append) server log to FILENAME
    # -o command line options to pass to postgres or initdb
    local -r pg_ctl_flags=("-W" "-D" "$PG_DATA_DIR" "-l" "$PG_LOG_FILE" "-o" "--config-file=$PG_CONF_FILE --external_pid_file=$PG_PID_FILE --hba_file=$PG_HBA_FILE")
    LOG_I "Starting ${APP_NAME} in background..."
    local pg_ctl_cmd=(pg_ctl)
    if is_boolean_yes "${ENV_DEBUG}"; then
        "${pg_ctl_cmd[@]}" "start" "${pg_ctl_flags[@]}"
    else
        "${pg_ctl_cmd[@]}" "start" "${pg_ctl_flags[@]}" >/dev/null 2>&1
    fi

    local -r check_args=("-h" "localhost" "-p" "${PG_PORT_NUMBER}" "-U" "postgres")
    local check_cmd=(pg_isready)
    local counter=$PG_INIT_MAX_TIMEOUT
    LOG_I "Checking ${APP_NAME} ready status..."
    while ! PGPASSWORD=$PG_REPLICATION_PASSWORD "${check_cmd[@]}" "${check_args[@]}" >/dev/null 2>&1; do
        sleep 1
        counter=$(( counter - 1 ))
        if (( counter <= 0 )); then
            LOG_E "PostgreSQL is not ready after $PG_INIT_MAX_TIMEOUT seconds"
            exit 1
        fi
    done
    LOG_D "${APP_NAME} is ready for service..."
}

# 停止应用后台服务
# 全局变量:
#   PG_PID_FILE
app_stop_server() {
    is_app_server_running || return

    LOG_I "Stopping ${APP_NAME}..."
    stop_service_using_pid "$PG_PID_FILE"
}

# 检测应用服务是否在后台运行中
# 全局变量:
#   PG_PID_FILE
# 返回值:
#   布尔值
is_app_server_running() {
    local pid
    pid="$(get_pid_from_file "$PG_PID_FILE")"

    if [[ -z "$pid" ]]; then
        LOG_D "${APP_NAME} is Stopped..."
        false
    else
        LOG_D "${APP_NAME} is Running..."
        is_service_running "$pid"
    fi
}

# 清理初始化应用时生成的临时文件
app_clean_tmp_file() {
    LOG_D "Clean ${APP_NAME} tmp files..."

	rm -rf "${PG_LOG_FILE}"
}

# 在重新启动容器时，删除标志文件及必须删除的临时文件 (容器重新启动)
# 全局变量:
#   APP_*
#   PG_*
app_clean_from_restart() {
    LOG_D "Delete temp files when restart container"
    local -r -a files=(
        "$PG_DATA_DIR"/postmaster.pid
        "$PG_DATA_DIR"/standby.signal
        "$PG_DATA_DIR"/recovery.signal
        "$PG_PID_FILE"
    )

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            LOG_I "Cleaning stale $file file"
            rm "$file"
        fi
    done
}

# 应用默认初始化操作
# 执行完毕后，生成文件 ${APP_CONF_DIR}/.app_init_flag 及 ${APP_DATA_DIR}/.data_init_flag 文件
docker_app_init() {
	app_clean_from_restart
    LOG_D "Check init status of ${APP_NAME}..."

    # 检测配置文件是否存在
    if [[ ! -f "${APP_CONF_DIR}/.app_init_flag" ]]; then
        LOG_I "No injected configuration file found, creating default config files..."
        postgresql_default_postgresql_config
        postgresql_default_hba_config

        if [[ "$PG_REPLICATION_MODE" = "master" ]]; then
            [[ -n "$PG_REPLICATION_USER" ]] && postgresql_add_replication_to_pghba
        else
            postgresql_configure_recovery
        fi

        touch ${APP_CONF_DIR}/.app_init_flag
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_CONF_DIR}/.app_init_flag
    else
        LOG_I "User injected custom configuration detected!"
    fi

    if [[ ! -f "${APP_DATA_DIR}/.data_init_flag" ]]; then
        LOG_I "Deploying ${APP_NAME} from scratch..."
        if [[ "$PG_REPLICATION_MODE" = "master" ]]; then
            postgresql_master_init_db
        	app_start_server_bg
            [[ "$PG_DATABASE" != "postgres" ]] && postgresql_create_custom_database

            # 为数据库授权；默认用户不为 postgres 时，需要创建管理员账户
            LOG_D "Set password for postgres user"
            if [[ "$PG_USERNAME" = "postgres" ]]; then
                [[ -n "$PG_PASSWORD" ]] && postgresql_alter_postgres_user "$PG_PASSWORD"
            else
                if [[ -n "$PG_POSTGRES_PASSWORD" ]]; then
                    postgresql_alter_postgres_user "$PG_POSTGRES_PASSWORD"
                fi
                postgresql_create_admin_user
            fi
            [[ -n "$PG_REPLICATION_USER" ]] && postgresql_create_replication_user
        else
            postgresql_slave_init_db
        fi

        touch ${APP_DATA_DIR}/.data_init_flag
        echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.data_init_flag
    else
        LOG_I "Deploying ${APP_NAME} with persisted data..."
    fi
}

# 用户自定义的前置初始化操作，依次执行目录 preinitdb.d 中的初始化脚本
# 执行完毕后，生成文件 ${APP_DATA_DIR}/.custom_preinit_flag
docker_custom_preinit() {
    LOG_D "Check custom pre-init status of ${APP_NAME}..."

    # 检测用户配置文件目录是否存在 preinitdb.d 文件夹，如果存在，尝试执行目录中的初始化脚本
    if [ -d "/srv/conf/${APP_NAME}/preinitdb.d" ]; then
        # 检测数据存储目录是否存在已初始化标志文件；如果不存在，检索可执行脚本文件并进行初始化操作
        if [[ -n $(find "/srv/conf/${APP_NAME}/preinitdb.d/" -type f -regex ".*\.\(sh\)") ]] && \
            [[ ! -f "${APP_DATA_DIR}/.custom_preinit_flag" ]]; then
            LOG_I "Process custom pre-init scripts from /srv/conf/${APP_NAME}/preinitdb.d..."

            # 检索所有可执行脚本，排序后执行
            find "/srv/conf/${APP_NAME}/preinitdb.d/" -type f -regex ".*\.\(sh\)" | sort | docker_process_init_files

            touch ${APP_DATA_DIR}/.custom_preinit_flag
            echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.custom_preinit_flag
            LOG_I "Custom preinit for ${APP_NAME} complete."
        else
            LOG_I "Custom preinit for ${APP_NAME} already done before, skipping initialization."
        fi
    fi
}

# 用户自定义的应用初始化操作，依次执行目录initdb.d中的初始化脚本
# 执行完毕后，生成文件 ${APP_DATA_DIR}/.custom_init_flag
docker_custom_init() {
    LOG_D "Check custom init status of ${APP_NAME}..."

    # 检测用户配置文件目录是否存在 initdb.d 文件夹，如果存在，尝试执行目录中的初始化脚本
    if [ -d "/srv/conf/${APP_NAME}/initdb.d" ]; then
    	# 检测数据存储目录是否存在已初始化标志文件；如果不存在，检索可执行脚本文件并进行初始化操作
    	if [[ -n $(find "/srv/conf/${APP_NAME}/initdb.d/" -type f -regex ".*\.\(sh\|sql\|sql.gz\)") ]] && \
            [[ ! -f "${APP_DATA_DIR}/.custom_init_flag" ]]; then
            LOG_I "Process custom init scripts from /srv/conf/${APP_NAME}/initdb.d..."

            app_start_server_bg

            # 检索所有可执行脚本，排序后执行
    		find "/srv/conf/${APP_NAME}/initdb.d/" -type f -regex ".*\.\(sh\|sql\|sql.gz\)" | sort | while read -r f; do
                case "$f" in
                    *.sh)
                        if [[ -x "$f" ]]; then
                            LOG_D "Executing $f"; "$f"
                        else
                            LOG_D "Sourcing $f"; . "$f"
                        fi
                        ;;
                    *.sql)    LOG_D "Executing $f"; postgresql_execute "$PG_DATABASE" "$PG_INITSCRIPTS_USERNAME" "$PG_INITSCRIPTS_PASSWORD" < "$f";;
                    *.sql.gz) LOG_D "Executing $f"; gunzip -c "$f" | postgresql_execute "$PG_DATABASE" "$PG_INITSCRIPTS_USERNAME" "$PG_INITSCRIPTS_PASSWORD";;
                    *)        LOG_D "Ignoring $f" ;;
                esac
            done

            touch ${APP_DATA_DIR}/.custom_init_flag
    		echo "$(date '+%Y-%m-%d %H:%M:%S') : Init success." >> ${APP_DATA_DIR}/.custom_init_flag
    		LOG_I "Custom init for ${APP_NAME} complete."
    	else
    		LOG_I "Custom init for ${APP_NAME} already done before, skipping initialization."
    	fi
    fi

    # 停止初始化时启动的后台服务
	is_app_server_running && app_stop_server

    # 删除第一次运行生成的临时文件
    app_clean_tmp_file

    # 如果设置了用户密码，启用 md5 加密的密码认证 
    postgresql_restrict_hba_config

	# 绑定所有 IP ，启用远程访问
    app_enable_remote_connections
}

# 初始化 Master 节点数据库
# 全局变量:
#   PG_*
# 返回值:
#   布尔值
postgresql_master_init_db() {
    if ! is_dir_empty "$PG_DATA_DIR"; then
        LOG_E "Directory ${PG_DATA_DIR} exists but is not empty,"
        LOG_E "If you want to create a new database system, either remove or empty"
        LOG_E "the directory ${PG_DATA_DIR},  or run initdb"
        LOG_E "with an argument other than ${PG_DATA_DIR}."
        exit 1
    fi

    postgresql_enable_nss_wrapper

    local envExtraFlags=()
    local initdb_args=()
    if [[ -n "${PG_INITDB_ARGS}" ]]; then
        read -r -a envExtraFlags <<< "$PG_INITDB_ARGS"
        initdb_args+=("${envExtraFlags[@]}")
    fi
    #initdb+=("-o" "--config-file=$PG_CONF_FILE --external_pid_file=$PG_PID_FILE --hba_file=$PG_HBA_FILE")
    initdb_args+=("--waldir=$APP_DATA_LOG_DIR")

    local initdb_cmd=(initdb)

    LOG_I "Initializing PostgreSQL database"

    if [[ -n "${initdb_args[*]}" ]]; then
        LOG_I "extra initdb arguments: ${initdb_args[*]}"
    fi

    if is_boolean_yes "${ENV_DEBUG}"; then
        "${initdb_cmd[@]}" -E UTF8 -D "$PG_DATA_DIR" -U "postgres" "${initdb_args[@]}"
    else
        "${initdb_cmd[@]}" -E UTF8 -D "$PG_DATA_DIR" -U "postgres" "${initdb_args[@]}" >/dev/null 2>&1
    fi

    postgresql_disable_nss_wrapper
}

# 初始化 Slave 节点数据库
# 全局变量:
#   PG_*
# 返回值:
#   布尔值
postgresql_slave_init_db() {
    LOG_I "Waiting for replication master to accept connections (${PG_INIT_MAX_TIMEOUT} seconds)..."
    local -r check_args=("-U" "$PG_REPLICATION_USER" "-h" "$PG_MASTER_HOST" "-p" "$PG_MASTER_PORT_NUMBER" "-d" "postgres")
    local check_cmd=(pg_isready)
    local ready_counter=$PG_INIT_MAX_TIMEOUT

    while ! PGPASSWORD=$PG_REPLICATION_PASSWORD "${check_cmd[@]}" "${check_args[@]}" >/dev/null 2>&1;do
        sleep 1
        ready_counter=$(( ready_counter - 1 ))
        if (( ready_counter <= 0 )); then
            LOG_E "PostgreSQL master is not ready after $PG_INIT_MAX_TIMEOUT seconds"
            exit 1
        fi
    done

    LOG_I "Replicating the database from node master..."
    #local -r backup_args=("-D" "$PG_DATA_DIR" -d "hostaddr=$PG_MASTER_HOST port=$PG_MASTER_PORT_NUMBER user=$PG_REPLICATION_USER password=$PG_REPLICATION_PASSWORD" -v -Fp -Xs
    local -r backup_args=("-D" "$PG_DATA_DIR" "-U" "$PG_REPLICATION_USER" "-h" "$PG_MASTER_HOST" "-p" "$PG_MASTER_PORT_NUMBER" "-X" "stream" "-w" "-v" "-P")
    local backup_cmd=(pg_basebackup)
    local replication_counter=$PG_INIT_MAX_TIMEOUT

    while ! PGPASSWORD=$PG_REPLICATION_PASSWORD "${backup_cmd[@]}" "${backup_args[@]}";do
        LOG_D "Backup command failed. Sleeping and trying again"
        sleep 1
        replication_counter=$(( replication_counter - 1 ))
        if (( replication_counter <= 0 )); then
            LOG_E "Slave replication failed after trying for $PG_INIT_MAX_TIMEOUT seconds"
            exit 1
        fi
    done
}
