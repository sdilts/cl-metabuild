(in-package #:metabuild)

(defun %build-feature-group (proj)
  (let ((feature-options nil))
	(dolist (spec (project-config-features proj))
	  (declare (type feature-spec spec))
	  (with-accessors ((name feature-spec-feature)
					   (default feature-spec-enabled))
		  spec
		(let ((symb-name (if (find-symbol (symbol-name name) :keyword)
							  (symbol-name name)
							  (format nil "~S" name))))
		  (push (adopt:make-option
				 name
				 :parameter "y-or-n"
				 :long (concatenate 'string "with-" symb-name)
				 :help (format nil "Include ~S in *FEATURES*" name)
				 :initial-value default
				 :reduce (lambda (prev new)
						   (declare (ignore prev))
						   (cond
							 ((member new '("y" "yes" "t") :test #'string=)
							  t)
							 ((member new '("n" "no" "nil") :test #'string=)
							  nil)
							 (t t))))
				feature-options))))
	(adopt:make-group 'features
					  :title "Enable Features"
					  :options feature-options)))

(defun build-cmd-line-parser (proj)
  (let ((help-option (adopt:make-option
					  'help
					  :long "help"
					  :short #\h
					  :help "Display help and exit"
					  :reduce (constantly t)))
		(build-dir-option (adopt:make-option
					   'build-dir
					   :parameter "PATH"
					   :long "build-directory"
					   :short #\o
					   :help "Build directory location."
					   :reduce (lambda (prev new)
								 (declare (ignore prev))
								 new)))
		(state-group (adopt:make-option
					  'reuse-state
					  :parameter "PATH"
					  :long "state"
					  ;; :hidden t
					  :help "Reuse state from previous build"
					  :reduce (lambda (prev new)
							   (declare (ignore prev))
							   new)))
		(feature-group (%build-feature-group proj)))
	(adopt:make-interface
	 :name (format nil "Static Builder")
	 :summary (format nil "Configure build options for ~S"
					  (project-config-system proj))
	 :usage "[OPTIONS]"
	 :help "Specify build options ..."
	 :contents (append (list help-option
							 build-dir-option
							 feature-group
							 state-group)
					   (get-package-source-opts)
					   (get-compiler-opts)))))

(defun apply-command-line-opts (parser opts proj)
  (declare (type hash-table opts)
		   (type project-config proj))
  (when (gethash 'help opts)
	(adopt:print-help-and-exit parser))
  (let ((p (gethash 'build-dir opts)))
	(when p
	  (setf (project-config-build-dir proj)
			(%construct-relative-directory (uiop:getcwd)
										   (uiop:parse-native-namestring p)))))
  (apply-package-source-from-opts proj opts)
  (apply-compiler-from-opts proj opts)
  (dolist (f (project-config-features proj))
	(declare (type feature-spec f))
	(multiple-value-bind (arg present)
		(gethash (feature-spec-feature f) opts)
	  (when present
		(setf (feature-spec-enabled f) arg))))
  (let ((reuse-state (gethash 'reuse-state opts)))
	(when reuse-state
		(read-build-state reuse-state))))
