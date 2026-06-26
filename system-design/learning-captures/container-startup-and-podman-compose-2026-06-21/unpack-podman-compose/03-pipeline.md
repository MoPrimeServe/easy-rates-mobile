# 3. The pipeline — what `podman-compose up` actually does

Cold start, in order:

1. **Parse the YAML.** Resolve every `${VAR}` from the shell and the special `.env` file.
   Expand anchors (`*node-healthcheck`).
2. **Create the network** (`easyrates_net`) and start its DNS resolver.
3. **Create the named volumes** (`pgdata`, `redisdata`, `pgadmin_data`) if they don't
   exist. Existing ones keep their data.
4. **Pull or build images** for each service.
5. **Start containers in `depends_on` order.** A service with no dependencies starts
   first. A service waits at its `depends_on` gate.
6. **Run healthchecks.** For a service whose dependents asked for `service_healthy`, run
   its healthcheck on the interval until it passes — *then* release the dependents.
7. **Attach bind mounts and env vars** as each container starts.

Teardown is the reverse: `podman-compose down` stops containers and removes the network.
Named volumes **survive** unless you add `-v`. That's why DB data persists across restarts.
