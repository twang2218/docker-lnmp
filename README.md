# LNMP Docker 配置文件

启动3个Docker：`php`, `mysql`, `nginx`。`nginx`连接 `php`，`php` 连接 `mysql`。

三个服务都可定制，

 - `nginx` 配置文件： `conf/nginx.conf` ；
 - `mysql` 配置文件： `conf/mysql.cnf`；
 - `php` 配置文件： `conf/php.conf`；

## 启动

```
docker-compose up -d
```

## 访问服务

`nginx` 将会守候 80 端口，除了默认主机外，还有一个域名为 `www.example.com` 的虚拟主机。可以在本机 `/etc/hosts` 中添加一条绑定，然后访问 http://www.example.com 

## 停止服务

```
docker-compose stop
```
