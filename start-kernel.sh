#!/bin/sh

# Start the ACL2 Jupyter Kernel.
#
# Works with either an SBCL- or CCL-based saved_acl2.  The implementation is
# detected from the saved_acl2 launcher script; override with
# ACL2_JUPYTER_LISP=sbcl or ACL2_JUPYTER_LISP=ccl.
#
# No sbcl-restart, no LD, no set-raw-mode-on!.  start sets up its own
# persistent LP context directly.

set -e

CONNECTION_FILE="$1"
if [ -z "${CONNECTION_FILE}" ]; then
    echo "Usage: $0 <connection-file>" >&2
    exit 1
fi

ACL2_HOME="${ACL2_HOME:-/home/acl2}"
ACL2_SCRIPT="${ACL2:-${ACL2_HOME}/saved_acl2}"
QUICKLISP_SETUP="${QUICKLISP_SETUP:-${HOME}/quicklisp/setup.lisp}"
ACL2_QL_BUNDLE="${ACL2_HOME}/books/quicklisp/bundle/software"

EXEC_LINE=$(grep -m 1 '^exec ' "${ACL2_SCRIPT}" || true)
IMPL="${ACL2_JUPYTER_LISP:-}"
if [ -z "${IMPL}" ]; then
    case "${EXEC_LINE}" in
        *--core*) IMPL=sbcl ;;
        *-I*)     IMPL=ccl ;;
        *)        IMPL=sbcl ;;
    esac
fi

BABEL_PRELOAD="(let ((d (car (directory \"${ACL2_QL_BUNDLE}/babel-*/\")))) (when d (push d asdf:*central-registry*) (asdf:load-system \"babel\")))"
START_FORM="(acl2-jupyter-kernel:start \"${CONNECTION_FILE}\" :event-forms ${ACL2_JUPYTER_EVENT_FORMS:-1} :full-world nil :deep-events nil :exworld nil)"

case "${IMPL}" in
  sbcl)
    # Locate the ACL2 core from the --core argument.
    ACL2_CORE=$(printf '%s\n' "${EXEC_LINE}" | sed -n 's/.*--core "\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/p')
    if [ -z "${ACL2_CORE}" ] || [ ! -f "${ACL2_CORE}" ]; then
        echo "ERROR: Cannot find saved_acl2 core in ${ACL2_SCRIPT}" >&2
        exit 1
    fi
    export SBCL_HOME="${SBCL_HOME:-/usr/lib/sbcl/}"
    exec "${SBCL:-/usr/bin/sbcl}" \
        --tls-limit 16384 --dynamic-space-size 32000 --control-stack-size 64 --disable-ldb \
        --core "${ACL2_CORE}" \
        --end-runtime-options \
        --no-userinit \
        --load "${QUICKLISP_SETUP}" \
        --eval "(asdf:clear-source-registry)" \
        --eval "${BABEL_PRELOAD}" \
        --eval '(ql:quickload :acl2-jupyter-kernel :silent t)' \
        --eval "${START_FORM}"
    ;;
  ccl)
    CCL_EXE=$(printf '%s\n' "${EXEC_LINE}" | sed -n 's/^exec "\([^"]*\)".*/\1/p')
    ACL2_IMAGE=$(printf '%s\n' "${EXEC_LINE}" | sed -n 's/.*-I "\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/p')
    if [ -z "${CCL_EXE}" ]; then CCL_EXE="${CCL:-/usr/local/lib/ccl/arm64cl}"; fi
    if [ -z "${ACL2_IMAGE}" ] || [ ! -f "${ACL2_IMAGE}" ]; then
        echo "ERROR: Cannot find ACL2 heap image in ${ACL2_SCRIPT}" >&2
        exit 1
    fi
    export CCL_DEFAULT_DIRECTORY="${CCL_DEFAULT_DIRECTORY:-$(dirname "${CCL_EXE}")}"
    exec "${CCL_EXE}" \
        -n \
        -I "${ACL2_IMAGE}" \
        -Z 64M -K ISO-8859-1 \
        --load "${QUICKLISP_SETUP}" \
        --eval "(asdf:clear-source-registry)" \
        --eval "${BABEL_PRELOAD}" \
        --eval '(ql:quickload :acl2-jupyter-kernel :silent t)' \
        --eval "${START_FORM}"
    ;;
  *)
    echo "ERROR: Unsupported Lisp implementation: ${IMPL}" >&2
    exit 1
    ;;
esac
