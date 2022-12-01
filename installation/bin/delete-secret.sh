#!/bin/bash

# Remove secret created in the presync hook
kubectl -n argo delete secret age