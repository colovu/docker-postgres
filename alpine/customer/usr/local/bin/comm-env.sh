#!/bin/bash
# Ver: 1.0 by Endial Fang (endial@126.com)
# 
# 应用环境变量定义及初始化

# 通用设置
export ENV_DEBUG=${ENV_DEBUG:-false}
export ALLOW_ANONYMOUS_LOGIN="${ALLOW_ANONYMOUS_LOGIN:-no}"

# 通过读取变量名对应的 *_FILE 文件，获取变量值；如果对应文件存在，则通过传入参数设置的变量值会被文件中对应的值覆盖
# 变量优先级： *_FILE > 传入变量 > 默认值
app_env_file_lists=(
	PG_POSTGRES_PASSWORD
	PG_PASSWORD
	PG_REPLICATION_PASSWORD
	PG_LDAP_BIND_PASSWORD
)
for env_var in "${app_env_file_lists[@]}"; do
    file_env_var="${env_var}_FILE"
    if [[ -n "${!file_env_var:-}" ]]; then
        export "${env_var}=$(< "${!file_env_var}")"
        unset "${file_env_var}"
    fi
done
unset app_env_file_lists

# 应用路径参数
export APP_HOME_DIR="/usr/local/${APP_NAME}"
export APP_DEF_DIR="/etc/${APP_NAME}"
export APP_CONF_DIR="/srv/conf/${APP_NAME}"
export APP_DATA_DIR="/srv/data/${APP_NAME}"
export APP_DATA_LOG_DIR="/srv/datalog/${APP_NAME}"
export APP_CACHE_DIR="/var/cache/${APP_NAME}"
export APP_RUN_DIR="/var/run/${APP_NAME}"
export APP_LOG_DIR="/var/log/${APP_NAME}"
export APP_CERT_DIR="/srv/cert/${APP_NAME}"

export PG_DATA_DIR="${APP_DATA_DIR}/data"

export PG_CONF_FILE="${APP_CONF_DIR}/postgresql.conf"
export PG_HBA_FILE="${APP_CONF_DIR}/pg_hba.conf"
export PG_RECOVERY_FILE="${PG_DATA_DIR}/recovery.conf"
export PG_IDENT_FILE="${PG_DATA_DIR}/pg_ident.conf"
export PG_EXT_PID_FILE="${APP_RUN_DIR}/postgresql.pid"
export PG_LOG_FILE="${APP_LOG_DIR}/postgresql.log"

# 应用配置参数
export PG_CLUSTER_APP_NAME=${PG_CLUSTER_APP_NAME:-cvcluster}
export PG_REPLICATION_MODE="${PG_REPLICATION_MODE:-primary}"
export PG_PRIMARY_HOST="${PG_PRIMARY_HOST:-}"
export PG_PRIMARY_PORT="${PG_PRIMARY_PORT:-5432}"
export PG_NUM_SYNCHRONOUS_REPLICAS="${PG_NUM_SYNCHRONOUS_REPLICAS:-0}"
export PG_REPLICATION_USER="${PG_REPLICATION_USER:-}"
export PG_REPLICATION_PASSWORD="${PG_REPLICATION_PASSWORD:-}"
export PG_SYNCHRONOUS_COMMIT_MODE="${PG_SYNCHRONOUS_COMMIT_MODE:-on}"
export PG_FSYNC="${PG_FSYNC:-on}"
export PG_INIT_MAX_TIMEOUT=${PG_INIT_MAX_TIMEOUT:-60}
export PG_INITDB_ARGS="${PG_INITDB_ARGS:-}"
export PG_INITDB_WAL_DIR="${PG_INITDB_WAL_DIR:-}"
export PG_PORT_NUMBER="${PG_PORT_NUMBER:-5432}"
export PG_SHARED_PRELOAD_LIBRARIES="${PG_SHARED_PRELOAD_LIBRARIES:-}"
export PG_USERNAME_CONNECTION_LIMIT="${PG_USERNAME_CONNECTION_LIMIT:-}"
export PG_POSTGRES_CONNECTION_LIMIT="${PG_POSTGRES_CONNECTION_LIMIT:-}"

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

export PG_ENABLE_TLS="${PG_ENABLE_TLS:-no}"
export PG_TLS_CERT_FILE="${PG_TLS_CERT_FILE:-}"
export PG_TLS_KEY_FILE="${PG_TLS_KEY_FILE:-}"
export PG_TLS_CA_FILE="${PG_TLS_CA_FILE:-}"
export PG_TLS_CRL_FILE="${PG_TLS_CRL_FILE:-}"
export PG_TLS_PREFER_SERVER_CIPHERS="${PG_TLS_PREFER_SERVER_CIPHERS:-yes}"

export PG_PGAUDIT_LOG="${PG_PGAUDIT_LOG:-}"
export PG_PGAUDIT_LOG_CATALOG="${PG_PGAUDIT_LOG_CATALOG:-}"
export PG_LOG_CONNECTIONS="${PG_LOG_CONNECTIONS:-}"
export PG_LOG_DISCONNECTIONS="${PG_LOG_DISCONNECTIONS:-}"
export PG_LOG_HOSTNAME="${PG_LOG_HOSTNAME:-}"
export PG_CLIENT_MIN_MESSAGES="${PG_CLIENT_MIN_MESSAGES:-error}"
export PG_LOG_LINE_PREFIX="${PG_LOG_LINE_PREFIX:-}"
export PG_LOG_TIMEZONE="${PG_LOG_TIMEZONE:-}"

export PG_MAX_CONNECTIONS="${PG_MAX_CONNECTIONS:-}"
export PG_TCP_KEEPALIVES_IDLE="${PG_TCP_KEEPALIVES_IDLE:-}"
export PG_TCP_KEEPALIVES_INTERVAL="${PG_TCP_KEEPALIVES_INTERVAL:-}"
export PG_TCP_KEEPALIVES_COUNT="${PG_TCP_KEEPALIVES_COUNT:-}"
export PG_STATEMENT_TIMEOUT="${PG_STATEMENT_TIMEOUT:-}"

export PG_USERNAME="${PG_USERNAME:-postgres}"
export PG_PASSWORD="${PG_PASSWORD:-}"
export PG_DATABASE="${PG_DATABASE:-postgres}"
# 使用自定义用户名（非"postgres"）时的管理员密码
[[ "${PG_USERNAME}" = "postgres" ]] && PG_POSTGRES_PASSWORD="${PG_PASSWORD}"
export PG_POSTGRES_PASSWORD="${PG_POSTGRES_PASSWORD:-}"
export PG_INITSCRIPTS_USERNAME="${PG_INITSCRIPTS_USERNAME:-${PG_USERNAME}}"
export PG_INITSCRIPTS_PASSWORD="${PG_INITSCRIPTS_PASSWORD:-${PG_PASSWORD}}"

export PGCONNECT_TIMEOUT="${PGCONNECT_TIMEOUT:-10}"

# 内部变量
export PG_FIRST_BOOT="yes"

# 个性化变量

