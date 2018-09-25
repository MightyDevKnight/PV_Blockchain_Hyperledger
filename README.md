# Starter Application for Hyperledger Fabric

Create a network to jump start development of your decentralized application.

The network can be deployed to multiple docker containers on one host for development or to multiple hosts for testing 
or production.

Scripts of this starter generate crypto material and config files, start the network and deploy your chaincodes. 
Developers can use REST API to invoke and query chaincodes, explore blocks and transactions.

What's left is to develop your chaincodes and place them into the [chaincode](./chaincode) folder, 
and user interface as a single page web app that you can serve by by placing the sources into the [www](./www) folder. 

Most of the plumbing work is taken care of by this starter.

# Install

Install prerequisites: `docker`. This example is for Ubuntu 18:
```bash
sudo apt update
sudo apt install apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
sudo apt update
sudo apt install docker-ce docker-compose
# add yourself to the docker group and re-login
sudo usermod -aG docker ${USER}
```

# Create a network with 1 organization for development

## Generate and start orderer

Generate crypto material and the genesis block for the *Orderer* organization. Using default *example.com* DOMAIN. 
```bash
./generate-orderer.sh
```

Start docker containers for *Orderer*.
```bash
docker-compose -f docker-compose-orderer.yaml up
```

## Generate and start member organization

Open another console. Generate crypto material for the member organization. Using default ORG name *org1*.
```bash
./generate-peer.sh
```

Start docker containers for *org1*.
```bash
docker-compose up
```

## Add organization to the consortium and create a channel

Open another console. Add *org1* to the consortium as *Admin* of the *Orderer* organization:
```bash
./consortium-add-org.sh org1
``` 

Create channel *common* as *Admin* of *org1* and join our peers to the channel:
```bash
./channel-create.sh common
./channel-join.sh common
``` 

## Install and instantiate chaincode

Install and instantiate *nodejs* chaincode *reference* on channel *common*. 
Using defaults: language `node`, version `1.0`, source code is in the folder of the same 
name as the chaincode.
Note the path to the source code is inside `cli` docker container and is mapped to the local 
`./chaincode/node/reference`. 
```bash
./chaincode-install.sh reference
./chaincode-instantiate.sh reference common '["init","a","10","b","0"]'
```

## Invoke chaincode

Invoke chaincode *reference*.
```bash
./chaincode-invoke.sh reference common '["invoke","a","b","1"]'
```

Query chaincode.
```bash
./chaincode-query.sh reference common '["query","a"]'
```

## Upgrade chaincode 

Now you can make changes to your chaincode, install a new version `1.1` and upgrade it.
```bash
./chaincode-install.sh reference 1.1
./chaincode-upgrade.sh reference common '["init","a","10","b","0"]' 1.1
```

When you develop and need to push your changes frequently, this shortcut script will install and instantiate with a 
new random version
```bash
./chaincode-reload.sh reference common '["init","a","10","b","0"]'
``` 

## Golang chaincode 

Install and instantiate *golang* chaincode *example_02* on channel *common*. 
Source code is in local `./chaincode/go/chaincode_example02` mapped to `/opt/gopath/src/chaincode_example02` 
inside `cli` container.
```bash
./chaincode-install.sh example02 1.0 chaincode_example02 golang
./chaincode-instantiate.sh example02 common '["init","a","10","b","0"]'
```

Reload *golang* chaincode.
```bash
./chaincode-reload.sh example02 common '["init","a","10","b","0"]' chaincode_example02 golang
```

# Example with a network of 3 organizations

You can replace default DOMAIN *example.com* and *org1*, *org2* with the names of your organizations. 
Define them via environment variables either in shell or `.env` file. 
```bash
export DOMAIN=example.com ORG=org1
```

You can also extend this example by adding more than 3 organizations and any number of channels with various membership.

## Create organizations and add them to the consortium

Clean up. Remove all containers, delete local crypto material:
```bash
./clean.sh
```

Generate crypto material and start docker containers of the *Orderer* organization:
```bash
./generate-orderer.sh

docker-compose -f docker-compose-orderer.yaml up
```

Open another shell. Set environment variables `ORGS` and `CAS` that define how this org's client will connect to other 
organizations' peers and certificate authorities. When moving to multi host deployment they will be need 
to be redefined.

Generate and start *org1*.
```bash
export ORGS='{"org1":"peer0.org1.example.com:7051","org2":"peer0.org2.example.com:7051","org3":"peer0.org3.example.com:7051"}' CAS='{"org1":"ca.org1.example.com:7054"}'

./generate-peer.sh

docker-compose up
```

Open another shell. Note since we're reusing the same `docker-compose.yaml` file we need to redefine `COMPOSE_PROJECT_NAME`.
Also the ports open to host machine need to be redefined to avoid collision.

Generate and start *org2*.
```bash
export COMPOSE_PROJECT_NAME=org2 ORG=org2 
export ORGS='{"org1":"peer0.org1.example.com:7051","org2":"peer0.org2.example.com:7051","org3":"peer0.org3.example.com:7051"}' CAS='{"org2":"ca.org2.example.com:7054"}'
export API_PORT=3001

./generate-peer.sh

docker-compose up
```

Generate and start *org3* in another shell:
```bash
export COMPOSE_PROJECT_NAME=org3 ORG=org3 
export ORGS='{"org1":"peer0.org1.example.com:7051","org2":"peer0.org2.example.com:7051","org3":"peer0.org3.example.com:7051"}' CAS='{"org3":"ca.org2.example.com:7054"}'
export API_PORT=3002

./generate-peer.sh

docker-compose up
```

