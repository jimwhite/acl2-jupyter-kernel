#!/bin/sh

# Start the ACL2 Jupyter Kernel.
#
# No sbcl-restart, no LD, no set-raw-mode-on!.
# start sets up its own persistent LP context directly.

set -e

CONNECTION_FILE="$1"
if [ -z "${CONNECTION_FILE}" ]; then
    echo "Usage: $0 <connection-file>" >&2
    exit 1
fi

ACL2_HOME="${ACL2_HOME:-/home/acl2}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
ACL2_QL_BUNDLE="${ACL2_HOME}/books/quicklisp/bundle/software"

export SBCL_HOME="${SBCL_HOME:-/usr/local/lib/sbcl/}"

# Pre-load babel from the ACL2 books' quicklisp bundle so the kernel
# and ACL2 books use the same version.  Without this, the kernel's
# quicklisp loads a newer babel with incompatible defconstant values,
# causing defconstant-uneql when ACL2 books later reload babel from
# their bundle via include-raw.
exec /usr/local/bin/sbcl \
    --tls-limit 16384 --dynamic-space-size 32000 --control-stack-size 64 --disable-ldb \
    --core "${ACL2_HOME}/saved_acl2.core" \
    --end-runtime-options \
    --no-userinit \
    --load "${QUICKLISP_SETUP}" \
    --eval "(let ((d (car (directory \"${ACL2_QL_BUNDLE}/babel-*/\")))) (when d (push d asdf:*central-registry*) (asdf:load-system \"babel\")))" \
    --eval '(ql:quickload :acl2-jupyter-kernel :silent t)' \
    --eval "(acl2-jupyter-kernel:start \"${CONNECTION_FILE}\")"
