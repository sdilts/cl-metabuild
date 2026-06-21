(in-package #:static-build)

(defun %print-file-header (proj file-source stream)
  (declare (type project-config proj)
		   (type stream stream))
  (format stream ";; This file was generated for the system ~S."
		  (asdf:component-name (project-config-system proj)))
  (format stream "~%;; Edit the build file at ~A~%;; instead of changing this file."
		  file-source)
  (format stream "~%;;~%;; Creation Date: ~A" (local-time:format-timestring nil (local-time:now))))

(defun %insert-declarations (proj stream)
  (declare (type project-config proj)
		   (type stream stream))
  (when (project-config-optimization proj)
	(format stream  "~%")
	(pprint `(declaim ,(project-config-optimization proj))
			stream)))

(defun %generate-features-insert (proj stream)
  (declare (type project-config proj))
  (let ((forms (loop for f in (project-config-features proj)
					 append (when (feature-spec-enabled f)
							  (list `(cl:pushnew ,(feature-spec-feature f)
												 *features*))))))
	(format stream "~%~%;; Enabled features:")
	(pprint `(progn ,@forms) stream)))

(defun %build-source-registry-param (proj)
  `(:source-registry
		   ,@(reverse (project-config-source-registry proj))
				   :ignore-inherited-configuration))

(defun %generate-asdf-config (proj source-registry-param stream)
  (declare (type project-config proj))
  (let ((output-translations
		  `(quote (:output-translations
				   :inherit-configuration
				   (,(namestring (project-config-base-path proj))
					,(namestring (project-asdf-cache proj)))))))
	(format stream "~%~%;; Isolate where ASDF searches for systems")
	(pprint (list 'asdf:initialize-source-registry
				  (list 'quote source-registry-param))
			stream)
	(format stream "~%~%;; Place the compilation results from files")
	(format stream "~%;; in this project in the build directory")
	(pprint (list 'asdf:initialize-output-translations
				  output-translations)
			stream)))


(defun generate-init-env (proj source-registry)
  "Generate the init-build-env.lisp file that initializes the
features and ASDF environment"
  (declare (type project-config proj))
  (let ((path (make-pathname
			   :directory (pathname-directory (project-config-build-dir proj))
			   :name "init-build-env"
			   :type "lisp")))

	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (%print-file-header proj (project-config-build-file proj) stream)
	  (pprint `(require "asdf") stream)
	  (%insert-declarations proj stream)
	  (%generate-features-insert proj stream)
	  (%generate-asdf-config proj source-registry stream)
	  (format stream "~&"))
	path))

(defun generate-build-exec-script (proj init-path)
  (declare (type project-config proj))
  (let ((path (make-pathname
			   :directory (pathname-directory (project-config-build-dir proj))
			   :name "build"
			   :type "lisp")))
	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (with-accessors ((build-file project-config-build-file)
					   (exec-sys project-config-exec-system)
					   (sys project-config-system))
		  proj
		(%print-file-header proj (project-config-build-file proj) stream)
		(pprint `(load ,init-path)
				stream)
		(pprint (list 'asdf:make (asdf:component-name
								  (if exec-sys
									  exec-sys
									  sys)))
				stream)
		(format stream "~&")))))

(defun finish-configure (project)
  (let ((parser (build-cmd-line-parser project)))
	(multiple-value-bind (pos opts)
		(adopt:parse-options parser)
	  (declare (ignore pos))
	  (apply-command-line-opts parser opts project)))
  (let ((source-registry-param (%build-source-registry-param project)))
	(download-dependencies project source-registry-param)
	(print-summary project)
	(format *error-output* "~%Generating output files...")
	(finish-output *error-output*)
	(ensure-directories-exist (project-config-build-dir project))
	(let ((init-file-path (generate-init-env project source-registry-param)))
	  (generate-build-exec-script project init-file-path))
	(format *error-output* "~%Done! You can now build the project.~%")))
