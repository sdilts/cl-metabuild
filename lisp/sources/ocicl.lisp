(in-package #:metabuild)

(define-pkg-source (ocicl-source "ocicl")
  (dir nil))

(defmethod package-source-available-p ((source ocicl-source))
  (program-availabe-p "ocicl"))

(defun invoke-ocicl-install (proj dependencies)
  (uiop:with-current-directory ((project-config-base-path proj))
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

(defmethod install-dependencies ((source ocicl-source) project dependencies)
  (invoke-ocicl-install project dependencies))
  ;; (let ((visited (make-hash-table)))
  ;; 	(%ensure-dependencies (project-config-package-source project)
  ;; 						  project dependencies visited)))

(defmethod dependency-source-registry ((source ocicl-source))
  (list `(:tree  ,(ocicl-source-dir source))))

(defmethod system-from-source-p ((source ocicl-source) system)
  (let ((dist-path (ocicl-source-dir source)))
	(when (probe-file dist-path)
	  (pathname-under-p (asdf:system-source-directory system)
						dist-path))))

(defmethod init-with-cli-options ((source ocicl-source) project opts)
  (setf (ocicl-source-dir source)
		(merge-pathnames "ocicl/" (project-config-base-path project))))
