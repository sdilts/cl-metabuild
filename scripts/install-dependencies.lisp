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

(defun cur-dir ()
  (make-pathname
   :directory (pathname-directory (or *load-truename* *compile-file-pathname*))))

(defun metabuild-system-dir ()
  "Get the parent directory of this file. Will only work if this
file is loaded or compiled, and not when interactively evaluated."
  (let* ((cur-dir (cur-dir))
		 (path-type (car (pathname-directory cur-dir)))
		 (dir-list (cons path-type (reverse
									(cdr (reverse
										  (cdr (pathname-directory cur-dir))))))))
	(make-pathname :directory dir-list)))

(let ((src-registry (list :source-registry
						  ;; Make the cl-metabuild system visible to the environment:
						  (list :directory (metabuild-system-dir))
						  ;; Make the example project visible to ASDF:
						  (list :directory (cur-dir))
						  :inherit-configuration)))
  (finish-output)
  (asdf:initialize-source-registry
   src-registry))

(ql-install-dependencies "cl-metabuild")
