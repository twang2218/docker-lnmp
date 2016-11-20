# LNMP - Docker 多容器间协作互连

# 说明

这是一个 Docker 多容器间协作互连的例子。使用的是最常见的 LNMP 的技术栈，既 `Nginx` + `PHP` + `MySQL`。

在这个例子中，我使用的是 Docker Compose，这样比较简洁，如果使用 `docker` 命令也可以做到同样的效果，当然，过程要相对繁琐一些。

## 服务

在 `docker-compose.yml` 文件中，定义了3个**服务**，分别是 `nginx`, `php` 和 `mysql`。

```yml
services:
    nginx:
        image: "${DOCKER_USER}/lnmp-nginx:v1.2"
        build:
            context: .
            dockerfile: Dockerfile.nginx
        ...
    php:
        image: "${DOCKER_USER}/lnmp-php:v1.2"
        build:
            context: .
            dockerfile: Dockerfile.php
        ...
    mysql:
        image: mysql:5.7
        ...
```

其中 `mysql` 服务中的 `image: mysql:5.7` 是表明使用的是 `mysql:5.7` 这个镜像。而 `nginx` 和 `php` 服务中的 `image` 含义更为复杂。一方面是说，要使用其中名字的镜像，另一方面，如果这个镜像不存在，则利用其下方指定的 `build` 指令进行构建。在单机环境，这里的 `image` 并非必须，只保留 `build` 就可以。但是在 Swarm 环境中，需要集群中全体主机使用同一个镜像，每个机器自己构建就不合适了，指定了 `image` 后，就可以在单机 `build` 并 `push` 到 registry，然后在集群中执行 `up` 的时候，才可以自动从 registry 下载所需镜像。

这里的镜像名看起来也有些不同：

```bash
image: "${DOCKER_USER}/lnmp-nginx:v1.2"
```

其中的 `${DOCKER_USER}` 这种用法是环境变量替换，当存在环境变量 `DOCKER_USER` 时，将会用其值替换 `${DOCKER_USER}`。而环境变量从哪里来呢？除了在 Shell 中 `export` 对应的环境变量外，Docker Compose 还支持一个默认的环境变量文件，既 `.env` 文件。你可以在项目中看到，`docker-compose.yml` 的同级目录下，存在一个 `.env` 文件，里面定义了环境变量。

```bash
DOCKER_USER=twang2218
```

每次执行 `docker-compose` 命令的时候，这个 `.env` 文件就会自动被加载，所以是一个用来定制 compose 文件非常方便的地方。这里我只定义了一个环境变量 `DOCKER_USER`，当然，可以继续一行一个定义更多的环境变量。

