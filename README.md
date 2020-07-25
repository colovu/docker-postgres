# 简介

针对 PostgreSQL 应用的 Docker 镜像，用于提供 PostgreSQL 服务。

详细信息可参照官网：https://www.postgresql.org/

**版本信息：**

- 11
- 10、10.13.0、latest

**镜像信息：**

* 镜像地址：colovu/postgres:latest
  * 依赖镜像：colovu/ubuntu:latest

**使用 Docker Compose 运行应用**

可以使用 Git 仓库中的默认`docker-compose.yml`，快速启动应用进行测试：

```shell
$ curl -sSL https://raw.githubusercontent.com/colovu/docker-postgres/master/docker-compose.yml > docker-compose.yml

$ docker-compose up -d
```



## 默认对外声明

### 端口

- 5432：PostgreSQL 业务客户端访问端口

### 数据卷

镜像默认提供以下数据卷定义：

```shell
/var/log			# 日志输出，应用日志输出，非数据日志输出
/srv/conf			# 配置文件
/srv/data			# 数据文件
/srv/datalog	# 数据操作日志文件
/var/run			# 运行时文件
```

如果需要持久化存储相应数据，需要在宿主机建立本地目录，并在使用镜像初始化容器时进行数据卷映射。

举例：

- 使用宿主机`/host/dir/to/conf`存储配置文件
- 使用宿主机`/host/dir/to/data`存储数据文件
- 使用宿主机`/host/dir/to/log`存储日志文件

创建以上相应的宿主机目录后，容器启动命令中对应的数据卷映射参数类似如下：

```shell
-v /host/dir/to/conf:/srv/conf -v /host/dir/to/data:/srv/data -v /host/dir/to/log:/var/log
```

使用 Docker Compose 时配置文件类似如下：

```yaml
services:
  postgresql:
  ...
    volumes:
      - /host/dir/to/conf:/srv/conf
      - /host/dir/to/data:/srv/data
      - /host/dir/to/log:/var/log
  ...
```

> 注意：应用需要使用的子目录会自动创建。



## 使用说明

### 启动容器

#### 通过默认方式启动

```shell
$ docker run --name some-postgres -e POSTGRES_PASSWORD=mysecretpassword -d colovu/postgres:latest
```

- 由容器执行默认的`entrypoint.sh`脚本，并生成默认的用户及数据文件
- `some-postgres`：容器名；命名后，可以直接使用该名字进行操作
- `mysecretpassword`：数据库密码



#### 通过`psql`命令方式启动

```shell
$ docker run -it --rm --network some-network colovu/postgres:latest psql -h some-postgres -U postgres
psql (10.12.0)
Type "help" for help.

postgres=# SELECT 1;
 ?column? 
----------
        1
(1 row)
```



#### 通过`docker-compose`方式启动

docker-cpmpose.yml 参考:

```yaml
# 使用 postgres/example 作为用户名/密码

version: '3.1'

services:

  db:
    image: colovu/postgres:latest
    restart: always
    environment:
      POSTGRES_PASSWORD: example

  adminer:
    image: adminer
    restart: always
    ports:
      - 8080:8080
```



## 镜像扩展使用

有多种方式可以扩展使用`postgres`镜像；这里仅列举部分，在实际使用时，不一定需要全部使用。

### 环境变量

PostgreSQL镜像定义了许多环境变量，但并不是所有都必须使用的；如果需要定制化启动镜像，可以选择需要的环境变量进行设置。

> 注意：部分环境变量仅在初始化时起作用。针对已经存在数据目录的情况，环境变量会被跳过。

#### POSTGRES_PASSWORD

该环境变量需要在启动镜像时使用。该环境变量定义了使用PostgreSQL时，超级用户对应的密码，不应当为空。默认的超级用户由环境变量`POSTGRES_USER`定义.

> 注意：
>
> - PostgreSQL镜像配置`localhost`为默认的`trust`认证方式，在同一容器内链接数据库时，可以不使用密码。但通过不同的`主机/容器`链接时，需要密码。
> - 在使用PostgreSQL镜像创建容器时，通过`initdb脚本`在启动时定义该变量对应的值。但该值不影响尽在`psql`方式启动时设置的`PGPASSWORD`环境变量。`PGPASSWORD`环境变量在设置时仅作为一个独立的环境变量设置。

#### POSTGRES_USER

