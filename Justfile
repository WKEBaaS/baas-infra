# just is a command runner, Justfile is very similar to Makefile, but simpler.

[group('CNPG')]
create-image-catalog:
    kubectl apply \
      -f https://raw.githubusercontent.com/cloudnative-pg/postgres-containers/main/Debian/ClusterImageCatalog-bookworm.yaml

[group('BaaS')]
deploy:
    # Make sure you have created the following files from their .example counterparts:
    # - base/baas-auth/secret.env
    # - base/baas-pgrst/secret.env
    # - base/baas-api/secret.env
    kubectl apply -k .
