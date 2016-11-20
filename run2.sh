#!/bin/bash

# Swarm Size. (default is 3)
if [ -z "${SWARM_SIZE}" ]; then
    SWARM_SIZE=3
fi

# By default, 'virtualbox' will be used, you can set 'MACHINE_DRIVER' to override it.
if [ -z "${MACHINE_DRIVER}" ]; then
    export MACHINE_DRIVER=virtualbox
fi

# REGISTRY_MIRROR_OPTS="--engine-registry-mirror https://jxus37ac.mirror.aliyuncs.com"
INSECURE_OPTS="--engine-insecure-registry 192.168.99.0/24"
# STORAGE_OPTS="--engine-storage-driver overlay2"

MACHINE_OPTS="${STORAGE_OPTS} ${INSECURE_OPTS} ${REGISTRY_MIRROR_OPTS}"

##############################
#      Image Management      #
##############################

function publish() {
    # Get username
    REGISTRY_USER=$(docker info | awk '/Username/ { print $2 }')

    if [ -z "${REGISTRY_USER}" ]; then
        # Login first, so we can get the user name directly
        echo "Please login first: 'docker login'"
        exit 1
    fi

    # Build & Push
    # Just remember replace the 'twang2218' in the '.env' with your hub username.
    docker-compose build && docker-compose push
}

#####################################
#  Swarm Mode Cluster Preparation   #
#####################################

function create_assistant() {
    NAME=$1
    docker-machine create ${MACHINE_OPTS} ${NAME}
    eval "$(docker-machine env ${NAME})"
    HostIP="$(docker-machine ip ${NAME})"

    echo "Create a registry mirror"
    docker run -d \
        -p 5000:5000 \
        -e REGISTRY_STORAGE_CACHE_BLOBDESCRIPTOR=inmemory \
        -e REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io \
        --name registry \
        registry
    REGISTRY_MIRROR_OPTS="--engine-registry-mirror http://${HostIP}:5000"
    export MACHINE_OPTS="${MACHINE_OPTS} ${REGISTRY_MIRROR_OPTS}"
}

function create_manager() {
    # The first argument is manager node name
    NAME=$1
    # Using docker-machine create a docker host for swarm manager
    docker-machine create ${MACHINE_OPTS} ${NAME}
    # Load manager docker host environment
    eval "$(docker-machine env ${NAME})"
    # Get manager IP
    ManagerIP=`docker-machine ip ${NAME}`
    # Initialize a Swarm
    docker swarm init --advertise-addr ${ManagerIP}
    # Get Worker Token
    WorkerToken=`docker swarm join-token worker | grep token | awk '{ print $2 }'`
    echo "Worker's Token is: '${WorkerToken}'"
    # Exports
    export ManagerIP
    export WorkerToken
}

function create_node() {
    # The first argument is the node name
    NAME=$1
    # Using docker-machine create a docker host for swarm worker
    docker-machine create ${MACHINE_OPTS} ${NAME}
    # Load the worker docker host environment
    eval "$(docker-machine env ${NAME})"
    # Get the Worker IP
    WorkerIP=`docker-machine ip ${NAME}`
    # Join the Swarm as a Worker
    docker swarm join \
        --token ${WorkerToken} \
        --advertise-addr ${WorkerIP} \
        ${ManagerIP}:2377
}

function create() {
    create_assistant assistant
    create_manager manager
    for i in $(seq 1 ${SWARM_SIZE})
    do
        create_node node${i} &
    done

    wait
}

function remove() {
    for i in $(seq 1 ${SWARM_SIZE})
    do
        docker-machine rm -y node${i} || true
    done
    docker-machine rm -y manager || true
    docker-machine rm -y assistant || true
}

##############################
#     Service Management     #
##############################

function up() {
    # Load '.env' environment variables
    export $(cat .env | xargs)
    # Load Swarm Manager docker host environment
    eval "$(docker-machine env manager)"
    set -xe
    # Create Networks
    docker network create -d overlay frontend
    docker network create -d overlay backend
    # Start 'mysql' Service
    docker service create \
        --name mysql \
        -e TZ=Asia/Shanghai \
        -e MYSQL_ROOT_PASSWORD=Passw0rd \
        --mount src=mysql-data,dst=/var/lib/mysql \
        --network backend \
        mysql:5.7 \
            mysqld --character-set-server=utf8
    # Start 'php' Service
    docker service create \
        --name php \
        -e MYSQL_PASSWORD=Passw0rd \
        --network frontend \
        --network backend \
        "${DOCKER_USER}/lnmp-php:v1.2"
    # Start 'nginx' Service
    docker service create \
        --name nginx \
        --network frontend \
        -p 80:80 \
        "${DOCKER_USER}/lnmp-nginx:v1.2"
    # List Created Service
    docker service ls
}

function scale() {
    # The first argument is 'nginx' service replica number.
    NGINX_SIZE=$1
    # The second argument is 'php' service replica number.
    PHP_SIZE=$2

    # Load Swarm Manager Docker host environment
    eval "$(docker-machine env manager)"

    if [ -z "${NGINX_SIZE}" ]; then
        # We need at least 'nginx_size' to scale
        echo "Usage: scale <nginx_size> [php_size]"; exit 1
    else
        echo "Scaling 'nginx' service to ${NGINX_SIZE} replicas ..."
        docker service update \
            --replicas "${NGINX_SIZE}" \
            nginx
    fi

    # We need at least 1 'php' replica.
    if [ "${PHP_SIZE}" -ge 1 ]; then
        echo "Scaling 'php' service to ${PHP_SIZE} replicas ..."
        docker service update \
            --replicas "${PHP_SIZE}" \
            php
    fi
}

function down() {
    # Load Swarm Manager Docker host environment
    eval "$(docker-machine env manager)"
    set -xe
    # Remove services
    docker service rm nginx php mysql
    # Remove networks
    docker network rm frontend backend
}

function ps() {
    # Load Swarm Manager Docker host environment
    eval "$(docker-machine env manager)"
    set -xe
    # List 'nginx' service tasks
    docker service ps -f desired-state=running nginx
    # List 'php' service tasks
    docker service ps -f desired-state=running php
    # List 'mysql' service tasks
    docker service ps -f desired-state=running mysql
}

function list_nodes() {
    echo "manager   http://$(docker-machine ip manager)"
    for i in $(seq 1 ${SWARM_SIZE})
    do
        echo "node${i}     http://$(docker-machine ip node${i})"
    done
}

##############################
#         Entrypoint         #
##############################

function main() {
    Command=$1
    shift
    case "${Command}" in
        create)     create ;;
        remove)     remove ;;
        up)         up ;;
        scale)      scale "$@" ;;
        env)        docker-machine env manager ;;
        down)       down ;;
        ps)         ps ;;
        nodes)      list_nodes ;;
        publish)    publish ;;
        *)          echo "Usage: $0 <create|remove|up|scale|down|ps|nodes|publish>"; exit 1 ;;
    esac
}

main "$@"
