(asdf:defsystem #:cl-metabuild
  :description "Meta build system for Common Lisp that allows a configure-build-install workflow"
  :author "Stuart Dilts"
  :license "MIT"
  :version "0.0.0"
  :pathname "lisp/"
  :build-pathname "cl-metabuild"
  :depends-on (#:uiop
			   #:adopt
			   #:quicklisp
			   #:trivial-gray-streams
			   #:local-time)
  :components ((:module ninja
				:serial t
				:components ((:file "packages")
							 (:file "line-wrapping-stream")
							 (:file "ninja")))
			   (:file "package")
			   (:file "util" :depends-on ("package"))
			   (:file "configure" :depends-on ("package"))
			   (:file "cli"
				:depends-on ("configure" "package-source" "build-state"))
			   (:file "generate"
				:depends-on ("cli" "package-source" "configure" "build-state"
								   "compiler-types"))
			   (:file "package-source" :depends-on ("package" "configure"))
			   (:file "build-state" :depends-on ("package" "configure"))
			   (:file "compiler-types" :depends-on ("package" "configure"))
			   (:module compilers
				:depends-on ("compiler-types")
				:components ((:file "sbcl")
							 (:file "ccl")))
			   (:module sources
				:depends-on ("package-source" "util")
				:components ((:file "quicklisp")))))