初次之外，还可以明确指定环境变量文件。具体的配置请查看 [`docker-compose` 官方文档](https://docs.docker.com/compose/compose-file/#envfile)。

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
        command: ['mysqld', '--character-set-server=utf8']
        ...
```

在这个例子中，`mysql` 服务就通过环境变量 `MYSQL_ROOT_PASSWORD`，设定了 MySQL 数据库初始密码为 `Passw0rd`，并且通过 `TZ` 环境变量指定了国内时区。

并且，我重新指定了启动容器的命令，在 `command` 中，添加了额外的参数。`--character-set-server=utf8`，指定了默认字符集。

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

对应的[`Dockerfile.php`](https://coding.net/u/twang2218/p/docker-lnmp/git/blob/master/Dockerfile.php)：

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
// 建立连接
$conn = mysqli_connect("mysql", "root", $_ENV["MYSQL_PASSWORD"]);
...
?>
```

可以注意到，在这段数据库连接的代码里，数据库密码是通过环境变量，`$_ENV["MYSQL_PASSWORD"]`，读取的，因此密码并非写死于代码中。在运行时，可以通过环境变量将实际环境的密码传入容器。在这个例子里，就是在 `docker-compose.yml` 文件中指定的环境变量：

```yml
version: '2'
services:
...
    php:
...
        environment:
            MYSQL_PASSWORD: Passw0rd
...
```

关于 Docker 自定义网络，可以看一下官方文档的介绍：
<https://docs.docker.com/engine/userguide/networking/dockernetworks/#/user-defined-networks>

关于在 Docker Compose 中使用自定义网络的部分，可以看官方这部分文档：
<https://docs.docker.com/compose/networking/>

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

# 单机操作

## 启动

```bash
docker-compose up -d
```

*如果构建过程中，发现镜像下载极为缓慢、甚至失败。这是伟大的墙在捣乱。你需要去配置加速器，具体文章可以参看我的 [Docker 问答录](http://blog.lab99.org/post/docker-2016-07-14-faq.html#docker-pull-hao-man-a-zen-me-ban)。*

如果修改了配置文件，可能需要明确重新构建，可以使用命令 `docker-compose build`。

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

如果访问后，看到了 `成功连接 MySQL 服务器` 就说明数据库连接正常。



## 停止服务

```bash
docker-compose down
```

# Swarm 集群编排

在单机环境中使用容器，可能经常会用到绑定宿主目录的情况，这在开发时很方便。但是在集群环境中部署应用的时候，挂载宿主目录就变得非常不方便了。

在集群环境中，Swarm 可能会调度容器运行于任何一台主机上，如果一个主机失败后，可能还会再次调度到别的主机上，确保服务可以继续。在这种情况下，如果使用绑定宿主目录的形式，就必须同时在所有主机上的相同位置，事先准备好其内容，并且要保持同步。这并不是一个好的解决方案。

因此为了在集群环境中部署方便，比较好的做法是，将应用代码、配置文件等直接放入镜像。就如同这个例子中我们看到的 `nginx`、`php` 服务的镜像一样，在使用 `Dockerfile` 定制的过程中，将配置和应用代码放入镜像。

`nginx` 的服务镜像 `Dockerfile`

```Dockerfile
...
COPY ./nginx.conf /etc/nginx/conf.d/default.conf
COPY ./site /usr/share/nginx/html
```

`php` 的服务镜像 `Dockerfile`

```Dockerfile
...
COPY ./php.conf /usr/local/etc/php/conf.d/php.conf
COPY ./site /usr/share/nginx/html
```

Docker Swarm 目前分为两代。第一代是以容器形式运行，被称为 Docker Swarm；而第二代是自 `1.12` 以后以 `SwarmKit` 为基础集成进 `docker` 的 Swarm，被称为 Docker Swarm Mode。

## 一代 Swarm

[一代 Swarm](https://docs.docker.com/swarm/) 是 Docker 团队最早的集群编排的尝试，以容器形式运行，需要外置键值库（如 etcd, consul, zookeeper），需要手动配置 `overlay` 网络。其配置比 `kubernetes` 要简单，但是相比后面的第二代来说还是稍显复杂。

这里提供了一个脚本，`run1.sh`，用于建立一代 Swarm，以及启动服务、横向扩展。

### 建立 swarm 集群

在安装有 `docker-machine` 以及 VirtualBox 的虚拟机上（比如装有 Docker Toolbox 的Mac/Windows），使用 `run1.sh` 脚本即可创建集群：

```bash
./run1.sh create
```

### 启动

```bash
./run1.sh up
```

### 横向扩展

```bash
./run1.sh scale 3 5
```

这里第一个参数是 nginx 容器的数量，第二个参数是 php 容器的数量。

### 访问服务

`nginx` 将会守候 80 端口。利用 `docker ps` 可以查看具体集群哪个节点在跑 nginx 以及 IP 地址。如

```bash
$ eval $(./run1.sh env)
$ docker ps
CONTAINER ID        IMAGE                       COMMAND                  CREATED             STATUS              PORTS                                NAMES
d85a2c26dd7d        twang2218/lnmp-php:v1.2     "php-fpm"                9 minutes ago       Up 9 minutes        9000/tcp                             node1/dockerlnmp_php_5
c81e169c164d        twang2218/lnmp-php:v1.2     "php-fpm"                9 minutes ago       Up 9 minutes        9000/tcp                             node1/dockerlnmp_php_2
b43de77c9340        twang2218/lnmp-php:v1.2     "php-fpm"                9 minutes ago       Up 9 minutes        9000/tcp                             master/dockerlnmp_php_4
fdcb718b6183        twang2218/lnmp-php:v1.2     "php-fpm"                9 minutes ago       Up 9 minutes        9000/tcp                             node3/dockerlnmp_php_3
764b10b17dc4        twang2218/lnmp-nginx:v1.2   "nginx -g 'daemon off"   9 minutes ago       Up 9 minutes        192.168.99.104:80->80/tcp, 443/tcp   master/dockerlnmp_nginx_3
e92b34f998bf        twang2218/lnmp-nginx:v1.2   "nginx -g 'daemon off"   9 minutes ago       Up 9 minutes        192.168.99.106:80->80/tcp, 443/tcp   node2/dockerlnmp_nginx_2
077ee73c8148        twang2218/lnmp-nginx:v1.2   "nginx -g 'daemon off"   22 minutes ago      Up 22 minutes       192.168.99.105:80->80/tcp, 443/tcp   node3/dockerlnmp_nginx_1
1931249a66c1        e8920543aee8                "php-fpm"                22 minutes ago      Up 22 minutes       9000/tcp                             node2/dockerlnmp_php_1
cf71bca309dd        mysql:5.7                   "docker-entrypoint.sh"   22 minutes ago      Up 22 minutes       3306/tcp                             node1/dockerlnmp_mysql_1
```

如这种情况，就可以使用 <http://192.168.99.104>, <http://192.168.99.105>, <http://192.168.99.106> 来访问服务。

### 停止服务

```bash
./run1.sh down
```

### 销毁集群

```bash
./run1.sh remove
```

## 二代 Swarm (Swarm Mode)

[二代 Swarm](https://docs.docker.com/engine/swarm/)，既 Docker Swarm Mode，是自 1.12 之后引入的原生的 Docker 集群编排机制。吸取一代 Swarm 的问题，大幅改变了架构，并且大大简化了集群构建。内置了分布式数据库，不在需要配置外置键值库；内置了内核级负载均衡；内置了边界负载均衡。

和一代 Swarm 的例子一样，为了方便说明，这里提供了一个 `run2.sh` 来帮助建立集群、运行服务。

### 建立 swarm 集群

在安装有 `docker-machine` 以及 VirtualBox 的虚拟机上（比如装有 Docker Toolbox 的Mac/Windows），使用 `run2.sh` 脚本即可创建集群：

```bash
./run2.sh create
```

*使用 Digital Ocean, AWS之类的云服务的话，就没必要本地使用 VirtualBox，不过需要事先配置好对应的 `docker-machine` 所需的环境变量。*

### 启动

```bash
./run2.sh up
```

### 横向扩展

```bash
./run2.sh scale 10 5
```

这里第一个参数是 nginx 容器的数量，第二个参数是 php 容器的数量。

### 列出服务状态

我们可以使用标准的命令列出所有服务以及状态：

```bash
$ docker service ls
ID            NAME   REPLICAS  IMAGE                      COMMAND
2lnqjas6rov4  mysql  1/1       mysql:5.7                  mysqld --character-set-server=utf8
ahqktnscjlkl  php    5/5       twang2218/lnmp-php:v1.2
bhoodda99ebt  nginx  10/10     twang2218/lnmp-nginx:v1.2
```

我们也可以通过下面的命令列出具体的每个服务对应的每个容器状态：

```bash
$ ./run2.sh ps
+ docker service ps -f desired-state=running nginx
ID                         NAME      IMAGE                      NODE     DESIRED STATE  CURRENT STATE           ERROR
87xr5oa577hl9amelznpy7s7z  nginx.1   twang2218/lnmp-nginx:v1.2  node2    Running        Running 3 hours ago
7dwmc22qaftz0xrvijij9dnuw  nginx.2   twang2218/lnmp-nginx:v1.2  node3    Running        Running 22 minutes ago
00rus0xed3y851pcwkbybop80  nginx.3   twang2218/lnmp-nginx:v1.2  manager  Running        Running 22 minutes ago
5ypct2dnfu6ducnokdlk82dne  nginx.4   twang2218/lnmp-nginx:v1.2  manager  Running        Running 22 minutes ago
7qshykjq8cqju0zt6yb9dkktq  nginx.5   twang2218/lnmp-nginx:v1.2  node2    Running        Running 22 minutes ago
e2cux4vj2femrb3wc33cvm70n  nginx.6   twang2218/lnmp-nginx:v1.2  node1    Running        Running 22 minutes ago
9uwbn5tm49k7vxesucym4plct  nginx.7   twang2218/lnmp-nginx:v1.2  node1    Running        Running 22 minutes ago
6d8v5asrqwnz03hvm2jh96rq3  nginx.8   twang2218/lnmp-nginx:v1.2  node1    Running        Running 22 minutes ago
eh44qdsiv7wq8jbwh2sr30ada  nginx.9   twang2218/lnmp-nginx:v1.2  node3    Running        Running 22 minutes ago
51l7nirwtv4gxnzbhkx6juvko  nginx.10  twang2218/lnmp-nginx:v1.2  node2    Running        Running 22 minutes ago
+ docker service ps -f desired-state=running php
ID                         NAME   IMAGE                    NODE     DESIRED STATE  CURRENT STATE           ERROR
4o3pqdva92vjdbfygdn0agp32  php.1  twang2218/lnmp-php:v1.2  manager  Running        Running 3 hours ago
bf3d6g4rr8cax4wucu9lixgmh  php.2  twang2218/lnmp-php:v1.2  node3    Running        Running 22 minutes ago
9xq9ozbpea7evllttvyxk7qtf  php.3  twang2218/lnmp-php:v1.2  manager  Running        Running 22 minutes ago
8umths3p8rqib0max6b6wiszv  php.4  twang2218/lnmp-php:v1.2  node2    Running        Running 22 minutes ago
0fxe0i1n2sp9nlvfgu4xlc0fx  php.5  twang2218/lnmp-php:v1.2  node1    Running        Running 22 minutes ago
+ docker service ps -f desired-state=running mysql
ID                         NAME     IMAGE      NODE   DESIRED STATE  CURRENT STATE        ERROR
3ozjwfgwfcq89mu7tqzi1hqeu  mysql.1  mysql:5.7  node3  Running        Running 3 hours ago
```

### 访问服务

`nginx` 将会守候 80 端口，由于二代 Swarm 具有边界负载均衡 (Routing Mesh, Ingress Load balance)，因此，集群内所有节点都会守护 80 端口，无论是 Manager 还是 Worker，无论是否有 `nginx` 容器在其上运行。当某个节点接到 80 端口服务请求后，会自动根据容器所在位置，利用 overlay 网络将请求转发过去。因此，访问任意节点的 80 端口都应该可以看到服务。

通过下面的命令可以列出所有节点，访问其中任意地址都应该可以看到应用页面：

```bash
$ ./run2.sh nodes
manager   http://192.168.99.101
node1     http://192.168.99.103
node2     http://192.168.99.102
node3     http://192.168.99.104
```

### 停止服务

```bash
./run2.sh down
```

### 销毁集群

```bash
./run2.sh remove
```
