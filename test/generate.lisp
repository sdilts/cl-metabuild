(defpackage #:static-build/generate-tests
  (:use :cl))

(in-package #:static-build/generate-tests)

(defvar *project-dir* (asdf:system-source-directory (asdf:find-system "example-system")))
  ;; (merge-pathnames
  ;;  #p"example-system/"
  ;;  (make-pathname
  ;; 	:directory (pathname-directory (uiop:current-lisp-file-pathname))))
  ;; )

(defmacro with-source-registry (&body body)
  (let ((prev-config (gensym "prev-config")))
	`(let ((,prev-config asdf:*source-registry-parameter*))
	  ,@body
	  (asdf:initialize-source-registry ,prev-config))))

(defun clean-project (project)
  (uiop:delete-directory-tree (static-build::exec-project-build-dir project)))

(defmacro with-execute-build (project &body body)
  `(with-source-registry
	(let ((,project (static-build::%init-exec-project
					(asdf:find-system "example-system")
					nil
					*project-dir*
					*project-dir*
					#p"build/")))
	  ,@body
	  (static-build:finish-configure ,project))))
