# just is a command runner, Justfile is very similar to Makefile, but simpler.

source_dir := source_dir()

[group('BaaS')]
setup-db:
  kubectl apply -f {{source_dir}}/db/db-cluster.yml

create-auth-secret:
  kubectl create secret -n baas generic baas-auth-secret \
    --from-literal AUTH_SECRET=$(openssl rand -base64 32)

create-pgrst-secret:
  kubectl create secret -n baas generic baas-pgrst-secret \
    --from-literal PGRST_JWT_SECRET=${JWT_SECRET?retrive this from auth endpoint /api/auth/jwks}
