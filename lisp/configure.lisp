(in-package #:static-build)

(defstruct (feature-spec
			(:constructor make-feature-spec (feature default)))
  (feature nil :type symbol :read-only t)
  (default nil :type boolean :read-only t)
  (enabled default :type boolean))

(defstruct project-config
  (system nil :type asdf:system :read-only t)
  (exec-system nil :type (or null asdf:system) :read-only t)
  (test-system nil :type (or null asdf:system) :read-only t)
  ;; The file that defines the build:
  (build-file nil :type pathname :read-only t)
  ;; The directory that the systems and relative paths get
  ;; resolved against:
  (base-path nil :type pathname :read-only t)
  (package-source nil)
  ;; Where build artifacts get placed:
  (build-dir nil :type pathname)
  ;; Information on where to find other ASDF systems:
  (source-registry nil :type list)
  ;; Optimization settings
  (optimization nil :type list)
  ;; symbols push to *FEATURES*; see FEATURE-SPEC
  (features nil :type list))

(defun project-asdf-cache (proj)
  (declare (type project-config proj))
  (merge-pathnames "asdf-cache/" (project-config-build-dir proj)))

(defun %compute-max-len (features &key (key #'identity))
  (let ((len 0))
	(dolist (spec features)
	  (let* ((var (funcall key spec))
			 (new-len (length var)))
		(setf len (max len new-len))))
	len))

(defun %print-features-summary (features stream)
  (format stream "~%~%~2TFeatures:")
  (flet ((extract-feature-str (x)
		   (format nil "~S"
				   (feature-spec-feature x))))
	(let ((var-len (%compute-max-len features
									 :key #'extract-feature-str)))
	  (dolist (spec features)
		(declare (type feature-spec spec))
		(format stream "~%~4T~VS : ~A~@[*~]"
				var-len
				(feature-spec-feature spec)
				(feature-spec-enabled spec)
				(not (eql (feature-spec-default spec)
							 (feature-spec-enabled spec))))))))

(defun print-summary (project &optional (stream *standard-output*))
  (declare (type project-config project))
  (with-accessors ((system project-config-system)
				   (exec-system project-config-exec-system)
				   (test-system project-config-test-system)
				   (source-registry project-config-source-registry)
				   (features project-config-features)
				   (build-dir project-config-build-dir))
	  project
	(format stream "~%Project Summary:")
	(format stream "~%~2TMain System:    ~A" system)
	(format stream "~%~2TExec System:    ~A" exec-system)
	(format stream "~%~2TTest System:    ~A" test-system)
	(format stream "~%~2TBuild Location: ~A" build-dir)
	(when features
	  (%print-features-summary features stream))
	(format stream "~%~%~2TSystem search paths: ~{~%~4T~A~}"
			(reverse source-registry)))
  (format stream "~%"))


(define-condition invalid-configuration ()
  ((reason :initarg :reason :reader invalid-configuration-reason))
  (:report (lambda (condition stream)
			 (format stream "Invalid configuration: ~S"
					 (invalid-configuration-reason condition)))))

(defun cur-directory ()
  (let* ((p (or *load-truename* *compile-file-truename*))
		 (dir (pathname-directory p)))
	(make-pathname :directory dir)))

(defun %construct-relative-directory (base pathname)
  (if (%relative-directory-p pathname)
	  (uiop:merge-pathnames* pathname (etypecase base
								  (project-config (project-config-base-path base))
								  ((or string pathname)
								   base)))
	  pathname))

(defun %init-exec-project (system test-system exec-system base-path build-file build-directory
						   &aux (base-asdf-location (list :directory base-path)))
  (asdf:initialize-source-registry
   (list :source-registry
		 base-asdf-location
		 :inherit-configuration))
  (let ((system (asdf:find-system system))
		(test-system (if test-system
						 (asdf:find-system test-system)
						 nil))
		(exec-system (if exec-system
						 (asdf:find-system exec-system)
						 nil)))
	(make-project-config
	 :build-file build-file
	 :build-dir (%construct-relative-directory base-path build-directory)
	 :source-registry (list base-asdf-location)
	 :system system
	 :test-system test-system
	 :exec-system exec-system
	 :base-path base-path)))

(defmacro init-exec-project (system &key test-system
									  exec-system
										(base-path (cur-directory))
										(build-directory #p"build/"))
  "Initialize the ASDF build environment and return a project object.
Args:
  SYSTEM: the name of the primary ASDF for this project
  TEST-SYSTEM: The test system for this project if it is present
  EXEC-SYSTEM: The system that contains the executable definition
  BASE-PATH: The root directory of the project and the presumed location
     of the system definitions
  BUILD-DIRECTORY: The directory to place the build artifacts"
  (let ((sys (gensym "sys"))
		(test-sys (gensym "test-sys"))
		(exec-sys (gensym "exec-sys"))
		(base (gensym "base"))
		(build-dir (gensym "build-dir")))
	`(let ((,sys ,system)
		   (,test-sys ,test-system)
		   (,exec-sys ,exec-system)
		   (,base ,base-path)
		   (,build-dir ,build-directory))
	   (%init-exec-project ,sys ,test-sys ,exec-sys ,base
						   ,(uiop:current-lisp-file-pathname)
						   ,build-dir))))

(defmacro with-project (project-var
						(system &key test-system
								  exec-system
								  (base-path (cur-directory))
								  (build-directory #p"build/"))
						&body body)
  `(let ((,project-var (init-exec-project ,system
										  :test-system ,test-system
										  :exec-system ,exec-system
										 :base-path ,base-path
										 :build-directory ,build-directory)))
	(handler-case
		(progn
		  ,@body)
	  (invalid-configuration (c)
		(format *error-output* "Error: Configuration step failed: ~A~%"
				(invalid-configuration-reason c))
		(uiop:quit 1)))))

(defun %add-features (project feature-specs)
  (declare (type project-config project))
  (dolist (f feature-specs)
	(let ((spec (if (listp f)
					(destructuring-bind (f-symb &key default) f
					  (make-feature-spec f-symb default))
					(make-feature-spec f nil))))
	  (pushnew spec (project-config-features project)))))

(defmacro add-features (project &body feature-specs)
  `(%add-features ,project (quote ,feature-specs)))

(defun %relative-directory-p (pathname)
  (let ((directory (pathname-directory pathname)))
	(if (and (not (null directory))
			 (listp directory)
			 (not (pathname-name pathname)))
        (eq (car directory) :relative)
		(error 'invalid-configuration
			   :reason (format nil "~S is not a directory.
Ensure there is a ~A character at the end of directory names."
							   pathname
							   (uiop:directory-separator-for-host))))))

(defun add-vendor-directories (project &rest directories)
  (declare (type project-config project))
  (dolist (d directories)
	(pushnew (list :directory (%construct-relative-directory project d))
			 (project-config-source-registry project))))

(defun add-vendor-trees (project &rest directories)
  (declare (type project-config project))
  (dolist (d directories)
	(pushnew (list :tree (%construct-relative-directory project d))
			 (project-config-source-registry project))))

(defun set-optimization (project &rest args &key speed safety debug)
  (declare (ignore speed safety debug))
  (setf (project-config-optimization project)
		`(optimize ,@(loop for (type level) on args
								   by #'cddr
							  collect (list (find-symbol (symbol-name type)) level)))))
