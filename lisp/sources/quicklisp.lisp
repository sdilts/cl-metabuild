(in-package #:static-build)

(define-pkg-source (quicklisp-source "quicklisp") ()
  ((home :type (or null pathname) :initform nil :accessor quicklisp-source-home)))

(defun %get-systems (tree table)
  (cond ((atom tree)
		 (when tree
		   (setf (gethash tree table) t)))
		(t (%get-systems (car tree) table)
		   (%get-systems (cdr tree) table))))

(defmethod install-dependencies ((source quicklisp-source) project dependencies)
  (declare (ignore project)
		   (optimize (debug 3)))
  (let ((required (make-hash-table)))
	(dolist (d dependencies)
	  (setf (gethash (ql-dist:find-system "adopt") required) t)
	  (%get-systems (ql-dist:dependency-tree d) required))
	(format t "Required systems:~{ ~S~}~%"
			(loop for k being the hash-keys of required
				  collect k))
	(finish-output)
	(loop for k being the hash-keys of required
		  do (ql-dist:ensure-installed k))))

(defmethod dependency-source-registry ((source quicklisp-source) project)
  (declare (ignore project))
  (list `(:tree ,(merge-pathnames "dists/"
								  (quicklisp-source-home source)))))

(defmethod get-cli-options ((source quicklisp-source))
  (let ((home-option (adopt:make-option
					  'quicklisp-home
					  :parameter "DIR"
					  :initial-value (merge-pathnames "quicklisp/"
													  (user-homedir-pathname))
					  :long "quicklisp-home"
					  :help "Home of quicklisp installation"
					  :reduce (lambda (prev new)
								(declare (ignore prev))
								new))))
	(adopt:make-group
	 'quicklisp-opts
	 :title "Options for Quicklisp package Source"
	 :options (list home-option))))

(defun validate-ql-install (ql-home)
  (declare (type pathname ql-home))
  (unless (probe-file ql-home)
	(error 'package-source-available-error
		   :reason (format nil
						   "Specified quicklisp home directory ~S does not exist"
						   ql-home)))
  (with-open-file (s (merge-pathnames "quicklisp/version.txt"
									   ql-home))
	(let ((desired-version (uiop:slurp-stream-string s :stripped t))
		  (loaded-version (ql:client-version)))
	  (unless (string= desired-version loaded-version)
		 (error 'package-source-available-error
			 :reason (format nil "Quicklisp versions do not match (loaded ~A) (specified ~A)"
							 loaded-version desired-version))))))

(defmethod apply-cli-options ((source quicklisp-source) opts)
  (let ((ql-home (gethash 'quicklisp-home opts)))
	(validate-ql-install ql-home)
	(setf (quicklisp-source-home source) ql-home)))
