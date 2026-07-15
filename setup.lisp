#!/usr/bin/env -S sbcl --load "/home/stuart/quicklisp/setup.lisp" --script

(require 'asdf)

;; If using quicklisp, load the setup file
;; TODO: make this not needed somehow:
(load "/home/stuart/quicklisp/setup.lisp")

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
   "--load"
   (merge-pathnames "quicklisp/setup.lisp"
     				(user-homedir-pathname)))
  (metabuild::finish-configure project))
