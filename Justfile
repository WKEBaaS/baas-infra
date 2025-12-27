# Justfile for BaaS Infrastructure Deployment

# This file uses 'just' (a command runner) to simplify Kubernetes deployments.
# For more information on 'just', visit: https://github.com/casey/just

# External Tools:
# - kubectl: Kubernetes command-line tool.
# - pwgen: To generate random passwords (used for Postgres authenticator secret).
# - openssl: To generate base64 encoded secrets.

[group('CNPG')]
# Creates a Cluster Image Catalog for CloudNative-PG, defining available PostgreSQL container images.
create-image-catalog:
    kubectl apply \
      -f https://raw.githubusercontent.com/cloudnative-pg/postgres-containers/main/Debian/ClusterImageCatalog-bookworm.yaml

[group('BaaS')]
# Deploys the entire BaaS infrastructure using Kustomize.
# Before running this command, ensure you have created and populated the necessary
# secret.env and config.env files in their respective base component directories.
deploy:
    # Required secret.env files:
    # - base/baas-auth/secret.env (from base/baas-auth/secret.env.example)
    # - base/baas-pgrst/secret.env (from base/baas-pgrst/secret.env.example)
    # - base/baas-api/secret.env (from base/baas-api/secret.env.example)
    kubectl apply -k .
