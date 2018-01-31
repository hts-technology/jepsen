#!/bin/sh
set -e # exit on an error

ERROR(){
    /bin/echo -e "\e[101m\e[97m[ERROR]\e[49m\e[39m $@"
}

WARNING(){
    /bin/echo -e "\e[101m\e[97m[WARNING]\e[49m\e[39m $@"
}

INFO(){
    /bin/echo -e "\e[104m\e[97m[INFO]\e[49m\e[39m $@"
}

exists() {
    type $1 > /dev/null 2>&1
}

for f in $@; do
    case $f in
        '--help' )
            HELP=1
            ;;
        '--init-only' )
            INIT_ONLY=1
            ;;
        '--dev' )
            if [ ! "$JEPSEN_ROOT" ]; then
                INFO "MISSING VAR: --dev requires JEPSEN_ROOT to be set"
                exit 1
            else
                INFO "Running docker-compose with dev config"
                DEV="-f docker-compose.dev.yml"
            fi
            ;;
        '--daemon' )
            INFO "Running docker-compose as daemon"
            RUN_AS_DAEMON=1
            ;;
        *)
            ERROR "unknown option $1"
            exit 1
            ;;
    esac
    shift
done

if [ "$HELP" ]; then
    echo "usage: $0 [OPTION]"
    echo "  --help                                                Display this message"
    echo "  --init-only                                           Initializes the secret, but does not call docker-compose"
    echo "  --daemon                                              Runs docker-compose in the background"
    echo "  --dev                                                 Mounts dir at host's $JEPSEN_ROOT to /jepsen on jepsen-control container, syncing files for development"
    exit 0
fi

exists ssh-keygen || { ERROR "Please install ssh-keygen (apt-get install openssh-client)"; exit 1; }
exists perl || { ERROR "Please install perl (apt-get install perl)"; exit 1; }

if [ ! -f ./secret/node.env ]; then
    INFO "Generating key pair"
    ssh-keygen -t rsa -N "" -f ./secret/id_rsa

    INFO "Generating ./secret/control.env"
    echo '# generated by jepsen/docker/up.sh, parsed by jepsen/docker/control/bashrc' > ./secret/control.env
    echo '# NOTE: \\n is expressed as ↩' >> ./secret/control.env
    echo SSH_PRIVATE_KEY="$(cat ./secret/id_rsa | perl -p -e 's/\n/↩/g')" >> ./secret/control.env
    echo SSH_PUBLIC_KEY=$(cat ./secret/id_rsa.pub) >> ./secret/control.env

    INFO "Generating ./secret/node.env"
    echo '# generated by jepsen/docker/up.sh, parsed by the "tutum/debian" docker image entrypoint script' > ./secret/node.env
    echo ROOT_PASS=root >> ./secret/node.env
    echo AUTHORIZED_KEYS=$(cat ./secret/id_rsa.pub) >> ./secret/node.env
else
    INFO "No need to generate key pair"
fi

# Dockerfile does not allow `ADD ..`. So we need to copy that.
INFO "Copying .. to control/jepsen"
(
    rm -rf ./control/jepsen
    mkdir ./control/jepsen
    (cd ..; tar --exclude=./docker --exclude=./.git -cf - .)  | tar Cxf ./control/jepsen -
)

if [ "$INIT_ONLY" ]; then
    exit 0
fi

exists docker || { ERROR "Please install docker (https://docs.docker.com/engine/installation/)"; exit 1; }
exists docker-compose || { ERROR "Please install docker-compose (https://docs.docker.com/compose/install/)"; exit 1; }

INFO "Running \`docker-compose build\`"
docker-compose build

INFO "Running \`docker-compose up\`"
if [ "$RUN_AS_DAEMON" ]; then
    docker-compose -f docker-compose.yml $DEV up -d
    INFO "All containers started, run \`docker ps\` to view"
    for i in {1..5}; do docker exec jepsen-n${i} service rsyslog start ; done;
    exit 0
else
    INFO "Please run \`docker exec -it jepsen-control bash\` in another terminal to proceed"
    docker-compose -f docker-compose.yml $DEV up
fi