Now you should have 4 console windows running containers of *Orderer*, *org1*, *org2*, *org3* organizations.

Open another console where we'll become an *Admin* user of the *Orderer* organization. We'll add orgs to the consortium:
```bash
./consortium-add-org.sh org1
./consortium-add-org.sh org2
./consortium-add-org.sh org3
``` 

Now all 3 orgs are known in the consortium and can create and join channels.

## Create channels, install and instantiate chaincodes

Open another console where we'll become *org1* again. We'll create channel *common*, add other orgs to it, 
and join our peers to the channel:
```bash
./channel-create.sh common
./channel-add-org.sh org2 common
./channel-add-org.sh org3 common
./channel-join.sh common
``` 

Let's create a bilateral channel between *org1* and *org2* and join to it:
```bash
./channel-create.sh org1-org2
./channel-add-org.sh org2 org1-org2
./channel-join.sh org1-org2
```

Install and instantiate chaincode *reference* on channel *common*. Note the path to the source code is inside `cli` 
docker container and is mapped to the local  `./chaincode/node/reference`
```bash
./chaincode-install.sh reference
./chaincode-instantiate.sh reference common '["init","a","10","b","0"]'
```

Install and instantiate chaincode *relationship* on channel *org1-org2*:
```bash
./chaincode-install.sh relationship
./chaincode-instantiate.sh relationship org1-org2 '["init","a","10","b","0"]'
```

Open another console where we'll become *org2* to install chaincodes *reference* and  *relationship* 
and to join channels *common* and *org1-org2*:
```bash
export COMPOSE_PROJECT_NAME=org2 ORG=org2

./chaincode-install.sh reference
./chaincode-install.sh relationship
./channel-join.sh common
./channel-join.sh org1-org2
``` 

Now become *org3* to install chaincode *reference* and join channel *common*:
```bash
export COMPOSE_PROJECT_NAME=org3 ORG=org3

./chaincode-install.sh reference
./channel-join.sh common
``` 

## Use REST API to query and invoke chaincodes

Login into *org1* as *user1* and save returned token into env variable `JWT` which we'll use to identify our user 
in subsequent requests:
```bash
JWT=`(curl -d '{"login":"user1","password":"pass"}' --header "Content-Type: application/json" http://localhost:3000/users | tr -d '"')`
```

Query channels *org1* has joined
```bash
curl -H "Authorization: Bearer $JWT" http://localhost:3000/channels
```
returns
```json
[{"channel_id":"common"},{"channel_id":"org1-org2"}]
``` 

Query status, orgs, instantiated chaincodes and block 2 of channel *common*:
```bash
curl -H "Authorization: Bearer $JWT" http://localhost:3000/channels/common
curl -H "Authorization: Bearer $JWT" http://localhost:3000/channels/common/chaincodes
curl -H "Authorization: Bearer $JWT" http://localhost:3000/channels/common/orgs
curl -H "Authorization: Bearer $JWT" http://localhost:3000/channels/common/blocks/2
```

Invoke chaincode *reference* on channel *common*, it's implemented by chaincode_example_02 and moves 1 from a to b:
```bash
curl -H "Authorization: Bearer $JWT" --header "Content-Type: application/json" \
http://localhost:3000/channels/common/chaincodes/reference -d '{"fcn":"invoke","args":["a","b","1"]}'
```

Query chaincode *reference* on channel *common* for the balance of *a*:
```bash
curl -H "Authorization: Bearer $JWT" --header "Content-Type: application/json" \
'http://localhost:3000/channels/common/chaincodes/reference?fcn=query&args=a'
```

Now login into the API server of *org2* `http://localhost:3001` and query the balance of *b*:
```bash
JWT=`(curl -d '{"login":"user1","password":"pass"}' --header "Content-Type: application/json" http://localhost:3001/users | tr -d '"')`

curl -H "Authorization: Bearer $JWT" --header "Content-Type: application/json" \
'http://localhost:3001/channels/common/chaincodes/reference?fcn=query&args=b'
```

# Build Fabric with support for chaincodes in Java

This excercise has been tested with the following versions:
```bash
docker --version && java -version && go version
```

- Docker version 17.12.1-ce, build 7390fc6
- java version "1.8.0_181"
- go version go1.10.1 linux/amd64


Clean up. Delete all docker containers and images.
```bash
docker rm -f `(docker ps -aq)`
docker rmi -f `(docker images -aq)`
```

Create directories, environment and clone the latest source of Hyperledger Fabric from `master`.
```bash
mkdir -p ~/go
export GOPATH=~/go
mkdir -p $GOPATH/src/github.com/hyperledger
cd $GOPATH/src/github.com/hyperledger
git clone https://github.com/hyperledger/fabric
cd fabric
```

Build docker images with java enabled via `EXPERIMENTAL` flag.
```bash
export EXPERIMENTAL=true
make docker
```

Clone the latest source of java chaincode support.
```bash
cd $GOPATH/src/github.com/hyperledger
git clone https://github.com/hyperledger/fabric-chaincode-java 
cd fabric-chaincode-java
```

Build docker image for java chaincode `fabric-javaenv` and java `shim` for chaincode development.
```bash
./gradlew buildImage
./gradlew publishToMavenLocal
```

Install and instantiate *java* chaincode *fabric-chaincode-example* on channel *common*. 
Note the path to the source code is inside `cli` docker container and is mapped to the local 
`./chaincode/java/fabric-chaincode-example-gradle`
```bash
./chaincode-install.sh fabric-chaincode-example /opt/chaincode/java/fabric-chaincode-example-gradle java
./chaincode-instantiate.sh fabric-chaincode-example common '["init","a","10","b","0"]'
```
