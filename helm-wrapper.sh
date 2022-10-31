#! /bin/sh
    
# helm secrets only supports a few helm commands
if [ $1 = "template" ] || [ $1 = "install" ] || [ $1 = "upgrade" ] || [ $1 = "lint" ] || [ $1 = "diff" ]
then 
    # Helm secrets add some useless outputs to every commands including template, namely
    # 'remove: <secret-path>.dec' for every decoded secrets.
    # As argocd use helm template output to compute the resources to apply, these outputs
    # will cause a parsing error from argocd, so we need to remove them.
    # We cannot use exec here as we need to pipe the output so we call helm in a subprocess and
    # handle the return code ourselves.
    out=$(helm.bin secrets $@) 
    code=$? 
    if [ $code -eq 0 ]; then
        # printf insted of echo here because we really don't want any backslash character processing
        printf '%s\n' "$out" | sed -E "/^removed '.+\.dec'$/d"      
        exit 0
    else
        exit $code
    fi
else
    # helm.bin is the original helm binary
    exec helm.bin $@
fi