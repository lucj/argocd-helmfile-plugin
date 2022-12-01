#!/bin/bash

# Remove secret created in the presync hook
kubectl -n argocd delete secret age