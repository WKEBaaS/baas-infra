# just is a command runner, Justfile is very similar to Makefile, but simpler.

source_dir := source_dir()

[group('BaaS')]
setup-db:
  kubectl apply -f {{source_dir}}/db/db-cluster.yml
