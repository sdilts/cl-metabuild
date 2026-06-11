(in-package #:static-build)

(defstruct (feature-spec
			(:constructor make-feature-spec (feature default)))
  (feature nil :type symbol :read-only t)
  (default nil :type boolean :read-only t)
  (enabled default :type boolean))

(defstruct exec-project
  (system nil :type asdf:system :read-only t)
  (exec-system nil :type (or null asdf:system) :read-only t)
  (test-system nil :type (or null asdf:system) :read-only t)
  (build-file nil :type pathname)
  (build-dir nil :type pathname)
  (base-path nil :type pathname)
  (source-registry nil :type list)
  (optimization nil :type list)
  (features nil :type list))

(defun project-asdf-cache (proj)
  (declare (type exec-project proj))
  (merge-pathnames "asdf-cache/" (exec-project-build-dir proj)))

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
  (declare (type exec-project project))
  (with-accessors ((system exec-project-system)
				   (exec-system exec-project-exec-system)
				   (test-system exec-project-test-system)
				   (source-registry exec-project-source-registry)
				   (features exec-project-features)
				   (build-dir exec-project-build-dir))
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
	  (merge-pathnames pathname (etypecase base
								  (exec-project (exec-project-base-path base))
								  ((or string pathname)
								   base)))
	  pathname))

(defun %init-exec-project (system test-system exec-system base-path build-file build-directory)
  (asdf:initialize-source-registry
   (list :source-registry
		 (list :directory base-path)
		 :ignore-inherited-configuration))
  (let ((system (asdf:find-system system))
		(test-system (if test-system
						 (asdf:find-system test-system)
						 nil))
		(exec-system (if exec-system
						 (asdf:find-system exec-system)
						 nil)))
	(make-exec-project
	 :build-file build-file
	 :build-dir (%construct-relative-directory base-path build-directory)
	 :source-registry (list
					   (list :directory (asdf:system-source-directory system)))
	 :system system
	 :test-system test-system
	 :exec-system exec-system
	 :base-path base-path)))

(defmacro init-exec-project (system &key test-system
									  exec-system
										(base-path (cur-directory))
										(build-directory #p"build/"))
  "Initialize the ASDF build environment and return a project object."
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
								  (base-path (cur-directory))
								  (build-directory #p"build/"))
						&body body)
  `(let ((,project-var (init-exec-project ,system
										 :test-system ,test-system
										 :base-path ,base-path
										 :build-directory ,build-directory)))
	(handler-case
		(progn
		  ,@body)
	  (invalid-configuration (c)
		(format *error-output* "Error: Configuration step failed: ~A"
				(invalid-configuration-reason c))
		(uiop:quit 1)))))

(defun %add-features (project feature-specs)
  (declare (type exec-project project))
  (dolist (f feature-specs)
	(let ((spec (if (listp f)
					(destructuring-bind (f-symb &key default) f
					  (make-feature-spec f-symb default))
					(make-feature-spec f nil))))
	  (pushnew spec (exec-project-features project)))))

(defmacro add-features (project &body feature-specs)
  `(%add-features ,project (quote ,feature-specs)))

(defun %relative-directory-p (pathname)
  (let ((directory (pathname-directory pathname)))
	(if (and (not (null directory)) (listp directory))
        (eq (car directory) :relative)
		(error 'invalid-configuration :reason (format nil "~S is not a directory."
													 pathname)))))

(defun add-system-directories (project &rest directories)
  (declare (type exec-project project))
  (dolist (d directories)
	(pushnew (list :directory (%construct-relative-directory project d))
			 (exec-project-source-registry project))))

(defun add-system-trees (project &rest directories)
  (declare (type exec-project project))
  (dolist (d directories)
	(pushnew (list :tree (%construct-relative-directory project d))
			 (exec-project-source-registry project))))

(defun set-optimization (project &rest args &key speed safety debug)
  (declare (ignore speed safety debug))
  (setf (exec-project-optimization project)
		`(optimize ,@(loop for (type level) on args
								   by #'cddr
							  collect (list (find-symbol (symbol-name type)) level)))))
