(in-package #:static-build)

(define-pkg-source (ocicl-source "ocicl") ()
  ())

(defmethod package-source-available-p ((source ocicl-source))
  (let (
		#+unix
		(find-command (list "which" "ocicl"))
		#+windows
		(find-command (list "where" "ocicl")))
  (multiple-value-bind (output err-output code)
	  (uiop:run-program find-command :ignore-error-status t)
	(zerop code))))

(defmethod install-dependencies ((source ocicl-source) project dependencies)
  (uiop:with-current-directory ((project-config-base-path project))
	(with-env-values (("OCICL_LOCAL_ONLY" "1"))
	  (let ((cmd (append (list "ocicl" "install") dependencies)))
		(format *standard-output* "Running~{ ~S~}~%" cmd)
		(finish-output *standard-output*)
		(handler-case
			(uiop:run-program cmd
							  :output :interactive)
		  (uiop/run-program:subprocess-error (c)
			(error 'package-source-fetch-error
				   :reason (format nil "ocicl execution failed with code ~A"
								   (uiop/run-program:subprocess-error-code c)))))))))

(defmethod dependency-source-registry ((source ocicl-source) project)
  (list `(:tree ,(merge-pathnames "ocicl/" (project-config-base-path project)))))
