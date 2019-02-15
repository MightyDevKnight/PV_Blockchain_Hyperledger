# Starter Application for Hyperledger Fabric

Create a network to jump start development of your decentralized application on 
[Hyperledger Fabric](https://www.hyperledger.org/projects/fabric) platform.

The network is run by docker containers and can be deployed to one host for development or to multiple hosts for testing 
or production.

Scripts of this starter generate crypto material and config files, start the network and deploy your chaincodes. 
Developers can use [REST API](https://github.com/olegabu/fabric-starter-rest) to invoke and query chaincodes, 
explore blocks and transactions.

What's left is to develop your chaincodes and place them into the [chaincode](./chaincode) folder, 
and user interface as a single page web app that you can serve by by placing the sources into the [www](./www) folder.

See also

- [fabric-starter-rest](https://github.com/olegabu/fabric-starter-rest) REST API server and client built with NodeJS SDK
- [fabric-starter-web](https://github.com/olegabu/fabric-starter-web) Starter web application to work with the REST API
- [chaincode-node-storage](https://github.com/olegabu/chaincode-node-storage) Base class for node.js chaincodes with CRUD functionality


## Blockchain network deployment

The following sections describe Fabric Starter possibilites in more details:

- [Installation.](#install)
- [Network with 1 organization (and orderer) for development.](#example1org)
- [Several organizations on one (local) host in multiple docker containers.](#example3org)
- [REST API to query and invoke chaincodes.](#restapi)
- [Getting closer to production. Multiple hosts deployment with `docker-machine`. Deployment to clouds.](#multihost)
- [SSL\Https connection](#sslhttps)
- [Development\Release cycle](#releasecycle)



<a name="install"></a>
## Install
See [Installation](docs/install.md)



<a name="setversion"></a>
## Using a particular version of Hyperledger Fabric
To deploy network with a particular version of HL Fabric export desired version in the 
FABRIC_VERSION environment variable. The `latest` docker image tag is used by default.
```bash
export FABRIC_VERSION=1.2.0
```


<a name="example1org"></a>
## Create a network with 1 organization for development
See [One Org Network](docs/network-one-org.md)



<a name="example3org"></a>
## Create a local network of 3 organizations
See [Three local Orgs Network](docs/network-three-org.md)


<a name="restapi"></a>
## Use REST API to query and invoke chaincodes

Login into *org1* as *user1* and save returned token into env variable `JWT` which we'll use to identify our user 
in subsequent requests:
```bash
JWT=`(curl -d '{"username":"user1","password":"pass"}' --header "Content-Type: application/json" http://localhost:4000/users | tr -d '"')`
```

Query channels *org1* has joined
```bash
curl -H "Authorization: Bearer $JWT" http://localhost:4000/channels
```
returns
```json
[{"channel_id":"common"},{"channel_id":"org1-org2"}]
``` 

Query status, orgs, instantiated chaincodes and block 2 of channel *common*:
```bash
curl -H "Authorization: Bearer $JWT" http://localhost:4000/channels/common
curl -H "Authorization: Bearer $JWT" http://localhost:4000/channels/common/chaincodes
curl -H "Authorization: Bearer $JWT" http://localhost:4000/channels/common/orgs
curl -H "Authorization: Bearer $JWT" http://localhost:4000/channels/common/blocks/2
```

Invoke function `put` of chaincode *reference* on channel *common* to save entity of type `account` and id `1`:

With `["targets"]`:
```bash
curl -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
http://localhost:4000/channels/common/chaincodes/reference -d '{"fcn":"put","args":["account","1","{name:\"one\"}"],"targets":["peer0.org1.example.com","peer1.org1.example.com:7051"]}'
```
Without `["targets"]`:
```bash
curl -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
http://localhost:4000/channels/common/chaincodes/reference -d '{"fcn":"put","args":["account","1","{name:\"one\"}"]}'
```


Query function `list` of chaincode *reference* on channel *common* with args `["account"]`:

With `["targets"]`:
```bash
curl -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
'http://localhost:4000/channels/common/chaincodes/reference?channelId=common&chaincodeId=reference&fcn=list&args=%5B%22account%22%5D&targets=%5B%22peer0.org1.example.com%22%2C%22peer1.org1.example.com%3A7051%22%5D'
```

Without `["targets"]`:
```bash
curl -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
'http://localhost:4000/channels/common/chaincodes/reference?channelId=common&chaincodeId=reference&fcn=list&args=%5B%22account%22%5D'
```


 <a name="multihost"></a>
## Multi host deployment
See [Multi host deployment](docs/multihost.md)


<a name="sslhttps"></a>
## SSL\Https connection to API

You can configure Fabric Starter to serve API requests and WebUI at `https://` endpoint.
If an organization has own SSL-certificate it can be used in its web\rest communications (see below).  

Otherwise a self-signed certificate will be generated with `openssl` during first run of the network. 
The certificate's attributes for the auto-generated certificate may be adjusted by environment variables. 


### Use existing organization's certificate:
In order to apply existing certificates:  

- copy the certificate and the private key files into `ssl-certs` folder  
OR
- specify the path to the folder with the certificate in *SSL_CERTS_PATH* environment variable  
Then
- rename the certificate file to `public.crt` 
- rename the private key file to `private.key`

Start node with the `docker-compose` as described in previous chapters 
but specify additional docker-compose _override_ file parameter: `-f docker-compose-ssl.yaml` 
(and exclude `-f ports.yaml` as ports area changed)  

```bash
docker-compose -f docker-compose.yaml -f docker-compose-ssl.yaml up
```

### Define properties for the auto-generated certificate

To adjust certificates's parameters export necessary variables before _up_ the node:

```bash 
export CERT_COUNTRY="US" CERT_STATE="N/A" CERT_ORG="$ORG.$DOMAIN" CERT_ORGANIZATIONAL_UNIT="Hyperledger Fabric Blockchain" CERT_COMMON_NAME="Fabric-Starter-Rest-API"
```

If you use `network-create.sh` scripts export DOCKER_COMPOSE_ARGS variable 
```bash 
${DOCKER_COMPOSE_ARGS:- -f docker-compose.yaml -f couchdb.yaml -f multihost.yaml -f docker-compose-ssl.yaml}
```

<a name="releasecycle"></a>
## Releases\Snapshots cycle

As this project doesn't have a defined release cycle yet we create 
`snapshot-{version}-{fabric-version}` branches  
when we see code is stable enough or before introducing major changes\new features.  

`Note`, the Hyperledger Fabric version which the snapshot depends on is defined in the `.env` file.  
Also this project uses _olegabu/fabric-starter-rest_ docker image which has 
the same versioning approach but even updated docker image with the same label (e.g. latest)
won't be pulled automatically if it exists in the local docker registry.   
You have to remove the old image manually (by `docker rmi -f olegabu/fabric-starter-rest`).    


The _`master`_ branch as well as potentially _`feature branches`_ are used for development.  
`Master` is assigned to the _`latest`_ version of Fabric.


#### Currently issued branches are:

- master(development)
    - ssl/https support for API\WebUI 
- snapshot-0.2-1.4
    - use _fabric-starter-rest:snapshot-0.2-1.4_
- snapshot-0.1-1.4
    - start snapshot branching
