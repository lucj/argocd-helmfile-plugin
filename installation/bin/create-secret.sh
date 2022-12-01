#!/bin/bash

# Create a sops / age secret key if none already exists
if [[ -f ./conf/key.txt ]]; then
  echo "age key already exists in ./conf/key.txt"
else
  age-keygen > ./conf/key.txt
fi

# Create secret to give Argo access to the age key
kubectl create ns argocd || true
kubectl -n argocd create secret generic age --from-file=key.txt=./conf/key.txt || true