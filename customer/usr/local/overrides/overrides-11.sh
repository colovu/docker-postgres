#!/bin/bash -e

POSTGRESQL_CONF="${APP_DEF_DIR}/${APP_VERSION}/main/postgresql.conf"

# 在安装完应用后，使用该脚本修改默认配置文件中部分配置项
# 如果相应的配置项已经定义整体环境变量，则不需要在这里修改
echo "Process overrides for default configs..."
#sed -i -E 's/^listeners=/d' "$KAFKA_HOME/config/server.properties"

# 设置默认监听地址为 localhost ，防止初始化操作期间外部链接，在容器初始化完成后修改为监听所有地址
sed -i -E "s/^#listen_addresses .*/listen_addresses = \'localhost\'/g" ${POSTGRESQL_CONF}

sed -i -E "s/^data_directory .*/data_directory = \'\/srv\/data\/postgresql\/${APP_VERSION}\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^hba_file .*/hba_file = \'\/srv\/conf\/postgresql\/${APP_VERSION}\/main\/pg_hba.conf\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^ident_file .*/ident_file = \'\/srv\/conf\/postgresql\/${APP_VERSION}\/main\/pg_ident.conf\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#external_pid_file .*/external_pid_file = \'\/var\/run\/postgresql\/postgresql.pid\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^max_connections .*/max_connections = 2000/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#password_encryption .*/password_encryption = md5/g" ${POSTGRESQL_CONF}

sed -i -E "s/^#log_destination .*/log_destination = \'stderr\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#logging_collector .*/logging_collector = on/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#log_directory .*/log_directory = \'\/var\/log\/postgresql\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#log_filename .*/log_filename = \'postgresql-\%Y-\%m-\%d_\%H\%M\%S.log\'/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#log_truncate_on_rotation .*/log_truncate_on_rotation = on/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#log_rotation_age .*/log_rotation_age = 1d/g" ${POSTGRESQL_CONF}
sed -i -E "s/^#log_rotation_size .*/log_rotation_size = 0/g" ${POSTGRESQL_CONF}
sed -i -E "s/^log_timezone .*/log_timezone = \'Asia\/Shanghai\'/g" ${POSTGRESQL_CONF}

sed -i -E "s/^#include_dir .*/include_dir = \'conf\.d\'/g" ${POSTGRESQL_CONF}
