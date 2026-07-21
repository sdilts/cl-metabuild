(in-package #:metabuild)

#+quicklisp
(define-pkg-source (quicklisp-source "quicklisp")
  (home nil :type (or null pathname))
  (dist-dir nil :type (or null pathname)))

#+quicklisp
(defun %get-systems (tree table)
  (cond ((atom tree)
		 (when tree
		   (setf (gethash tree table) t)))
		(t (%get-systems (car tree) table)
		   (%get-systems (cdr tree) table))))

#+quicklisp
(defmethod install-dependencies ((source quicklisp-source) project dependencies)
  (declare (ignore project)
		   (optimize (debug 3)))
  (let ((required (make-hash-table)))
	(dolist (d dependencies)
	  (%get-systems (ql-dist:dependency-tree d) required))
	(format t "~&Required systems:~%~1T~{ ~S~:_~}~%"
			(loop for k being the hash-keys of required
				  collect k))
	(finish-output)
	(loop for k being the hash-keys of required
		  do (ql-dist:ensure-installed k))))

#+quicklisp
(defmethod dependency-source-registry ((source quicklisp-source))
  (list `(:tree ,(quicklisp-source-dist-dir source))))

#+quicklisp
(defmethod system-from-source-p ((source quicklisp-source) system)
  (let ((dist-path (quicklisp-source-dist-dir source)))
	(pathname-under-p (asdf:system-source-directory system)
					  dist-path)))

#+quicklisp
(defmethod package-source-equals ((a quicklisp-source) (b quicklisp-source))
  (with-accessors ((a-dist quicklisp-source-dist-dir)
				   (a-home quicklisp-source-home))
	  a
	(with-accessors ((b-dist quicklisp-source-dist-dir)
					 (b-home quicklisp-source-home))
		b
	  (and (equalp a-dist b-dist)
		   (equalp a-home b-home)))))

#+quicklisp
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

#+quicklisp
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

#+quicklisp
(defmethod init-with-cli-options ((source quicklisp-source) project opts)
  (let ((ql-home (gethash 'quicklisp-home opts)))
	(validate-ql-install ql-home)
	(setf (quicklisp-source-home source) ql-home
		  (quicklisp-source-dist-dir source)
		  (merge-pathnames "dists/"
						   (quicklisp-source-home source)))))

#+quicklisp
(defmethod setup-package-source ((source quicklisp-source) project)
  ;; Nothing to do here right now
  )
