# Docker and Kubernetes

The plugin adds **Docker** (`docker:///`) to the Change Drive list (Alt+F1 / Alt+F2). It runs the `docker` program (and `kubectl` for pods), so both must be in PATH and able to reach the daemon or the cluster.

| Folder | Content |
|---|---|
| `containers` | every container, colored by state: green running, grey stopped, yellow paused or restarting |
| `images` | one file per image; F3 shows `docker image inspect`, F8 removes the image |
| `kubernetes` | namespaces, then the pods of a namespace, colored by phase |

## Inside a container or pod

| Item | Content |
|---|---|
| `info.txt` | `docker inspect` of the container, `kubectl describe pod` of the pod |
| `logs.txt` | the last 2000 lines of the log |
| `fs` | the files of the container or pod |

In `fs` the usual keys work: F3 views a file, F4 edits and saves it, F5 copies between the container and a local folder (`docker cp`, `kubectl cp`), F7 makes a folder, F8 deletes. Listing, viewing, editing and deleting run commands inside the container (`find` or `ls`, `cat`, `sh`, `rm`), so a running container with these tools is needed; copying also works for a stopped Docker container. Moving and copying between two containers are not supported. F8 on a container removes it with `docker rm -f`; on a pod it deletes the pod.

The **Plugins** menu starts, stops, restarts, pauses and unpauses the container under the cursor.

A `/` in a name is written `%2F`.
