# BaaS Infra

<!-- toc -->

- [Prepare Namespaces (if not exist)](#prepare-namespaces-if-not-exist)
- [Setup BaaS Services](#setup-baas-services)
  * [Setup Database](#setup-database)
    + [Init Cluster](#init-cluster)
    + [Migrate BaaS Database](#migrate-baas-database)
    + [Create basic auth secret for Authenticator role used by PostgREST](#create-basic-auth-secret-for-authenticator-role-used-by-postgrest)
  * [Setup Auth Service](#setup-auth-service)
    + [Deploy Auth Service](#deploy-auth-service)
  * [Setup PostgREST](#setup-postgrest)
    + [Prepare JWT for PostgREST](#prepare-jwt-for-postgrest)
    + [Deploy PostgREST](#deploy-postgrest)
- [Setup BaaS Project](#setup-baas-project)
  * [Create migrations for projects](#create-migrations-for-projects)

<!-- tocstop -->

> [!CAUTION]
> Please Setup Cloud First

## Prepare Namespaces (if not exist)

1. BaaS
2. BaaS-Project

```sh
kubectl create namespace baas
kubectl create namespace baas-project
```

## Setup BaaS Services

### Setup Database

#### Init Cluster

Create [CloudNative-PG](https://github.com/cloudnative-pg/cloudnative-pg) Cluster, Database, ImageCatalog

```sh
kubectl apply \
  -f https://raw.githubusercontent.com/cloudnative-pg/postgres-containers/main/Debian/ClusterImageCatalog-bookworm.yaml
kubectl apply -f ./000001_db-cluster.yaml
```

#### Migrate BaaS Database

Create ConfigMap from migrations and running migrations with [dbmate](https://github.com/amacneil/dbmate)

```sh
kubectl create configmap -n baas migrations \
  --from-file=./migrations/i3s/ \
  --from-file=./migrations/baas
kubectl apply -f ./000002_migrate_baas.yaml
```

#### Create basic auth secret for Authenticator role used by PostgREST

```sh
password=$(pwgen 20 1)
kubectl create secret -n baas generic baas-db-authenticator \
  --type=kubernetes.io/basic-auth \
  --from-literal=username=authenticator \
  --from-literal=password=${password} \
  --from-literal=uri=postgresql://authenticator:${password}@baas-db-rw.baas:5432/app
```

### Setup Auth Service

Create secret for auth service encryption, signing, and hashing.

```sh
kubectl create secret -n baas generic baas-auth-secret \
  --from-literal AUTH_SECRET=$(openssl rand -base64 32)
```

#### Deploy Auth Service

```sh
kubectl apply -f ./000003_auth.yaml
```

### Setup PostgREST

#### Prepare JWT for PostgREST

```sh
# you can using `cat | jq -c .` to stringify JSON
export JWT_SECRET=<retrive from /api/auth/jwks>
kubectl create secret -n baas generic baas-pgrst-secret \
  --from-literal PGRST_JWT_SECRET=${JWT_SECRET?JWT_SECRET is Required}
```

#### Deploy PostgREST

```sh
kubectl apply -f ./000004_pgrst.yaml
```

## Setup BaaS Project

### Create migrations for projects

Create ConfigMap from ./migrations/i3s/ for projects

```sh
kubectl create configmap -n baas-project migrations \
  --from-file=./migrations/i3s/
```
