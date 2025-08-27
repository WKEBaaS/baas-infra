# just is a command runner, Justfile is very similar to Makefile, but simpler.

source_dir := source_dir()

[group('CNPG')]
create-image-catalog:
    kubectl apply \
      -f https://raw.githubusercontent.com/cloudnative-pg/postgres-containers/main/Debian/ClusterImageCatalog-bookworm.yaml

[group('BaaS')]
setup-cluster:
    kubectl apply -f {{ source_dir }}/000001_db-cluster.yml

[group('BaaS')]
migrate-baas:
    kubectl create configmap -n baas migrations \
      --from-file={{ source_dir }}/migrations/i3s/ \
      --from-file={{ source_dir }}/migrations/baas
    kubectl apply -f {{ source_dir }}/000002_migrate_baas.yaml

[group('BaaS')]
create-auth-secret:
    kubectl create secret -n baas generic baas-auth-secret \
      --from-literal AUTH_SECRET=$(openssl rand -base64 32)

[group('BaaS')]
deploy_auth_service:
    kubectl apply -f {{ source_dir }}/000003_auth.yaml

[group('BaaS')]
create-pgrst-secret:
    kubectl create secret -n baas generic baas-pgrst-secret \
      --from-literal PGRST_JWT_SECRET=${JWT_SECRET?retrive this from auth endpoint /api/auth/jwks}

[group('BaaS-Project')]
create-project-migrations:
    kubectl create configmap -n baas-project migrations \
      --from-file={{ source_dir }}/migrations/i3s/
