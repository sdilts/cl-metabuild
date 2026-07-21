(in-package #:metabuild)

(define-compiler (sbcl-compiler "sbcl"))

(defmethod compiler-load-cmd ((compiler sbcl-compiler) lisp-file &key impl-flags exec-flags)
  (format nil "~A --disable-ldb --lose-on-corruption ~{~A ~}--end-runtime-options~{ ~A~} --script ~A"
		  (compiler-path compiler)
		  impl-flags
		  exec-flags
		  lisp-file))

(defmethod compiler-exe-name ((compiler sbcl-compiler))
  "sbcl")

(defmethod compiler-version-args ((compiler sbcl-compiler))
  (list "--version"))

(defmethod init-with-cli-options ((compiler sbcl-compiler) project opts)
  nil)
