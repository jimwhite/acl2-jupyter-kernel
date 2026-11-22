# ACL2 Jupyter Kernel

A native ACL2 kernel for Jupyter.  It runs **inside** the ACL2 process (no
subprocess, no prompt scraping) on **SBCL** or **CCL**, and speaks the Jupyter
wire protocol through [common-lisp-jupyter](https://github.com/yitzikc/common-lisp-jupyter).

Design and internals: [DESIGN.md](DESIGN.md).  Portability notes and the
`exworld` metadata work live in [DESIGN-NOTES.md](DESIGN-NOTES.md) and
[EXWORLD-METADATA-PLAN.md](EXWORLD-METADATA-PLAN.md).

## Prerequisites

- An ACL2 built on SBCL or CCL (a `saved_acl2` launcher and its core/image).
- Quicklisp: `quicklisp/setup.lisp` must exist (the kernel is quickloaded at
  startup).  The ACL2 books bundle (`books/quicklisp/bundle/software`) is used
  for a shared `babel`.
- `libzmq` (and `libczmq`) system libraries, plus a C compiler for `pzmq`.

## Install

From this directory:

```sh
# The launcher determines the implementation (SBCL --core or CCL -I).
ACL2=/workspaces/acl2/saved_acl2 \
ACL2_HOME=/workspaces/acl2 \
QUICKLISP_SETUP="$HOME/quicklisp/setup.lisp" \
  ./install-kernelspec.sh
```

The spec is installed as `acl2`.  To keep a second implementation available:

```sh
ACL2=/path/to/sbcl-saved_acl2 \
ACL2_HOME=/path/to/acl2 \
ACL2_JUPYTER_KERNEL_NAME=acl2-sbcl \
ACL2_JUPYTER_DISPLAY_NAME='ACL2 (SBCL)' \
QUICKLISP_SETUP="$HOME/quicklisp/setup.lisp" \
  ./install-kernelspec.sh
```

`install-kernelspec.sh` copies the sources into
`~/quicklisp/local-projects/acl2-jupyter-kernel`, so later edits here are
picked up by `quickload` after copying again (the script does this).

`start-kernel.sh <connection-file>` launches the kernel directly for debugging;
it detects SBCL/CCL from the launcher, or honors `ACL2_JUPYTER_LISP`.

## Test

```sh
pip install jupyter_client pytest
pytest -q test_kernel.py test_metadata.py
```

The tests use the kernelspec named `acl2`.  To test the other implementation,
install it as `acl2` (or temporarily point the name at it) and rerun.  The
`test_dual.py` and `test_bridge_include.py` modules additionally require the
ACL2 Bridge Python client.

## Notes

- **One Lisp per books tree.**  ACL2 book certificates and compiled files are
  tied to the implementation that produced them.  Use CCL-certified books with
  a CCL ACL2 image and SBCL-certified books with an SBCL image; do not mix
  them in one repository.
- `acl2-default-restart` is called with `called-by-lp = T`.  On CCL this
  suppresses the built-in `(lp)` call; the kernel installs its own persistent
  LP context.
- Cell metadata (`application/vnd.acl2.events+json`) reports the events a cell
  added and, with `:event-forms t`, the original source forms.
