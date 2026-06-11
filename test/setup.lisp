#!/usr/bin/env -S sbcl --script

(require 'asdf)

(asdf:initialize-source-registry
 (list :source-registry
	   (list :directory (make-pathname
						 :directory (pathname-directory (uiop:current-lisp-file-pathname))))
   :inherit-configuration))

(asdf:load-system "static-build")

(static-build::with-project project
	("static-build")
  (static-build::add-features project
	(:hrt-debug :default t)
	:mh-layer-shell)
  (static-build::set-optimization project :debug 3)
  (static-build::add-system-directories project
										#p"foo/"
										#p"bar/")
  (static-build::add-system-trees project
								  #p"tree/")
  (static-build:finish-configure project))
