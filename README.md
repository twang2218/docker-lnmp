# LNMP - Docker 多容器间协作互连

# 说明

这是一个 Docker 多容器间协作互连的例子。使用的是最常见的 LNMP 的技术栈，既 `Nginx` + `PHP` + `MySQL`。

在这个例子中，我使用的是 Docker Compose，这样比较简洁，如果使用 `docker` 命令也可以做到同样的效果，当然，过程要相对繁琐一些。

## 服务

在 `docker-compose.yml` 文件中，定义了3个**服务**，分别是 `nginx`, `php` 和 `mysql`。

```yml
services:
    nginx:
        build:
            context: ./web
            dockerfile: Dockerfile.nginx
        ...
    php:
        build:
            context: ./web
            dockerfile: Dockerfile.php
        ...
    mysql:
        image: mysql:5.7
        ...
```

## 镜像

### mysql 服务镜像

`mysql` 服务均直接使用的是 Docker 官方镜像。使用官方镜像并非意味着无法定制，Docker 官方提供的镜像，一般都具有一定的定制能力。

```yml
    mysql:
        image: mysql:5.7
        ...
        environment:
            TZ: 'Asia/Shanghai'
            MYSQL_ROOT_PASSWORD: Passw0rd
        command: ['mysqld', '--default-time-zone=Asia/Shanghai']
        ...
```

在这个例子中，`mysql` 服务就通过环境变量 `MYSQL_ROOT_PASSWORD`，设定了 MySQL 数据库初始密码为 `Passw0rd`，并且通过 `TZ` 环境变量指定了国内时区。

并且，我重新指定了启动容器的命令，在 `command` 中，添加了额外的参数。`--default-time-zone=Asia/Shanghai`。

### nginx 服务镜像

`nginx` 官方镜像基本满足需求，但是我们需要添加默认网站的配置文件、以及网站页面目录。

```Dockerfile
FROM nginx:1.11
ENV TZ=Asia/Shanghai
COPY ./nginx.conf /etc/nginx/conf.d/default.conf
COPY ./site /usr/share/nginx/html
```

镜像定制很简单，就是指定时区后，将配置文件、网站页面目录复制到指定位置。

### php 服务镜像

`php` 服务较为特殊，由于官方 `php` 镜像未提供连接 `mysql` 所需的插件，所以 `php` 服务无法直接使用官方镜像。在这里，正好用其作为例子，演示如何基于官方镜像，安装插件，定制自己所需的镜像。

