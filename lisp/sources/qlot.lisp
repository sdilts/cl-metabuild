(in-package #:metabuild)

(define-pkg-source (qlot-source "qlot")
	(dir nil))

(defun invoke-qlot-install (proj dependencies)
  (uiop:with-current-directory ((project-config-base-path proj))
	(let ((cmd (append (list "qlot" "add") dependencies)))
	  (format *standard-output* "Running~{ ~A~}~%" cmd)
	  (finish-output *standard-output*)
	  (handler-case
		  (uiop:run-program cmd
							:output :interactive)
		(uiop/run-program:subprocess-error (c)
		  (finish-output)
		  (error 'package-source-fetch-error
				 :reason (format nil "qlot execution failed with code ~A"
								 (uiop/run-program:subprocess-error-code c))))))))

(defmethod install-dependencies ((source qlot-source) project dependencies)
  (dolist (d dependencies)
	(invoke-qlot-install project (list (if (symbolp d)
										   (string-downcase (symbol-name d))
										   d)))))

(defmethod dependency-source-registry ((source qlot-source))
  (list `(:tree ,(qlot-source-dir source))))

(defmethod system-from-source-p ((source qlot-source) system)
  (let ((dist-path (qlot-source-dir source)))
	(pathname-under-p (asdf:system-source-directory system)
					  dist-path)))

(defmethod init-with-cli-options ((source qlot-source) project opts)
  (declare (ignore opts))
  (setf (qlot-source-dir source)
		(merge-pathnames ".qlot/" (project-config-base-path project))))

(defmethod setup-package-source ((source qlot-source) project)
  (uiop:with-current-directory ((project-config-base-path project))
	(unless (probe-file (merge-pathnames "qlfile"
										 (project-config-base-path project)))
	  (uiop:run-program (list "qlot" "init") :output :interactive))
	(uiop:run-program (list "qlot" "install") :output :interactive)))

(defmethod package-source-available-p ((source qlot-source))
  #-qlot
  (program-availabe-p "qlot")
  #+qlot
  t)
