#!/usr/bin/env -S sbcl --load "${HOME}/quicklisp/setup.lisp" --script

(require :asdf)

(defun get-cur-filename ()
  (or *load-truename* *compile-file-truename*))

(defun ql-install-dependencies (sys-name)
  (let* ((sys (asdf:find-system sys-name))
         (required (asdf:system-depends-on sys)))
    (format t "~%Install the following dependencies for system ~S?~%~S~%> "
            sys-name required)
    (let ((answer (read-line)))
      (unless (or (string= answer "yes")
                  (string= answer "y"))
        (format t "Not installing dependencies~%")
        (uiop:quit 1)))
    (ql:quickload required)))

(ql-install-dependencies "cl-metabuild")
