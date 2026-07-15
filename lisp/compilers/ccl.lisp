(in-package #:metabuild)

(define-compiler (ccl-compiler "ccl"))

(defmethod compiler-load-cmd ((compiler ccl-compiler) lisp-file &key impl-flags exec-flags)
  (format nil "cat ~A | ~A --batch --no-init~{ ~A~}~@[ --~]~{ ~A~}"
		  lisp-file
		  (compiler-path compiler)
		  impl-flags
		  exec-flags
		  exec-flags))

(defmethod compiler-exe-name ((compiler ccl-compiler))
  "ccl")

(defmethod compiler-version-args ((compiler ccl-compiler))
  (list "-V"))

(defmethod init-with-cli-options ((compiler ccl-compiler) project opts)
  nil)
