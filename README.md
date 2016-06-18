# LNMP Docker 配置文件

启动3个Docker：`php`, `mysql`, `nginx`。`nginx`连接 `php`，`php` 连接 `mysql`。

三个服务都可定制。

每个服务都有独立的文件夹存储其相关内容。

 - `nginx`： 存储 nginx 的默认站点配置文件：`default.conf`；
 - `mysql`： 存储 mysql 的配置文件 `mysql.cnf`；
 - `php`： 存储定制 php image 的 `Dockerfile`，以及`conf/php.conf`；

  官方的 php 是不带 mysql 插件的，因此需要使用 Dockerfile 进行定制。

## 启动

```
docker-compose up -d
```

## 访问服务

`nginx` 将会守候 80 端口，直接在本机访问 http://localhost（如果是使用 Docker Toolbox 的虚拟机的话，http://192.168.99.100），其它环境请查询Docker主机IP。

```
curl http://localhost
```

## 停止服务

```
docker-compose stop
```
