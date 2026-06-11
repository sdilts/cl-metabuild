(in-package #:static-build)

(defclass ocicl-source ()
  ())

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

(setf (gethash "ocicl" *package-sources*)
	  (make-instance 'ocicl-source))
