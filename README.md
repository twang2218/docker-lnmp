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

## 停止服务

```
docker-compose stop
```
