#!/usr/bin/env -S sbcl --script

(require 'asdf)

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

;; Load quicklisp; hopefully we can remove this reqirement
;; in deployed applications;
(load (merge-pathnames
	   (merge-pathnames #p"quicklisp/setup.lisp" (user-homedir-pathname))))

(let ((src-registry (list :source-registry
						  ;; Make the cl-metabuild system visible to the environment:
						  (list :directory (metabuild-system-dir))
						  ;; Make the example project visible to ASDF:
						  (list :directory (cur-dir))
						  :inherit-configuration)))
  (finish-output)
  (asdf:initialize-source-registry
   src-registry))

(asdf:load-system "cl-metabuild")

(metabuild:with-project project
	;; the name of your system. If there's a separate system
	;; that defines the executable, specify it here:
	("example-system" :exec-system "example-system/executable")
  ;; Set the configuration:
  (metabuild:add-features project
	(:print-name :default t))
  (metabuild::set-optimization project
							   :debug 0 :speed 3 :safety 0)
  ;; Generate the files:
  (metabuild:finish-configure project))