该可选环境环境变量与`POSTGRES_PASSWORD`环境变量一起使用，以在使用镜像创建容器时设置用户名和密码。使用该变量时，会创建用户对应的超级权限及同名数据库。如果该变量没有设置，默认使用用户`postgres`。

> 注意：即使使用了该变量，在初始化时，系统信息仍然会提示`The files belonging to this database system will be owned by user "postgres"`；这是因为在容器初始化时，是以Linux系统用户（镜像中`/etc/passwd`定义）`postgres`来运行的守护进程。

#### POSTGRES_DB

该可选环境变量在使用镜像创建容器时，定义一个不与默认的`POSTGRES_USER`同名的数据库。如果在创建容器时没有使用该变量，则创建`POSTGRES_USER`对应的同名数据库。

#### POSTGRES_INITDB_ARGS

该可选环境变量在使用镜像创建容器时，传递参数给`postgres initdb`。传递的参数是一个使用空格分隔的字符串。例如增加页校验码：`-e POSTGRES_INITDB_ARGS="--data-checksums"`。

#### POSTGRES_INITDB_WALDIR

该可选环境变量在使用镜像创建容器时，定义一个单独的PostgreSQL事务处理日志存储目录。相关的日志默认存储在PostgreSQL的数据存储目录(`PGDATA`)子目录中。部分情况下，用户可以定义该存储目录在不同的存储设备上，以提升性能或稳定性。

#### POSTGRES_HOST_AUTH_METHOD

该可选环境变量在使用镜像创建容器时，定义至服务器的`auth-method`，该定义针对所有数据库、用户、链接地址起作用。未定义该参数时，使用默认值`md5`密码认证方式。

对于一个未初始化的数据库，可以修改`pg_hba.conf`文件，增加以下命令行进行预定义：

```shell
echo "host all all all $POSTGRES_HOST_AUTH_METHOD" >> pg_hba.conf
```

或：

```shell
echo "host all all 0.0.0.0/0 $POSTGRES_HOST_AUTH_METHOD" >> pg_hba.conf
```

详细说明可参考官方针对[`pg_hba.conf`](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)文档的介绍。

