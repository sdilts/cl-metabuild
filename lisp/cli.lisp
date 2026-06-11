(in-package #:static-build)

(defun %build-feature-group (proj)
  (let ((feature-options nil))
	(dolist (spec (exec-project-features proj))
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

(defun %build-cmd-line-parser (proj)
  (let ((help-option (adopt:make-option
					  'help
					  :long "help"
					  :short #\h
					  :help "Display help and exit"
					  :reduce (constantly t)))
		(feature-group (%build-feature-group proj)))
	(adopt:make-interface
	 :name (format nil "Static Build" (exec-project-system proj))
	 :summary (format nil "Configure build options for ~S"
					  (exec-project-system proj))
	 :usage "[OPTIONS]"
	 :help "Specify build options ..."
	 :contents (list help-option
					 feature-group))))

(defun process-command-line-args (proj)
  (let ((parser (%build-cmd-line-parser proj)))
	(multiple-value-bind (pos opts)
		(adopt:parse-options parser)
	  (when (gethash 'help opts)
		(adopt:print-help-and-exit parser))
	  (dolist (f (exec-project-features proj))
		(declare (type feature-spec f))
		(multiple-value-bind (arg present)
			(gethash (feature-spec-feature f) opts)
		  (when present
			(setf (feature-spec-enabled f) arg)))))))
