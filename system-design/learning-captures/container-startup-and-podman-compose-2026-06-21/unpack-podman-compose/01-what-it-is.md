# 1. What it is

**Podman Compose runs several containers together from one YAML file.**

A *container* is a single isolated process with its own filesystem — your `auth`
service, for example. An *image* is the frozen template a container is started from
(`postgres:16-alpine`). Normally you start containers one at a time. A *compose file*
describes a whole set of them — ports, storage, startup order — and one command brings
them all up.

*Podman* is the engine that runs the containers. *podman-compose* is a small tool that
reads the compose YAML and tells Podman what to create. The YAML format is the same one
Docker uses (the "Compose Spec"), which is why the file looks like a Docker Compose file.
