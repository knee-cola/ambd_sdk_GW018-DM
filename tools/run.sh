#!/bin/bash

docker run --rm --name gw018-builder-flasher \
  --volume $PWD../:/workspace/ambd_sdk_GW018-DM \
  -ti --entrypoint /bin/bash \
  gw018-builder-flasher:latest
