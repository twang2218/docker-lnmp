#!/bin/bash

# Swarm Size. (default is 3)
if [ -z "${SWARM_SIZE}" ]; then
    SWARM_SIZE=3
fi

# By default, 'virtualbox' will be used, you can set 'DOCKER_MACHINE_DRIVER' to override it.
if [ -z "${DOCKER_MACHINE_DRIVER}" ]; then
    DOCKER_MACHINE_DRIVER=virtualbox
fi

# REGISTRY_MIRROR_OPTS="--engine-registry-mirror https://jxus37ac.mirror.aliyuncs.com"
INSECURE_OPTS="--engine-insecure-registry 192.168.99.0/24"
# STORAGE_OPTS="--engine-storage-driver overlay2"

MACHINE_OPTS="${STORAGE_OPTS} ${INSECURE_OPTS} ${REGISTRY_MIRROR_OPTS}"

##############################
#      Image Management      #
##############################

function build() {
    # Build images
    docker build --pull -t ${REGISTRY_USER}/lnmp-nginx:latest -f nginx-php/Dockerfile.nginx ./nginx-php
    docker build --pull -t ${REGISTRY_USER}/lnmp-php:latest -f nginx-php/Dockerfile.php ./nginx-php
    docker build --pull -t ${REGISTRY_USER}/lnmp-mysql:latest -f mysql/Dockerfile ./mysql
}

function push() {
    # Push to the registry
    docker push ${REGISTRY_USER}/lnmp-nginx:latest
    docker push ${REGISTRY_USER}/lnmp-php:latest
    docker push ${REGISTRY_USER}/lnmp-mysql:latest
}

function publish() {
    # Get username
    REGISTRY_USER=$(docker info | awk '/Username/ { print $2 }')

    if [ -z "${REGISTRY_USER}" ]; then
        # Login first, so we can get the user name directly
        echo "Please login first: 'docker login'"
        exit 1
    fi

    # Build & Push
    # More clean way would be:
    #
    #   docker-compose build && docker-compose push
    #
    # Just remember replace the 'twang2218' in the 'docker-compose.yml' with your hub username.
    build && push
}

##############################
#  Swarm Cluster Preparation #
##############################

function create_assistant() {
    NAME=$1
    docker-machine create -d ${DOCKER_MACHINE_DRIVER} ${MACHINE_OPTS} ${NAME}
    eval "$(docker-machine env ${NAME})"
    HostIP="$(docker-machine ip ${NAME})"

    echo "Create etcd as a Key-value store"
    export KVSTORE="etcd://${HostIP}:2379"
    docker run -d \
        -p 4001:4001 -p 2380:2380 -p 2379:2379 \
        --restart=always \
        --name etcd \
        twang2218/etcd:v2.3.7 \
            --initial-advertise-peer-urls http://${HostIP}:2380 \
            --initial-cluster default=http://${HostIP}:2380 \
            --advertise-client-urls http://${HostIP}:2379,http://${HostIP}:4001 \
            --listen-client-urls http://0.0.0.0:2379,http://0.0.0.0:4001 \
            --listen-peer-urls http://0.0.0.0:2380

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

function create_master() {
    NAME=$1
    echo "kvstore is ${KVSTORE}"
    # eth1 on virtualbox, eth0 on digitalocean
    docker-machine create -d ${DOCKER_MACHINE_DRIVER} ${MACHINE_OPTS} \
        --swarm \
        --swarm-discovery=${KVSTORE} \
        --swarm-master \
        --engine-opt="cluster-store=${KVSTORE}" \
        --engine-opt="cluster-advertise=eth1:2376" \
        ${NAME}
}

function create_node() {
    NAME=$1
    echo "kvstore is ${KVSTORE}"
    # eth1 on virtualbox, eth0 on digitalocean
    docker-machine create -d ${DOCKER_MACHINE_DRIVER} ${MACHINE_OPTS} \
        --swarm \
        --swarm-discovery=${KVSTORE} \
        --engine-opt="cluster-store=${KVSTORE}" \
        --engine-opt="cluster-advertise=eth1:2376" \
        ${NAME}
}

function create() {
    create_assistant assistant
    create_master master
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
    docker-machine rm -y master || true
    docker-machine rm -y assistant || true
}

##############################
#     Service Management     #
##############################

function up() {
    eval "$(docker-machine env --swarm master)"
    # Pull Images from hub
    docker-compose pull
    # Start Image
    docker-compose up -d
}

function scale() {
    NGINX_SIZE=$1
    PHP_SIZE=$2

    if [ -z "${NGINX_SIZE}" ]; then
        echo "Usage: scale <nginx_size> [php_size]"; exit 1
    elif [ "${NGINX_SIZE}" -gt "${SWARM_SIZE}" ]; then
        SCALE_NGINX="nginx=${SWARM_SIZE}"
    else
        SCALE_NGINX="nginx=${NGINX_SIZE}"
    fi

    if [ "${PHP_SIZE}" -gt 1 ]; then
        SCALE_PHP="php=${PHP_SIZE}"
    fi

    eval "$(docker-machine env --swarm master)"
    set -xe
    docker-compose scale ${SCALE_NGINX} ${SCALE_PHP}
    set +xe
}

function down() {
    eval "$(docker-machine env --swarm master)"
    docker-compose down
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
        env)        docker-machine env --swarm master ;;
        down)       down ;;
        publish)    publish ;;
        *)          echo "Usage: $0 <create|remove|up|scale|down|publish>"; exit 1 ;;
    esac
}

main "$@"
