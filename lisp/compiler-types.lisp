(in-package #:metabuild)

(defgeneric compiler-load-cmd (compiler-spec lisp-file &key impl-flags exec-flags)
  (:documentation "Return a format string that represents a command line invocation executing FILE"))

(defgeneric compiler-exe-name (compiler-spec)
  (:documentation "Return the common name of the compiler executable"))

(defgeneric compiler-version-args (compiler-spec)
  (:documentation "Return the arguments needed to get the compiler version from the command line"))

(defstruct compiler
  (name nil :type string)
  (path nil :type (or null string))
  (version nil :type (or null string)))

(defvar *compiler-impls* (make-hash-table :test 'equal))

(defmacro define-compiler ((name designator)
						   &body direct-slots)
  (let ((ds (gensym "designator"))
		(constructor-name (intern (string-upcase
								   (concatenate 'string
												"make-"
												(symbol-name name))))))
	`(eval-when (:compile-toplevel :load-toplevel :execute)
	   (let ((,ds ,designator))
		 (defstruct (,name (:include compiler))
		   ,@direct-slots)
		 (setf (gethash ,ds *compiler-impls*)
			   (,constructor-name :name ,ds))))))

(defun detect-compiler ()
  (let ((impl-string (lisp-implementation-type)))
	(cond
	  ((string= impl-string "SBCL")
	   "sbcl")
	  ((string= impl-string "Clozure Common Lisp")
	   "ccl"))))

(defun get-compiler-opts ()
  (let ((type-opts nil)
		(valid-type-keys nil))
	(loop :for k :being :the :hash-key
			:using (hash-value s) :of *compiler-impls*
		  do (when (package-source-available-p s)
			   (push (get-cli-options s) type-opts))
			 (push k valid-type-keys))
	(cons
	 (adopt:make-group
	  'compiler-info
	  :title "Compiler Info"
	  :options (list
				(adopt:make-option
				 'compiler-impl
				 :parameter "COMPILER"
				 :long "compiler"
				 :short #\c
				 :initial-value (detect-compiler)
				 :help (format nil "Compiler to use.
Valid options are~{ ~A~}" valid-type-keys)
				 :reduce (lambda (prev new)
						   (declare (ignore prev))
						   new))
				(adopt:make-option
				 'compiler-path
				 :parameter "PATH"
				 :long "compiler-path"
				 :help "The path to the compiler."
				 :reduce (lambda (prev new)
						   (declare (ignore prev))
						   new))))
	 type-opts)))

(defun %find-compiler-exe (impl opts)
  (declare (optimize (debug 3)))
  (flet ((run-program (args)
		   (string-trim '(#\Newline #\Space)
						(uiop:run-program args
										  :output :string))))
	(let* ((from-opts (gethash 'compiler-path opts))
		   common-name)
	  (handler-case
		  (cond
			(from-opts
			 (setf common-name from-opts)
			 (values
			  from-opts
			  (run-program (cons from-opts (compiler-version-args impl)))))
			(t
			 (setf common-name (compiler-exe-name impl))
			 (let ((path (run-program (list "which" common-name))))
			   (values
				path
				(run-program (cons path (compiler-version-args impl)))))))
		(uiop/run-program:subprocess-error ()
		  (error 'invalid-configuration
				 :reason (format nil "Could not use compiler ~S"
								 common-name)))))))

(defun apply-compiler-from-opts (proj opts)
  (let* ((compiler-name (gethash 'compiler-impl opts))
		 (impl (gethash compiler-name *compiler-impls*)))
	(unless impl
	  (error 'invalid-configuration
			 :reason (format nil "Not compatible with compiler ~S"
							 compiler-name)))
	(setf impl (copy-structure impl))
	(multiple-value-bind (path version)
		(%find-compiler-exe impl opts)
	  (setf (compiler-path impl) path
			(compiler-version impl) version))
	(init-with-cli-options impl proj opts)
	(setf (project-config-compiler proj) impl)))

;; (define-compiler (ccl-compiler "ccl"))
