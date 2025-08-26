# BaaS Infra

<!-- toc -->

- [Prepare Namespaces (if not exist)](#prepare-namespaces-if-not-exist)
- [Setup BaaS Services](#setup-baas-services)
  * [Setup Database](#setup-database)
    + [Init Cluster](#init-cluster)
    + [Migrate BaaS Database](#migrate-baas-database)
  * [Setup Auth Service](#setup-auth-service)

<!-- tocstop -->

> [!CAUTION]
> Please Setup Cloud First

## Prepare Namespaces (if not exist)

1. BaaS
2. BaaS-Project

```bash
kubectl create namespace baas
kubectl create namespace baas-project
```

## Setup BaaS Services

### Setup Database

#### Init Cluster

Create [CloudNative-PG](https://github.com/cloudnative-pg/cloudnative-pg) Cluster, Database, ImageCatalog

```bash
just create-image-catalog
just setup-cluster
```

#### Migrate BaaS Database

Create ConfigMap from migrations and running migrations with [dbmate](https://github.com/amacneil/dbmate)

```sh
just migrate-baas
```

### Setup Auth Service

```bash
create-auth-secret:
  kubectl create secret -n baas generic baas-auth-secret \
    --from-literal AUTH_SECRET=$(openssl rand -base64 32)
```
