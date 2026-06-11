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

(define-condition package-source-error ()
  ((reason :initarg :reason :reader package-source-error-reason)))

(define-condition package-source-fetch-error (package-source-error)
  ())

(defvar *package-sources* (make-hash-table :test 'equal))

(defun get-package-source-opts ()
  (let ((source-opts nil)
		(valid-source-keys nil))
	(loop :for k :being :the :hash-key
			:using (hash-value s) :of *package-sources*
		  do (push (get-cli-options s) source-opts)
			 (push k valid-source-keys))
	(cons
	 (adopt:make-option
	  'package-source-type
	  :parameter "SOURCE"
	  :long "package-source"
	  :initial-value "ocicl"
	  :short #\s
	  :help (format nil "Method by which to fetch ASDF systems not found locally.
Valid options are~{ ~A~}" valid-source-keys)
	  :reduce (lambda (prev new)
				(declare (ignore prev))
						 new))
	 source-opts)))

(defun apply-package-source-from-opts (proj opts)
  (let* ((source-name (gethash 'package-source-type opts))
		 (pkg-source (gethash source-name *package-sources*)))
	(unless pkg-source
	  (error 'package-source-error
			 :reason (format nil "No package source named ~S avaiable"
							 source-name)))
	;; TODO: Detect if the chosen source won't work and maybe
	;; fallback to another option:
	(apply-cli-options pkg-source opts)
	(with-accessors ((proj-source project-config-package-source)
					 (proj-registry project-config-source-registry))
		proj
	  (setf proj-source pkg-source
			proj-registry (append
						   (dependency-source-registry pkg-source proj)
						   proj-registry)))))


(defun %ensure-dependencies (source proj dependencies visited)
  (let ((missing nil))
	(dolist (d dependencies)
	  (setf (gethash d visited) t)
	  (let ((sys (asdf:find-system d)))
		(if sys
			(dolist (sub (asdf:system-depends-on sys))
			  (when (not (or (gethash sub visited) (asdf:find-system sub)))
				(push sub missing)))
			(push d missing))))
	(when missing
	  (install-dependencies source proj missing)
	  (%ensure-dependencies source proj missing visited))))

(defun ensure-dependencies (proj dependencies)
  (let ((visited (make-hash-table)))
	(%ensure-dependencies (project-config-package-source proj)
						  proj dependencies visited)))

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
