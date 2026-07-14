(in-package #:metabuild)

(defgeneric install-dependencies (source project dependencies)
  (:documentation "Install the given dependencies using the given
package source."))

(defgeneric dependency-source-registry (source)
  (:documentation "Return a list of source registry specs that this package
source will place the dependencies in"))

(defgeneric get-cli-options (source)
  (:documentation "Return the CLI options group for this package source")
  (:method (source)
	(list)))

(defgeneric init-with-cli-options (source project opts)
  (:documentation "Apply the given CLI options to this package source")
  (:method (source project opts)))

(defgeneric package-source-available-p (source)
  (:documentation "Check if the given package source is usable")
  (:method (source)
	t))

(defgeneric system-from-source-p (source system)
  (:documentation "Return T if the given system is from this package source"))

(defgeneric package-source-equals (a b)
  (:documentation "Checks to see if two package sources are the same"))

(define-condition package-source-error ()
  ((reason :initarg :reason :reader package-source-error-reason)))

(define-condition package-source-fetch-error (package-source-error)
  ())

(defvar *package-sources* (make-hash-table :test 'equal))

(defstruct package-source
  (name nil :type string))

(defmacro define-pkg-source ((name designator)
							 &body direct-slots)
  (let ((ds (gensym "designator"))
		(constructor-name (intern (string-upcase
								   (concatenate 'string
												"make-"
												(symbol-name name))))))
	`(eval-when (:compile-toplevel :load-toplevel :execute)
	   (let ((,ds ,designator))
		 (defstruct (,name (:include package-source))
		   ,@direct-slots)
		 (setf (gethash ,ds *package-sources*)
			   (,constructor-name :name ,ds))))))

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
	  (setf source-name "quicklisp"))
	(let ((pkg-source (gethash source-name *package-sources*)))
	  (unless pkg-source
		(error 'package-source-error
			   :reason (format nil "No package source named ~S avaiable"
							   source-name)))
	  ;; TODO: Maybe fallback to another option if the option isn't available?
	  (unless (package-source-available-p pkg-source)
		(error 'package-source-error
			   :reason (format nil
							   "System missing required dependencies for package source ~S."
							   source-name)))
	  (setf pkg-source (copy-structure pkg-source))
	  (init-with-cli-options pkg-source proj opts)
	  (with-accessors ((proj-source project-config-package-source)
					   (proj-registry project-config-source-registry))
		  proj
		(setf proj-source pkg-source
			  proj-registry (append
							 (dependency-source-registry pkg-source)
							 proj-registry))))))

(defmacro with-missing-dependency-fetcher ((project source-registry-param
											&key purpose)
										   &body body)
  (let ((handle-missing-dependency (gensym "handle-missing-dependency"))
		(registry-param (gensym "registry-param"))
		(log-str (if purpose
					 (format nil "~~&Missing dependency for ~A: ~~S~~%"
							 purpose)
					 "~&Missing dependency: ~S~%")))
	`(let ((,registry-param ,source-registry-param))
	   (flet ((,handle-missing-dependency (c)
				(let ((missing-req (asdf/find-component:missing-requires c)))
				  (finish-output *error-output*)
				  (finish-output)
				  (format *error-output* ,log-str
						  missing-req)
				  (finish-output *error-output*)
				  (install-dependencies
				   (project-config-package-source ,project)
				   ,project
				   (list missing-req))
				  ;; ASDF won't find the new package unless the source
				  ;; registry is reset:
				  (asdf:initialize-source-registry ,registry-param)
				  (invoke-restart 'asdf:retry))))
		 ;; We could just add something to
		 ;; asdf:*system-definition-search-functions*
		 ;; instead of this, but I'm less
		 ;; confident of the results. Maybe it would be faster?
		 (handler-bind ((asdf:missing-dependency
						  (function ,handle-missing-dependency)))
		   ,@body)))))

(defun %find-sys (project source-registry-param system-name)
  (with-missing-dependency-fetcher (project source-registry-param
											:purpose "defsystem")
	(asdf:find-system system-name nil)))

(defun %find-missing-dependencies (project dependencies source-registry-param)
  (let ((pkg-src (project-config-package-source project))
		(missing nil)
		(vendored nil))
	(declare (optimize (debug 3)))
	(dolist (d dependencies)
	  (let ((sys (%find-sys project source-registry-param d)))
		(if sys
			(unless (system-from-source-p
					 pkg-src sys)
			  (push sys vendored))
			(push d missing))))
	(values missing vendored)))

(defun download-dependencies (project source-registry-param)
  (declare (type project-config project))
  ;; We need to clear this project's dependencies so they
  ;; aren't counted as present:
  (let ((cur-sys (asdf:find-system "cl-metabuild")))
	(dolist (d (asdf:system-depends-on cur-sys))
	  (asdf:clear-system d)))
  (format *error-output* "~%Checking project dependencies...~%")
  (asdf:initialize-source-registry source-registry-param)
  (let* ((dependencies (asdf:system-depends-on (project-config-system project))))
	(multiple-value-bind (missing vendored)
		(%find-missing-dependencies project dependencies source-registry-param)
	  (when vendored
		(format *error-output* "Checking dependencies of vendored systems:~%~1T~{ ~A~}~%"
				vendored)
		(dolist (v vendored)
		  (let ((v-deps (asdf:system-depends-on v)))
			(dolist (d v-deps)
			  (unless (%find-sys project source-registry-param d)
				(push d missing))))))
	  (when missing
		(format *error-output* "Missing systems:~%~1T~{ ~A~}~%"
				missing)
		(install-dependencies (project-config-package-source project)
							  project missing))
	  (format *error-output* "~&Dependency check done!~%")
	  (finish-output *error-output*)
	  vendored)))
