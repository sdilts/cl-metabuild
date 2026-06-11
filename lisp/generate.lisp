(in-package #:static-build)

(defun %print-file-header (proj file-source stream)
  (declare (type exec-project proj)
		   (type stream stream))
  (format stream ";; This file was generated for the system ~S."
		  (asdf:component-name (exec-project-system proj)))
  (format stream "~%;; Edit the build file at ~A~%;; instead of changing this file."
		  file-source)
  (format stream "~%;;~%;; Creation Date: ~A" (local-time:format-timestring nil (local-time:now))))

(defun %insert-declarations (proj stream)
  (when (exec-project-optimization proj)
	(format stream  "~%")
	(pprint `(declaim ,(exec-project-optimization proj))
			stream)))

(defun %generate-features-insert (proj stream)
  (let ((forms (loop for f in (exec-project-features proj)
					 append (when (feature-spec-enabled f)
							  (list `(cl:pushnew ,(feature-spec-feature f)
												 *features*))))))
	(format stream "~%~%;; Enabled features:")
	(pprint `(progn ,@forms) stream)))

(defun %generate-asdf-config (proj stream)
  (let ((source-registry-param
		  `(quote (:source-registry
			,@(reverse (exec-project-source-registry proj))
				   :ignore-inherited-configuration)))
		(output-translations
		  `(quote (:output-translations
				   :inherit-configuration
				   (,(namestring (exec-project-base-path proj))
					,(namestring (project-asdf-cache proj)))))))
	(format stream "~%~%;; Isolate where ASDF searches for systems")
	(pprint (list 'asdf:initialize-source-registry
				  source-registry-param)
			stream)
	(format stream "~%~%;; Place the compilation results from files")
	(format stream "~%;; in this project in the build directory")
	(pprint (list 'asdf:initialize-output-translations
				  output-translations)
			stream)))


(defun generate-init-env (proj)
  "Generate the init-build-env.lisp file that initializes the
features and ASDF environment"
  (declare (type exec-project proj))
  (let ((path (make-pathname
			   :directory (pathname-directory (exec-project-build-dir proj))
			   :name "init-build-env"
			   :type "lisp")))

	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (%print-file-header proj (exec-project-build-file proj) stream)
	  (pprint `(require "asdf") stream)
	  (%insert-declarations proj stream)
	  (%generate-features-insert proj stream)
	  (%generate-asdf-config proj stream)
	  (format stream "~&"))
	path))

(defun generate-build-exec-script (proj init-path)
  (declare (type exec-project proj))
  (let ((path (make-pathname
			   :directory (pathname-directory (exec-project-build-dir proj))
			   :name "build"
			   :type "lisp")))
	(with-open-file (stream path :direction :output :if-exists :supersede)
	  (with-accessors ((build-file exec-project-build-file)
					   (exec-sys exec-project-exec-system)
					   (sys exec-project-system))
		  proj
		(%print-file-header proj (exec-project-build-file proj) stream)
		(pprint `(load ,init-path)
				stream)
		(pprint (list 'asdf:make (asdf:component-name
								  (if exec-sys
									  exec-sys
									  sys)))
				stream)
		(format stream "~&")))))


(defun finish-configure (project)
  (process-command-line-args project)
  (print-summary project)
  (format *error-output* "~%Generating output files...")
  (finish-output *error-output*)
  (ensure-directories-exist (exec-project-build-dir project))
  (let ((init-file-path (generate-init-env project)))
	(generate-build-exec-script project init-file-path))
  (format *error-output* "~%Done! You can build the project.~%"))
