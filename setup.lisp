#!/usr/bin/env -S sbcl --script

;; It's safe to use quicklisp for this:
(let ((quicklisp-init (merge-pathnames "quicklisp/setup.lisp"
									   (user-homedir-pathname))))
  (when (probe-file quicklisp-init)
    (load quicklisp-init)))

(require 'asdf)

;; Make the cl-metabuild visible to ASDF:
(let ((cur-directory
	   (make-pathname
		:directory (pathname-directory
					(or *load-truename* *compile-file-pathname*)))))
  (asdf:initialize-source-registry
   (list :source-registry
		 (list :directory cur-directory)
		 :inherit-configuration)))

(asdf:load-system "cl-metabuild")

(metabuild::with-project project
	("cl-metabuild")
  (metabuild::add-compiler-flags
   project "sbcl"
   :exec-flags (list
				"--load"
				(merge-pathnames "quicklisp/setup.lisp"
     							 (user-homedir-pathname))))
  (metabuild::finish-configure project))
