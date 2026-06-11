(in-package #:static-build)

(defgeneric install-dependencies (source project dependencies)
  (:documentation "Install the given dependencies using the given
package source."))

(defgeneric dependency-source-registry (source project)
  (:documentation "Return a list of source registry specs that this package
source will place the dependencies in"))

(defgeneric get-cli-options (source)
  (:documentation "Return the CLI options group for this package source")
  (:method (source)
	(list)))

(defgeneric apply-cli-options (source opts)
  (:documentation "Apply the given CLI options to this package source")
  (:method (source opts)))

(defgeneric package-source-available-p (source)
  (:documentation "Check if the given package source is usable")
  (:method (source opts )
	t))

(define-condition package-source-error ()
  ((reason :initarg :reason :reader package-source-error-reason)))

(define-condition package-source-fetch-error (package-source-error)
  ())

(defvar *package-sources* (make-hash-table :test 'equal))

(defmacro define-pkg-source ((name designator)
							 direct-superclasses
							 direct-slots
							 &body options)
  `(progn
	 (defclass ,name ,direct-superclasses
	   ,direct-slots
	   ,@options)
	 (setf (gethash ,designator *package-sources*)
		   (make-instance (quote ,name)))))

(defun get-package-source-opts ()
  (let ((source-opts nil)
		(valid-source-keys nil))
	(loop :for k :being :the :hash-key
			:using (hash-value s) :of *package-sources*
		  do (when (package-source-available-p s)
			   (push (get-cli-options s) source-opts))
			 (push k valid-source-keys))
	(cons
	 (adopt:make-option
	  'package-source-type
	  :parameter "SOURCE"
	  :long "package-source"
	  :short #\s
	  :help (format nil "Method by which to fetch ASDF systems not found locally.
Valid options are~{ ~A~}" valid-source-keys)
	  :reduce (lambda (prev new)
				(declare (ignore prev))
						 new))
	 source-opts)))

(defun apply-package-source-from-opts (proj opts)
  (let ((source-name (gethash 'package-source-type opts)))
	(unless source-name
	  (setf source-name "ocicl"))
	(let ((pkg-source (gethash source-name *package-sources*)))
	  (unless pkg-source
		(error 'package-source-error
			   :reason (format nil "No package source named ~S avaiable"
							   source-name)))
	  ;; TODO: Maybe fallback to another option if the option isn't available?
	  (unless (package-source-available-p pkg-source)
		(error 'package-source-error
			   :reason "System missing required dependencies for package source ~S."
			   source-name))
	  (apply-cli-options pkg-source opts)
	  (with-accessors ((proj-source project-config-package-source)
					   (proj-registry project-config-source-registry))
		  proj
		(setf proj-source pkg-source
			  proj-registry (append
							 (dependency-source-registry pkg-source proj)
							   proj-registry))))))


(defmacro with-env-values (value-spec &body body)
  (let ((vars (mapcar (lambda (x)
						(cons (gensym (car x)) x))
					  value-spec))
		(val-or-blank (gensym "val-or-blank")))
	`(let (,@(mapcar (lambda (x)
					   (list (car x) `(uiop:getenv ,(second x))))
					 vars))
	   (setf ,@(loop for v in vars
					 append (list `(uiop:getenv ,(second v)) (third v))))
	   ,@body
	   (flet ((,val-or-blank (val)
				(if val val "")))
		 (setf ,@(loop for v in vars
					   append (list `(uiop:getenv ,(second v)) `(,val-or-blank ,(car v)))))))))
