# BaaS Infra

<!-- toc -->

- [Prepare Namespaces](#prepare-namespaces)
- [Setup BaaS Database](#setup-baas-database)

<!-- tocstop -->

> [!CAUTION]
> Please Setup Cloud First

## Prepare Namespaces

1. BaaS
2. BaaS-Project

```bash
kubectl create namespace baas
kubectl create namespace baas-project
```

## Setup BaaS Database

```bash
# kubectl apply -f ./db/db-cluster.yml
just setup-db
```