对应的[`./web/Dockerfile.php`](https://coding.net/u/twang2218/p/docker-lnmp/git/blob/master/web/Dockerfile.php)：

```Dockerfile
FROM php:7-fpm

ENV TZ=Asia/Shanghai

COPY sources.list /etc/apt/sources.list

RUN set -xe \
    && echo "构建依赖" \
    && buildDeps=" \
        build-essential \
        php5-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng12-dev \
    " \
    && echo "运行依赖" \
    && runtimeDeps=" \
        libfreetype6 \
        libjpeg62-turbo \
        libmcrypt4 \
        libpng12-0 \
    " \
    && echo "安装 php 以及编译构建组件所需包" \
    && apt-get update \
    && apt-get install -y ${runtimeDeps} ${buildDeps} --no-install-recommends \
    && echo "编译安装 php 组件" \
    && docker-php-ext-install iconv mcrypt mysqli pdo pdo_mysql zip \
    && docker-php-ext-configure gd \
        --with-freetype-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install gd \
    && echo "清理" \
    && apt-get purge -y --auto-remove \
        -o APT::AutoRemove::RecommendsImportant=false \
        -o APT::AutoRemove::SuggestsImportant=false \
        $buildDeps \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/lib/apt/lists/*

COPY ./php.conf /usr/local/etc/php/conf.d/php.conf
COPY ./site /usr/share/nginx/html
```

前面几行很简单，指定了基础镜像为 [`php:7-fpm`](https://hub.docker.com/_/php/)，并且设定时区为中国时区，然后用[网易的 Debian 源](http://mirrors.163.com/.help/debian.html)替代默认的源，避免伟大的墙影响普通的包下载。接下来的那一个很多行的 `RUN` 需要特别的说一下。

初学 Docker，不少人会误以为 `Dockerfile` 等同于 Shell 脚本，于是错误的用了很多个 `RUN`，每个 `RUN` 对应一个命令。这是错误用法，会导致最终镜像极为臃肿。`Dockerfile` 是镜像定制文件，其中每一个命令都是在定义这一层该如何改变，因此应该[遵循最佳实践](https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/)，将同一类的东西写入一层，并且在结束时清理任何无关的文件。

这一层的目的是安装、构建 PHP 插件，因此真正所需要的是构建好的插件、以及插件运行所需要的依赖库，其它任何多余的文件都不应该存在。所以，在这里可以看到，依赖部分划分为了“构建依赖”以及“运行依赖”，这样在安装后，可以把不再需要的“构建依赖”删除掉，避免因为构建而导致这层多了一些不需要的文件。

这里使用的是官方 `php` 镜像中所带的 `docker-php-ext-install` 来安装 php 的插件，并且在需要时，使用 `docker-php-ext-configure` 来配置构建参数。这两个脚本是官方镜像中为了帮助镜像定制所提供的，很多官方镜像都有这类为镜像定制特意制作的脚本或者程序。这也是官方镜像易于扩展复用的原因之一，他们在尽可能的帮助使用、定制镜像。

更多关于如何定制镜像的信息可以从 Docker Hub 官方镜像的文档中看到：<https://hub.docker.com/_/mysql/>

最后的清理过程中，可以看到除了清除“构建依赖”、以及相关无用软件外，还彻底清空了 `apt` 的缓存。任何不需要的东西，都应该清理掉，确保这一层构建完毕后，仅剩所需的文件。

在 `Dockerfile` 的最后，复制配置文件和网页目录到指定位置。

## 网络

在这个例子中，演示了如何使用自定义网络，并利用服务名通讯。

首先，在 `docker-compose.yml` 文件尾部，全局 `networks` 部分定义了两个自定义网络，分别名为 `frontend`，`backend`。

```yml
networks:
    frontend:
    backend:
```

每个自定义网络都可以配置很多东西，包括网络所使用的驱动、网络地址范围等设置。但是，你可能会注意到这里 `frontend`、`backend` 后面是空的，这是指一切都使用默认，换句话说，在单机环境中，将意味着使用 `bridge` 驱动；而在 Swarm 环境中，使用 `overlay` 驱动，而且地址范围完全交给 Docker 引擎决定。

然后，在前面`services`中，每个服务下面的也有一个 `networks` 部分，这部分是用于定义这个服务要连接到哪些网络上。

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

## 存储

在这三个服务中，`nginx` 和 `php` 都是无状态服务，它们都不需要本地存储。但是，`mysql` 是数据库，需要存储动态数据文件。我们知道 Docker 是要求容器存储层里不放状态，所有的状态（也就是动态的数据）的持久化都应该使用卷，在这里就是使用命名卷保存数据的。

```yaml
volumes:
    mysql-data:
```

在 `docker-compose.yml` 文件的后面，有一个全局的 `volumes` 配置部分，用于定义的是命名卷，这里我们定义了一个名为 `mysql-data` 的命名卷。这里卷的定义后还可以加一些卷的参数，比如卷驱动、卷的一些配置，而这里省略，意味着都使用默认值。也就是说使用 `local` 也就是最简单的本地卷驱动，将来建立的命名卷可能会位于 `/var/lib/docker/volumes` 下，不过不需要、也不应该直接去这个位置访问其内容。

在 `mysql` 服务的部分，同样有一个 `volumes` 配置，这里配置的是容器运行时需要挂载什么卷、或绑定宿主的目录。在这里，我们使用了之前定义的命名卷 `mysql-data`，挂载到容器的 `/var/lib/mysql`。

```yaml
mysql:
    image: mysql:5.7
    volumes:
        - mysql-data:/var/lib/mysql
...
```

# 操作

## 启动

```bash
docker-compose up -d
```

*如果构建过程中，发现镜像下载极为缓慢、甚至失败。这是伟大的墙在捣乱。你需要去配置加速器，具体文章可以参看我的 [Docker 问答录](http://blog.lab99.org/post/docker-2016-07-14-faq.html#docker-pull-hao-man-a-zen-me-ban)。*

## 查看服务状态

```bash
docker-compose ps
```

## 查看服务日志

```bash
docker-compose logs
```

## 访问服务

`nginx` 将会守候 `80` 端口，

* 如果使用的 Linux 或者 `Docker for Mac`，可以直接在本机访问 <http://localhost>
* 如果是使用 `Docker Toolbox` 的话，则应该使用虚拟机地址，如 <http://192.168.99.100>，具体虚拟机地址查询使用命令 `docker-machine ip default`。
* 如果是自己安装的 Ubuntu、CentOS 类的虚拟机，直接进虚拟机查看地址。

## 停止服务

```bash
docker-compose down
```
