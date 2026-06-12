(asdf:defsystem #:static-build
  :description "Meta build system for Common Lisp that allows a configure-build-install workflow"
  :author "Stuart Dilts"
  :license "MIT"
  :version "0.0.0"
  :pathname "lisp/"
  :depends-on (#:uiop
			   #:adopt
			   #:quicklisp
			   #:local-time)
  :components ((:file "package")
			   (:file "util" :depends-on ("package"))
			   (:file "configure" :depends-on ("package"))
			   (:file "cli" :depends-on ("configure" "package-source"))
			   (:file "generate" :depends-on ("cli" "package-source" "configure"))
			   (:file "package-source" :depends-on ("package" "configure"))
			   (:module sources
				:depends-on ("package-source" "util")
				:components ((:file "quicklisp")))))
