# LNMP - Docker 多容器间协作互连

# 说明

这是一个 Docker 多容器间协作互连的例子。使用的是最常见的 LNMP 的技术栈，既 `Nginx` + `PHP` + `MySQL`。

在这个例子中，我使用的是 Docker Compose，这样比较简洁，如果使用 `docker` 命令也可以做到同样的效果，当然，过程要相对繁琐一些。

## 服务

在 `docker-compose.yml` 文件中，定义了3个**服务**，分别是 `nginx`, `php` 和 `mysql`。

```yml
services:
    nginx:
        image: nginx:latest
        ...
    php:
        build: ./php/.
        ...
    mysql:
        image: mysql:latest
        ...
```

## 镜像

其中 `nginx` 和 `mysql` 服务均直接使用的是 Docker 官方镜像。使用官方镜像并非意味着无法定制，Docker 官方提供的镜像，一般都具有一定的定制能力。

在这个例子中，`mysql` 服务就通过环境变量 `MYSQL_ROOT_PASSWORD`，设定了 MySQL 数据库初始密码为 `Passw0rd`。

```yml
    mysql:
        image: mysql:latest
        ...
        environment:
            MYSQL_ROOT_PASSWORD: Passw0rd
        ...
```

`php` 服务较为特殊，由于官方 `php` 镜像未提供连接 `mysql` 所需的插件，所以 `php` 服务无法直接使用官方镜像。在这里，正好用其作为例子，演示如何基于官方镜像，安装插件，定制自己所需的镜像。

对应的[`./php/Dockerfile`](https://coding.net/u/twang2218/p/docker-lnmp/git/blob/master/php/Dockerfile)：

```Dockerfile
FROM php:7-fpm
RUN set -xe \
# "构建依赖"
    && buildDeps=" \
        build-essential \
        php5-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng12-dev \
    " \
# "运行依赖"
    && runtimeDeps=" \
        libfreetype6 \
        libjpeg62-turbo \
        libmcrypt4 \
        libpng12-0 \
    " \
# "安装 php 以及编译构建组件所需包"
    && apt-get update \
    && apt-get install -y ${runtimeDeps} ${buildDeps} --no-install-recommends \
# "编译安装 php 组件"
    && docker-php-ext-install iconv mcrypt mysqli pdo pdo_mysql zip \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install gd \
# "清理"
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false $buildDeps \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/lib/apt/lists/*
```

Dockerfile 的书写要遵循官方的最佳实践写法，<https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/>。

编译构建的依赖在运行时不需要，因此应该在插件安装后删除，并且 `apt-get` 包管理的缓存也应当清理。

## 定制

在这个例子中，每个服务的配置文件均采用挂载宿主目录中的配置文件的形式，配置文件位于各个服务对应的目录中：

*   `nginx`：nginx 的默认站点配置文件：`./nginx/default.conf`；
*   `mysql`：mysql 的配置文件 `./mysql/mysql.cnf`；
*   `php`： PHP 配置文件 `./php/php.conf`；

修改配置文件后重新运行服务，就会加载其配置。

## 网络

在这个例子中，演示了如何使用自定义网络，并利用服务名通讯。

首先，在 `docker-compose.yml` [文件尾部](https://coding.net/u/twang2218/p/docker-lnmp/git/blob/master/docker-compose.yml#L36)，`networks` 部分定义了两个自定义网络，分别名为 `frontend`，`backend`。

```yml
networks:
    frontend:
    backend:
```

然后，在前面`services`中，每个服务下面的`networks`部分，说明这个服务要接到哪个网络上。

```yml
services:
    nginx:
        ...
        networks:
            - frontend
    php:
        ...
        networks:
            - frontend
            - backend
    mysql:
        ...
        networks:
            - backend

```

在这个例子中，

*   `nginx` 接到了名为 `frontend` 的前端网络；
*   `mysql` 接到了名为 `backend` 的后端网络；
*   而作为中间的 `php` 同时连接了 `frontend` 和 `backend` 网络上。

连接到同一个网络的容器，可以进行互连；而不同网络的容器则会被隔离。
所以在这个例子中，`nginx` 可以和 `php` 服务进行互连，`php` 也可以和 `mysql` 服务互连，因为它们连接到了同一个网络中；
而 `nginx` 和 `mysql` 并不处于同一网络，所以二者无法通讯，这起到了隔离的作用。

处于同一网络的容器，可以使用**服务名**访问对方。比如，在这个例子中的 `./site/index.php` 里，就是使用的 `mysql` 这个服务名去连接的数据库服务器。

```php
<?php
$servername = "mysql";
$username = "root";
$password = "Passw0rd";

// Create connection
$conn = new mysqli($servername, $username, $password);

// Check connection
if ($conn->connect_error) {
    die("连接错误: " . $conn->connect_error);
}
echo "<h1>成功连接 MySQL 服务器</h1>";

phpinfo();

?>
```

关于 Docker 自定义网络，可以看一下官方文档的介绍：
<https://docs.docker.com/engine/userguide/networking/dockernetworks/#/user-defined-networks>

关于在 Docker Compose 中使用自定义网络的部分，可以看官方这部分文档：
<https://docs.docker.com/compose/networking/>

## 依赖

服务的启动顺序有时候比较关键，Compose 在这里可以提供一定程度的启动控制。比如这个例子中，我是用了依赖关系 `depends_on` 来进行配置。

```yml

services:
    nginx:
        ...
        depends_on:
            - php
    php:
        ...
        depends_on:
            - mysql
    mysql:
        ...
```

在这里，`nginx` 需要使用 `php` 服务，所以这里依赖关系上设置了 `php`，而 `php` 服务则需要操作 `mysql`，所以它依赖了 `mysql`。

在 `docker-compose up -d` 的时候，会根据依赖控制服务间的启动顺序，对于这个例子，则会以 `mysql` → `php` → `nginx` 的顺序启动服务。

需要注意的是，这里的启动顺序的控制是有限度的，并非彻底等到所依赖的服务可以工作后，才会启动下一个服务。而是确定容器启动后，则开始启动下一个服务。因此，这里的顺序控制可能依旧会导致某项服务启动时，它所依赖的服务并未准备好。比如 `php` 启动后，有可能会出现 `mysql` 服务的数据库尚未初始化完。对于某些应用来说，这个控制，依旧可能导致报错说无法连接所需服务。

如果需要应用级别的服务依赖等待，需要在 `entrypoint.sh` 这类脚本中，加入服务等待的部分。而且，也可以通过 `restart: always` 这种设置，让应用启动过程中，如果依赖服务为准备好，而报错退出后，有再一次尝试的机会。

# 操作

## 启动

```bash
docker-compose up -d
```

## 访问服务

`nginx` 将会守候 `80` 端口，

*   如果使用的 Linux 或者 `Docker for Mac`，可以直接在本机访问 <http://localhost>
*   如果是使用 `Docker Toolbox` 的话，则应该使用虚拟机地址，如 <http://192.168.99.100>，具体虚拟机地址查询使用命令 `docker-machine ip default`。

## 停止服务

```bash
docker-compose down
```
