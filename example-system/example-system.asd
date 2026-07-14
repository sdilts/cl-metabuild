(asdf:defsystem #:example-system
  :description "Example system for testing the static-build tooling"
  :depends-on (#:alexandria)
  :pathname #p"lisp/"
  :components
  ((:file "main")))

;; You don't need to have a separate executable system,
;; but it can make some things a bit easier;
;; just put the :build-operation, :build-pathname
;; and :entry-point options in your main system.
(asdf:defsystem #:example-system/executable
  :build-operation program-op
  ;; The file name of the executable
  :build-pathname "build/test-exec"
  :entry-point "metabuild/example-system::main"
  :depends-on (#:example-system))
