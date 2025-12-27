# BaaS Infra

<!-- toc -->

- [Prepare Namespaces (if not exist)](#prepare-namespaces-if-not-exist)
- [Setup Environment Variables](#setup-environment-variables)
- [Deploy BaaS Infrastructure with Kustomize](#deploy-baas-infrastructure-with-kustomize)
  * [Prepare Secrets and ConfigMaps](#prepare-secrets-and-configmaps)
  * [Deploy Kustomize Base](#deploy-kustomize-base)

<!-- tocstop -->

> [!CAUTION]
> Please Setup Cloud First

## Prepare Namespaces (if not exist)

```sh
kubectl create namespace baas
kubectl create namespace baas-project
```

## Setup Environment Variables

This project uses Kustomize for deployment. Before deploying, you need to prepare several environment files for secrets and configMaps. These files should be created and filled with appropriate values.

- **baas-auth secrets:** Fill `base/baas-auth/secret.env`.
- **baas-pgrst secrets:** Fill `base/baas-pgrst/secret.env`.
- **baas-api S3 credentials:** Fill `base/baas-api/secret.env`.
- **(Optional) BaaS Postgres Authenticator Secret**: Create a secret for the Postgres authenticator role.

```sh
# Example for baas-auth/secret.env:
# BETTER_AUTH_SECRET=your_super_secret_key

# Example for baas-pgrst/secret.env:
# PGRST_JWT_SECRET=<retrive this from auth endpoint /api/auth/jwks>

# Example for baas-api/secret.env:
# S3_SECRETACCESSKEY=your_s3_secret_access_key
```

## Deploy BaaS Infrastructure with Kustomize

### Prepare Secrets and ConfigMaps

Ensure you have created and filled the `secret.env` and `config.env` files in their respective component directories (e.g., `base/baas-auth/secret.env` or `base/baas-auth/config.env`). Kustomize will use these files to generate Kubernetes Secrets and ConfigMaps.

### Deploy Kustomize Base

Deploy the entire BaaS infrastructure using Kustomize:

```sh
kubectl apply -k .
# Or use the Justfile command
# just deploy
```
