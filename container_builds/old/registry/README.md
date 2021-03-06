# docker registry
Build a private registry from [Dotcloud Github Repo](https://github.com/dotcloud/docker-registry)

## Prerequest
We assume there is a storage device mounted on /registry-storage to the docker host.
This folder is added to the container as the folder tmp  issuing command 
`docker run -v /registry-storage:/tmp/`. 
The registry uses the tmp folder to store the registry data.

## Version
As docker is under developement, we tested different registry versions
and found version 0.7.0 working for our purpose. As of 2014-06-24 
version 0.7.3 does work correctly. 


## build.sh
This script builds the registry container either fresh or by pulling samalba/docker-registry.
It then configures the container and tags it my-registry:mkl

Usage
====

```bash
build.sh -b --base	build a fresh base registry container and configure it
build.sh -p --pull      pull container samalba/docker-registry as base and configure it
build.sh -c --config	use the base registry and configure it
build.sh -h --help      this message
```

### Kdocker-web
We can use a [Docker Web Gui](https://github.com/tsaikd/kdocker-web) to show local images 
pulled onto the docker host. 

### Docker Options
In order do connect to the docker host, we need to set docker server options, to allow these connections:
`DOCKER_OPTS="-api-enable-cors=true -H tcp://10.0.0.4:4243 -H unix:///var/run/docker.sock"` int `/etc/default/docker`
if 10.0.0.4 is the private ip of the docker host.

### Authentication
We use nginx to provide *basic authentication*. Still any one who can log into the
serve can pull an push any image. 

### registry reachability

We tested container samalba/docker-registry 
The registry was only reachable within the same AWS availability zone