> 注意：
>
> - 不建议使用[`trust`](https://www.postgresql.org/docs/current/auth-trust.html)方式；该方式允许任意用户不使用密码连接数据库，即使部分用户设置了密码（如通过`POSTGRES_PASSWORD`）。更多介绍可参考[*Trust Authentication*](https://www.postgresql.org/docs/current/auth-trust.html)。
> - 如果设置了`POSTGRES_HOST_AUTH_METHOD`为`trust`，那么`POSTGRES_PASSWORD`就不在需要，也不再起作用了。

#### PGDATA

该可选环境变量在使用镜像创建容器时，定义一个单独的PostgreSQL数据库存储目录。未定义该参数时，使用默认的`/var/lib/postgresql/data`目录。

如果使用的数据卷为文件系统挂载点（GCE persistent disks）或远程目录（NFS mounts），这些目录无法被更改所属用户为`postgres`，针对这种情况建议配置子目录以存储数据。例如:

```shell
$ docker run -d \
    --name some-postgres \
    -e POSTGRES_PASSWORD=mysecretpassword \
    -e PGDATA=/var/lib/postgresql/data/pgdata \
    -v /custom/mount:/var/lib/postgresql/data \
    colovu/postgres:latest
```

该变量并不是为Docker定义的数据卷，而是由`postgres`服务本身使用（参考 [PostgreSQL docs](https://www.postgresql.org/docs/11/app-postgres.html#id-1.9.5.14.7)），entrypoing.sh脚本只是传输该值。



### 容器安全

作为敏感信息通过环境变量传输的可选替代方案，可以增加`_FILE`在部分环境变量末尾，以使容器的初始化脚本通过加载文件的方式，获取相关变量。例如，可以通过加载文件的方式加载密码：

```shell
$ docker run --name some-postgres -e POSTGRES_PASSWORD_FILE=/run/secrets/postgres-passwd -d colovu/postgres:latest
```

支持该方式的变量为： `POSTGRES_INITDB_ARGS`, `POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`。



### 初始化脚本

如果需要在使用当前镜像时，增加一些附加的初始化操作，可以将相应的`*.sql`、 `*.sql.gz` 或 `*.sh`脚本文件放置在`initdb.d`目录中（使用数据卷映射方式时，可先创建相应的目录）。在`entrypoint.sh`调用`initdb`创建默认的`postgres`用户及数据库时，会执行所有在`initdb.d`目录下的`*.sql`及可执行`*.sh`脚本，并source所有不可执行的`*.sh`脚本，执行完成后，启动postgres服务。

> 注意：
>
> - 在`initdb.d`目录下的脚本，仅在数据库存储目录为空时才会执行。如果部分脚本执行失败（会导致容器退出），则可能数据库目录已经存在；此时，重新启动容器，则不会继续执行`initdb.d`目录下的初始化脚本。



### 数据库配置

有多种方式可以配置PostgreSQL服务器。详细信息可参考相关[docs](https://www.postgresql.org/docs/current/static/runtime-config.html)文档。部分常用配置项如下：

- 使用自定义的配置文件。可将容器内的模板配置文件 `/usr/share/postgresql/postgresql.conf.sample`导出后修改，并重新映射以启动容器。 

  ```shell
  $ # 获取配置文件模板，存储为当前目录的my-postgres.conf
  $ docker run -i --rm colovu/postgres:latest cat /usr/share/postgresql/postgresql.conf.sample > my-postgres.conf
  
  $ # 个性化修改配置信息，至少增加`listen_addresses='*'`以确保其他容器可以访问
  $ echo "listen_addresses='*'" >> my-postgres.conf
  
  $ # 使用定制后的配置文件启动容器
  $ docker run -d --name some-postgres -v "$PWD/my-postgres.conf":/etc/postgresql/postgresql.conf -e POSTGRES_PASSWORD=mysecretpassword colovu/postgres:latest -c 'config_file=/etc/postgresql/postgresql.conf'
  ```

- 在命令行中设置相应参数。entrypoint.sh基本会将所有的启动时传递给Docker的配置参数传递给postgres服务进程。从官方 [docs](https://www.postgresql.org/docs/current/static/app-postgres.html)文档可以看出，所有在 `.conf`文件中的配置项都可以使用`-c`进行设置。

  ```shell
  $ docker run -d --name some-postgres -e POSTGRES_PASSWORD=mysecretpassword colovu/postgres:latest -c 'shared_buffers=256MB' -c 'max_connections=200'
  ```

> 注意：配置文件至少修改`listen_addresses='*'`以确保其他容器可以访问

配置文件模板：

- 基于Linux系列的镜像，默认配置文件在容器内为：`/usr/share/postgresql/postgresql.conf.sample`
- 基于Alpine系统的镜像，默认配置文件在容器内为：`/usr/local/share/postgresql/postgresql.conf.sample`



导出模板文件：

```shell
docker run -i --rm colovu/postgres:latest cat /usr/share/postgresql/postgresql.conf.sample > my-postgres.conf
```

- 使用的镜像：colovu/postgres-ubuntu:v10.12
- 原始文件：/usr/share/postgresql/postgresql.conf.sample
- 导出后文件：my-postgres.conf



### 个性化配置Locale

PostgreSQL镜像使用的Ubuntu基础镜像默认的Locale配置为`en_US.UTF-8`，可以使用一个简单的 Dockerfile来设置为不同的Locale。比如设置为 `de_DE.utf8`:

```dockerfile
FROM colovu/postgres:latest
RUN localedef -i de_DE -c -f UTF-8 -A /usr/share/locale/locale.alias de_DE.UTF-8
ENV LANG de_DE.utf8
```

因为数据库仅在容器启动时创建，使用这种方式，可以在创建数据库前设置默认语言。



### 扩展功能模块

使用默认的镜像时，安装扩展功能模块比较简单，可以参考文档 [github.com/postgis/docker-postgis](https://github.com/postgis/docker-postgis/blob/4eb614133d6aa87bfc5c952d24b7eb1f499e5c7c/12-3.0/Dockerfile) 。

使用基于Alpine的镜像时，没有在 [postgres-contrib](https://www.postgresql.org/docs/10/static/contrib.html) 列明的模块需要自己在镜像中编译，参见文档  [github.com/postgis/docker-postgis](https://github.com/postgis/docker-postgis/blob/4eb614133d6aa87bfc5c952d24b7eb1f499e5c7c/12-3.0/alpine/Dockerfile) 。



## 变参 --user 说明

本镜像允许使用变参`--user`指定运行时的用户信息。但需要注意的是，`postgres`可以允许使用任何UID执行（只需要与数据库目录所属账户一致），`initdb`需要确保该UID实际存在（指定的用户需要在容器的`/etc/passwd`文件中存在）：

```shell
$ docker run -it --rm --user www-data -e POSTGRES_PASSWORD=mysecretpassword colovu/postgres:latest
The files belonging to this database system will be owned by user "www-data".
...

$ docker run -it --rm --user 1000:1000 -e POSTGRES_PASSWORD=mysecretpassword colovu/postgres:latest
initdb: could not look up effective user ID 1000: user does not exist
```

针对类似问题，有三种解决方案：

1. 使用Linux系列镜像（Centos/Debian/Ubuntu/Redhat等），类似镜像允许使用 [ `nss_wrapper` 库](https://cwrap.org/nss_wrapper.html) 将系统`/etc/passwd`包含的用户伪装为容器内用户。但Alpine系列镜像不允许。

2. 如果宿主系统存在相应的用户，可以使用只读绑定将`/etc/passwd`文件映射为容器内对应文件：

   ```shell
   $ docker run -it --rm --user "$(id -u):$(id -g)" -v /etc/passwd:/etc/passwd:ro -e POSTGRES_PASSWORD=mysecretpassword colovu/postgres:latest
   The files belonging to this database system will be owned by user "jsmith".
   ...
   ```

3. 单独初始化相应的数据库存储目录，并使用`chown`命令更改所属用户：

   ```shell
   $ docker volume create pgdata
   $ docker run -it --rm -v pgdata:/var/lib/postgresql/data -e POSTGRES_PASSWORD=mysecretpassword colovu/postgres:latest
   The files belonging to this database system will be owned by user "postgres".
   ...
   ( once it's finished initializing successfully and is waiting for connections, stop it )
   
   $ docker run -it --rm -v pgdata:/var/lib/postgresql/data colovu/postgres:latest bash chown -R 1000:1000 /var/lib/postgresql/data
   
   $ docker run -it --rm --user 1000:1000 -v pgdata:/var/lib/postgresql/data colovu/postgres:latest
   LOG:  database system was shut down at 2017-01-20 00:03:23 UTC
   LOG:  MultiXact member wraparound protections are now enabled
   LOG:  autovacuum launcher started
   LOG:  database system is ready to accept connections
   ```



## 使用预警

如果不存在数据库，容器启动时，会花费一定时间创建默认的数据库，在创建期间，容器不接受访问链接。如果使用`docker-compose`方式同时启动多个容器时，可能会产生问题。

容器默认的`/dev/shm` 大小为`64MB`。如果在容器运行过程中共享内存不足，可能会遇到错误``。针对这种情况，可以通过在启动容器时传递类似参数 [--shm-size=256MB ](https://docs.docker.com/engine/reference/run/#runtime-constraints-on-resources) 进行调整。

在Swarm模式中使用overlay网络模式时，针对长时间运行的IDLE链接，可能会遇到`IPVS connection timeouts`错误，可以参照以下信息解决： ["IPVS connection timeout issue" in the Docker Success Center](https://success.docker.com/article/ipvs-connection-timeout-issue) 。



## 如何存储数据

**重要**：针对运行在Docker容器中的应用，有几种不同的数据存储方式。如：

- 让Docker本身管理存储的数据（在容器内）。这是一种简单，也是默认的存储方式。这种方式存在的问题是：在宿主机上很难使用工具对存储的数据定位及处理。
- 在宿主机上创建数据存储目录（在容器外）。使用这种方式，可以比较容易的在宿主机上使用工具对数据文件进行分析及处理。这种方式存在的问题是：使用镜像的用户需要保证相关目录的存在和权限的正确性。

详细说明，可参考Docker的相关文档或讨论区。简单举例使用方式：

1. 在宿主机上合适位置创建数据存储目录，如：`/absolute/host/datadir`.

2. 启动容器：

   ```shell
   $ docker run --name <instance-name> -v /absolute/host/datadir:/container/volume/dir -d image-name:tag
   ```

其中，`-v /absolute/host/datadir:/container/volume/dir`参数部分，会将宿主机的`/absolute/host/datadir`目录挂载为容器中的`/var/lib/postgresql/data`目录。



## 参考

- [官方Docker](https://hub.docker.com/_/postgres?tab=description)
- [官方介绍](http://www.postgresql.org/docs/9.5/interactive/app-initdb.html)
- [官方中文手册](http://www.postgres.cn/v2/document)

----

本文原始来源 [Endial Fang](https://github.com/colovu) @ [Github.com](https://github.com)

