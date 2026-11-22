;;;; ACL2 Jupyter Kernel - Installer
;;;;
;;;; Installs the ACL2 Jupyter kernelspec so Jupyter can find and launch it.
;;;;
;;;; kernel.json argv calls the Lisp implementation directly with the
;;;; saved_acl2 core/image, loads Quicklisp and the kernel system via
;;;; --eval, then starts the kernel.  No shell script wrapper.
;;;;
;;;; Implementation-specific argv construction is dispatched via
;;;; UIOP:IMPLEMENTATION-TYPE.

(in-package #:acl2-jupyter)

;;; ---------------------------------------------------------------------------
;;; Constants
;;; ---------------------------------------------------------------------------

(defvar +display-name+
  (or (uiop:getenv "ACL2_JUPYTER_DISPLAY_NAME") "ACL2"))
(defvar +language+ "acl2")
(defvar +kernel-name+
  (or (uiop:getenv "ACL2_JUPYTER_KERNEL_NAME") "acl2"))

;;; ---------------------------------------------------------------------------
;;; Path Discovery  (implementation-neutral, uses UIOP)
;;; ---------------------------------------------------------------------------

(defun acl2-script-path ()
  "Return the path to the saved_acl2 launcher script."
  (or (uiop:getenv "ACL2")
      (namestring
       (merge-pathnames "saved_acl2"
                        (uiop:ensure-directory-pathname
                         (or (uiop:getenv "ACL2_HOME") "/home/acl2"))))))

(defun shell-split (line)
  "Split LINE into shell-like words, honoring single and double quotes."
  (let ((words nil)
        (current (make-string-output-stream))
        (quote nil)
        (in-word nil))
    (flet ((finish-word ()
             (when in-word
               (push (get-output-stream-string current) words)
               (setf current (make-string-output-stream)
                     in-word nil))))
      (loop for ch across line
            do (cond
                 ((and quote (char= ch quote))
                  (setf quote nil
                        in-word t))
                 (quote
                  (write-char ch current))
                 ((or (char= ch #\") (char= ch #\'))
                  (setf quote ch
                        in-word t))
                 ((member ch '(#\Space #\Tab))
                  (finish-word))
                 (t
                  (write-char ch current)
                  (setf in-word t))))
      (finish-word))
    (nreverse words)))

(defun acl2-script-exec-line ()
  "Return the words of the first `exec' line in the saved_acl2 script.
   Returns NIL when the script cannot be read or has no exec line."
  (handler-case
      (with-open-file (stream (acl2-script-path))
        (loop for line = (read-line stream nil nil)
              while line
              when (and (>= (length line) 4)
                        (string= (subseq line 0 4) "exec"))
                return (shell-split (subseq line 4))))
    (error () nil)))

(defun option-value (args option)
  "Return the value following OPTION in ARGS, also accepting OPTION=value."
  (loop for tail on args
        for arg = (car tail)
        when (string= arg option)
          return (cadr tail)
        when (and (> (length arg) (length option))
                  (char= (char arg (length option)) #\=)
                  (string= option arg :end2 (length option)))
          return (subseq arg (1+ (length option)))))

(defun find-lisp-runtime ()
  "Return the absolute path to the Lisp executable used by saved_acl2.
   Falls back to searching for the current implementation on PATH."
  (or (let* ((args (acl2-script-exec-line))
             (exe (first args)))
        (when (and exe (probe-file exe))
          (namestring (probe-file exe))))
      (let ((impl (string-downcase (symbol-name (uiop:implementation-type)))))
        (string-right-trim
         '(#\Newline #\Space #\Return)
         (uiop:run-program (list "which" impl) :output :string)))))

(defun find-acl2-core ()
  "Return the path to the ACL2 core/image used by saved_acl2.
   SBCL scripts pass it with --core; CCL scripts pass it with -I / --image-name."
  (let* ((args (acl2-script-exec-line))
         (core (or (option-value args "--core")
                   (option-value args "-I")
                   (option-value args "--image-name"))))
    (unless (and core (probe-file core))
      (error "Cannot find ACL2 core from script ~A" (acl2-script-path)))
    (namestring (probe-file core))))

(defun ccl-runtime-args ()
  "Return the CCL runtime arguments from the saved_acl2 script.
   Drops the executable, the -I image argument (added separately), the
   -e (acl2-default-restart) form (the kernel performs startup itself),
   and the trailing \"$@\"."
  (let ((skip-next nil))
    (loop for arg in (rest (acl2-script-exec-line))
          if skip-next
            do (setf skip-next nil)
          else if (member arg '("-I" "--image-name" "-e" "--eval")
                         :test #'string=)
            do (setf skip-next t)
          else unless (string= arg "$@")
            collect arg)))

(defun find-quicklisp-setup ()
  "Return the path to quicklisp/setup.lisp."
  (let ((setup (merge-pathnames "quicklisp/setup.lisp"
                                (uiop:ensure-directory-pathname
                                 (user-homedir-pathname)))))
    (unless (probe-file setup)
      (error "Cannot find quicklisp setup at ~A" setup))
    (namestring setup)))

;;; ---------------------------------------------------------------------------
;;; Installer Classes
;;; ---------------------------------------------------------------------------

(defclass acl2-installer (jupyter:installer)
  ((lisp-runtime :initarg :lisp-runtime :accessor installer-lisp-runtime)
   (core-path :initarg :core-path :accessor installer-core-path)
   (quicklisp-setup :initarg :quicklisp-setup :accessor installer-quicklisp-setup))
  (:default-initargs
    :class 'kernel
    :language +language+
    :debugger nil
    :resources nil
    :systems '(:acl2-jupyter-kernel)))


(defclass acl2-system-installer (jupyter:system-installer acl2-installer)
  ()
  (:documentation "ACL2 Jupyter kernel system installer."))


(defclass acl2-user-installer (jupyter:user-installer acl2-installer)
  ()
  (:documentation "ACL2 Jupyter kernel user installer."))


(defclass acl2-user-image-installer (jupyter:user-image-installer acl2-installer)
  ()
  (:documentation "ACL2 Jupyter kernel user image installer."))


;;; ---------------------------------------------------------------------------
;;; Command Line Generation  (implementation-dispatched)
;;; ---------------------------------------------------------------------------

(defgeneric make-kernel-argv (impl lisp-runtime core-path quicklisp-setup)
  (:documentation "Build the argv list for kernel.json, dispatched on IMPL
   (a keyword like :SBCL or :CCL)."))

(defun kernel-start-form ()
  "Build the (acl2-jupyter-kernel:start ...) form with the configured flags."
  (let ((full-world  (equal (or (uiop:getenv "ACL2_JUPYTER_FULL_WORLD") "0") "1"))
        (event-forms (equal (or (uiop:getenv "ACL2_JUPYTER_EVENT_FORMS") "0") "1"))
        (deep-events (equal (or (uiop:getenv "ACL2_JUPYTER_DEEP_EVENTS") "0") "1"))
        (exworld     (equal (or (uiop:getenv "ACL2_JUPYTER_EXWORLD") "0") "1")))
    (format nil "(acl2-jupyter-kernel:start \"~A\" :event-forms ~A :full-world ~A :deep-events ~A :exworld ~A)"
            "{connection_file}"
            (if event-forms "t" "nil")
            (if full-world  "t" "nil")
            (if deep-events "t" "nil")
            (if exworld     "t" "nil"))))

(defun babel-preload-eval ()
  "Form that pre-loads babel from ACL2's books quicklisp bundle.
   Prevents defconstant-uneql when books later load their own babel."
  (format nil "(let ((d (car (directory \"~A/books/quicklisp/bundle/software/babel-*/\")))) (when d (push d asdf:*central-registry*) (asdf:load-system \"babel\")))"
          (or (uiop:getenv "ACL2_HOME") "/home/acl2")))

(defmethod make-kernel-argv ((impl (eql :sbcl)) lisp-runtime core-path
                             quicklisp-setup)
  (list lisp-runtime
        "--tls-limit" "16384"
        "--dynamic-space-size" "32000"
        "--control-stack-size" "64"
        "--disable-ldb"
        "--core" core-path
        "--end-runtime-options"
        "--no-userinit"
        ;; Quicklisp setup.lisp loads ASDF, then we clear the stale
        ;; source-registry cached in the saved ACL2 image so it
        ;; picks up the current source-registry.conf.d at runtime.
        "--load" quicklisp-setup
        "--eval" "(asdf:clear-source-registry)"
        ;; Pre-load babel from the ACL2 books' quicklisp bundle so the
        ;; kernel and ACL2 books use the same version (prevents
        ;; defconstant-uneql when books load babel via include-raw).
        "--eval" (babel-preload-eval)
        "--eval" "(ql:quickload :acl2-jupyter-kernel :silent t)"
        "--eval" (kernel-start-form)))

(defmethod make-kernel-argv ((impl (eql :ccl)) lisp-runtime core-path
                             quicklisp-setup)
  ;; CCL is launched against the saved ACL2 heap image with -I.  Runtime
  ;; options (stack size, terminal encoding) come from the saved_acl2
  ;; script, minus its -I image and (acl2-default-restart) eval, which the
  ;; kernel start function performs itself.
  (append (list lisp-runtime
                "-n"
                "-I" core-path)
          (ccl-runtime-args)
          (list "--load" quicklisp-setup
                "--eval" "(asdf:clear-source-registry)"
                "--eval" (babel-preload-eval)
                "--eval" "(ql:quickload :acl2-jupyter-kernel :silent t)"
                "--eval" (kernel-start-form))))

(defmethod jupyter:command-line ((instance acl2-installer))
  "Get the command line for an ACL2 kernel installation."
  (make-kernel-argv (uiop:implementation-type)
                    (installer-lisp-runtime instance)
                    (installer-core-path instance)
                    (installer-quicklisp-setup instance)))

;;; ---------------------------------------------------------------------------
;;; Environment Variables  (implementation-dispatched)
;;; ---------------------------------------------------------------------------

(defgeneric make-kernel-env (impl)
  (:documentation "Return a plist of environment variables for kernel.json,
   dispatched on IMPL (a keyword like :SBCL or :CCL)."))

(defmethod make-kernel-env ((impl (eql :sbcl)))
  (let ((sbcl-home (or (uiop:getenv "SBCL_HOME") "/usr/local/lib/sbcl/")))
    (list :object-plist
          "SBCL_HOME" sbcl-home)))

(defmethod make-kernel-env ((impl (eql :ccl)))
  (let* ((args (acl2-script-exec-line))
         (exe (first args))
         (ccl-home
           (or (uiop:getenv "CCL_DEFAULT_DIRECTORY")
               (and exe
                    (namestring
                     (uiop:pathname-directory-pathname
                      (uiop:parse-native-namestring exe))))
               "/usr/local/lib/ccl/")))
    (list :object-plist
          "CCL_DEFAULT_DIRECTORY" ccl-home)))

;;; ---------------------------------------------------------------------------
;;; Kernel Spec Override
;;; ---------------------------------------------------------------------------

(defun install-acl2-spec (instance)
  "Install kernel.json for the ACL2 kernel."
  (let ((spec-path (jupyter:installer-path instance :spec)))
    (format t "Installing kernel spec file ~A~%" spec-path)
    (with-open-file (stream spec-path :direction :output :if-exists :supersede)
      (shasht:write-json
        (list :object-plist
          "argv" (jupyter:command-line instance)
          "display_name" (jupyter:installer-display-name instance)
          "language" (jupyter:installer-language instance)
          "interrupt_mode" "message"
          "metadata" :empty-object
          "env" (make-kernel-env (uiop:implementation-type)))
        stream))))


;;; ---------------------------------------------------------------------------
;;; Public Install Functions
;;; ---------------------------------------------------------------------------

(defun install (&key system local prefix jupyter program
                     lisp-runtime core-path quicklisp-setup)
  "Install the ACL2 Jupyter kernel.
   Paths are auto-detected from the running environment unless overridden.
   - SYSTEM: if T, install system-wide; otherwise install for current user
   - LOCAL: use /usr/local/share instead of /usr/share for system installs
   - PREFIX: directory prefix for packaging
   - JUPYTER: Jupyter directory override
   - PROGRAM: program directory override
   - LISP-RUNTIME: path to Lisp executable (auto-detected)
   - CORE-PATH: path to saved_acl2.core (auto-detected)
   - QUICKLISP-SETUP: path to quicklisp/setup.lisp (auto-detected)"
  (let ((instance (make-instance
                    (if system 'acl2-system-installer 'acl2-user-installer)
                    :display-name +display-name+
                    :kernel-name +kernel-name+
                    :lisp-runtime (or lisp-runtime (find-lisp-runtime))
                    :core-path (or core-path (find-acl2-core))
                    :quicklisp-setup (or quicklisp-setup (find-quicklisp-setup))
                    :local local
                    :prefix prefix
                    :jupyter-path jupyter
                    :program-path program)))
    (jupyter::install-directories instance)
    (install-acl2-spec instance)
    (jupyter::install-resources instance)
    (jupyter::install-local-systems instance)))

(defun install-image (&key prefix jupyter program)
  "Install the ACL2 kernel based on a saved image of the current process."
  (jupyter:install
    (make-instance 'acl2-user-image-installer
      :display-name +display-name+
      :kernel-name +kernel-name+
      :prefix prefix
      :jupyter-path jupyter
      :program-path program)))
